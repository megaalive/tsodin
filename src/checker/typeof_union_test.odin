package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
typeof_guard_splits_both_arms_and_rejoins :: proc(t: ^testing.T) {
    input := "let flag: boolean = 1 < 2; let value: number | string = 1;" +
             "if (flag) { value = 8; } else { value = 'one'; }" +
             "let numeric: number = 0; let textual: string = '';" +
             "if (typeof value === 'number') { numeric = value; }" +
             "else { textual = value; }" +
             "if (typeof value !== 'number') { textual = value; }" +
             "else { numeric = value; }"
    v, ok := source.source_version_create(source.File_Id(951), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    report := check_file(&v, &ast, &bound)
    defer report_destroy(&report)
    testing.expect(t, ast.complete && bound.complete && report.complete &&
                   !report.fatal && len(report.diagnostics)==0 &&
                   report.checked_declarations==4 && report.checked_assignments==6,
                   "both typeof operators narrow exact primitive union and rejoin")
}

@(test)
typeof_guard_invalidation_in_branch_and_after_join :: proc(t: ^testing.T) {
    input := "let flag: boolean = 1 < 2; let value: number | string = 1;" +
             "if (flag) { value = 8; } else { value = 'one'; }" +
             "let numeric: number = 0; let textual: string = '';" +
             "if (typeof value === 'number') { numeric = value; value = 'changed'; textual = value; }" +
             "else { textual = value; value = 4; }" +
             "if (typeof value === 'string') { textual = value; } else { numeric = value; }"
    v, ok := source.source_version_create(source.File_Id(952), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    report := check_file(&v, &ast, &bound)
    defer report_destroy(&report)
    testing.expect(t, ast.complete && bound.complete && report.complete &&
                   !report.fatal && len(report.diagnostics)==0,
                   "union writes replace branch fact and nested join remains sound")
}

@(test)
typeof_guard_proves_incompatible_writes :: proc(t: ^testing.T) {
    input := "let flag: boolean = 1 < 2; let value: number | string = 1;" +
             "if (flag) { value = 8; } else { value = 'one'; }" +
             "let numeric: number = 0; let textual: string = '';" +
             "if (typeof value === 'number') { textual = value; }" +
             "else { numeric = value; }"
    v, ok := source.source_version_create(source.File_Id(953), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    report := check_file(&v, &ast, &bound)
    defer report_destroy(&report)
    testing.expect(t, ast.complete && bound.complete && !report.complete &&
                   !report.fatal && len(report.diagnostics)==2,
                   "both arms yield real type mismatch diagnostics")
    for d in report.diagnostics {
        testing.expect(t, d.issue == .Assignment_Type_Mismatch,
                       "negative witnesses remain checker type mismatches")
    }
}

@(test)
typeof_guard_unsupported_fragments_fail_closed :: proc(t: ^testing.T) {
    cases := [?]string{
        "let x: number | string = 1; if (typeof x === 'object') { x = 2; } else { x = 'a'; }",
        "let x: number | string = 1; if (typeof x === 'number') { x = 2; } else { x = 'a'; }",
        "let x: number | string = 1; if (typeof x === 2) { x = 2; } else { x = 'a'; }",
        "let x: number | string = 1; if (typeof x === 'number' && true) { x = 2; } else { x = 'a'; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(954), 1, input)
        testing.expect(t, ok, "valid utf8")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        report := check_file(&v, &ast, &bound)
        testing.expect(t, !report.complete && (report.fatal || len(report.diagnostics)>0),
                       "unsupported typeof guard cannot report a success")
        report_destroy(&report)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}
