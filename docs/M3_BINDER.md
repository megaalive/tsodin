# M3-A: Single-file binder

The binder consumes a complete syntax report from the same immutable
FileId and generation. Partial syntax recovery or mismatched snapshots
are fatal; they are never reported as successful binding.

The first supported scope is one file's top-level declarations.
Stable dense symbol indices identify distinct declaration names.
A two-pass binder collects declarations before resolving name-expression
nodes, including references to declarations later in the same file.

Within this limited scope, repeated `var` declarations merge into
one symbol. `let`/`const` name conflicts and unresolved identifiers
produce internal issues with source byte spans. These internal issue
kinds are not TypeScript diagnostic codes.

The temporary symbol table uses contiguous, open-addressed buckets,
source-owned name views and no individual symbol allocations. It is
released when binding ends. The binding report owns its arrays and
must be destroyed explicitly.

Unsupported: nested scopes, modules, imports/exports, globals,
namespace merges, function binding, temporal-dead-zone diagnostics,
type relations and checker output. The `tsodin check` CLI still
rejects requests until real checker compatibility is established.

Validation: `odin test src/binder` covers forward names, symbol IDs,
var merging, lexical duplicates, unresolved names, stale source
versions and refusal to bind incomplete syntax.

## M3-B — selected multi-file script-global binding

The `bind_script_project` entry point groups multiple explicitly selected
**script files** into one shared top-level scope. It is deliberately NOT a
tsconfig/module-resolution implementation. The caller provides a list of
individually complete parser reports and corresponding immutable source
versions, with unique File_Id values and matching generations.

The collector runs one declaration pass across all files before a second
reference-resolution pass. Symbol identities are dense indices in stable
file/declaration order, with a temporary open-addressed hash table. Symbols
retain a (file index, source span) identity; no name strings are copied.

Repeated `var` declarations may merge across script files; lexical
declaration collisions and unknown names are recorded with file-local spans.
Any incomplete source or version mismatch prevents binding entirely. This
does not implement imports, exports, ambient globals, modules, node resolution,
block scopes, or TypeScript's complete global declaration-merging rules.

Unit tests validate cross-file forward references and conflicts. Two
independent pinned TypeScript 7 CLI projects provide acceptance and diagnostic
existence evidence, NOT matching internal tsodin diagnostics.

## M3-C — explicit module boundary (fail-closed)

A project loader must classify each file as `Script` or
`External_Module` before invoking `bind_script_project`. The M3-B script
binder **refuses** explicitly marked external modules, rather than leaking
their declarations into the shared script-global symbol table. This is a
safety boundary, not an import/export implementation. An omitted mode in the
M3-B legacy API defaults to Script; future project-loading APIs must supply
and validate mode explicitly. No automatic module detection is claimed.

Until parsing and module graph resolution exist, external-module projects
are **unsupported**. Never treat their rejection as passing an upstream
TypeScript conformance case.
