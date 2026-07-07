// Package maia scores how plausible each legal move is for a human at a
// given rating band, using lc0 running a Maia network as a policy-only
// (nodes 1) search. Maia's policy head approximates "what a human at this
// rating would actually play" — the plausibility half of the punish-corpus
// signal, alongside stockfish's severity/refutation signal.
package maia

import (
	"context"
	"regexp"
	"strconv"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/bands"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/uci"
)

// Scorer drives one or more lc0+Maia engines (one per net) to estimate
// per-move plausibility for a position.
type Scorer struct {
	// engineFor returns the lc0 Engine already configured with a given net's
	// WeightsFile. Supplied by the pipeline; may be nil for the
	// beginner-only path (BandProbs never calls it when a band has no maia
	// nets).
	engineFor func(net string) uci.Engine
}

// New builds a Scorer over engineFor. engineFor may be nil if the caller
// only ever queries bands with no maia nets (e.g. beginner).
func New(engineFor func(net string) uci.Engine) *Scorer {
	return &Scorer{engineFor: engineFor}
}

// policyRe matches lc0's policy-head "info string <uci-move>  (P: xx.xx%)"
// lines. lc0's exact info-string format has varied across versions, so all
// parsing is isolated here and unit-tested against a captured sample rather
// than depended on elsewhere.
var policyRe = regexp.MustCompile(`info string (\S+)\s+\(P:\s*([0-9.]+)%\)`)

// parseMaiaPolicy extracts the per-move policy probability (as a fraction,
// i.e. percent/100) from raw lc0 output lines. Lines that don't match the
// expected shape (including "bestmove ...") are ignored.
func parseMaiaPolicy(lines []string) map[string]float64 {
	out := map[string]float64{}
	for _, l := range lines {
		m := policyRe.FindStringSubmatch(l)
		if m == nil {
			continue
		}
		if v, err := strconv.ParseFloat(m[2], 64); err == nil {
			out[m[1]] = v / 100.0
		}
	}
	return out
}

// Probs runs lc0 policy-only (nodes 1) at fen with the given maia net and
// returns the per-legal-move plausibility (fraction).
func (s *Scorer) Probs(ctx context.Context, fen, net string) (map[string]float64, error) {
	eng := s.engineFor(net)
	raw, err := eng.RawGo(ctx, fen, "nodes 1")
	if err != nil {
		return nil, err
	}
	return parseMaiaPolicy(raw), nil
}

// BandProbs averages per-move plausibility across all of the band's maia
// nets. A band with no maia nets (beginner) returns nil, err == nil without
// touching the engine at all — nil is the "no maia signal for this band"
// sentinel the pipeline checks for.
func (s *Scorer) BandProbs(ctx context.Context, fen string, b bands.Band) (map[string]float64, error) {
	nets := bands.MaiaNets(b)
	if len(nets) == 0 {
		return nil, nil
	}

	sum := map[string]float64{}
	for _, net := range nets {
		p, err := s.Probs(ctx, fen, net)
		if err != nil {
			return nil, err
		}
		for uciMove, prob := range p {
			sum[uciMove] += prob / float64(len(nets))
		}
	}
	return sum, nil
}
