package checker

import "core:testing"
import "../parser"
import "../scanner"

// The same pure unwrapping invariant must serve the short-circuit RHS,
// full condition guards and Boolean identity guard recognition.
@(test)
checker_guard_wrapper_postorder_and_negation_parity :: proc(t: ^testing.T) {
    nodes := [?]parser.Expr_Node{
        {kind=.Name, left=-1},
        {kind=.Group, left=0},
        {kind=.Unary, operator=.Exclamation, left=1},
        {kind=.Unary, operator=.Exclamation, left=2},
        {kind=.Group, left=3},
    }
    plain := unwrap_guard_wrappers(nodes[:], 0, 0)
    testing.expect(t, plain.valid && plain.index==0 && !plain.flipped,
                   "plain names keep the original node and polarity")
    grouped := unwrap_guard_wrappers(nodes[:], 1, 0)
    testing.expect(t, grouped.valid && grouped.index==0 && !grouped.flipped,
                   "parentheses never change Boolean polarity")
    one := unwrap_guard_wrappers(nodes[:], 2, 0)
    testing.expect(t, one.valid && one.index==0 && one.flipped,
                   "single negation flips polarity exactly once")
    twice := unwrap_guard_wrappers(nodes[:], 4, 0)
    testing.expect(t, twice.valid && twice.index==0 && !twice.flipped,
                   "double negation and group retain original polarity")
    clipped := unwrap_guard_wrappers(nodes[:], 4, 2)
    testing.expect(t, !clipped.valid,
                   "crossing expression lower bound is forbidden")
    impossible := unwrap_guard_wrappers(nodes[:], 5, 0)
    testing.expect(t, !impossible.valid,
                   "a nonexistent node cannot be followed")
}

@(test)
checker_guard_wrapper_malformed_children_fail_closed :: proc(t: ^testing.T) {
    nodes := [?]parser.Expr_Node{
        {kind=.Name, left=-1},
        {kind=.Group, left=1},
        {kind=.Unary, operator=.Exclamation, left=-1},
        {kind=.Unary, operator=.Exclamation, left=4},
        {kind=.Unary, operator=.Minus, left=0},
    }
    for index in 1..=3 {
        actual := unwrap_guard_wrappers(nodes[:], index, 0)
        testing.expect(t, !actual.valid,
                       "invalid or nonpostorder wrapper child must fail closed")
    }
    non_boolean := unwrap_guard_wrappers(nodes[:], 4, 0)
    testing.expect(t, non_boolean.valid && non_boolean.index==4 &&
                   !non_boolean.flipped,
                   "nonlogical unary operators must never be peeled")
    negative := unwrap_guard_wrappers(nodes[:], -1, 0)
    testing.expect(t, !negative.valid,
                   "negative node indices are never inspected")
}
