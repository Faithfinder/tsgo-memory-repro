# tsgo (TS7 native) over-instantiates shared generics across module boundaries

**Claim:** On identical, error-free TypeScript that uses [Panda CSS](https://panda-css.com/),
the native compiler **`tsgo` instantiates the shared `styled-system` generic type
machinery once per module for the first ~4 modules that use it — a fixed ~4×
over-instantiation — instead of caching it program-wide like `tsc` does.** The result is
a constant **+489,160 instantiations** regardless of project size, which also shows up as
a robust peak-memory gap. The over-instantiation is **deterministic, content-independent,
and thread-independent**; within a single module `tsgo`'s caching matches `tsc` exactly.

Zero proprietary code — only public packages (`react`, `@pandacss/dev`) plus a generator.
This is the minimized form of a regression on a large production React app (3758 files)
where `tsgo` uses ~2.15× the instantiations and ~1.6× the peak RSS of `tsc`.

> **Filing against [microsoft/typescript-go](https://github.com/microsoft/typescript-go).**

---

## Run it

```bash
npm install
npm run setup     # panda codegen -> generates ./styled-system (the heavy shared types)
npm run diag      # type-check the 8 committed src/example*.tsx with both tools (the headline)
./mechanism.sh    # reproduce the deterministic fingerprint (ramp, content/thread-independence)
```

`npm run diag` runs `tsc` then `tsgo` with `--extendedDiagnostics` over the **8 committed
example files** — no generator needed — and prints the full gap below. Both report
**0 errors**: identical, valid work.

To reproduce the linearity / fixed-offset claim at scale, also:

```bash
npm run gen       # generates ./src/f*.tsx (default 800; `node pandagen.mjs 1500` for more)
./measure.sh 12   # interleaved peak RSS, 12 rounds, + deterministic counts
```

---

## The headline (8 committed files, no generator)

`npm run diag` on the 8 committed `src/example*.tsx` — the full gap is already present:

| `--extendedDiagnostics` | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 158,021 | 357,110 | 2.26× |
| Types | 10,884 | 44,236 | 4.06× |
| **Instantiations** | **165,664** | **654,824** | **3.95×** |

Both: **0 errors**. The instantiation gap is **+489,160**. These counts are
**machine-independent and zero-variance** — the same on any machine, any core count.

(Note: the gap requires more than one module. A *single* file shows no gap at all —
`tsc` and `tsgo` are identical at N=1. The gap accrues over the first ~4 modules and then
saturates; see below. Eight committed files sits comfortably past saturation.)

## The mechanism

`./mechanism.sh` reproduces all of the following deterministically.

### 1. The gap ramps over the first 4 modules, then saturates

Regenerate at small file counts (`node pandagen.mjs N`) and watch the full-surface
instantiation counts:

| modules | `tsc` | `tsgo` | gap |
|---|---|---|---|
| 1 | 163,452 | 163,390 | ~0 |
| 2 | 163,768 | 326,780 | 163,012 |
| 3 | 164,084 | 490,170 | 326,086 |
| 4 | 164,400 | 653,560 | **489,160** |
| 5 | 164,716 | 653,876 | 489,160 |
| 6 | 165,032 | 654,192 | 489,160 |

`tsc` adds a fixed marginal cost (316 instantiations) per module and instantiates the
shared machinery **once**. `tsgo` adds a *full extra re-instantiation of the shared
machinery* (~163K) for modules 2, 3 and 4 — three redundant copies — then drops to the
same 316/module marginal. So `tsgo` instantiates the shared `styled-system` machinery
**4× (once per module, capped at 4)** where `tsc` does it **1×**. The counts fit an exact
linear model for N ≥ 4:

```
tsc  instantiations = 163,136 + 316·N      (holds for all N)
tsgo instantiations = 652,296 + 316·N      (holds for N ≥ 4; 652,296 ≈ 4 × 163,136)
```

The fixed offset is `652,296 − 163,136 = 489,160` — three redundant instantiations of the
shared machinery, incurred once and never repaid down.

### 2. It is content-independent (same 4× on a one-line file)

Replace each file with a single `css({ color: "red.500" })` call. The per-module cost
shrinks from ~163K to ~3.5K, but the **multiplier is identical**:

| modules | `tsc` | `tsgo` |
|---|---|---|
| 1 | 3,459 | 3,464 |
| 2 | 3,459 | 6,928 |
| 3 | 3,459 | 10,392 |
| 4 | 3,459 | **13,856** |
| 5 | 3,459 | 13,856 |
| 6 | 3,459 | 13,856 |

`tsc` is **dead flat** — it instantiates `css`'s machinery once and reuses it for every
module. `tsgo` = per-module-cost × min(modules, 4) = `3,464 × 4 = 13,856`, exactly 4.00×.
The 4× is a property of the *checker's cross-module instantiation caching*, not of Panda's
types or of how much any file uses.

### 3. The boundary is the module, not the call

Eight `css()` calls in **eight files** → `tsgo` 13,856 (4×). The same eight calls in
**one file** → `tsgo` 3,485 (`tsc` 3,480) — **1×, identical to tsc**. Within a module
`tsgo` deduplicates instantiations perfectly; the over-instantiation happens *only across
module boundaries*, for the first 4 modules.

### 4. It is not a parallelism artifact

The minimal 8-module count is **13,856 at `GOMAXPROCS=1, 2, 4, 8`** alike (on a 12-core
machine). The over-instantiation is intrinsic to the checker's data structures, not a
per-worker-cache race.

## Scale & linearity (generator)

`npm run gen` (800 files → 808 total with the 8 committed) confirms the offset is fixed,
not per-file:

| `--extendedDiagnostics` (808 files) | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 360,421 | 559,510 | 1.55× |
| Types | 82,084 | 115,436 | 1.41× |
| **Instantiations** | 418,464 | 907,624 | 2.17× |

Same **+489,160** gap as at 8 files. Because the offset is fixed, the *ratio* dilutes as
you add cheap uniform files (3.95× at 8 → 2.17× at 808 → 1.62× at 2000), while the absolute
over-instantiation and the 4× multiplier stay constant. Read the absolute gap, not the ratio.

## Corroboration: peak RSS (interleaved)

Apple Silicon, macOS. 12 interleaved rounds at 808 files (`maximum resident set size`):

```
tsc : 0.36 0.33 0.38 0.38 0.36 0.36 0.34 0.37 0.36 0.35 0.37 0.34   (max 0.38 GB)
tsgo: 0.51 0.50 0.50 0.49 0.49 0.48 0.51 0.50 0.50 0.49 0.52 0.48   (min 0.48 GB)
```

Non-overlapping: `tsc`'s worst run stays below `tsgo`'s best. `tsgo` is also ~10× faster —
a speed/memory trade-off, not a free lunch.

### Caveats (please read before dismissing)

- **Measure memory interleaved.** `tsc`'s peak RSS is high-variance (V8 GC timing) and can
  swing widely on larger inputs; comparing a separately-measured `tsc` low run against
  `tsgo` is invalid. `measure.sh` interleaves `tsc`-then-`tsgo` every round on purpose.
- **Read the absolute instantiation gap, not the ratio.** The regression is a *fixed*
  ~489K extra instantiations, so the ratio shrinks as cheap files dilute it. The real app
  *sustains* ~2.15× at 3758 files because it stacks many generic-heavy libraries (Zodios,
  React Query, React Table, Formily) on top of Panda — each contributes its own fixed
  offset, so they add instead of diluting. This repro isolates the single biggest one.
- **Don't compare the two tools' "Memory used" lines.** `tsc`'s `--extendedDiagnostics`
  "Memory used" is a cumulative V8 allocation counter (exceeds real peak RSS); `tsgo`'s is
  Go live heap. They are not comparable. Use peak RSS for memory and the instantiation
  count for the deterministic signal.

---

## Real-world numbers (private codebase — comparable metrics only)

Large production React app, 3758 files, identical 0 errors from both:

| Metric (3758 files) | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 2.15 M | 4.88 M | 2.3× |
| Types | 749 K | 2.13 M | 2.8× |
| Instantiations | 37.7 M | 81.2 M | 2.15× |
| Peak RSS (interleaved) | ~2.1 GB | ~3.3 GB | ~1.6× |

Single-threaded (`GOMAXPROCS=1 tsgo`) reproduces the same peak RSS, consistent with the
thread-independence above — intrinsic to the checker's data structures.

## Environment

| | |
|---|---|
| OS / arch | macOS (Darwin 25.5.0), Apple Silicon `arm64`, 12 cores |
| Node | v22.16.0 |
| `typescript` | 6.0.3 |
| `@typescript/native-preview` | 7.0.0-dev.20260604.1 |

```bash
node --version
npx tsc --version     # -> Version 6.0.3
npx tsgo --version    # -> Version 7.0.0-dev.20260604.1
```

Versions are pinned in `package.json` for deterministic counts. Please re-confirm the gap
on `@typescript/native-preview@latest` — the exact saturation count (4) may shift, but the
8 committed files sit far enough past it to show the full gap regardless.

## Questions for the TypeScript team

1. Why does `tsgo` instantiate a shared generic type once per module for the first ~4
   modules that use it, rather than caching the instantiation program-wide like `tsc`?
   Within a module the caching is already correct (1×, matching `tsc`) — what differs at
   the module boundary, and why does it saturate at 4?
2. Is the fixed ~4× over-instantiation of shared generics (here +489,160, but additive
   across every generic-heavy library in a real app) expected, or a caching gap vs `tsc`?
3. Is there a heap budget / GC knob recommended for `tsgo` in memory-constrained CI?
```