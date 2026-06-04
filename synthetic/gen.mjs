// Regenerates the synthetic modules synthetic/m1..mN.ts (default 8). Each module imports
// the shared heavy surface from ./shared and forces the checker to materialize it once.
// The committed m1..m8.ts already reproduce the full per-checker scaling on their own; this
// generator only exists to vary the module count and confirm the gap is linear in
// --checkers, NOT in the number of modules.
//
// Usage: node synthetic/gen.mjs [moduleCount]
import { writeFileSync, rmSync, readdirSync } from "node:fs";

const N = Number(process.argv[2] ?? 8);
const DIR = new URL("./", import.meta.url);

for (const name of readdirSync(DIR)) {
  if (/^m\d+\.ts$/.test(name)) rmSync(new URL(name, DIR));
}

const mod = (i) => `import type { Force } from "./shared";
declare const a: Force[0];
// Assigning SurfaceA -> SurfaceB forces the checker to materialize every node of the
// shared surface (the two surfaces use distinct alias chains, so the comparison cannot
// short-circuit on reference equality).
export const s${i}: Force[1] = a;
`;

for (let i = 1; i <= N; i++) writeFileSync(new URL(`m${i}.ts`, DIR), mod(i));
console.log(`generated ${N} synthetic modules in synthetic/`);
