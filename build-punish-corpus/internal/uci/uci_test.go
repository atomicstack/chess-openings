package uci

import (
	"testing"
)

func TestParseInfoLine_CpAndPV(t *testing.T) {
	l, ok := parseInfoLine("info depth 22 multipv 2 score cp -150 pv e2e4 e7e5 g1f3")
	if !ok {
		t.Fatal("expected a parsed line")
	}
	if l.Rank != 2 || l.ScoreCp != -150 || l.HasMate {
		t.Errorf("bad parse: %+v", l)
	}
	if len(l.PV) != 3 || l.PV[0] != "e2e4" {
		t.Errorf("pv wrong: %v", l.PV)
	}
}

func TestParseInfoLine_Mate(t *testing.T) {
	l, ok := parseInfoLine("info depth 20 multipv 1 score mate 3 pv d1h5 g8f6 h5f7")
	if !ok || !l.HasMate || l.Mate != 3 {
		t.Fatalf("mate parse failed: %+v ok=%v", l, ok)
	}
}

func TestCollectAnalysis_KeepsDeepestPerRank(t *testing.T) {
	stream := []string{
		"info depth 10 multipv 1 score cp 20 pv e2e4",
		"info depth 22 multipv 1 score cp 35 pv e2e4 e7e5",
		"info depth 22 multipv 2 score cp 10 pv d2d4 d7d5",
		"bestmove e2e4",
	}
	lines := collectAnalysis(stream, 2)
	if len(lines) != 2 {
		t.Fatalf("want 2 ranked lines, got %d", len(lines))
	}
	if lines[0].Rank != 1 || lines[0].ScoreCp != 35 {
		t.Errorf("rank1 should be deepest (cp 35): %+v", lines[0])
	}
}
