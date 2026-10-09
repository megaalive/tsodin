package checker

import "../binder"
import "../parser"
import "../scanner"
import "../source"
import "../typecore"

// M4-A: a deliberately restricted, one-file semantic slice.
// All issue kinds are INTERNAL; none are TypeScript diagnostic codes.
Primitive :: enum {
    Unknown,
    Number,
    Text,
    Boolean,
    Union, // Canonical union IDs are stored in separate dense arrays.
}

Check_Issue :: enum {
    Invalid_Input,
    Incomplete_Syntax,
    Incomplete_Binding,
    Snapshot_Mismatch,
    Unsupported_Implicit_Any,
    Unsupported_Forward_Reference,
    Unsupported_Definite_Assignment,
    Unsupported_Expression,
    Invalid_Expression_Node,
    Incompatible_Operator,
    Assignment_Type_Mismatch,
    // Appended: preserve internal issue IDs used by the TS2322 witness.
    Disjoint_Literal_Comparison,
    // Independent proof: base primitive domains cannot overlap under ===/!==.
    Disjoint_Primitive_Domains,
    Unsupported_Assignment_Target, // fail closed on const/var and unknown flow
    Unsupported_Condition, // unproved branch guard or malformed CFG event
}

Diagnostic :: struct {
    issue: Check_Issue,
    byte_start: int,
    byte_end: int,
}

// Opt-in, bounded evidence only; there is no general type-relation engine.
// The hot-path check_file wrapper deliberately requests .None.
Relation_Trace_Mode :: enum { None, Failures, All }
Relation_Context :: enum { Variable, Assignment }
Type_Relation :: struct {
    source: Primitive,
    target: Primitive,
    node_index: int, // actual postorder RHS expression root
    declaration_index: int, // actual parser declaration index
    relation_kind: Relation_Context,
    result: bool, // the same comparison used by the checker
}

// Distinct from assignment compatibility: a proof of possible overlap
// between equality operands, NOT the runtime result of === or !==.
// No record is emitted when overlap cannot be proven either way.
Comparison_Proof :: enum {
    Disjoint_Domains,
    Disjoint_Literals,
    Same_Symbol,
    Same_Literal,
    Widened_Domain,
}
Comparison_Evidence :: struct {
    left: Primitive,
    right: Primitive,
    node_index: int, // postorder equality expression, not either operand
    operator: scanner.Token_Kind, // strict === or !==
    proof: Comparison_Proof,
    overlaps: bool, // describes operand domains, never runtime Boolean value
}

Report :: struct {
    file_id: source.File_Id,
    generation: u32,
    diagnostics: [dynamic]Diagnostic,
    relations: [dynamic]Type_Relation,
    comparisons: [dynamic]Comparison_Evidence,
    checked_declarations: int,
    checked_assignments: int,
    complete: bool,
    fatal: bool,
}

report_destroy :: proc(r: ^Report) {
    delete(r.diagnostics)
    delete(r.relations)
    delete(r.comparisons)
    r^ = Report{}
}

fail :: proc(r: ^Report, kind: Check_Issue, start, end: int, fatal: bool) {
    append(&r.diagnostics, Diagnostic{
        issue=kind, byte_start=start, byte_end=end,
    })
    if fatal {
        r.fatal = true
    }
}

// Record decisions at their actual checking site, not reconstructed by the UI.
record_relation :: proc(
    report: ^Report, mode: Relation_Trace_Mode,
    source_type, target_type: Primitive,
    node_index, declaration_index: int, kind: Relation_Context,
    compatible: bool,
) {
    if mode == .None || source_type == .Unknown || target_type == .Unknown { return }
    if compatible && mode != .All { return }
    append(&report.relations, Type_Relation{
        source=source_type, target=target_type,
        node_index=node_index, declaration_index=declaration_index,
        relation_kind=kind, result=compatible,
    })
}

// PERF: .None exits before append. The regular checker path never owns a
// comparison evidence buffer; developer traces reuse the existing mode.
record_comparison :: proc(
    report: ^Report, mode: Relation_Trace_Mode,
    left, right: Primitive, node_index: int, op: scanner.Token_Kind,
    proof: Comparison_Proof, overlaps: bool,
) {
    if mode == .None || (mode == .Failures && overlaps) { return }
    append(&report.comparisons, Comparison_Evidence{
        left=left, right=right, node_index=node_index,
        operator=op, proof=proof, overlaps=overlaps,
    })
}

annotation_type :: proc(value: parser.Primitive_Type) -> Primitive {
    if value == .Number {
        return .Number
    }
    if value == .String {
        return .Text
    }
    if value == .Boolean {
        return .Boolean
    }
    return .Unknown
}

// The existing primitive fast path stays in place for monomorphic code.
// Only union-bearing assignments pay for the TypeId relation.
primitive_type_id :: proc(kind: Primitive) -> typecore.Type_Id {
    switch kind {
    case .Number: return typecore.Number
    case .Text: return typecore.Text
    case .Boolean: return typecore.Boolean
    case .Unknown, .Union: return typecore.Invalid
    }
    return typecore.Invalid
}

primitive_from_id :: proc(pool: ^typecore.Pool, id: typecore.Type_Id) -> Primitive {
    switch typecore.kind_of(pool, id) {
    case .Number: return .Number
    case .Text: return .Text
    case .Boolean: return .Boolean
    case .Union: return .Union
    case: return .Unknown
    }
    return .Unknown
}

union_annotation_mask :: proc(kind: parser.Primitive_Type) -> u8 {
    switch kind {
    case .Number_String: return 3
    case .Number_Boolean: return 5
    case .String_Boolean: return 6
    case .Number_String_Boolean: return 7
    case .Inferred, .Number, .String, .Boolean: return 0
    }
    return 0
}

union_annotation_id :: proc(pool: ^typecore.Pool, mask: u8) -> (typecore.Type_Id, bool) {
    if mask == 0 || mask > 7 { return typecore.Invalid, false }
    members: [3]typecore.Type_Id
    count := 0
    if (mask & 1) != 0 { members[count] = typecore.Number; count += 1 }
    if (mask & 2) != 0 { members[count] = typecore.Text; count += 1 }
    if (mask & 4) != 0 { members[count] = typecore.Boolean; count += 1 }
    return typecore.intern_union(pool, members[:count])
}

// A value can carry a proven literal identity without allocating a string.
// A default (.Name) kind means unknown. Ordinary spans are source-backed;
// the explicitly marked Boolean fact below is synthetic for if(flag)/!flag.
Literal_Fact :: struct {
    kind: parser.Expr_Kind,
    byte_start: int,
    byte_end: int,
}

literal_fact_from_node :: proc(node: parser.Expr_Node) -> Literal_Fact {
    if node.kind == .Integer || node.kind == .Text || node.kind == .Boolean {
        return Literal_Fact{
            kind=node.kind, byte_start=node.byte_start, byte_end=node.byte_end,
        }
    }
    return Literal_Fact{}
}

// INVARIANT: byte_start=-1 only for a proven branch Boolean; byte_end=0/1
// stores false/true. No source mapper may consume this fact as a byte span.
// This keeps the existing compact fact layout and avoids per-node storage.
branch_boolean_fact :: proc(value: bool) -> Literal_Fact {
    return Literal_Fact{
        kind=.Boolean, byte_start=-1, byte_end=value ? 1 : 0,
    }
}

boolean_fact_value :: proc(fact: Literal_Fact, text: string) -> (bool, bool) {
    if fact.kind != .Boolean { return false, false }
    if fact.byte_start == -1 {
        if fact.byte_end == 0 { return false, true }
        if fact.byte_end == 1 { return true, true }
        return false, false
    }
    if fact.byte_start < 0 || fact.byte_end > len(text) ||
       fact.byte_start >= fact.byte_end {
        return false, false
    }
    spelling := text[fact.byte_start:fact.byte_end]
    if spelling == "true" { return true, true }
    if spelling == "false" { return false, true }
    return false, false
}

// Source-backed literal equality. Strings contain no escapes in this grammar;
// stripping either quote delimiter preserves the value. This does not handle
// computed expressions, widened annotations or mutable flow types.
literal_overlap :: proc(a, b: Literal_Fact, text: string) -> (both_literals, same_value: bool) {
    if a.kind != b.kind || a.kind == .Name { return false, false }
    if a.kind == .Integer {
        return true, text[a.byte_start:a.byte_end] == text[b.byte_start:b.byte_end]
    }
    if a.kind == .Boolean {
        a_value, a_ok := boolean_fact_value(a, text)
        b_value, b_ok := boolean_fact_value(b, text)
        return a_ok && b_ok, a_ok && b_ok && a_value == b_value
    }
    if a.kind == .Text {
        // Lexer guarantees both delimiters and forbids escape sequences.
        if a.byte_end-a.byte_start < 2 || b.byte_end-b.byte_start < 2 {
            return false, false
        }
        return true, text[a.byte_start+1:a.byte_end-1] ==
                     text[b.byte_start+1:b.byte_end-1]
    }
    return false, false
}

// Every expression child index must be earlier than its parent (postorder).
// This allows a linear, non-recursive evaluator on dense syntax nodes.
operand_type :: proc(nodes: []parser.Expr_Node, inferred: []Primitive, child, current: int) -> (Primitive, bool) {
    if child < 0 || child >= current || child >= len(nodes) {
        return .Unknown, false
    }
    if inferred[child] == .Unknown {
        return .Unknown, false
    }
    return inferred[child], true
}

// Pure postorder wrapper traversal shared by condition recognition, contextual
// RHS guards and identity reduction. No allocation, no type inference.
// INVARIANT: every Group or unary ! child is strictly earlier than its
// parent AND belongs to this expression (index >= lower_bound).
// A malformed wrapper returns valid=false; callers decide whether a hard
// condition failure or conservative no-context result is appropriate.
Guard_Wrapper :: struct {
    index: int,
    flipped: bool,
    valid: bool,
}

unwrap_guard_wrappers :: proc(
    nodes: []parser.Expr_Node, start, lower_bound: int,
) -> Guard_Wrapper {
    if lower_bound < 0 || start < lower_bound || start >= len(nodes) {
        return Guard_Wrapper{}
    }
    index := start
    flipped := false
    for {
        node := nodes[index]
        if node.kind != .Group &&
           !(node.kind == .Unary && node.operator == .Exclamation) {
            break
        }
        if node.left < lower_bound || node.left >= index {
            return Guard_Wrapper{}
        }
        if node.kind == .Unary { flipped = !flipped }
        index = node.left
    }
    return Guard_Wrapper{index=index, flipped=flipped, valid=true}
}

// Validate the three independent widened Boolean let bindings required by
// a mixed &&/|| guard. The input is a fixed tuple of actual Name AST nodes,
// not a computed predicate or a list of guessed declarations.
// Every source reference is range-checked before indexing; duplicate binder
// declarations are rejected even when referenced through different nodes.
// Pure and allocation-free; the caller still decides WHICH arm gets a fact.
// M4-G5F8Q: caller-site forcing is an isolated candidate, not a
// permanent speed claim. The pinned same-runner probe determines retention.
three_distinct_wide_boolean_lets :: proc(
    nodes: []parser.Expr_Node,
    node_indices: [3]int,
    references: []int,
    symbols: []binder.Symbol,
    declared: []Primitive,
    wide_decls: []bool,
    checked_declarations: int,
) -> bool {
    guards: [3]int
    for slot in 0..<3 {
        index := node_indices[slot]
        if index < 0 || index >= len(nodes) ||
           index >= len(references) || nodes[index].kind != .Name {
            return false
        }
        ref := references[index]
        if ref <= 0 || ref > len(symbols) { return false }
        symbol := symbols[ref-1]
        guard := symbol.declaration_index
        if symbol.kind != .Let || guard < 0 ||
           guard >= checked_declarations ||
           guard >= len(declared) || guard >= len(wide_decls) ||
           declared[guard] != .Boolean || !wide_decls[guard] {
            return false
        }
        for previous in 0..<slot {
            if guards[previous] == guard { return false }
        }
        guards[slot] = guard
    }
    return true
}

check_file_with_relations :: proc(
    version: ^source.Source_Version,
    syntax: ^parser.Syntax_Report,
    symbols: ^binder.Binding_Report,
    trace_mode: Relation_Trace_Mode,
) -> Report {
    result: Report
    if version == nil || !version.initialized || syntax == nil || symbols == nil {
        fail(&result, .Invalid_Input, 0, 0, true)
        return result
    }
    result.file_id=version.file_id
    result.generation=version.generation
    if syntax.file_id != version.file_id || syntax.generation != version.generation ||
       symbols.file_id != version.file_id || symbols.generation != version.generation {
        fail(&result, .Snapshot_Mismatch, 0, 0, true)
        return result
    }
    if !syntax.complete || syntax.fatal || len(syntax.diagnostics)>0 {
        fail(&result, .Incomplete_Syntax, 0, 0, true)
        return result
    }
    if !symbols.complete || symbols.fatal || len(symbols.issues)>0 {
        fail(&result, .Incomplete_Binding, 0, 0, true)
        return result
    }

    // Dense temporary arrays; source-backed facts use spans, not heap strings.
    inferred := make([]Primitive, len(syntax.nodes))
    defer delete(inferred)
    declared := make([]Primitive, len(syntax.declarations))
    defer delete(declared)
    // PERF: no TypeId pool or extra dense scratch arrays for the existing
    // monomorphic checker. Union handles are local to this invocation.
    union_file := false
    for d in syntax.declarations {
        if union_annotation_mask(d.type_kind) != 0 {
            union_file = true
            break
        }
    }
    pool: typecore.Pool
    expression_ids: []typecore.Type_Id
    declared_ids: []typecore.Type_Id
    flow_ids: []typecore.Type_Id
    if union_file {
        pool = typecore.pool_init()
        expression_ids = make([]typecore.Type_Id, len(syntax.nodes))
        declared_ids = make([]typecore.Type_Id, len(syntax.declarations))
        flow_ids = make([]typecore.Type_Id, len(syntax.declarations))
    }
    defer {
        if union_file {
            delete(expression_ids)
            delete(declared_ids)
            delete(flow_ids)
            typecore.pool_destroy(&pool)
        }
    }
    references := make([]int, len(syntax.nodes))
    defer delete(references)
    literal_nodes := make([]Literal_Fact, len(syntax.nodes))
    defer delete(literal_nodes)
    literal_decls := make([]Literal_Fact, len(syntax.declarations))
    defer delete(literal_decls)
    // A computed expression can have a widened primitive result while
    // direct literals still carry precise identities. No flow guessing.
    wide_nodes := make([]bool, len(syntax.nodes))
    defer delete(wide_nodes)
    wide_decls := make([]bool, len(syntax.declarations))
    defer delete(wide_decls)
    // PERF: Straight-line files allocate no branch snapshots. Each nesting
    // level obtains its own four dense buffers only when first encountered.
    // A completed child join mutates the enclosing arm's current facts;
    // parent's entry/then snapshots are never overwritten by a child.
    entry_literals: [parser.FLOW_NEST_LIMIT][]Literal_Fact
    then_literals: [parser.FLOW_NEST_LIMIT][]Literal_Fact
    entry_wide: [parser.FLOW_NEST_LIMIT][]bool
    then_wide: [parser.FLOW_NEST_LIMIT][]bool
    // Flow TypeIds are allocated ONLY when a union annotation is present.
    // Join snapshots are per-depth and preserve all other variable states.
    entry_ids: [parser.FLOW_NEST_LIMIT][]typecore.Type_Id
    then_ids: [parser.FLOW_NEST_LIMIT][]typecore.Type_Id
    typeof_guard: [parser.FLOW_NEST_LIMIT]int
    typeof_else_id: [parser.FLOW_NEST_LIMIT]typecore.Type_Id
    for &index in typeof_guard { index = -1 }
    defer {
        for level in 0..<parser.FLOW_NEST_LIMIT {
            delete(entry_literals[level])
            delete(then_literals[level])
            delete(entry_wide[level])
            delete(then_wide[level])
            delete(entry_ids[level])
            delete(then_ids[level])
        }
    }

    for ref in symbols.references {
        if ref.node_index < 0 || ref.node_index >= len(syntax.nodes) ||
           ref.symbol_index < 0 || ref.symbol_index >= len(symbols.symbols) ||
           references[ref.node_index] != 0 {
            fail(&result, .Invalid_Input, ref.byte_start, ref.byte_end, true)
            return result
        }
        references[ref.node_index]=ref.symbol_index+1
    }

    text := version.owned_text
    node_cursor := 0
    flow_depth := 0
    else_seen: [parser.FLOW_NEST_LIMIT]bool
    // A proven-impossible arm cannot participate in a reachable-path join.
    // Primitive literal writes can be typechecked without executing their
    // flow transfer; expressions requiring never-state analysis remain fatal.
    dead_then: [parser.FLOW_NEST_LIMIT]bool
    dead_else: [parser.FLOW_NEST_LIMIT]bool
    contradiction_guard: [parser.FLOW_NEST_LIMIT]int
    // Per-depth split metadata prevents child conditionals from corrupting
    // parent guard facts. The live literal_decls/wide_decls arrays represent
    // the current path and are the only state consumed by expressions.
    // Up to three *bare Boolean* operands in a homogeneous chain;
    // restricted mixed formulas carry only one entailed Boolean fact.
    // Other complex chains fail closed without a general CFG.
    // A short-circuit arm only receives facts logically implied by that arm.
    guard_count: [parser.FLOW_NEST_LIMIT]int
    guard_indices: [parser.FLOW_NEST_LIMIT][3]int
    guard_then_facts: [parser.FLOW_NEST_LIMIT][3]Literal_Fact
    guard_else_facts: [parser.FLOW_NEST_LIMIT][3]Literal_Fact
    for event in syntax.statements {
        if event.kind == .Else {
            if flow_depth == 0 || event.declaration_index != -1 ||
               event.target_node != -1 || event.expression != -1 {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
            level := flow_depth-1
            if else_seen[level] {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
            // Save the completed THEN arm, then restore this depth's entry
            // state. A nested join cannot overwrite an enclosing snapshot.
            if union_file {
                copy(then_ids[level], flow_ids)
                copy(flow_ids, entry_ids[level])
                if typeof_guard[level] >= 0 {
                    flow_ids[typeof_guard[level]] = typeof_else_id[level]
                }
            }
            copy(then_literals[level], literal_decls)
            copy(then_wide[level], wide_decls)
            copy(literal_decls, entry_literals[level])
            copy(wide_decls, entry_wide[level])
            for slot in 0..<guard_count[level] {
                if guard_else_facts[level][slot].kind != .Name {
                    literal_decls[guard_indices[level][slot]] = guard_else_facts[level][slot]
                    wide_decls[guard_indices[level][slot]] = false
                }
            }
            else_seen[level] = true
            continue
        }
        if event.kind == .End_If {
            if flow_depth == 0 || event.declaration_index != -1 ||
               event.target_node != -1 || event.expression != -1 {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
            level := flow_depth-1
            if !else_seen[level] {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
            // An unreachable arm has no runtime predecessor.
            // Joining it would erase facts from the only reachable path.
            if dead_else[level] {
                copy(literal_decls, then_literals[level])
                copy(wide_decls, then_wide[level])
            } else if !dead_then[level] {
                // Both live arms: retain only singleton facts proved on both.
                for i in 0..<len(declared) {
                    identical, same := literal_overlap(then_literals[level][i], literal_decls[i], text)
                    if identical && same && !then_wide[level][i] && !wide_decls[i] {
                        literal_decls[i] = then_literals[level][i]
                        wide_decls[i] = false
                    } else if then_wide[level][i] || wide_decls[i] ||
                              then_literals[level][i].kind != literal_decls[i].kind ||
                              (identical && !same) {
                        literal_decls[i] = Literal_Fact{}
                        wide_decls[i] = true
                    } else {
                        literal_decls[i] = Literal_Fact{}
                        wide_decls[i] = false
                    }
                }
            }
            if union_file {
                if dead_else[level] {
                    copy(flow_ids, then_ids[level])
                } else if !dead_then[level] {
                    for i in 0..<len(declared_ids) {
                        if declared_ids[i] == typecore.Invalid { continue }
                        pair := [2]typecore.Type_Id{then_ids[level][i], flow_ids[i]}
                        joined, ok := typecore.intern_union(&pool, pair[:])
                        if !ok {
                            fail(&result, .Unsupported_Condition,
                                 event.byte_start, event.byte_end, true)
                            return result
                        }
                        flow_ids[i] = joined
                    }
                }
                typeof_guard[level] = -1
                typeof_else_id[level] = typecore.Invalid
            }
            // If THEN is impossible, live ELSE is already in the current arrays.
            dead_then[level] = false
            dead_else[level] = false
            contradiction_guard[level] = -1
            else_seen[level] = false
            guard_count[level] = 0
            for slot in 0..<3 {
                guard_indices[level][slot] = -1
                guard_then_facts[level][slot] = Literal_Fact{}
                guard_else_facts[level][slot] = Literal_Fact{}
            }
            flow_depth -= 1
            continue
        }
        condition_event := event.kind == .If
        dead_assignment := false
        if flow_depth > 0 {
            enclosing := flow_depth-1
            if (!else_seen[enclosing] && dead_then[enclosing]) ||
               (else_seen[enclosing] && dead_else[enclosing]) {
                // TypeScript diagnoses wrong assignments even in a dead arm.
                // Only side-effect-free direct primitive literals to an
                // independent initialized let are proven checker-safe here.
                // The value is typechecked but NOT transferred to flow state.
                if event.kind != .Assignment || event.expression < 0 ||
                   event.expression >= len(syntax.nodes) {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                rhs := syntax.nodes[event.expression]
                if rhs.kind != .Integer && rhs.kind != .Text && rhs.kind != .Boolean {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                dead_assignment = true
            }
        }
        if condition_event && flow_depth >= parser.FLOW_NEST_LIMIT {
            fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
            return result
        }
        if event.kind == .Declaration && flow_depth > 0 {
            // The grammar cannot bind block declarations yet. Reject even
            // forged complete event streams instead of leaking fake scope.
            fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
            return result
        }
        assignment := event.kind == .Assignment
        // An assignment has no declaration index of its own. References in
        // its RHS may only see declarations already processed in source order.
        declaration_index := event.declaration_index
        if assignment || condition_event {
            declaration_index = result.checked_declarations
        }
        target_index := -1
        decl: parser.Expr_Declaration
        declared_type := Primitive.Unknown
        declared_id := typecore.Invalid
        if assignment {
            if event.target_node != node_cursor ||
               event.target_node < 0 || event.target_node >= len(syntax.nodes) {
                fail(&result, .Invalid_Expression_Node,
                     event.byte_start, event.byte_end, true)
                return result
            }
            target := syntax.nodes[event.target_node]
            ref := references[event.target_node]
            if target.kind != .Name || ref <= 0 || ref > len(symbols.symbols) {
                fail(&result, .Invalid_Expression_Node,
                     event.byte_start, event.byte_end, true)
                return result
            }
            symbol := symbols.symbols[ref-1]
            target_index = symbol.declaration_index
            if target_index < 0 || target_index >= len(declared) ||
               target_index >= len(syntax.declarations) {
                fail(&result, .Invalid_Input, target.byte_start, target.byte_end, true)
                return result
            }
            // A deliberately restricted flow subset: initialized let only.
            // Const, var, and definite-assignment reasoning remain unsupported.
            original := syntax.declarations[target_index]
            if symbol.kind != .Let || original.initializer < 0 ||
               original.byte_start >= event.byte_start ||
               declared[target_index] == .Unknown {
                fail(&result, .Unsupported_Assignment_Target,
                     target.byte_start, target.byte_end, true)
                return result
            }
            declared_type = declared[target_index]
            if union_file { declared_id = declared_ids[target_index] }
            if dead_assignment {
                // Never allow writes to the contradictory guard binding, nor
                // to any enclosing narrowing guard; its never-state meaning
                // must not be silently replaced by our broad declared type.
                for depth in 0..<flow_depth {
                    for slot in 0..<guard_count[depth] {
                        if guard_indices[depth][slot] == target_index {
                            fail(&result, .Unsupported_Condition,
                                 target.byte_start, target.byte_end, true)
                            return result
                        }
                    }
                    if contradiction_guard[depth] == target_index {
                        fail(&result, .Unsupported_Condition,
                             target.byte_start, target.byte_end, true)
                        return result
                    }
                }
            }
        } else if condition_event {
            if event.declaration_index != -1 || event.target_node != -1 {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
        } else {
            if event.kind != .Declaration || declaration_index < 0 ||
               declaration_index >= len(syntax.declarations) {
                fail(&result, .Invalid_Input, event.byte_start, event.byte_end, true)
                return result
            }
            decl = syntax.declarations[declaration_index]
            if decl.name_start < 0 || decl.name_start >= decl.name_end ||
               decl.name_end > len(text) {
                fail(&result, .Invalid_Input, decl.byte_start, decl.byte_end, true)
                return result
            }
            declared_type = annotation_type(decl.type_kind)
            declared_id = primitive_type_id(declared_type)
            mask := union_annotation_mask(decl.type_kind)
            if mask != 0 {
                declared_type = .Union
                ok: bool
                declared_id, ok = union_annotation_id(&pool, mask)
                if !ok || typecore.kind_of(&pool, declared_id) != .Union {
                    fail(&result, .Invalid_Input, decl.byte_start, decl.byte_end, true)
                    return result
                }
            }
            if decl.initializer < 0 {
                if declared_type == .Unknown {
                    fail(&result, .Unsupported_Implicit_Any,
                         decl.name_start, decl.name_end, true)
                    return result
                }
                declared[declaration_index] = declared_type
                if union_file {
                    declared_ids[declaration_index] = declared_id
                    flow_ids[declaration_index] = declared_id
                }
                result.checked_declarations += 1
                continue
            }
        }
        expression_root := event.expression
        if expression_root < node_cursor || expression_root >= len(syntax.nodes) {
            fail(&result, .Invalid_Expression_Node,
                 event.byte_start, event.byte_end, true)
            return result
        }

        // M4-G5F2: the RHS of a pure logical guard is checked under the
        // left predicate's success (&&) or failure (||) state. The syntax is
        // postorder: the right subtree begins immediately after left's root.
        // This is *static conditional analysis*, NOT eager runtime execution.
        // Only proven singleton facts from the supported leaf grammar apply.
        rhs_context_begin := -1
        rhs_context_end := -1
        rhs_context_guard := -1
        rhs_context_fact: Literal_Fact
        rhs_saved_fact: Literal_Fact
        rhs_saved_wide := false
        if condition_event {
            root_unwrapped := unwrap_guard_wrappers(
                syntax.nodes[:], expression_root, node_cursor)
            root_idx := expression_root
            if root_unwrapped.valid { root_idx = root_unwrapped.index }
            logical := syntax.nodes[root_idx]
            if logical.kind == .Binary &&
               (logical.operator == .Ampersand_Ampersand ||
                logical.operator == .Bar_Bar) &&
               logical.left >= node_cursor && logical.left < logical.right &&
               logical.right < root_idx {
                lhs_unwrapped := unwrap_guard_wrappers(
                    syntax.nodes[:], logical.left, node_cursor)
                lhs_idx := logical.left
                lhs_flipped := false
                if lhs_unwrapped.valid {
                    lhs_idx = lhs_unwrapped.index
                    lhs_flipped = lhs_unwrapped.flipped
                }
                lhs := syntax.nodes[lhs_idx]
                lhs_ref := -1
                lhs_then: Literal_Fact
                lhs_else: Literal_Fact
                if lhs.kind == .Name {
                    lhs_ref = references[lhs_idx]
                    lhs_then = branch_boolean_fact(!lhs_flipped)
                    lhs_else = branch_boolean_fact(lhs_flipped)
                } else if lhs.kind == .Binary &&
                          (lhs.operator == .Equals_Equals_Equals ||
                           lhs.operator == .Exclamation_Equals_Equals) &&
                          lhs.left >= node_cursor && lhs.right > lhs.left &&
                          lhs.right < lhs_idx {
                    left_name := syntax.nodes[lhs.left]
                    rhs_literal := syntax.nodes[lhs.right]
                    if left_name.kind == .Name {
                        lhs_ref = references[lhs.left]
                        fact := literal_fact_from_node(rhs_literal)
                        negative := (lhs.operator == .Exclamation_Equals_Equals) != lhs_flipped
                        if rhs_literal.kind == .Boolean {
                            value, known := boolean_fact_value(fact, text)
                            if known {
                                if negative {
                                    lhs_then = branch_boolean_fact(!value)
                                    lhs_else = fact
                                } else {
                                    lhs_then = fact
                                    lhs_else = branch_boolean_fact(!value)
                                }
                            }
                        } else if negative {
                            lhs_else = fact
                        } else {
                            lhs_then = fact
                        }
                    }
                }
                if lhs_ref > 0 && lhs_ref <= len(symbols.symbols) {
                    binding := symbols.symbols[lhs_ref-1]
                    guard := binding.declaration_index
                    if binding.kind == .Let && guard >= 0 &&
                       guard < result.checked_declarations &&
                       guard < len(declared) && wide_decls[guard] {
                        rhs_literal := lhs_then
                        if logical.operator == .Bar_Bar { rhs_literal = lhs_else }
                        if rhs_literal.kind != .Name {
                            rhs_context_guard = guard
                            rhs_context_fact = rhs_literal
                            rhs_context_begin = logical.left+1
                            rhs_context_end = logical.right
                        }
                    }
                }
            }
        }
        // The parser writes child nodes before their parent and appends each
        // declaration's expression nodes consecutively.
        for i in node_cursor..=expression_root {
            if i == rhs_context_begin {
                rhs_saved_fact = literal_decls[rhs_context_guard]
                rhs_saved_wide = wide_decls[rhs_context_guard]
                literal_decls[rhs_context_guard] = rhs_context_fact
                wide_decls[rhs_context_guard] = false
            }
            node := syntax.nodes[i]
            if node.byte_start < 0 || node.byte_end > len(text) ||
               node.byte_start >= node.byte_end {
                fail(&result, .Invalid_Expression_Node, node.byte_start, node.byte_end, true)
                return result
            }

            kind := Primitive.Unknown
            if node.kind == .Integer {
                kind = .Number
                literal_nodes[i] = literal_fact_from_node(node)
            } else if node.kind == .Text {
                kind = .Text
                literal_nodes[i] = literal_fact_from_node(node)
            } else if node.kind == .Boolean {
                kind = .Boolean
                literal_nodes[i] = literal_fact_from_node(node)
            } else if node.kind == .Name {
                entry := references[i]
                if entry <= 0 || entry > len(symbols.symbols) {
                    fail(&result, .Invalid_Expression_Node, node.byte_start, node.byte_end, true)
                    return result
                }
                symbol := symbols.symbols[entry-1]
                if symbol.declaration_index < 0 || symbol.declaration_index >= len(declared) {
                    fail(&result, .Invalid_Input, node.byte_start, node.byte_end, true)
                    return result
                }
                if symbol.declaration_index >= declaration_index {
                    // TDZ / hoist rules are not implemented; no false success
                    // for names whose declaration appears later in source.
                    fail(&result, .Unsupported_Forward_Reference, node.byte_start, node.byte_end, true)
                    return result
                }
                previous := syntax.declarations[symbol.declaration_index]
                if previous.initializer < 0 {
                    fail(&result, .Unsupported_Definite_Assignment, node.byte_start, node.byte_end, true)
                    return result
                }
                kind = declared[symbol.declaration_index]
                if union_file {
                    expression_ids[i] = flow_ids[symbol.declaration_index]
                    if kind == .Union {
                        kind = primitive_from_id(&pool, expression_ids[i])
                        if kind != .Union {
                            literal_nodes[i] = Literal_Fact{}
                            wide_nodes[i] = true
                        }
                    }
                }
                // Declared primitive and current flow/literal facts are
                // separate. Mutable bindings can narrow until reassigned;
                // annotations to number/string stay wide at comparisons.
                if declared[symbol.declaration_index] != .Union {
                    literal_nodes[i] = literal_decls[symbol.declaration_index]
                    wide_nodes[i] = wide_decls[symbol.declaration_index]
                }
                if kind == .Unknown {
                    fail(&result, .Unsupported_Expression, node.byte_start, node.byte_end, true)
                    return result
                }
            } else if node.kind == .Group || node.kind == .Unary {
                child, ok := operand_type(syntax.nodes[:], inferred, node.left, i)
                if !ok {
                    fail(&result, .Invalid_Expression_Node, node.byte_start, node.byte_end, true)
                    return result
                }
                if node.kind == .Unary {
                    if node.operator == .Typeof_Keyword {
                        // Runtime typeof of a supported primitive or union
                        // is a string. Only exact guard patterns narrow.
                        kind = .Text
                        wide_nodes[i] = true
                    } else if node.operator == .Exclamation && child == .Boolean {
                        kind = .Boolean
                        // COMPAT: negating a proven-wide Boolean yields a
                        // Boolean domain, never a singleton truth value.
                        // An unproved literal negation remains unsupported
                        // for later equality comparisons (fail closed).
                        wide_nodes[i] = wide_nodes[node.left]
                        if !wide_nodes[i] {
                            // Only a proven Boolean singleton can be negated
                            // into another singleton. Reuse the branch fact
                            // sentinel, never an invented source byte span.
                            value, known := boolean_fact_value(
                                literal_nodes[node.left], text)
                            if known {
                                literal_nodes[i] = branch_boolean_fact(!value)
                            }
                        }
                    } else if (node.operator == .Plus || node.operator == .Minus) &&
                              child == .Number {
                        kind = .Number
                    } else {
                        fail(&result, .Incompatible_Operator, node.byte_start, node.byte_end, true)
                        return result
                    }
                } else {
                    kind = child
                    literal_nodes[i] = literal_nodes[node.left]
                    wide_nodes[i] = wide_nodes[node.left]
                }
            } else if node.kind == .Binary {
                left, left_ok := operand_type(syntax.nodes[:], inferred, node.left, i)
                right, right_ok := operand_type(syntax.nodes[:], inferred, node.right, i)
                if !left_ok || !right_ok {
                    fail(&result, .Invalid_Expression_Node, node.byte_start, node.byte_end, true)
                    return result
                }
                if left == .Union || right == .Union {
                    // We do not yet reason about overlap or operations on
                    // union constituents. Never report false disjointness.
                    fail(&result, .Unsupported_Expression,
                         node.byte_start, node.byte_end, true)
                    return result
                }
                if node.operator == .Plus {
                    if left == .Text || right == .Text {
                        if (left == .Number || left == .Text) &&
                           (right == .Number || right == .Text) {
                            kind = .Text
                        }
                    } else if left == .Number && right == .Number {
                        kind = .Number
                    }
                } else if (node.operator == .Minus || node.operator == .Asterisk ||
                           node.operator == .Slash || node.operator == .Percent) &&
                          left == .Number && right == .Number {
                    kind = .Number
                }
                // Basic arithmetic and plain concatenation produce a base
                // primitive, not an inferred literal type. Keep this fact
                // independent of the operands' known literal identities.
                if kind != .Unknown && (node.operator == .Plus ||
                   node.operator == .Minus || node.operator == .Asterisk ||
                   node.operator == .Slash || node.operator == .Percent) {
                    wide_nodes[i] = true
                }
                if (node.operator == .Less_Than || node.operator == .Greater_Than ||
                    node.operator == .Less_Than_Equals || node.operator == .Greater_Than_Equals) &&
                   left == .Number && right == .Number {
                    kind = .Boolean
                    wide_nodes[i] = true
                } else if (node.operator == .Ampersand_Ampersand || node.operator == .Bar_Bar) &&
                          left == .Boolean && right == .Boolean {
                    // Logical operators return operands, not a fresh
                    // comparison Boolean. Pure Boolean operands permit only
                    // the implied singleton, otherwise a proven-wide domain.
                    // No eager execution or truthiness conversion is assumed.
                    kind = .Boolean
                    a, a_known := boolean_fact_value(literal_nodes[node.left], text)
                    b, b_known := boolean_fact_value(literal_nodes[node.right], text)
                    if node.operator == .Ampersand_Ampersand {
                        if (a_known && !a) || (b_known && !b) {
                            literal_nodes[i] = branch_boolean_fact(false)
                        } else if a_known && b_known {
                            literal_nodes[i] = branch_boolean_fact(true)
                        } else if wide_nodes[node.left] || wide_nodes[node.right] {
                            wide_nodes[i] = true
                        }
                    } else {
                        if (a_known && a) || (b_known && b) {
                            literal_nodes[i] = branch_boolean_fact(true)
                        } else if a_known && b_known {
                            literal_nodes[i] = branch_boolean_fact(false)
                        } else if wide_nodes[node.left] || wide_nodes[node.right] {
                            wide_nodes[i] = true
                        }
                    }
                } else if node.operator == .Equals_Equals_Equals ||
                          node.operator == .Exclamation_Equals_Equals {
                    if left != right {
                        // Number, string and boolean are pairwise disjoint
                        // domains for strict equality, even when an annotation
                        // widened either operand. No literal assumptions needed.
                        fail(&result, .Disjoint_Primitive_Domains,
                             node.byte_start, node.byte_end, false)
                        record_comparison(&result, trace_mode, left, right, i,
                                          node.operator, .Disjoint_Domains, false)
                        kind = .Boolean
                    } else {
                        // Same primitive domain does NOT prove overlap: TS
                        // literal and flow-narrowing rules may still report
                        // TS2367. Retain M4-G2's conservative proof boundary.
                        lhs := syntax.nodes[node.left]
                        rhs := syntax.nodes[node.right]
                        same_name := lhs.kind == .Name && rhs.kind == .Name &&
                                     references[node.left] > 0 &&
                                     references[node.left] == references[node.right]
                        both_literals, same_value := literal_overlap(
                            literal_nodes[node.left], literal_nodes[node.right], text)
                        if same_name || (both_literals && same_value) ||
                           wide_nodes[node.left] || wide_nodes[node.right] {
                            // These are alternative *proofs of possible overlap*,
                            // not claims that the equality expression is true.
                            proof := Comparison_Proof.Widened_Domain
                            if same_name {
                                proof = .Same_Symbol
                            } else if both_literals && same_value {
                                proof = .Same_Literal
                            }
                            record_comparison(&result, trace_mode, left, right, i,
                                              node.operator, proof, true)
                            kind = .Boolean
                        } else if both_literals {
                            fail(&result, .Disjoint_Literal_Comparison,
                                 node.byte_start, node.byte_end, false)
                            record_comparison(&result, trace_mode, left, right, i,
                                              node.operator, .Disjoint_Literals, false)
                            kind = .Boolean
                        }
                    }
                }
                if kind == .Boolean &&
                   (node.operator == .Equals_Equals_Equals ||
                    node.operator == .Exclamation_Equals_Equals) {
                    // Equality computes a boolean result, not a singleton
                    // truth value. Its dynamic result can flow through joins.
                    wide_nodes[i] = true
                }
                if kind == .Unknown {
                    fail(&result, .Incompatible_Operator, node.byte_start, node.byte_end, true)
                    return result
                }
            } else {
                fail(&result, .Unsupported_Expression, node.byte_start, node.byte_end, true)
                return result
            }
            inferred[i]=kind
            if kind == .Union {
                // Only a bound Name or parentheses can carry a union through
                // this deliberately bounded expression grammar. Other
                // operations remain unsupported, never guessed.
                if node.kind == .Group {
                    expression_ids[i] = expression_ids[node.left]
                } else if node.kind != .Name {
                    fail(&result, .Unsupported_Expression,
                         node.byte_start, node.byte_end, true)
                    return result
                }
                if typecore.kind_of(&pool, expression_ids[i]) != .Union {
                    fail(&result, .Invalid_Input, node.byte_start, node.byte_end, true)
                    return result
                }
            } else if union_file {
                expression_ids[i] = primitive_type_id(kind)
            }
            // The contextual fact is scoped to the RHS subtree only.
            // Branch entry snapshots must see the original pre-condition state.
            if i == rhs_context_end {
                literal_decls[rhs_context_guard] = rhs_saved_fact
                wide_decls[rhs_context_guard] = rhs_saved_wide
            }
        }
        expression_type := inferred[expression_root]
        // The postorder condition still needs this expression's first node.
        // node_cursor advances for the NEXT statement before guard matching.
        expression_begin := node_cursor
        node_cursor = expression_root + 1
        if condition_event {
            if expression_type != .Boolean {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
            // Only pure syntax nodes are available in conditions. Both
            // operands of &&/|| are checked independently (not evaluated as
            // mutations); TypeScript's short circuit controls WHICH arm may
            // infer facts, not whether this parser binds an operand.
            guard_unwrapped := unwrap_guard_wrappers(
                syntax.nodes[:], expression_root, expression_begin)
            if !guard_unwrapped.valid {
                fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                return result
            }
            guard_node := guard_unwrapped.index
            flipped := guard_unwrapped.flipped
            root := syntax.nodes[guard_node]
            // M4-G5F8W2: exact typeof Name === "number"/"string"/"boolean"
            // on a mutable union. General Boolean/compound guards retain the
            // existing proof path; no speculative union facts escape.
            if union_file && root.kind == .Binary &&
               (root.operator == .Equals_Equals_Equals ||
                root.operator == .Exclamation_Equals_Equals) &&
               root.left >= expression_begin && root.left < guard_node &&
               root.right > root.left && root.right < guard_node {
                lhs := syntax.nodes[root.left]
                rhs := syntax.nodes[root.right]
                if lhs.kind == .Unary && lhs.operator == .Typeof_Keyword &&
                   lhs.left >= expression_begin && lhs.left < root.left &&
                   syntax.nodes[lhs.left].kind == .Name &&
                   rhs.kind == .Text && rhs.byte_end-rhs.byte_start >= 2 {
                    inner_name := lhs.left
                    ref := references[inner_name]
                    if ref > 0 && ref <= len(symbols.symbols) {
                        symbol := symbols.symbols[ref-1]
                        guard := symbol.declaration_index
                        if symbol.kind == .Let && guard >= 0 &&
                           guard < result.checked_declarations &&
                           declared[guard] == .Union {
                            spelling := text[rhs.byte_start+1:rhs.byte_end-1]
                            primitive_id := typecore.Invalid
                            if spelling == "number" { primitive_id = typecore.Number
                            } else if spelling == "string" { primitive_id = typecore.Text
                            } else if spelling == "boolean" { primitive_id = typecore.Boolean }
                            if primitive_id != typecore.Invalid {
                                yes, no, ok := typecore.split_typeof(
                                    &pool, flow_ids[guard], primitive_id)
                                // A never arm requires explicit reachability
                                // modeling, which this small CFG does not have.
                                if ok && yes != typecore.Never &&
                                   no != typecore.Never {
                                    true_id := yes
                                    false_id := no
                                    if (root.operator == .Exclamation_Equals_Equals) != flipped {
                                        true_id, false_id = false_id, true_id
                                    }
                                    level := flow_depth
                                    if len(entry_literals[level]) == 0 {
                                        entry_literals[level] = make([]Literal_Fact, len(declared))
                                        then_literals[level] = make([]Literal_Fact, len(declared))
                                        entry_wide[level] = make([]bool, len(declared))
                                        then_wide[level] = make([]bool, len(declared))
                                    }
                                    if len(entry_ids[level]) == 0 {
                                        entry_ids[level] = make([]typecore.Type_Id, len(declared))
                                        then_ids[level] = make([]typecore.Type_Id, len(declared))
                                    }
                                    copy(entry_literals[level], literal_decls)
                                    copy(entry_wide[level], wide_decls)
                                    copy(entry_ids[level], flow_ids)
                                    flow_ids[guard] = true_id
                                    typeof_guard[level] = guard
                                    typeof_else_id[level] = false_id
                                    guard_count[level] = 0
                                    dead_then[level] = false
                                    dead_else[level] = false
                                    contradiction_guard[level] = -1
                                    else_seen[level] = false
                                    flow_depth += 1
                                    continue
                                }
                            }
                        }
                    }
                }
            }
            compound := root.kind == .Binary &&
                        (root.operator == .Ampersand_Ampersand ||
                         root.operator == .Bar_Bar)
            part_count := 1
            part_nodes: [3]int
            part_nodes[0] = guard_node
            if compound {
                if root.left < 0 || root.left >= guard_node ||
                   root.right < 0 || root.right >= guard_node {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                part_count = 2
                part_nodes[0] = root.left
                part_nodes[1] = root.right
                // Parser precedence is left-associative. Support precisely
                // (a && b) && c or (a || b) || c, not arbitrary formulae.
                // Only independent bare Boolean names (possibly !/groups)
                // can form a three-part chain. This keeps RHS conditional
                // semantics free of disjoint comparison diagnostics.
                inner := syntax.nodes[root.left]
                if inner.kind == .Binary && inner.operator == root.operator {
                    if inner.left < 0 || inner.left >= root.left ||
                       inner.right <= inner.left || inner.right >= root.left {
                        fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                        return result
                    }
                    part_count = 3
                    part_nodes[0] = inner.left
                    part_nodes[1] = inner.right
                    part_nodes[2] = root.right
                }
                // M4-G5F7A: exactly a && (b || c), or a || (b && c).
                // In the decisive arm only 'a' is certain; neither 'b'
                // nor 'c' can be narrowed individually. Inner operands
                // must be independent, proven-wide Boolean names with no
                // potential side effects or equality diagnostics.
                if part_count == 2 && syntax.nodes[root.left].kind == .Name {
                    right_idx := root.right
                    right_wrap := syntax.nodes[right_idx]
                    if right_wrap.kind == .Group &&
                       right_wrap.left > root.left &&
                       right_wrap.left < right_idx {
                        right_idx = right_wrap.left
                    }
                    rhs_inner := syntax.nodes[right_idx]
                    if rhs_inner.kind == .Binary &&
                       ((rhs_inner.operator == .Ampersand_Ampersand &&
                         root.operator == .Bar_Bar) ||
                        (rhs_inner.operator == .Bar_Bar &&
                         root.operator == .Ampersand_Ampersand)) {
                        if rhs_inner.left <= root.left ||
                           rhs_inner.right <= rhs_inner.left ||
                           rhs_inner.right >= right_idx ||
                           syntax.nodes[rhs_inner.left].kind != .Name ||
                           syntax.nodes[rhs_inner.right].kind != .Name {
                            fail(&result, .Unsupported_Condition,
                                 event.byte_start, event.byte_end, true)
                            return result
                        }
                        if !#force_inline three_distinct_wide_boolean_lets(
                            syntax.nodes[:],
                            [3]int{root.left, rhs_inner.left, rhs_inner.right},
                            references, symbols.symbols[:], declared, wide_decls,
                            result.checked_declarations) {
                            fail(&result, .Unsupported_Condition,
                                 event.byte_start, event.byte_end, true)
                            return result
                        }
                        // The outer left predicate is the ONLY branch fact.
                        part_count = 1
                    }
                }

                // M4-G5F7B: explicitly grouped left-nested mixed formulas.
                // (a && b) || c proves only c=false on the false arm;
                // (a || b) && c proves only c=true on the true arm.
                // Outer ! swaps arms, never the value of c.
                if part_count == 2 && syntax.nodes[root.left].kind == .Group &&
                   syntax.nodes[root.right].kind == .Name {
                    left_group := syntax.nodes[root.left]
                    if left_group.left >= 0 && left_group.left < root.left {
                        inner_idx := left_group.left
                        inner := syntax.nodes[inner_idx]
                        if inner.kind == .Binary &&
                           ((inner.operator == .Ampersand_Ampersand &&
                             root.operator == .Bar_Bar) ||
                            (inner.operator == .Bar_Bar &&
                             root.operator == .Ampersand_Ampersand)) {
                            if inner.left < 0 || inner.right <= inner.left ||
                               inner.right >= inner_idx || root.right <= root.left ||
                               syntax.nodes[inner.left].kind != .Name ||
                               syntax.nodes[inner.right].kind != .Name {
                                fail(&result, .Unsupported_Condition,
                                     event.byte_start, event.byte_end, true)
                                return result
                            }
                            if !#force_inline three_distinct_wide_boolean_lets(
                                syntax.nodes[:],
                                [3]int{inner.left, inner.right, root.right},
                                references, symbols.symbols[:], declared, wide_decls,
                                result.checked_declarations) {
                                fail(&result, .Unsupported_Condition,
                                     event.byte_start, event.byte_end, true)
                                return result
                            }
                            // One existing compound-guard slot holds the only
                            // entailed predicate. Never invent facts for a/b.
                            part_count = 1
                            part_nodes[0] = root.right
                        }
                    }
                }

                // M4-G5F8M: a pure (possibly negated/grouped) Boolean
                // name AND true, or OR false, is the SAME guard on both
                // arms. Match only direct literal identities and a chain
                // of ! / parentheses around one Name, never computed
                // expressions, other operands or arbitrary truthiness.
                // The existing one-leaf walker owns negation parity.
                if part_count == 2 {
                    name_expr := -1
                    literal_idx := -1
                    if syntax.nodes[root.right].kind == .Boolean {
                        name_expr = root.left
                        literal_idx = root.right
                    } else if syntax.nodes[root.left].kind == .Boolean {
                        name_expr = root.right
                        literal_idx = root.left
                    }
                    if name_expr >= 0 {
                        fact := literal_fact_from_node(syntax.nodes[literal_idx])
                        value, known := boolean_fact_value(fact, text)
                        if known &&
                           ((root.operator == .Ampersand_Ampersand && value) ||
                            (root.operator == .Bar_Bar && !value)) {
                            name_unwrapped := unwrap_guard_wrappers(
                                syntax.nodes[:], name_expr, expression_begin)
                            if name_unwrapped.valid &&
                               syntax.nodes[name_unwrapped.index].kind == .Name {
                                part_count = 1
                                part_nodes[0] = name_expr
                                compound = false
                            }
                        }
                    }
                }
            }
            level := flow_depth
            // Do not carry metadata from an earlier conditional at this depth.
            guard_count[level] = 0
            leaf_then: [3]Literal_Fact
            leaf_else: [3]Literal_Fact
            leaf_is_bare_boolean: [3]bool
            contradiction := false
            dead_then[level] = false
            dead_else[level] = false
            contradiction_guard[level] = -1
            for slot in 0..<part_count {
                leaf_unwrapped := unwrap_guard_wrappers(
                    syntax.nodes[:], part_nodes[slot], expression_begin)
                if !leaf_unwrapped.valid {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                leaf_node := leaf_unwrapped.index
                leaf_flipped := (!compound && flipped) != leaf_unwrapped.flipped
                leaf := syntax.nodes[leaf_node]
                if part_count == 3 && leaf.kind != .Name {
                    // No comparisons or computed operators on RHS of a
                    // three-way chain until contextual evaluation is proven.
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                guard_ref := -1
                then_fact: Literal_Fact
                else_fact: Literal_Fact
                if leaf.kind == .Name {
                    guard_ref = references[leaf_node]
                    then_fact = branch_boolean_fact(!leaf_flipped)
                    else_fact = branch_boolean_fact(leaf_flipped)
                } else if leaf.kind == .Binary &&
                          (leaf.operator == .Equals_Equals_Equals ||
                           leaf.operator == .Exclamation_Equals_Equals) &&
                          leaf.left >= 0 && leaf.right >= 0 {
                    lhs := syntax.nodes[leaf.left]
                    rhs := syntax.nodes[leaf.right]
                    if lhs.kind != .Name {
                        fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                        return result
                    }
                    guard_ref = references[leaf.left]
                    fact := literal_fact_from_node(rhs)
                    negative := (leaf.operator == .Exclamation_Equals_Equals) != leaf_flipped
                    if rhs.kind == .Boolean {
                        value, valid := boolean_fact_value(fact, text)
                        if !valid {
                            fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                            return result
                        }
                        opposite := branch_boolean_fact(!value)
                        if negative {
                            then_fact = opposite
                            else_fact = fact
                        } else {
                            then_fact = fact
                            else_fact = opposite
                        }
                    } else if negative {
                        else_fact = fact
                    } else {
                        then_fact = fact
                    }
                } else {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                if guard_ref <= 0 || guard_ref > len(symbols.symbols) {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                symbol := symbols.symbols[guard_ref-1]
                guard := symbol.declaration_index
                if symbol.kind != .Let || guard < 0 || guard >= result.checked_declarations ||
                   !wide_decls[guard] {
                    fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                    return result
                }
                if leaf.kind == .Name {
                    if declared[guard] != .Boolean {
                        fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                        return result
                    }
                } else {
                    rhs := syntax.nodes[leaf.right]
                    if !((declared[guard] == .Number && rhs.kind == .Integer) ||
                         (declared[guard] == .Text && rhs.kind == .Text) ||
                         (declared[guard] == .Boolean && rhs.kind == .Boolean)) {
                        fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                        return result
                    }
                }
                leaf_then[slot] = then_fact
                leaf_else[slot] = else_fact
                leaf_is_bare_boolean[slot] = leaf.kind == .Name &&
                                             declared[guard] == .Boolean
                // Three-way chains require distinct bindings, even in
                // non-decisive arms; do not generalize idempotent predicates
                // without explicit multi-path intersection semantics.
                if part_count == 3 {
                    for prior in 0..<slot {
                        if guard == guard_indices[level][prior] {
                            fail(&result, .Unsupported_Condition,
                                 event.byte_start, event.byte_end, true)
                            return result
                        }
                    }
                }
                // Two-way same-target predicates preserve G5F2/G5F3 logic.
                if part_count == 2 && slot > 0 &&
                   guard == guard_indices[level][0] {
                    first_fact := guard_then_facts[level][0]
                    if (root.operator == .Ampersand_Ampersand && flipped) ||
                       (root.operator == .Bar_Bar && !flipped) {
                        first_fact = guard_else_facts[level][0]
                    }
                    next_fact := then_fact
                    if root.operator == .Bar_Bar { next_fact = else_fact }
                    known, same := literal_overlap(first_fact, next_fact, text)
                    if known && !same && leaf_is_bare_boolean[0] &&
                       leaf_is_bare_boolean[1] {
                        // Opposite Boolean truth values on the same binding:
                        // AND can never be true; OR can never be false.
                        // Pure !name and name leaves do not introduce TS2367.
                        contradiction = true
                    } else if !known || !same {
                        fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                        return result
                    }
                }
                guard_indices[level][slot] = guard
                guard_then_facts[level][slot] = Literal_Fact{}
                guard_else_facts[level][slot] = Literal_Fact{}
                if !compound {
                    guard_then_facts[level][slot] = then_fact
                    guard_else_facts[level][slot] = else_fact
                } else if root.operator == .Ampersand_Ampersand {
                    // a && b proves BOTH predicates only when true.
                    if flipped {
                        guard_else_facts[level][slot] = then_fact
                    } else {
                        guard_then_facts[level][slot] = then_fact
                    }
                } else {
                    // a || b disproves BOTH predicates only when false.
                    if flipped {
                        guard_then_facts[level][slot] = else_fact
                    } else {
                        guard_else_facts[level][slot] = else_fact
                    }
                }
                guard_count[level] += 1
            }
            if compound && contradiction {
                if root.operator == .Ampersand_Ampersand {
                    if flipped { dead_else[level] = true
                    } else { dead_then[level] = true }
                } else {
                    if flipped { dead_then[level] = true
                    } else { dead_else[level] = true }
                }
                // Preserve the contradiction's identity for dead-arm target
                // rejection, even though no singleton flow fact may escape.
                contradiction_guard[level] = guard_indices[level][0]
                guard_count[level] = 0
            } else if compound && part_count == 2 &&
                      guard_indices[level][0] == guard_indices[level][1] {
                // Same Boolean predicate on both sides is idempotent:
                // a&&a and a||a each prove a on BOTH output arms.
                // Never deduce the complement for open number/string domains.
                t_known, t_same := literal_overlap(leaf_then[0], leaf_then[1], text)
                f_known, f_same := literal_overlap(leaf_else[0], leaf_else[1], text)
                if declared[guard_indices[level][0]] == .Boolean &&
                   t_known && t_same && f_known && f_same {
                    if root.operator == .Ampersand_Ampersand {
                        if flipped {
                            guard_then_facts[level][0] = leaf_else[0]
                        } else {
                            guard_else_facts[level][0] = leaf_else[0]
                        }
                    } else {
                        if flipped {
                            guard_else_facts[level][0] = leaf_then[0]
                        } else {
                            guard_then_facts[level][0] = leaf_then[0]
                        }
                    }
                }
                // One declaration slot, not two competing mutations.
                guard_count[level] = 1
            }
            if len(entry_literals[level]) == 0 {
                entry_literals[level] = make([]Literal_Fact, len(declared))
                then_literals[level] = make([]Literal_Fact, len(declared))
                entry_wide[level] = make([]bool, len(declared))
                then_wide[level] = make([]bool, len(declared))
            }
            copy(entry_literals[level], literal_decls)
            copy(entry_wide[level], wide_decls)
            if union_file {
                if len(entry_ids[level]) == 0 {
                    entry_ids[level] = make([]typecore.Type_Id, len(declared))
                    then_ids[level] = make([]typecore.Type_Id, len(declared))
                }
                copy(entry_ids[level], flow_ids)
                typeof_guard[level] = -1
            }
            for slot in 0..<guard_count[level] {
                if guard_then_facts[level][slot].kind != .Name {
                    literal_decls[guard_indices[level][slot]] = guard_then_facts[level][slot]
                    wide_decls[guard_indices[level][slot]] = false
                }
            }
            else_seen[level] = false
            flow_depth += 1
            continue
        }
        if assignment {
            result.checked_assignments += 1
            compatible := expression_type == declared_type
            if expression_type == .Union || declared_type == .Union {
                supported: bool
                compatible, supported = typecore.assignable(
                    &pool, expression_ids[expression_root], declared_id)
                if !supported {
                    fail(&result, .Unsupported_Expression,
                         event.byte_start, event.byte_end, true)
                    return result
                }
            } else {
                record_relation(&result, trace_mode, expression_type, declared_type,
                                expression_root, target_index, .Assignment, compatible)
            }
            if !compatible {
                // Native TS7 starts TS2322 at the assignment target;
                // supplemental TS6 structured diagnostics cover precisely
                // the target identifier, not the entire RHS expression.
                target := syntax.nodes[event.target_node]
                fail(&result, .Assignment_Type_Mismatch,
                     target.byte_start, target.byte_end, false)
                if !dead_assignment {
                    literal_decls[target_index] = Literal_Fact{}
                    wide_decls[target_index] = false
                }
            } else if !dead_assignment {
                // This is the first linear flow transfer. Reassignment
                // replaces the earlier narrowed fact; nothing persists
                // across unsupported branches or mutation paths.
                if declared_type == .Union {
                    // Assignment invalidates any previous typeof narrowing.
                    if union_file {
                        flow_ids[target_index] = expression_ids[expression_root]
                    }
                    literal_decls[target_index] = Literal_Fact{}
                    wide_decls[target_index] = true
                } else if declared_type == .Number || declared_type == .Text {
                    // A mutable number/string retains its widened base domain:
                    // assigning a literal does not make it a singleton type.
                    literal_decls[target_index] = Literal_Fact{}
                    wide_decls[target_index] = true
                } else {
                    // Boolean flow is deliberately a separate restricted case.
                    literal_decls[target_index] = literal_nodes[expression_root]
                    wide_decls[target_index] = wide_nodes[expression_root]
                }
            }
        } else {
            if declared_type != .Unknown {
                compatible := expression_type == declared_type
                if expression_type == .Union || declared_type == .Union {
                    supported: bool
                    compatible, supported = typecore.assignable(
                        &pool, expression_ids[expression_root], declared_id)
                    if !supported {
                        fail(&result, .Unsupported_Expression,
                             event.byte_start, event.byte_end, true)
                        return result
                    }
                } else {
                    record_relation(&result, trace_mode, expression_type, declared_type,
                                    expression_root, declaration_index, .Variable, compatible)
                }
                if !compatible {
                    // TS7 anchors declaration type mismatches at the name.
                    fail(&result, .Assignment_Type_Mismatch,
                         decl.name_start, decl.name_end, false)
                }
            }
            declared[declaration_index] = declared_type
            if union_file { declared_ids[declaration_index] = declared_id }
            if declared_type == .Unknown {
                declared[declaration_index] = expression_type
                if union_file {
                    declared_ids[declaration_index] = expression_ids[expression_root]
                }
            }
            if union_file {
                // A declared union starts with the initializer's proven type.
                // An invalid initializer cannot be considered successful.
                flow_ids[declaration_index] = expression_ids[expression_root]
            }
            if declared[declaration_index] == .Union {
                // A general union has no single literal fact in this slice.
                literal_decls[declaration_index] = Literal_Fact{}
                wide_decls[declaration_index] = true
            } else if expression_type == declared[declaration_index] {
                if decl.kind == .Const && declared_type == .Unknown {
                    // An unannotated const keeps its inferred literal type,
                    // including immutable aliases and computed-wide results.
                    literal_decls[declaration_index] = literal_nodes[expression_root]
                    wide_decls[declaration_index] = wide_nodes[expression_root]
                } else if expression_type == .Number || expression_type == .Text {
                    // COMPAT: fresh literals widen at mutable locations;
                    // explicit primitive annotations are declared-wide even
                    // for const. Neither is a singleton equality operand.
                    wide_decls[declaration_index] = true
                } else if expression_type == .Boolean {
                    // COMPAT: an initialized Boolean can still have a
                    // singleton *flow type* despite its wide annotation.
                    // Assignment and branch joins replace/merge this fact.
                    literal_decls[declaration_index] = literal_nodes[expression_root]
                    wide_decls[declaration_index] = wide_nodes[expression_root]
                }
            }
            result.checked_declarations += 1
        }
    }
    if flow_depth != 0 {
        fail(&result, .Unsupported_Condition, 0, 0, true)
        return result
    }
    if node_cursor != len(syntax.nodes) {
        fail(&result, .Invalid_Expression_Node, 0, 0, true)
        return result
    }
    result.complete = !result.fatal && len(result.diagnostics)==0
    return result
}

// Production/default path retains the original no-trace allocation behavior.
check_file :: proc(
    version: ^source.Source_Version,
    syntax: ^parser.Syntax_Report,
    symbols: ^binder.Binding_Report,
) -> Report {
    return check_file_with_relations(version, syntax, symbols, .None)
}
