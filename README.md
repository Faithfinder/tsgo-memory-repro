# tsgo (TS7 native) peak-memory regression vs tsc (TS6)

**Claim:** On identical, error-free, app-realistic TypeScript (React + React Query +
Zod), the native compiler **`tsgo` materializes more symbols/types/instantiations
than `tsc` and uses meaningfully more peak memory**, even though it is ~10× faster.
This is the opposite of the native port's stated goal (lower memory than `tsc`).

This repro contains **zero proprietary code** — only public packages and a generator.

---

## Run it

```bash
npm install
npm run gen            # generates ./src (default 1500 files; `node generate.mjs 3000` for more)

# Peak RSS — macOS:
/usr/bin/time -l npx tsc  -p tsconfig.json     # TS6 (typescript 6.0.3)
/usr/bin/time -l npx tsgo -p tsconfig.json     # TS7 (@typescript/native-preview)
#   look at "maximum resident set size" (bytes)
# Peak RSS — Linux:
/usr/bin/time -v npx tsc  -p tsconfig.json
/usr/bin/time -v npx tsgo -p tsconfig.json
#   look at "Maximum resident set size (kbytes)"

# Type/instantiation counts (deterministic, no noise):
npm run diag:ts6       # tsc  --extendedDiagnostics
npm run diag:ts7       # tsgo --extendedDiagnostics
```

Both tools report **0 errors** → identical, valid work.

---

## Observed (this repro, 1500 generated files)

Machine: Apple Silicon, macOS, 12 cores / 18 GB. `typescript@6.0.3`,
`@typescript/native-preview@7.0.0-dev.20260604.1`.

| | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| **Peak RSS** | 0.88–1.04 GB | **1.28–1.34 GB** | **~1.3×** |
| Wall time | ~22 s | ~2 s | ~0.1× |
| Symbols | 2.02 M | 2.11 M | 1.04× |
| Types | 866 K | 945 K | 1.09× |
| Instantiations | 4.08 M | 4.16 M | 1.02× |

The peak-RSS gap (~30%) exceeds the type-count gap, consistent with Go GC heap
retention amplifying the extra live type objects. Scaling `generate.mjs` higher
widens the absolute gap.

### Not a parallelism artifact

`tsgo` checks across all cores; `tsc` is single-threaded. Forcing `tsgo`
single-threaded (`GOMAXPROCS=1 npx tsgo -p tsconfig.json`) leaves peak RSS
essentially unchanged — the extra memory is intrinsic to the checker's data
structures, not concurrent per-core state.

---

## Real-world signal (private codebase — metrics only, no source)

The same comparison on a large production React app (3758 files) shows a **much
larger** gap, because it stacks more generic-heavy libraries on top (Panda CSS,
Zodios, React-Hook-Form, Formily, React-Table). `--extendedDiagnostics`, identical
0 errors from both:

| Metric (3758 files) | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 2.15 M | 4.88 M | **2.3×** |
| Types | 749 K | 2.13 M | **2.8×** |
| Instantiations | 37.7 M | 81.2 M | **2.15×** |
| Internal "memory used" | 2.07 GB | 2.69 GB | 1.30× |
| **Peak RSS** (`/usr/bin/time -l`, 3 runs) | 1.99 / 2.17 / 1.99 GB | 3.05 / 3.19 / 3.61 GB | **~1.6×** |

A `tsc --generateTrace` of that app puts the hottest files in JSX components,
React-Query/Zodios data hooks, and Panda CSS styled usage — i.e. the same
construct family this repro isolates, just at higher density. The dominant driver
appears to be **`tsgo` creating ~2× the type/instantiation objects `tsc` creates
for the same code**, which this minimal repro reproduces in direction at lower
magnitude.

## What would help

- Whether the higher Symbols/Types/Instantiations counts are expected (different
  accounting) or indicate missing instantiation/type caching vs `tsc`.
- Guidance on a heap budget / GC knob for `tsgo` in memory-constrained CI.
