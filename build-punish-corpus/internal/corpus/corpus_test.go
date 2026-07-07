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

// TestBuilder_MergeIsOrderInsensitive proves Add's conflict resolution does not
// depend on the order workers happen to finish in: two lines reaching the same
// NormFEN with different book moves, and a same-move blunder with divergent
// evalDropCp, must resolve to the identical result regardless of Add order.
func TestBuilder_MergeIsOrderInsensitive(t *testing.T) {
	entA := PositionEntry{NormFEN: "K", OpponentSide: "black",
		BookMove: Move{UCI: "g8f6", SAN: "Nf6"},
		Blunders: []Blunder{{Move: Move{UCI: "f6g4"}, EvalDropCp: 300,
			Refutation: Refutation{EvalAfterCp: 500}, Lines: []string{"lineA"}}}}
	entB := PositionEntry{NormFEN: "K", OpponentSide: "black",
		BookMove: Move{UCI: "b8c6", SAN: "Nc6"}, // lexicographically smaller uci
		Blunders: []Blunder{{Move: Move{UCI: "f6g4"}, EvalDropCp: 250,
			Refutation: Refutation{EvalAfterCp: 400}, Lines: []string{"lineB"}}}}

	forward := NewBuilder()
	forward.Add(entA)
	forward.Add(entB)
	fp := forward.Build().Positions["K"]

	reverse := NewBuilder()
	reverse.Add(entB)
	reverse.Add(entA)
	rp := reverse.Build().Positions["K"]

	if fp.BookMove.UCI != rp.BookMove.UCI {
		t.Errorf("bookMove depends on Add order: forward=%q reverse=%q", fp.BookMove.UCI, rp.BookMove.UCI)
	}
	if fp.BookMove.UCI != "b8c6" {
		t.Errorf("bookMove = %q, want the lexicographically smaller %q", fp.BookMove.UCI, "b8c6")
	}
	if len(fp.Blunders) != 1 || len(rp.Blunders) != 1 {
		t.Fatalf("blunders should merge to 1, got fwd=%d rev=%d", len(fp.Blunders), len(rp.Blunders))
	}
	if fp.Blunders[0].EvalDropCp != rp.Blunders[0].EvalDropCp {
		t.Errorf("evalDropCp depends on Add order: forward=%d reverse=%d",
			fp.Blunders[0].EvalDropCp, rp.Blunders[0].EvalDropCp)
	}
	if fp.Blunders[0].EvalDropCp != 250 {
		t.Errorf("evalDropCp = %d, want the smaller %d", fp.Blunders[0].EvalDropCp, 250)
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

// TestMarshal_JSONShapeAndNullability is a schema regression test: this
// package defines the frozen JSON shape a future Swift Decodable will parse,
// so every array field must render as `[]` when empty (never `null`), and
// `mateIn` must remain the only field allowed to be `null`.
func TestMarshal_JSONShapeAndNullability(t *testing.T) {
	b := NewBuilder()
	b.SetProvenance(Provenance{
		Stockfish:         "stockfish-16",
		Depth:             20,
		MultiPV:           3,
		MaiaNets:          []string{"maia1100", "maia1900"},
		LichessBuckets:    []int{1000, 1600},
		SourceSeedVersion: 2,
	})

	mateIn := 3
	b.Add(PositionEntry{
		NormFEN:      "pos1",
		OpponentSide: "black",
		BookMove:     Move{SAN: "e4", UCI: "e2e4"},
		Blunders: []Blunder{
			{
				Move:       Move{SAN: "a6", UCI: "a7a6"},
				EvalDropCp: 250,
				Bands:      []string{"advanced", "beginner"},
				Plaus:      map[string]map[string]float64{"beginner": {"a7a6": 0.4}},
				Refutation: Refutation{
					PV:          []Move{{SAN: "Qh5", UCI: "d1h5"}, {SAN: "g6", UCI: "g7g6"}},
					EvalAfterCp: 900,
					MateIn:      &mateIn,
				},
				Lines: []string{"lineA", "lineB"},
			},
			{
				Move:       Move{SAN: "h6", UCI: "h7h6"},
				EvalDropCp: 120,
				Refutation: Refutation{
					EvalAfterCp: 300,
					// PV and MateIn deliberately left zero-valued (nil).
				},
			},
		},
	})

	out, err := Marshal(b.Build())
	if err != nil {
		t.Fatalf("marshal failed: %v", err)
	}
	s := string(out)

	for _, key := range []string{
		`"version"`, `"provenance"`, `"positions"`, `"opponentSide"`, `"bookMove"`,
		`"blunders"`, `"evalDropCp"`, `"bands"`, `"plausibility"`, `"refutation"`,
		`"pv"`, `"evalAfterCp"`, `"mateIn"`, `"lines"`, `"maiaNets"`, `"lichessBuckets"`,
	} {
		if !strings.Contains(s, key) {
			t.Errorf("expected output to contain key %s, got:\n%s", key, s)
		}
	}

	if !strings.Contains(s, `"mateIn": 3`) {
		t.Errorf("expected blunder a's mateIn to serialize as the number 3, got:\n%s", s)
	}
	if !strings.Contains(s, `"mateIn": null`) {
		t.Errorf("expected blunder b's mateIn to serialize as null, got:\n%s", s)
	}

	// no field other than mateIn may render as null anywhere in the output —
	// this is what protects a Swift Decodable with non-optional arrays.
	for _, line := range strings.Split(s, "\n") {
		if strings.Contains(line, ": null") && !strings.Contains(line, `"mateIn"`) {
			t.Errorf("unexpected null (only mateIn may be null): %s", line)
		}
	}

	var decoded struct {
		Positions map[string]struct {
			Blunders []struct {
				Move struct {
					UCI string `json:"uci"`
				} `json:"move"`
				Refutation struct {
					PV     []Move `json:"pv"`
					MateIn *int   `json:"mateIn"`
				} `json:"refutation"`
			} `json:"blunders"`
		} `json:"positions"`
	}
	if err := json.Unmarshal(out, &decoded); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	pos1 := decoded.Positions["pos1"]
	if len(pos1.Blunders) != 2 {
		t.Fatalf("expected 2 blunders (different-move append path), got %d", len(pos1.Blunders))
	}
	for _, bl := range pos1.Blunders {
		if bl.Move.UCI == "h7h6" {
			if bl.Refutation.PV == nil {
				t.Error("blunder b's pv decoded as nil, want a non-nil empty slice")
			}
			if len(bl.Refutation.PV) != 0 {
				t.Errorf("expected blunder b's pv to be empty, got %v", bl.Refutation.PV)
			}
			if bl.Refutation.MateIn != nil {
				t.Errorf("expected blunder b's mateIn to be nil, got %v", *bl.Refutation.MateIn)
			}
		}
		if bl.Move.UCI == "a7a6" {
			if bl.Refutation.MateIn == nil || *bl.Refutation.MateIn != 3 {
				t.Errorf("expected blunder a's mateIn to be 3, got %v", bl.Refutation.MateIn)
			}
		}
	}
}
