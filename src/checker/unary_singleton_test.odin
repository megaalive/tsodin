package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
checker_unary_singleton_literals_and_aliases :: proc(t: ^testing.T) {
    input := "const no = !true; const yes = !false;" +
             "const twice = !!true; const grouped = !(false);" +
             "const first = no === false; const second = twice !== true;" +
             "const third = grouped === true; const fourth = yes !== true;"
    v, ok := source.source_version_create(source.File_Id(838), 1, input)
    testing.expect(t, ok, "source")
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
                   len(ordinary.diagnostics)==0 && len(all.diagnostics)==0 &&
                   len(ordinary.comparisons)==0 && len(failed.comparisons)==0 &&
                   len(all.comparisons)==4,
                   "singleton negation and aliases preserve provable overlap")
    previous := -1
    for c in all.comparisons {
        testing.expect(t, c.proof==.Same_Literal && c.overlaps &&
                       c.left==.Boolean && c.right==.Boolean &&
                       c.node_index>previous && c.node_index<len(ast.nodes),
                       "grouped and repeated unary negations keep Boolean facts")
        previous = c.node_index
    }
    testing.expect(t, ordinary.checked_declarations==all.checked_declarations &&
                   ordinary.checked_assignments==all.checked_assignments,
                   "opt-in tracing has no semantic side effect")
}

@(test)
checker_unary_singleton_disjoint_diagnostics :: proc(t: ^testing.T) {
    input := "const no = !true; const yes = !false;" +
             "const badFirst = no === true; const good = yes === true;" +
             "const badSecond = yes !== false;" +
             "const badThird = !!false === true;" +
             "const wrong: string = no;"
    v, ok := source.source_version_create(source.File_Id(839), 1, input)
    testing.expect(t, ok, "source")
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
                   len(normal.diagnostics)==4 && len(failures.diagnostics)==4 &&
                   len(all.diagnostics)==4 && len(normal.comparisons)==0 &&
                   len(failures.comparisons)==3 && len(all.comparisons)==4,
                   "three disjoint Boolean comparisons and one assignment mismatch")
    if len(normal.diagnostics)==4 {
        for i in 0..<4 {
            a := normal.diagnostics[i]
            b := failures.diagnostics[i]
            c := all.diagnostics[i]
            want := Check_Issue.Disjoint_Literal_Comparison
            if i == 3 { want = .Assignment_Type_Mismatch }
            testing.expect(t, a.issue==want && b.issue==want && c.issue==want &&
                           a.byte_start==b.byte_start && b.byte_start==c.byte_start &&
                           a.byte_end==b.byte_end && b.byte_end==c.byte_end,
                           "comparison proof tracing does not shift error anchors")
        }
    }
    if len(all.comparisons)==4 && len(failures.comparisons)==3 {
        previous, skipped := -1, 0
        for c in all.comparisons {
            testing.expect(t, c.node_index>previous &&
                           (c.proof==.Same_Literal || c.proof==.Disjoint_Literals),
                           "stable evidence kinds and source order")
            if !c.overlaps {
                testing.expect(t, failures.comparisons[skipped].node_index==c.node_index &&
                               c.proof==.Disjoint_Literals,
                               "failure-only records match actual disjoint sites")
                skipped += 1
            }
            previous=c.node_index
        }
        testing.expect(t, skipped==3, "all three failures were recorded")
    }
}

@(test)
checker_unary_singleton_branch_mutation_join :: proc(t: ^testing.T) {
    input := "let flag: boolean = false; flag = 2 < 3;" +
             "let out: boolean = false;" +
             "if (flag) { out = (!flag) === true;" +
             "  flag = 4 > 2; out = (!flag) === false;" +
             "} else { out = (!flag) === false; }" +
             "out = (!flag) === true;"
    v, ok := source.source_version_create(source.File_Id(840), 1, input)
    testing.expect(t, ok, "source")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    normal := check_file(&v, &ast, &bound)
    defer report_destroy(&normal)
    failed := check_file_with_relations(&v, &ast, &bound, .Failures)
    defer report_destroy(&failed)
    all := check_file_with_relations(&v, &ast, &bound, .All)
    defer report_destroy(&all)
    testing.expect(t, ast.complete && bound.complete &&
                   !normal.fatal && !failed.fatal && !all.fatal &&
                   len(normal.diagnostics)==2 && len(failed.diagnostics)==2 &&
                   len(all.diagnostics)==2 && len(normal.comparisons)==0 &&
                   len(failed.comparisons)==2 && len(all.comparisons)==4,
                   "branch-local inverse singleton is invalidated by mutation and join")
    if len(all.comparisons)==4 {
        proofs := [?]Comparison_Proof{
            .Disjoint_Literals,.Widened_Domain,
            .Disjoint_Literals,.Widened_Domain,
        }
        for i in 0..<4 {
            c := all.comparisons[i]
            testing.expect(t, c.proof==proofs[i] &&
                           c.overlaps==(proofs[i]==.Widened_Domain),
                           "source-ordered proofs never reuse stale narrowed facts")
        }
    }
    testing.expect(t, normal.checked_assignments==all.checked_assignments &&
                   normal.checked_declarations==all.checked_declarations &&
                   len(normal.relations)==0 && len(normal.comparisons)==0,
                   "normal checker remains untraced")
}
