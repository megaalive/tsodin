package dump

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "../source"
import "../scanner"
import "../parser"
import "../binder"
import "../checker"
import "../compat"

// M4-G5F8A: a developer-readable projection of REAL stage reports.
// This is not a TypeScript AST serializer, full type graph or public check.
// Array indices remain identical to the source-owned Odin arena indices.
Span :: [2]int
Unit_Span :: [2]u32

Diagnostic :: struct {
    issue_id: int,
    bytes: Span,
    utf16: Unit_Span,
}

Token :: struct {
    kind: scanner.Token_Kind,
    bytes: Span,
    utf16: Unit_Span,
}

Node :: struct {
    kind: parser.Expr_Kind,
    operator: scanner.Token_Kind,
    bytes: Span,
    utf16: Unit_Span,
    tokens: [2]int, // inclusive scanner token IDs; [-1,-1] when none
    left: int,      // parser postorder arena index, -1 means absent
    right: int,
}

Symbol :: struct {
    name: string, // borrowed slice of Source_Version.owned_text
    kind: parser.Declaration_Kind,
    declaration: int,
    declarations: int,
}

Scope :: struct {
    kind: string,
    parent: int, // -1 indicates root, NOT a claim about TS lexical scopes
}

Token_Stage :: struct {
    status: string,
    outcome: string,
    tokens: []Token,
    diagnostics: []Diagnostic,
    issue_namespace: string,
}

Ast_Stage :: struct {
    status: string,
    outcome: string,
    nodes: []Node,
    declarations: []parser.Expr_Declaration,
    statements: []parser.Expr_Statement,
    diagnostics: []Diagnostic,
    issue_namespace: string,
    model: string,
}

Symbol_Stage :: struct {
    status: string,
    outcome: string,
    scopes: []Scope,
    symbols: []Symbol,
    references: []binder.Reference,
    diagnostics: []Diagnostic,
    issue_namespace: string,
    lookup_status: string,
}

Relation :: struct {
    source: checker.Primitive,
    target: checker.Primitive,
    node_index: int,
    declaration_index: int,
    relation_kind: checker.Relation_Context,
    result: bool,
    bytes: Span, // source expression, never a guessed TS diagnostic anchor
    utf16: Unit_Span,
}

Type_Stage :: struct {
    status: string,
    outcome: string,
    checked_declarations: int,
    checked_assignments: int,
    diagnostics: []Diagnostic,
    relations: []Relation,
    trace_mode: string,
    issue_namespace: string,
    node_types_status: string,
    relations_status: string,
}

Source :: struct {
    name: string,
    text: string,
    bytes: int,
    utf16: u32,
}

Stages :: struct {
    tokens: Token_Stage,
    ast: Ast_Stage,
    symbols: Symbol_Stage,
    types: Type_Stage,
}

Document :: struct {
    schema: string,
    profile: string,
    source: Source,
    stages: Stages,
}

// Exact snapshot conversion. Reject forged/non-scalar byte boundaries.
unit_span :: proc(v: ^source.Source_Version, start, end: int) -> (Unit_Span, bool) {
    a, ok_a := source.source_position(v, start)
    b, ok_b := source.source_position(v, end)
    if !ok_a || !ok_b || start > end {
        return Unit_Span{}, false
    }
    return Unit_Span{a.absolute_utf16, b.absolute_utf16}, true
}

diagnostic :: proc(v: ^source.Source_Version, id, start, end: int) -> (Diagnostic, bool) {
    units, ok := unit_span(v, start, end)
    if !ok { return Diagnostic{}, false }
    return Diagnostic{issue_id=id, bytes=Span{start,end}, utf16=units}, true
}

// No timestamps, no labels/colors and no fabricated TypeScript diagnostics.
// Unsupported parsing/binding/checking is represented as an outcome, not a
// successful check. Does not mutate any of the stage reports.
write :: proc(filename: string, trace_all: bool) -> bool {
    bytes, file_error := os.read_entire_file(filename, context.allocator)
    if file_error != nil { fmt.eprintln("error: source file unavailable"); return false }
    defer delete(bytes)
    version, valid := source.source_version_create(source.File_Id(1), 1, transmute(string)bytes)
    if !valid { fmt.eprintln("error: source file is not valid UTF-8"); return false }
    defer source.source_version_destroy(&version)

    output := Document {
        schema="tsodin.dump/2",
        profile="ts7",
        source=Source{
            name=filename, text=version.owned_text,
            bytes=len(version.owned_text), utf16=version.total_utf16,
        },
    }

    tokens := make([dynamic]Token)
    defer delete(tokens)
    lexical_issues := make([dynamic]Diagnostic)
    defer delete(lexical_issues)
    lexical_complete := true
    lexer := scanner.scanner_init(&version)
    for {
        token := scanner.scanner_next(&lexer)
        mapped, ok := unit_span(&version, token.byte_start, token.byte_end)
        if !ok { fmt.eprintln("error: invalid token position"); return false }
        append(&tokens, Token{
            kind=token.kind,
            bytes=Span{token.byte_start,token.byte_end}, utf16=mapped,
        })
        if token.kind == .Invalid || token.error != .None {
            issue, ok_issue := diagnostic(&version, int(token.error),
                                           token.byte_start, token.byte_end)
            if !ok_issue { return false }
            append(&lexical_issues, issue)
            lexical_complete = false
            break
        }
        if token.kind == .End_Of_File { break }
    }
    output.stages.tokens = Token_Stage{
        status="partial", outcome=lexical_complete ? "complete" : "unsupported",
        tokens=tokens[:], diagnostics=lexical_issues[:],
        issue_namespace="tsodin.scanner.Scan_Error",
    }

    syntax := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&syntax)
    nodes := make([dynamic]Node)
    defer delete(nodes)
    syntax_issues := make([dynamic]Diagnostic)
    defer delete(syntax_issues)
    // Tokens are in source order with non-overlapping spans. Exclude the
    // terminal EOF/failure token from AST mappings, exactly as before.
    span_token_count := len(tokens)
    if span_token_count > 0 {
        tail := tokens[span_token_count-1].kind
        if tail == .End_Of_File || tail == .Invalid { span_token_count -= 1 }
    }
    for node in syntax.nodes {
        units, ok := unit_span(&version, node.byte_start, node.byte_end)
        if !ok { fmt.eprintln("error: invalid syntax node position"); return false }
        first, last := -1, -1
        // PERF: two monotone binary searches replace scanning every token
        // for every AST node. Retain the exact inclusive token-ID contract.
        low, high := 0, span_token_count
        for low < high {
            mid := low + (high-low)/2
            if tokens[mid].bytes[0] < node.byte_start {
                low = mid+1
            } else {
                high = mid
            }
        }
        if low < span_token_count && tokens[low].bytes[1] <= node.byte_end {
            first = low
            high = span_token_count
            for low < high {
                mid := low + (high-low)/2
                if tokens[mid].bytes[1] <= node.byte_end {
                    low = mid+1
                } else {
                    high = mid
                }
            }
            last = low-1
        }
        append(&nodes, Node{
            kind=node.kind, operator=node.operator,
            bytes=Span{node.byte_start,node.byte_end}, utf16=units,
            tokens=[2]int{first,last},left=node.left,right=node.right,
        })
    }
    for issue in syntax.diagnostics {
        d, ok := diagnostic(&version, int(issue.issue), issue.byte_start, issue.byte_end)
        if !ok { fmt.eprintln("error: invalid syntax diagnostic"); return false }
        append(&syntax_issues, d)
    }
    output.stages.ast = Ast_Stage{
        status="partial", outcome=syntax.complete ? "complete" : "unsupported",
        nodes=nodes[:], declarations=syntax.declarations[:],
        statements=syntax.statements[:], diagnostics=syntax_issues[:],
        issue_namespace="tsodin.parser.Syntax_Issue",
        model="postorder_expression_nodes_and_statement_events",
    }

    binding := binder.bind_program(&version, &syntax)
    defer binder.binding_report_destroy(&binding)
    symbols := make([dynamic]Symbol)
    defer delete(symbols)
    scopes := make([dynamic]Scope)
    defer delete(scopes)
    binding_issues := make([dynamic]Diagnostic)
    defer delete(binding_issues)
    if syntax.complete { append(&scopes, Scope{kind="file", parent=-1}) }
    for symbol in binding.symbols {
        append(&symbols, Symbol{
            name=version.owned_text[symbol.name_start:symbol.name_end],
            kind=symbol.kind, declaration=symbol.declaration_index,
            declarations=symbol.declaration_count,
        })
    }
    for issue in binding.issues {
        d, ok := diagnostic(&version, int(issue.kind), issue.byte_start, issue.byte_end)
        if !ok { fmt.eprintln("error: invalid binding diagnostic"); return false }
        append(&binding_issues, d)
    }
    output.stages.symbols = Symbol_Stage{
        status="partial",outcome=binding.complete ? "complete" : "unsupported",
        scopes=scopes[:],symbols=symbols[:],references=binding.references[:],
        diagnostics=binding_issues[:],issue_namespace="tsodin.binder.Issue_Kind",
        lookup_status="not_implemented",
    }

    mode := checker.Relation_Trace_Mode.Failures
    if trace_all { mode = .All }
    checked := checker.check_file_with_relations(&version, &syntax, &binding, mode)
    defer checker.report_destroy(&checked)
    check_issues := make([dynamic]Diagnostic)
    defer delete(check_issues)
    relations := make([dynamic]Relation)
    defer delete(relations)
    for relation in checked.relations {
        if relation.node_index < 0 || relation.node_index >= len(syntax.nodes) ||
           relation.declaration_index < 0 ||
           relation.declaration_index >= len(syntax.declarations) {
            fmt.eprintln("error: invalid checker relation index")
            return false
        }
        node := syntax.nodes[relation.node_index]
        units, ok := unit_span(&version, node.byte_start, node.byte_end)
        if !ok {
            fmt.eprintln("error: invalid checker relation span")
            return false
        }
        append(&relations, Relation{
            source=relation.source, target=relation.target,
            node_index=relation.node_index,
            declaration_index=relation.declaration_index,
            relation_kind=relation.relation_kind, result=relation.result,
            bytes=Span{node.byte_start,node.byte_end}, utf16=units,
        })
    }
    for issue in checked.diagnostics {
        d, ok := diagnostic(&version, int(issue.issue), issue.byte_start, issue.byte_end)
        if !ok { fmt.eprintln("error: invalid checker diagnostic"); return false }
        append(&check_issues, d)
    }
    check_outcome := "diagnostics"
    if checked.fatal { check_outcome = "unsupported"
    } else if checked.complete { check_outcome = "complete" }
    output.stages.types = Type_Stage{
        status="partial",outcome=check_outcome,
        checked_declarations=checked.checked_declarations,
        checked_assignments=checked.checked_assignments,
        diagnostics=check_issues[:],relations=relations[:],
        trace_mode=trace_all ? "all" : "failures",
        issue_namespace="tsodin.checker.Check_Issue",
        node_types_status="not_implemented",relations_status="partial",
    }

    data, encode_error := json.marshal(output, {use_enum_names=true})
    if encode_error != nil { fmt.eprintln("error: JSON serialization failed"); return false }
    defer delete(data)
    fmt.printf("%s\n", transmute(string)data)
    return true
}
