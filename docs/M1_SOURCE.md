# M1-A — source versions and indexed positions

## Status

First M1 foundation slice: a version-owned source string and an ordered line-start
table, implemented in `src/source/version.odin`. This is a **source layer only**,
not a TypeScript scanner, syntax parser, binder or checker.

## Contract

- `File_Id` identifies a logical file; `generation` identifies an immutable
  snapshot of its contents. No global counters or pointer-identity assumptions.
- `source_version_create` validates the *entire* UTF-8 input before creating
  an owned string copy and line index. Malformed UTF-8 is rejected.
- `source_position` accepts a byte offset in `[0, byte_length]` and returns
  zero-based line number, UTF-16 column, and absolute UTF-16 offset.
- Positions inside multibyte UTF-8 scalars and outside the source fail closed.
- CRLF counts as one line break but **two** UTF-16 units; CR, LF, U+2028 and
  U+2029 are also line breaks. A trailing terminator creates an empty last line.
- Line lookup uses binary search over line start offsets. Conversion of the
  remainder of a line deliberately uses the checked UTF-8→UTF-16 reference.
  Complexity: building the index O(source bytes), position query O(log lines +
  current-line prefix). It is not yet a constant-time hot-path line-position API.
- The snapshot owns `owned_text` and its dynamic index. Call
  `source_version_destroy` once using the same allocator context as creation.
  Do not copy a `Source_Version` by value after creation; its allocated
  members are single-owner state. Do not query a destroyed version.

## Tests

Pinned CI's existing `odin test src/source` includes empty input, ASCII, LF,
CRLF, supplementary characters, UTF-8 half-scalar offsets, Unicode line
separators, final line, invalid encodings, independent generations, and
post-destroy rejection.

## Next

M1-B scanner needs a pull-token interface accepting a specific immutable
`Source_Version`, explicit `Need_Rescan` hooks for TS-contextual lexing,
and cases compared to the pinned TypeScript oracle. Do not claim syntax or
semantic parity based solely on these source-position tests.

Validation is run by the pinned Linux Odin CI on the exact PR revision.
