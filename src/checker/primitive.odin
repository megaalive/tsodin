package checker

import "../binder"
import "../parser"
import "../scanner"
import "../source"

// M4-A: a deliberately restricted, one-file semantic slice.
// All issue kinds are INTERNAL; none are TypeScript diagnostic codes.
Primitive :: enum {
    Unknown,
    Number,
    Text,
    Boolean,
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
    defer {
        for level in 0..<parser.FLOW_NEST_LIMIT {
            delete(entry_literals[level])
            delete(then_literals[level])
            delete(entry_wide[level])
            delete(then_wide[level])
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
            if decl.initializer < 0 {
                if declared_type == .Unknown {
                    fail(&result, .Unsupported_Implicit_Any,
                         decl.name_start, decl.name_end, true)
                    return result
                }
                declared[declaration_index] = declared_type
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
            root_idx := expression_root
            for {
                outer := syntax.nodes[root_idx]
                if outer.kind != .Group &&
                   !(outer.kind == .Unary && outer.operator == .Exclamation) {
                    break
                }
                if outer.left < node_cursor || outer.left >= root_idx { break }
                root_idx = outer.left
            }
            logical := syntax.nodes[root_idx]
            if logical.kind == .Binary &&
               (logical.operator == .Ampersand_Ampersand ||
                logical.operator == .Bar_Bar) &&
               logical.left >= node_cursor && logical.left < logical.right &&
               logical.right < root_idx {
                lhs_idx := logical.left
                lhs_flipped := false
                for {
                    lhs := syntax.nodes[lhs_idx]
                    if lhs.kind != .Group &&
                       !(lhs.kind == .Unary && lhs.operator == .Exclamation) {
                        break
                    }
                    if lhs.left < node_cursor || lhs.left >= lhs_idx { break }
                    if lhs.kind == .Unary { lhs_flipped = !lhs_flipped }
                    lhs_idx = lhs.left
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
                // Only inferred const declarations retain the literal type.
                // An explicit annotation widens it; let/var flow is untracked.
                literal_nodes[i] = literal_decls[symbol.declaration_index]
                wide_nodes[i] = wide_decls[symbol.declaration_index]
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
                    if node.operator == .Exclamation && child == .Boolean {
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
                           node.operator == .Slash) &&
                          left == .Number && right == .Number {
                    kind = .Number
                }
                // Basic arithmetic and plain concatenation produce a base
                // primitive, not an inferred literal type. Keep this fact
                // independent of the operands' known literal identities.
                if kind != .Unknown && (node.operator == .Plus ||
                   node.operator == .Minus || node.operator == .Asterisk ||
                   node.operator == .Slash) {
                    wide_nodes[i] = true
                }
                if (node.operator == .Less_Than || node.operator == .Greater_Than ||
                    node.operator == .Less_Than_Equals || node.operator == .Greater_Than_Equals) &&
                   left == .Number && right == .Number {
                    kind = .Boolean
                    wide_nodes[i] = true
                } else if (node.operator == .Ampersand_Ampersand || node.operator == .Bar_Bar) &&
                          left == .Boolean && right == .Boolean {
                    // Logical operators return operand values in TypeScript.
                    // Restrict to boolean-only cases until truthiness is modeled.
                    kind = .Boolean
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
            // The contextual fact is scoped to the RHS subtree only.
            // Branch entry snapshots must see the original pre-condition state.
            if i == rhs_context_end {
                literal_decls[rhs_context_guard] = rhs_saved_fact
                wide_decls[rhs_context_guard] = rhs_saved_wide
            }
        }
        expression_type := inferred[expression_root]
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
            guard_node := expression_root
            flipped := false
            for {
                node := syntax.nodes[guard_node]
                if node.kind == .Group ||
                   (node.kind == .Unary && node.operator == .Exclamation) {
                    if node.left < 0 || node.left >= guard_node {
                        fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                        return result
                    }
                    if node.kind == .Unary { flipped = !flipped }
                    guard_node = node.left
                } else {
                    break
                }
            }
            root := syntax.nodes[guard_node]
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
                        lhs_ref := references[root.left]
                        first_ref := references[rhs_inner.left]
                        second_ref := references[rhs_inner.right]
                        if lhs_ref <= 0 || first_ref <= 0 || second_ref <= 0 ||
                           lhs_ref > len(symbols.symbols) ||
                           first_ref > len(symbols.symbols) ||
                           second_ref > len(symbols.symbols) {
                            fail(&result, .Unsupported_Condition,
                                 event.byte_start, event.byte_end, true)
                            return result
                        }
                        lhs := symbols.symbols[lhs_ref-1]
                        first := symbols.symbols[first_ref-1]
                        second := symbols.symbols[second_ref-1]
                        a := lhs.declaration_index
                        b := first.declaration_index
                        d := second.declaration_index
                        if lhs.kind != .Let || first.kind != .Let ||
                           second.kind != .Let ||
                           a < 0 || b < 0 || d < 0 ||
                           a >= result.checked_declarations ||
                           b >= result.checked_declarations ||
                           d >= result.checked_declarations ||
                           a == b || a == d || b == d ||
                           declared[a] != .Boolean ||
                           declared[b] != .Boolean ||
                           declared[d] != .Boolean ||
                           !wide_decls[a] || !wide_decls[b] || !wide_decls[d] {
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
                            first_ref := references[inner.left]
                            second_ref := references[inner.right]
                            right_ref := references[root.right]
                            if first_ref <= 0 || second_ref <= 0 || right_ref <= 0 ||
                               first_ref > len(symbols.symbols) ||
                               second_ref > len(symbols.symbols) ||
                               right_ref > len(symbols.symbols) {
                                fail(&result, .Unsupported_Condition,
                                     event.byte_start, event.byte_end, true)
                                return result
                            }
                            first := symbols.symbols[first_ref-1]
                            second := symbols.symbols[second_ref-1]
                            right := symbols.symbols[right_ref-1]
                            a := first.declaration_index
                            b := second.declaration_index
                            c := right.declaration_index
                            if first.kind != .Let || second.kind != .Let ||
                               right.kind != .Let ||
                               a < 0 || b < 0 || c < 0 ||
                               a >= result.checked_declarations ||
                               b >= result.checked_declarations ||
                               c >= result.checked_declarations ||
                               a == b || a == c || b == c ||
                               declared[a] != .Boolean ||
                               declared[b] != .Boolean ||
                               declared[c] != .Boolean ||
                               !wide_decls[a] || !wide_decls[b] || !wide_decls[c] {
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
                leaf_node := part_nodes[slot]
                leaf_flipped := !compound && flipped
                for {
                    node := syntax.nodes[leaf_node]
                    if node.kind == .Group ||
                       (node.kind == .Unary && node.operator == .Exclamation) {
                        if node.left < 0 || node.left >= leaf_node {
                            fail(&result, .Unsupported_Condition, event.byte_start, event.byte_end, true)
                            return result
                        }
                        if node.kind == .Unary { leaf_flipped = !leaf_flipped }
                        leaf_node = node.left
                    } else {
                        break
                    }
                }
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
            record_relation(&result, trace_mode, expression_type, declared_type,
                            expression_root, target_index, .Assignment, compatible)
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
                if declared_type == .Number || declared_type == .Text {
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
                record_relation(&result, trace_mode, expression_type, declared_type,
                                expression_root, declaration_index, .Variable, compatible)
                if !compatible {
                    // TS7 anchors declaration type mismatches at the name.
                    fail(&result, .Assignment_Type_Mismatch,
                         decl.name_start, decl.name_end, false)
                }
            }
            declared[declaration_index] = declared_type
            if declared_type == .Unknown {
                declared[declaration_index] = expression_type
                if decl.kind == .Const {
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
