# P0C — explicit tsconfig root preflight

This milestone adds an **Odin-native, bounded project loader**, not a usable TypeScript project checker.

- `tsodin check -p path/to/tsconfig.json` reads the supplied file and resolves its explicit `files` relative to that configuration's directory. It **always exits 2**. Successful source/parser/binder preflight still reports `unsupported`; it never reports TypeScript correctness.
- Accepted form: JSON object (trailing commas allowed, comments not yet supported) with `files` (nonempty ordered array of distinct relative `.ts` paths) and `compilerOptions: {"noEmit": true}`. Only these two top-level keys and the one compiler option are recognized.
- Deliberate fail-closed boundaries: JSONC comments; `extends`, `include`, `exclude`, `references`, globs, external module resolution, .d.ts/.tsx/.js, absolute/parent paths, unknown options, implicit lib/emit semantics, source syntax outside the existing subset.
- Paths are normalized lexically, not canonicalized via symlinks. If a root is missing or UTF-8 invalid, loading stops without binding a partial project. Symlink/case alias semantics, path provenance and module classification need a subsequent explicit gate.
- Each loaded source and syntax result is owned by a stable allocation; the loader assigns `File_Id` by explicit root order and passes all roots to the existing deterministic project binder only after reading each. A binding conflict or unsupported syntax cannot be mistaken for complete preflight.
- Unit tests cover ordered roots, normalized duplicates, rejected unsupported config/options, cross-file references, a second-file duplicate, and a missing root. This is *not* official TypeScript conformance validation.

Reference behavior must continue to come from pinned Microsoft sources and the executable TS7 oracle. TS7 CLI `noEmit` is not used as evidence for TypeScript semantic parity here; enabling a `check -p` exit-0 path requires separate checked subset and oracle witnesses.
