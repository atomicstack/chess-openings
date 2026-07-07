#!/usr/bin/env bash
# usage: ./watch-progress.sh <progress-file>
# run in a 3-line tmux pane at the bottom of the screen.
# set cfg.progressPath to a file so both the generator and this watcher share it.
#
# the generator emits lines as `phase|current|total|detail`. this script tails
# the file and converts each line to progress-bar-3000 control protocol events:
# @set-total (denominator), @phase-name (phase label), @value (progress value),
# @label (detail). see ~/git_tree/progress-bar-3000/skills/progress-bar-3000/SKILL.md
# for the control protocol spec.
set -euo pipefail

PROG="${HOME}/git_tree/progress-bar-3000/progress-bar-3000"
FILE="${1:?pass the progress file the generator writes (cfg.progressPath)}"

{
	# `@phase-name <name>` only jumps to a phase that already exists in the
	# renderer's phase plan (see @set-phases in the progress-bar-3000 SKILL) —
	# it does not create one. the pipeline (internal/pipeline/pipeline.go)
	# only ever calls progress.Emitter.Phase with a single phase, "analyse",
	# so register that one-phase plan up front, before the first
	# `@phase-name analyse` line below, or the renderer would reject it.
	printf '@set-phases analyse\n'
	tail -n +1 -f "$FILE" | while IFS='|' read -r phase current total detail; do
		[ -z "${total:-}" ] && continue
		# emit control protocol: phase label, denominator, progress value, detail text
		printf '@phase-name %s\n@set-total %s\n@value %s\n@label %s\n' "$phase" "$total" "$current" "$detail"
	done
} | "$PROG" --detail=phase --tint-animation=cycle --style gradient-granular
