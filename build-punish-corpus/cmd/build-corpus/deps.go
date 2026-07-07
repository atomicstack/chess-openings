package main

import (
	"context"
	"fmt"
	"net/http"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/bands"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/config"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/lichess"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/maia"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/pipeline"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/plausibility"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/progress"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/stockfish"
	"github.com/mattkoscica/chess-openings/build-punish-corpus/internal/uci"
)

// lichessBaseURL is the real Lichess opening-explorer host. lichess.Client
// appends "/lichess" itself (see internal/lichess), which matches the real
// explorer's "lichess games" endpoint (as opposed to "/masters" or
// "/player"), so base must be the bare host.
const lichessBaseURL = "https://explorer.lichess.ovh"

// maiaWeightsFile is the assumed on-disk naming convention for a maia net's
// weights file. No convention existed anywhere else in the repo (config
// only carries the containing directory), so this picks the common maia
// distribution naming (e.g. "maia-1100.pb.gz") and isolates the assumption
// to one place should it need correcting once real weights files are in
// hand.
func maiaWeightsFile(cfg config.Config, net string) string {
	return filepath.Join(cfg.MaiaWeightsDir, net+".pb.gz")
}

// buildRealDeps constructs the production pipeline.Deps: a pooled Stockfish
// severity/refutation adapter, a lichess.Client, and a pooled maia.Scorer,
// wired behind the pipeline.Sev/pipeline.Plaus interfaces. The returned
// cleanup func closes every pooled engine and must be called (via defer)
// once pipeline.Run has returned.
//
// ctx MUST be cancellable (e.g. the run's signal.NotifyContext context), NOT
// context.Background() — every pooled uci.Process is constructed with ctx,
// and Process.IsReady()'s cancellability is bound to whatever context it was
// constructed with (IsReady has no per-call ctx parameter on the Engine
// interface).
func buildRealDeps(ctx context.Context, cfg config.Config, prog *progress.Emitter) (pipeline.Deps, func(), error) {
	sevPool, err := newEnginePool(ctx, cfg.Workers, func() (*uci.Process, error) {
		return newStockfishProcess(ctx, cfg)
	})
	if err != nil {
		return pipeline.Deps{}, nil, fmt.Errorf("stockfish pool: %w", err)
	}

	nets := unionMaiaNets()
	netPools := make(map[string]*enginePool, len(nets))
	for _, net := range nets {
		net := net
		p, err := newEnginePool(ctx, cfg.Workers, func() (*uci.Process, error) {
			return newMaiaProcess(ctx, cfg, net)
		})
		if err != nil {
			sevPool.closeAll()
			for _, existing := range netPools {
				existing.closeAll()
			}
			return pipeline.Deps{}, nil, fmt.Errorf("maia pool %s: %w", net, err)
		}
		netPools[net] = p
	}

	cleanup := func() {
		sevPool.closeAll()
		for _, p := range netPools {
			p.closeAll()
		}
	}

	sev := &poolSev{pool: sevPool, depth: cfg.StockfishDepth, multiPV: cfg.MultiPV}

	httpClient := &http.Client{Timeout: 30 * time.Second}
	lichClient := lichess.NewClient(lichessBaseURL, cfg.LichessCacheDir, httpClient)

	scorer := maia.New(func(net string) uci.Engine {
		p, ok := netPools[net]
		if !ok {
			return failingEngine{err: fmt.Errorf("no engine pool configured for maia net %q", net)}
		}
		proc, err := p.checkout(ctx)
		if err != nil {
			return failingEngine{err: err}
		}
		return &releasingEngine{proc: proc, pool: p}
	})

	plaus := &plausAdapter{lich: lichClient, maia: scorer, cfg: cfg, cache: map[string]bandSignals{}}

	return pipeline.Deps{Sev: sev, Plaus: plaus, Progress: prog}, cleanup, nil
}

// unionMaiaNets returns every maia net referenced by any band, so a single
// pool-per-net set covers whichever band plausAdapter.PerBand ends up
// querying.
func unionMaiaNets() []string {
	seen := map[string]struct{}{}
	var out []string
	for _, b := range bands.All() {
		for _, n := range bands.MaiaNets(b) {
			if _, ok := seen[n]; !ok {
				seen[n] = struct{}{}
				out = append(out, n)
			}
		}
	}
	return out
}

func newStockfishProcess(ctx context.Context, cfg config.Config) (*uci.Process, error) {
	proc, err := uci.NewProcess(ctx, cfg.StockfishPath)
	if err != nil {
		return nil, err
	}
	if err := proc.SetOption("Threads", "1"); err != nil {
		proc.Close()
		return nil, err
	}
	if err := proc.SetOption("Hash", strconv.Itoa(cfg.HashMB)); err != nil {
		proc.Close()
		return nil, err
	}
	if err := proc.IsReady(); err != nil {
		proc.Close()
		return nil, err
	}
	return proc, nil
}

func newMaiaProcess(ctx context.Context, cfg config.Config, net string) (*uci.Process, error) {
	proc, err := uci.NewProcess(ctx, cfg.Lc0Path)
	if err != nil {
		return nil, err
	}
	if err := proc.SetOption("WeightsFile", maiaWeightsFile(cfg, net)); err != nil {
		proc.Close()
		return nil, err
	}
	if err := proc.IsReady(); err != nil {
		proc.Close()
		return nil, err
	}
	return proc, nil
}

// enginePool is a bounded, error-aware pool of ready uci.Process instances,
// shared across the errgroup's worker goroutines.
//
// Engine-reuse contract (see internal/uci.Process's doc comment): once any
// Analyse/RawGo/IsReady call on a Process returns a non-nil error — including
// a ctx cancellation error — that Process is dead and must never be reused.
// release(p, healthy) enforces this: healthy=false closes p and best-effort
// spawns a fresh replacement rather than returning p to the channel.
//
// checkout selects on ctx.Done() as well as the channel receive so that if
// the pool ever runs dry (every spawn attempt after a dead engine failed),
// blocked callers unblock via context cancellation instead of deadlocking
// forever; errgroup.WithContext cancels ctx as soon as any worker returns an
// error, which is exactly when a pool could plausibly run dry.
type enginePool struct {
	spawn func() (*uci.Process, error)
	ch    chan *uci.Process
}

func newEnginePool(ctx context.Context, size int, spawn func() (*uci.Process, error)) (*enginePool, error) {
	if size < 1 {
		size = 1
	}
	p := &enginePool{spawn: spawn, ch: make(chan *uci.Process, size)}
	for i := 0; i < size; i++ {
		e, err := spawn()
		if err != nil {
			p.closeAll()
			return nil, err
		}
		p.ch <- e
	}
	return p, nil
}

func (p *enginePool) checkout(ctx context.Context) (*uci.Process, error) {
	select {
	case e := <-p.ch:
		return e, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

// release returns e to the pool when healthy is true (its last query
// succeeded). When healthy is false, e is dead per the reuse contract: it is
// closed and, best-effort, replaced with a freshly spawned engine so the
// pool doesn't shrink on every single-engine failure. If the replacement
// spawn also fails, the pool is simply one engine short — checkout(ctx)
// still terminates via ctx.Done() rather than hanging forever.
func (p *enginePool) release(e *uci.Process, healthy bool) {
	if healthy {
		p.ch <- e
		return
	}
	_ = e.Close()
	if fresh, err := p.spawn(); err == nil {
		p.ch <- fresh
	}
}

// closeAll drains and closes every engine currently sitting in the pool.
// Must only be called once every checked-out engine has been released back
// (i.e. after the run's errgroup.Wait has returned) — closeAll does not wait
// for outstanding checkouts.
func (p *enginePool) closeAll() {
	close(p.ch)
	for e := range p.ch {
		_ = e.Close()
	}
}

// poolSev adapts a pooled Stockfish enginePool to pipeline.Sev. Each call
// checks an engine out, wraps it in a fresh *stockfish.Analyzer (cheap: it's
// just a struct holding the engine/depth/multiPV, no engine state), runs the
// query, and releases the engine — healthy or not — per the reuse contract.
type poolSev struct {
	pool           *enginePool
	depth, multiPV int
}

func (s *poolSev) Severity(ctx context.Context, slotFEN, bookUCI, candUCI string) (stockfish.EvalDrop, error) {
	proc, err := s.pool.checkout(ctx)
	if err != nil {
		return stockfish.EvalDrop{}, err
	}
	drop, err := stockfish.New(proc, s.depth, s.multiPV).Severity(ctx, slotFEN, bookUCI, candUCI)
	s.pool.release(proc, err == nil)
	return drop, err
}

func (s *poolSev) Refute(ctx context.Context, postFEN string) (stockfish.Refutation, error) {
	proc, err := s.pool.checkout(ctx)
	if err != nil {
		return stockfish.Refutation{}, err
	}
	ref, err := stockfish.New(proc, s.depth, s.multiPV).Refute(ctx, postFEN)
	s.pool.release(proc, err == nil)
	return ref, err
}

// releasingEngine wraps a single checked-out *uci.Process for exactly the
// one call maia.Scorer.Probs makes against it (engineFor -> one RawGo),
// releasing it back to its pool (or discarding it per the reuse contract)
// as soon as that call returns.
//
// Only RawGo releases the engine — that is the sole method
// maia.Scorer.Probs actually calls on the value engineFor hands back
// (engineFor -> exactly one RawGo, never SetOption/IsReady/Analyse). Wiring
// release into every method would be wrong: if a future caller ever chained
// two calls on the same releasingEngine (e.g. SetOption then RawGo),
// releasing after the first would return the still-in-use *uci.Process to
// the pool, letting a second goroutine check it out and use it concurrently
// with the first. SetOption/IsReady/Analyse are therefore plain delegates
// with no pool interaction, which is safe (worst case, an engine used only
// through them is never released back to the pool — a leak, not a race) —
// unreachable in the current call graph but forward-compatible if that
// changes.
type releasingEngine struct {
	proc *uci.Process
	pool *enginePool
}

func (r *releasingEngine) SetOption(name, value string) error {
	return r.proc.SetOption(name, value)
}

func (r *releasingEngine) IsReady() error {
	return r.proc.IsReady()
}

func (r *releasingEngine) Analyse(ctx context.Context, fen string, depth, multiPV int) ([]uci.Line, error) {
	return r.proc.Analyse(ctx, fen, depth, multiPV)
}

func (r *releasingEngine) RawGo(ctx context.Context, fen, goArgs string) ([]string, error) {
	out, err := r.proc.RawGo(ctx, fen, goArgs)
	r.pool.release(r.proc, err == nil)
	return out, err
}

// failingEngine is returned by engineFor when a pool checkout fails (e.g.
// ctx cancelled while waiting). maia.Scorer's engineFor signature has no
// error return, so the failure is deferred to the first call any Engine
// method makes.
type failingEngine struct{ err error }

func (f failingEngine) SetOption(string, string) error { return f.err }
func (f failingEngine) IsReady() error                 { return f.err }
func (f failingEngine) Analyse(context.Context, string, int, int) ([]uci.Line, error) {
	return nil, f.err
}
func (f failingEngine) RawGo(context.Context, string, string) ([]string, error) {
	return nil, f.err
}

// bandSignals is the raw lichess+maia data behind one (fen, band) pair,
// cached by plausAdapter so a slot's O(legal moves) PerBand calls at the
// same fen don't each refetch the whole per-move lichess/maia distribution
// just to read out one move's entry.
type bandSignals struct {
	lich  map[string]lichess.MoveStat
	total int
	maia  map[string]float64
}

// plausAdapter adapts lichess.Client + maia.Scorer + plausibility.Blend to
// pipeline.Plaus. It loops bands.All(), fetching (and caching) each band's
// full move-distribution once per fen, then blends and reads out the one
// candidate the caller asked about.
type plausAdapter struct {
	lich *lichess.Client
	maia *maia.Scorer
	cfg  config.Config

	mu    sync.Mutex
	cache map[string]bandSignals // key: fen + "|" + band
}

func (p *plausAdapter) signalsFor(ctx context.Context, fen string, b bands.Band) (bandSignals, error) {
	key := fen + "|" + string(b)

	p.mu.Lock()
	if s, ok := p.cache[key]; ok {
		p.mu.Unlock()
		return s, nil
	}
	p.mu.Unlock()

	lich, err := p.lich.Moves(ctx, fen, bands.LichessBucket(b))
	if err != nil {
		return bandSignals{}, fmt.Errorf("lichess moves (%s): %w", b, err)
	}
	total := 0
	for _, st := range lich {
		total += st.Games
	}
	maiaProbs, err := p.maia.BandProbs(ctx, fen, b)
	if err != nil {
		return bandSignals{}, fmt.Errorf("maia bandProbs (%s): %w", b, err)
	}

	s := bandSignals{lich: lich, total: total, maia: maiaProbs}
	p.mu.Lock()
	p.cache[key] = s
	p.mu.Unlock()
	return s, nil
}

func (p *plausAdapter) PerBand(ctx context.Context, fen, candUCI string) (map[string]float64, map[string]map[string]float64, error) {
	perBand := map[string]float64{}
	meta := map[string]map[string]float64{}
	for _, b := range bands.All() {
		s, err := p.signalsFor(ctx, fen, b)
		if err != nil {
			return nil, nil, err
		}
		blended := plausibility.Blend(s.lich, s.total, s.maia, p.cfg.MinLichessGames)
		sc, ok := blended[candUCI]
		if !ok {
			continue
		}
		perBand[string(b)] = sc.Value
		meta[string(b)] = map[string]float64{
			"lichessFreq":  sc.LichessFreq,
			"maiaProb":     sc.MaiaProb,
			"lichessGames": float64(s.total),
		}
	}
	return perBand, meta, nil
}
