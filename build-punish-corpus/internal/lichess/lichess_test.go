package lichess

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestMoves_ParsesAndComputesFreq(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"moves":[
			{"uci":"g8f6","white":30,"draws":10,"black":20},
			{"uci":"f8c5","white":5,"draws":2,"black":3}]}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, t.TempDir(), srv.Client())
	m, err := c.Moves(context.Background(), "somefen w - -", []int{1000})
	if err != nil {
		t.Fatal(err)
	}
	// totals: Nf6=60, Bc5=10, grand=70
	if m["g8f6"].Games != 60 {
		t.Errorf("Nf6 games = %d, want 60", m["g8f6"].Games)
	}
	if got := m["g8f6"].Freq; got < 0.85 || got > 0.86 {
		t.Errorf("Nf6 freq = %.3f, want ~0.857", got)
	}
}
