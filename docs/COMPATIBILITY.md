# Forward-compatible TypeScript language policy

## The architectural promise

tsodin should be able to **add TypeScript 8 without a cross-compiler refactor**.
This does not mean that a major language or type-system change can be handled
without implementing its semantics.

Maintain *stable internal representations* for source versions, byte spans,
token identities and diagnostic records. Put upstream dialect/version policy at
the boundary, never encode upstream major numbers in the main hot path.

## Current implementation

- `src/compat/profile.odin` is the Odin profile registry, currently limited
  to the independently pinned TypeScript 7.0.2 baseline. Unsupported versions,
  including hypothetical TS8, **fail closed**.
- `src/scanner/scanner.odin` takes a `compat.Profile` by value. Only the
  registered scanner edition is allowed to produce tokens. No hidden
  `>= 7` fallback exists.
- `tests/oracle/profiles.json` is the separate, data-driven CLI oracle
  registry (package, version, upstream commit, executable, invocation).
- `tools/oracle/capture.mjs` reads the chosen profile. Captures are
  version-scoped, and the TS7 corpus stays independent of later versions.
- No checker, parser, full grammar, TS7 token parity, or TS8 support is claimed.

## Upgrade contract: TS7 → TS8

1. **Discover:** pin the actual published TS8 compiler, version and upstream
   revision. Never assume its CLI or library API has the same shape.
2. **Classify:** build a change ledger covering scanner syntax, parser grammar,
   module resolution, checker semantics, diagnostics and compiler options.
3. **Add:** register a separate TS8 compatibility profile with explicit
   policy/feature changes; do not overwrite the TS7 profile.
4. **Prove:** run both TS7 and TS8 oracle matrices. Freeze distinct diagnostics
   for supported projects; compare emitted diagnostic codes and UTF-16 spans.
5. **Promote:** only enable a TS8 `--compat` selector when all declared
   supported grammar/semantic slices pass. Otherwise fail closed with
   a clear unsupported-edition error.
6. **Measure:** benchmark TS8-compatible real-project work only after parity,
   separate from TS7 performance records.

A patch/minor revision also needs independent review, but may reuse an edition
policy once differential tests establish no relevant behavior change.
Avoid premature version flags for hypothetical TS8 features; introduce them
only when measured deltas demand an actual policy difference.

## Explicit non-goals

- Automatically following the newest `typescript` package;
- using `TypeScript.createScanner` as the authoritative native TS7 oracle;
- scattering `if tsMajor >= 8` across tokenizing or type relations;
- treating TS7 CLI acceptance as exact token parity;
- relaxing TypeScript semantics to preserve a benchmark score.
