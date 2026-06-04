# tsgo (TS7 native) over-instantiates vs tsc (TS6) on Panda CSS code

**Claim:** On identical, error-free TypeScript that uses [Panda CSS](https://panda-css.com/),
the native compiler **`tsgo` performs a fixed ~490K *more* type instantiations than
`tsc`** for the shared `styled-system` type machinery — a **~4× over-instantiation
that is constant regardless of project size** — and this shows up as a **robust
peak-memory gap**. The instantiation counts are deterministic (machine-independent);
the memory gap survives interleaved measurement. Zero proprietary code — only public
packages + a generator.

This is the minimized form of a regression seen on a large production React app
(3758 files), where `tsgo` uses ~1.6× the peak RSS of `tsc`. A `tsc --generateTrace`
of that app puts Panda CSS styled components at the top of the hot list.

---

## Run it

```bash
npm install
npm run setup          # panda codegen -> generates ./styled-system (the heavy types)
npm run gen            # generates ./src (default 800 files; `node pandagen.mjs 1500` for more)
./measure.sh 12        # interleaved peak RSS, 12 rounds, + deterministic counts
```

`measure.sh` interleaves `tsc` and `tsgo` back-to-back (controls for machine-state
drift and V8 GC-timing variance) and prints peak RSS per round plus the
`--extendedDiagnostics` counts. macOS and Linux supported.

Both tools report **0 errors** → identical, valid work.

---

## The signal: a fixed, deterministic over-instantiation

These counts are **machine-independent and zero-variance** — you will see the exact
same numbers on any machine (`npm run diag:ts6` / `npm run diag:ts7`). At the default
800 files:

| `--extendedDiagnostics` | TS6 `tsc` | TS7 `tsgo` | tsgo / tsc |
|---|---|---|---|
| Symbols | 358,397 | 557,486 | 1.56× |
| Types | 81,372 | 114,724 | 1.41× |
| **Instantiations** | 415,936 | **905,096** | **2.18×** |

The ratio alone understates it. Regenerate at several file counts (`node pandagen.mjs N`)
and the instantiation counts fit a **perfectly linear** model (verified at N = 100, 400,
800, 2000 — every point exact):

```
tsc  instantiations = 163,136 + 316·N
tsgo instantiations = 652,296 + 316·N
```

Two facts fall out:

- **The marginal cost is identical** — each added file costs *both* tools exactly 316
  instantiations. `tsgo` is not slower-per-file.
- **The gap is a fixed offset of 489,160 instantiations** — `tsgo` instantiates the
  shared Panda `styled-system` type machinery **4.0× more than `tsc`** (652K vs 163K),
  *once*, independent of file count. This fixed cost is the entire regression.

So the headline ratio shrinks as you dilute the fixed cost with cheap files (2.18× at
800 files → 1.62× at 2000), but the **absolute over-instantiation (~489K) and the 4×
fixed multiplier are constant**. That points squarely at instantiation/type caching of
shared generic types differing between the two checkers.

## Corroboration: peak RSS (interleaved)

Apple Silicon, macOS, `typescript@6.0.3`, `@typescript/native-preview@7.0.0-dev.20260604.1`.
12 interleaved rounds, 800 files (`maximum resident set size`):

```
tsc : 0.34 0.36 0.34 0.34 0.38 0.35 0.35 0.41 0.39 0.37 0.35 0.38   (max 0.41 GB)
tsgo: 0.51 0.50 0.48 0.46 0.49 0.49 0.51 0.50 0.49 0.50 0.51 0.51   (min 0.46 GB)
```

Non-overlapping: `tsc`'s worst run (0.41 GB) stays below `tsgo`'s best (0.46 GB).
`tsgo` is also ~10× faster — this is a speed/memory trade-off, not a free lunch.

### Honest caveats (please read before dismissing)

- **Measure interleaved.** `tsc`'s peak RSS is high-variance (V8 GC timing) and can
  swing ~0.8–1.8 GB on larger inputs; comparing a separately-measured `tsc` low run
  against `tsgo` is not valid. `measure.sh` interleaves on purpose.
- **The ratio dilutes; the absolute gap does not.** The regression is a *fixed* ~489K
  extra instantiations (4.0× on Panda's shared `styled-system` machinery), so as you
  add cheap uniform files with equal marginal cost the *ratio* shrinks (2.18× at 800 →
  1.62× at 2000). Read the absolute gap, not the ratio. (Note: `styled-system` types in
  isolation instantiate *nothing* in either tool — instantiation is lazy, triggered by
  the first `css()`/`cva()`/`styled()` use; the 4× fixed cost is incurred once on first
  use and cached thereafter.) The real app *sustains* ~2.15× at 3758 files because it
  stacks many generic-heavy libraries (Zodios, React Query, React Table, Formily) on top
  of Panda — each contributes its own fixed over-instantiation, so the offsets add up
  instead of diluting. This minimal repro isolates the single biggest contributor.
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

1. Is `tsgo` expected to instantiate the shared `styled-system` type machinery ~4×
   more than `tsc` (a fixed ~489K-instantiation overhead, independent of file count),
   or does this indicate missing instantiation/type caching of shared generic types
   vs `tsc`?
2. Is there a heap budget / GC knob recommended for `tsgo` in memory-constrained CI?
