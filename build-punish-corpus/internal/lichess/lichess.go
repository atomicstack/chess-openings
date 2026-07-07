package lichess

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type MoveStat struct {
	Games int
	Freq  float64
}

type Client struct {
	base     string
	cacheDir string
	http     *http.Client
}

func NewClient(base, cacheDir string, hc *http.Client) *Client {
	if hc == nil {
		hc = http.DefaultClient
	}
	_ = os.MkdirAll(cacheDir, 0o755)
	return &Client{base: base, cacheDir: cacheDir, http: hc}
}

type apiResp struct {
	Moves []struct {
		UCI   string `json:"uci"`
		White int    `json:"white"`
		Draws int    `json:"draws"`
		Black int    `json:"black"`
	} `json:"moves"`
}

func (c *Client) Moves(ctx context.Context, fen string, ratings []int) (map[string]MoveStat, error) {
	raw, err := c.fetchCached(ctx, fen, ratings)
	if err != nil {
		return nil, err
	}
	var resp apiResp
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}
	total := 0
	games := map[string]int{}
	for _, m := range resp.Moves {
		g := m.White + m.Draws + m.Black
		games[m.UCI] = g
		total += g
	}
	out := map[string]MoveStat{}
	for u, g := range games {
		f := 0.0
		if total > 0 {
			f = float64(g) / float64(total)
		}
		out[u] = MoveStat{Games: g, Freq: f}
	}
	return out, nil
}

func ratingsToStrings(ratings []int) []string {
	rs := make([]string, len(ratings))
	for i, r := range ratings {
		rs[i] = strconv.Itoa(r)
	}
	return rs
}

func (c *Client) cacheKey(fen string, ratings []int) string {
	// make the key order-insensitive by sorting a copy of ratings
	sorted := make([]int, len(ratings))
	copy(sorted, ratings)
	sort.Ints(sorted)
	rs := ratingsToStrings(sorted)
	h := sha1.Sum([]byte(fen + "|" + strings.Join(rs, ",")))
	return hex.EncodeToString(h[:])
}

func (c *Client) fetchCached(ctx context.Context, fen string, ratings []int) ([]byte, error) {
	path := filepath.Join(c.cacheDir, c.cacheKey(fen, ratings)+".json")
	if b, err := os.ReadFile(path); err == nil {
		return b, nil
	}
	rs := ratingsToStrings(ratings)
	q := url.Values{}
	q.Set("fen", fen)
	q.Set("ratings", strings.Join(rs, ","))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+"/lichess?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	res, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("lichess status %d", res.StatusCode)
	}
	buf, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	_ = os.WriteFile(path, buf, 0o644)
	return buf, nil
}
