#!/usr/bin/env bash
# Interleaved peak-RSS comparison of tsc (TS6) vs tsgo (TS7), to control for
# machine-state drift and GC-timing variance. Runs them back-to-back, N rounds.
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

echo "=== interleaved peak RSS (GB), $ROUNDS rounds ==="
# Ordering is fixed: tsc first, then tsgo, every round. Interleaving back-to-back
# (rather than all-tsc-then-all-tsgo) is what controls for machine-state drift —
# keep the order fixed so the comparison stays apples-to-apples across rounds.
for r in $(seq 1 "$ROUNDS"); do
  a=$(rss npx tsc  -p tsconfig.json)
  b=$(rss npx tsgo -p tsconfig.json)
  printf "round %2s:  tsc %s   tsgo %s\n" "$r" "$a" "$b"
done

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
echo "-- tsgo (TS7) --"; for m in Symbols Types Instantiations; do count "$m" /tmp/_d7.t; done
