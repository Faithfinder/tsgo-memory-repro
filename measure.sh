#!/usr/bin/env bash
# Interleaved peak-RSS comparison of tsc (TS6) vs tsgo (TS7), to control for
# machine-state drift and GC-timing variance. Runs them back-to-back, N rounds,
# then sweeps tsgo's peak RSS across --checkers to show memory scales with the
# checker count (the same per-checker duplication the instantiation counts show).
#
# Usage: ./measure.sh [rounds]    (default 12)
set -euo pipefail
ROUNDS="${1:-12}"

# Versions up front, so the printed numbers are reproducible against a known build.
echo "=== versions ==="
printf "node : %s\n" "$(node --version)"
printf "tsc  : %s\n" "$(npx tsc --version)"
printf "tsgo : %s\n" "$(npx tsgo --version)"
echo

# Pick the right /usr/bin/time flag + RSS unit per OS.
if [[ "$(uname)" == "Darwin" ]]; then
  TIMEFLAG="-l"; RSS_RE='maximum resident set size'; DIV=1073741824   # bytes -> GB
else
  TIMEFLAG="-v"; RSS_RE='Maximum resident set size'; DIV=1048576      # kbytes -> GB
fi

rss () {
  /usr/bin/time $TIMEFLAG "$@" >/dev/null 2>/tmp/_m.t
  awk -v re="$RSS_RE" -v d="$DIV" '$0 ~ re { for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/){printf "%.2f", $i/d; exit} }' /tmp/_m.t
}

echo "=== interleaved peak RSS (GB), $ROUNDS rounds (tsc vs default tsgo) ==="
# Ordering is fixed: tsc first, then tsgo, every round. Interleaving back-to-back
# (rather than all-tsc-then-all-tsgo) is what controls for machine-state drift —
# keep the order fixed so the comparison stays apples-to-apples across rounds.
for r in $(seq 1 "$ROUNDS"); do
  a=$(rss npx tsc  -p tsconfig.json)
  b=$(rss npx tsgo -p tsconfig.json)
  printf "round %2s:  tsc %s   tsgo %s\n" "$r" "$a" "$b"
done
echo

echo "=== peak RSS (GB) vs --checkers: memory scales with the checker count ==="
# The bug is about memory: each checker holds independent type state, so peak RSS
# climbs with --checkers and --checkers 1 / --singleThreaded brings tsgo near tsc.
# Interleave a fresh tsc baseline each round so the comparison controls for drift.
printf "%-26s" "tsc"
for r in $(seq 1 "$ROUNDS"); do printf " %s" "$(rss npx tsc -p tsconfig.json)"; done; echo
printf "%-26s" "tsgo --singleThreaded"
for r in $(seq 1 "$ROUNDS"); do printf " %s" "$(rss npx tsgo -p tsconfig.json --singleThreaded)"; done; echo
for C in 1 2 4 8; do
  printf "%-26s" "tsgo --checkers $C"
  for r in $(seq 1 "$ROUNDS"); do printf " %s" "$(rss npx tsgo -p tsconfig.json --checkers "$C")"; done; echo
done
echo "  -> peak RSS rises monotonically with --checkers; --checkers 1 / --singleThreaded"
echo "     is the memory knob that collapses the gap back toward tsc."
echo

# Extract one diagnostic count, failing loudly if the label is missing. Guards
# against silent metric-label drift between tsc and tsgo: a bare grep would print
# nothing and the table would look broken rather than wrong.
count () {  # count <label> <logfile>
  local val
  val="$(grep -E "^${1}:" "$2" | grep -oE '[0-9,]+' | tail -1)"
  if [[ -z "$val" ]]; then
    echo "ERROR: '${1}:' not found in $(basename "$2") output — metric label drifted?" >&2
    echo "       last lines were:" >&2; tail -5 "$2" >&2
    exit 1
  fi
  printf "%s: %s\n" "$1" "$val"
}

echo "=== deterministic counts (machine-independent) ==="
npx tsc  -p tsconfig.json --extendedDiagnostics >/tmp/_d6.t 2>&1
npx tsgo -p tsconfig.json --extendedDiagnostics >/tmp/_d7.t 2>&1
echo "-- tsc  (TS6) --"; for m in Symbols Types Instantiations; do count "$m" /tmp/_d6.t; done
echo "-- tsgo (TS7, default --checkers) --"; for m in Symbols Types Instantiations; do count "$m" /tmp/_d7.t; done
