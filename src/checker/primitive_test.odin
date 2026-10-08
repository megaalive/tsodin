package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
primitive_checker_handles_inference_and_arithmetic :: proc(t: ^testing.T) {
    text := "const base: number = 4; let doubled = base * 2; const message: string = 'value=' + doubled;"
    v, ok := source.source_version_create(source.File_Id(601), 2, text)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    testing.expect(t, ast.complete && bound.complete, "fully supported parse and bind")
    result := check_file(&v, &ast, &bound)
    defer report_destroy(&result)
    testing.expect(t, result.complete && !result.fatal &&
                   len(result.diagnostics)==0 && result.checked_declarations==3,
                   "numeric inference and mixed string concatenation are typed")
    testing.expect(t, result.file_id==v.file_id && result.generation==2,
                   "file/version identity")
}

@(test)
primitive_checker_reports_type_mismatches_without_success :: proc(t: ^testing.T) {
    text := "const n: number = 'oops'; let fine: number = 1 + 2; const s: string = 5;"
    v, ok := source.source_version_create(source.File_Id(602), 1, text)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    result := check_file(&v, &ast, &bound)
    defer report_destroy(&result)
    testing.expect(t, !result.complete && !result.fatal &&
                   len(result.diagnostics)==2 && result.checked_declarations==3,
                   "two assignability failures and a valid intermediate declaration")
    for issue in result.diagnostics {
        testing.expect(t, issue.issue==.Assignment_Type_Mismatch &&
                       issue.byte_end > issue.byte_start,
                       "mismatched initializer has a real source span")
        _, valid := source.source_position(&v, issue.byte_start)
        testing.expect(t, valid, "UTF-16 projection exists")
    }
    testing.expect(t, text[result.diagnostics[0].byte_start:result.diagnostics[0].byte_end]=="n" &&
                   text[result.diagnostics[1].byte_start:result.diagnostics[1].byte_end]=="s",
                   "assignment mismatch markers point to declared identifiers")
}

@(test)
primitive_checker_refuses_unimplemented_forward_semantics :: proc(t: ^testing.T) {
    text := "const total: number = later + 1; let later: number = 3;"
    v, ok := source.source_version_create(source.File_Id(603), 1, text)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    testing.expect(t, bound.complete, "binder knows forward symbol")
    result := check_file(&v, &ast, &bound)
    defer report_destroy(&result)
    testing.expect(t, result.fatal && !result.complete &&
                   result.diagnostics[0].issue==.Unsupported_Forward_Reference,
                   "binder forward lookup must not imply sound TDZ semantics")
}

@(test)
primitive_checker_rejects_unsupported_operations_and_unassigned_reads :: proc(t: ^testing.T) {
    cases := [?]string{
        "const value = 'text' - 1;",
        "let value: number; const copy: number = value;",
        "let implicit; const copy = 1;",
    }
    for text in cases {
        v, ok := source.source_version_create(source.File_Id(604), 1, text)
        testing.expect(t, ok, "valid source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        testing.expect(t, ast.complete && bound.complete, "supported parsing/binding")
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, checked.fatal && !checked.complete &&
                       len(checked.diagnostics)>0, "unsupported semantic path fails closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_refuses_incomplete_binding_and_wrong_versions :: proc(t: ^testing.T) {
    v, ok := source.source_version_create(source.File_Id(605), 1, "const x = missing + 1;")
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    rejected := check_file(&v, &ast, &bound)
    testing.expect(t, rejected.fatal && !rejected.complete &&
                   rejected.diagnostics[0].issue==.Incomplete_Binding,
                   "unresolved name prevents a successful checker result")
    report_destroy(&rejected)

    v2, ok2 := source.source_version_create(source.File_Id(605), 2, "const x = 1;")
    testing.expect(t, ok2, "next generation exists")
    defer source.source_version_destroy(&v2)
    stale := check_file(&v2, &ast, &bound)
    testing.expect(t, stale.fatal && stale.diagnostics[0].issue==.Snapshot_Mismatch,
                   "check may not use old AST/binder over a new source snapshot")
    report_destroy(&stale)
}

@(test)
primitive_checker_accepts_empty_file_and_explicit_declaration :: proc(t: ^testing.T) {
    cases := [?]string{"", "let ready: boolean;", "var total: number;"}
    for text in cases {
        v, ok := source.source_version_create(source.File_Id(606), 1, text)
        testing.expect(t, ok, "source initialized")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, checked.complete && !checked.fatal &&
                       len(checked.diagnostics)==0,
                       "empty file or unused explicitly typed declarations pass")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}
