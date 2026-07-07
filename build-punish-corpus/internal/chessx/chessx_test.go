package chessx

import (
	"slices"
	"strings"
	"testing"
)

func TestNormalizeFEN_StripsMoveCounters(t *testing.T) {
	in := "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	want := "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3"
	if got := NormalizeFEN(in); got != want {
		t.Errorf("NormalizeFEN = %q, want %q", got, want)
	}
}

func TestNormalizeFEN_TranspositionsMatch(t *testing.T) {
	// Same position reached via different move orders differs only in counters.
	a := "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"
	b := "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 5 4"
	if NormalizeFEN(a) != NormalizeFEN(b) {
		t.Errorf("transposition keys differ:\n a=%q\n b=%q", NormalizeFEN(a), NormalizeFEN(b))
	}
}

func TestWalk_ProducesPreMoveFENsAndSAN(t *testing.T) {
	root := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	steps, err := Walk(root, []string{"e2e4", "e7e5", "g1f3"})
	if err != nil {
		t.Fatal(err)
	}
	if len(steps) != 3 {
		t.Fatalf("want 3 steps, got %d", len(steps))
	}
	if steps[0].MoverSide != White || steps[1].MoverSide != Black {
		t.Errorf("mover sides wrong: %+v", steps)
	}
	if steps[0].MoveSAN != "e4" || steps[2].MoveSAN != "Nf3" {
		t.Errorf("SAN wrong: %q / %q", steps[0].MoveSAN, steps[2].MoveSAN)
	}
	// FEN of step[1] must be position after e4 (black to move).
	if SideToMove(steps[1].FEN) != Black {
		t.Errorf("pre-move side of step[1] = %v, want black", SideToMove(steps[1].FEN))
	}
}

func TestApplyUCI_RoundTrip(t *testing.T) {
	start := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	result, err := ApplyUCI(start, "e2e4")
	if err != nil {
		t.Fatalf("ApplyUCI failed: %v", err)
	}
	// verify the pawn moved to e4 and black is to move
	if !strings.HasPrefix(result, "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b") {
		t.Errorf("ApplyUCI result = %q, want prefix 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b'", result)
	}
}

func TestApplyUCI_RejectsIllegalMove(t *testing.T) {
	start := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	_, err := ApplyUCI(start, "e2e5")
	if err == nil {
		t.Errorf("ApplyUCI should reject illegal move e2e5, but got nil error")
	}
}

func TestCastleUCI_RoundTrip(t *testing.T) {
	white := "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"
	black := "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R b KQkq - 0 1"
	cases := []struct {
		fen, kingToRook, standard string
	}{
		{white, "e1h1", "e1g1"}, // white O-O
		{white, "e1a1", "e1c1"}, // white O-O-O
		{black, "e8h8", "e8g8"}, // black O-O
		{black, "e8a8", "e8c8"}, // black O-O-O
	}
	for _, c := range cases {
		if got := ToStandardCastleUCI(c.fen, c.kingToRook); got != c.standard {
			t.Errorf("ToStandardCastleUCI(%q) = %q, want %q", c.kingToRook, got, c.standard)
		}
		if got := ToChessKitCastleUCI(c.fen, c.standard); got != c.kingToRook {
			t.Errorf("ToChessKitCastleUCI(%q) = %q, want %q", c.standard, got, c.kingToRook)
		}
	}
}

func TestCastleUCI_LeavesNonCastlesUnchanged(t *testing.T) {
	white := "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"
	// a normal pawn move and a normal (non-castling) king step must pass through.
	for _, u := range []string{"e2e4", "e1e2", "e1f1"} {
		if got := ToStandardCastleUCI(white, u); got != u {
			t.Errorf("ToStandardCastleUCI(%q) = %q, want unchanged", u, got)
		}
		if got := ToChessKitCastleUCI(white, u); got != u {
			t.Errorf("ToChessKitCastleUCI(%q) = %q, want unchanged", u, got)
		}
	}
	// king-check guard: a non-king piece whose coordinates look like a castle
	// must NOT be converted. rook on e1, no king on e1.
	rookFEN := "4k3/8/8/8/8/8/8/R3R3 w - - 0 1"
	if got := ToStandardCastleUCI(rookFEN, "e1a1"); got != "e1a1" {
		t.Errorf("rook e1a1 mis-converted to %q, want unchanged", got)
	}
	// empty from-square guard: e1 empty => unchanged.
	emptyFEN := "4k3/8/8/8/8/8/8/8 w - - 0 1"
	if got := ToStandardCastleUCI(emptyFEN, "e1h1"); got != "e1h1" {
		t.Errorf("empty-e1 e1h1 mis-converted to %q, want unchanged", got)
	}
}

func TestApplyUCI_AcceptsKingToRookCastle(t *testing.T) {
	white := "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"
	got, err := ApplyUCI(white, "e1h1") // king-to-rook O-O
	if err != nil {
		t.Fatalf("ApplyUCI(e1h1) should succeed after normalization, got %v", err)
	}
	if p := pieceAt(got, "g1"); p != 'K' {
		t.Errorf("king not on g1 after O-O: board=%q", got)
	}
	if p := pieceAt(got, "f1"); p != 'R' {
		t.Errorf("rook not on f1 after O-O: board=%q", got)
	}
}

func TestWalk_NormalizesKingToRookCastle(t *testing.T) {
	root := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	// white castles kingside at ply index 6, given in king-to-rook form.
	plies := []string{"e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "e1h1"}
	steps, err := Walk(root, plies)
	if err != nil {
		t.Fatalf("Walk over a king-to-rook castling line failed: %v", err)
	}
	if steps[6].MoveUCI != "e1g1" {
		t.Errorf("Step.MoveUCI = %q, want standard %q", steps[6].MoveUCI, "e1g1")
	}
	if steps[6].MoveSAN != "O-O" {
		t.Errorf("Step.MoveSAN = %q, want %q", steps[6].MoveSAN, "O-O")
	}
}

func TestLegalMovesUCI_StartPosition(t *testing.T) {
	start := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	moves, err := LegalMovesUCI(start)
	if err != nil {
		t.Fatalf("LegalMovesUCI failed: %v", err)
	}
	if len(moves) != 20 {
		t.Errorf("LegalMovesUCI returned %d moves, want 20", len(moves))
	}
	if !slices.Contains(moves, "e2e4") {
		t.Errorf("LegalMovesUCI missing e2e4")
	}
	if !slices.Contains(moves, "g1f3") {
		t.Errorf("LegalMovesUCI missing g1f3")
	}
}
