// Package pipeline ties every prior package together: it enumerates book
// opponent-to-move slots, fans a bounded worker pool out over them, scores
// each legal alternative to the book move for severity (stockfish) and
// plausibility (lichess+maia blend), runs selection's threshold/ranking
// gate, and merges the survivors into a corpus.Builder.
package pipeline

import (
	"context"
	"fmt"
	"sort"
	"sync"

	"golang.org/x/sync/errgroup"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/bands"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/chessx"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/corpus"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/progress"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/seed"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/selection"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/stockfish"
)

// Sev is the severity+refutation half of the per-candidate signal: how much
// worse the candidate move is than the book move (Severity), and the user's
// best reply once the opponent has played it (Refute). Satisfied by
// *stockfish.Analyzer in production and by a fake in tests.
type Sev interface {
	Severity(ctx context.Context, slotFEN, bookUCI, candUCI string) (stockfish.EvalDrop, error)
	Refute(ctx context.Context, postFEN string) (stockfish.Refutation, error)
}

// Plaus is the plausibility half of the per-candidate signal: how likely a
// human at each rating band is to actually play candUCI at fen. Returns the
// blended per-band probability plus a metadata map of the raw signals that
// went into the blend (band -> metric name -> value), for corpus
// provenance/debugging. A move with no signal in any band returns an empty
// (not nil) perBand map, which processSlot treats as "never plausible,
// don't bother scoring severity for it".
type Plaus interface {
	PerBand(ctx context.Context, fen, candUCI string) (perBand map[string]float64, meta map[string]map[string]float64, err error)
}

// Deps bundles the pipeline's external dependencies so Run stays testable
// with fakes.
type Deps struct {
	Sev      Sev
	Plaus    Plaus
	Progress *progress.Emitter
}

// Run loads the seed, enumerates every opponent-to-move slot, and processes
// them through a worker pool bounded by cfg.Workers. Each slot is scored
// independently; a mutex guards the shared corpus.Builder while workers
// merge in their results, but the builder itself is only Build()'t once, at
// the end, after every worker has finished (errgroup.Wait returns once all
// goroutines have completed or the group's context is cancelled).
func Run(ctx context.Context, cfg config.Config, dep Deps) (corpus.Corpus, error) {
	s, err := seed.Load(cfg.OpeningsJSONPath)
	if err != nil {
		return corpus.Corpus{}, err
	}
	slots, err := seed.EnumerateSlots(s)
	if err != nil {
		return corpus.Corpus{}, err
	}
	dep.Progress.Phase("analyse", len(slots))

	maiaNets, lichessBuckets := provenanceBandUnion()
	builder := corpus.NewBuilder()
	builder.SetProvenance(corpus.Provenance{
		Depth:             cfg.StockfishDepth,
		MultiPV:           cfg.MultiPV,
		SourceSeedVersion: s.Version,
		MaiaNets:          maiaNets,
		LichessBuckets:    lichessBuckets,
	})
	var mu sync.Mutex

	g, gctx := errgroup.WithContext(ctx)
	g.SetLimit(cfg.Workers)
	for _, sl := range slots {
		sl := sl
		g.Go(func() error {
			entry, err := processSlot(gctx, cfg, dep, sl)
			dep.Progress.Tick(sl.BookMoveSAN)
			if err != nil {
				return fmt.Errorf("slot %s (%s): %w", sl.LineKey, sl.BookMoveSAN, err)
			}
			if entry == nil {
				return nil
			}
			mu.Lock()
			builder.Add(*entry)
			mu.Unlock()
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return corpus.Corpus{}, err
	}
	return builder.Build(), nil
}

// processSlot scores every legal opponent move at sl other than the book
// move, gates+ranks the survivors through selection.Select, and (for the
// ones that make the cut) computes the refutation. Returns nil, nil if no
// candidate survives selection — the slot contributes nothing to the corpus.
func processSlot(ctx context.Context, cfg config.Config, dep Deps, sl seed.Slot) (*corpus.PositionEntry, error) {
	legal, err := chessx.LegalMovesUCI(sl.RawFEN)
	if err != nil {
		return nil, err
	}

	var raws []selection.Raw
	// moveUCI -> band -> metric name -> value; carried alongside raws so it
	// can be attached to the surviving candidates after selection.Select.
	meta := map[string]map[string]map[string]float64{}
	for _, mv := range legal {
		if mv == sl.BookMoveUCI {
			continue
		}
		perBand, m, err := dep.Plaus.PerBand(ctx, sl.RawFEN, mv)
		if err != nil {
			return nil, fmt.Errorf("plausibility %s: %w", mv, err)
		}
		if len(perBand) == 0 {
			// No plausibility signal in any band: never worth the cost of a
			// severity query, and selection.Select would reject it anyway.
			continue
		}
		drop, err := dep.Sev.Severity(ctx, sl.RawFEN, sl.BookMoveUCI, mv)
		if err != nil {
			return nil, fmt.Errorf("severity %s: %w", mv, err)
		}
		raws = append(raws, selection.Raw{MoveUCI: mv, Drop: drop.Cp, PerBand: perBand})
		meta[mv] = m
	}

	cands := selection.Select(raws, cfg)
	if len(cands) == 0 {
		return nil, nil
	}

	blunders := make([]corpus.Blunder, 0, len(cands))
	for _, c := range cands {
		postFEN, err := chessx.ApplyUCI(sl.RawFEN, c.MoveUCI)
		if err != nil {
			return nil, fmt.Errorf("apply candidate %s: %w", c.MoveUCI, err)
		}
		ref, err := dep.Sev.Refute(ctx, postFEN)
		if err != nil {
			return nil, fmt.Errorf("refute %s: %w", c.MoveUCI, err)
		}
		san, err := chessx.SANForUCI(sl.RawFEN, c.MoveUCI)
		if err != nil {
			return nil, fmt.Errorf("san %s: %w", c.MoveUCI, err)
		}
		blunders = append(blunders, corpus.Blunder{
			Move:       corpus.Move{UCI: c.MoveUCI, SAN: san},
			EvalDropCp: c.EvalDropCp,
			Bands:      c.Bands,
			Plaus:      meta[c.MoveUCI],
			Refutation: toRefutation(postFEN, ref),
			Lines:      []string{sl.LineKey},
		})
	}

	return &corpus.PositionEntry{
		NormFEN:      sl.NormFEN,
		OpponentSide: string(sl.OpponentSide),
		BookMove:     corpus.Move{UCI: sl.BookMoveUCI, SAN: sl.BookMoveSAN},
		Blunders:     blunders,
	}, nil
}

// toRefutation converts a stockfish.Refutation's UCI principal variation
// into corpus.Move{SAN,UCI} pairs.
//
// postFEN MUST be the position immediately AFTER the opponent's blunder —
// the same FEN passed to Sev.Refute — because r.PV is a sequence of moves
// starting from that position (the user's reply first, then the opponent's
// reply to that, and so on). SAN is context-dependent (it depends on what
// else could reach the same square, whether the moving piece gives check,
// etc.), so each PV move's SAN must be decoded against the FEN the position
// is actually in at that point in the sequence, not against the pre-blunder
// slot FEN. Threading the FEN forward one ApplyUCI per PV move is what makes
// that correct; passing the pre-blunder slot FEN here would decode every PV
// move's SAN against the wrong side-to-move/pre-blunder board and produce
// garbage (or in some cases silently wrong) notation.
func toRefutation(postFEN string, r stockfish.Refutation) corpus.Refutation {
	pv := make([]corpus.Move, 0, len(r.PV))
	fen := postFEN
	for _, u := range r.PV {
		san, err := chessx.SANForUCI(fen, u)
		if err != nil {
			// Keep the UCI even if SAN decoding fails so the PV isn't silently
			// truncated; an empty SAN is a visible signal something's off.
			san = ""
		}
		pv = append(pv, corpus.Move{UCI: u, SAN: san})
		next, err := chessx.ApplyUCI(fen, u)
		if err != nil {
			break
		}
		fen = next
	}
	out := corpus.Refutation{PV: pv, EvalAfterCp: r.EvalAfterCp}
	if r.HasMate {
		m := r.MateIn
		out.MateIn = &m
	}
	return out
}

// provenanceBandUnion returns the sorted, deduplicated union of every band's
// maia nets and lichess rating buckets. This is static config-derived
// metadata (not sensitive to which Sev/Plaus implementation is wired in), so
// it belongs in Provenance for both the fake-backed test run and the real
// run rather than being bolted on after the fact by cmd/build-corpus.
func provenanceBandUnion() (maiaNets []string, lichessBuckets []int) {
	netSet := map[string]struct{}{}
	bucketSet := map[int]struct{}{}
	for _, b := range bands.All() {
		for _, n := range bands.MaiaNets(b) {
			netSet[n] = struct{}{}
		}
		for _, r := range bands.LichessBucket(b) {
			bucketSet[r] = struct{}{}
		}
	}
	for n := range netSet {
		maiaNets = append(maiaNets, n)
	}
	sort.Strings(maiaNets)
	for r := range bucketSet {
		lichessBuckets = append(lichessBuckets, r)
	}
	sort.Ints(lichessBuckets)
	return maiaNets, lichessBuckets
}
