package chessx

import "testing"

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
