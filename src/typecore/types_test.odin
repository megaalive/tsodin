package typecore

import "core:testing"

@(test)
typecore_stable_atoms_and_pool_lifetime :: proc(t: ^testing.T) {
    p := pool_init()
    testing.expect(t, valid(&p, Number) && kind_of(&p, True)==.True &&
                   !valid(&p, Invalid) && !valid(&p, Type_Id(9999)),
                   "fixed atom IDs and invalid handles")
    pool_destroy(&p)
    testing.expect(t, !valid(&p, Number), "destroy invalidates the whole pool")
}

@(test)
typecore_canonical_union_interns_order_duplicates_and_nested :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    first, ok := intern_union(&p, []Type_Id{Text, Number, Number, Never})
    testing.expect(t, ok && kind_of(&p, first)==.Union, "new primitive union")
    reversed, ok2 := intern_union(&p, []Type_Id{Number, Text})
    nested, ok3 := intern_union(&p, []Type_Id{first, Text, Never})
    testing.expect(t, ok2 && ok3 && first==reversed && first==nested,
                   "canonical IDs ignore spelling order and nesting")
    members, has_members := union_members(&p, first)
    testing.expect(t, has_members && len(members)==2 &&
                   members[0]==Number && members[1]==Text,
                   "union holds sorted, flattened, unique IDs")
}

@(test)
typecore_any_unknown_never_and_boolean_reduction :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    none, a := intern_union(&p, nil)
    empty, b := intern_union(&p, []Type_Id{Never, Never})
    any_type, c := intern_union(&p, []Type_Id{Unknown, Any, Number})
    unknown_type, d := intern_union(&p, []Type_Id{Unknown, Text})
    bool_type, e := intern_union(&p, []Type_Id{True, False})
    bool_type2, f := intern_union(&p, []Type_Id{Boolean, False, True})
    testing.expect(t, a && b && c && d && e && f &&
                   none==Never && empty==Never && any_type==Any &&
                   unknown_type==Unknown && bool_type==Boolean &&
                   bool_type2==Boolean,
                   "absorption and Boolean literal normalization")
}

@(test)
typecore_invalid_input_does_not_mutate_intern_store :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    old_nodes := len(p.nodes)
    old_members := len(p.members)
    result, ok := intern_union(&p, []Type_Id{Number, Type_Id(777), Text})
    testing.expect(t, !ok && result==Invalid &&
                   len(p.nodes)==old_nodes && len(p.members)==old_members,
                   "reject invalid handle atomically")
    _, success := union_members(&p, Number)
    testing.expect(t, !success, "non-union is not exposed as member storage")
}

@(test)
typecore_union_assignability_preserves_constituents :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    numeric_text, ok := intern_union(&p, []Type_Id{Number, Text})
    all, ok2 := intern_union(&p, []Type_Id{Boolean, Text, Number})
    yes, known := assignable(&p, Number, numeric_text)
    other, known2 := assignable(&p, numeric_text, Number)
    common, known3 := assignable(&p, numeric_text, all)
    bool_true, known4 := assignable(&p, True, Boolean)
    bool_reverse, known5 := assignable(&p, Boolean, True)
    testing.expect(t, ok && ok2 && known && known2 && known3 &&
                   known4 && known5 && yes && !other && common &&
                   bool_true && !bool_reverse,
                   "union source/all and target/any, Boolean literal subtyping")
}

@(test)
typecore_special_assignability_and_invalid_rejection :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    n, a := assignable(&p, Never, Number)
    u, b := assignable(&p, Number, Unknown)
    unknown_src, c := assignable(&p, Unknown, Number)
    any_src, d := assignable(&p, Any, Text)
    any_to_never, e := assignable(&p, Any, Never)
    invalid, f := assignable(&p, Type_Id(1234), Number)
    testing.expect(t, a && b && c && d && e && !f && n && u &&
                   !unknown_src && any_src && !any_to_never && !invalid,
                   "special cases never grant success to an invalid handle")
}

@(test)
typecore_overlap_is_not_equality :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    pair, ok := intern_union(&p, []Type_Id{Number, Text})
    disjoint, known := overlap(&p, Number, Text)
    common, known2 := overlap(&p, pair, Text)
    bools, known3 := overlap(&p, Boolean, True)
    opposite, known4 := overlap(&p, True, False)
    never_overlap, known5 := overlap(&p, Never, Number)
    testing.expect(t, ok && known && known2 && known3 && known4 &&
                   known5 && !disjoint && common && bools &&
                   !opposite && !never_overlap,
                   "overlap is a domain property, never a Boolean runtime result")
}

@(test)
typecore_typeof_narrows_both_primitive_arms :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    all, ok := intern_union(&p, []Type_Id{Boolean, Number, Text})
    expect_other, ok2 := intern_union(&p, []Type_Id{Text, Boolean})
    yes, no, valid_split := split_typeof(&p, all, Number)
    testing.expect(t, ok && ok2 && valid_split &&
                   yes==Number && no==expect_other,
                   "typeof number partitions a three-way union")
    only, other, valid_single := split_typeof(&p, True, Boolean)
    testing.expect(t, valid_single && only==True && other==Never,
                   "Boolean literal narrowing retains the singleton")
    none, all_remaining, valid_disjoint := split_typeof(&p, Text, Number)
    testing.expect(t, valid_disjoint && none==Never && all_remaining==Text,
                   "unreachable primitive arm is never")
}

@(test)
typecore_typeof_unknown_and_invalid_fail_closed :: proc(t: ^testing.T) {
    p := pool_init()
    defer pool_destroy(&p)
    _, _, unknown_ok := split_typeof(&p, Unknown, Number)
    _, _, any_ok := split_typeof(&p, Any, Number)
    _, _, invalid_ok := split_typeof(&p, Type_Id(12345), Number)
    _, _, target_ok := split_typeof(&p, Text, True)
    testing.expect(t, !unknown_ok && !any_ok && !invalid_ok && !target_ok,
                   "no fabricated narrowing of unknown or unsupported inputs")
}
