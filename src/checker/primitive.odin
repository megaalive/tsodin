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
}

Diagnostic :: struct {
    issue: Check_Issue,
    byte_start: int,
    byte_end: int,
}

Report :: struct {
    file_id: source.File_Id,
    generation: u32,
    diagnostics: [dynamic]Diagnostic,
    checked_declarations: int,
    checked_assignments: int,
    complete: bool,
    fatal: bool,
}

report_destroy :: proc(r: ^Report) {
    delete(r.diagnostics)
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

// A value can carry a proven literal identity without allocating a new string.
// A default (.Name) kind means unknown: do not infer a literal merely from a
// primitive base type. The borrowed spans refer to the same source snapshot.
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

// Source-backed literal equality. Strings contain no escapes in this grammar;
// stripping either quote delimiter preserves the value. This does not handle
// computed expressions, widened annotations or mutable flow types.
literal_overlap :: proc(a, b: Literal_Fact, text: string) -> (both_literals, same_value: bool) {
    if a.kind != b.kind || a.kind == .Name { return false, false }
    if a.kind == .Integer || a.kind == .Boolean {
        return true, text[a.byte_start:a.byte_end] == text[b.byte_start:b.byte_end]
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

check_file :: proc(
    version: ^source.Source_Version,
    syntax: ^parser.Syntax_Report,
    symbols: ^binder.Binding_Report,
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
    for event in syntax.statements {
        assignment := event.kind == .Assignment
        // An assignment has no declaration index of its own. References in
        // its RHS may only see declarations already processed in source order.
        declaration_index := event.declaration_index
        if assignment {
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

        // The parser writes child nodes before their parent and appends each
        // declaration's expression nodes consecutively.
        for i in node_cursor..=expression_root {
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
                            // At least one operand is proven to have a broad
                            // base primitive type, which overlaps all values
                            // of the matching primitive domain.
                            kind = .Boolean
                        } else if both_literals {
                            fail(&result, .Disjoint_Literal_Comparison,
                                 node.byte_start, node.byte_end, false)
                            kind = .Boolean
                        }
                    }
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
        }
        expression_type := inferred[expression_root]
        node_cursor = expression_root + 1
        if assignment {
            result.checked_assignments += 1
            if expression_type != declared_type {
                // Unlike a declaration initializer, TS2322 on a simple
                // assignment points to its RHS expression.
                rhs := syntax.nodes[expression_root]
                fail(&result, .Assignment_Type_Mismatch,
                     rhs.byte_start, rhs.byte_end, false)
                literal_decls[target_index] = Literal_Fact{}
                wide_decls[target_index] = false
            } else {
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
            if declared_type != .Unknown && expression_type != declared_type {
                // TS7 anchors declaration type mismatches at the name.
                fail(&result, .Assignment_Type_Mismatch,
                     decl.name_start, decl.name_end, false)
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
    if node_cursor != len(syntax.nodes) {
        fail(&result, .Invalid_Expression_Node, 0, 0, true)
        return result
    }
    result.complete = !result.fatal && len(result.diagnostics)==0
    return result
}
