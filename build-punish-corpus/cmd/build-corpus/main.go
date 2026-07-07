package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
)

func main() {
	var (
		cfgPath  = flag.String("config", "", "path to json config")
		workers  = flag.Int("workers", 0, "worker count (0 => config/default)")
		openings = flag.String("openings", "", "path to openings.json (overrides config)")
		out      = flag.String("out", "", "output corpus path (overrides config)")
	)
	flag.Parse()

	f := config.Flags{}
	if isFlagSet("workers") {
		f.Workers = workers
	}
	if isFlagSet("openings") {
		f.OpeningsJSONPath = openings
	}
	if isFlagSet("out") {
		f.OutputPath = out
	}

	cfg, err := config.Load(f, *cfgPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(2)
	}
	fmt.Fprintf(os.Stderr, "loaded config: workers=%d depth=%d\n", cfg.Workers, cfg.StockfishDepth)
	// Task 13 replaces this with pipeline.Run(cfg).
}

func isFlagSet(name string) bool {
	set := false
	flag.Visit(func(fl *flag.Flag) {
		if fl.Name == name {
			set = true
		}
	})
	return set
}
