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
| checker-primitives-valid | 0.9957× | 0.9580×  0.9728× |
| checker-boolean-identity-valid | 1.0134× | 1.0236×  1.0306× |
| checker-negated-identity-valid | 1.0019× | 1.0474×  1.0539× |
| checker-flow-mixed-rhs-valid | 1.0408× | 1.0531×  1.0589× |
| checker-flow-mixed-left-valid | 1.0139× | 1.0300×  1.0414× |
| checker-flow-mixed-nested-errors | 1.0257× | 1.0309×  1.0203× |
| checker-flow-three-nested-valid | 0.9921× | 0.9914×  1.0082× |

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
