# M2-B — expression precedence and syntax recovery

## Narrow, intentional scope

The new `parse_expression_program` API extends M2-A without modifying the
legacy `parse_declarations` behavior. It handles `const`, `let`, and
`var` with optional `number`/`string`/`boolean` annotations, required
semicolons, integer and plain ASCII string literals, names, parentheses,
unary `+`/`-`, and left-associative binary `+`, `-`, `*`, `/`.

This is a **syntax** parser. It does not resolve names, infer types, validate
assignability, implement JavaScript evaluation, or emit TypeScript's diagnostic
codes. No TS7 syntax parity or checker feature is implied by this subset.

## Representation

- `Syntax_Report.nodes` is a contiguous dynamic array of small
  `Expr_Node` records; child edges are integer indices and a missing edge is
  `-1`. No heap allocation per AST node.
- Identifier, literal, and declaration spans refer to the exact owned
  `Source_Version`. Their byte positions are projected to
  TypeScript-compatible UTF-16 positions through `source_position`.
- A file ID and generation travel with the syntax report.
- `syntax_report_destroy` releases owned buffers. The source version must
  remain valid while interpreting its spans.
- Pratt/precedence-climbing parsing bounds recursion to 64 levels. Rejecting
  deeper expressions is an explicit temporary safety restriction.

## Error contract

`Syntax_Report.complete` is true **only** if the entire supported input
was consumed with zero diagnostics and no fatal lexer/profile failure.

- Recoverable errors (missing name/initializer, unexpected expression token,
  missing `)` or `;`) yield typed `Syntax_Diagnostic` records with exact
  byte spans; these are **internal categories**, not TypeScript error codes.
- Recovery advances to the next `;` or declaration start, without
  promoting the overall result to success. Nodes belonging to a failed
  declaration are rolled back; valid later declarations remain inspectable.
- Unsupported lexical input and unknown compatibility profiles are fatal.
  They cannot be reclassified as successful parsing.
- A malformed expression cannot produce a partly accepted declaration.
  `tsodin check` remains intentionally disabled.

## Independent oracle evidence

`tests/oracle/expression-subset` is a success fixture: TypeScript 7.0.2
must accept its complete project. `expression-syntax-errors` is a deliberately
failing project: the pinned TypeScript CLI must emit diagnostics. These oracle
captures are **not** structural AST parity, nor do they establish a diagnostic
code/span match with tsodin; follow-up work must normalize specific records.

`odin test src/parser` validates precedence, associativity, Unicode source
positions, deterministic internal issue kinds and spans, recovery, unknown
future-version rejection, and bounded recursion.

## Performance discipline

Contiguous storage and source spans are design hypotheses, not measured
wins. We do not reuse legacy microbenchmark scores: performance comparisons
are allowed only after real source-to-diagnostics work and a locked
correctness-equivalent corpus, with paired time/RSS/counters.
