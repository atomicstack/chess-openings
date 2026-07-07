// Package stockfish wraps a uci.Engine to compute two things the corpus
// pipeline needs about a candidate opponent blunder: how severe it is
// (Severity) and how the user should refute it (Refute).
package stockfish

import (
	"context"
	"fmt"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/chessx"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/uci"
)

// Analyzer drives a uci.Engine at a fixed depth/multiPV to score candidate
// opponent moves and find the user's best reply after a blunder.
type Analyzer struct {
	eng     uci.Engine
	depth   int
	multiPV int
}

// New builds an Analyzer over eng, searching to depth and requesting
// multiPV ranked lines per Analyse call.
func New(eng uci.Engine, depth, multiPV int) *Analyzer {
	return &Analyzer{eng: eng, depth: depth, multiPV: multiPV}
}

// EvalDrop is the severity of a candidate opponent move relative to the book
// move. BookCp and CandCp are the user's eval (in centipawns, user POV)
// after the book move and after the candidate move respectively. Cp is
// CandCp - BookCp: positive means the candidate is worse for the opponent
// (better for the user), i.e. a losing move.
type EvalDrop struct{ Cp, BookCp, CandCp int }

// Severity evaluates the position after the book move and after the
// candidate move. Both of those positions have the same side to move (the
// user replying), so Stockfish's scores there are directly comparable
// user-POV numbers with no sign flip needed: Cp = CandCp - BookCp is how
// much better the position becomes for the user after the candidate versus
// after the book move, which is exactly how much worse the candidate is for
// the opponent — i.e. the severity of the opponent's mistake. Positive means
// the candidate is a losing move.
func (a *Analyzer) Severity(ctx context.Context, slotFEN, bookUCI, candUCI string) (EvalDrop, error) {
	bookFEN, err := chessx.ApplyUCI(slotFEN, bookUCI)
	if err != nil {
		return EvalDrop{}, fmt.Errorf("apply book move %s at %s: %w", bookUCI, slotFEN, err)
	}
	candFEN, err := chessx.ApplyUCI(slotFEN, candUCI)
	if err != nil {
		return EvalDrop{}, fmt.Errorf("apply candidate move %s at %s: %w", candUCI, slotFEN, err)
	}

	bookCp, err := a.topCp(ctx, bookFEN)
	if err != nil {
		return EvalDrop{}, err
	}
	candCp, err := a.topCp(ctx, candFEN)
	if err != nil {
		return EvalDrop{}, err
	}

	return EvalDrop{Cp: candCp - bookCp, BookCp: bookCp, CandCp: candCp}, nil
}

// Refutation is the user's best line at the position immediately after the
// opponent's blunder.
type Refutation struct {
	PV          []string
	EvalAfterCp int
	MateIn      int
	HasMate     bool
}

// Refute returns the user's best line (the top-ranked Analyse result) at
// postBlunderFEN.
func (a *Analyzer) Refute(ctx context.Context, postBlunderFEN string) (Refutation, error) {
	lines, err := a.eng.Analyse(ctx, postBlunderFEN, a.depth, a.multiPV)
	if err != nil {
		return Refutation{}, fmt.Errorf("analyse %s: %w", postBlunderFEN, err)
	}
	if len(lines) == 0 {
		return Refutation{}, fmt.Errorf("no analysis for %s", postBlunderFEN)
	}
	top := lines[0]
	return Refutation{
		PV:          top.PV,
		EvalAfterCp: top.ScoreCp,
		MateIn:      top.Mate,
		HasMate:     top.HasMate,
	}, nil
}

// topCp asks for a single line at fen and returns its score in centipawns,
// converting a mate score to a large-magnitude cp value so mate-vs-mate and
// mate-vs-cp comparisons both stay ordinally correct (shorter mates for the
// side to move rank above longer ones, and any mate outranks any plain cp
// score).
func (a *Analyzer) topCp(ctx context.Context, fen string) (int, error) {
	lines, err := a.eng.Analyse(ctx, fen, a.depth, 1)
	if err != nil {
		return 0, fmt.Errorf("analyse %s: %w", fen, err)
	}
	if len(lines) == 0 {
		return 0, fmt.Errorf("no analysis for %s", fen)
	}
	l := lines[0]
	if l.HasMate {
		if l.Mate >= 0 {
			return 100000 - l.Mate, nil
		}
		return -100000 - l.Mate, nil
	}
	return l.ScoreCp, nil
}
