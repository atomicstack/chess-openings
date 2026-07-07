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
type EvalDrop struct {
	Cp, BookCp, CandCp int
	// LeadsToMate is true when the position after the candidate move is a
	// forced mate in the user's favor (the user is the side to move there).
	// Such blunders are kept as bonus punish content even when their Cp drop
	// blows past the material self-immolation ceiling.
	LeadsToMate bool
}

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

	bookCp, _, err := a.topCp(ctx, bookFEN)
	if err != nil {
		return EvalDrop{}, err
	}
	candCp, candMate, err := a.topCp(ctx, candFEN)
	if err != nil {
		return EvalDrop{}, err
	}

	return EvalDrop{Cp: candCp - bookCp, BookCp: bookCp, CandCp: candCp, LeadsToMate: candMate}, nil
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

// topCp returns the score in centipawns and whether the side to move at fen has
// a forced mate (mate in the side-to-move's favor). A mate is converted to a
// large-magnitude cp value so mate-vs-mate and mate-vs-cp comparisons both stay
// ordinally correct.
func (a *Analyzer) topCp(ctx context.Context, fen string) (int, bool, error) {
	lines, err := a.eng.Analyse(ctx, fen, a.depth, 1)
	if err != nil {
		return 0, false, fmt.Errorf("analyse %s: %w", fen, err)
	}
	if len(lines) == 0 {
		return 0, false, fmt.Errorf("no analysis for %s", fen)
	}
	l := lines[0]
	if l.HasMate {
		if l.Mate >= 0 {
			return 100000 - l.Mate, true, nil
		}
		return -100000 - l.Mate, false, nil
	}
	return l.ScoreCp, false, nil
}
