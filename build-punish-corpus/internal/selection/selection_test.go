package selection

import (
	"reflect"
	"testing"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
)

func cfg() config.Config {
	c := config.Default()
	c.MinEvalDropCp = 150
	c.MaxEvalDropCp = 900
	c.MinPlausibility = 0.05
	c.MaxBlundersPerPosition = 3
	return c
}

func TestSelect_DropsBelowSeverity(t *testing.T) {
	got := Select([]Raw{{MoveUCI: "a2a3", Drop: 100, PerBand: map[string]float64{"beginner": 0.4}}}, cfg())
	if len(got) != 0 {
		t.Errorf("100cp drop should be gated out, got %+v", got)
	}
}

func TestSelect_DropsSelfImmolation(t *testing.T) {
	got := Select([]Raw{{MoveUCI: "d1h5", Drop: 1500, PerBand: map[string]float64{"beginner": 0.4}}}, cfg())
	if len(got) != 0 {
		t.Errorf("1500cp hang should be gated out, got %+v", got)
	}
}

func TestSelect_TagsQualifyingBandsAndCaps(t *testing.T) {
	raw := []Raw{
		{MoveUCI: "f6g4", Drop: 300, PerBand: map[string]float64{"beginner": 0.2, "expert": 0.01}},
		{MoveUCI: "f8b4", Drop: 250, PerBand: map[string]float64{"intermediate": 0.1}},
		{MoveUCI: "h7h6", Drop: 200, PerBand: map[string]float64{"beginner": 0.06}},
		{MoveUCI: "a7a6", Drop: 180, PerBand: map[string]float64{"advanced": 0.08}},
	}
	got := Select(raw, cfg())
	if len(got) != 3 {
		t.Fatalf("cap should keep 3, got %d", len(got))
	}
	// f6g4 keeps only beginner (expert 0.01 < 0.05) and ranks first (0.2*300 highest).
	if got[0].MoveUCI != "f6g4" || len(got[0].Bands) != 1 || got[0].Bands[0] != "beginner" {
		t.Errorf("top candidate wrong: %+v", got[0])
	}
}

func TestSelect_KeepsBoundaryDrops(t *testing.T) {
	// gate is Drop < Min || Drop > Max (exclusive), so boundary values must be kept.
	// min boundary: drop == 150.
	got := Select([]Raw{{MoveUCI: "e2e4", Drop: 150, PerBand: map[string]float64{"beginner": 0.4}}}, cfg())
	if len(got) != 1 {
		t.Errorf("drop == min (150) should be kept, got %d candidates", len(got))
	}
	// max boundary: drop == 900.
	got = Select([]Raw{{MoveUCI: "d1h5", Drop: 900, PerBand: map[string]float64{"beginner": 0.4}}}, cfg())
	if len(got) != 1 {
		t.Errorf("drop == max (900) should be kept, got %d candidates", len(got))
	}
}

func TestSelect_MultiBandDeterministicOrder(t *testing.T) {
	raw := []Raw{{
		MoveUCI: "c3e4",
		Drop:    300,
		PerBand: map[string]float64{"beginner": 0.3, "intermediate": 0.2, "advanced": 0.1},
	}}
	got := Select(raw, cfg())
	if len(got) != 1 {
		t.Fatalf("expected 1 candidate, got %d", len(got))
	}
	expected := []string{"beginner", "intermediate", "advanced"}
	if !reflect.DeepEqual(got[0].Bands, expected) {
		t.Errorf("bands should be %v (bands.All() order), got %v", expected, got[0].Bands)
	}
	if got[0].Plaus != 0.3 {
		t.Errorf("plaus should be 0.3 (max qualifying), got %f", got[0].Plaus)
	}
}
