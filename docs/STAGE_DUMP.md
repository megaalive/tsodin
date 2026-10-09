# M4-G5F8A — Evidence-first stage dump

`tsodin dump --stage=all examples/typed-mismatch.ts` serializes **actual**
Odin stage reports as JSON (`tsodin.dump/1`). It does not run TypeScript,
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
  `node_types` and `relations` are `not_implemented`. This dump must
  not invent answers to questions the checker has not traced.
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

### Follow-on scope (not yet implemented)

Generate a versioned gallery from curated `examples/*.ts` using a pinned
CI/Pages pipeline without manual hand-written traces. Let the client
present hover-linked token/node/symbol facts, never perform its own fake
binding or checker inference. When detailed lookup paths and type relations
exist in the engine, extend a separate versioned schema with exact records
and positive/negative differential tests.
