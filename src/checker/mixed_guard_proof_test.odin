package checker

import "core:testing"
import "../parser"
import "../binder"

// No new language shape: this tests the shared lookup/provenance predicate,
// while the existing mixed-right/left/nested TypeScript oracle fixtures
// continue to test full source-to-diagnostic behavior independently.
@(test)
checker_mixed_guard_three_distinct_wide_lets :: proc(t: ^testing.T) {
    nodes := [3]parser.Expr_Node{
        {kind=.Name}, {kind=.Name}, {kind=.Name},
    }
    ids := [3]int{0, 1, 2}
    refs := [3]int{1, 2, 3}
    symbols := [3]binder.Symbol{
        {kind=.Let, declaration_index=0},
        {kind=.Let, declaration_index=1},
        {kind=.Let, declaration_index=2},
    }
    declared := [3]Primitive{.Boolean, .Boolean, .Boolean}
    wide := [3]bool{true, true, true}
    testing.expect(t, three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "three proven-wide Boolean let bindings are eligible")

    refs[2] = 1
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "repeated reference to one declaration is not independent")
    refs[2] = 3
    symbols[2].declaration_index = 0
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "different symbol indices cannot conceal the same declaration")
    symbols[2].declaration_index = 2

    symbols[0].kind = .Const
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "const is never a mutable flow guard")
    symbols[0].kind = .Let

    wide[1] = false
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "unknown or singleton-only evidence is not a proven-wide guard")
    wide[1] = true
    declared[2] = .Number
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "non-Boolean bindings cannot enter Boolean compound narrowing")
    declared[2] = .Boolean
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 2),
        "forward declarations must not enter the flow state")
}

@(test)
checker_mixed_guard_invalid_references_fail_closed :: proc(t: ^testing.T) {
    nodes := [3]parser.Expr_Node{
        {kind=.Name}, {kind=.Name}, {kind=.Name},
    }
    ids := [3]int{0, 1, 2}
    refs := [3]int{1, 2, 3}
    symbols := [3]binder.Symbol{
        {kind=.Let, declaration_index=0},
        {kind=.Let, declaration_index=1},
        {kind=.Let, declaration_index=2},
    }
    declared := [3]Primitive{.Boolean, .Boolean, .Boolean}
    wide := [3]bool{true, true, true}
    refs[1] = 0
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "unresolved zero symbol references are rejected")
    refs[1] = 4
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "out-of-range binder indices are rejected before dereference")
    refs[1] = 2
    ids[1] = -1
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "negative AST indices are rejected before dereference")
    ids[1] = 3
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "out-of-range AST indices are rejected before dereference")
    ids[1] = 1
    nodes[1].kind = .Boolean
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "literal operands are never considered independent name guards")
    nodes[1].kind = .Name
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:2], symbols[:], declared[:], wide[:], 3),
        "truncated reference table must fail closed")
    symbols[2].declaration_index = 99
    testing.expect(t, !three_distinct_wide_boolean_lets(
        nodes[:], ids, refs[:], symbols[:], declared[:], wide[:], 3),
        "out-of-range declaration indices are rejected before dereference")
}
