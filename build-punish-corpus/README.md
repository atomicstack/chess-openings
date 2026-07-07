# build-punish-corpus

offline Go pipeline that reads an `openings.json` seed, finds opponent blunders in the seed lines, and writes `punish-corpus.json` for bundling in the iOS app.

the pipeline scores each legal alternative to the book move for severity (Stockfish analysis) and plausibility (blend of Lichess opening explorer + Maia neural-network estimates), gates candidates by configurable thresholds, and outputs a deterministic JSON corpus keyed by normalized FEN and grouped by rating bands.

## prerequisites

### Stockfish binary

a single-threaded Stockfish binary (e.g., `Stockfish 17`, `Stockfish 18`) that understands UCI protocol. the pipeline analyzes each candidate move at a fixed depth, so the exact version matters for reproducibility — set `stockfishVersion` in your config to match.

**key config fields:**
- `stockfishPath` — absolute path to the binary
- `stockfishVersion` — version string for provenance records (e.g., `"Stockfish 17"`); used when the corpus is re-run to confirm byte-identical output
- `stockfishDepth` — fixed search depth in plies (default 22)

### lc0 binary and weights

lc0 (Leela Chess Zero) is used during plausibility analysis. you need:

- **lc0 binary** — supports UCI `go nodes <n>` queries (the pipeline runs a policy-only query, not a depth-limited search)
- **Maia weights** — neural-network files for evaluating move quality at different rating levels (e.g., `maia-1900.onnx`, `maia-1500.onnx`)

**key config fields:**
- `lc0Path` — absolute path to the lc0 binary
- `maiaWeightsDir` — directory containing Maia `.onnx` weight files (one per rating band)

### Lichess opening-explorer cache

optionally pre-populate a cache of Lichess opening-explorer data to avoid hitting rate limits during long runs. a Lichess API token (in `lichess-api-key.txt` at the repo root, gitignored) raises the rate limit.

**key config field:**
- `lichessCacheDir` — directory for cached explorer stats (default `.lichess-cache`)

## configuration

the pipeline is tuned via a JSON config file. all keys are optional; defaults are applied for missing keys.

### paths

| key | default | purpose |
|-----|---------|---------|
| `openingsJsonPath` | `"../Chess Openings/Resources/openings.json"` | path to the app seed file |
| `outputPath` | `"punish-corpus.json"` | output corpus path |
| `stockfishPath` | (required) | path to Stockfish binary |
| `lc0Path` | (required) | path to lc0 binary |
| `maiaWeightsDir` | (required) | directory containing Maia `.onnx` files |
| `lichessCacheDir` | `".lichess-cache"` | local cache of Lichess explorer data |
| `progressPath` | (empty) | progress file path; if empty, progress emits to stderr |

### concurrency & engine

| key | default | purpose |
|-----|---------|---------|
| `workers` | CPU count | number of concurrent slot processors |
| `hashMB` | 128 | Stockfish transposition-table size in MB |
| `stockfishDepth` | 22 | fixed search depth for severity analysis (plies) |
| `stockfishVersion` | (empty) | version string for provenance; set to your binary version for reproducibility records |
| `multiPV` | 20 | Stockfish MultiPV count (number of alternatives analyzed per position) |

### severity gate

| key | default | purpose |
|-----|---------|---------|
| `minEvalDropCp` | 150 | minimum evaluation drop (centipawns) to consider a move a blunder |
| `maxEvalDropCp` | 900 | maximum evaluation drop to include (above this is likely a mate threat) |
| `winThresholdCp` | 150 | centipawn threshold above which a position is considered "winning" (affects mate-bonus logic) |

### selection & plausibility

| key | default | purpose |
|-----|---------|---------|
| `maxBlundersPerPosition` | 5 | cap on the number of candidate blunders per position in the output corpus |
| `minLichessGames` | 50 | fallback game threshold: if Lichess data has fewer than this many games, prefer Maia estimates |
| `minPlausibility` | 0.02 | drop candidates with lower blended plausibility score (0.0–1.0 scale) |

## running the pipeline

### basic invocation

```bash
go run ./cmd/build-corpus --config config.json
```

### cli flags

- `--config <path>` — path to the JSON config file
- `--workers <n>` — override `config.workers` (worker pool size)
- `--openings <path>` — override `config.openingsJsonPath`
- `--out <path>` — override `config.outputPath`

### example

```bash
go run ./cmd/build-corpus \
  --config /path/to/config.json \
  --workers 4 \
  --out my-corpus.json
```

## monitoring with tmux

for long-running analyses, use the progress watcher to display a live bar in a tmux pane at the bottom of the screen.

### step 1: set config to write progress to a file

in your `config.json`:
```json
{
  "progressPath": "/tmp/punish-corpus-progress.txt"
}
```

### step 2: start the pipeline

```bash
go run ./cmd/build-corpus --config config.json
```

### step 3: in another tmux pane, start the watcher

```bash
./watch-progress.sh /tmp/punish-corpus-progress.txt
```

the watcher tails the progress file and renders phase / progress / detail via progress-bar-3000. it updates in real-time as the pipeline emits progress lines.

**ordering matters:** start the pipeline (step 2) before the watcher (step 3). the watcher's `tail -f` needs the progress file to exist, and the pipeline creates it as soon as it emits its first progress line — starting the watcher first just means it waits for that file to appear.

**the watcher does not exit on its own** when the pipeline finishes — `tail -f` (and the progress-bar-3000 renderer behind it) keeps running until you stop it. once the run is done, `Ctrl-C` the watcher's tmux pane to stop it.

## determinism & reproducibility

the pipeline is fully deterministic, even though it runs concurrently:

- **a pool of concurrent, single-threaded Stockfish engines** — the pipeline spins up `workers` (default: CPU count) separate Stockfish processes (see `cmd/build-corpus/deps.go`), each configured with `Threads 1` and searched to the fixed `stockfishDepth`. determinism does **not** come from serializing queries through one shared connection — it comes from each engine's single-threaded, fixed-depth search being independently reproducible, regardless of how many run concurrently or how the goroutine scheduler happens to interleave the `errgroup` worker pool (`internal/pipeline/pipeline.go`'s `analyse` phase, bounded by `g.SetLimit(cfg.Workers)`).
- **lc0/Maia plausibility uses a fixed node count, not a depth-limited search** — `internal/maia/maia.go` sends `go nodes 1` (policy-only) against each rating band's Maia network, so plausibility is read straight off the policy head rather than the result of a variable-depth search. no randomization.
- **sorted JSON output** — `internal/corpus/corpus.go`'s `Marshal` sorts position keys, sorts each position's blunders by move UCI, and sorts band/line arrays before encoding; combined with `encoding/json` already sorting map keys, the file is deterministically ordered from top to bottom.

**re-running with the same Stockfish binary, `stockfishDepth`, and config produces a byte-identical `punish-corpus.json`, regardless of `workers` or how the goroutine scheduler interleaves the worker pool.**

to verify reproducibility:
1. run the pipeline once with your config and note the `stockfishVersion` value
2. run again with the same binary, weights, and config
3. compare output files: `diff punish-corpus.json punish-corpus-2.json` should be empty

**note:** if the Stockfish binary changes (upgrade, downgrade, or even a rebuild), the output may differ due to internal engine changes — this is expected. set `stockfishVersion` in your config to record which binary generated the corpus for future reproducibility checks.

## output format

the pipeline writes `punish-corpus.json`, a deterministic corpus keyed by normalized FEN, with blunders grouped by opponent and move. each position contains:

- `opponent_side` — the side that played the blunder (`"white"` or `"black"`)
- `book_move` — the book's recommended move (UCI + SAN)
- `blunders` — array of candidate blunders (up to `maxBlundersPerPosition`), each with:
  - `move` — the candidate move (UCI + SAN)
  - `eval_drop_cp` — severity in centipawns
  - `bands` — rating bands where this move is a credible blunder
  - `plausibility` — blend of Lichess + Maia probabilities by band
  - `refutation` — the best response (principal variation + evaluation)
  - `lines` — which seed openings contain this position

**provenance:** the corpus includes a provenance section with:
- `stockfish` — the version string from config
- `depth` — the search depth used
- `multipv` — MultiPV count
- `maia_nets` — all Maia networks used (union across bands)
- `lichess_buckets` — all rating buckets queried (union across bands)
- `source_seed_version` — the seed file version

## next steps (plan 2)

the output `punish-corpus.json` is consumed by the iOS app's "punish" feature (separate plan). the app loads the corpus, presents positions to the user, and evaluates move quality using bundled Stockfish.

## testing

```bash
# full test suite
go test ./...

# run only config tests
go test ./internal/config

# run with verbose output
go test ./... -v
```

## build & vet

```bash
# compile only
go build ./...

# run go vet
go vet ./...
```
