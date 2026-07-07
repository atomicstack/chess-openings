package config

import "testing"

func TestLoad_DefaultsWhenNoJSONOrFlags(t *testing.T) {
	c, err := Load(Flags{}, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if c.Workers <= 0 {
		t.Errorf("workers should default > 0, got %d", c.Workers)
	}
	if c.MaxBlundersPerPosition != 5 {
		t.Errorf("maxBlunders default = %d, want 5", c.MaxBlundersPerPosition)
	}
	if c.MultiPV < 1 {
		t.Errorf("multiPV default = %d, want >= 1", c.MultiPV)
	}
}

func TestLoad_FlagOverridesJSON(t *testing.T) {
	dir := t.TempDir()
	p := dir + "/c.json"
	if err := writeFile(p, `{"workers": 2, "stockfishDepth": 18}`); err != nil {
		t.Fatal(err)
	}
	w := 7
	c, err := Load(Flags{Workers: &w}, p)
	if err != nil {
		t.Fatal(err)
	}
	if c.Workers != 7 {
		t.Errorf("flag should override json: got workers=%d, want 7", c.Workers)
	}
	if c.StockfishDepth != 18 {
		t.Errorf("json value lost: got depth=%d, want 18", c.StockfishDepth)
	}
}
