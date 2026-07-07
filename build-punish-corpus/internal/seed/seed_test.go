package seed

import (
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/chessx"
)

func TestEnumerateSlots_OnlyOpponentToMove(t *testing.T) {
	s, err := Load("testdata/mini-openings.json")
	if err != nil {
		t.Fatal(err)
	}
	slots, err := EnumerateSlots(s)
	if err != nil {
		t.Fatal(err)
	}
	// white-side opening: opponent = black. Black book moves are e5 and Nc6 => 2 slots.
	if len(slots) != 2 {
		t.Fatalf("want 2 opponent slots, got %d: %+v", len(slots), slots)
	}
	for _, sl := range slots {
		if sl.OpponentSide != chessx.Black {
			t.Errorf("slot opponentSide = %v, want black", sl.OpponentSide)
		}
		if chessx.SideToMove(sl.RawFEN) != chessx.Black {
			t.Errorf("slot RawFEN side-to-move != black: %s", sl.RawFEN)
		}
	}
	if slots[0].BookMoveSAN != "e5" || slots[1].BookMoveSAN != "Nc6" {
		t.Errorf("book moves wrong: %q %q", slots[0].BookMoveSAN, slots[1].BookMoveSAN)
	}
	if slots[0].LineKey != "italian game|masters|f1c4" {
		t.Errorf("line provenance lost: %q", slots[0].LineKey)
	}
}

func TestEnumerateSlots_BlackSideOpening(t *testing.T) {
	s, err := Load("testdata/black-side.json")
	if err != nil {
		t.Fatal(err)
	}
	slots, err := EnumerateSlots(s)
	if err != nil {
		t.Fatal(err)
	}
	// black-side opening: user plays black, opponent = white. White book moves are e4 and Nf3 => 2 slots.
	if len(slots) != 2 {
		t.Fatalf("want 2 opponent slots, got %d: %+v", len(slots), slots)
	}
	for _, sl := range slots {
		if sl.OpponentSide != chessx.White {
			t.Errorf("slot opponentSide = %v, want white", sl.OpponentSide)
		}
		if chessx.SideToMove(sl.RawFEN) != chessx.White {
			t.Errorf("slot RawFEN side-to-move != white: %s", sl.RawFEN)
		}
	}
	if slots[0].BookMoveSAN != "e4" || slots[1].BookMoveSAN != "Nf3" {
		t.Errorf("book moves wrong: %q %q", slots[0].BookMoveSAN, slots[1].BookMoveSAN)
	}
	if slots[0].LineKey != "sicilian defense|masters|c7c5" {
		t.Errorf("line provenance lost: %q", slots[0].LineKey)
	}
}

func TestEnumerateSlots_RejectsInvalidSide(t *testing.T) {
	invalidSeed := Seed{
		Version: 4,
		Openings: []Opening{
			{
				Name:    "test opening",
				ECO:     "a00",
				Side:    "purple",
				RootFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
				Lines: []Line{
					{
						Name:      "main",
						StableKey: "test|line|key",
						Plies: []Ply{
							{UCI: "e2e4", SAN: "e4"},
						},
					},
				},
			},
		},
	}
	_, err := EnumerateSlots(invalidSeed)
	if err == nil {
		t.Fatalf("want error for invalid side, got nil")
	}
}
