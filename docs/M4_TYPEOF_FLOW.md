# M4-G5F8W2 — bounded typeof union flow

Source contract: Microsoft TypeScript 7.0.2 pinned upstream test
`tests/cases/conformance/expressions/typeGuards/typeGuardOfFormTypeOfNumber.ts`
(commit `1e4744d68260a7cb91b62b12edc3f6a2187faaf1`).
The official test contains classes, uninitialized globals, and block declarations
outside this subset and is **not run as a Tsodin official conformance case**.

## Supported subset

- Append-only `Typeof_Keyword` scanning, unary `typeof` AST node,
  postorder evaluation to a string primitive.
- Simple `if (typeof x === "number" | "string" | "boolean")` with
  `!==` and unary `!` over a proven union-valued initialized let.
- Exact both-arm filtering through `typecore.split_typeof`, with
  per-branch TypeId state, reassignment invalidation and canonical joins.
- Monomorphic code retains its original zero-TypeId-allocation path.
  Extra dense state and lazy branch snapshots are scoped to union files.
- Existing if/else Boolean flow guards and all oracle/CI paths must
  preserve their previous diagnostics and postorder span semantics.

## Fail closed

This is NOT general TypeScript control-flow analysis. A split producing an
unreachable/never arm now supports only direct literal assignments to an
independent initialized let. These are typechecked (including errors) but
never transferred into the post-join flow state. Reads of names, nested
conditions and writes to the guard in a dead arm still fail closed.
Compound typeof guards, typeof on objects/null/any/unknown, destructuring,
uninitialized variables, nested scopes/functions, and assignment expressions
in conditions remain unsupported. All source spans and diagnostics are
internal; no public TypeScript conformance or checker benchmark is claimed.

## Verification

- `odin test src/checker`: true/false arms, inverted guards, reassignment,
  branch joins, negative mismatches and unsupported shapes.
- TS7.0.2 CLI capture plus direct code and UTF-16 start comparisons:
  `checker-typeof-flow-{valid,errors}` and
  `checker-typeof-never-{valid,errors}`; TS6 full-span checks are auxiliary.
- Upstream source inspected at pinned Microsoft TypeScript
  `1e4744d68260a7cb91b62b12edc3f6a2187faaf1`; the upstream fixture
  has class/uninitialized cases outside this subset, so our separately
  authored CLI witnesses remain independent of an official-suite claim.
- Bootstrap CI, native trace/Pages smoke and pinned TS7 oracle workflow
  are mandatory merge gates. No public benchmark or conformance score.
