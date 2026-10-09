# M4-G5F8X — impossible typeof arms

Authority: pinned TS7.0.2 CLI and official Microsoft source test
`tests/cases/conformance/expressions/typeGuards/typeGuardOfFormTypeOfNumber.ts`
at `1e4744d68260a7cb91b62b12edc3f6a2187faaf1`.
The official file is inspected for the typeof narrowing contract only, not
claimed as a successfully executed Tsodin conformance test.

The predecessor W2 guard handled only splits with *two live arms*. It
rejected a guard on an initialized `number | string` whose current
flow value was provably a single `number` or `string` with the other
arm of `typecore.split_typeof` equal to `Never`.

The checker now records exactly which arm is unreachable. It preserves
its existing restricted dead-arm policy: only assignments of direct
primitive literals to independent, initialized `let` targets can
typecheck there; mismatches still emit internal
`Assignment_Type_Mismatch` (TS2322 candidate), and no unreachable
writes can transfer state to the join. Writes to the narrowed guard,
nested conditions, name-based RHS, declarations, and anything requiring
general `never` expression typing remain fail-closed.

The then/else snapshots and existing dead-arm join mechanism discard
the impossible branch; the reachable branch keeps its full TypeId
and primitive literal facts, including inverted `!==` and unary
`!` guards. No new TypeId kernel layout, pool, public diagnostics,
or dump/3 schema changes. The zero-pool monomorphic path is unchanged.

Proof: independent `checker-typeof-never-{valid,errors}`
TS7 CLI fixtures, exact TS7 code/start matches, optional TS6 full spans,
native positive/negative and unsupported boundary tests. Never infer
full TypeScript conformance or benchmark speed from this subset.
