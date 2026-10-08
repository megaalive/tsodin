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

## M4-D — supplementary full-span diagnostic evidence

The TypeScript 7.0.2 CLI remains our authoritative reference for diagnostic
codes and **starting UTF-16 coordinates**. Its plain-text CLI output does not
directly expose authoritative end positions or structured diagnostic categories.

To validate full diagnostic ranges without pretending TS7 provides a JS
compiler API, the CI now installs the separately pinned
`@typescript/typescript6@6.0.2` **supplemental** API and runs
`tools/oracle/compare-primitive-structured.mjs`. Against the same three
primitive fixtures, it asserts all emitted codes, error categories,
start/end line and UTF-16 column positions match Odin's `checktrace`.
Any unexpected extra TS6 diagnostic, missing source span, or unmapped Odin
issue fails the job.

**Evidence must remain version-scoped**: TS6 structured end-span agreement
is *not* proof of native TS7 end-span parity. Messages are not compared.
No score is added to official Microsoft conformance; the Pages panel remains
NOT RUN. Future work must expose or reproduce TS7's exact structured
diagnostic semantics before full TS7 parity can be claimed.

## M4-E — additional boolean fixture coverage

The existing pinned native TS7 code+UTF-16-start differential and separate
TS6 structured-span auxiliary checks now also include
`checker-boolean-valid` (0 issues) and `checker-boolean-errors`
(2 primitive TS2322 mismatches). The same strict count, code, and source
span assertions apply: no unsupported or skipped test is counted as a
success. This expands fixture coverage, **not** official conformance.

## M4-G5A — straight-line assignment differential witnesses

Two additional pinned projects, `checker-flow-assign-valid` and
`checker-flow-assign-errors`, exercise sequential `let` assignments.
TS7 CLI diagnostic **code and UTF-16 start** must exactly match the Odin
trace. The independent supplemental TS6 lane checks complete diagnostic
spans. `TS2322` on a simple assignment is anchored to its RHS expression;
`TS2367` on an impossible comparison covers that comparison expression.
No official conformance score or unconditional flow-parity claim follows.
