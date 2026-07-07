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
		cur = Position{OpponentSide: e.OpponentSide, BookMove: e.BookMove}
	} else if e.BookMove.UCI < cur.BookMove.UCI {
		// Resolve competing book continuations deterministically (independent of
		// which worker's Add landed first): the lexicographically smaller move
		// uci always wins. A v1 simplification — deterministic beats
		// lossy-but-random when sibling lines diverge at a transposition.
		cur.BookMove = e.BookMove
	}
	// Route both the first-insert and subsequent-insert paths through the
	// same merge-by-move logic so blunders sharing a move uci (whether
	// arriving in this call or a prior one) get deduped identically:
	// order-insensitive scalar resolution, union lines/bands.
	idx := map[string]int{}
	for i, bl := range cur.Blunders {
		idx[bl.Move.UCI] = i
	}
	for _, bl := range e.Blunders {
		if i, seen := idx[bl.Move.UCI]; seen {
			cur.Blunders[i] = mergeBlunder(cur.Blunders[i], bl)
		} else {
			idx[bl.Move.UCI] = len(cur.Blunders)
			cur.Blunders = append(cur.Blunders, bl)
		}
	}
	b.pos[e.NormFEN] = cur
}

// mergeBlunder combines two entries for the SAME move uci order-insensitively:
// the scalar fields (EvalDropCp, Refutation, Plaus) are taken from whichever
// entry has the smaller EvalDropCp, tie-broken by the smaller
// Refutation.EvalAfterCp, so the result never depends on Add order; Lines and
// Bands are unioned.
func mergeBlunder(a, b Blunder) Blunder {
	winner := a
	if b.EvalDropCp < a.EvalDropCp ||
		(b.EvalDropCp == a.EvalDropCp && b.Refutation.EvalAfterCp < a.Refutation.EvalAfterCp) {
		winner = b
	}
	out := winner
	out.Lines = union(a.Lines, b.Lines)
	out.Bands = union(a.Bands, b.Bands)
	return out
}

func (b *Builder) Build() Corpus {
	// Snapshot the map so a later Add cannot mutate an already-returned
	// Corpus: Positions used to alias the builder's live map directly.
	out := make(map[string]Position, len(b.pos))
	for k, v := range b.pos {
		out[k] = v
	}
	return Corpus{Version: 1, Provenance: b.prov, Positions: out}
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
//
// Marshal builds a normalized copy of c rather than touching the caller's
// slices in place — the schema is frozen for a future Swift Decodable that
// declares non-optional arrays, so every slice field must render as `[]`
// (never `null`) when empty. `Refutation.MateIn` is the sole nullable field.
func Marshal(c Corpus) ([]byte, error) {
	out := Corpus{
		Version:    c.Version,
		Provenance: normalizeProvenance(c.Provenance),
		Positions:  make(map[string]Position, len(c.Positions)),
	}
	for k, p := range c.Positions {
		out.Positions[k] = normalizePosition(p)
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(out); err != nil { // map keys sorted by encoder
		return nil, err
	}
	return buf.Bytes(), nil
}

// copySlice returns an independent copy of s, never nil — nil or empty input
// yields a non-nil empty slice so it marshals as `[]` rather than `null`.
func copySlice[T any](s []T) []T {
	out := make([]T, len(s))
	copy(out, s)
	return out
}

func normalizeProvenance(p Provenance) Provenance {
	p.MaiaNets = copySlice(p.MaiaNets)
	p.LichessBuckets = copySlice(p.LichessBuckets)
	return p
}

func normalizePosition(p Position) Position {
	blunders := copySlice(p.Blunders)
	sort.Slice(blunders, func(i, j int) bool { return blunders[i].Move.UCI < blunders[j].Move.UCI })
	for i := range blunders {
		blunders[i] = normalizeBlunder(blunders[i])
	}
	p.Blunders = blunders
	return p
}

func normalizeBlunder(bl Blunder) Blunder {
	bl.Bands = copySlice(bl.Bands)
	sort.Strings(bl.Bands)
	bl.Lines = copySlice(bl.Lines)
	sort.Strings(bl.Lines)
	if bl.Plaus == nil {
		bl.Plaus = map[string]map[string]float64{}
	}
	// PV is a move sequence — order is meaningful, never sorted.
	bl.Refutation.PV = copySlice(bl.Refutation.PV)
	return bl
}
