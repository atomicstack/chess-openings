package maia

import (
	"context"
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/bands"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/uci"
)

func TestParseMaiaPolicy_ExtractsPerMoveP(t *testing.T) {
	sample := []string{
		"info string e2e4  (P: 45.20%) N: 1",
		"info string d2d4  (P: 30.10%) N: 1",
		"info string g1f3  (P: 10.00%) N: 1",
		"bestmove e2e4",
	}
	p := parseMaiaPolicy(sample)
	if len(p) != 3 {
		t.Fatalf("want 3 moves, got %d", len(p))
	}
	if got := p["e2e4"]; got < 0.45 || got > 0.46 {
		t.Errorf("e2e4 P = %.3f, want ~0.452", got)
	}
}

func TestBandProbs_BeginnerHasNoMaia(t *testing.T) {
	s := New(nil) // beginner path must not touch the engine
	got, err := s.BandProbs(nil, "fen", "beginner")
	if err != nil {
		t.Fatal(err)
	}
	if got != nil {
		t.Errorf("beginner should yield nil maia probs, got %v", got)
	}
}

func TestBandProbs_AveragesAcrossBandNets(t *testing.T) {
	fen := "fen"

	net1500 := uci.NewFake()
	net1500.RawScript[fen] = []string{
		"info string e2e4  (P: 40.00%) N: 1",
		"bestmove e2e4",
	}
	net1700 := uci.NewFake()
	net1700.RawScript[fen] = []string{
		"info string e2e4  (P: 60.00%) N: 1",
		"bestmove e2e4",
	}

	engines := map[string]uci.Engine{
		"maia-1500": net1500,
		"maia-1700": net1700,
	}
	s := New(func(net string) uci.Engine { return engines[net] })

	got, err := s.BandProbs(context.Background(), fen, bands.Advanced)
	if err != nil {
		t.Fatal(err)
	}
	if got == nil {
		t.Fatal("want non-nil averaged probs for advanced band")
	}
	if p := got["e2e4"]; p < 0.499 || p > 0.501 {
		t.Errorf("e2e4 averaged P = %.3f, want ~0.5 (average of 0.40 and 0.60)", p)
	}
}
