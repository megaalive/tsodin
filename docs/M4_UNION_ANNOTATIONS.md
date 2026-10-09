# M4-G5F8W1 — primitive union annotations

This historical W1 slice was the first production integration of TypeId,
introduced in PR #79. W2 later added bounded `typeof` support, documented
separately in [M4_TYPEOF_FLOW.md](M4_TYPEOF_FLOW.md).

## Scope

- Scanner appends a single-| token, without changing previous token IDs. It
  remains unsupported in expressions. Logical || retains its original token.
- The expression parser accepts annotated combinations of number, string and
  boolean with |, including repeated or reordered primitive constituents.
  Syntax stores a small canonical combination enum, not a pool-local handle;
  the existing stage-dump schema and old gallery outputs stay unchanged.
- The checker creates a pool only for files containing union annotations and interns union annotations
  into sorted canonical identities; TypeId handles are not stored in syntax,
  binder, global state or any returned report.
- A separate dense TypeId lane accompanies the existing primitive/fact arrays.
  Direct references, grouped aliases, declarations, and assignments can carry
  canonical unions. The existing monomorphic hot path retains its equality
  check without invoking typecore relations.
- Unsupported union operators, truthiness, compound typeof guards, literal-union
  annotations, undefined/null/object constituents, forward references,
  structural relations, and implicit-any remain fail closed.

## Semantic boundary

W1 used the *declared* union rather than branch-local narrowed types.
W2 adds exact primitive `typeof` narrowing and mutation/branch joins, but
general TypeScript control flow remains unsupported. No conformance rate,
full diagnostic parity or performance win is claimed.

## Evidence

- Native end-to-end tests check parser -> binder -> checker acceptance,
  mismatched writes/declarations, duplicate annotations, and unsupported
  syntax. A full successful check requires zero diagnostics.
- Two independent pinned TS7.0.2 CLI oracle projects mirror the valid and
  erroneous supported syntax. Oracle capture is independent of Odin tests.
- Existing native primitive/flow suites, Bootstrap CI and oracle gates must
  remain green before merge; no public tsodin check or benchmark is enabled.

Follow-up implemented: M4-G5F8W2 (see linked flow documentation).
Future work: general CFG reachability and compound/typeguard operators.
