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

## M4-C — exact code + UTF-16 start-position witness

The same pinned CLI 7.0.2 and the Odin `checktrace` now compare **both**
TS2322 diagnostic codes **and one-based UTF-16 line/column starts** on the
declared three-file fixture set: successful types, two primitive mismatches,
and a CRLF file with non-BMP Unicode trivia. The checker projects source byte
spans using `source_position`; comparisons fail on any unexpected count,
code or start coordinate.

This is still **not full TS7 diagnostic parity**. The native CLI in
`--pretty false` mode does not provide authoritative end spans, diagnostic
categories or complete structured messages. Those dimensions remain
explicitly unverified in the machine-readable test log, and no official
Microsoft conformance score is published. No previous benchmark is imported.
