#!/usr/bin/env bash
# Interleaved peak-RSS comparison of tsc (TS6) vs tsgo (TS7), to control for
# machine-state drift and GC-timing variance. Runs them back-to-back, N rounds.
#
# Usage: ./measure.sh [rounds]    (default 12)
set -euo pipefail
ROUNDS="${1:-12}"

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
for r in $(seq 1 "$ROUNDS"); do
  a=$(rss npx tsc  -p tsconfig.json)
  b=$(rss npx tsgo -p tsconfig.json)
  printf "round %2s:  tsc %s   tsgo %s\n" "$r" "$a" "$b"
done

echo "=== deterministic counts (machine-independent) ==="
echo "-- tsc  (TS6) --"; npx tsc  -p tsconfig.json --extendedDiagnostics 2>&1 | grep -E 'Symbols:|Types:|Instantiations:'
echo "-- tsgo (TS7) --"; npx tsgo -p tsconfig.json --extendedDiagnostics 2>&1 | grep -E 'Symbols:|Types:|Instantiations:'
