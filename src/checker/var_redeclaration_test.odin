package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
var_redeclaration_matching_type_remains_valid :: proc(t: ^testing.T) {
    input := "var shared: number = 1; var shared: number = 2; const n: number = shared;"
    v, ok := source.source_version_create(source.File_Id(964), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    report := check_file(&v, &ast, &bound)
    defer report_destroy(&report)
    testing.expect(t, ast.complete && bound.complete &&
                   len(bound.symbols)==2 && bound.symbols[0].declaration_count==2,
                   "both var declarations resolve to one symbol")
    testing.expect(t, report.complete && !report.fatal &&
                   len(report.diagnostics)==0 && report.checked_declarations==3,
                   "same-type redeclarations are valid")
}

@(test)
var_redeclaration_conflicting_type_never_succeeds :: proc(t: ^testing.T) {
    input := "var shared: number = 1; var shared: string = 'hello'; const n: number = shared;"
    v, ok := source.source_version_create(source.File_Id(965), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    report := check_file(&v, &ast, &bound)
    defer report_destroy(&report)
    testing.expect(t, ast.complete && bound.complete, "binder merges names")
    testing.expect(t, !report.complete && len(report.diagnostics)>0,
                   "conflicting var redeclaration must not report checker success")
}
