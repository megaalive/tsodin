# P0D → P1A — upstream-first vertical project plan

Status updated 10 October 2026. P0A/P0B/P0C merged. This file is the actionable
next-step ledger, not a claim of semantic or conformance parity.

Microsoft references (read-only, pinned for investigation):
- `microsoft/TypeScript` Go tree at `aad4c72bf2d22e1fddb2a07d9e6f131e9b2ade44`,
  especially `tsc/internal/tsoptions/tsconfigparsing.go`,
  `tsconfigparsing_test.go`, `compiler/program.go`, `parser/parser.go`.
- `microsoft/typescript-go` at `89d5d5b2849a0db0957065889ca58536fa6d2e4a`
  for independent source structure inspection.
- **Executable** TS7 7.0.2 oracle remains at `1e4744d` and must not
  be replaced by source snapshots. No case may become PASS by cataloguing it.

## Ordered steps and closure gates

| Slice | Deliverable | Closure evidence | Status |
|---|---|---|---|
| P0D-1 | JSONC comments/trailing comma for existing explicit-files tsconfig; comments in quoted strings preserved; reject unterminated comment and unknown compiler options | Native lexer/config tests + disk fixture + pinned oracle regression CI | Implemented candidate; merge gate pending |
| P0D-2 | Stable logical file identity from normalized file paths; explicitly audit Windows case rules, aliases, symlinks, path traversal and root order; script vs external-module classification from proven syntax/package context | Canonical-path and alias collision tests, import/export and package mode negative tests; no unsupported module reaches script-global binder | NOT STARTED |
| P0D-3 | Deterministic syntax/binding/project diagnostic reporting and source ownership; file/UTF-16 spans and status taxonomy; distinguish `UNSUPPORTED` vs language diagnostics | Multiple files and line ending/Unicode witnesses vs pinned TS7 plus stable exit codes | NOT STARTED |
| P1A-1 | Single-file bounded `check -p` with real checker diagnostics only for a frozen supported grammar and options | TS7 independent positive/negative witnesses: identical code, byte→UTF16 start, correct file; reject unsupported constructs | BLOCKED by P0D |
| P1A-2 | Extend to bounded multi-file script globals; prove cross-file symbols and type relations without implicit module resolution | TS7 real project parity including conflicting declarations, missing globals, assignments; negative unsupported witnesses | NOT STARTED |
| P1B | Reusable scopes/symbol identities and structural type relation engine before growing general syntax | Native independent tests + upstream conformance selection | NOT STARTED |
| P2+ | Functions/objects/modules/generics/flow in semantic dependency order | Feature-specific pinned oracle cases; no PASS for unsupported fixtures | NOT STARTED |

## P0D-1 limitations

Only lexically strips `//` and `/* ... */` comments outside JSON
double-quoted strings, maintaining length and line endings. The existing Odin
JSON parser handles trailing commas; no general JSON/JSONC TypeScript parser
parity is claimed. Unknown properties/options, implicit include, extends,
glob, JS, JSX, .d.ts, module resolution, declaration checking, and emit still
fail closed. Symlink and case-alias semantics remain unresolved.

The public `check -p` command continues to return code 2 for valid preflight.
Do not publish compiler throughput based on this loader. End-to-end work
equivalence and a frozen real-project diagnostic corpus are mandatory first.

## Development protocol

1. Audit official Go implementation and nearest upstream tests before each
   slice, record exact revisions, directives, file boundaries and options.
2. Build minimal Odin-native ownership/types and independent fixtures; every
   previously supported input stays supported unless correctness demands a gate.
3. Run native CI, pinned TS7 oracle, TS6 supplemental witnesses where relevant,
   and post-merge CI. Never merge with missing mandatory checks.
4. Keep one focused PR per multi-file milestone, no new issue clutter.
