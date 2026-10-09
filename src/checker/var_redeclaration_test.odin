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
    testing.expect(t, !report.complete && !report.fatal &&
                   len(report.diagnostics)==1 &&
                   report.diagnostics[0].issue==.Conflicting_Var_Redeclaration &&
                   report.diagnostics[0].byte_end > report.diagnostics[0].byte_start,
                   "TS2403 candidate must anchor the second declaration name")
}

@(test)
var_redeclaration_replaces_canonical_union_flow :: proc(t: ^testing.T) {
    cases := [?]struct {input: string, valid: bool}{
        {"var x: number | string = 1; var x: string | number = 'text'; const s: string = x;", true},
        {"var x: number | string = 1; var x: string | number = 'text'; const n: number = x;", false},
    }
    for c in cases {
        v, ok := source.source_version_create(source.File_Id(966), 1, c.input)
        testing.expect(t, ok, "source valid")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete &&
                       checked.complete == c.valid, "redeclared union flow is current")
        if !c.valid {
            testing.expect(t, len(checked.diagnostics)==1 &&
                           checked.diagnostics[0].issue==.Assignment_Type_Mismatch,
                           "incompatible read follows the latest initializer")
        }
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}
