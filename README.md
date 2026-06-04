# tsgo (TS7 native) duplicates shared-generic instantiations once per checker

**Claim:** On identical, error-free TypeScript that uses [Panda CSS](https://panda-css.com/),
the native compiler **`tsgo` re-instantiates the shared `styled-system` generic type
machinery once per checker worker (`--checkers`, default 4)**, where `tsc` instantiates it
once for the whole program. For *shared infrastructure* types — used by most files — the
cost is therefore **~N×** the single-instantiation cost (here ~163K instantiations per
checker), not the roughly-20%-overhead-for-duplicated-types that the multi-checker design
anticipates, and it scales **peak RSS** with the checker count. The effect is **deterministic** and **exactly linear in
`--checkers`**: `--checkers 1` / `--singleThreaded` reproduces `tsc`'s instantiation count
to within 0.04%.

Zero proprietary code — only public packages (`react`, `@pandacss/dev`) plus a generator.
A Panda-free [`synthetic/`](#mechanism-proof-panda-free-synthetic) reproduces the same
per-checker scaling with no `panda codegen`. This is the minimized form of a regression on
a large production React app (3758 files) where `tsgo` uses ~2.15× the instantiations and
~1.6× the peak RSS of `tsc`.

> **Filing against [microsoft/typescript-go](https://github.com/microsoft/typescript-go).**
> This is the documented multi-checker design — the concern is its *magnitude for
> shared-infrastructure generics*, not its existence.

---

## Run it

```bash
npm install
npm run setup       # panda codegen -> generates ./styled-system (the heavy shared types)
npm run diag:checkers   # THE HEADLINE: instantiation count vs --checkers (linear)
npm run diag:single     # tsgo --singleThreaded -> matches tsc
./mechanism.sh      # the full deterministic fingerprint (sweep, ramp, content-independence)
npm run diag:synthetic  # Panda-free proof of the same per-checker scaling (no codegen)
```

`npm run diag:checkers` type-checks the **8 committed `src/example*.tsx`** with `tsc` and
with `tsgo` at `--checkers 1,2,4,8`. Both tools report **0 errors**: identical, valid work.

---

## The headline: instantiations are exactly linear in `--checkers`

`tsgo` runs a pool of checker workers (`--checkers`, default 4), **each with its own
independent type state**. Each checker that touches the shared `styled-system` surface
instantiates it once. So the instantiation count is linear in the number of checkers — and
`--checkers 1` / `--singleThreaded` collapses the gap to `tsc`'s number:

| run | Instantiations | vs `tsc` |
|---|---|---|
| `tsc` (TS6) | 165,664 | 1.00× |
| `tsgo --singleThreaded` | 165,602 | **1.00× — gap gone** |
| `tsgo --checkers 1` | 165,602 | **1.00× — gap gone** |
| `tsgo --checkers 2` | 328,676 | 1.98× |
| `tsgo --checkers 4` *(default)* | 654,824 | 3.95× |
| `tsgo --checkers 8` | 1,307,120 | 7.89× |

Both: **0 errors**, on the same 8 committed files. The "~4×" is not a mysterious
constant — it is the **default checker count**. The full `--extendedDiagnostics` at the
default `--checkers 4`:

| `--extendedDiagnostics` | TS6 `tsc` | TS7 `tsgo` (default) | tsgo / tsc |
|---|---|---|---|
| Symbols | 158,021 | 357,110 | 2.26× |
| Types | 10,884 | 44,236 | 4.06× |
| **Instantiations** | **165,664** | **654,824** | **3.95×** |

These counts are **machine-independent and zero-variance** — the same on any machine, any
core count. (`GOMAXPROCS` does *not* change them — it is not the checker-count knob; see
the mechanism below.)

## The mechanism

`./mechanism.sh` reproduces all of the following deterministically.

### 1. It is per-checker, not per-thread (`--checkers`, not `GOMAXPROCS`)

Each `tsgo` checker keeps independent type state and re-instantiates the shared surface
once. The count is therefore exactly linear in `--checkers` and **collapses to `tsc` at
`--checkers 1`**. (An earlier framing noted the count was invariant under `GOMAXPROCS=1,2,4,8`
and read that as "intrinsic / not parallelism." That observation actually proves the
opposite: `GOMAXPROCS` does not control the checker count — `--checkers` does — so invariance
under `GOMAXPROCS` was guaranteed and says nothing. The `--checkers` sweep above is the
decisive test.)

### 2. The gap tracks the default checker count (4), then saturates

Regenerate at small file counts (`node pandagen.mjs N`) and watch the full-surface counts.
The redundant surface is incurred once per checker, so the gap grows over the first
`--checkers` (=4) modules — until every checker has work — then saturates:

| modules | `tsc` | `tsgo` (default) | gap |
|---|---|---|---|
| 1 | 163,452 | 173,782 | 10,330 |
| 2 | 163,768 | 333,708 | 169,940 |
| 3 | 164,084 | 493,634 | 329,550 |
| 4 | 164,400 | 653,560 | **489,160** |
| 5 | 164,716 | 653,876 | 489,160 |
| 6 | 165,032 | 654,192 | 489,160 |

`tsc` adds a fixed marginal cost (316 instantiations) per module and instantiates the shared
machinery **once**. `tsgo` adds a *full extra re-instantiation of the shared machinery*
(~163K) for each additional active checker, then drops to the same 316/module marginal once
all checkers are busy. The counts fit an exact linear model, parameterised by the checker
count `C`:

```
tsc           = 163,136 + 316·N                              (shared surface instantiated 1×)
tsgo(C)       = 163,136 + 316·N + (min(N,C) − 1)·163,053      (one extra surface per active checker)
```

The fixed offset at the default `C = 4` is `(4 − 1) × 163,053 = 489,160` — three redundant
instantiations of the shared machinery, distributed over the first four modules. At
`C = 8` with 8 modules every checker instantiates the surface once: `≈ 8 × 163K = 1,307,120`,
exactly the headline `--checkers 8` number.

### 3. It is content-independent (same per-checker factor on a one-line file)

Replace each file with a single `css({ color: "red.500" })` call. The per-module cost
shrinks from ~163K to ~3.5K, but the **multiplier is the checker count**, unchanged:

| modules | `tsc` | `tsgo` (default) |
|---|---|---|
| 1 | 3,459 | 3,464 |
| 2 | 3,459 | 6,928 |
| 3 | 3,459 | 10,392 |
| 4 | 3,459 | **13,856** |
| 5 | 3,459 | 13,856 |
| 6 | 3,459 | 13,856 |

`tsc` is **dead flat** — it instantiates `css`'s machinery once and reuses it for every
module. `tsgo` = per-module-cost × `min(modules, --checkers)` = `3,464 × 4 = 13,856`. The
factor is the checker count, independent of how much any file uses.

### 4. The boundary is the module, not the call

Eight `css()` calls in **eight files** → `tsgo` 13,856 (4×). The same eight calls in
**one file** → `tsgo` 3,485 (`tsc` 3,480) — **1×, identical to tsc**. Within a module
`tsgo` deduplicates instantiations perfectly; the work that gets duplicated is the *shared*
surface, which spans modules and therefore lands on multiple checkers.

## On the "~20% overhead for duplicated types"

The multi-checker design is documented, with the expectation that duplicated types are a
small fraction of total work — hence "~20%." That assumption does not hold for *shared
infrastructure* generics. Here the duplicated `styled-system` surface **is** the dominant
cost, so the overhead is `(C − 1)×` the shared machinery, not 20%: **+295%** at the default
`--checkers 4`, scaling to **+689%** at `--checkers 8`.

In a real app this stacks: every generic-heavy library used widely (Zodios, React Query,
React Table, Formily, Panda) contributes its own shared surface, each re-instantiated per
checker. The offsets **add** instead of diluting, which is why the production app
*sustains* ~2.15× at 3758 files (table below) rather than regressing to ~20%.

## Mechanism proof, Panda-free (`synthetic/`)

To show the effect is **general, not Panda-specific** and needs no `panda codegen`,
`synthetic/` defines a single deliberately-heavy shared generic (a wide mapped type over
~100 keys whose per-key value is a branching-recursive type) and uses it from 8 tiny
modules. `npm run diag:synthetic`:

| run | Instantiations | vs `tsc` |
|---|---|---|
| `tsc` | 8,848 | 1.00× |
| `tsgo --checkers 1` | 8,848 | **1.00× — gap gone** |
| `tsgo --checkers 2` | 17,696 | 2.00× |
| `tsgo --checkers 4` | 35,392 | 4.00× |
| `tsgo --checkers 8` | 70,784 | 8.00× |

**Exactly N×**, 0 errors, no Panda. The shared surface is instantiated once per checker —
the same mechanism as the Panda headline, with the magnitude set by how large the shared
generic surface is. (Note: an *arbitrary* small hand-written generic reproduces the gap-is-
zero-at-`--checkers 1` / linear-in-checkers shape but with a small magnitude — the size of
the gap tracks the size of the shared surface. `synthetic/` uses a deliberately heavy
surface so the scaling reads clearly; Panda remains the real-world-magnitude headline.)

## Scale & linearity (generator)

`npm run gen` (800 files → 808 total with the 8 committed) confirms the offset is fixed per
checker, not per-file:

| `--extendedDiagnostics` (808 files) | TS6 `tsc` | TS7 `tsgo` (default) | tsgo / tsc |
|---|---|---|---|
| Symbols | 360,421 | 559,510 | 1.55× |
| Types | 82,084 | 115,436 | 1.41× |
| **Instantiations** | 418,464 | 907,624 | 2.17× |

Same **+489,160** gap as at 8 files (the surface is instantiated `--checkers` times
regardless of file count). Because the offset is fixed, the *ratio* dilutes as you add cheap
uniform files (3.95× at 8 → 2.17× at 808 → 1.62× at 2000), while the absolute
over-instantiation and the per-checker factor stay constant. Read the absolute gap, not the
ratio.

## Corroboration: peak RSS scales with `--checkers`

The bug is about memory: each checker holds independent type state, so peak RSS climbs with
`--checkers`, and `--checkers 1` / `--singleThreaded` brings `tsgo` back toward (here below)
`tsc`. `./measure.sh` sweeps it. Apple Silicon, macOS, 8 committed files (`maximum resident
set size`, GB):

```
tsc                    ~0.30
tsgo --singleThreaded   0.15
tsgo --checkers 1       0.15
tsgo --checkers 2       0.18
tsgo --checkers 4       0.27   (default)
tsgo --checkers 8       0.46
```

Monotonic in the checker count. At larger inputs (808 files) the default-`--checkers`
interleaved comparison is non-overlapping — `tsc`'s worst run stays below `tsgo`'s best:

```
tsc : 0.36 0.33 0.38 0.38 0.36 0.36 0.34 0.37 0.36 0.35 0.37 0.34   (max 0.38 GB)
tsgo: 0.51 0.50 0.50 0.49 0.49 0.48 0.51 0.50 0.50 0.49 0.52 0.48   (min 0.48 GB)
```

`tsgo` is also ~10× faster at the default `--checkers` — the per-checker memory cost is the
price of that parallelism, not a free lunch.

### Mitigation

`--checkers 2`, `--checkers 1`, or `--singleThreaded` trades throughput for memory and
removes the duplication — the actionable memory knob for constrained CI today. (See the
questions below for whether this is the intended answer.)

### Caveats (please read before dismissing)

- **Measure memory interleaved.** `tsc`'s peak RSS is high-variance (V8 GC timing) and can
  swing widely on larger inputs; comparing a separately-measured `tsc` low run against
  `tsgo` is invalid. `measure.sh` interleaves a fresh `tsc` baseline every round on purpose.
- **Read the absolute instantiation gap, not the ratio.** The regression is a *fixed*
  per-checker offset, so the ratio shrinks as cheap files dilute it. The real app *sustains*
  ~2.15× at 3758 files because it stacks many generic-heavy libraries (Zodios, React Query,
  React Table, Formily) on top of Panda — each contributes its own per-checker offset, so
  they add instead of diluting. This repro isolates the single biggest one.
- **Don't compare the two tools' "Memory used" lines.** `tsc`'s `--extendedDiagnostics`
  "Memory used" is a cumulative V8 allocation counter (exceeds real peak RSS); `tsgo`'s is
  Go live heap. They are not comparable. Use peak RSS for memory and the instantiation
  count for the deterministic signal.

---

## Real-world numbers (private codebase — comparable metrics only)

Large production React app, 3758 files, identical 0 errors from both:

| Metric (3758 files) | TS6 `tsc` | TS7 `tsgo` (default) | tsgo / tsc |
|---|---|---|---|
| Symbols | 2.15 M | 4.88 M | 2.3× |
| Types | 749 K | 2.13 M | 2.8× |
| Instantiations | 37.7 M | 81.2 M | 2.15× |
| Peak RSS (interleaved) | ~2.1 GB | ~3.3 GB | ~1.6× |

`tsgo --singleThreaded` reproduces `tsc`'s instantiation count here too, and lowers peak RSS
toward `tsc` — consistent with the per-checker mechanism above.

## Environment

| | |
|---|---|
| OS / arch | macOS (Darwin 25.5.0), Apple Silicon `arm64`, 12 cores |
| Node | v22.16.0 |
| `typescript` | 6.0.3 |
| `@typescript/native-preview` | 7.0.0-dev.20260604.1 |
| default `--checkers` | 4 |

```bash
node --version
npx tsc --version     # -> Version 6.0.3
npx tsgo --version    # -> Version 7.0.0-dev.20260604.1
```

Versions are pinned in `package.json` for deterministic counts. Please re-confirm on
`@typescript/native-preview@latest` — the *saturation* count tracks the default `--checkers`
(4 here), so if a future build changes that default the saturation point shifts with it; the
`--checkers` sweep itself is invariant.

## Questions for the TypeScript team

1. **Shared-infrastructure generics are re-instantiated per checker.** Types used by most
   files (a CSS-in-TS surface, an API-client schema layer, a table/forms library) are
   instantiated once per checker, so for these the cost is ~N×, not ~20%. Is there a path to
   **share hot / widely-used instantiations across checkers** — e.g. a shared instantiation
   cache for library/`node_modules` types — while keeping per-file checking independent?
2. **Peak RSS scales with `--checkers`.** Is lowering `--checkers` (or `--singleThreaded`)
   the intended memory knob for memory-constrained CI, or is shared-instantiation hoisting
   on the roadmap? If lowering `--checkers` is the answer, is there guidance on the
   speed/memory trade-off for large programs?
