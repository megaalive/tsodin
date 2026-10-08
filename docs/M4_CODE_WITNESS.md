## M4-B — first code-only TypeScript 7 differential witness

The pinned native TS7 CLI and `src/checktrace` now execute the same two
primitive-checker fixtures. `tools/oracle/compare-primitive-codes.mjs` maps
**only** the internal primitive assignment mismatch kind to TS2322 and
asserts the exact diagnostic-code occurrences: 0 for a valid project,
2 for the intentionally incompatible declarations.

This is a narrow, intentionally **code-only** differential witness.
It does NOT yet compare UTF-16 start/end positions, message text, categories,
nontrivial control flow, all TypeScript checker semantics, or Microsoft
compiler/conformance test corpus. Passing this job MUST NOT increment the
official suite counters shown in Pages. Any unrecognized internal issue or
other TypeScript diagnostic code fails the gate, rather than being filtered.

The CI job pins both the Odin toolchain and TypeScript 7.0.2. It emits a
machine-readable code witness in logs, with `spanParityChecked:false`
and `messageParityChecked:false`.
