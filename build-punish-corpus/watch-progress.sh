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

tail -n +1 -f "$FILE" | while IFS='|' read -r phase current total detail; do
	[ -z "${total:-}" ] && continue
	# emit control protocol: set denominator, phase label, progress value, detail text
	printf '@set-total %s\n@phase-name %s\n@value %s\n@label %s\n' "$total" "$phase" "$current" "$detail"
done | "$PROG" --detail=phase --tint-animation=cycle --style gradient-granular
