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

// Compare only directly source-backed primitive literals. Strings are scanned
// without escapes, so removing their quote delimiters is value-preserving.
// No heap allocations, literal inference claims, or speculative flow narrowing.
literal_overlap :: proc(a, b: parser.Expr_Node, text: string) -> (both_literals, same_value: bool) {
    if a.kind != b.kind { return false, false }
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

    // Only three temporary contiguous arrays; no heap allocation per AST node.
    inferred := make([]Primitive, len(syntax.nodes))
    defer delete(inferred)
    declared := make([]Primitive, len(syntax.declarations))
    defer delete(declared)
    references := make([]int, len(syntax.nodes))
    defer delete(references)

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
    for decl, declaration_index in syntax.declarations {
        if decl.name_start < 0 || decl.name_start >= decl.name_end ||
           decl.name_end > len(text) {
            fail(&result, .Invalid_Input, decl.byte_start, decl.byte_end, true)
            return result
        }
        declared_type := annotation_type(decl.type_kind)
        if decl.initializer < 0 {
            if declared_type == .Unknown {
                fail(&result, .Unsupported_Implicit_Any, decl.name_start, decl.name_end, true)
                return result
            }
            declared[declaration_index]=declared_type
            result.checked_declarations += 1
            continue
        }
        if decl.initializer < node_cursor || decl.initializer >= len(syntax.nodes) {
            fail(&result, .Invalid_Expression_Node, decl.byte_start, decl.byte_end, true)
            return result
        }

        // The parser writes child nodes before their parent and appends each
        // declaration's expression nodes consecutively.
        for i in node_cursor..=decl.initializer {
            node := syntax.nodes[i]
            if node.byte_start < 0 || node.byte_end > len(text) ||
               node.byte_start >= node.byte_end {
                fail(&result, .Invalid_Expression_Node, node.byte_start, node.byte_end, true)
                return result
            }

            kind := Primitive.Unknown
            if node.kind == .Integer {
                kind = .Number
            } else if node.kind == .Text {
                kind = .Text
            } else if node.kind == .Boolean {
                kind = .Boolean
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
                if (node.operator == .Less_Than || node.operator == .Greater_Than ||
                    node.operator == .Less_Than_Equals || node.operator == .Greater_Than_Equals) &&
                   left == .Number && right == .Number {
                    kind = .Boolean
                } else if (node.operator == .Ampersand_Ampersand || node.operator == .Bar_Bar) &&
                          left == .Boolean && right == .Boolean {
                    // Logical operators return operand values in TypeScript.
                    // Restrict to boolean-only cases until truthiness is modeled.
                    kind = .Boolean
                } else if (node.operator == .Equals_Equals_Equals ||
                           node.operator == .Exclamation_Equals_Equals) &&
                          left == right {
                    // Coarse primitive types lose literal/flow narrowing.
                    // Constant comparisons may emit TS2367.
                    lhs := syntax.nodes[node.left]
                    rhs := syntax.nodes[node.right]
                    same_name := lhs.kind == .Name && rhs.kind == .Name &&
                                 references[node.left] > 0 &&
                                 references[node.left] == references[node.right]
                    both_literals, same_value := literal_overlap(lhs, rhs, text)
                    if same_name || (both_literals && same_value) {
                        kind = .Boolean
                    } else if both_literals {
                        // Two distinct literal types have no overlap. This is
                        // recoverable TS2367-candidate evidence, not an unsupported
                        // operator; subsequent declarations are still checked.
                        fail(&result, .Disjoint_Literal_Comparison,
                             node.byte_start, node.byte_end, false)
                        kind = .Boolean
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
        expression_type := inferred[decl.initializer]
        node_cursor = decl.initializer+1
        if declared_type != .Unknown && expression_type != declared_type {
            // TS7 reports a variable-declaration type mismatch at the
            // declared name. Keep full name bytes for UTF-16 projection.
            fail(&result, .Assignment_Type_Mismatch,
                 decl.name_start, decl.name_end, false)
        }
        declared[declaration_index] = declared_type
        if declared_type == .Unknown {
            declared[declaration_index] = expression_type
        }
        result.checked_declarations += 1
    }
    if node_cursor != len(syntax.nodes) {
        fail(&result, .Invalid_Expression_Node, 0, 0, true)
        return result
    }
    result.complete = !result.fatal && len(result.diagnostics)==0
    return result
}
