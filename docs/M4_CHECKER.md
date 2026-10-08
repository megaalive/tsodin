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
