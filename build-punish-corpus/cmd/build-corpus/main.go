package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/corpus"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/pipeline"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/progress"
)

func main() {
	os.Exit(run())
}

// run does the real work and returns a process exit code, so main itself
// stays a one-liner and defers (cleanup, file close) actually fire before
// the process exits.
func run() int {
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
		return 2
	}
	fmt.Fprintf(os.Stderr, "loaded config: workers=%d depth=%d\n", cfg.Workers, cfg.StockfishDepth)

	progW, closeProgW, err := progressWriter(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "progress output error: %v\n", err)
		return 1
	}
	defer closeProgW()
	prog := progress.New(progW)

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	dep, cleanup, err := buildRealDeps(ctx, cfg, prog)
	if err != nil {
		fmt.Fprintf(os.Stderr, "init error: %v\n", err)
		return 1
	}
	defer cleanup()

	c, err := pipeline.Run(ctx, cfg, dep)
	if err != nil {
		fmt.Fprintf(os.Stderr, "run error: %v\n", err)
		return 1
	}

	body, err := corpus.Marshal(c)
	if err != nil {
		fmt.Fprintf(os.Stderr, "marshal error: %v\n", err)
		return 1
	}
	if err := os.WriteFile(cfg.OutputPath, body, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write error: %v\n", err)
		return 1
	}

	fmt.Fprintf(os.Stderr, "wrote %s (%d positions)\n", cfg.OutputPath, len(c.Positions))
	return 0
}

// progressWriter resolves cfg.ProgressPath to an io.Writer: "" means stderr
// (no file to close), otherwise a created/truncated file. The returned close
// func is always safe to defer unconditionally.
func progressWriter(cfg config.Config) (io.Writer, func(), error) {
	if cfg.ProgressPath == "" {
		return os.Stderr, func() {}, nil
	}
	fl, err := os.Create(cfg.ProgressPath)
	if err != nil {
		return nil, nil, err
	}
	return fl, func() { fl.Close() }, nil
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
