# M2-A — restricted declaration parser

This first parser consumes the source-version-owned lexical context reader,
records compact source byte spans, and accepts a deliberately narrow program
grammar:

```
program      := declaration* EOF
declaration  := ("var" | "let" | "const") Identifier type? initializer? ";"
type         := ":" ("number" | "string" | "boolean")
initializer  := "=" (integer-literal | simple-string-literal)
```

`const` requires an initializer. Other declarations may omit it.
Declarations require semicolons, and the parser **consumes the entire source**;
export declarations, arithmetic expressions, inferred complex types, escapes,
template expressions and broader TS syntax are not silently accepted.

## Source/ownership model

- A `Program` stores File_Id + generation and a dense dynamic array of
  `Declaration` structs with byte spans. It copies no identifier or literal
  text. Name/initializer strings can be viewed from the matching immutable
  `Source_Version` only while that source snapshot is alive.
- The Program's declaration buffer must be released with `program_destroy`.
- Any parse failure deletes intermediate allocations and returns an EMPTY
  Program plus an explicit Parse_Error. There is no partial-success path.
- A `compat.Profile` is required for entry; unregistered future TS8 editions
  fail closed. No version arithmetic is embedded in this parser.
- This is a simple reference representation, not a proven optimum. Optimize
  memory shape only after diagnostic parity and a real-project profile.

## Evidence

- Odin unit tests check declaration counts, kinds, literal/type annotations,
  byte spans, Unicode line position interop, invalid inputs and version gates.
- The pinned TypeScript 7 CLI separately accepts
  `tests/oracle/parser-subset`. **It does not produce AST structure
  fingerprints or prove C0 syntax-diagnostic parity**. The new parser is
  not wired to the `tsodin check` CLI.
- No speedups vs Rust/TypeScript or the old experiments are claimed.

## Next

Extend expression parsing/recovery with oracle-backed expected diagnostics,
produce a stable syntax representation for the binder, and enter the
first narrow real source-to-diagnostics checker slice. Only after useful
equivalent work exists should end-to-end benchmarks become product evidence.
