// Package chessx provides pure helpers over github.com/corentings/chess/v2
// for FEN normalization (the corpus transposition key) and walking a line's
// UCI plies into per-ply pre-move positions with SAN.
package chessx

import (
	"fmt"
	"strings"

	"github.com/corentings/chess/v2"
)

// Side is the color to move, rendered lowercase for corpus/log output.
type Side string

const (
	White Side = "white"
	Black Side = "black"
)

// Step is one ply of a walked line: the position BEFORE the move, who moved,
// and the move in both UCI and SAN form.
type Step struct {
	FEN       string // position BEFORE the move
	MoverSide Side
	MoveUCI   string
	MoveSAN   string
}

// NormalizeFEN drops the halfmove-clock and fullmove-number fields so
// transposed positions share one key. This is the corpus transposition key.
// The 4-field output is a key only and must never be passed back to the chess
// library; use Slot.RawFEN or the original FEN for that.
func NormalizeFEN(fen string) string {
	f := strings.Fields(fen)
	if len(f) < 4 {
		return fen
	}
	return strings.Join(f[:4], " ")
}

// SideToMove reads the side-to-move field out of a FEN string.
func SideToMove(fen string) Side {
	f := strings.Fields(fen)
	if len(f) >= 2 && f[1] == "b" {
		return Black
	}
	return White
}

// newGameAt constructs a *chess.Game whose current position is fen.
func newGameAt(fen string) (*chess.Game, error) {
	opt, err := chess.FEN(fen)
	if err != nil {
		return nil, err
	}
	return chess.NewGame(opt), nil
}

// Walk replays uciPlies from rootFEN, returning one Step per ply. Step.FEN
// is the position BEFORE that ply's move is applied.
func Walk(rootFEN string, uciPlies []string) ([]Step, error) {
	g, err := newGameAt(rootFEN)
	if err != nil {
		return nil, err
	}
	steps := make([]Step, 0, len(uciPlies))
	for i, u := range uciPlies {
		pre := g.Position()
		preFEN := pre.String()
		san, err := SANForUCI(preFEN, u)
		if err != nil {
			return nil, fmt.Errorf("ply %d (%s): %w", i, u, err)
		}
		steps = append(steps, Step{
			FEN:       preFEN,
			MoverSide: SideToMove(preFEN),
			MoveUCI:   u,
			MoveSAN:   san,
		})
		if err := g.PushNotationMove(u, chess.UCINotation{}, nil); err != nil {
			return nil, fmt.Errorf("apply ply %d (%s): %w", i, u, err)
		}
	}
	return steps, nil
}

// SANForUCI decodes a UCI move against fen and encodes it as algebraic
// (SAN) notation, e.g. "e4" or "Nf3".
func SANForUCI(fen, uci string) (string, error) {
	g, err := newGameAt(fen)
	if err != nil {
		return "", err
	}
	mv, err := chess.UCINotation{}.Decode(g.Position(), uci)
	if err != nil {
		return "", err
	}
	return chess.AlgebraicNotation{}.Encode(g.Position(), mv), nil
}

// ApplyUCI applies a single UCI move to fen and returns the resulting FEN.
func ApplyUCI(fen, uci string) (string, error) {
	g, err := newGameAt(fen)
	if err != nil {
		return "", err
	}
	if err := g.PushNotationMove(uci, chess.UCINotation{}, nil); err != nil {
		return "", err
	}
	return g.Position().String(), nil
}

// LegalMovesUCI returns every legal move in fen, encoded as UCI strings.
func LegalMovesUCI(fen string) ([]string, error) {
	g, err := newGameAt(fen)
	if err != nil {
		return nil, err
	}
	moves := g.ValidMoves()
	out := make([]string, 0, len(moves))
	enc := chess.UCINotation{}
	for i := range moves {
		out = append(out, enc.Encode(g.Position(), &moves[i]))
	}
	return out, nil
}
