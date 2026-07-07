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

// Castling UCI convention: the ChessKit-based iOS app (and the seed
// openings.json) encode castling as KING-TO-ROOK UCI (e1h1, e1a1, e8h8, e8a8),
// whereas github.com/corentings/chess/v2 only speaks STANDARD UCI (e1g1, e1c1,
// e8g8, e8c8). These maps and the two converters below bridge the two so the
// library-facing helpers can normalize on input and the pipeline can
// denormalize on output.
var kingToRookToStandardCastle = map[string]string{
	"e1h1": "e1g1", // white O-O
	"e1a1": "e1c1", // white O-O-O
	"e8h8": "e8g8", // black O-O
	"e8a8": "e8c8", // black O-O-O
}

var standardToKingToRookCastle = map[string]string{
	"e1g1": "e1h1",
	"e1c1": "e1a1",
	"e8g8": "e8h8",
	"e8c8": "e8a8",
}

// pieceAt returns the FEN piece character on the given algebraic square (e.g.
// "e1"), or 0 if the square is empty or either input is malformed. It parses
// only the board (first) field of the FEN — no chess library involved.
func pieceAt(fen, square string) byte {
	if len(square) != 2 {
		return 0
	}
	file := int(square[0] - 'a') // 0..7 for a..h
	rank := int(square[1] - '1') // 0..7 for 1..8
	if file < 0 || file > 7 || rank < 0 || rank > 7 {
		return 0
	}
	board := fen
	if i := strings.IndexByte(fen, ' '); i >= 0 {
		board = fen[:i]
	}
	rows := strings.Split(board, "/")
	if len(rows) != 8 {
		return 0
	}
	row := rows[7-rank] // rows[0] is rank 8, rows[7] is rank 1
	col := 0
	for i := 0; i < len(row) && col <= file; i++ {
		ch := row[i]
		if ch >= '1' && ch <= '8' {
			col += int(ch - '0')
			continue
		}
		if col == file {
			return ch
		}
		col++
	}
	return 0
}

func isKing(p byte) bool { return p == 'K' || p == 'k' }

// ToStandardCastleUCI converts a king-to-rook castling UCI (e1h1/e1a1/e8h8/
// e8a8) into the standard two-square king move (e1g1/e1c1/e8g8/e8c8) the chess
// library expects. It only converts when the from-square actually holds a king,
// so a rook (or other piece) move whose coordinates happen to match a castle is
// left untouched. Any non-castling uci is returned unchanged.
func ToStandardCastleUCI(fen, uci string) string {
	if len(uci) < 4 {
		return uci
	}
	std, ok := kingToRookToStandardCastle[uci[:4]]
	if !ok {
		return uci
	}
	if !isKing(pieceAt(fen, uci[:2])) {
		return uci
	}
	return std
}

// ToChessKitCastleUCI is the inverse of ToStandardCastleUCI: it converts a
// standard king castling move back into the king-to-rook form the ChessKit iOS
// app consumes. Non-king or non-castling moves are returned unchanged.
func ToChessKitCastleUCI(fen, uci string) string {
	if len(uci) < 4 {
		return uci
	}
	ktr, ok := standardToKingToRookCastle[uci[:4]]
	if !ok {
		return uci
	}
	if !isKing(pieceAt(fen, uci[:2])) {
		return uci
	}
	return ktr
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
		// Normalize king-to-rook castling (seed convention) to the standard UCI
		// the library speaks, and store the STANDARD form in Step.MoveUCI so
		// downstream slots stay comparable to LegalMovesUCI output.
		std := ToStandardCastleUCI(preFEN, u)
		san, err := SANForUCI(preFEN, std)
		if err != nil {
			return nil, fmt.Errorf("ply %d (%s): %w", i, u, err)
		}
		steps = append(steps, Step{
			FEN:       preFEN,
			MoverSide: SideToMove(preFEN),
			MoveUCI:   std,
			MoveSAN:   san,
		})
		if err := g.PushNotationMove(std, chess.UCINotation{}, nil); err != nil {
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
	uci = ToStandardCastleUCI(fen, uci)
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
	uci = ToStandardCastleUCI(fen, uci)
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
