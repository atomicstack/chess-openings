package uci

import "context"

var _ Engine = (*Fake)(nil)

// Fake returns canned analysis keyed by FEN; used by stockfish/maia unit tests.
type Fake struct {
	Options   map[string]string
	Script    map[string][]Line   // fen -> ranked lines, for Analyse
	RawScript map[string][]string // fen -> canned raw engine lines, for RawGo
}

func NewFake() *Fake {
	return &Fake{
		Options:   map[string]string{},
		Script:    map[string][]Line{},
		RawScript: map[string][]string{},
	}
}

func (f *Fake) SetOption(name, value string) error { f.Options[name] = value; return nil }
func (f *Fake) IsReady() error                     { return nil }
func (f *Fake) Analyse(_ context.Context, fen string, _, _ int) ([]Line, error) {
	return f.Script[fen], nil
}
func (f *Fake) RawGo(_ context.Context, fen, _ string) ([]string, error) {
	return f.RawScript[fen], nil
}
