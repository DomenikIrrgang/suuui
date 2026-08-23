#!/bin/sh
# Runs every spec file in parallel, one process each, and aggregates the totals.
#
# WHY THIS IS SAFE: Tests/run.lua already loads the addon into a fresh sandbox per test and
# holds no state outside its own process, so one file per process is exactly what the
# sequential runner does -- just not one at a time. The totals are the proof: this reports the
# same passed/failed/skipped as `lua Tests/run.lua` does on its own.
#
# On this machine that is ~30s against ~215s. The floor is the slowest single file (currently
# Tests/spec/18_integration_spec.lua at ~21s), so more cores stop helping past that.
#
# WHAT YOU LOSE: the per-test tree and the failure detail. That is why a failing run prints the
# files that failed -- re-run one of those on its own for the diagnosis:
#
#     lua Tests/run.lua Tests/spec/18_integration_spec.lua
#
# Usage:  Tests/parallel.sh [jobs]      (default 12)
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

JOBS=${1:-12}
OUT=$(mktemp -t suuui_parallel)
trap 'rm -f "$OUT"' EXIT

# Each line of $OUT is one file's summary, prefixed with the file so a failure is nameable.
ls Tests/spec/*_spec.lua \
    | xargs -P "$JOBS" -I{} sh -c 'printf "%s %s\n" "$1" "$(lua Tests/run.lua "$1" 2>&1 | tail -1)"' _ {} \
    > "$OUT" 2>&1

# Strip the runner's colour escapes before any arithmetic touches the numbers.
CLEAN=$(sed 's/\x1b\[[0-9;]*m//g' "$OUT")

echo "$CLEAN" | awk '
    { pass += $2; fail += $4; skip += $6 }
    END { printf "%d passed, %d failed, %d skipped  (%d files)\n", pass, fail, skip, NR }
'

FAILED=$(echo "$CLEAN" | grep -v ", 0 failed" || true)
if [ -n "$FAILED" ]; then
    echo
    echo "Files with failures -- re-run one on its own for the detail:"
    echo "$FAILED" | sed 's/^/  /'
    exit 1
fi
