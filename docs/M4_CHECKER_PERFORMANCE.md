# M4-G5F8P — Checker refactor performance probe

## Purpose and status

The structural M4-G5F8N and M4-G5F8O refactors consolidate pure syntax
wrapper traversal and provenance validation of three distinct, widened
Boolean `let` guards. Neither refactor was originally a measured
optimization. This experiment asks whether the checker-only latency
changed while preserving work and diagnostics.

**Scope:** internal primitive checker only. This is **not** an end-to-end
compiler benchmark, not a TypeScript conformance score, not a comparison
with Microsoft TypeScript, tsgo, Rust, Zig or C++, and not a result that
can be extrapolated to real projects.

## Pinned comparison

| Lane | Compiler revision | Meaning |
|---|---|---|
| pre-N | `e8faff8f61b17f9d6bc58ca7ba106b4fd8fe229a` | G5F8M, before wrapper consolidation |
| post-N | `5514c229be14af89e443467f32505b8ace6420b1` | G5F8N, after wrapper consolidation |
| post-O | `6ce293434fde1ec72a0fc8a01814cb33414ed1c8` | G5F8O, after mixed guard provenance consolidation |

The same driver `src/checkbench/main.odin` is copied verbatim into
each detached historical checkout. All three versions are built on
the *same* GitHub Actions Ubuntu 24.04 runner with pinned Odin
`dev-2026-10`, verified release SHA256 and `-o:speed`.
Every run uses the same source file, compiler flags and native checker
`.None` code path. Parser and binder run **once per process**,
then the actual `checker.check_file` runs **8,192 times** with normal
report destruction, including internal diagnostics and allocations.
Each check contributes to a checksum that is compared *exactly*
across all revisions and all repetitions. Incorrect/unsupported
results cause a hard failure before they can be interpreted as faster.

The external Node sampler measures wall time for the *whole process*:
process startup, parsing, binding and output are **included** and
amortized, **not** magically subtracted. Thus this is a repeated
checker-dominated process time, not a pure single-check cycle count.

The seven unmodified, TS7-witnessed fixtures are a simple primitive
control, Boolean identity, negated identity, mixed-right, mixed-left,
nested mixed with diagnostics, and homogeneous three-way nested guard.
Each lane receives two warmup executions and 12 timed samples per
workload; six balanced permutations are repeated twice.
The JSON artifact retains the raw samples, medians, relative median
absolute deviation, split-half drift, CPU/OS, revisions, checksum
and reproducibility metadata. The runner labels an individual
workload unstable when *any* lane has relative MAD greater than 8%
or split-half drift greater than 12%. This within-run threshold
does not certify between-run or across-host stability.
No CPU pinning or perf counters are claimed.

To reproduce: open `.github/workflows/checker-perf.yml`, run
`workflow_dispatch`, download `checker-refactor-perf-<run-id>`,
and inspect `checker-benchmark.json`. The same workflow runs on
related pull requests. Independently, `Bootstrap CI` must build,
self-test and smoke-run the driver. The existing pinned TypeScript
7.0.2 code/UTF-16-start oracle and supplemental TS6.0.2 structured
span witnesses remain separate **correctness** gates.

## Exploratory GitHub runner observations — 9 October 2026

Median wall-time **post-O / pre-N** (below 1.0 means lower measured
time, above 1.0 means higher measured time):

| Fixture | Run 37902658343 | Run 37902837978 | Run 37903234282 |
|---|---:|---:|---:|
| checker-primitives-valid | 0.9957× | 0.9580× | 0.9728× |
| checker-boolean-identity-valid | 1.0134× | 1.0236× | 1.0306× |
| checker-negated-identity-valid | 1.0019× | 1.0474× | 1.0539× |
| checker-flow-mixed-rhs-valid | 1.0408× | 1.0531× | 1.0589× |
| checker-flow-mixed-left-valid | 1.0139× | 1.0300× | 1.0414× |
| checker-flow-mixed-nested-errors | 1.0257× | 1.0309× | 1.0203× |
| checker-flow-three-nested-valid | 0.9921× | 0.9914× | 1.0082× |

- [First complete run](https://github.com/megaalive/tsodin/actions/runs/37902658343)
- [Second complete run](https://github.com/megaalive/tsodin/actions/runs/37902837978)
- [Third complete run](https://github.com/megaalive/tsodin/actions/runs/37903234282)

All seven cases retained **exact checker checksum parity across all
three versions**. In these three exploratory measurements, mixed-right
guards cost around 4–6% more wall time post-O versus pre-N; other
cases range from small reductions to increases. Run-to-run variance
is visible even in the control and negated-identity cases, so this
does **not** establish a portable or production regression and cannot
prove an optimization win. The full raw results are in time-limited
CI artifacts; the compact table is retained in the repository.

## Decision and next experiment

**Keep the correctness/maintenance refactors N/O for now.** They
remove duplicated guards and strengthen index/provenance checking.
Do not introduce unchecked indexing, hand-inlining, source
special cases or a general CFG to chase small differences from a
shared runner. If mixed-right overhead remains relevant, repeat
the same three-version protocol on one controlled bare-metal host
with CPU governor/affinity and longer measurement intervals,
then inspect generated code/branch and allocation profiles.
Treat any subsequently optimized guard path as a separate PR,
with the full pinned semantic witness gate *and* before/after
benchmarks. If it does not win consistently, reject it.

**No headline performance claim is authorized by this record.**

## M4-G5F8Q — compiler-directed mixed-guard inline experiment

Only the **two call sites** of `three_distinct_wide_boolean_lets`
are forced inline using Odin's `#force_inline`. The predicate still
validates all indexes, three independent declarations, proven-wide
Boolean types and mutable `let` provenance. No optimization is
allowed to change branch entailment, diagnostic order or allocation
ownership.

Q compares the precise historical `pre-N` and `post-O` revisions
with the experimental PR commit in the same Ubuntu runner, using the
**same** `src/checkbench/main.odin`, pinned Odin and balanced
three-way execution orders. `tools/perf/compare-checker-q.mjs` emits
complete machine-readable samples and checksums for all seven fixtures.

### First exploratory Q measurement (9 October 2026)

[Full Actions log and downloadable raw samples](https://github.com/megaalive/tsodin/actions/runs/37905740716)

| Source-backed fixture | Candidate / post-O |
|---|---:|
| checker-primitives-valid | 0.9977× |
| checker-boolean-identity-valid | 0.9730× |
| checker-negated-identity-valid | 0.9788× |
| checker-flow-mixed-rhs-valid | 0.9700× |
| checker-flow-mixed-left-valid | 0.9611× |
| checker-flow-mixed-nested-errors | 0.9808× |
| checker-flow-three-nested-valid | 0.9686× |

Every result checksum matched across all revisions. These ratios
are *exploratory*, include process startup and cannot yet establish
a stable overall speedup. Subsequent independent runs must support
any keep/reject decision.

### Second exploratory Q measurement (9 October 2026)

[Independent Actions run and raw samples](https://github.com/megaalive/tsodin/actions/runs/37905967534)

| Fixture | Q / post-O, first run | Q / post-O, second run |
|---|---:|---:|
| checker-primitives-valid | 0.9977× | 0.9987× |
| checker-boolean-identity-valid | 0.9730× | 0.9608× |
| checker-negated-identity-valid | 0.9788× | 0.9587× |
| checker-flow-mixed-rhs-valid | 0.9700× | 0.9786× |
| checker-flow-mixed-left-valid | 0.9611× | 0.9713× |
| checker-flow-mixed-nested-errors | 0.9808× | 0.9768× |
| checker-flow-three-nested-valid | 0.9686× | 1.0054× |

Both runs passed full semantic checksums. Homogeneous three-way
guard results disagree on direction, and runner variability remains
a concern. The candidate improves mixed guards in both runs, but
without controlled-host confirmation is still **exploratory**.

### Third exploratory Q measurement and bounded decision

[Third Actions run and raw samples](https://github.com/megaalive/tsodin/actions/runs/37906144224)

| Fixture | Q / post-O, third run |
|---|---:|
| checker-primitives-valid | 1.0020× |
| checker-boolean-identity-valid | 0.9679× |
| checker-negated-identity-valid | 0.9812× |
| checker-flow-mixed-rhs-valid | 0.9746× |
| checker-flow-mixed-left-valid | 0.9691× |
| checker-flow-mixed-nested-errors | 0.9796× |
| checker-flow-three-nested-valid | 0.9889× |

Across these three unpinned-host GitHub runner measurements,
`checker-flow-mixed-rhs-valid` improved to 0.9700× / 0.9786× /
0.9746× candidate/post-O; `checker-flow-mixed-left-valid` to
0.9611× / 0.9713× / 0.9691×. All seven checksum witnesses
matched exactly across each historical and candidate lane.

**Bounded decision:** keep the two forced-inline call sites as a
small, reversible code-generation candidate with supporting repeated
exploratory evidence. They preserve every existing source-level guard
and no extra allocation or analyzer path. Do not claim the project
or TypeScript checker is categorically faster: the effect applies to
this pinned optimized Odin build and selected fixtures, includes
process startup, and is not yet corroborated on a controlled host.
If a future Odin release or controlled benchmark reverses the
result, remove the directives rather than weakening provenance
validation.

### GitHub Pages performance-publication contract

The Observatory should eventually receive a dedicated
**Benchmark** view, populated only by a versioned structured
performance record, with *all* of the following gates:

1. Exact commit SHA of **each** lane, pinned compiler/toolchains,
   host CPU/OS, optimization flags, corpus ID and corpus digest.
2. Explicit comparable semantic work, complete diagnostic or
   checksum parity, independent oracle/conformance eligibility.
3. Warmup, randomized or balanced order, complete raw sample links,
   median, relative MAD, split-half drift and stated stability gate.
4. Controlled physical host or comparable documented dedicated
   environment for a **headline** benchmark; shared GitHub Actions
   is exploratory, never eligible for global ranking.
5. Clear distinction between checker-only microprobes and equivalent
   end-to-end TypeScript checker comparisons. No mixing these ratios.
6. A validator that defaults to `NOT MEASURED` and rejects incomplete,
   stale, wrong-revision, or self-certified promotional results.

The page should show **benchmarks only after eligible publication**,
not turn pinned TS7 diagnostic witness counts into speed scores.
The current status remains **no eligible headline benchmark**. A
faster exploratory microprobe is evidence for engineering only.

