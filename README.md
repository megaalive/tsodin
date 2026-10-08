# tsodin

> Yet another TypeScript checker/compiler — this time in Odin. The benchmarks can do the talking.

tsodin is an experimental, performance-first TypeScript checker/compiler designed for an Odin-native architecture, not a mechanical port of TypeScript, tsgo, or a Rust implementation.

**Make semantics obvious. Make data compact. Make hot paths ruthless. Document every non-obvious reason. Measure everything.**

## Status

M0 foundation work is underway. The initial executable is an honest bootstrap: it reports its development version and rejects `check` until a real semantic checker exists. There are **no TypeScript compatibility or compiler performance claims**.

The first implemented library primitive is a checked UTF-8-byte-prefix to UTF-16-unit mapper, with tests. It is a correctness reference, not a hot-path implementation.

- [Execution plan and gates](docs/EXECUTION.md)
- [Research transfer and benchmark claims](docs/RESEARCH_TRANSFER.md)
- [Compatibility/oracle contract](docs/ORACLE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Memory model](docs/MEMORY.md)
- [Performance doctrine](docs/PERFORMANCE.md)
- [Benchmarking](docs/BENCHMARKING.md)
- [Hack registry](docs/HACKS.md)
- [Agent/contributor rules](AGENTS.md)

## Local bootstrap

The M0 toolchain is pinned in [bench/manifests/baselines.json](bench/manifests/baselines.json).

```sh
odin test src/source
odin build src/cli -out:tsodin
./tsodin --version
./tsodin check    # intentionally returns exit code 2 (not implemented)
```

Linux CI checks the pinned compiler, runs source tests, builds the CLI, and tests that the unsupported checker fails closed.

Do not benchmark this bootstrap against TypeScript. A whole-project benchmark becomes meaningful only after the relevant source files and diagnostics are actually processed at comparable compatibility.
