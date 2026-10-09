# Audit R2 — var redeclaration semantic repair

Authority: pinned TypeScript 7.0.2 at upstream commit
`1e4744d68260a7cb91b62b12edc3f6a2187faaf1`.

The original binder merged same-name `var` declarations, while the checker
evaluated declarations independently. R2 reproduced a **false checker success**
using a deliberately failing native test, with TS7 independently rejecting the
incompatible declaration.

The binder now stores first/subsequent declaration indices only for duplicate
`var` symbols. The checker requires matching semantic declared/inferred
primitive or canonical union types, emitting a source-backed internal issue
`Conflicting_Var_Redeclaration` (append-only ID 15). Its pinned TS7 candidate
mapping is TS2403, while TS2322 retains internal ID 10.

For valid redeclarations, a subsequent initializer transfers the current flow
and literal state to the canonical first symbol so later reads cannot see
stale flow facts. Normal files incur no var-redeclaration records.

Multi-file `bind_script_project` is *binding only*, not the project type
checker; cross-file TS2403 is not claimed. No full TS7 conformance or
performance claim follows from this bounded source-to-checker repair.
