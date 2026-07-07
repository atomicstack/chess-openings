package plausibility

import (
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/lichess"
)

func TestBlend_TrustsLichessWhenEnoughGames(t *testing.T) {
	lich := map[string]lichess.MoveStat{"e2e4": {Games: 400, Freq: 0.6}}
	maia := map[string]float64{"e2e4": 0.2}
	got := Blend(lich, 500, maia, 50)
	if got["e2e4"].Value != 0.6 {
		t.Errorf("should use lichess freq, got %.2f", got["e2e4"].Value)
	}
}

func TestBlend_FallsBackToMaiaWhenSparse(t *testing.T) {
	lich := map[string]lichess.MoveStat{"e2e4": {Games: 3, Freq: 1.0}}
	maia := map[string]float64{"e2e4": 0.25}
	got := Blend(lich, 3, maia, 50)
	if got["e2e4"].Value != 0.25 {
		t.Errorf("should fall back to maia, got %.2f", got["e2e4"].Value)
	}
}

func TestBlend_UnionOfMoves(t *testing.T) {
	lich := map[string]lichess.MoveStat{"a2a3": {Games: 5, Freq: 0.5}}
	maia := map[string]float64{"h2h3": 0.1}
	got := Blend(lich, 5, maia, 50)
	if _, ok := got["a2a3"]; !ok {
		t.Error("missing lichess-only move")
	}
	if _, ok := got["h2h3"]; !ok {
		t.Error("missing maia-only move")
	}
}
