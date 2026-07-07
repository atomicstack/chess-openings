package progress

import (
	"fmt"
	"io"
	"sync"
)

type Emitter struct {
	mu      sync.Mutex
	w       io.Writer
	phase   string
	total   int
	current int
}

func New(w io.Writer) *Emitter { return &Emitter{w: w} }

func (e *Emitter) Phase(name string, total int) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.phase, e.total, e.current = name, total, 0
	fmt.Fprintf(e.w, "%s|%d|%d|%s\n", e.phase, e.current, e.total, "start")
}

func (e *Emitter) Tick(detail string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.current++
	fmt.Fprintf(e.w, "%s|%d|%d|%s\n", e.phase, e.current, e.total, detail)
}
