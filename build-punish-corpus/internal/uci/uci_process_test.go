package uci

import (
	"bufio"
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"
)

// fakeEngine launches this test binary as a subprocess in "helper mode" (see
// TestHelperProcess below), where it behaves like a tiny scripted uci engine.
// This is the standard os/exec "helper process" testing technique: no real
// engine binary is needed, and the subprocess exercises the real NewProcess
// handshake and Process.readLoop plumbing.
func fakeEngine(ctx context.Context, t *testing.T, script string) *Process {
	t.Helper()
	t.Setenv("GO_WANT_HELPER_PROCESS", "1")
	t.Setenv("UCI_HELPER_SCRIPT", script)

	p, err := NewProcess(ctx, os.Args[0], "-test.run=^TestHelperProcess$", "--")
	if err != nil {
		t.Fatalf("start fake engine: %v", err)
	}
	t.Cleanup(func() { _ = p.Close() })
	return p
}

// TestHelperProcess is not a real test: it is exec'd as a subprocess by
// fakeEngine and behaves like a minimal uci engine, scripted by the
// UCI_HELPER_SCRIPT env var. When run normally (without
// GO_WANT_HELPER_PROCESS=1) it is a no-op so it never affects `go test`
// output.
func TestHelperProcess(t *testing.T) {
	if os.Getenv("GO_WANT_HELPER_PROCESS") != "1" {
		return
	}
	defer os.Exit(0)

	script := os.Getenv("UCI_HELPER_SCRIPT")
	in := bufio.NewScanner(os.Stdin)
	out := bufio.NewWriter(os.Stdout)
	send := func(s string) {
		_, _ = out.WriteString(s + "\n")
		_ = out.Flush()
	}

	gotMultiPV := ""
	for in.Scan() {
		cmd := in.Text()
		switch {
		case cmd == "uci":
			send("uciok")
		case cmd == "isready":
			send("readyok")
		case strings.HasPrefix(cmd, "setoption name MultiPV value "):
			gotMultiPV = strings.TrimPrefix(cmd, "setoption name MultiPV value ")
		case strings.HasPrefix(cmd, "go "):
			switch script {
			case "multipv":
				// Only emit multiple ranked lines if Analyse actually wired
				// multiPV through to setoption first; this is what makes the
				// TestAnalyse_SendsMultiPVAndReturnsRankedLines assertion a
				// real regression check for fix 3, not a tautology.
				if gotMultiPV == "3" {
					send("info depth 10 multipv 1 score cp 25 pv e2e4 e7e5")
					send("info depth 10 multipv 2 score cp 10 pv d2d4 d7d5")
					send("info depth 10 multipv 3 score cp 5 pv g1f3 g8f6")
				} else {
					send("info depth 10 multipv 1 score cp 25 pv e2e4 e7e5")
				}
				send("bestmove e2e4")
			case "hang":
				// Emit one info line and then simply go back to waiting on
				// stdin for the next command, which the test never sends.
				// That's a real blocked read syscall, simulating a stalled
				// engine that never reaches bestmove. (Deliberately not a
				// bare `select {}` here: with no other goroutine runnable,
				// that trips the Go runtime's own deadlock detector and
				// crashes this helper subprocess instead of just hanging.)
				send("info depth 10 multipv 1 score cp 25 pv e2e4 e7e5")
			}
		case cmd == "stop":
			// ignored; the canned scripts above don't run a real search loop.
		case cmd == "quit":
			return
		}
	}
}

func TestAnalyse_SendsMultiPVAndReturnsRankedLines(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	p := fakeEngine(ctx, t, "multipv")

	lines, err := p.Analyse(ctx, "startpos", 10, 3)
	if err != nil {
		t.Fatalf("analyse: %v", err)
	}
	if len(lines) != 3 {
		t.Fatalf("want 3 ranked lines (only possible if multipv was wired to setoption), got %d: %+v", len(lines), lines)
	}
	for i, l := range lines {
		if l.Rank != i+1 {
			t.Errorf("lines out of rank order: %+v", lines)
		}
	}
}

func TestAnalyse_RespectsContextCancellation(t *testing.T) {
	// setupCtx just bounds the lifetime of the subprocess itself; it is
	// generous so subprocess startup can't make this test flaky.
	setupCtx, setupCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer setupCancel()

	p := fakeEngine(setupCtx, t, "hang")

	// analyseCtx is the one under test: it should cut the blocking read
	// short well before any wall-clock second passes.
	analyseCtx, analyseCancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer analyseCancel()

	start := time.Now()
	_, err := p.Analyse(analyseCtx, "startpos", 10, 1)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("want a context error from analyse, got nil")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("want context.DeadlineExceeded, got %v", err)
	}
	// Bounded generously above the 300ms deadline so this can't flake on a
	// loaded CI box, but tight enough that it fails fast if fix 1 regresses
	// and Analyse goes back to blocking on p.out.Scan() forever.
	if elapsed > 3*time.Second {
		t.Fatalf("analyse took %v to respect context cancellation; want well under a second", elapsed)
	}
}
