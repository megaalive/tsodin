# tsodin

> Yet another TypeScript checker/compiler — this time in Odin. The real compiler and its evidence will do the talking.

tsodin is an experimental, performance-first TypeScript checker/compiler designed for an Odin-native architecture, not a mechanical port of TypeScript, tsgo or a Rust implementation.

**Make semantics obvious. Make data compact. Make hot paths ruthless. Document every non-obvious reason. Measure everything.**

## Status

M0 is **closed**. **M1 remains active**: source versions, a bounded scanner, contextual rescans and nested templates are implemented; full scanner parity is not yet established. **M2-A–C are implemented**: declaration parsing, expression precedence and syntax recovery, plus a developer-only source-to-syntax diagnostic tracer with UTF-16 positions. **M3-A–C are implemented**: a one-file binder, cross-file script-global binding, and explicit rejection of unsupported external modules. **M4-A–G5A are implemented as a narrow semantic slice**: primitive number/string/boolean expression checking (including bounded comparisons, strict equality and logical operators), selected TS2322/TS2367 code/UTF-16-start comparisons against native TypeScript 7, and separate supplemental TS6 structured full-span checks. A complete parser, module-aware binder, full type checker, official C0/C1 conformance, native TS7 end-span/message parity and end-to-end performance are **not yet established**.

- [M1-A: source-version/index contract](docs/M1_SOURCE.md)
- [M1-B–E: scanner and contextual witness](docs/M1_SCANNER.md)
- [M2-A: declaration-parser subset](docs/M2_PARSER.md)
- [M2-B/C: expression syntax, recovery, and diagnostic trace](docs/M2_EXPRESSION.md)
- [M3-A–C: symbols, script globals, and module safety boundary](docs/M3_BINDER.md)
- [M4-A–G5A: primitive checker, computed-wide types, and straight-line assignments](docs/M4_CHECKER.md)
- [M4-B–E: expanded TS7 code/start and separate TS6 full-span witnesses](docs/M4_CODE_WITNESS.md)
- [Official TypeScript conformance strategy](docs/OFFICIAL_CONFORMANCE.md)
- [Audited Microsoft source/test inventory and next implementation priorities](docs/UPSTREAM_AUDIT.md)

There are **no full TypeScript compatibility or compiler performance claims**. The CLI `check` command remains disabled; the primitive semantic checker is available only through developer tooling.

**Developer evidence:** `tsodin dump --stage=all examples/typed-mismatch.ts` emits a versioned JSON snapshot of the actual supported scanner/parser/binder/checker slice. Stage statuses and internal error IDs are explicit; M4-G5F8C additionally captures bounded primitive assignment relations at their real checker decision sites. Use `--trace-relations` to include successful decisions; missing general relations are never invented. M4-G5F8F publishes source-backed strict-equality proof categories separately in `tsodin.dump/3`, never claiming that possible overlap means an expression evaluates to true. See [Stage dump contract](docs/STAGE_DUMP.md).

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

A static dashboard that fetches **current public GitHub repository commits, workflow runs and source paths on demand**, explicitly identifying unavailable data. It includes a separate browser-only Unicode position reference **and a read-only Lab tab populated from real pinned Odin stage dumps**. The Lab does not compile user input in JavaScript; its trace gallery is regenerated from curated public examples and CI-checked byte-for-byte. It does not publish historical prototype benchmarks or claim a complete TypeScript checker. See [Observatory maintenance](docs/OBSERVATORY.md).

## Local bootstrap

The M0 toolchain is pinned in [bench/manifests/baselines.json](bench/manifests/baselines.json).

```sh
odin test src/source
odin test src/compat
odin test src/scanner
odin test src/context
odin test src/parser
odin test src/binder
odin build src/cli -out:tsodin
./tsodin --version
./tsodin dump --stage=all examples/typed-mismatch.ts
./tsodin check    # intentionally exits 2 (not implemented)
```

Linux CI checks the pinned Odin compiler, runs source tests, builds the CLI and tests that the unsupported checker fails closed.

Do not benchmark this bootstrap against TypeScript. Real-project benchmarks require equivalent processing and meaningful diagnostic-parity gates.
