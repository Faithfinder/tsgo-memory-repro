import type { Force } from "./shared";
declare const a: Force[0];
// Assigning SurfaceA -> SurfaceB forces the checker to materialize every node of the
// shared surface (the two surfaces use distinct alias chains, so the comparison cannot
// short-circuit on reference equality).
export const s7: Force[1] = a;
