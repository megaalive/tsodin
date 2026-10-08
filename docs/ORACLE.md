# Oracle and compatibility contract

## Baseline identities

The source of truth for preliminary pins is bench/manifests/baselines.json. These are **bootstrap candidates**, not an eligibility declaration for a published end-to-end comparison.

TypeScript 7.0.2 CLI is the primary semantic oracle. Run its resolved executable directly after preparing all dependencies. In a separate lane, TypeScript 6 or another reference API may help inspect AST structure; it must not silently redefine expected TypeScript 7 diagnostics.

## Version profiles and future TypeScript editions

Do **not** scatter `major == 7` checks throughout scanner, parser, binder, or checker.
The runtime compatibility selection lives in `src/compat/profile.odin`;
lexical behavior is selected through a version-bound scanner edition.
A version which is not registered must fail closed. Never reinterpret
unknown TS8 syntax as TS7 or manufacture successful diagnostics.

The external CLI oracle registry is `tests/oracle/profiles.json`.
Each entry pins an exact package version, upstream commit, executable,
manifest, and project arguments. `tools/oracle/capture.mjs` is
version-neutral: profile metadata selects the CLI and invocation.
The CI matrix currently enables **ts7** only. An eventual TS8 release
requires a new, independently verified profile, manifest, workflow matrix
entry, and separate goldens. Preserve TS7 regression fixtures in parallel;
do not replace or rewrite them with TS8 expectations.

TypeScript 7 exposes a native CLI rather than the historical JavaScript
compiler API; this primary semantic oracle uses the official CLI.
A future AST/scanner API adapter, if needed, is supplemental evidence,
not an authority for TS7/TS8 diagnostic truth.

The first `scanner-ascii` project tests that the pinned TypeScript CLI accepts
a lexical shape which the Odin subset also tokenizes in unit tests.
It **does not** establish identical token streams, syntax diagnostic parity
or full M1-C conformance. A future fixture lane must compare canonical token
kinds and byte→UTF-16 spans before claiming scanner parity.

## Levels

C0: for the explicitly declared grammar slice, syntax structure/parse behavior and syntax-diagnostic code + UTF-16 span agree with the frozen oracle.
C1: same diagnostic tuples (code, file, UTF-16 start, UTF-16 length) for each fully supported claimed project.
C2+: only later message/emit tiers; not an initial performance goal.

Do not treat empty diagnostics from a compiler that skipped files or unresolved syntax as equivalence. Unsupported options, project structures, or semantics must cause explicit failure, not a green result.

## First oracle corpus, to be pinned before M1 gate

- ASCII declarations and operators.
- CRLF and LF, with line and column boundaries.
- Supplementary Unicode characters before diagnostics.
- Malformed escapes and invalid input: classify explicitly; do not silently normalize.
- Context-sensitive slash/template/JSX cases for future rescans.
- Tiny multi-file import/export after binder work exists.

Each fixture requires a source hash, exact TS7 version, complete invocation/options, diagnostics fingerprint, and independently inspectable expected output. Do not invent goldens before running the oracle.

## Benchmark scope

T1: exact single-thread TS7 and tsodin modes.
TD: each tool's documented default worker behavior.
TN: honest fully normalized core policy on the same physical host.
PC and incremental: separate, never mixed into cold comparisons.

Include standard libs and dependencies on both sides, identical inputs/options, no persistent cache in headline cold runs. Stable paired wall is primary; RSS and useful counters supplement, but never supersede semantic equivalence.

Github-hosted shared runners are CI correctness/build machines, not authoritative performance hosts.
