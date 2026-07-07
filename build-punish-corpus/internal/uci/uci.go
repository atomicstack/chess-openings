package uci

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strconv"
	"strings"
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

func next(t []string, i int) string  { return nextN(t, i, 1) }
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

// Process is the real os/exec-backed engine.
type Process struct {
	cmd *exec.Cmd
	in  *bufio.Writer
	out *bufio.Scanner
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
	p := &Process{cmd: cmd, in: bufio.NewWriter(stdin), out: bufio.NewScanner(stdout)}
	p.out.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	if err := p.send("uci"); err != nil {
		return nil, err
	}
	if err := p.readUntil("uciok"); err != nil {
		return nil, err
	}
	return p, nil
}

func (p *Process) send(s string) error {
	if _, err := p.in.WriteString(s + "\n"); err != nil {
		return err
	}
	return p.in.Flush()
}

func (p *Process) readUntil(prefix string) error {
	for p.out.Scan() {
		if strings.HasPrefix(p.out.Text(), prefix) {
			return nil
		}
	}
	return fmt.Errorf("engine closed before %q", prefix)
}

func (p *Process) SetOption(name, value string) error {
	return p.send(fmt.Sprintf("setoption name %s value %s", name, value))
}

func (p *Process) IsReady() error {
	if err := p.send("isready"); err != nil {
		return err
	}
	return p.readUntil("readyok")
}

func (p *Process) Analyse(ctx context.Context, fen string, depth, multiPV int) ([]Line, error) {
	if err := p.send("position fen " + fen); err != nil {
		return nil, err
	}
	if err := p.send(fmt.Sprintf("go depth %d", depth)); err != nil {
		return nil, err
	}
	var stream []string
	for p.out.Scan() {
		txt := p.out.Text()
		stream = append(stream, txt)
		if strings.HasPrefix(txt, "bestmove") {
			break
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
	}
	return collectAnalysis(stream, multiPV), nil
}

func (p *Process) Close() error {
	_ = p.send("quit")
	return p.cmd.Wait()
}
