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

## Developer-only source-to-syntax-diagnostics trace (M2-C)

A separate `src/syntaxtrace` executable reads an actual TypeScript source
file and emits one `DIAG` record for each **internal** parser issue, with
zero-based line and UTF-16 column start/end coordinates, followed by a
`SUMMARY` containing recovered declaration count, diagnostic count, and
process status.

- Exit **0**: source fully accepted by the intentionally small grammar.
- Exit **1**: recoverable syntax errors, with a non-empty diagnostics list.
- Exit **2**: malformed UTF-8, unsupported lexical forms, I/O failure, or
  another fatal condition.
- The developer tool is not the public `tsodin check` command, does not
  perform symbol binding or type checking, and does not use actual TS7 error
  codes. Its issue ordinals are explicitly internal implementation details.

`tools/oracle/check-syntaxtrace.mjs` asserts the textual trace on the
successful and erroneous pinned fixtures, an emoji+CRLF source and a fatal
unsupported-token source. The reference TS7 CLI still runs independently
and does **not** yet compare normalized diagnostics with this developer tool.

## M4-G5A — source-ordered statement event extension

The developer expression parser now records `Syntax_Report.statements`
containing source-order declaration or restricted assignment events.
Exactly `identifier = expression;` is recognized in statement position.
An assignment target is a source-spanned Name node, not a declaration.
Nodes remain postorder per expression; failures recover without committing
a partial event or retaining its nodes. The older `parse_declarations` API
remains unchanged, and no TypeScript syntax-parity claim is made.
