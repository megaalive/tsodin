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
