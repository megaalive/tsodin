package typecore

// M4-G5F8V: a bounded, canonical primitive-type kernel. No syntax or
// diagnostics are accepted merely because an internal Type_Id exists.
// IDs are local to one Pool; the nine built-in IDs are fixed.
Type_Id :: distinct u32

Invalid :: Type_Id(0)
Never   :: Type_Id(1)
Any     :: Type_Id(2)
Unknown :: Type_Id(3)
Number  :: Type_Id(4)
Text    :: Type_Id(5)
Boolean :: Type_Id(6)
True    :: Type_Id(7)
False   :: Type_Id(8)

Kind :: enum {
    Invalid,
    Never,
    Any,
    Unknown,
    Number,
    Text,
    Boolean,
    True,
    False,
    Union,
}

Node :: struct {
    kind: Kind,
    first: u32,
    count: u32,
}

// Pool owns all union nodes and their flattened sorted memberships.
// A borrowed member slice is invalidated by the next successful insertion.
// No global interning table, per-node pointer graph, or implicit allocator.
Pool :: struct {
    nodes: [dynamic]Node,
    members: [dynamic]Type_Id,
}

pool_init :: proc() -> Pool {
    p: Pool
    for i in 0..<9 {
        append(&p.nodes, Node{kind=Kind(i)})
    }
    return p
}

pool_destroy :: proc(p: ^Pool) {
    if p == nil { return }
    delete(p.members)
    delete(p.nodes)
    p^ = Pool{}
}

valid :: proc(p: ^Pool, id: Type_Id) -> bool {
    return p != nil && len(p.nodes) >= 9 &&
           id != Invalid && int(u32(id)) < len(p.nodes) &&
           p.nodes[int(u32(id))].kind != .Invalid
}

kind_of :: proc(p: ^Pool, id: Type_Id) -> Kind {
    if !valid(p, id) { return .Invalid }
    return p.nodes[int(u32(id))].kind
}

// Borrowed view. Never retain across pool intern operations.
union_members :: proc(p: ^Pool, id: Type_Id) -> ([]Type_Id, bool) {
    if kind_of(p, id) != .Union { return nil, false }
    node := p.nodes[int(u32(id))]
    start := int(node.first)
    end := start + int(node.count)
    if start < 0 || end > len(p.members) || start >= end {
        return nil, false
    }
    return p.members[start:end], true
}

same_members :: proc(a, b: []Type_Id) -> bool {
    if len(a) != len(b) { return false }
    for i in 0..<len(a) {
        if a[i] != b[i] { return false }
    }
    return true
}

// Canonical union for the *supported* primitive fragment:
// - flatten nested unions and remove never/duplicates;
// - any absorbs unknown and everything else; unknown absorbs other types;
// - true | false -> boolean; boolean absorbs true/false;
// - canonical order is ascending built-in ID;
// - intern equal unions in this pool, independent of input order.
// Invalid IDs fail closed without modifying the pool.
intern_union :: proc(p: ^Pool, input: []Type_Id) -> (Type_Id, bool) {
    if p == nil || len(p.nodes) < 9 { return Invalid, false }
    flattened: [dynamic]Type_Id
    defer delete(flattened)
    for id in input { append(&flattened, id) }

    has_any := false
    has_unknown := false
    has_boolean := false
    has_true := false
    has_false := false
    cursor := 0
    for cursor < len(flattened) {
        id := flattened[cursor]
        if !valid(p, id) { return Invalid, false }
        kind := kind_of(p, id)
        if kind == .Union {
            nested, ok := union_members(p, id)
            if !ok { return Invalid, false }
            for member in nested { append(&flattened, member) }
        } else if kind == .Any {
            has_any = true
        } else if kind == .Unknown {
            has_unknown = true
        } else if kind == .Boolean {
            has_boolean = true
        } else if kind == .True {
            has_true = true
        } else if kind == .False {
            has_false = true
        }
        cursor += 1
    }
    if has_any { return Any, true }
    if has_unknown { return Unknown, true }
    if has_true && has_false { has_boolean = true }

    used := 0
    for id in flattened {
        kind := kind_of(p, id)
        if kind == .Union || kind == .Never { continue }
        if has_boolean && (kind == .True || kind == .False) { continue }
        duplicate := false
        for previous in 0..<used {
            if flattened[previous] == id {
                duplicate = true
                break
            }
        }
        if !duplicate {
            flattened[used] = id
            used += 1
        }
    }
    if has_boolean {
        found := false
        for i in 0..<used {
            if flattened[i] == Boolean { found = true; break }
        }
        if !found {
            flattened[used] = Boolean
            used += 1
        }
    }

    if used == 0 { return Never, true }
    if used == 1 { return flattened[0], true }
    // Insertion sort is tiny and deterministic for primitive union arity.
    for i in 1..<used {
        current := flattened[i]
        j := i
        for j > 0 && u32(flattened[j-1]) > u32(current) {
            flattened[j] = flattened[j-1]
            j -= 1
        }
        flattened[j] = current
    }
    canonical := flattened[:used]
    for index in 9..<len(p.nodes) {
        node := p.nodes[index]
        if node.kind != .Union || int(node.count) != used { continue }
        old, ok := union_members(p, Type_Id(index))
        if ok && same_members(old, canonical) {
            return Type_Id(index), true
        }
    }

    // This slice currently interns only primitive unions; a future general
    // TypeId table must replace the linear lookup before large-scale usage.
    first := len(p.members)
    append(&p.members, ..canonical)
    append(&p.nodes, Node{
        kind=.Union, first=u32(first), count=u32(used),
    })
    return Type_Id(len(p.nodes)-1), true
}

atom_assignable :: proc(source, target: Kind) -> bool {
    if source == target { return true }
    return (source == .True || source == .False) && target == .Boolean
}

// Restricted relation, intentionally not TypeScript's full structural relation.
// A union source must fit the target; each source member may choose a different
// target union member. Invalid handles fail closed (never silently succeed).
assignable :: proc(p: ^Pool, source, target: Type_Id) -> (bool, bool) {
    if !valid(p, source) || !valid(p, target) { return false, false }
    if source == target || source == Never || target == Any || target == Unknown {
        return true, true
    }
    if target == Never { return false, true }
    if source == Any { return true, true }
    if source == Unknown { return false, true }
    source_kind := kind_of(p, source)
    target_kind := kind_of(p, target)
    if source_kind == .Union {
        parts, ok := union_members(p, source)
        if !ok { return false, false }
        for member in parts {
            accepts, supported := assignable(p, member, target)
            if !supported { return false, false }
            if !accepts { return false, true }
        }
        return true, true
    }
    if target_kind == .Union {
        parts, ok := union_members(p, target)
        if !ok { return false, false }
        for member in parts {
            if atom_assignable(source_kind, kind_of(p, member)) {
                return true, true
            }
        }
        return false, true
    }
    return atom_assignable(source_kind, target_kind), true
}

atom_overlap :: proc(a, b: Kind) -> bool {
    if a == b { return true }
    return (a == .Boolean && (b == .True || b == .False)) ||
           (b == .Boolean && (a == .True || a == .False))
}

// Possible value-domain overlap for this primitive subset, not the
// result of === or a substitute for flow analysis.
overlap :: proc(p: ^Pool, left, right: Type_Id) -> (bool, bool) {
    if !valid(p, left) || !valid(p, right) { return false, false }
    if left == Never || right == Never { return false, true }
    if left == Any || right == Any || left == Unknown || right == Unknown {
        return true, true
    }
    left_kind := kind_of(p, left)
    right_kind := kind_of(p, right)
    if left_kind == .Union {
        parts, ok := union_members(p, left)
        if !ok { return false, false }
        for member in parts {
            yes, supported := overlap(p, member, right)
            if !supported { return false, false }
            if yes { return true, true }
        }
        return false, true
    }
    if right_kind == .Union {
        parts, ok := union_members(p, right)
        if !ok { return false, false }
        for member in parts {
            if atom_overlap(left_kind, kind_of(p, member)) {
                return true, true
            }
        }
        return false, true
    }
    return atom_overlap(left_kind, right_kind), true
}

// Return both branches for typeof == "number"/"string"/"boolean" when every
// constituent is in the supported primitive domain. No guesses for any,
// unknown, open object domains, null, undefined, or unimplemented types.
// This is the reusable semantic operation; parser and CFG wiring come later.
split_typeof :: proc(p: ^Pool, id, primitive: Type_Id) -> (yes, no: Type_Id, ok: bool) {
    if !valid(p, id) ||
       !(primitive == Number || primitive == Text || primitive == Boolean) {
        return Invalid, Invalid, false
    }
    if id == Any || id == Unknown {
        return Invalid, Invalid, false
    }
    parts: []Type_Id
    if kind_of(p, id) == .Union {
        parts, ok = union_members(p, id)
        if !ok { return Invalid, Invalid, false }
    } else {
        parts = []Type_Id{id}
    }
    matched: [dynamic]Type_Id
    unmatched: [dynamic]Type_Id
    defer delete(matched)
    defer delete(unmatched)
    for member in parts {
        kind := kind_of(p, member)
        if kind == .Any || kind == .Unknown || kind == .Invalid ||
           kind == .Union {
            return Invalid, Invalid, false
        }
        if kind == .Never { continue }
        is_match := member == primitive ||
                    (primitive == Boolean && (member == True || member == False))
        if is_match {
            append(&matched, member)
        } else {
            append(&unmatched, member)
        }
    }
    yes_id, yes_ok := intern_union(p, matched[:])
    no_id, no_ok := intern_union(p, unmatched[:])
    if !yes_ok || !no_ok { return Invalid, Invalid, false }
    return yes_id, no_id, true
}
