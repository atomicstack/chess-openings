package progress

import (
	"strings"
	"sync"
	"testing"
)

func TestEmitter_FormatAndCount(t *testing.T) {
	var sb strings.Builder
	e := New(&sb)
	e.Phase("severity", 2)
	e.Tick("e2e4")
	e.Tick("d2d4")
	lines := strings.Split(strings.TrimSpace(sb.String()), "\n")
	last := lines[len(lines)-1]
	if last != "severity|2|2|d2d4" {
		t.Errorf("last progress line = %q, want severity|2|2|d2d4", last)
	}
}

func TestEmitter_ConcurrentTicksAreSafe(t *testing.T) {
	var sb strings.Builder
	e := New(&sb)
	e.Phase("candidates", 100)
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); e.Tick("x") }()
	}
	wg.Wait()
	if e.current != 100 {
		t.Errorf("current = %d, want 100", e.current)
	}
}
