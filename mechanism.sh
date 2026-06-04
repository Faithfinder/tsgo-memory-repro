#!/usr/bin/env bash
# Reproduces the deterministic over-instantiation fingerprint described in the README.
# Every number printed here is machine-independent — you should see the same instantiation
# counts on any machine, any core count. Requires `npm run setup` to have run first.
#
# It moves the committed src/example*.tsx aside, runs four experiments in a clean src/,
# then restores them (and cleans up its own probe files: f*.tsx, m*.tsx, single.tsx).
#
# Usage: ./mechanism.sh
set -euo pipefail

# --- instantiation count for one tool, as a plain integer (fails loudly on label drift) ---
inst () {  # inst <tsc|tsgo>
  local out val
  out="$(npx "$1" -p tsconfig.json --extendedDiagnostics 2>&1)"
  val="$(printf '%s\n' "$out" | grep -E '^Instantiations:' | grep -oE '[0-9,]+' | tail -1 | tr -d ,)"
  if [[ -z "$val" ]]; then
    echo "ERROR: 'Instantiations:' not found in $1 output — metric label drifted?" >&2
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

echo "=== 1. Ramp & saturation (full Panda surface; tsc linear, tsgo saturates at 4 modules) ==="
printf "%8s  %12s  %12s  %12s\n" "modules" "tsc" "tsgo" "gap"
for N in 1 2 3 4 5 6; do
  node pandagen.mjs "$N" >/dev/null
  t6=$(inst tsc); t7=$(inst tsgo)
  printf "%8s  %12s  %12s  %12s\n" "$N" "$t6" "$t7" "$((t7 - t6))"
done
rm -f src/f*.tsx
echo "  -> tsc adds a fixed marginal cost per module; tsgo adds a FULL extra re-instantiation"
echo "     for modules 2,3,4 then matches tsc's marginal. Gap saturates at ~489,160."
echo

echo "=== 2. Content-independence (minimal: one css() call per module; tsc FLAT, tsgo x4) ==="
printf "%8s  %12s  %12s\n" "modules" "tsc" "tsgo"
for N in 1 2 3 4 5 6; do
  write_minimal "$N"
  printf "%8s  %12s  %12s\n" "$N" "$(inst tsc)" "$(inst tsgo)"
done
echo "  -> tsc is dead flat (one global instantiation, reused). tsgo = per-module-cost x"
echo "     min(modules,4). Same 4.00x multiplier as the full surface => content-independent."
echo

echo "=== 3. Thread-independence (minimal, 8 modules; tsgo identical across GOMAXPROCS) ==="
write_minimal 8
for G in 1 2 4 8; do
  printf "  GOMAXPROCS=%s  tsgo=%s\n" "$G" "$(GOMAXPROCS=$G inst tsgo)"
done
echo "  -> identical at every core count => not a parallelism artifact; intrinsic to the checker."
echo

echo "=== 4. The boundary is the module (8 css() calls: one file vs eight files) ==="
write_minimal 8
echo "  eight files :  tsc=$(inst tsc)  tsgo=$(inst tsgo)"
rm -f src/m*.tsx
{ echo 'import { css } from "styled-system/css";'; for i in $(seq 1 8); do echo "export const y$i = css({ color: \"red.500\", p: \"$i\" });"; done; } > src/single.tsx
echo "  one file    :  tsc=$(inst tsc)  tsgo=$(inst tsgo)"
echo "  -> within a single module tsgo dedups perfectly (matches tsc). The over-instantiation"
echo "     happens only ACROSS module boundaries, for the first 4 modules."
