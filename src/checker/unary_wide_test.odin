package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

// The unary Boolean domain is widened only when its operand is already
// proven-wide; neither the result nor its negation is a guessed singleton.
@(test)
checker_unary_not_preserves_wide_boolean_domain :: proc(t: ^testing.T) {
    input := "let flag: boolean = false; flag = 2 < 3;" +
             "const inverted = !flag; const twice = !!flag;" +
             "const grouped = !(flag);" +
             "const first: boolean = inverted === true;" +
             "const second: boolean = twice !== false;" +
             "const third: boolean = grouped === false;"
    v, ok := source.source_version_create(source.File_Id(835), 1, input)
    testing.expect(t, ok, "valid source version")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    ordinary := check_file(&v, &ast, &bound)
    defer report_destroy(&ordinary)
    failed := check_file_with_relations(&v, &ast, &bound, .Failures)
    defer report_destroy(&failed)
    all := check_file_with_relations(&v, &ast, &bound, .All)
    defer report_destroy(&all)
    testing.expect(t, ast.complete && bound.complete &&
                   ordinary.complete && failed.complete && all.complete &&
                   !ordinary.fatal && !failed.fatal && !all.fatal &&
                   len(ordinary.diagnostics)==0 && len(all.diagnostics)==0 &&
                   ordinary.checked_declarations==7 &&
                   ordinary.checked_assignments==1 &&
                   ordinary.checked_declarations==all.checked_declarations &&
                   ordinary.checked_assignments==all.checked_assignments,
                   "wide unary negation typechecks without changing declaration/assignment work")
    testing.expect(t, len(ordinary.comparisons)==0 &&
                   len(failed.comparisons)==0 && len(all.comparisons)==3,
                   "wide Boolean equality produces only opt-in overlap proofs")
    previous := -1
    for c in all.comparisons {
        testing.expect(t, c.proof==.Widened_Domain && c.overlaps &&
                       c.left==.Boolean && c.right==.Boolean &&
                       c.node_index>previous &&
                       c.node_index<len(ast.nodes),
                       "all three comparisons are proven-wide, never folded literals")
        previous=c.node_index
    }
}

// An explicitly annotated Boolean const is not retained as an inferred
// singleton in this bounded checker. Negating it cannot fabricate a fact.
@(test)
checker_unary_not_unproved_annotated_operand_stays_closed :: proc(t: ^testing.T) {
    input := "const typed: boolean = true; const negated = !typed;" +
             "const comparison = negated === false;"
    v, ok := source.source_version_create(source.File_Id(836), 1, input)
    testing.expect(t, ok, "valid source version")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    checked := check_file_with_relations(&v, &ast, &bound, .All)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && bound.complete &&
                   checked.fatal && !checked.complete &&
                   len(checked.comparisons)==0 &&
                   len(checked.diagnostics)==1 &&
                   checked.diagnostics[0].issue==.Incompatible_Operator,
                   "unproven annotated const Boolean remains explicitly unsupported")
}

@(test)
checker_unary_not_wide_diagnostics_and_trace_modes :: proc(t: ^testing.T) {
    input := "let flag: boolean = false; flag = 2 < 3;" +
             "const inverted = !flag; const wrong: string = inverted;" +
             "const badDomain = inverted === 1;" +
             "const fine: boolean = inverted !== false;"
    v, ok := source.source_version_create(source.File_Id(837), 1, input)
    testing.expect(t, ok, "valid source version")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    normal := check_file(&v, &ast, &bound)
    defer report_destroy(&normal)
    failures := check_file_with_relations(&v, &ast, &bound, .Failures)
    defer report_destroy(&failures)
    all := check_file_with_relations(&v, &ast, &bound, .All)
    defer report_destroy(&all)
    testing.expect(t, ast.complete && bound.complete &&
                   !normal.fatal && !failures.fatal && !all.fatal &&
                   !normal.complete && !failures.complete && !all.complete &&
                   len(normal.diagnostics)==2 &&
                   len(failures.diagnostics)==2 &&
                   len(all.diagnostics)==2,
                   "wide unary comparisons report two independent semantic errors")
    if len(normal.diagnostics)==2 {
        testing.expect(t, normal.diagnostics[0].issue==.Assignment_Type_Mismatch &&
                       normal.diagnostics[1].issue==.Disjoint_Primitive_Domains,
                       "type mismatch precedes strict-equality domain disjointness")
        for i in 0..<2 {
            a := normal.diagnostics[i]
            b := failures.diagnostics[i]
            c := all.diagnostics[i]
            testing.expect(t, b.issue==a.issue && c.issue==a.issue &&
                           b.byte_start==a.byte_start && c.byte_start==a.byte_start &&
                           b.byte_end==a.byte_end && c.byte_end==a.byte_end,
                           "evidence mode must not alter semantic diagnostics or spans")
        }
    }
    testing.expect(t, len(normal.comparisons)==0 &&
                   len(failures.comparisons)==1 && len(all.comparisons)==2,
                   "failures-only records disjoint proof, all mode includes overlap")
    if len(all.comparisons)==2 && len(failures.comparisons)==1 {
        testing.expect(t, all.comparisons[0].proof==.Disjoint_Domains &&
                       !all.comparisons[0].overlaps &&
                       all.comparisons[1].proof==.Widened_Domain &&
                       all.comparisons[1].overlaps &&
                       failures.comparisons[0].node_index==all.comparisons[0].node_index,
                       "comparison proof taxonomy remains source-ordered")
    }
}
