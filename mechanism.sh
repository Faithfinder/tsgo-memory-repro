#!/usr/bin/env bash
# Reproduces the deterministic per-checker over-instantiation described in the README.
# Every number printed here is machine-independent — you should see the same instantiation
# counts on any machine, any core count. Requires `npm run setup` to have run first.
#
# It moves the committed src/example*.tsx aside, runs the experiments in a clean src/,
# then restores them (and cleans up its own probe files: f*.tsx, m*.tsx, single.tsx).
#
# Usage: ./mechanism.sh
set -euo pipefail

# --- instantiation count for one tool, as a plain integer (fails loudly on label drift) ---
# Extra args (e.g. --checkers 4, --singleThreaded) are forwarded to the tool.
inst () {  # inst <tsc|tsgo> [extra args...]
  local tool="$1"; shift
  local out val
  out="$(npx "$tool" -p tsconfig.json "$@" --extendedDiagnostics 2>&1)"
  val="$(printf '%s\n' "$out" | grep -E '^Instantiations:' | grep -oE '[0-9,]+' | tail -1 | tr -d ,)"
  if [[ -z "$val" ]]; then
    echo "ERROR: 'Instantiations:' not found in $tool output — metric label drifted?" >&2
    printf '%s\n' "$out" | tail -5 >&2
    exit 1
  fi
  printf '%s' "$val"
}

write_minimal () {  # write_minimal <count>   — one css() call per file, N separate modules
  rm -f src/m*.tsx
  for ((i=0; i<$1; i++)); do
    printf 'import { css } from "styled-system/css";\nexport const x%s = css({ color: "red.500" });\n' "$i" > "src/m$i.tsx"
  done
}

# --- isolate: stash committed files, guarantee restore + cleanup on any exit ---
HOLD="$(mktemp -d)"
restore () { rm -f src/f*.tsx src/m*.tsx src/single.tsx; mv "$HOLD"/*.tsx src/ 2>/dev/null || true; rmdir "$HOLD" 2>/dev/null || true; }
trap restore EXIT
mv src/example*.tsx "$HOLD"/

echo "=== versions ==="
printf "node %s | tsc %s | tsgo %s\n\n" "$(node --version)" "$(npx tsc --version)" "$(npx tsgo --version)"

echo "=== 1. The mechanism: instantiations are LINEAR in the checker count (--checkers) ==="
echo "    8 modules, one css() call each. tsgo runs a pool of checker workers, each with"
echo "    independent type state; each re-instantiates the shared styled-system surface once."
write_minimal 8
t6=$(inst tsc)
printf "  %-22s %12s   %s\n" "tsc"                 "$t6" "1.00x  (baseline)"
single=$(inst tsgo --singleThreaded)
printf "  %-22s %12s   %.2fx\n" "tsgo --singleThreaded" "$single" "$(echo "$single/$t6" | bc -l)"
for C in 1 2 4 8; do
  v=$(inst tsgo --checkers "$C")
  printf "  %-22s %12s   %.2fx\n" "tsgo --checkers $C" "$v" "$(echo "$v/$t6" | bc -l)"
done
echo "  -> EXACTLY linear in --checkers. --checkers 1 / --singleThreaded == tsc. The default"
echo "     --checkers 4 is the entire source of the ~4x gap; it is not a mysterious constant."
echo

echo "=== 2. Ramp & saturation: gap tracks the default checker count (4), not project size ==="
echo "    Full Panda surface. tsc adds a fixed marginal cost per module and instantiates the"
echo "    shared machinery once; tsgo re-instantiates it once per checker until every checker"
echo "    has work (saturates at the default --checkers, here 4)."
printf "%8s  %12s  %12s  %12s\n" "modules" "tsc" "tsgo" "gap"
for N in 1 2 3 4 5 6; do
  node pandagen.mjs "$N" >/dev/null
  t6=$(inst tsc); t7=$(inst tsgo)
  printf "%8s  %12s  %12s  %12s\n" "$N" "$t6" "$t7" "$((t7 - t6))"
done
rm -f src/f*.tsx
echo "  -> the gap accrues over the first 4 modules (one redundant surface per checker) then"
echo "     saturates at the default checker count; both tools share the same per-module marginal."
echo

echo "=== 3. Content-independence (minimal: one css() call per module; same per-checker factor) ==="
printf "%8s  %12s  %12s\n" "modules" "tsc" "tsgo"
for N in 1 2 3 4 5 6; do
  write_minimal "$N"
  printf "%8s  %12s  %12s\n" "$N" "$(inst tsc)" "$(inst tsgo)"
done
echo "  -> tsc is dead flat (one global instantiation, reused). tsgo = per-module-cost x"
echo "     min(modules, --checkers). The factor is the checker count, independent of file size."
echo

echo "=== 4. The boundary is the module, not the call (8 css() calls: one file vs eight files) ==="
write_minimal 8
echo "  eight files :  tsc=$(inst tsc)  tsgo=$(inst tsgo)"
rm -f src/m*.tsx
{ echo 'import { css } from "styled-system/css";'; for i in $(seq 1 8); do echo "export const y$i = css({ color: \"red.500\", p: \"$i\" });"; done; } > src/single.tsx
echo "  one file    :  tsc=$(inst tsc)  tsgo=$(inst tsgo)"
echo "  -> within a single module tsgo dedups perfectly (matches tsc); the work that gets"
echo "     duplicated is shared across modules, so it lands on multiple checkers."
echo "  NOTE: GOMAXPROCS does not change the checker count — --checkers does; see the sweep above."
