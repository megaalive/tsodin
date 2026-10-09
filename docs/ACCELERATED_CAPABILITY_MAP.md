# TSODIN — accelerated upstream-first capability map (10 October 2026)

## Source authority and boundaries

- Current upstream implementation map: [Microsoft TypeScript native Go tree](https://github.com/microsoft/TypeScript/tree/aad4c72bf2d22e1fddb2a07d9e6f131e9b2ade44/tsc)
  at revision `aad4c72bf2d22e1fddb2a07d9e6f131e9b2ade44`.
- Independently inspected upstream native code structure: [Microsoft typescript-go](https://github.com/microsoft/typescript-go/tree/89d5d5b2849a0db0957065889ca58536fa6d2e4a)
  at revision `89d5d5b2849a0db0957065889ca58536fa6d2e4a`.
  The TypeScript repo's `tsc/` tree is the main reference; the staging repository
  is supporting source, not a second executable oracle.
- Pinned executable oracle remains Microsoft TypeScript **7.0.2**,
  commit `1e4744d68260a7cb91b62b12edc3f6a2187faaf1`
  (`tests/oracle/profiles.json`). Upstream main is *not* silently substituted.
- The historical inventory is in `docs/UPSTREAM_AUDIT.md`; its status labels
  predate M4-G5F8V–X and must not be interpreted as a current capability list.

## Capability / dependency matrix

| Go source in `tsc/internal/` | Upstream role and dependency | Tsodin now | Next action / rank |
|---|---|---|---|
| `scanner/scanner.go` | Scanner and contextual rescans feed parser | `src/scanner`: bounded ASCII+rescan grammar | P2: expand with parser-backed witnesses |
| `parser/parser.go` | Source files and recovery feed binder | `src/parser`: expressions, declarations, bounded if/else | P1: support file/import/function syntax based on project needs |
| `binder/binder.go` | Symbols, scopes and control-flow graph | `src/binder`: single-file and bounded script-global project, no general scopes | P1: reusable scope and symbol identity, not checker special cases |
| `compiler/program.go`, `fileloader.go`, `filesparser.go` | Root files, project references, source inclusion and provenance | P0C explicit tsconfig loader and project binding, check -p still exit 2 | **P0D: JSONC, source paths, diagnostics** |
| `module/resolver.go` | Resolve source imports and packages | No module resolver | P1 after project/file classification |
| `checker/types.go`, `relater.go` | Canonical types, structural relations | `src/typecore`: restricted primitive/union TypeIds; `checker/primitive.odin` bounded relations | P1: reusable semantic relation engine |
| `checker/flow.go` | Flow-node reachability and join | `src/checker`: restricted Boolean, typeof, never arms | P2: full CFG only after scopes/project support |
| `checker/inference.go` | Generic inference based on signatures/relations | Unsupported | P3 after signatures and type params |
| `testrunner/test_case_parser.go`, `compiler_runner.go` | Directives, file units, options matrix and official diagnostics baselines | Custom TS7 witnesses plus first selective source adapter | **P0: conformance foundation** |
| `execute/tsc` | CLI project compilation and diagnostic/status contracts | `check -p` preflight only, exit 2 even on valid project | **P1A: bounded project checker** |

## Prioritized delivery and acceptance gates

1. **P0A: source-backed official-case adapter.** Verify exact pinned source
   bytes; understand `@filename`, `@target`, `@strict` and selected options.
   Preserve individual file contents and target variants. Unknown directives,
   multi-file project parity and unsupported grammar must never register PASS.
   This slice uses three original Microsoft cases solely for **oracle capture**:
   `everyTypeWithAnnotationAndInitializer.ts`,
   `typeGuardOfFormTypeOfNumber.ts`, and `strictModeOctalLiterals.ts`.
   All are `unsupported` for Tsodin. TS7 CLI capture **is not** a run of
   Microsoft's official test harness or its baseline verifier.
2. **P0B: project foundation.** Implement verified root-file/config ownership,
   snapshot identities, file modes and explicit unsupported flags; test
   cross-file conflicts and options fail-closed before enabling project checker.
   Initial bounded slice: reject empty root sets and use a deterministic,
   collision-tested File_Id preflight table for selected script files.
   This is *not* tsconfig loading or project type checking.
3. **P0C: merged.** Explicit `files` list and `noEmit: true`, path validation,
   source snapshots, parser and script-global binder. It always exits 2.\n4. **P0D: project contract.** JSONC, stable path identity and script/module
   provenance, and UTF-16 diagnostics. See [P0D → P1A plan](P0D_PROJECT_PLAN.md).\n5. **P1A: bounded operational `check -p`.** End-to-end semantic correctness
   on a declared subset, with non-zero status for unsupported imports,
   functions, generics, and unresolved symbols. Keep type diagnostics grounded.
6. **P1B: semantic foundations.** Expand scope/symbol and TypeId relations
   independently from the giant primitive checker; keep union aliasing,
   assignment, and flow guarantees tested.
7. **P2+: new syntax, modules, signatures, generics, true CFG, incrementality,
   and eventually emit after each dependent layer is sound.

## Official-test evidence ledger

- Catalogued original source: **not passed**.
- Selected and source-byte verified: **source verified**, not conformance.
- TypeScript 7 CLI executed: **oracle capture**, not Tsodin semantics.
- Microsoft harness baseline comparisons: **not implemented**.
- Tsodin native official-case result: **UNSUPPORTED** for all three selected
  sources, because language constructs and/or harness contracts exceed the
  current bounded compiler.
- Tsodin official conformance passes claimed: **zero**.

The first adapter deliberately does not parse or fabricate Microsoft's
`.errors.txt`, `.js`, or multi-configuration baselines. It rejects unsupported
options rather than generating false confidence. Future upgrades may promote
selected tests only after exact per-file diagnostic/category/span comparisons
and all upstream harness directives for that test are faithfully implemented.

## Performance

No competitive compiler benchmark before equivalent work. Any existing
checker-only or dump-only microprobe remains a diagnostic engineering tool,
not an eligible TS7-vs-Tsodin headline benchmark.
