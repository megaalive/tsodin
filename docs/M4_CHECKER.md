# M4-A — first primitive checker slice

The development-only `src/checker` package completes the first **narrow
source → scanner → syntax → binder → primitive type diagnostics** pipeline.
It is not yet the full `tsodin check` command or TypeScript 7 parity.

## Supported, explicit subset

- One source file, with complete M2 syntax and complete M3-A binding
  from the *same immutable File_Id + generation*.
- `const`, `let`, `var`; optional primitive annotations (`number`,
  `string`, `boolean`); numeric and plain ASCII string literals.
- Nonforward, initialized local name references, unary numeric `+`/`-`,
  numeric `+`/`-`/`*`/`/`, and basic numeric/string concatenation.
- Simple primitive assignability and inferred base `number`/`string`
  types. This deliberately does not preserve TypeScript literal types.

## Memory and correctness boundary

The checker evaluates postorder parser nodes iteratively, using three
temporary dense arrays: inferred expression types, declaration types, and
symbol-reference indices. There is **no per-expression heap allocation** or
checker recursion, but no speedup is claimed before a measured real project.

A source with unsupported forward-use/temporal-dead-zone rules, uncertain
definite assignment, implicit-any declarations, unsupported operators,
unresolved names, stale snapshots, or invalid syntax is **rejected**.
Type mismatches emit internal `Assignment_Type_Mismatch` issues with
byte-span positions, which can be projected to UTF-16 by the source mapper.
Internal issues are NOT TypeScript diagnostic codes; do not label them TS2322.

`Report.complete` becomes true only after every declaration in the declared
subset was analyzed with no issues; mismatch reports are non-success.
`report_destroy` frees report-owned diagnostics.

## Proof

- `odin test src/checker`: type inference, arithmetic precedence,
  string concatenation, multiple mismatches, forward-use refusal,
  uninitialized references, incomplete binding and stale snapshots.
- `src/checktrace`: developer-only Odin executable reading actual .ts
  files and emitting source-to-type-diagnostics with UTF-16 positions;
  exit 0 accepted, 1 type mismatch, 2 fatal/unsupported.
- `tools/oracle/check-primitive-trace.mjs`: CI integration smoke of that
  executable on two project source files.
- Separate pinned TS7 CLI oracle captures for valid and error projects.
  They do **not** yet compare tsodin diagnostic code, span or message to
  TypeScript. The official conformance Pages panel must remain NOT RUN.

## Next gates

M4-B must turn captured TS7 diagnostics into strict differential assertions
with explicit unsupported cases. Expand lexical/grammar handling and type
relations only after keeping the complete supported slice correct.
Real-project benchmarking is premature while C1 parity remains open.

## M4-E — boolean literal vertical slice

Both `true` and `false` now have appended stable scanner token kinds,
a dedicated source-spanned boolean expression node and `Primitive.Boolean`
in the non-recursive checker. Previous scanner token ordinals remain intact.
Boolean literal inference and assignment to `boolean` declarations are
supported within the exact existing single-file grammar.

Operations such as `true + 1` are **not** accepted. Full TypeScript boolean
flow analysis, literal narrowing, truthiness, logical operators and
control-flow semantics are not implemented. Unsupported work remains fatal.

Two independent TypeScript 7.0.2 CLI projects test a valid boolean program
and two `TS2322` primitive mismatches. The Odin trace is checked against
the same fixtures for type errors. This is a bounded semantic extension,
not full conformance.

## M4-F — bounded relational, strict equality and logical operators

The scanner now recognizes `<`, `>`, `<=`, `>=`, `===`, `!==`, `&&`, `||` and unary `!`.
New token variants are appended so earlier lexical witness ordinals stay unchanged.
Unsupported loose `==`/`!=` and standalone `&`/`|` fail closed.
The expression parser preserves the TS ordering of unary, arithmetic, relational,
equality, logical conjunction, and logical disjunction precedence.

The primitive checker accepts numeric relational comparisons; boolean-only logical
operands and negation; and demonstrably overlapping strict equality (identical
source-backed literal spellings or the same bound name on both sides). Coarse
primitive types cannot yet represent TS literal/flow narrowing; accepting
`1 === 2` as a valid program would incorrectly suppress TS2367.
More complete truthiness, strict equality and literal narrowing remain future work.

Two independently pinned TS7.0.2 oracle projects exercise valid expressions and
TS2322 assignment mismatches. Native TS7 code + UTF-16 start positions are
compared separately from auxiliary TS6 structured full spans. These are scoped
witnesses, not full TypeScript conformance. Public `tsodin check` stays disabled.

## M4-G1 — source-backed literal identity and disjoint comparison diagnostics

The checker recognizes direct, same-primitive integer/boolean and unescaped
ASCII string literal pairs without allocating new per-node type objects.
String values are compared without their single/double quote delimiters.
For distinct direct literal values in strict equality/inequality, the
nonfatal internal `Disjoint_Literal_Comparison` issue is emitted with the
binary expression's source span. The checker continues scanning later
declarations; a report containing such issues must never be `complete`.

Internal issue ID 11 is separately mapped to candidate TS2367 in the
pinned TS7 7.0.2 CLI code/UTF-16 start witness and TS6 structured supplemental
span witness. Existing TS2322 internal issue ID 10 is unchanged.
The added oracle projects are `checker-literal-valid` and
`checker-literal-disjoint`.

This is NOT general TypeScript literal-type inference or control-flow
narrowing. Variable references, computed expressions, numeric spelling
edge cases and different primitive types remain conservatively bounded.
Official Microsoft conformance remains NOT RUN.

## M4-G2 — inferred const literal identity across references

A direct integer, unescaped string, or boolean literal carries its immutable
source span as a temporary `Literal_Fact` in the checker. When a `const`
without an explicit primitive annotation is initialized with such a literal,
the checker retains its *inferred literal identity* as a declaration fact.
Subsequent references and immutable `const` alias chains propagate that same
fact through the compact indexed binder and grouped expressions.

Example supported witnesses:

```ts
const low = 1;
const alias = low;
const high = 2;
const different = alias === high; // candidate TS2367
```

Disjoint proven literal facts emit nonfatal internal issue 11; equal facts
yield a boolean result. The pinned TS7.0.2 CLI still checks actual diagnostic
codes and UTF-16 start positions, with TS6.0.2 structured spans as supplemental
evidence. The new oracle fixtures are `checker-const-literal-valid` and
`checker-const-literal-disjoint`.

`let`/`var`, explicit annotations (which can widen the inferred literal
type), computed values, general type relations and flow narrowing are **not**
claimed. They do not acquire speculative facts. No public `tsodin check` or
official Microsoft conformance score is enabled. Two extra dense scratch
arrays store source spans; no per-node strings or object allocation is added.

## M4-G3 — disjoint primitive domains through widening

Under strict equality/inequality, the three supported primitive domains
`number`, `string` and `boolean` cannot overlap with *each other*.
When both operand types are known and different, the checker emits an
internal, recoverable `Disjoint_Primitive_Domains` diagnostic (ID 12).
This remains true when variables have explicit widening annotations, come
from earlier bound names, or are produced by supported arithmetic. This
requires no additional heap storage or mutable flow-state assumptions.

The existing literal-specific issue 11 and assignment issue 10 keep their
ordinals. Differential witness tooling maps issues 11/12 to candidate
`TS2367` and issue 10 to `TS2322`. The new pinned fixtures
`checker-domain-valid` and `checker-domain-errors` check actual
TS7 CLI diagnostic codes and UTF-16 start positions; TS6 structured spans
remain supplemental. Same-domain comparisons with insufficient overlap
proof still fail closed: widening alone does not prove TS literal/flow
semantics. This does not enable the public checker or establish official
TypeScript conformance.

## M4-G4 — computed-wide expression facts (not flow narrowing)

Arithmetic (`+`, `-`, `*`, `/`), supported string concatenation, and
numeric relational expressions produce broad primitive results. M4-G4
adds two dense `bool` fact arrays to the iterative checker: one per syntax
node, another per declaration. These facts flow through parentheses and
previous, inferred `const` aliases without allocating per-node strings.
When a strict equality compares two operands from the same primitive
domain, a proven broad computed result overlaps that domain, avoiding
a false unsupported failure.

Example:

```ts
const total = 1 + 2;
const copy = total;
const comparison: boolean = copy === 9; // valid in the pinned subset
```

A direct literal still retains its precise identity. Different literal
identities produce candidate TS2367; different primitive domains produce
candidate TS2367 even if computed; incompatible declaration annotations
produce candidate TS2322. Every diagnostic remains non-success, with
UTF-16 positions compared against pinned TypeScript 7.0.2 CLI output and
supplementary structured TS6.0.2 spans. New oracle fixtures:
`checker-wide-valid` and `checker-wide-errors`.

This is *not* general control-flow narrowing. In particular, mutable
`let`/`var`, annotations, unary constant folding, and arbitrary logical
operators are **not** presumed broad. They retain the previous
conservative refusal rules where exact TS flow rules are unimplemented.
Full official TypeScript conformance and public `tsodin check` remain
NOT RUN / unavailable.

## M4-G5A — first ordered, straight-line assignment transfer

The expression parser appends source-ordered `Expr_Statement` events alongside
the existing dense postorder syntax nodes. `Declaration` events continue to
point to the original declaration indices; `Assignment` events carry a
source-backed target Name node and RHS expression root. The binder resolves
assignment targets through the same stable symbol table and does not create
a new declaration/symbol on assignment.

The primitive checker executes events in source order. For an already
initialized `let` whose target type is known, `name = expression;` first
checks the RHS against the declared/inferred primitive domain. Mutable
number/string bindings retain their widened base types even after assignment
of a literal; TypeScript 7 does *not* report TS2367 merely because the last
number assignment differs from a compared numeric literal. Boolean literal
flow is limited to the tested cases, not general control-flow narrowing. The
checker records `checked_assignments` separately; source-to-diagnostics
`checktrace` keeps its existing external SUMMARY protocol unchanged.

```ts
let count: number = 1;
count = 2;
const okay: boolean = count === 2;
const possible = count === 3; // valid: widened number
count = 1 + 2;
const broad: boolean = count === 9;
```

Assignments to `const` and `var`, uninitialized targets, forward targets,
chained/compound assignments, branches, loops, destructuring, closures,
imports and exports **remain unsupported**. They must not return a false
successful check. The new parser event model is a foundation for CFG work,
not yet a control-flow graph or conditional type narrowing.

`checker-flow-assign-valid` and `checker-flow-assign-errors` extend the
native pinned TS7.0.2 diagnostic-code/UTF-16-start assertions. The TS6.0.2
structured end-span lane remains separately labeled as supplemental.
An incompatible `let` RHS produces candidate TS2322 covering the
assignment target identifier, supported by the TS7 start and TS6 complete
structured span witnesses; disjoint immutable `const` literals produce
candidate TS2367. No permanent numeric/string singleton fact is inferred from a
mutable assignment. No official conformance score is published.

## M4-G5B — bounded conditional narrowing and flow join

This gate admits a **flat, explicit** `if (name === literal) { assignments; }
else { assignments; }`. The guard must compare an already initialized
mutable `let` (number or string) whose primitive domain has been proved
broad with a matching source literal.

Three source-order events (`If`, `Else`, `End_If`) form a small
fork/join. Entry facts are copied into dense temporary arrays; the true arm
narrows the guard to its literal. The false arm starts from entry facts, not
the previous arm's mutations. After the join, only singleton identities
independently proved on both arms survive; otherwise changed values widen.
There is no per-node heap allocation or general CFG graph.

```ts
let code: number = 1;
code = 1 + 2;
let verdict: boolean = false;
if (code === 2) {
    verdict = code === 2;
} else {
    verdict = code === 3;
}
const merged: boolean = verdict === true;
const possible: boolean = code === 9;
```

The guard subset is intentionally narrower than TypeScript. The false arm
starts with the original broad primitive domain: it **does not** subtract
the equality guard's literal or claim negative-path exclusion. Unsupported
guards (including `!==`, relational conditions, truthiness), nested
branches, branch-local declarations and scopes, `else if`, implicit else,
loops, switch and closures **fail closed**. Multiple independent flat
conditionals reuse the same lazily allocated snapshots.

`checker-flow-branch-valid` and `checker-flow-branch-errors`
are checked against pinned **TypeScript 7.0.2** CLI diagnostic codes and
UTF-16 start coordinates. Internal issue 11 maps to TS2367; 10 to TS2322.
Auxiliary TS6.0.2 structured full spans remain separately labeled. No
public checker readiness or official conformance is claimed.
Neither the public checker nor a benchmark performance win is claimed by this event-only gate.

## M4-G5C — negative-arm narrowing under direct strict inequality

The existing event-only flat `if/else` checker now recognizes
`if (name !== literal)` when `name` is an initialized mutable
`let` with a proven-wide number/string domain and the literal has
the same primitive type. The `if` arm keeps the wide entry fact.
The `else` arm alone receives the proven identity `name === literal`.
Nothing subtracts the literal from the broad true-arm domain.

```ts
let code: number = 1;
code = 1 + 2;
let result: boolean = false;
if (code !== 2) {
    result = code === 2; // true arm remains wide
} else {
    result = code === 2; // false arm proves exact equality
}
const after: boolean = code === 9; // join remains broad
```

Assignment kills a branch-local literal fact; the original conservative
fork/join combines independently proven facts only. Branch snapshots are
still lazy, with no general graph or per-node heap objects.

The new `checker-flow-negative-valid` and
`checker-flow-negative-errors` fixtures cover numeric/string conditions,
disjoint literals, assignment mismatch and post-join restoration.
Native pinned **TS7.0.2** compares diagnostic codes and UTF-16 starts;
**TS6.0.2** structured full spans are supplemental. Odin unit tests
also cover assignment invalidation and unsupported guard rejection.

Reversed operands, chained guards, truthiness, general negation,
literal-exclusion types, branch-local declarations, nested branches,
implicit else and loops remain outside the proof boundary: **fail closed**.
No public checker, official Microsoft conformance pass, or real-world
performance win is claimed by this milestone.

## M4-G5D — negated comparisons and proven-wide boolean guards

G5D extends the **existing event-only, flat, explicit if/else** slice;
it does not introduce a heap-allocated CFG. The checker strips only
transparent parentheses and unary `!` from a guard, tracking inverted
polarity. The inner guard must remain a direct `name === literal` or
`name !== literal` (number, string or boolean), or a direct **boolean**
`let` name. The name must resolve to an initialized mutable `let` with
a proven-wide primitive domain at the entry snapshot.

A direct `if (flag)` narrows `flag` to true in the then branch and
false in the else branch; `if (!flag)` reverses the facts. Strict
comparisons against a boolean literal can also narrow the *opposite*
branch because the boolean domain contains exactly two values. For
number/string, opposite branches remain broad; we do **not** fabricate
exclusion types. Arbitrary truthiness for number/string is unsupported.

```ts
let count: number = 1;
count = 1 + 2;
let flag: boolean = false;
flag = count === 2;
let outcome: boolean = false;
if (!flag) {
    outcome = flag === false; // proven false
} else {
    outcome = flag === true;  // proven true
}
if (!(count === 2)) {
    outcome = count === 3;   // no exclusion fact inferred
} else {
    outcome = count === 2;   // proven literal
}
```

For boolean-only flow facts, a reserved, **internal** `Literal_Fact`
marker (`byte_start=-1`, `byte_end=0/1`) encodes proved
false/true without allocating strings or widening the fact structure.
It is NEVER treated as a source span or surfaced as a diagnostic
position. `literal_overlap` handles this marker alongside real source
boolean literal tokens. A branch-local mutation replaces the fact;
the existing join retains only facts independently proved on both arms.

`checker-flow-guards-valid` and `checker-flow-guards-errors`
add pinned native TS7.0.2 code/UTF-16-start witnesses and independently
labeled TS6.0.2 structured full-span witnesses. Unit tests cover
double negation, direct boolean guards, complementary literal guards,
branch-local disjoint facts, source-backed errors, and fail-closed
unsupported guards.

Not supported: `&&`/`||` as guards, nested branches, optional
`else`, unproven/widening-free names, property accesses, reversed
operands, side-effecting conditions, closures, or general truthiness.
Public `tsodin check` stays disabled; official Microsoft conformance
is NOT RUN. No speed comparison to Rust/Go is claimed.

## M4-G5E — bounded two-level nested if/else flow

The parser accepts **at most two levels** of explicit `if/else` with
assignment-only arms; the third level, missing `else`, branch-local
declarations, `else if` and other unsupported statements fail closed.
Statements remain flat and source-ordered (If / Else / End_If), with
nested markers emitted in lexical order. No general heap CFG is built.

The checker stores **independent fork/join snapshots per active depth**
with lazy, reusable dense buffers. At the nested `End_If`, the child
joins its two paths into the **parent's current arm**; the parent's entry
snapshot and other arm remain untouched. An assignment in one child arm
invalidates its singleton on join if not proved by both child arms.
After the outer join, only facts common to its two outcomes survive.

```ts
let code: number = 1;
code = 1 + 2;
let ready: boolean = false;
ready = code === 2;
let result: boolean = false;
if (code === 2) {
    if (ready) {
        result = code === 2; // outer fact persists in nested arm
    } else {
        result = code === 2; // independent child path
    }
} else {
    result = code === 9;     // broad outer false arm
}
```

A nesting limit of 2 is deliberate, separate from expression depth 64;
it bounds snapshot storage to four dense arrays per encountered level.
Straight-line files still allocate no branch snapshots. Source spans,
internal issue IDs, TS7-compatible diagnostics, and the public checker
fail-closed boundary remain unchanged.

The new `checker-flow-nested-valid` and `checker-flow-nested-errors`
fixtures compare Odin issues with pinned **TS7.0.2 diagnostic codes
and UTF-16 starts** and auxiliary **TS6.0.2 structured full spans**.
Unit tests exercise nested ordering, parent fact preservation, branch
mutation invalidation and depth-three refusal. These are scoped witnesses,
NOT full official TypeScript conformance. Public `tsodin check` stays
disabled and no Rust/Go build-time speedup is claimed.

## M4-G5F1 — independent two-operand short-circuit guards

The checker now recognizes **one** `&&` or `||` in a conditional guard,
with two distinct, proven-wide `let` bindings. Each operand must independently
match the prior M4-G5D narrowable form (`flag`, `!flag`, or a
left-hand-name strict equality to a literal); outer `!` and grouped guards
are accepted. The parser's pure expression subset contains no side-effecting
assignment, call, or property access in a condition.

TypeScript's short circuit does **not** prove both operands evaluated:
- `a && b` proves **both true** only in the true arm; the false arm
  receives neither inferred singleton.
- `a || b` proves **both false** only in the false arm; the true arm
  receives neither inferred singleton.
- Wrapping either expression in `!` swaps those conclusions between arms;
  negation on either individual operand reverses its Boolean fact.

This is bounded conjunction/disjunction *branch implication*, NOT eager
execution of an arbitrary right operand. Already-evaluated expression trees
are side-effect-free under this grammar. Facts are stored in a fixed
two-element per-depth metadata array; the existing lazy, dense snapshots
retain independent nested fork/join state. Assignments still replace
singleton facts, and joins preserve only values proven along both paths.

Repeated guard bindings (until G5F2), chained/nested compound operators,
unproved operands, and side-effecting syntax remain fail-closed rather than
claiming contradiction resolution, conditional evaluation of effects, or
full TypeScript flow behavior. The depth-two bound and public CLI restriction
remain unchanged.

`checker-flow-compound-valid` and `checker-flow-compound-errors`
extend pinned TS7.0.2 diagnostic-code and UTF-16-start parity, with
independent TS6.0.2 structured-span supplementary witnesses.
No official TypeScript suite or build-time competitive benchmark is claimed.

## M4-G5F2 — RHS conditional analysis and idempotent guards

The right expression of a pure short-circuit conditional is *analyzed*
under a temporary snapshot of what evaluating the left side proves:
`&&` assumes the left side is true; `||` assumes it is false.
Only a source-backed singleton or the previously documented synthetic
Boolean fact may enter this temporary state. Postorder syntax guarantees
that the right subtree occupies the contiguous node interval immediately
following the left root. The checker restores the original flow slot after
the right subtree, *before* branch entry and parent fork/join logic.
This is static checking of a potentially-executed path, not eager
execution of mutations; the accepted condition grammar has no calls,
assignments or property effects.

Two repeated guards of the **same mutable binding** are now legal only
when the decisive path proves the *same literal value* in both operands.
Idempotent Boolean predicates such as `flag && flag` or
`flag || flag` also infer the complementary Boolean singleton
on the other arm. Contradictory guards (`a && !a`), inconsistent literal
intersections, unproved chained/nested compounds and side-effecting
conditions remain fail-closed until reachability and conditional effects
are explicitly represented. Numeric/string domains never gain a
complementary singleton from an exclusion.

The new `checker-flow-rhs-{valid,errors}` fixtures extend strict
pinned TS7.0.2 diagnostic-code and UTF-16-start comparisons and
supplemental TS6.0.2 structured full-span witnesses. This is not
general TypeScript flow, official conformance or a performance claim.
Public `tsodin check` remains disabled.

## M4-G5F3 — bounded Boolean contradiction-aware reachability

Two complementary *bare Boolean* predicates on the same initialized,
proven-wide `let` now establish a **dead arm**:
`flag && !flag` cannot enter its true arm, and `flag || !flag`
cannot enter its false arm. An enclosing unary `!` swaps those arms.
The accepted unreachable arm **must be empty**. Its flow snapshot is not
joined with the only reachable arm, so assignments in the live arm
remain effective. Two per-depth Boolean reachability flags add no heap
allocation and preserve the existing depth-two bound.

Statements inside an unreachable arm remain **fatal unsupported**, not
silently ignored: TypeScript still typechecks unreachable statements,
and this bounded checker cannot yet represent its `never` state.
Nested unreachable conditionals, unrelated primitive or numeric
contradictions, equality expressions that may produce TS2367 during
short-circuit checking, and complex Boolean formulas are not accepted.
The RHS retains G5F2's temporary left-operand context and is restored
before the fork. No general CFG or global unreachable-code elision
has been introduced.

`checker-flow-contradiction-{valid,errors}` add pinned TS7.0.2
diagnostic-code and UTF-16-start witnesses and TS6.0.2 supplemental
structured-span checks. This is narrowly scoped checker evidence,
not official conformance. Public `tsodin check` remains disabled.

A nested live parent guard with a contradictory child guard is included in
both Odin unit tests and the TS7 valid witness to prevent per-depth
reachability flags from leaking into the enclosing branch.

## M4-G5F4 — typecheck direct primitive writes in unreachable arms

A proven-dead Boolean contradiction arm may now contain assignments to
previously initialized independent `let` variables with **direct**
integer, string or Boolean literal RHS expressions. The checker performs
normal declared-domain checking on these assignments, preserving TS2322
candidate errors (including in unreachable code), but **does not transfer**
dead assignments into any live flow state. The dead predecessor remains
excluded from the join, preserving assignment facts on the only live path.

Dead-arm assignments to any enclosing guard variable, references or
computed expressions on the RHS, and nested conditionals remain fatal
unsupported. This conservative boundary avoids claiming TypeScript's
general unreachable `never` semantics. Multiple direct writes are
typechecked in source order, with no per-statement heap allocation.
`checker-flow-dead-assign-{valid,errors}` provide pinned TS7.0.2
diagnostic-code/UTF-16-start oracle evidence and supplemental TS6.0.2
structured spans. Public `tsodin check` remains disabled and official
conformance is NOT RUN.

The original G5F3 fail-closed tests are retained and updated to cover
reference/computed expressions (still unsupported), while the newly
supported direct-literal assignments have their own positive and
TS2322-negative witnesses. Contradiction identity is retained per depth
for rejection of writes to the impossible branch's guard target.

## M4-G5F5 — homogeneous three-operand Boolean guard chains

The checker now accepts **exactly three** independent proven-wide Boolean
`let` names (including grouped or `!`-negated names) in a
left-associative homogeneous `a && b && c` or `a || b || c` guard.
For conjunction, only the true arm inherits all three implied facts;
for disjunction, only the false arm inherits all three. Outer `!`
reverses the arms. No implication is assigned to the other arm.
Snapshots and compact per-depth guard slots extend from two to three;
straight-line source still allocates no branch snapshots.

The three-operand case excludes equality leaves, repeated bindings,
mixed/chained operator trees, four-or-more operands, side effects and
unproved expressions. It is not a general Boolean formula evaluator.
Two-operand idempotence and contradiction behavior are preserved as-is.

`checker-flow-three-guards-{valid,errors}` extend pinned TS7.0.2
diagnostic-code/UTF-16-start comparison and TS6.0.2 structured-span
supplementary witness. Public `tsodin check` remains disabled, and no
official conformance or competitive benchmark result is claimed.

## M4-G5F6 — nested mutation/join evidence for three-way guards

The depth-two checker, previously proved for one- and two-part guards, is
now explicitly regression-tested with a three-part parent guard and an
independent inner Boolean `if/else`. Assigning a computed wide Boolean
value to one parent binding inside a child arm must widen that binding
at the child join; the other two parent singleton facts must remain
intact until their own enclosing join. Both TS2367 path-local errors
and TS2322 assignment mismatches are asserted in their source order.

`checker-flow-three-nested-{valid,errors}` are pinned native TS7.0.2
code/start UTF-16 differential fixtures with TS6.0.2 supplementary
structured spans. This is a correctness regression milestone, **not**
additional grammar support, official conformance, or a speed claim.
