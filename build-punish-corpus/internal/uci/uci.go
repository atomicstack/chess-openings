package uci

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"sync"
)

type Line struct {
	Rank    int
	ScoreCp int
	Mate    int
	HasMate bool
	PV      []string
}

type Engine interface {
	SetOption(name, value string) error
	IsReady() error
	Analyse(ctx context.Context, fen string, depth, multiPV int) ([]Line, error)
}

func parseInfoLine(s string) (Line, bool) {
	if !strings.HasPrefix(s, "info ") || !strings.Contains(s, " pv ") {
		return Line{}, false
	}
	tok := strings.Fields(s)
	var l Line
	for i := 0; i < len(tok); i++ {
		switch tok[i] {
		case "multipv":
			l.Rank, _ = strconv.Atoi(next(tok, i))
		case "score":
			switch next(tok, i) {
			case "cp":
				l.ScoreCp, _ = strconv.Atoi(nextN(tok, i, 2))
			case "mate":
				l.HasMate = true
				l.Mate, _ = strconv.Atoi(nextN(tok, i, 2))
			}
		case "pv":
			l.PV = append([]string{}, tok[i+1:]...)
		}
	}
	if l.Rank == 0 {
		l.Rank = 1
	}
	return l, true
}

func next(t []string, i int) string { return nextN(t, i, 1) }
func nextN(t []string, i, n int) string {
	if i+n < len(t) {
		return t[i+n]
	}
	return ""
}

// collectAnalysis keeps, per multipv rank, the deepest (last-seen) line before bestmove.
func collectAnalysis(stream []string, multiPV int) []Line {
	byRank := map[int]Line{}
	for _, s := range stream {
		if strings.HasPrefix(s, "bestmove") {
			break
		}
		if l, ok := parseInfoLine(s); ok && l.Rank <= multiPV {
			byRank[l.Rank] = l // later overwrites earlier => deepest wins
		}
	}
	out := make([]Line, 0, len(byRank))
	for _, l := range byRank {
		out = append(out, l)
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Rank < out[b].Rank })
	return out
}

var _ Engine = (*Process)(nil)

// Process is the real os/exec-backed engine.
//
// Contract: once Analyse, IsReady, or the internal readUntil helper returns a
// non-nil error — including a context error from a caller's cancellation or
// timeout — the Process is dead or in an indeterminate state and MUST NOT be
// reused. the caller must Close() it and, if pooling engines, discard it
// rather than returning it to the pool.
type Process struct {
	cmd   *exec.Cmd
	in    *bufio.Writer
	out   *bufio.Scanner
	lines chan string // fed by readLoop, one uci output line per element
	done  chan struct{}

	// ctx is the context the process was constructed with. IsReady's
	// signature is fixed by the Engine interface (no context parameter), so
	// it reuses this one for its cancellable read.
	ctx context.Context

	teardownOnce sync.Once
	waitErr      error
}

func NewProcess(ctx context.Context, bin string, args ...string) (*Process, error) {
	cmd := exec.CommandContext(ctx, bin, args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}

	p := &Process{
		cmd:   cmd,
		in:    bufio.NewWriter(stdin),
		out:   bufio.NewScanner(stdout),
		lines: make(chan string, 64),
		done:  make(chan struct{}),
		ctx:   ctx,
	}
	p.out.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	go p.readLoop()

	if err := p.send("uci"); err != nil {
		p.kill()
		return nil, err
	}
	if err := p.readUntil(ctx, "uciok"); err != nil {
		p.kill()
		return nil, err
	}
	return p, nil
}

// readLoop pumps scanned stdout lines onto p.lines until the scanner is
// exhausted (engine exited or stdout closed), then closes p.lines so any
// reader waiting on it observes ok == false instead of blocking forever. it
// also selects on p.done so that once the process is torn down, readLoop
// does not sit blocked forever trying to hand off a line nobody will ever
// read again.
func (p *Process) readLoop() {
	defer close(p.lines)
	for p.out.Scan() {
		select {
		case p.lines <- p.out.Text():
		case <-p.done:
			return
		}
	}
}

// nextLine returns the next line read from the engine, ok == false if the
// engine's stdout has closed, or a non-nil error if ctx is done first.
func (p *Process) nextLine(ctx context.Context) (string, bool, error) {
	select {
	case l, ok := <-p.lines:
		return l, ok, nil
	case <-ctx.Done():
		return "", false, ctx.Err()
	}
}

func (p *Process) send(s string) error {
	if _, err := p.in.WriteString(s + "\n"); err != nil {
		return err
	}
	return p.in.Flush()
}

// readUntil blocks until a line with the given prefix arrives, the engine's
// stdout closes, or ctx is done. per the Process contract, a non-nil return
// means the process must not be reused.
func (p *Process) readUntil(ctx context.Context, prefix string) error {
	for {
		line, ok, err := p.nextLine(ctx)
		if err != nil {
			p.kill()
			return err
		}
		if !ok {
			return fmt.Errorf("engine closed before %q", prefix)
		}
		if strings.HasPrefix(line, prefix) {
			return nil
		}
	}
}

func (p *Process) SetOption(name, value string) error {
	return p.send(fmt.Sprintf("setoption name %s value %s", name, value))
}

func (p *Process) IsReady() error {
	if err := p.send("isready"); err != nil {
		return err
	}
	return p.readUntil(p.ctx, "readyok")
}

// Analyse drives one search: it wires multiPV via setoption (so the engine
// actually emits that many ranked "info ... multipv N ..." lines instead of
// just rank 1), then collects lines until "bestmove" or ctx cancellation.
//
// see the Process doc comment for the post-error reuse contract: a non-nil
// error here (including ctx.Err()) means this Process is dead and must be
// Close()'d, never reused.
func (p *Process) Analyse(ctx context.Context, fen string, depth, multiPV int) ([]Line, error) {
	if err := p.SetOption("MultiPV", strconv.Itoa(multiPV)); err != nil {
		return nil, err
	}
	if err := p.send("position fen " + fen); err != nil {
		return nil, err
	}
	if err := p.send(fmt.Sprintf("go depth %d", depth)); err != nil {
		return nil, err
	}

	var stream []string
	for {
		line, ok, err := p.nextLine(ctx)
		if err != nil {
			// best-effort: ask the engine to stop searching before we kill it.
			_ = p.send("stop")
			p.kill()
			return nil, err
		}
		if !ok {
			return nil, fmt.Errorf("engine closed before %q", "bestmove")
		}
		stream = append(stream, line)
		if strings.HasPrefix(line, "bestmove") {
			break
		}
	}
	return collectAnalysis(stream, multiPV), nil
}

// wait reaps the subprocess exactly once, no matter how many times it (or
// kill) is called.
func (p *Process) wait() error {
	p.teardownOnce.Do(func() {
		close(p.done)
		p.waitErr = p.cmd.Wait()
	})
	return p.waitErr
}

// kill force-terminates the subprocess and reaps it. safe to call more than
// once, and safe to call after Close (or vice versa) — the underlying
// os.Process.Kill/cmd.Wait only actually run once.
func (p *Process) kill() {
	_ = p.cmd.Process.Kill()
	_ = p.wait()
}

func (p *Process) Close() error {
	_ = p.send("quit")
	return p.wait()
}
