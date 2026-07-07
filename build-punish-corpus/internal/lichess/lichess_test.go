package lichess

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
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

func TestMoves_CacheHitSkipsNetwork(t *testing.T) {
	var counter atomic.Int32
	const testFEN = "testfen w - -"
	testRatings := []int{1600, 1200}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		counter.Add(1)

		// validate that query params are present and non-empty
		fenParam := r.URL.Query().Get("fen")
		if fenParam != testFEN {
			t.Errorf("fen param = %q, want %q", fenParam, testFEN)
		}
		ratingsParam := r.URL.Query().Get("ratings")
		if ratingsParam == "" {
			t.Error("ratings param is empty")
		}

		w.Write([]byte(`{"moves":[
			{"uci":"g8f6","white":40,"draws":15,"black":25},
			{"uci":"f8c5","white":10,"draws":4,"black":6}]}`))
	}))
	defer srv.Close()

	c := NewClient(srv.URL, t.TempDir(), srv.Client())

	// first call - populates cache
	m1, err := c.Moves(context.Background(), testFEN, testRatings)
	if err != nil {
		t.Fatal(err)
	}

	// second call - should hit cache and skip network
	m2, err := c.Moves(context.Background(), testFEN, testRatings)
	if err != nil {
		t.Fatal(err)
	}

	// verify counter is exactly 1 (only one network request)
	if count := counter.Load(); count != 1 {
		t.Errorf("server received %d requests, want 1", count)
	}

	// verify both calls return the same data
	if m1["g8f6"].Games != m2["g8f6"].Games {
		t.Errorf("first call g8f6.Games = %d, second call = %d", m1["g8f6"].Games, m2["g8f6"].Games)
	}
	if m1["g8f6"].Freq != m2["g8f6"].Freq {
		t.Errorf("first call g8f6.Freq = %f, second call = %f", m1["g8f6"].Freq, m2["g8f6"].Freq)
	}
	if m1["f8c5"].Games != m2["f8c5"].Games {
		t.Errorf("first call f8c5.Games = %d, second call = %d", m1["f8c5"].Games, m2["f8c5"].Games)
	}
	if m1["f8c5"].Freq != m2["f8c5"].Freq {
		t.Errorf("first call f8c5.Freq = %f, second call = %f", m1["f8c5"].Freq, m2["f8c5"].Freq)
	}
}
