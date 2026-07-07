package corpus

import (
	"bytes"
	"encoding/json"
	"sort"
)

type Move struct {
	SAN string `json:"san"`
	UCI string `json:"uci"`
}

type Refutation struct {
	PV          []Move `json:"pv"`
	EvalAfterCp int    `json:"evalAfterCp"`
	MateIn      *int   `json:"mateIn"`
}

type Blunder struct {
	Move       Move                          `json:"move"`
	EvalDropCp int                           `json:"evalDropCp"`
	Bands      []string                      `json:"bands"`
	Plaus      map[string]map[string]float64 `json:"plausibility"`
	Refutation Refutation                    `json:"refutation"`
	Lines      []string                      `json:"lines"`
}

type Position struct {
	OpponentSide string    `json:"opponentSide"`
	BookMove     Move      `json:"bookMove"`
	Blunders     []Blunder `json:"blunders"`
}

type Provenance struct {
	Stockfish         string   `json:"stockfish"`
	Depth             int      `json:"depth"`
	MultiPV           int      `json:"multipv"`
	MaiaNets          []string `json:"maiaNets"`
	LichessBuckets    []int    `json:"lichessBuckets"`
	SourceSeedVersion int      `json:"sourceSeedVersion"`
}

type Corpus struct {
	Version    int                 `json:"version"`
	Provenance Provenance          `json:"provenance"`
	Positions  map[string]Position `json:"positions"`
}

type PositionEntry struct {
	NormFEN      string
	OpponentSide string
	BookMove     Move
	Blunders     []Blunder
}

type Builder struct {
	prov Provenance
	pos  map[string]Position
}

func NewBuilder() *Builder { return &Builder{pos: map[string]Position{}} }

func (b *Builder) SetProvenance(p Provenance) { b.prov = p }

func (b *Builder) Add(e PositionEntry) {
	cur, ok := b.pos[e.NormFEN]
	if !ok {
		b.pos[e.NormFEN] = Position{OpponentSide: e.OpponentSide, BookMove: e.BookMove, Blunders: e.Blunders}
		return
	}
	idx := map[string]int{}
	for i, bl := range cur.Blunders {
		idx[bl.Move.UCI] = i
	}
	for _, bl := range e.Blunders {
		if i, seen := idx[bl.Move.UCI]; seen {
			cur.Blunders[i].Lines = union(cur.Blunders[i].Lines, bl.Lines)
			cur.Blunders[i].Bands = union(cur.Blunders[i].Bands, bl.Bands)
		} else {
			idx[bl.Move.UCI] = len(cur.Blunders)
			cur.Blunders = append(cur.Blunders, bl)
		}
	}
	b.pos[e.NormFEN] = cur
}

func (b *Builder) Build() Corpus {
	return Corpus{Version: 1, Provenance: b.prov, Positions: b.pos}
}

func union(a, b []string) []string {
	seen := map[string]struct{}{}
	for _, s := range a {
		seen[s] = struct{}{}
	}
	for _, s := range b {
		seen[s] = struct{}{}
	}
	out := make([]string, 0, len(seen))
	for s := range seen {
		out = append(out, s)
	}
	sort.Strings(out)
	return out
}

// Marshal emits deterministic JSON: sorted position keys, sorted blunders (by
// move uci), sorted bands/lines. json.Marshal already sorts map keys, so the
// per-blunder plausibility map is stable; we only need to sort slices.
func Marshal(c Corpus) ([]byte, error) {
	for k, p := range c.Positions {
		sort.Slice(p.Blunders, func(i, j int) bool { return p.Blunders[i].Move.UCI < p.Blunders[j].Move.UCI })
		for i := range p.Blunders {
			sort.Strings(p.Blunders[i].Bands)
			sort.Strings(p.Blunders[i].Lines)
		}
		c.Positions[k] = p
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(c); err != nil { // map keys sorted by encoder
		return nil, err
	}
	return buf.Bytes(), nil
}
