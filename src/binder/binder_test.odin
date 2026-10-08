package binder

import "core:testing"
import "../source"
import "../parser"
import "../compat"

@(test)
binder_resolves_forward_names :: proc(t: ^testing.T) {
    text := "const x = later + 1; let later = 2;"
    v, ok := source.source_version_create(source.File_Id(1), 9, text)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    testing.expect(t, ast.complete, "parse complete")
    result := bind_program(&v, &ast)
    defer binding_report_destroy(&result)
    testing.expect(t, result.complete && !result.fatal &&
                   len(result.symbols) == 2 && len(result.references) == 1,
                   "forward binding succeeds")
    reference := result.references[0]
    testing.expect(t, reference.symbol_index == 1 &&
                   text[reference.byte_start:reference.byte_end] == "later" &&
                   result.generation == 9, "stable symbol ID and version")
}

@(test)
binder_distinguishes_var_merge_and_duplicate_lexicals :: proc(t: ^testing.T) {
    text := "var v = 1; var v = 2; let a = 3; const a = 4;"
    v, ok := source.source_version_create(source.File_Id(2), 1, text)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    result := bind_program(&v, &ast)
    defer binding_report_destroy(&result)
    testing.expect(t, !result.complete && !result.fatal &&
                   len(result.symbols) == 2 && len(result.issues) == 1 &&
                   result.issues[0].kind == .Duplicate_Declaration,
                   "lexical redeclaration is not silently permitted")
    testing.expect(t, result.symbols[0].declaration_count == 2,
                   "same-scope var redeclarations share a symbol")
    issue := result.issues[0]
    testing.expect(t, text[issue.byte_start:issue.byte_end] == "a",
                   "second conflicting name is reported")
}

@(test)
binder_unresolved_and_stale_syntax_fail :: proc(t: ^testing.T) {
    v, ok := source.source_version_create(source.File_Id(3), 1, "let a = missing;")
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    result := bind_program(&v, &ast)
    testing.expect(t, !result.complete && len(result.issues) == 1 &&
                   result.issues[0].kind == .Unresolved_Name,
                   "unknown local identifier must be reported")
    binding_report_destroy(&result)
    other, ok2 := source.source_version_create(source.File_Id(3), 2, "let a = missing;")
    testing.expect(t, ok2, "second snapshot")
    defer source.source_version_destroy(&other)
    stale := bind_program(&other, &ast)
    testing.expect(t, stale.fatal && !stale.complete &&
                   stale.issues[0].kind == .Snapshot_Mismatch,
                   "cannot bind AST to another generation")
    binding_report_destroy(&stale)
    syntax_bad, ok3 := source.source_version_create(source.File_Id(4), 1, "const a = 1 + ;")
    testing.expect(t, ok3, "invalid syntax but valid bytes")
    defer source.source_version_destroy(&syntax_bad)
    parsed_bad := parser.parse_expression_program(&syntax_bad, compat.ts7_profile())
    defer parser.syntax_report_destroy(&parsed_bad)
    refused := bind_program(&syntax_bad, &parsed_bad)
    testing.expect(t, refused.fatal && !refused.complete &&
                   refused.issues[0].kind == .Syntax_Not_Complete,
                   "parser recovery is not binding success")
    binding_report_destroy(&refused)
}


@(test)
binder_resolves_assignment_targets_without_creating_symbols :: proc(t: ^testing.T) {
    input := "let score = 1; score = 2; const copy = score;"
    v, ok := source.source_version_create(source.File_Id(732), 1, input)
    testing.expect(t, ok, "valid source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := bind_program(&v, &ast)
    testing.expect(t, ast.complete && bound.complete &&
                   len(bound.symbols) == 2 && len(bound.references) == 2,
                   "target and read references resolve to original declaration")
    if len(bound.references) == 2 {
        testing.expect(t, bound.references[0].symbol_index == 0 &&
                       bound.references[1].symbol_index == 0,
                       "both uses share the first symbol identity")
    }
    binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}
