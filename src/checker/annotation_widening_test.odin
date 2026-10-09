package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
annotated_domains_and_flow_facts_match_supported_comparisons :: proc(t: ^testing.T) {
    input := "const typedCount: number = 1; const targetCount = 2;" +
             "const countCheck: boolean = typedCount === targetCount;" +
             "const copiedCount = typedCount; const copyCheck: boolean = copiedCount !== 9;" +
             "const typedLabel: string = 'first'; const otherLabel = 'second';" +
             "const labelCheck: boolean = typedLabel !== otherLabel;" +
             "let flexibleCount = 1; const mutableCheck: boolean = flexibleCount === 2;" +
             "const computedFlag: boolean = 1 < 2;" +
             "const computedCheck: boolean = computedFlag === false;" +
             "const trueFlag: boolean = true; const sameFlag: boolean = trueFlag === true;" +
             "const inverse = !trueFlag; const inverseCheck: boolean = inverse === false;"
    version, ok := source.source_version_create(source.File_Id(932), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&version)
    ast := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&version, &ast)
    defer binder.binding_report_destroy(&bound)
    checked := check_file_with_relations(&version, &ast, &bound, .All)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==0 &&
                   checked.checked_declarations==16 && len(checked.comparisons)==7,
                   "annotated, inferred, mutable, and Boolean declarations check without guessing")
    if len(checked.comparisons)==7 {
        for i in 0..<5 {
            testing.expect(t, checked.comparisons[i].proof==.Widened_Domain &&
                           checked.comparisons[i].overlaps,
                           "number/string/computed Boolean comparisons are wide")
        }
        for i in 5..<7 {
            testing.expect(t, checked.comparisons[i].proof==.Same_Literal &&
                           checked.comparisons[i].overlaps,
                           "Boolean flow literal and its inversion are preserved")
        }
    }
}

@(test)
annotated_boolean_flow_reports_disjointness_and_invalidation :: proc(t: ^testing.T) {
    input := "const typedFlag: boolean = true; const oppositeFlag = false;" +
             "const disjointFlag: boolean = typedFlag === oppositeFlag;" +
             "const aliasFlag: boolean = typedFlag;" +
             "const disjointAlias: boolean = aliasFlag !== false;" +
             "let mutableFlag: boolean = false;" +
             "const disjointFlow: boolean = mutableFlag === true;" +
             "mutableFlag = true;" +
             "const disjointAfterWrite: boolean = mutableFlag === false;" +
             "const inferredOne = 1; const inferredTwo = 2;" +
             "const disjointNumber: boolean = inferredOne === inferredTwo;" +
             "const wrong: string = typedFlag;"
    version, ok := source.source_version_create(source.File_Id(933), 1, input)
    testing.expect(t, ok, "source valid")
    defer source.source_version_destroy(&version)
    ast := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&version, &ast)
    defer binder.binding_report_destroy(&bound)
    checked := check_file(&version, &ast, &bound)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && bound.complete && !checked.fatal &&
                   !checked.complete && checked.checked_declarations==12 &&
                   checked.checked_assignments==1 && len(checked.diagnostics)==6,
                   "five disjoint comparisons and one assignment mismatch")
    if len(checked.diagnostics)==6 {
        for i in 0..<5 {
            testing.expect(t, checked.diagnostics[i].issue==.Disjoint_Literal_Comparison,
                           "actual Boolean/number literal flow is disjoint")
        }
        testing.expect(t, checked.diagnostics[5].issue==.Assignment_Type_Mismatch,
                       "annotation assignment retains TS2322 semantics")
    }
}
