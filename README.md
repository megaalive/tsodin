# tsodin

> Yet another TypeScript checker/compiler — this time in Odin. The real compiler and its evidence will do the talking.

tsodin is an experimental, performance-first TypeScript checker/compiler designed for an Odin-native architecture, not a mechanical port of TypeScript, tsgo or a Rust implementation.

**Make semantics obvious. Make data compact. Make hot paths ruthless. Document every non-obvious reason. Measure everything.**

## Status

M0 is **closed**: the pinned CLI intentionally rejects `check`, with Unicode reference tests and CI. **M1 remains active**: source versions, a bounded scanner, contextual rescans and nested template tracking are implemented, but full scanner parity is not yet established. **M2-A is implemented**: an intentionally narrow parser handles basic `var`/`let`/`const` declarations with primitive annotations and simple literal initializers. A complete TypeScript parser, binder, checker, C0/C1 compatibility and end-to-end performance are **not yet established**.

- [M1-A: source-version/index contract](docs/M1_SOURCE.md)
- [M1-B–E: scanner and contextual witness](docs/M1_SCANNER.md)
- [M2-A: declaration-parser subset](docs/M2_PARSER.md)

There are **no TypeScript compatibility or compiler performance claims**.

- [Execution plan and gates](docs/EXECUTION.md)
- [Architectural decision](docs/RESEARCH_TRANSFER.md)
- [Compatibility/oracle contract](docs/ORACLE.md)
- [TypeScript version policy (including future TS8)](docs/COMPATIBILITY.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Memory model](docs/MEMORY.md)
- [Performance doctrine](docs/PERFORMANCE.md)
- [Benchmarking](docs/BENCHMARKING.md)
- [Hack registry](docs/HACKS.md)
- [Agent/contributor rules](AGENTS.md)

## Public Compiler Observatory

**https://megaalive.github.io/tsodin/**

A static dashboard that fetches **current public GitHub repository commits, workflow runs and source paths on demand**, explicitly identifying unavailable data. It includes a separate browser-only Unicode position reference. It does not publish historical prototype benchmarks or claim an operational Odin TypeScript checker. See [Observatory maintenance](docs/OBSERVATORY.md).

## Local bootstrap

The M0 toolchain is pinned in [bench/manifests/baselines.json](bench/manifests/baselines.json).

```sh
odin test src/source
odin test src/compat
odin test src/scanner
odin test src/context
odin test src/parser
odin build src/cli -out:tsodin
./tsodin --version
./tsodin check    # intentionally exits 2 (not implemented)
```

Linux CI checks the pinned Odin compiler, runs source tests, builds the CLI and tests that the unsupported checker fails closed.

Do not benchmark this bootstrap against TypeScript. Real-project benchmarks require equivalent processing and meaningful diagnostic-parity gates.
