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

## Auxiliary lexical witness (not C0)

The dedicated `src/scantrace` developer tool consumes file paths and
emits tab-separated token-kind ordinals with exact UTF-16 start/end
positions. Its lexical spans are compared to a pinned TypeScript 6
scanner API on known TS7-accepted fixtures; TypeScript 7's actual CLI
is verified separately. This tests a specific common lexical subset,
not full TypeScript 7 scanner parity.

## Tests

Pinned CI runs `odin test src/source`, then `odin test src/scanner`.
The scanner suite covers byte spans, source UTF-16 interop, comments,
Unicode line separators, EOF, unsupported slash/identifier/escape cases,
unterminated strings/comments, and sticky failure. The end-to-end `check`
CLI remains intentionally disabled.


## M1-D — explicit contextual scan entry points

The scanner now separates **raw tokenization** from parser decisions. The Odin
parser is not implemented yet; callers/tests exercise the following explicit
boundaries. A successful tokenization does **not** imply a valid TypeScript
expression or semantic checker result.

- `scanner_next` returns an ordinary `Slash` or `Slash_Equals` token
  without assuming division versus regex. The parser alone may call
  `scanner_rescan_slash_as_regex` on the most recently returned `Slash`
  token. A restricted ASCII regex body supports escaping, bracket classes,
  and a small set of flags; malformed or unsupported spellings fail closed.
  Regex parsing, regular-expression validity, and Unicode escapes remain out
  of scope.
- For template literals, the initial backtick scans a
  `No_Substitution_Template` or `Template_Head`; the parser reinterprets
  an immediately preceding `Close_Brace` using
  `scanner_rescan_close_brace_as_template`, yielding
  `Template_Middle` or `Template_Tail`. Nested expression brace depth
  belongs to the future parser, not to speculative scanner state.
- An ordinary `Less_Than` may be classified by the parser as a
  `Jsx_Tag_Start`, then a just-read `Greater_Than` can activate
  `scanner_begin_jsx_text`. Only `scanner_next_jsx_text` reads raw text
  containing whitespace, line separators and multibyte UTF-8; it exits on
  `<` or `{`. These hooks do not implement TSX grammar, JSX entities,
  attributes or nested-element recovery.

Each rescan verifies that its argument is exactly the last contextual token
and that the source/version profile is valid. Wrong-mode or stale requests
fail closed and remain sticky errors, rather than rewinding to earlier offsets
or accidentally interpreting syntax.

The existing TS6 lexical witness uses a **fixed subset** and unchanged Odin
token ordinals. New kinds are appended to preserve evidence comparability.
M1-D unit tests cover the implemented contexts, but full TS7/TS8 grammar and
scanner parity are **not** claimed.

Next: TypeScript-oracle-backed contextual fixtures with specifically
documented behavior and parser-owned nested mode tracking; no entire
compiler work should be inferred from lexical tests.

## M1-E — nested template context and external evidence

`src/context/reader.odin` adds a fixed-capacity (32-level), allocation-free
lexical context reader used by a future parser. It tracks **only**
template-interpolation curly brace depth and nested template frames;
it does not parse TypeScript expressions. A matching interpolation
closing brace is explicitly rescanned into TemplateMiddle/TemplateTail,
while ordinary nested object braces remain plain punctuation.
An unmatched template at EOF is an error, not a successful token stream.
The reader exposes an explicit `reader_rescan_regex` request;
it never infers whether a slash is a division operator or a regexp.

`src/contexttrace` drives two **fixture-scoped** token streams and
writes Odin token kinds and byte-to-UTF-16 spans.
`tools/oracle/compare-context.mjs` compares those streams with the
independently pinned TypeScript 6 JavaScript scanner and its documented
rescan functions. The pinned TypeScript 7 *CLI* independently accepts
a basic regex+template project (`contextual-basic`).

These are three **different** forms of evidence:
1. Odin's own nested-context unit tests;
2. TS6 supplementary lexical token/span equivalence on exactly two fixtures;
3. TS7 native CLI project acceptance.

There is still no TS7-native token parity, no JSX grammar/parser, and no
diagnostic parity. Context drivers are not a complete statement parser.

Future performance must be evaluated on true source-to-diagnostics project
workloads after compatibility gates. Token benchmark wins do not imply that
whole-program checking beats any previous prototype or competing checker.

## TS7 numeric lexical follow-up — leading-zero forms

The pinned TypeScript 7.0.2 CLI capture now runs three independent
`strict`, `noEmit` projects for `01`, `00`, and `08`, each expecting
a nonzero TypeScript diagnostic exit. Keeping separate projects means
one spelling cannot be masked by diagnostics from another. The
fixture registry verifies the exact source lexemes in the profile test.

Tsodin's scanner already rejects these legacy spellings with a sticky
internal `Unsupported_Syntax` (PR #58). The independent native TS7
CLI projects test the error boundary, **not** token-kind or exact
TypeScript diagnostic-code parity. No semantic checker expansion,
runtime allocation or unsupported numeric grammar is added.

