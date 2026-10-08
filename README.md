# tsodin

> Yet another TypeScript checker/compiler — this time in Odin. The real compiler and its evidence will do the talking.

tsodin is an experimental, performance-first TypeScript checker/compiler designed for an Odin-native architecture, not a mechanical port of TypeScript, tsgo or a Rust implementation.

**Make semantics obvious. Make data compact. Make hot paths ruthless. Document every non-obvious reason. Measure everything.**

## Status

The M0 bootstrap includes a versioned CLI that intentionally rejects `check` until a real semantic checker exists, a UTF-8/UTF-16 source position reference, tests, a pinned toolchain and CI. Source/scanner and the end-to-end checker remain active future work.

There are **no TypeScript compatibility or compiler performance claims**.

- [Execution plan and gates](docs/EXECUTION.md)
- [Architectural decision](docs/RESEARCH_TRANSFER.md)
- [Compatibility/oracle contract](docs/ORACLE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Memory model](docs/MEMORY.md)
- [Performance doctrine](docs/PERFORMANCE.md)
- [Benchmarking](docs/BENCHMARKING.md)
- [Hack registry](docs/HACKS.md)
- [Agent/contributor rules](AGENTS.md)

## Public Compiler Observatory

**https://megaalive.github.io/tsodin/**

The Observatory is a lightweight, Blue Glassy Soft static dashboard that fetches **current public GitHub repository commits, workflow runs and source paths on demand**, explicitly identifying unavailable data. It includes a separate browser-only Unicode position reference. It does not publish historical prototype benchmarks or claim an operational Odin TypeScript checker. See [Observatory maintenance](docs/OBSERVATORY.md).

## Local bootstrap

The M0 toolchain is pinned in [bench/manifests/baselines.json](bench/manifests/baselines.json).

```sh
odin test src/source
odin build src/cli -out:tsodin
./tsodin --version
./tsodin check    # intentionally exits 2 (not implemented)
```

Linux CI checks the pinned Odin compiler, runs source tests, builds the CLI and tests that the unsupported checker fails closed.

Do not benchmark this bootstrap against TypeScript. Real-project benchmarks require equivalent processing and meaningful diagnostic-parity gates.
