# Upstream-first TypeScript engineering audit — 9 October 2026

**Audit status:** First source/harness inventory and conservative capability map.
Not a formal conformance run, a performance comparison, or a complete audit
of Microsoft's codebase.

## Exactly which Microsoft compiler did we inspect?

- Official native compiler: [`microsoft/TypeScript`](https://github.com/microsoft/TypeScript), Go tree at [`tsc/`](https://github.com/microsoft/TypeScript/tree/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc), **discovery snapshot** `6ad8c56f9b5a9bb910046c56059296311adc24ba`.
- The **separate, existing executable semantic oracle** remains TypeScript
  **7.0.2**, npm `typescript@7.0.2`, upstream `1e4744d68260a7cb91b62b12edc3f6a2187faaf1`,
  configured by [`tests/oracle/profiles.json`](../tests/oracle/profiles.json).
- Do **not** treat the discovery snapshot as the 7.0.2 oracle's exact source,
  and do not silently change the pinned version when reading more recent code.
- The historical compiler and its suite are public Microsoft-maintained
  reference material. We study semantics, tests and failure modes. Tsodin's
  internal model, allocation and data layouts remain Odin-native.

### Verified upstream component map

| Microsoft native Go source | Role | Tsodin location / gap |
|---|---|---|
| [`tsc/internal/scanner/scanner.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/scanner/scanner.go) | Tokens and contextual scanning | `src/scanner/`, bounded ASCII subset, Unicode names/escapes incomplete |
| [`tsc/internal/parser/parser.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/parser/parser.go) | Full syntax and recovery | `src/parser/`, selected declarations/expressions/if only |
| [`tsc/internal/binder/binder.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/binder/binder.go) | Symbols, lexical scopes and control-flow graph | `src/binder/`, one-file and selected script-global scope; functions/nested scopes incomplete |
| [`tsc/internal/module/resolver.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/module/resolver.go) | Project imports/module resolution | **Not implemented** in Tsodin; external modules explicitly rejected |
| [`tsc/internal/checker/checker.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/checker/checker.go) | Type checking | `src/checker/primitive.odin`, bounded `number/string/boolean` relations only |
| [`tsc/internal/checker/relater.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/checker/relater.go) | Structural type relations | No general `TypeId`/structural assignability engine yet |
| [`tsc/internal/checker/inference.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/checker/inference.go) | Generic type inference | No generic type inference yet |
| [`tsc/internal/checker/flow.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/checker/flow.go) | Control-flow narrowing and joins | Bounded `if`/Boolean guards, limited nesting and snapshots; no general CFG |
| [`tsc/internal/testrunner/test_case_parser.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/testrunner/test_case_parser.go) | Splits multi-file cases and interprets directives/options | Current `tests/oracle/` holds small self-authored differential fixtures, **not** a runner for upstream cases |
| [`tsc/internal/testrunner/compiler_runner.go`](https://github.com/microsoft/TypeScript/blob/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/internal/testrunner/compiler_runner.go) | Enumerates test files and verifies diagnostics/emitted baselines | Upstream compiler/conformance suites have **not** been executed against Tsodin |

The upstream compiler/conformance source suites reside under
[`tsc/testdata/tests/cases/compiler/`](https://github.com/microsoft/TypeScript/tree/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/testdata/tests/cases/compiler)
and
[`tsc/testdata/tests/cases/conformance/`](https://github.com/microsoft/TypeScript/tree/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/testdata/tests/cases/conformance).
The test harness interprets `// @target:`, `// @filename:`,
multi-file test units, `tsconfig`, per-test options, baseline diagnostics
and some emit checks. **Running TypeScript alone on flattened snippets
does not mean a compiler/conformance test has passed.**
Tests can have multiple configurations and distinct expected outputs.
Do not copy the entire Microsoft test suite into Tsodin.

### Two different corpus layouts — verified at both revisions

**Important pinning hazard:** The TS7.0.2 oracle commit
[`1e4744d68260a7cb91b62b12edc3f6a2187faaf1`](https://github.com/microsoft/TypeScript/tree/1e4744d68260a7cb91b62b12edc3f6a2187faaf1)
contains the selected original conformance files under
[`tests/cases/conformance/`](https://github.com/microsoft/TypeScript/tree/1e4744d68260a7cb91b62b12edc3f6a2187faaf1/tests/cases/conformance).
The later audited native Go snapshot places the corresponding files under
[`tsc/testdata/tests/cases/conformance/`](https://github.com/microsoft/TypeScript/tree/6ad8c56f9b5a9bb910046c56059296311adc24ba/tsc/testdata/tests/cases/conformance).

All eight selected test paths were independently located at **both**
revisions. The triage catalog stores the two concrete paths per case.
This is **file presence only**; neither source contents across versions
nor test expectations are assumed interchangeable. When deriving a
TS7.0.2 goldens fixture, read its **pinned oracle** path, not only
the newer Go snapshot's test file.

## Curated upstream tests to read before implementation

The machine-readable [triage catalog](../tests/oracle/upstream-triage.json)
pins eight **catalogued but not executed** original tests. It contains
source paths, a rough capability status and a specific next engineering
question. All entries are `indexed_only_not_executed`: neither Microsoft
harness success nor Tsodin parity is inferred.

| Priority | Official test path (relative to `tsc/testdata/tests/cases/conformance/`) | What to understand | Current gap |
|---|---|---|---|
| P0 | `expressions/binaryOperators/arithmeticOperator/arithmeticOperatorWithInvalidOperands.ts` | Numeric operands vs invalid coercions, `any` and enum cases | Only bounded numeric forms |
| P0 | `statements/VariableStatements/everyTypeWithAnnotationAndInitializer.ts` | Declared vs inferred type and literal widening | Simple annotations; no general typed declarations |
| P0 | `expressions/binaryOperators/comparisonOperator/comparisonOperatorWithNumericLiteral.ts` | Narrow/wide numeric overlap diagnostics | Selected comparisons only |
| P1 | `expressions/binaryOperators/logicalAndOperator/logicalAndOperatorWithEveryType.ts` | Truthiness, non-Boolean operands and union results | Boolean-only proof slice |
| P1 | `types/union/unionTypeReduction.ts` | Union canonicalization and reduction | No union `TypeId` |
| P1 | `expressions/typeGuards/typeGuardOfFormTypeOfNumber.ts` | `typeof`, positive/negative narrowing | Missing `typeof` and union narrowing |
| P1 | `controlFlow/controlFlowIfStatement.ts` | Flow assignments, joins and liveness | Bounded snapshots, no general CFG |
| P2 | `types/union/discriminatedUnionTypes1.ts` | Property discriminants across unions | Requires object and union type relations |

These are discovery references, not the full list of missing features.
Several original suites require functions, classes, generics or imports;
they are **not** valid drop-in Tsodin fixtures yet.

## Revised build strategy — source-first, not feature guessing

1. **Read upstream semantics and the test harness first.** For each candidate
   capability, select a pinned original test, record `@...` directives,
   compiler options, file boundaries, diagnostic category/code/span and
   applicable baselines. Identify any unsupported dependencies.
2. **Derive a *minimal independent* TS7.0.2 differential witness.** Commit
   both accepting and rejecting examples with unchanged oracle expectations.
   Use native TS7 code + UTF-16-start evidence and supplemental TS6 full spans
   only where equivalent; full TS7 span parity cannot be claimed by TS6.
3. **Implement Odin-native data structures.** Prefer source ranges,
   contiguous syntax nodes, stable dense symbols and canonical `TypeId`
   handles where warranted. Do not port Go `*ast.Node` graphs, `sync.Pool`
   or nested checker closures mechanically.
4. **Keep fail-closed status.** Incomplete scanner/parser/binder/module
   resolution means no `tsodin check` success, regardless of the green
   TS7 differential *subset*. Count `passed / failed / unsupported /
   out-of-scope / not run` separately.
5. **Merge one focused vertical slice at a time.** Require native tests,
   pinned semantic oracle, negative/failure tests and independent review.
   Do not manufacture microbenchmarks or add Benchmark to Pages.
6. **Measure performance only once equivalent work exists** on a pinned
   real project corpus. Lock single-thread and default-worker comparisons,
   build flags, host, correctness and sample-order rules before measuring.
   Do not confuse a fast syntax scanner with a faster TypeScript compiler.

## Next implementation priorities

**First:** close the P0 primitive domain/literal-widening contract using
real annotated declaration/comparison upstream test cases. Record an exact
minimal oracle witness *before* modifying the checker. Do not assume an
annotated `const` is a permanent literal or always proven-wide.

**Second:** introduce a small canonical `TypeId`/union reference model and
`typeof` guard vertical slice. Unit tests must demonstrate invalidation
across assignment and join, not merely successful parsing.

**Third:** expand binder scopes/functions and project/module resolution,
then expose an actual `check -p tsconfig.json` entry point with fail-closed
options. This project-level milestone is necessary before official
conformance suite adoption and performance comparisons.

**Fourth:** integrate a subset of official compiler/conformance cases using
their real directive/config semantics. Only then grow coverage counts and
performance baselines. Do not pre-label catalog entries as passing.

## Strict evidence boundary

Current Tsodin `src/cli/main.odin` still disables `check`; `src/binder/project.odin`
explicitly lacks modules/`tsconfig` resolution; the checker has no general
type relation engine. Previous custom TS7 oracle fixtures are useful and
remain enabled, but they are **not equivalent** to passing Microsoft's
upstream compiler/conformance suite.

This document is deliberately a small evidence-backed gap audit rather than
an unjustified rewrite architecture or a claim of being faster than Go/Rust.
