package stockfish

import (
	"context"
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/chessx"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/uci"
)

func TestSeverity_CandidateWorseThanBook(t *testing.T) {
	slot := "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"
	book := "g8f6"
	cand := "f8c5" // pretend worse in this fake

	fen0book, _ := chessx.ApplyUCI(slot, book)
	fen0cand, _ := chessx.ApplyUCI(slot, cand)

	f := uci.NewFake()
	// After book move it's white to move, eval +20 for white; after cand, +260 for white.
	// Analyzer must evaluate each reply position and express drop from BLACK's POV.
	f.Script[fen0book] = []uci.Line{{Rank: 1, ScoreCp: 20}}  // white POV
	f.Script[fen0cand] = []uci.Line{{Rank: 1, ScoreCp: 260}} // white POV
	a := New(f, 22, 1)

	d, err := a.Severity(context.Background(), slot, book, cand)
	if err != nil {
		t.Fatal(err)
	}
	// From black's POV the book keeps it near -20, candidate drops to -260 => drop 240.
	if d.Cp != 240 {
		t.Errorf("eval drop = %d, want 240", d.Cp)
	}
}

func TestRefute_ReturnsTopPV(t *testing.T) {
	post := "some/fen w - - 0 1"
	f := uci.NewFake()
	f.Script[post] = []uci.Line{{Rank: 1, ScoreCp: 350, PV: []string{"f3e5", "c6e5"}}}
	a := New(f, 22, 1)
	r, err := a.Refute(context.Background(), post)
	if err != nil {
		t.Fatal(err)
	}
	if r.EvalAfterCp != 350 || len(r.PV) != 2 || r.PV[0] != "f3e5" {
		t.Errorf("bad refutation: %+v", r)
	}
}
