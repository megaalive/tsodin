# M4-G5F8W1 — primitive union annotations

This is the first production vertical slice using the canonical TypeId kernel
introduced in PR #79. It is not general TypeScript union or typeof support.

## Scope

- Scanner appends a single-| token, without changing previous token IDs. It
  remains unsupported in expressions. Logical || retains its original token.
- The expression parser accepts annotated combinations of number, string and
  boolean with |, including repeated or reordered primitive constituents.
  Syntax stores an exact three-bit mask, not a pool-local handle.
- The checker owns one TypeId pool per invocation and interns union annotations
  into sorted canonical identities; TypeId handles are not stored in syntax,
  binder, global state or any returned report.
- A separate dense TypeId lane accompanies the existing primitive/fact arrays.
  Direct references, grouped aliases, declarations, and assignments can carry
  canonical unions. The existing monomorphic hot path retains its equality
  check without invoking typecore relations.
- Unsupported union operators, truthiness, typeof guards, literal-union
  annotations, undefined/null/object constituents, forward references,
  structural relations, and implicit-any remain fail closed.

## Semantic boundary

TypeScript performs control-flow-dependent narrowing of initialized union
variables. This slice preserves the *declared* union and does not claim to
derive the flow-narrowed type of a union reference. Some otherwise-valid
TypeScript sources may therefore still be unsupported/rejected. No TS7
conformance rate, diagnostic parity, or performance claim follows from it.

## Evidence

- Native end-to-end tests check parser -> binder -> checker acceptance,
  mismatched writes/declarations, duplicate annotations, and unsupported
  syntax. A full successful check requires zero diagnostics.
- Two independent pinned TS7.0.2 CLI oracle projects mirror the valid and
  erroneous supported syntax. Oracle capture is independent of Odin tests.
- Existing native primitive/flow suites, Bootstrap CI and oracle gates must
  remain green before merge; no public tsodin check or benchmark is enabled.

Next: M4-G5F8W2, isolated typeof unary expression and exact branch split,
followed by assignment invalidation and join semantics.
