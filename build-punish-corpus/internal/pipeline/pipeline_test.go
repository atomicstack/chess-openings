package pipeline

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/chessx"
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
	cfg.StockfishVersion = "Stockfish 17"

	c, err := Run(context.Background(), cfg, Deps{
		Sev: fakeSev{}, Plaus: fakePlaus{}, Progress: progress.New(discard{}),
	})
	if err != nil {
		t.Fatal(err)
	}

	// Provenance.Stockfish is a direct pass-through of cfg.StockfishVersion
	// (pipeline.go's Run -> builder.SetProvenance). This is the task's core
	// deliverable: guard it against a future accidental edit that drops or
	// mangles the stamp on its way from config to the built corpus.
	if got := c.Provenance.Stockfish; got != "Stockfish 17" {
		t.Errorf("provenance stockfish = %q, want %q", got, "Stockfish 17")
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

// erroringSev fails Severity (and Refute) for every candidate with whatever
// err it's constructed with, so the same fake can drive both the skip case
// (a plain processing error) and the abort case (a context error) in the
// tests below.
type erroringSev struct{ err error }

func (e erroringSev) Severity(_ context.Context, _, _, _ string) (stockfish.EvalDrop, error) {
	return stockfish.EvalDrop{}, e.err
}
func (e erroringSev) Refute(_ context.Context, _ string) (stockfish.Refutation, error) {
	return stockfish.Refutation{}, e.err
}

var errBoom = fmt.Errorf("boom")

// TestRun_SkipsNonContextSlotError asserts the new skip+log behaviour: a
// plain (non-context) per-slot processing error must NOT abort the run. The
// failing slot (mini fixture's second slot, whose only plausible candidate is
// e8e7) is skipped — absent from the corpus — but Run still completes with a
// nil error, and the progress/skip bookkeeping doesn't otherwise disturb the
// rest of the batch.
func TestRun_SkipsNonContextSlotError(t *testing.T) {
	cfg := config.Default()
	cfg.OpeningsJSONPath = "testdata/mini-openings.json"
	cfg.Workers = 2
	cfg.MinEvalDropCp = 150

	c, err := Run(context.Background(), cfg, Deps{
		Sev: erroringSev{err: errBoom}, Plaus: fakePlaus{}, Progress: progress.New(discard{}),
	})
	if err != nil {
		t.Fatalf("expected a non-context slot error to be skipped, not propagated, got: %v", err)
	}
	for _, pos := range c.Positions {
		for _, bl := range pos.Blunders {
			if bl.Move.UCI == "e8e7" {
				t.Errorf("expected the e8e7 slot to be skipped after its severity error, but found it in the corpus")
			}
		}
	}
}

// TestRun_AbortsOnContextCancellation asserts the other half of the new
// behaviour: a context cancellation/deadline is NOT a per-slot problem, so it
// must still abort the whole run (ctrl-c has to work) rather than being
// silently skipped like an ordinary processing error.
func TestRun_AbortsOnContextCancellation(t *testing.T) {
	cfg := config.Default()
	cfg.OpeningsJSONPath = "testdata/mini-openings.json"
	cfg.Workers = 2
	cfg.MinEvalDropCp = 150

	_, err := Run(context.Background(), cfg, Deps{
		Sev: erroringSev{err: context.Canceled}, Plaus: fakePlaus{}, Progress: progress.New(discard{}),
	})
	if err == nil {
		t.Fatal("expected Run to abort and return an error on context cancellation, got nil")
	}
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected the returned error to wrap context.Canceled, got: %v", err)
	}
}

// TestToRefutation_ThreadsMultiMovePV calls toRefutation directly with a
// known post-blunder FEN and a real, legal 3-move PV, and asserts the SAN
// decoded for EACH ply is correct.
//
// The position has two white knights (c3 and e3) that can both reach d5.
// PV[0] moves the e3 knight away (to g4, which cannot reach d5), PV[1] is a
// black king move (e8-e7, walking the king onto a square the d5 knight will
// attack), and PV[2] is the surviving c3 knight jumping to d5.
//
// Decoded against the CORRECTLY-threaded FEN (i.e. after PV[0] and PV[1] have
// actually been applied), PV[2]'s SAN is unambiguous ("Nd5", only one knight
// can reach d5 now) and includes a check ("+", the black king just walked
// onto e7, which d5 attacks): "Nd5+".
//
// A regression that re-pins toRefutation's base FEN to postFEN for PV move 2+
// (i.e. forgets to thread `fen` forward and keeps decoding against the
// original pre-PV position) would instead decode PV[2] with BOTH knights
// still on the board (needing file disambiguation) and the black king still
// on e8 (not in check), producing "Ncd5" — visibly wrong on two counts. This
// test verifies that divergence exists (so it would actually catch such a
// regression) and then asserts toRefutation produces the correct, threaded
// SAN for every ply.
func TestToRefutation_ThreadsMultiMovePV(t *testing.T) {
	postFEN := "4k3/8/8/8/8/2N1N3/8/6K1 w - - 0 1"
	pv := []string{"e3g4", "e8e7", "c3d5"}
	wantSAN := []string{"Ng4", "Ke7", "Nd5+"}

	// Sanity-check the fixture actually exercises FEN-threading: decoding
	// PV[2] directly against the stale (pre-PV) postFEN must diverge from the
	// correctly-threaded SAN, or this test wouldn't catch a stale-base-FEN
	// regression at all.
	staleSAN, staleErr := chessx.SANForUCI(postFEN, pv[2])
	if staleErr == nil && staleSAN == wantSAN[2] {
		t.Fatalf("fixture is broken: decoding %s against the stale (pre-PV) FEN produced the same SAN (%q) as the correctly-threaded position — this test would not catch a stale-FEN regression", pv[2], staleSAN)
	}
	if staleSAN != "Ncd5" {
		t.Fatalf("fixture assumption changed: stale decode of %s against postFEN = %q, want %q (Ncd5 — disambiguated, no check)", pv[2], staleSAN, "Ncd5")
	}

	ref := stockfish.Refutation{PV: pv, EvalAfterCp: 250}
	got := toRefutation(postFEN, ref)

	if len(got.PV) != len(pv) {
		t.Fatalf("toRefutation PV length = %d, want %d", len(got.PV), len(pv))
	}
	for i, u := range pv {
		if got.PV[i].UCI != u {
			t.Errorf("ply %d UCI = %q, want %q", i, got.PV[i].UCI, u)
		}
		if got.PV[i].SAN != wantSAN[i] {
			t.Errorf("ply %d SAN = %q, want %q", i, got.PV[i].SAN, wantSAN[i])
		}
	}
	if got.EvalAfterCp != 250 {
		t.Errorf("EvalAfterCp = %d, want 250", got.EvalAfterCp)
	}
	if got.MateIn != nil {
		t.Errorf("MateIn = %v, want nil (ref.HasMate is false)", got.MateIn)
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
