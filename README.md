# tsgo peak RSS scales with `--checkers`: each checker re-instantiates the shared library surface

**TL;DR**

- `tsgo` (TS7 native) runs a pool of checker workers (`--checkers`, default 4), each with its own
  type state. A generic surface that most files share — a CSS-in-TS layer (Panda CSS, in this
  repro), an API-client schema, a table/forms library — is instantiated once *per checker*, not
  once per program.
- Peak RSS and instantiation count both scale linearly in `--checkers`. On a real 3758-file app the
  default `--checkers 4` costs **~1.6× `tsc`'s peak RSS and 2.15× its instantiations — for the same
  0 errors** from both tools. `--checkers 1` / `--singleThreaded` collapses both to `tsc`'s numbers.
- This is the **memory** cost of the mechanism [#2859][2859] closed on **speed**, and unlike #2859
  it is not user-fixable: every file legitimately does `import { css } from "styled-system/css"` —
  there is no cross-file reference chain to restructure.

`tsgo` is ~10× faster than `tsc` here; the cost is memory. Every comparison below is same-input,
same-result, different memory.

---

## Reproduce

The headline is Panda-free and needs no codegen — 8 tiny committed modules that share one
deliberately heavy generic, checked with `tsc` and with `tsgo` at `--checkers 1,2,4,8`:

```bash
npm install
npm run diag:synthetic   # instantiations are exactly linear in --checkers
```

Instantiations come out exactly N× the checker count, collapsing to `tsc` at `--checkers 1`:

| run | Instantiations | vs `tsc` |
|---|---|---|
| `tsc` (TS6) | 8,848 | 1.00× |
| `tsgo --checkers 1` | 8,848 | 1.00× |
| `tsgo --checkers 2` | 17,696 | 2.00× |
| `tsgo --checkers 4` *(default)* | 35,392 | 4.00× |
| `tsgo --checkers 8` | 70,784 | 8.00× |

The same effect on a real library surface (Panda CSS) needs codegen first:

```bash
npm run setup            # panda codegen -> ./styled-system (the heavy shared library types)
npm run diag:checkers    # tsc vs tsgo --checkers 1,2,4,8 on 8 committed src/example*.tsx
./measure.sh             # interleaved peak-RSS sweep across --checkers (the memory evidence)
./mechanism.sh           # full deterministic fingerprint (ramp, saturation, content-independence)
```

---

## Relation to #2859

The per-checker duplication is known. In [#2859][2859] Anders Hejlsberg explained the mechanism and
closed it as working as expected:

> "we create four checkers (by default) and assign them each a quarter of the files… each of the
> four checkers ends up checking *all* of the fragments… 32M instantiations jumping to 125M in
> concurrent mode. That's pretty much 4x, meaning each of the 4 type checkers repeats the same
> very expensive work."

That was a *speed* report, resolved on speed. Two things make the memory cost worth surfacing:

1. **Memory, not speed.** "Each checker repeats the work" is also the memory mechanism: each
   checker holds that work in its own live type state, so peak RSS scales with `--checkers` even
   when wall-clock is great. #2859 never measured memory.
2. **Unavoidable for library types.** #2859 was fixed by restructuring the *user's* cross-file
   reference chains. Shared library infrastructure has no analogue — every file legitimately does
   `import { css } from "styled-system/css"`. The [content-independence test](#full-mechanism)
   uses 8 independent one-line files with only that shared import and still gets the full
   `--checkers`× factor: there is no chain to break.

Related: [#2454](https://github.com/microsoft/typescript-go/issues/2454) (closed,
[PR #2466](https://github.com/microsoft/typescript-go/pull/2466)) added a *within-checker* `keyof
T` cache — nothing is shared *across* checkers.
[#2115](https://github.com/microsoft/typescript-go/issues/2115) is the open checker-pool design
discussion.

---

## Memory: peak RSS scales with `--checkers`

`./measure.sh` sweeps peak RSS across `--checkers`. Apple Silicon, macOS, 8 committed Panda files
(`maximum resident set size`, GB):

```
tsc                    ~0.30
tsgo --singleThreaded   0.15
tsgo --checkers 1       0.15
tsgo --checkers 2       0.18
tsgo --checkers 4       0.27   (default)
tsgo --checkers 8       0.46
```

Monotonic in the checker count. At 808 files the default-`--checkers` interleaved comparison is
non-overlapping — `tsc`'s worst run stays below `tsgo`'s best:

```
tsc : 0.36 0.33 0.38 0.38 0.36 0.36 0.34 0.37 0.36 0.35 0.37 0.34   (max 0.38 GB)
tsgo: 0.51 0.50 0.50 0.49 0.49 0.48 0.51 0.50 0.50 0.49 0.52 0.48   (min 0.48 GB)
```

The deterministic mirror of the same story: on the Panda surface instantiations go
**165,664** (`tsc`) → **654,824** (`tsgo`, default 4) = **3.95×**, collapsing to `tsc`'s count at
`--checkers 1` / `--singleThreaded`. Same shape as the synthetic table above, at real-library
magnitude.

### Caveats

- **Measure memory interleaved.** `tsc`'s peak RSS is high-variance (V8 GC timing); comparing a
  separately measured low `tsc` run against `tsgo` is invalid. `measure.sh` interleaves a fresh
  `tsc` baseline every round.
- **Don't compare the two tools' "Memory used" lines.** `tsc`'s `--extendedDiagnostics` "Memory
  used" is a cumulative V8 allocation counter (exceeds real peak RSS); `tsgo`'s is Go live heap.
  Use peak RSS for memory, the instantiation count for the deterministic signal.
- **Read the absolute instantiation gap, not the ratio.** It is a fixed per-checker offset, so the
  ratio shrinks as cheap files dilute it (3.95× at 8 files → 2.17× at 808). The absolute
  over-instantiation and the per-checker factor stay constant.

---

## Real-world magnitude

The synthetic surface proves the *shape*; Panda shows the *magnitude* on a real shared library. At
the default `--checkers 4`, 8 committed files:

| `--extendedDiagnostics` | TS6 `tsc` | TS7 `tsgo` (default) | tsgo / tsc |
|---|---|---|---|
| Symbols | 158,021 | 357,110 | 2.26× |
| Types | 10,884 | 44,236 | 4.06× |
| **Instantiations** | **165,664** | **654,824** | **3.95×** |

The cost stacks across libraries. Every widely used generic-heavy dependency (Panda, Zodios, React
Query, React Table, Formily) contributes its own shared surface, re-instantiated per checker. The
per-checker offsets add instead of diluting — which is why a real 3758-file app *sustains* ~2.15×
(below) rather than regressing toward parity as file count grows. For shared-infrastructure
generics the duplicated surface *is* the dominant cost, so the overhead is `(C − 1)×` the shared
machinery — +295% at `--checkers 4`, +689% at `--checkers 8`.

Large production React app, 3758 files, identical 0 errors from both tools:

| Metric (3758 files) | TS6 `tsc` | TS7 `tsgo` (default) | tsgo / tsc |
|---|---|---|---|
| Symbols | 2.15 M | 4.88 M | 2.3× |
| Types | 749 K | 2.13 M | 2.8× |
| Instantiations | 37.7 M | 81.2 M | 2.15× |
| Peak RSS (interleaved) | ~2.1 GB | ~3.3 GB | ~1.6× |

`tsgo --singleThreaded` reproduces `tsc`'s instantiation count here too and lowers peak RSS toward
`tsc`. (Private codebase; only tool-comparable metrics shown.)

---

## Full mechanism

<details>
<summary><code>./mechanism.sh</code> reproduces all of the following deterministically (machine-independent, zero-variance).</summary>

### 1. Linear in `--checkers`, not `GOMAXPROCS`

Each `tsgo` checker keeps independent type state and re-instantiates the shared surface once, so
the count is exactly linear in `--checkers` and collapses to `tsc` at `--checkers 1`. Invariance
under `GOMAXPROCS=1,2,4,8` is guaranteed — `GOMAXPROCS` is not the checker-count knob — so the
`--checkers` sweep is the decisive test.

### 2. The gap tracks the default checker count (4), then saturates

Full Panda surface, regenerated at small file counts (`node pandagen.mjs N`):

| modules | `tsc` | `tsgo` (default) | gap |
|---|---|---|---|
| 1 | 163,452 | 173,782 | 10,330 |
| 2 | 163,768 | 333,708 | 169,940 |
| 3 | 164,084 | 493,634 | 329,550 |
| 4 | 164,400 | 653,560 | **489,160** |
| 5 | 164,716 | 653,876 | 489,160 |
| 6 | 165,032 | 654,192 | 489,160 |

`tsc` adds a fixed marginal cost (316 instantiations) per module and instantiates the shared
machinery once. `tsgo` adds a full extra re-instantiation (~163K) per active checker, then drops to
the same 316/module once all checkers are busy. The linear model, parameterised by checker count
`C`:

```
tsc      = 163,136 + 316·N                              (shared surface instantiated 1×)
tsgo(C)  = 163,136 + 316·N + (min(N,C) − 1)·163,053     (one extra surface per active checker)
```

At `C = 4`: `(4 − 1) × 163,053 = 489,160`. At `C = 8` with 8 modules: `≈ 8 × 163K = 1,307,120`,
the headline `--checkers 8` number.

### 3. Content-independent (the no-chain-to-break proof)

Replace each file with a single `css({ color: "red.500" })` call — 8 independent modules, zero
cross-references, only the shared library import. The per-module cost shrinks from ~163K to ~3.5K,
but the multiplier is still the checker count:

| modules | `tsc` | `tsgo` (default) |
|---|---|---|
| 1 | 3,459 | 3,464 |
| 2 | 3,459 | 6,928 |
| 3 | 3,459 | 10,392 |
| 4 | 3,459 | **13,856** |
| 5 | 3,459 | 13,856 |
| 6 | 3,459 | 13,856 |

`tsc` is dead flat. `tsgo` = per-module-cost × `min(modules, --checkers)`. The duplicated work is
the shared library surface, which every independent file pulls in.

### 4. The boundary is the module, not the call

Eight `css()` calls in eight files → `tsgo` 13,856 (4×). The same eight calls in one file → `tsgo`
3,485 (`tsc` 3,480) — 1×, identical to `tsc`. Within a module `tsgo` deduplicates perfectly; the
duplicated work is shared across modules and so lands on multiple checkers.

### Mechanism proof, Panda-free (`synthetic/`)

`synthetic/` defines one deliberately heavy shared generic (a wide mapped type over ~100 keys whose
per-key value is a branching-recursive type) and uses it from 8 tiny modules. It reproduces the
exactly-N× scaling with no Panda and no codegen (the headline table at the top). The size of the
gap tracks the size of the shared surface.

</details>

---

## Mitigation today

`--checkers 2`, `--checkers 1`, or `--singleThreaded` trades throughput for memory and removes the
duplication — the actionable memory knob today.

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

Versions are pinned for deterministic counts. The saturation count tracks the default `--checkers`
(4 here); the `--checkers` sweep itself is invariant.

[2859]: https://github.com/microsoft/typescript-go/issues/2859
