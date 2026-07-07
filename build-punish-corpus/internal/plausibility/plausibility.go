package plausibility

import "github.com/mattkoscica/chess-openings/build-punish-corpus/internal/lichess"

type Score struct {
	Value       float64
	LichessFreq float64
	MaiaProb    float64
}

func Blend(lich map[string]lichess.MoveStat, lichTotalGames int, maia map[string]float64, minLichessGames int) map[string]Score {
	trustLichess := lichTotalGames >= minLichessGames
	out := map[string]Score{}
	keys := map[string]struct{}{}
	for u := range lich {
		keys[u] = struct{}{}
	}
	for u := range maia {
		keys[u] = struct{}{}
	}
	for u := range keys {
		lf := lich[u].Freq
		mp := maia[u]
		var v float64
		switch {
		case trustLichess:
			v = lf
		case maia != nil:
			v = mp
		default:
			if lf > mp {
				v = lf
			} else {
				v = mp
			}
		}
		out[u] = Score{Value: v, LichessFreq: lf, MaiaProb: mp}
	}
	return out
}
