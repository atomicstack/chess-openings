package corpus

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestBuilder_MergesTranspositions(t *testing.T) {
	b := NewBuilder()
	b.Add(PositionEntry{NormFEN: "K", OpponentSide: "black",
		BookMove: Move{UCI: "g8f6", SAN: "Nf6"},
		Blunders: []Blunder{{Move: Move{UCI: "f6g4"}, Bands: []string{"beginner"}, Lines: []string{"lineA"}}}})
	b.Add(PositionEntry{NormFEN: "K", OpponentSide: "black",
		BookMove: Move{UCI: "g8f6", SAN: "Nf6"},
		Blunders: []Blunder{{Move: Move{UCI: "f6g4"}, Bands: []string{"intermediate"}, Lines: []string{"lineB"}}}})
	c := b.Build()
	pos := c.Positions["K"]
	if len(pos.Blunders) != 1 {
		t.Fatalf("same blunder move should merge to 1, got %d", len(pos.Blunders))
	}
	if len(pos.Blunders[0].Lines) != 2 {
		t.Errorf("provenance lines should union to 2, got %v", pos.Blunders[0].Lines)
	}
}

func TestMarshal_Deterministic(t *testing.T) {
	b := NewBuilder()
	b.Add(PositionEntry{NormFEN: "z", OpponentSide: "white", BookMove: Move{UCI: "a"}})
	b.Add(PositionEntry{NormFEN: "a", OpponentSide: "white", BookMove: Move{UCI: "b"}})
	out1, _ := Marshal(b.Build())
	out2, _ := Marshal(b.Build())
	if string(out1) != string(out2) {
		t.Fatal("marshal not deterministic")
	}
	if strings.Index(string(out1), `"a"`) > strings.Index(string(out1), `"z"`) {
		t.Error("position keys not sorted")
	}
	var sanity map[string]any
	if err := json.Unmarshal(out1, &sanity); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
}
