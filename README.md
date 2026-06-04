# tsgo (TS7 native) over-instantiates vs tsc (TS6) on Panda CSS code

**Claim:** On identical, error-free TypeScript that uses [Panda CSS](https://panda-css.com/),
the native compiler **`tsgo` performs ~2× the type *instantiations* `tsc` does**, and
this shows up as a **robust peak-memory gap**. The instantiation counts are
deterministic (machine-independent); the memory gap survives interleaved
measurement. Zero proprietary code — only public packages + a generator.

This is the minimized form of a regression seen on a large production React app
(3758 files), where `tsgo` uses ~1.6× the peak RSS of `tsc`. A `tsc --generateTrace`
of that app puts Panda CSS styled components at the top of the hot list.

---

## Run it

```bash
npm install
npm run setup          # panda codegen -> generates ./styled-system (the heavy types)
npm run gen            # generates ./src (default 800 files; `node pandagen.mjs 1500` for more)
./measure.sh 8         # interleaved peak RSS, 8 rounds, + deterministic counts
```

`measure.sh` interleaves `tsc` and `tsgo` back-to-back (controls for machine-state
drift and V8 GC-timing variance) and prints peak RSS per round plus the
`--extendedDiagnostics` counts. macOS and Linux supported.

Both tools report **0 errors** → identical, valid work.

---

## The signal: deterministic instantiation multiplier

This is the headline because it is **machine-independent and zero-variance** — you
will see the same counts on any machine (`npm run diag:ts6` / `npm run diag:ts7`).
At the default 800 files:

| `--extendedDiagnostics` | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 358,397 | 557,486 | 1.56× |
| Types | 81,372 | 114,724 | 1.41× |
| **Instantiations** | 415,936 | **905,096** | **2.18×** |

`tsgo` materializes roughly twice the instantiations `tsc` does for the same code.

## Corroboration: peak RSS (interleaved)

Apple Silicon, macOS, `typescript@6.0.3`, `@typescript/native-preview@7.0.0-dev.20260604.1`.
8 interleaved rounds, 800 files (`maximum resident set size`):

```
tsc : 0.38 0.40 0.39 0.39 0.38 0.41 0.34 0.39   (max 0.41 GB)
tsgo: 0.51 0.50 0.51 0.51 0.49 0.49 0.51 0.51   (min 0.49 GB)
```

Non-overlapping: `tsc`'s worst run (0.41 GB) is below `tsgo`'s best (0.49 GB).
`tsgo` is also ~10× faster — this is a speed/memory trade-off, not a free lunch.

### Honest caveats (please read before dismissing)

- **Measure interleaved.** `tsc`'s peak RSS is high-variance (V8 GC timing) and can
  swing ~0.8–1.8 GB on larger inputs; comparing a separately-measured `tsc` low run
  against `tsgo` is not valid. `measure.sh` interleaves on purpose.
- **The multiplier is highest where styling dominates.** It comes largely from
  `tsgo` eagerly instantiating Panda's fixed `styled-system` type machinery (~5× what
  `tsc` does). As you add cheap per-file code, the *equal* marginal cost dilutes the
  ratio — at 2000 uniform files here it falls to ~1.6× instantiations. The real app
  *sustains* ~2.15× at 3758 files because it stacks more generic-heavy libraries
  (Zodios, React Query, React Table, Formily) on top of Panda. This minimal repro
  isolates the single biggest contributor.
- **Don't compare `tsc`'s "Memory used" to `tsgo`'s.** `tsc`'s `--extendedDiagnostics`
  "Memory used" is a cumulative V8 allocation counter (it exceeds actual peak RSS),
  while `tsgo`'s is Go live heap. They are not comparable. Use `maximum resident set
  size` (peak RSS) for memory, and the instantiation count for the deterministic signal.

---

## Real-world numbers (private codebase — comparable metrics only)

Large production React app, 3758 files, identical 0 errors from both,
`--extendedDiagnostics` (deterministic) + interleaved peak RSS:

| Metric (3758 files) | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 2.15 M | 4.88 M | 2.3× |
| Types | 749 K | 2.13 M | 2.8× |
| Instantiations | 37.7 M | 81.2 M | 2.15× |
| Peak RSS (interleaved) | ~2.1 GB | ~3.3 GB | ~1.6× |

The native checker materializes ~2× the type/instantiation objects for the same
program. Single-threaded (`GOMAXPROCS=1 tsgo`) reproduces the same peak RSS, so it
is intrinsic to the checker's data structures, not a parallelism artifact.

## Questions for the TypeScript team

1. Is `tsgo` expected to perform ~2× the instantiations `tsc` does on Panda-style
   code, or does this indicate missing instantiation/type caching vs `tsc`?
2. Is there a heap budget / GC knob recommended for `tsgo` in memory-constrained CI?
