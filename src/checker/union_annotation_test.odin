package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
union_annotations_typecheck_and_reassign :: proc(t: ^testing.T) {
    input := "let value: number | string = 7;" +
             "value = 'word'; value = 2 + 5;" +
             "const boolOrText: boolean | string = true;" +
             "const both: string | number = value;" +
             "const numeric: number | number = 7;"
    version, ok := source.source_version_create(source.File_Id(945), 1, input)
    testing.expect(t, ok, "valid union program")
    defer source.source_version_destroy(&version)
    ast := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    binding := binder.bind_program(&version, &ast)
    defer binder.binding_report_destroy(&binding)
    checked := check_file(&version, &ast, &binding)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && binding.complete && checked.complete &&
                   len(checked.diagnostics)==0 && checked.checked_declarations==4 &&
                   checked.checked_assignments==2, "union source-to-checker path accepted")
    if len(ast.declarations)==4 {
        testing.expect(t, ast.declarations[0].type_kind==.Number_String &&
                       ast.declarations[3].type_kind==.Number,
                       "reordered union and duplicate annotation canonicalized")
    }
}

@(test)
union_annotations_reject_invalid_assignments :: proc(t: ^testing.T) {
    input := "let value: number | string = 7;" +
             "value = false;" +
             "const wrong: string | boolean = 42;"
    version, ok := source.source_version_create(source.File_Id(946), 1, input)
    testing.expect(t, ok, "valid error-source")
    defer source.source_version_destroy(&version)
    ast := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    binding := binder.bind_program(&version, &ast)
    defer binder.binding_report_destroy(&binding)
    checked := check_file(&version, &ast, &binding)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && binding.complete && !checked.complete &&
                   !checked.fatal && checked.checked_assignments==1 &&
                   checked.checked_declarations==2 &&
                   len(checked.diagnostics)==2,
                   "invalid union writes and declarations remain non-success")
    for diag in checked.diagnostics {
        testing.expect(t, diag.issue==.Assignment_Type_Mismatch &&
                       diag.byte_end > diag.byte_start, "source-backed mismatch")
    }
}

@(test)
union_annotations_fail_closed_for_unsupported_syntax :: proc(t: ^testing.T) {
    cases := [?]string{
        "let x: number | = 1;",
        "let x: number | unknown = 1;",
        "const x = 1 | 2;",
        "let x: number | string[] = 1;",
    }
    for input in cases {
        version, ok := source.source_version_create(source.File_Id(947), 1, input)
        testing.expect(t, ok, "valid UTF-8")
        ast := parser.parse_expression_program(&version, compat.ts7_profile())
        testing.expect(t, !ast.complete && len(ast.diagnostics)>0,
                       "unsupported syntax never becomes a valid check")
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&version)
    }
}

@(test)
union_comparisons_must_not_fake_disjoint_primitive_domains :: proc(t: ^testing.T) {
    input := "let flag: boolean = 1 < 2; let value: number | string = 7;" +
             "if (flag) { value = 2; } else { value = 'text'; }" +
             "const compared = value === 7;"
    version, ok := source.source_version_create(source.File_Id(949), 1, input)
    testing.expect(t, ok, "valid source")
    defer source.source_version_destroy(&version)
    ast := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    binding := binder.bind_program(&version, &ast)
    defer binder.binding_report_destroy(&binding)
    checked := check_file(&version, &ast, &binding)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && binding.complete &&
                   checked.fatal && !checked.complete &&
                   len(checked.diagnostics)==1 &&
                   checked.diagnostics[0].issue==.Unsupported_Expression,
                   "union comparisons stay unsupported, not falsely disjoint")
}
