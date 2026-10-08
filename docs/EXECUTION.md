# tsodin execution plan — bootstrap and vertical checker slice

Status: M0 CLOSED / M1 ACTIVE (scanner oracle gate open) / M2-A–C SYNTAX SUBSET / M3-A–C BINDING/BOUNDARY + M4-A/B PRIMITIVE CHECKER/CODE WITNESS; full modules/checker not yet implemented  
Baseline: tsodin main 775bb0c5c53f4d6ed9544942cb7e28a56eeed3a2  
Architecture: Odin-native; historical language-selection benchmarks are not tsodin product measurements.

## Mission and product boundary

Build a maintainable, Odin-native TypeScript checker whose primary product mode eventually corresponds to `tsc --noEmit -p tsconfig.json`. JavaScript emit, declaration emit, LSP, and watch are not initial victory requirements. The command must fail closed on unsupported semantics; it must never silently claim a successful check while skipping required work.

The long-term G2 ambition inherited from the original plan is end-to-end full-project checking at C1 diagnostic parity, including a geometric-mean speedup of at least 1.5x vs TypeScript 7 T1 and TD, at least 1.3x normalized all-core, a strong memory result (target at most 65% TS7 TD peak RSS), and an honest comparison to the best eligible Rust checker. The original 2.0x Rust goal is aspirational, not a premise or a microbenchmark inference. Thresholds and bootstrap confidence intervals must be frozen before formal runs. No win exists until a locked real-project corpus passes every applicable gate.

## Engineering principles

- Semantic reference and diagnostic compatibility, not upstream implementation structure.
- UTF-8 source storage, byte-oriented internal spans, TypeScript-compatible UTF-16 external positions.
- A compact, explicit lifetime/ID model as a hypothesis, subject to cardinality and profiling.
- A narrow source-to-diagnostics vertical slice as early as possible, not parser-only vanity wins.
- Strict oracle/differential tests, reproducible corpus, measured peak RSS and wall time.
- T1 (single-thread), TD (each tool default), TN (same full machine) and separate incremental/cache lanes.
- Controlled, paired benchmark protocol; no repeated favorable-sample hunting.

## What must be redesigned for Odin

Use Odin allocators, typed IDs, scopes, slices, multi-pointers, context and procedures because they fit the compiler's semantics and lifetimes. Do not pre-commit to 16-byte tokens, 16-byte AST nodes, a particular hash table, an arena everywhere, shared checker state, or assembly. Each remains a candidate with explicit retirement criteria.

Do not transfer microbenchmark-specific optimization decisions. Every tsodin hot-path change needs a proven invariant, a diagnostic-equivalence gate, and measurement on an actual TypeScript workload.

## Milestones and release gates

| Milestone | Deliverable | Exit gate |
|---|---|---|
| M0 — foundation (closed) | Pinned Odin, honest CLI, source byte/UTF-16 reference function, unit tests, benchmark/oracle contracts, lightweight CI | CI builds and tests at exact toolchain; unsupported `check` returns nonzero; no compatibility claim |
| M1 — source and scanner (active) | Source identity and version lifetime; line index; checked Unicode mapping; pull scanner with contextual rescan design; token fixtures | Locked scanner cases match the syntax oracle for the declared subset; malformed input is categorized; UTF-16 positions verified |
| M2 — syntax (M2-A–C subset, recovery and diagnostic trace implemented; full gate open) | Narrow expressions/statements/declarations/type grammar, parser recovery, compact node store | C0 subset passes structural/syntax diagnostics fixtures; parser-only perf may be diagnostic, not product claim |
| M3 — symbols/modules (M3-A–C script-global binder and module guard; module-resolution gate open) | Binder, scopes, FileId/ModuleId, imports/exports, simple module resolution | Deterministic bound program; small multi-file fixture matches reference outcomes |
| M4 — first vertical checker (M4-A/B primitive checker and code-only TS2322 witness; parity gate open) | Primitives, variables, function signatures, simple assignability, compact diagnostic records | One real small project runs end-to-end with explicit supported scope; diagnostic parity or every gap reported; benchmark only equivalent work |
| M5 — conformance expansion | Generic relations/inference, control flow, module edge cases, declaration files, failure clustering | C1 grows against pinned upstream corpus; no unexplained differences on any claimed project |
| M6 — performance and parallelism | Real-profile optimizations and T1 first, then TD/TN; bounded shared-state experiments | Stable end-to-end results with compatibility fingerprints, RSS, raw samples, and no regression |
| M7 — incrementality | File-version invalidation, signature fingerprinting, warm edit metrics | Correct edit results; independent cold/warm/incremental classifications |

Milestones are gates, not a promise that a compiler can be completed in a fixed number of days. A 21-day vertical-slice checkpoint is an aggressive review target, not a reason to weaken semantics.

Compatibility profile architecture: [versioned and fail-closed](COMPATIBILITY.md). M1-A source lifetime and line indexing: [implemented](M1_SOURCE.md). M1-B–E bounded scanning, contextual tokens and supplemental lexical witnesses: [implemented](M1_SCANNER.md). M2-A narrow declaration parser: [implemented](M2_PARSER.md). M2-B/C expression parsing, recovery and a developer-only UTF-16 syntax diagnostic tracer: [implemented](M2_EXPRESSION.md). M3-A–C single-file and script-global name binding, with explicit unsupported module boundary: [implemented](M3_BINDER.md). M4-A source-to-primitive semantic diagnostics: [implemented](M4_CHECKER.md). M4-B exact pinned TS7 code-only witness: [implemented](M4_CODE_WITNESS.md). The official upstream TypeScript suite adoption strategy is [documented](OFFICIAL_CONFORMANCE.md). These are **not** TS7 C0/C1 claims; scanner parity, syntax diagnostics, binder and checker exit gates remain open.

## Immediate sequence

1. Finish M0 Linux CI and lock the exact Odin artifact; establish Windows CI only when its artifact identity is independently verified.
2. Add a tiny committed oracle corpus covering clean syntax, diagnostics, line endings, non-BMP characters, and unsupported syntax; pin TS7 CLI 7.0.2 outputs.
3. Implement a single source-version-owned line index and scanner subset. Keep an inspectable reference implementation while evaluating compact/hot-path versions.
4. Reach the first lexer/parser/binder/checker vertical path without attempting full TS compatibility in the parser first.
5. Introduce large-project canaries and checker work counters early; if the design is bottlenecked, revise a measured representation rather than tuning synthetic kernels.

## Execution discipline

Conductor owns the architecture and gates. Parallel lanes can prepare the oracle, source/scanner, module resolution, semantic slice, benchmark harness, and docs, but no lane may silently change shared ID/lifetime contracts.

Use direct main edits for small safe documentation fixes; branch/PR for multi-file implementations and experiments. CI should take minutes, not deployment-workflow lengths. Natural English commits. No unexplained fast-but-opaque code.

## Stop/review triggers

- Oracle mismatch hidden by filtering/unsupported-syntax success: STOP and correct semantics.
- Performance claim without C-level, locked corpus, exact revisions and all samples: REJECT.
- New hot-path hack without WHY/INVARIANT/EVIDENCE/FAILURE MODE: REJECT.
- Major representation work with no vertical-project benefit: REVIEW before scaling the change.
- Unbuildable pinned toolchain or failing tests: M0 remains OPEN.
