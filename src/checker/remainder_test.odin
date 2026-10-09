package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
checker_remainder_infers_widened_numbers_through_assignments :: proc(t: ^testing.T) {
    input := "let a: number = 17; let b: number = 5;" +
             "const rem = a % b; const chain = 22 / 5 % 3 * 2;" +
             "let adjusted: number = 0; adjusted = (a + 4) % 3;" +
             "const first: boolean = rem === 2;" +
             "const second: boolean = chain !== 0;"
    version, valid := source.source_version_create(source.File_Id(923), 1, input)
    testing.expect(t, valid, "valid remainder source")
    defer source.source_version_destroy(&version)
    syntax := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&syntax)
    bound := binder.bind_program(&version, &syntax)
    defer binder.binding_report_destroy(&bound)
    ordinary := check_file(&version, &syntax, &bound)
    defer report_destroy(&ordinary)
    trace := check_file_with_relations(&version, &syntax, &bound, .All)
    defer report_destroy(&trace)
    testing.expect(t, syntax.complete && bound.complete &&
                   ordinary.complete && trace.complete &&
                   !ordinary.fatal && !trace.fatal &&
                   ordinary.checked_declarations==7 &&
                   ordinary.checked_assignments==1 &&
                   len(ordinary.diagnostics)==0 && len(trace.diagnostics)==0,
                   "remainder has number type and preserves assignment checks")
    testing.expect(t, len(ordinary.comparisons)==0 &&
                   len(trace.comparisons)==2,
                   "trace mode keeps computed overlap evidence opt-in")
    for item in trace.comparisons {
        testing.expect(t, item.proof==.Widened_Domain &&
                       item.left==.Number && item.right==.Number &&
                       item.overlaps,
                       "remainder does not pretend a singleton literal")
    }
}

@(test)
checker_remainder_reports_assignment_mismatch_and_overlap_disjointness :: proc(t: ^testing.T) {
    input := "const wrongText: string = 8 % 3;" +
             "const wrongBoolean: boolean = (9 - 2) % 4;" +
             "const computed = 17 % 5;" +
             "const impossible = computed === 'different';"
    version, valid := source.source_version_create(source.File_Id(924), 1, input)
    testing.expect(t, valid, "valid source")
    defer source.source_version_destroy(&version)
    syntax := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&syntax)
    bound := binder.bind_program(&version, &syntax)
    defer binder.binding_report_destroy(&bound)
    checked := check_file(&version, &syntax, &bound)
    defer report_destroy(&checked)
    testing.expect(t, syntax.complete && bound.complete &&
                   !checked.complete && !checked.fatal &&
                   len(checked.diagnostics)==3,
                   "two TS2322-like and one TS2367-like diagnostics")
    testing.expect(t, checked.diagnostics[0].issue==.Assignment_Type_Mismatch &&
                   checked.diagnostics[1].issue==.Assignment_Type_Mismatch &&
                   checked.diagnostics[2].issue==.Disjoint_Primitive_Domains,
                   "remainder error order and mapping are source-backed")
}

@(test)
checker_remainder_rejects_string_operand :: proc(t: ^testing.T) {
    input := "const impossible = 8 % 'not a number';"
    version, valid := source.source_version_create(source.File_Id(925), 1, input)
    testing.expect(t, valid, "source valid")
    defer source.source_version_destroy(&version)
    syntax := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&syntax)
    bound := binder.bind_program(&version, &syntax)
    defer binder.binding_report_destroy(&bound)
    checked := check_file(&version, &syntax, &bound)
    defer report_destroy(&checked)
    testing.expect(t, syntax.complete && bound.complete &&
                   checked.fatal && !checked.complete &&
                   len(checked.diagnostics)==1 &&
                   checked.diagnostics[0].issue==.Incompatible_Operator,
                   "unsupported mixed-domain remainder fails closed")
}
