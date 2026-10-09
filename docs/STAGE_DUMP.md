# M4-G5F8A–C — Evidence-first stage dump

`tsodin dump --stage=all examples/typed-mismatch.ts` serializes **actual**
Odin stage reports as JSON (`tsodin.dump/2`). It does not run TypeScript,
claim full TS7 parity, or enable `tsodin check`. Unsupported syntax, names
and checker semantics are still explicitly marked in each stage.

## Contract

- `source.name` is the command's input path (no environment-dependent absolute
  path normalization), `source.text` is the exact validated UTF-8 source;
  `source.bytes` and `source.utf16` are computed by the Odin source module.
- `tokens.tokens` uses the scanner's **actual** `Token_Kind` names and
  half-open byte/UTF-16 spans. The scanner omits trivia and includes EOF.
  This is a partial lexical implementation, not all TypeScript tokens.
- `ast.nodes` is the real postorder `Expr_Node` table, with `left/right`
  arena IDs (`-1` = absent), operator, source spans and an inclusive
  *scanner-token range*. It is **not** a TypeScript `SourceFile` AST.
  `declarations` and `statements` are the original parser tables,
  so consumers can distinguish declaration syntax from expressions.
- `symbols.scopes` describes the **single-file scope only**. Names refer
  to original source text. `symbols.references` contains actual
  `node_index`/`symbol_index` mappings from the binder, zero-based.
  Nested lookup paths are `not_implemented`, never fabricated.
- `types.diagnostics` uses the **internal checker issue IDs**, clearly
  namespaced as `tsodin.checker.Check_Issue`. In particular issue ID 10 is
  **NOT** a serialized TypeScript diagnostic code. The externally pinned
  TS7.0.2 differential witness maps selected internal kinds independently.
  `node_types` remains `not_implemented`. Since M4-G5F8C,
  `types.relations` is a **partial** record of primitive assignments and
  explicitly annotated variable initializers. Every record originates from
  the exact boolean compatibility decision used by the checker, linking
  source/target primitive types to the actual RHS expression node and
  declaration index. No general assignability engine is claimed.
- Every stage has both `status` (current implementation coverage, normally
  `partial`) and `outcome` (`complete`, `diagnostics`, `unsupported`)
  for this exact input. A well-formed JSON response can contain a failed
  stage: JSON generation success **never means checking succeeded**.
- No timestamp, browser color, localized text, synthetic benchmark or
  generated AST/type facts. The source filename is intentionally the given
  argument; identical inputs and arguments produce byte-identical JSON.

The deliberately narrow initial schema can evolve with an explicitly
versioned change. Do not silently broaden the meaning of any existing
field. Parser failure and unsupported declarations must never be shown as
a successful check in the Pages UI.

## Correctness and security

CI runs the pinned Odin compiler on supported, erroneous, UTF-16/emoji,
and unresolved-name examples. A Node verifier independently recomputes
UTF-16 from source byte prefixes, checks arena references, exact internal
error IDs, omitted relation support and deterministic reruns.

Input reading is local only. Dump embeds the full source text; **never publish
source containing secrets, PII or proprietary code**. The Pages gallery
should consume a curated set of public examples only. Do not automatically
publish arbitrary CI inputs or offer server-side compilation of user text.

### M4-G5F8B — Pages gallery of actual generated traces

The Lab tab in the existing Pages Observatory fetches **only** static,
versioned traces under `docs/traces`. `tools/dump/build-gallery.mjs` finds
all curated `examples/*.ts` (no parallel hard-coded example registry),
runs the pinned Odin `tsodin dump --stage=all` executable and builds a
matching `index.json`. After changing an example or the dump semantics,
regenerate locally using:

```sh
odin build src/cli -out:tsodin
TSODIN_BIN=./tsodin node tools/dump/build-gallery.mjs --write
TSODIN_BIN=./tsodin node tools/dump/build-gallery.mjs --check
node tools/dump/check-gallery.mjs
```

CI **fails** unless the committed trace bytes match a fresh Odin run. Browser
validation independently recomputes byte and UTF-16 boundaries and rejects
any mismatch instead of showing a false verification badge. Selecting a
token, expression node or symbol highlights related source ranges; diagnostic
IDs remain explicitly internal. Read-only source is intentional because
GitHub Pages is static and cannot run the native Odin checker for edits.

The dumps omit a self-referential Git SHA: embedding the final commit hash in
files committed to the same hash cannot be deterministic. Publication
provenance is therefore the **Git commit containing source, generated JSON
and passing CI**, rather than a fabricated fixed commit field inside each
JSON file. No timestamps or reference-code parity badges are emitted.

### Beyond this milestone (not yet implemented)

Hierarchical scope lookup trails, per-expression type tables, a general
assignability graph and full TS7 diagnostic-code/message parity remain
out of scope. Extend the versioned schema only when Odin emits those
facts from its actual implementation; the Lab must not invent them.

### M4-G5F8C — bounded real type-relation evidence

The `tsodin.dump/2` schema extends dump/1 with
`stages.types.relations` and `trace_mode`. Relation objects contain
`source`, `target` (internal `Primitive` enum names), `relation_kind`
(`Variable` or `Assignment`), `node_index` (postorder RHS root),
`declaration_index` (original declaration table), `result` (exact
decision), and source-backed `bytes`/`utf16` spans. Failed checks are
recorded by default:

```sh
tsodin dump --stage=all examples/typed-mismatch.ts
```

To record all actual supported primitive decisions (including successes):

```sh
tsodin dump --stage=all --trace-relations examples/mixed-boolean.ts
```

The real Pages gallery deliberately uses `--trace-relations` to teach
both yes/no decisions. This flag affects only the **developer dump**;
normal `checker.check_file` does not allocate relation records.
Unsupported syntax/binding/semantics still fail closed. Relations do
not include all expression operators, control-flow narrowing, object
structural types, TS diagnostic codes, hierarchical lookup, or a general
type graph. The browser must not infer or manufacture missing relations.

Previously published `tsodin.dump/1` is superseded by the explicitly
versioned v2 data, and the checked-in examples must be regenerated from
the pinned Odin binary. The schema version is deliberately changed so
consumers can reject incompatible records instead of silently
misinterpreting them.

### M4-G5F8D — relation evidence integrity

This milestone keeps `tsodin.dump/2` unchanged. The browser rejects a
relation unless its RHS node is the root of a matching parser declaration or
assignment event, its declaration/assignment target agrees with the parser
and binder, and the records occur once in source expression order.
For annotated targets, the primitive target must match the original
annotation; inferred targets are **not** re-inferred in JavaScript.
Because v2 compares only supported primitive compatibility, the recorded
YES/NO must agree with the primitive-domain identity check already used by
Odin. These are **integrity checks of existing evidence**, not a second
browser-side type checker.

The verifier deliberately rejects corrupted source spans, forged node IDs,
shuffled decisions, wrong relation contexts, false YES/NO results, or wrong
binder targets. Odin regression coverage additionally checks relation
ordering across two nested if/else levels, mutations and joins with tracing
disabled, failures-only, and all mode. Comparison/disjointness diagnostics
remain separate internal issues, **not** additional assignability relations.
A future comparison-evidence stream requires a separately specified schema;
no comparison decisions are fabricated for v2.

### Pending M4-G5F8E publication

The Odin checker has a separately owned opt-in `comparisons` evidence
buffer for proved strict-equality operand overlap/disjointness. This internal
report is **not serialized** by `tsodin.dump/2`; the Lab intentionally shows
only v2 assignment relations. Publishing comparison records requires an
explicitly new schema, an Odin-generated deterministic gallery and independent
source-span validation. Do not synthesize comparison facts in JavaScript.
