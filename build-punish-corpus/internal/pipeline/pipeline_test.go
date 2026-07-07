package pipeline

import (
	"context"
	"fmt"
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/progress"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/stockfish"
)

// fakeSev scores exactly one candidate move (e8e7, a legal black king move in
// the mini fixture's second slot: after 1.e4 e5 2.Nf3, black to move, book
// reply b8c6) as a severe blunder (300cp); everything else is a non-blunder
// (20cp, below the 150cp gate in the test's cfg).
type fakeSev struct{}

func (fakeSev) Severity(_ context.Context, _, _, cand string) (stockfish.EvalDrop, error) {
	if cand == "e8e7" {
		return stockfish.EvalDrop{Cp: 300}, nil
	}
	return stockfish.EvalDrop{Cp: 20}, nil
}

func (fakeSev) Refute(_ context.Context, _ string) (stockfish.Refutation, error) {
	return stockfish.Refutation{PV: []string{"d1h5"}, EvalAfterCp: 320}, nil
}

// fakePlaus only reports a plausibility signal for e8e7 (the intended
// blunder); every other candidate reports no signal at all, so processSlot
// drops it before it ever reaches Severity's fake gate.
type fakePlaus struct{}

func (fakePlaus) PerBand(_ context.Context, _, cand string) (map[string]float64, map[string]map[string]float64, error) {
	if cand == "e8e7" {
		return map[string]float64{"beginner": 0.3}, map[string]map[string]float64{"beginner": {"lichessFreq": 0.3}}, nil
	}
	return map[string]float64{}, nil, nil
}

type discard struct{}

func (discard) Write(p []byte) (int, error) { return len(p), nil }

func TestRun_ProducesBlunderForSevereMove(t *testing.T) {
	cfg := config.Default()
	cfg.OpeningsJSONPath = "testdata/mini-openings.json"
	cfg.Workers = 2
	cfg.MinEvalDropCp = 150

	c, err := Run(context.Background(), cfg, Deps{
		Sev: fakeSev{}, Plaus: fakePlaus{}, Progress: progress.New(discard{}),
	})
	if err != nil {
		t.Fatal(err)
	}

	found := false
	for _, pos := range c.Positions {
		for _, bl := range pos.Blunders {
			if bl.Move.UCI == "e8e7" && bl.EvalDropCp == 300 {
				found = true
			}
		}
	}
	if !found {
		t.Errorf("expected e8e7 blunder in corpus; positions=%d", len(c.Positions))
	}

	// Provenance metadata is config-derived (bands.All()'s union), not
	// dependent on Sev/Plaus, so it must be populated even in this
	// fake-backed run.
	wantNets := []string{"maia-1100", "maia-1300", "maia-1500", "maia-1700", "maia-1900"}
	if got := c.Provenance.MaiaNets; !equalStrings(got, wantNets) {
		t.Errorf("provenance maiaNets = %v, want %v", got, wantNets)
	}
	wantBuckets := []int{0, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2500}
	if got := c.Provenance.LichessBuckets; !equalInts(got, wantBuckets) {
		t.Errorf("provenance lichessBuckets = %v, want %v", got, wantBuckets)
	}
	if c.Provenance.SourceSeedVersion != 4 {
		t.Errorf("provenance sourceSeedVersion = %d, want 4", c.Provenance.SourceSeedVersion)
	}
}

// erroringSev fails Severity for every candidate, so Run's worker pool must
// surface that error rather than silently swallowing it — the bounded
// errgroup must actually propagate a per-slot failure back to the caller.
type erroringSev struct{}

func (erroringSev) Severity(_ context.Context, _, _, _ string) (stockfish.EvalDrop, error) {
	return stockfish.EvalDrop{}, errBoom
}
func (erroringSev) Refute(_ context.Context, _ string) (stockfish.Refutation, error) {
	return stockfish.Refutation{}, errBoom
}

var errBoom = fmt.Errorf("boom")

func TestRun_PropagatesSlotError(t *testing.T) {
	cfg := config.Default()
	cfg.OpeningsJSONPath = "testdata/mini-openings.json"
	cfg.Workers = 2
	cfg.MinEvalDropCp = 150

	_, err := Run(context.Background(), cfg, Deps{
		Sev: erroringSev{}, Plaus: fakePlaus{}, Progress: progress.New(discard{}),
	})
	if err == nil {
		t.Fatal("expected Run to propagate the Severity error, got nil")
	}
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func equalInts(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
