package seed

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/chessx"
)

type Seed struct {
	Version  int       `json:"version"`
	Openings []Opening `json:"openings"`
}

type Opening struct {
	Name    string `json:"name"`
	ECO     string `json:"eco"`
	Side    string `json:"side"` // "white" | "black" = the side the USER plays
	RootFEN string `json:"rootFen"`
	Lines   []Line `json:"lines"`
}

type Line struct {
	Name      string `json:"name"`
	StableKey string `json:"stableKey"`
	Plies     []Ply  `json:"plies"`
}

type Ply struct {
	UCI string `json:"uci"`
	SAN string `json:"san"`
}

type Slot struct {
	NormFEN      string
	RawFEN       string
	OpponentSide chessx.Side
	BookMoveUCI  string
	BookMoveSAN  string
	LineKey      string
}

func Load(path string) (Seed, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Seed{}, fmt.Errorf("load seed %s: %w", path, err)
	}
	var s Seed
	if err := json.Unmarshal(b, &s); err != nil {
		return Seed{}, fmt.Errorf("load seed %s: %w", path, err)
	}
	return s, nil
}

func EnumerateSlots(s Seed) ([]Slot, error) {
	var slots []Slot
	for _, op := range s.Openings {
		if op.Side != "white" && op.Side != "black" {
			return nil, fmt.Errorf("opening %q: invalid side %q", op.Name, op.Side)
		}
		userSide := chessx.Side(op.Side)
		for _, ln := range op.Lines {
			ucis := make([]string, len(ln.Plies))
			for i, p := range ln.Plies {
				ucis[i] = p.UCI
			}
			steps, err := chessx.Walk(op.RootFEN, ucis)
			if err != nil {
				return nil, err
			}
			for _, st := range steps {
				if st.MoverSide == userSide {
					continue // user-to-move: not a blunder slot
				}
				slots = append(slots, Slot{
					NormFEN:      chessx.NormalizeFEN(st.FEN),
					RawFEN:       st.FEN,
					OpponentSide: st.MoverSide,
					BookMoveUCI:  st.MoveUCI,
					BookMoveSAN:  st.MoveSAN,
					LineKey:      ln.StableKey,
				})
			}
		}
	}
	return slots, nil
}
