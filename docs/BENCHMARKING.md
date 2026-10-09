# Benchmarking Doctrine

## Purpose

Benchmarks are part of tsodin's correctness and engineering process, not marketing decoration.

Public posture:

> **The benchmarks can do the talking.**

That requires benchmarks that survive scrutiny.

## Correctness first

A performance result is ineligible unless compared lanes perform equivalent work and produce equivalent semantics/output.

Depending on the benchmark, require exact checksum parity, differential comparison against a reference, TypeScript conformance tests, expected diagnostics, or deterministic output comparison.

Do not trade semantic work for benchmark speed.

## No benchmark gaming

Do not:

- remove work from only one lane;
- use easier input for tsodin;
- disable required correctness checks without an equivalent invariant;
- special-case known benchmark answers;
- change expected output after seeing timing;
- silently alter flags or workload;
- cherry-pick samples;
- repeatedly rerun until a favorable number appears and discard the rest.

If methodology changes intentionally, record a new protocol.

## Reproducibility

Important benchmark records should include:

- exact tsodin commit;
- exact reference commit;
- compiler/toolchain versions;
- optimization flags;
- host/OS/CPU;
- warmup policy;
- sample count;
- affinity policy when used;
- raw results or durable artifact;
- checksums/conformance state;
- binary identity when useful.

## Stability

Do not interpret a lucky timing as a win.

Each benchmark family should define stability gates appropriate for its duration and host.

Useful statistics include median, relative MAD, split-half drift, execution-order bias, and paired measurements.

Virtualized PMU counters are secondary evidence unless their reliability is independently established.

Stable wall time remains the primary result for latency/throughput comparisons.

## Isolate changes

Performance work should prefer one interpretable hypothesis per experiment.

Good:

    P2: compact value representation
    P3: branch-light relation-state path
    P4: specialize value flow

Bad:

    changed allocator + hash + layout + loop + flags
    result is 7% faster

Combined changes are acceptable when they cannot reasonably be separated, but that limitation must be stated.

## Benchmark layers

The real project should eventually cover at least:

- scanner/tokenizer throughput;
- parser throughput and memory;
- binder/symbol-table construction;
- module resolution;
- type relation / assignability;
- generic instantiation and cache behavior;
- cold full check;
- warm repeated check;
- incremental rebuild;
- monorepo/project graph;
- parallel scaling;
- peak RSS / retained memory;
- diagnostics equivalence;
- conformance/correctness.

Microbenchmarks are diagnostic tools. They are not substitutes for project-level TypeScript workloads.

## Reference competitors

Reference implementations and competitor projects must be pinned to exact revisions for formal comparison.

README claims from another project are not evidence until reproduced under tsodin's protocol.

## Result language

Use precise statements.

Good:

    On workload X, commit A measured 0.91x the wall time of reference B.

Bad:

    Odin is 9% faster than Rust.

A benchmark result belongs to its workload, toolchain, machine, and protocol.

## Evidence retention

Store compact decision records in git. Large raw artifacts may live in CI artifacts or separately archived evidence, but the repository must retain enough metadata to reconstruct the decision.

Do not let the only copy of benchmark reasoning live in a chat.

## Checker refactor microprobe (M4-G5F8P)

[Reproducible three-revision checker-only comparison](M4_CHECKER_PERFORMANCE.md)
records pinned Odin, exact revisions, identical semantic work/checksums,
balanced observations, raw artifacts, and explicitly limited conclusions.
It is diagnostic instrumentation, never a substitute for equivalently
correct end-to-end TypeScript benchmarks.
