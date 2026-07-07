package selection

import (
	"sort"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/bands"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
)

type Raw struct {
	MoveUCI string
	Drop    int
	PerBand map[string]float64
}

type Candidate struct {
	MoveUCI    string
	EvalDropCp int
	Plaus      float64 // best qualifying band plausibility
	Bands      []string
}

func Select(in []Raw, cfg config.Config) []Candidate {
	var cands []Candidate
	for _, r := range in {
		if r.Drop < cfg.MinEvalDropCp || r.Drop > cfg.MaxEvalDropCp {
			continue
		}
		var qual []string
		best := 0.0
		for _, b := range bands.All() {
			if p := r.PerBand[string(b)]; p >= cfg.MinPlausibility {
				qual = append(qual, string(b))
				if p > best {
					best = p
				}
			}
		}
		if len(qual) == 0 {
			continue
		}
		cands = append(cands, Candidate{MoveUCI: r.MoveUCI, EvalDropCp: r.Drop, Plaus: best, Bands: qual})
	}
	sort.Slice(cands, func(a, b int) bool {
		sa := cands[a].Plaus * float64(cands[a].EvalDropCp)
		sb := cands[b].Plaus * float64(cands[b].EvalDropCp)
		if sa != sb {
			return sa > sb
		}
		return cands[a].MoveUCI < cands[b].MoveUCI // deterministic tie-break
	})
	if len(cands) > cfg.MaxBlundersPerPosition {
		cands = cands[:cfg.MaxBlundersPerPosition]
	}
	return cands
}
