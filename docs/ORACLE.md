# Oracle and compatibility contract

## Baseline identities

The source of truth for preliminary pins is bench/manifests/baselines.json. These are **bootstrap candidates**, not an eligibility declaration for a published end-to-end comparison.

TypeScript 7.0.2 CLI is the primary semantic oracle. Run its resolved executable directly after preparing all dependencies. In a separate lane, TypeScript 6 or another reference API may help inspect AST structure; it must not silently redefine expected TypeScript 7 diagnostics.

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
