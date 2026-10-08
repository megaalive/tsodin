package parser

import "core:testing"
import "../source"
import "../compat"
import "../scanner"

@(test)
expression_precedence_and_source_spans :: proc(t: ^testing.T) {
    text := "const sum: number = 1 + 2 * (3 - 4);\nlet scale = -sum / 2;\nvar label: string = 'ok';"
    version, valid := source.source_version_create(source.File_Id(401), 12, text)
    testing.expect(t, valid, "test source should be valid UTF-8")
    defer source.source_version_destroy(&version)
    report := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, report.complete && !report.fatal &&
                   len(report.diagnostics) == 0 && len(report.declarations) == 3,
                   "expression parser accepts full declared subset")
    testing.expect(t, report.file_id == version.file_id && report.generation == 12,
                   "snapshot identity is preserved without copied text")
    first := report.declarations[0]
    testing.expect(t, first.kind == .Const && first.type_kind == .Number &&
                   text[first.name_start:first.name_end] == "sum",
                   "first declaration name span")
    root := report.nodes[first.initializer]
    testing.expect(t, root.kind == .Binary && root.operator == .Plus,
                   "plus is top-level operator, not multiply")
    rhs := report.nodes[root.right]
    testing.expect(t, rhs.kind == .Binary && rhs.operator == .Asterisk,
                   "multiplication binds tighter")
    group := report.nodes[rhs.right]
    testing.expect(t, group.kind == .Group &&
                   report.nodes[group.left].operator == .Minus,
                   "parentheses override precedence")
    second := report.declarations[1]
    div := report.nodes[second.initializer]
    testing.expect(t, div.kind == .Binary && div.operator == .Slash &&
                   report.nodes[div.left].kind == .Unary,
                   "unary operator binds ahead of division")
    third := report.declarations[2]
    testing.expect(t, third.type_kind == .String &&
                   report.nodes[third.initializer].kind == .Text,
                   "string literal retained as source span")
}

@(test)
expression_left_associativity_and_unicode_positions :: proc(t: ^testing.T) {
    text := "// 😀\r\nlet total = 12 - 4 - 2;"
    version, valid := source.source_version_create(source.File_Id(402), 1, text)
    testing.expect(t, valid, "input valid")
    defer source.source_version_destroy(&version)
    report := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, report.complete && len(report.declarations) == 1,
                   "simple subtraction parses")
    root := report.nodes[report.declarations[0].initializer]
    testing.expect(t, root.operator == .Minus &&
                   report.nodes[root.left].kind == .Binary &&
                   report.nodes[root.left].operator == .Minus,
                   "binary subtraction is left-associative")
    pos, ok := source.source_position(&version, report.declarations[0].name_start)
    testing.expect(t, ok && pos.line == 1 && pos.column_utf16 == 4,
                   "source spans are mapped through byte-to-UTF16 line index")
}

@(test)
expression_recovery_reports_multiple_errors_without_false_success :: proc(t: ^testing.T) {
    text := "const broken = 1 + ;\nlet okay = 2 * 3;\nconst lost = (4 + 5;\nvar again: string = 'ok';"
    version, valid := source.source_version_create(source.File_Id(403), 1, text)
    testing.expect(t, valid, "test source")
    defer source.source_version_destroy(&version)
    report := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, !report.complete && !report.fatal &&
                   len(report.diagnostics) == 2 && len(report.declarations) == 2,
                   "both syntax issues reported; later valid statements recovered")
    testing.expect(t, report.diagnostics[0].issue == .Expected_Expression &&
                   report.diagnostics[1].issue == .Expected_Close_Paren,
                   "diagnostic classification is stable")
    for d in report.diagnostics {
        testing.expect(t, text[d.byte_start:d.byte_end] == ";",
                       "syntax diagnostic points to unexpected semicolon")
        _, ok := source.source_position(&version, d.byte_start)
        testing.expect(t, ok, "diagnostic span can be converted to UTF-16")
    }
    testing.expect(t, text[report.declarations[0].name_start:report.declarations[0].name_end] == "okay" &&
                   text[report.declarations[1].name_start:report.declarations[1].name_end] == "again",
                   "bad declarations don't enter the syntax result")
    testing.expect(t, len(report.nodes) == 4,
                   "rolled-back syntax nodes do not leak from bad declarations")
}

@(test)
expression_missing_name_and_semicolon_recover :: proc(t: ^testing.T) {
    text := "const = 1; let x = 2 3; const valid = 4;"
    version, valid := source.source_version_create(source.File_Id(404), 1, text)
    testing.expect(t, valid, "input valid")
    defer source.source_version_destroy(&version)
    report := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, !report.complete && len(report.diagnostics) == 2 &&
                   len(report.declarations) == 1, "two errors and final declaration")
    testing.expect(t, report.diagnostics[0].issue == .Missing_Name &&
                   report.diagnostics[1].issue == .Expected_Semicolon,
                   "missing-name and missing-semicolon issues")
    testing.expect(t, text[report.declarations[0].name_start:report.declarations[0].name_end] == "valid",
                   "recovery resumed at the next declaration")
}

@(test)
expression_unsupported_lexeme_is_fatal :: proc(t: ^testing.T) {
    text := "const okay = 1;\nconst bad = @;\nconst later = 2;"
    version, valid := source.source_version_create(source.File_Id(405), 1, text)
    testing.expect(t, valid, "source valid utf8")
    defer source.source_version_destroy(&version)
    report := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, report.fatal && !report.complete &&
                   len(report.diagnostics) >= 1 &&
                   report.diagnostics[len(report.diagnostics)-1].issue == .Unsupported_Lexeme,
                   "unsupported token cannot be recovered as success")
    testing.expect(t, len(report.declarations) == 1,
                   "only earlier complete statement can remain")
}

@(test)
expression_profile_and_depth_fail_closed :: proc(t: ^testing.T) {
    version, valid := source.source_version_create(source.File_Id(406), 1, "const value = 42;")
    testing.expect(t, valid, "valid source")
    defer source.source_version_destroy(&version)
    unknown := compat.Profile{version = compat.Version{8, 0, 0},
                              scanner_edition = .ASCII_Subset_V1}
    denied := parse_expression_program(&version, unknown)
    testing.expect(t, denied.fatal && !denied.complete &&
                   denied.diagnostics[0].issue == .Unsupported_Profile,
                   "unknown future edition is rejected explicitly")
    syntax_report_destroy(&denied)

    blank: source.Source_Version
    invalid := parse_expression_program(&blank, compat.ts7_profile())
    testing.expect(t, invalid.fatal && !invalid.complete &&
                   invalid.diagnostics[0].issue == .Invalid_Source,
                   "uninitialized source rejected")
    syntax_report_destroy(&invalid)

    deep := "const x = ((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((1))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))));"
    nested, ok := source.source_version_create(source.File_Id(407), 1, deep)
    testing.expect(t, ok, "deep parentheses valid UTF-8")
    defer source.source_version_destroy(&nested)
    report := parse_expression_program(&nested, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, !report.complete && len(report.diagnostics) > 0 &&
                   report.diagnostics[0].issue == .Nesting_Limit,
                   "recursion limit is an explicit diagnostic")
}


@(test)
parser_boolean_literals_keep_source_spans :: proc(t: ^testing.T) {
    input := "const enabled: boolean = true; let off = false; const next: boolean = off;"
    version, ok := source.source_version_create(source.File_Id(611), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&version)
    result := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&result)
    testing.expect(t, result.complete && !result.fatal &&
                   len(result.declarations) == 3, "boolean declarations parsed")
    first := result.nodes[result.declarations[0].initializer]
    second := result.nodes[result.declarations[1].initializer]
    testing.expect(t, first.kind == .Boolean && second.kind == .Boolean,
                   "true and false are literal nodes, not free names")
    testing.expect(t, input[first.byte_start:first.byte_end] == "true" &&
                   input[second.byte_start:second.byte_end] == "false",
                   "boolean literal source spellings are preserved")
    name := result.nodes[result.declarations[2].initializer]
    testing.expect(t, name.kind == .Name && input[name.byte_start:name.byte_end] == "off",
                   "ordinary boolean variable reference stays a Name")
}


@(test)
expression_comparison_logical_precedence :: proc(t: ^testing.T) {
    input := "const result: boolean = !false || 1 + 2 * 3 >= 7 && (4 === 4);"
    v, ok := source.source_version_create(source.File_Id(712), 1, input)
    testing.expect(t, ok, "expression source valid")
    defer source.source_version_destroy(&v)
    report := parse_expression_program(&v, compat.ts7_profile())
    defer syntax_report_destroy(&report)
    testing.expect(t, report.complete && len(report.declarations) == 1,
                   "comparison and logical program parsed")
    root := report.nodes[report.declarations[0].initializer]
    testing.expect(t, root.operator == .Bar_Bar, "logical or is lowest precedence")
    lhs := report.nodes[root.left]
    testing.expect(t, lhs.kind == .Unary && lhs.operator == .Exclamation,
                   "logical negation parsed before logical or")
    rhs := report.nodes[root.right]
    testing.expect(t, rhs.operator == .Ampersand_Ampersand, "logical and precedes or")
    relation := report.nodes[rhs.left]
    testing.expect(t, relation.operator == .Greater_Than_Equals,
                   "comparison precedes logical and")
    arithmetic := report.nodes[relation.left]
    testing.expect(t, arithmetic.operator == .Plus &&
                   report.nodes[arithmetic.right].operator == .Asterisk,
                   "arithmetic takes precedence over comparison")
    equal_group := report.nodes[rhs.right]
    testing.expect(t, equal_group.kind == .Group &&
                   report.nodes[equal_group.left].operator == .Equals_Equals_Equals,
                   "parenthesized equality retained")
}


@(test)
expression_statements_preserve_assignment_event_order :: proc(t: ^testing.T) {
    input := "let total: number = 1; total = 2; const copy = total;"
    v, ok := source.source_version_create(source.File_Id(730), 1, input)
    testing.expect(t, ok, "source accepted")
    defer source.source_version_destroy(&v)
    ast := parse_expression_program(&v, compat.ts7_profile())
    defer syntax_report_destroy(&ast)
    testing.expect(t, ast.complete && len(ast.declarations) == 2 &&
                   len(ast.statements) == 3 && len(ast.nodes) == 4,
                   "assignments are ordered events, not new declarations")
    if len(ast.statements) == 3 {
        first := ast.statements[0]
        assign := ast.statements[1]
        third := ast.statements[2]
        testing.expect(t, first.kind == .Declaration && first.declaration_index == 0 &&
                       assign.kind == .Assignment && assign.declaration_index == -1 &&
                       third.kind == .Declaration && third.declaration_index == 1,
                       "source order and declaration indices remain stable")
        testing.expect(t, input[ast.nodes[assign.target_node].byte_start:ast.nodes[assign.target_node].byte_end] == "total" &&
                       input[ast.nodes[assign.expression].byte_start:ast.nodes[assign.expression].byte_end] == "2",
                       "target and RHS are separately source-spanned nodes")
    }
}

@(test)
expression_assignment_syntax_fails_closed :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n = 1; n + 2;",
        "let n = 1; n = ;",
        "let n = 1; n = 2",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(731), 1, input)
        testing.expect(t, ok, "UTF-8 source accepted")
        ast := parse_expression_program(&v, compat.ts7_profile())
        testing.expect(t, !ast.complete && len(ast.diagnostics) > 0,
                       "unsupported/invalid assignment syntax never passes")
        syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
expression_conditional_events_keep_order :: proc(t: ^testing.T) {
    input := "let x: number = 1; x = 1 + 2; if (x === 2) { x = 3; } else { x = 4; } const y = x;"
    v, ok := source.source_version_create(source.File_Id(740), 1, input)
    testing.expect(t, ok, "source accepted")
    defer source.source_version_destroy(&v)
    ast := parse_expression_program(&v, compat.ts7_profile())
    defer syntax_report_destroy(&ast)
    testing.expect(t, ast.complete && len(ast.statements) == 8 && len(ast.declarations) == 2,
                   "one conditional emits a fork, split, join and two assignment events")
    if len(ast.statements) == 8 {
        testing.expect(t, ast.statements[2].kind == .If &&
                       ast.statements[3].kind == .Assignment &&
                       ast.statements[4].kind == .Else &&
                       ast.statements[5].kind == .Assignment &&
                       ast.statements[6].kind == .End_If &&
                       ast.statements[7].kind == .Declaration,
                       "events remain in source order")
        node := ast.nodes[ast.statements[2].expression]
        testing.expect(t, input[node.byte_start:node.byte_end] == "x === 2",
                       "guard span belongs to original source")
    }
}

@(test)
expression_conditional_unsupported_syntax_fails_closed :: proc(t: ^testing.T) {
    cases := [?]string {
        "let x = 1; if (x === 1) { x = 2; }",
        "let x = 1; if (x === 1) x = 2; else { x = 3; }",
        "let x = 1; if (x === 1) { let y = 2; } else { x = 3; }",
        "let x = 1; if (x === 1) { if (x === 2) { if (x === 3) { x = 4; } else { x = 5; } } else { x = 6; } } else { x = 7; }",
        "let x = 1; if (x === 1) { x = 2; } else x = 3;",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(741), 1, input)
        testing.expect(t, ok, "valid snapshot")
        ast := parse_expression_program(&v, compat.ts7_profile())
        testing.expect(t, !ast.complete && len(ast.diagnostics) > 0,
                       "unsupported shape is an incomplete parse")
        syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
expression_nested_if_events_keep_parent_order :: proc(t: ^testing.T) {
    input := "let x: number = 1; let ready: boolean = false;" +
             "if (x === 2) { if (ready) { x = 3; } else { x = 4; } x = 5; }" +
             "else { if (!ready) { x = 6; } else { x = 7; } }"
    v, ok := source.source_version_create(source.File_Id(751), 1, input)
    testing.expect(t, ok, "nested source")
    defer source.source_version_destroy(&v)
    ast := parse_expression_program(&v, compat.ts7_profile())
    defer syntax_report_destroy(&ast)
    testing.expect(t, ast.complete && !ast.fatal &&
                   len(ast.declarations) == 2 && len(ast.statements) == 16,
                   "two-level if/else emits a properly nested flat event stream")
    if len(ast.statements) == 16 {
        expected := [?]Statement_Kind {
            .Declaration, .Declaration, .If,
            .If, .Assignment, .Else, .Assignment, .End_If,
            .Assignment, .Else,
            .If, .Assignment, .Else, .Assignment, .End_If, .End_If,
        }
        for kind, i in expected {
            testing.expect(t, ast.statements[i].kind == kind,
                           "every child marker precedes the parent join")
        }
    }
}
