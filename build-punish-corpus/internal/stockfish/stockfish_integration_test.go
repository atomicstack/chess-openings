//go:build integration

package stockfish

import (
	"context"
	"os"
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/uci"
)

func TestRefute_RealStockfish_FindsScholarPunish(t *testing.T) {
	bin := os.Getenv("STOCKFISH_PATH")
	if bin == "" {
		t.Skip("set STOCKFISH_PATH to run")
	}
	ctx := context.Background()
	p, err := uci.NewProcess(ctx, bin)
	if err != nil {
		t.Fatal(err)
	}
	defer p.Close()
	_ = p.SetOption("Threads", "1")
	_ = p.IsReady()
	a := New(p, 18, 1)
	// After 1.e4 e5 2.Qh5 Nc6 3.Bc4 Nf6?? (allows Qxf7#): white to move, mate available.
	post := "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
	r, err := a.Refute(ctx, post)
	if err != nil {
		t.Fatal(err)
	}
	if !r.HasMate {
		t.Errorf("expected mate refutation, got %+v", r)
	}
}
