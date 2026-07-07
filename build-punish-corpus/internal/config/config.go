package config

import (
	"encoding/json"
	"os"
	"runtime"
)

// Config is the fully-resolved run configuration. All thresholds live here so
// tuning never touches logic (spec TODO #6).
type Config struct {
	// paths
	OpeningsJSONPath string `json:"openingsJsonPath"`
	OutputPath       string `json:"outputPath"`
	StockfishPath    string `json:"stockfishPath"`
	Lc0Path          string `json:"lc0Path"`
	MaiaWeightsDir   string `json:"maiaWeightsDir"`
	LichessCacheDir  string `json:"lichessCacheDir"`
	ProgressPath     string `json:"progressPath"` // "" => stderr

	// concurrency / engine
	Workers        int `json:"workers"`
	HashMB         int `json:"hashMB"`
	StockfishDepth int `json:"stockfishDepth"`
	MultiPV        int `json:"multiPV"`

	// severity gate & selection
	MinEvalDropCp          int `json:"minEvalDropCp"`
	MaxEvalDropCp          int `json:"maxEvalDropCp"`
	WinThresholdCp         int `json:"winThresholdCp"`
	MaxBlundersPerPosition int `json:"maxBlundersPerPosition"`

	// plausibility
	MinLichessGames int     `json:"minLichessGames"` // fallback threshold to trust lichess over maia
	MinPlausibility float64 `json:"minPlausibility"` // drop candidates below this blended prob
}

// Flags holds only the CLI-overridable subset; nil pointer => not set.
type Flags struct {
	Workers          *int
	ConfigPath       string
	OpeningsJSONPath *string
	OutputPath       *string
}

func Default() Config {
	return Config{
		OpeningsJSONPath:       "../Chess Openings/Resources/openings.json",
		OutputPath:             "punish-corpus.json",
		LichessCacheDir:        ".lichess-cache",
		Workers:                runtime.NumCPU(),
		HashMB:                 128,
		StockfishDepth:         22,
		MultiPV:                20,
		MinEvalDropCp:          150,
		MaxEvalDropCp:          900,
		WinThresholdCp:         150,
		MaxBlundersPerPosition: 5,
		MinLichessGames:        50,
		MinPlausibility:        0.02,
	}
}

// Load merges defaults <- json file <- flags (later wins).
func Load(f Flags, jsonPath string) (Config, error) {
	c := Default()
	if jsonPath != "" {
		b, err := os.ReadFile(jsonPath)
		if err != nil {
			return Config{}, err
		}
		if err := json.Unmarshal(b, &c); err != nil { // only present keys overwrite
			return Config{}, err
		}
	}
	if f.Workers != nil {
		c.Workers = *f.Workers
	}
	if f.OpeningsJSONPath != nil {
		c.OpeningsJSONPath = *f.OpeningsJSONPath
	}
	if f.OutputPath != nil {
		c.OutputPath = *f.OutputPath
	}
	if c.Workers < 1 {
		c.Workers = 1
	}
	return c, nil
}

func writeFile(p, s string) error { return os.WriteFile(p, []byte(s), 0o644) }
