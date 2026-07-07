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
