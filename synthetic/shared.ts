// A deliberately heavy SHARED generic surface, Panda-free.
//
// `Surface{A,B}` are two wide mapped types over ~100 keys whose value for each key K is a
// branching-recursive type carrying a per-path-distinct string accumulator (so nothing
// dedupes). The two surfaces use SEPARATE alias chains (`DeepA`/`DeepB`) of identical shape,
// so a `SurfaceA -> SurfaceB` assignment cannot short-circuit on reference equality: the
// checker must descend and instantiate every node on both sides. This is the analogue of
// Panda's per-property responsive/conditional value types being materialized per file.
//
// All modules use the SAME surface, so `tsc` instantiates it once and caches program-wide;
// each `tsgo` checker re-instantiates the whole surface once (the bug under test).
type D = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9;
type Keys = `prop${D}${D}`; // 100 keys
type Prev = [never, 0, 1, 2, 3, 4, 5, 6, 7, 8];

type DeepA<N extends number, S extends string> = N extends 0
  ? S
  : { a: DeepA<Prev[N], `${S}a`>; b: DeepA<Prev[N], `${S}b`> };
type DeepB<N extends number, S extends string> = N extends 0
  ? S
  : { a: DeepB<Prev[N], `${S}a`>; b: DeepB<Prev[N], `${S}b`> };

type SurfaceA = { [K in Keys]: DeepA<5, K> };
type SurfaceB = { [K in Keys]: DeepB<5, K> };

export type Force = [SurfaceA, SurfaceB];
