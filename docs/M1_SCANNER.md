# M1-B — fail-closed ASCII pull scanner

This is an intentionally limited first scanner. It proves the iterator interface,
token spans, trivia handling, immutable source-version integration, and *explicit
unsupported syntax* rather than silently accepting TypeScript we cannot handle.

## Version-aware compatibility boundary

`src/compat/profile.odin` owns the registry for approved compiler
compatibility profiles. The scanner receives a concrete profile, and
`scanner_init_with_profile` rejects an unregistered version at the
next token request with `Unsupported_Profile` (sticky failure).
`scanner_init` is the convenience entry for the pinned TypeScript 7
profile only. A future TS8 adapter must explicitly register a new
scanner edition if its lexical semantics differ; unknown versions are
never inferred to be compatible.

The independently pinned TypeScript CLI oracle is configured via
`tests/oracle/profiles.json`; see `docs/COMPATIBILITY.md`.

## API / lifetime
- Package `src/scanner` imports `../source`.
- `scanner_init(^Source_Version)` borrows an initialized immutable version.
  Its owning version must outlive the scanner.
- `scanner_next` returns a `Token{kind, byte_start, byte_end, error}`.
  Tokens reference byte spans, never copied text. Call `source_position`
  when UTF-16 diagnostic positions are needed.
- After any error, the scanner is *sticky-failed*. It never returns a false
  successful EOF after encountering unsupported or malformed source.

## Supported subset
- ASCII identifiers and keywords `let`, `const`, `var`, `number`,
  `string`, `boolean`;
- decimal **integer-only** digit runs, quoted ASCII strings without escapes;
- punctuation for simple declarations and arithmetic;
- horizontal whitespace, LF, CR, CRLF, U+2028 and U+2029;
- line and block comments, including unterminated block-comment detection.

## Explicitly unsupported

Unicode identifiers, regular expression vs division rescans, template and JSX
lexing, string escapes, Unicode string contents, numeric exponent/hex/decimal
syntax, complete TS keywords/operators, and full lexical diagnostics.

Some supported token spellings are **not** sufficient evidence for TypeScript
syntax correctness. This scanner is not yet TS7 lexical parity or C0. Future
M1 work will compare specific lexical fixtures with a captured TS7 oracle and
add contextual re-scan entry points.

## Tests

Pinned CI runs `odin test src/source`, then `odin test src/scanner`.
The scanner suite covers byte spans, source UTF-16 interop, comments,
Unicode line separators, EOF, unsupported slash/identifier/escape cases,
unterminated strings/comments, and sticky failure. The end-to-end `check`
CLI remains intentionally disabled.
