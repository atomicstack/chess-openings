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

func TestEnumerateSlots_HandlesKingToRookCastling(t *testing.T) {
	// white-side opening => opponent is black; the line has black castle
	// kingside in king-to-rook form (e8h8), which corentings rejects unless
	// EnumerateSlots (via chessx.Walk) normalizes it to standard UCI first.
	castleSeed := Seed{
		Version: 4,
		Openings: []Opening{
			{
				Name:    "italian game",
				ECO:     "c50",
				Side:    "white",
				RootFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
				Lines: []Line{
					{
						Name:      "black castles",
						StableKey: "italian|black-castles",
						Plies: []Ply{
							{UCI: "e2e4", SAN: "e4"}, {UCI: "e7e5", SAN: "e5"},
							{UCI: "g1f3", SAN: "Nf3"}, {UCI: "b8c6", SAN: "Nc6"},
							{UCI: "f1c4", SAN: "Bc4"}, {UCI: "g8f6", SAN: "Nf6"},
							{UCI: "d2d3", SAN: "d3"}, {UCI: "f8e7", SAN: "Be7"},
							{UCI: "b1c3", SAN: "Nc3"}, {UCI: "e8h8", SAN: "O-O"},
						},
					},
				},
			},
		},
	}
	slots, err := EnumerateSlots(castleSeed)
	if err != nil {
		t.Fatalf("EnumerateSlots should handle king-to-rook castling, got %v", err)
	}
	var found bool
	for _, sl := range slots {
		if sl.BookMoveSAN == "O-O" {
			found = true
			if sl.BookMoveUCI != "e8g8" {
				t.Errorf("castle slot BookMoveUCI = %q, want standard %q", sl.BookMoveUCI, "e8g8")
			}
		}
	}
	if !found {
		t.Errorf("expected a slot with the black O-O book move, got %d slots", len(slots))
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
