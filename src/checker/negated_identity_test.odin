package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

// A pure !Name guard equivalent to the original symbol must narrow both
// paths; proof records are observational, never branch inputs.
@(test)
checker_negated_identity_guards_narrow_both_arms :: proc(t: ^testing.T) {
    input := "let flag: boolean = false;" +
             "flag = 2 < 3;" +
             "let out: boolean = false;" +
             "if (!flag && true) { out = flag === false; } else { out = flag === true; }" +
             "if (true && !flag) { out = flag === false; } else { out = flag === true; }" +
             "if (!flag || false) { out = flag === false; } else { out = flag === true; }" +
             "if (false || !flag) { out = flag === false; } else { out = flag === true; }" +
             "if ((!flag) && true) { out = flag === false; } else { out = flag === true; }" +
             "if (false || (!!flag)) { out = flag === true; } else { out = flag === false; }" +
             "if (!(!flag && true)) { out = flag === true; } else { out = flag === false; }" +
             "if (!(false || !flag)) { out = flag === true; } else { out = flag === false; }" +
             "const after: boolean = flag === false;"
    v, ok := source.source_version_create(source.File_Id(849), 1, input)
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
                   normal.complete && failed.complete && all.complete &&
                   len(normal.diagnostics)==0 && len(failed.diagnostics)==0 &&
                   len(all.diagnostics)==0 && len(normal.comparisons)==0 &&
                   len(failed.comparisons)==0 && len(all.comparisons)==17,
                   "negated, grouped and double-negated identity guards infer both arms")
    if len(all.comparisons)==17 {
        previous := -1
        for i in 0..<17 {
            c := all.comparisons[i]
            expected := Comparison_Proof.Same_Literal
            if i == 16 { expected = .Widened_Domain }
            testing.expect(t, c.proof==expected && c.overlaps &&
                           c.left==.Boolean && c.right==.Boolean &&
                           c.node_index>previous && c.node_index<len(ast.nodes),
                           "real postorder equality proofs exclude stale post-join singleton")
            previous=c.node_index
        }
    }
    testing.expect(t, normal.checked_assignments==all.checked_assignments &&
                   normal.checked_declarations==all.checked_declarations &&
                   len(normal.relations)==0,
                   "proof tracing does not change ordinary checker work")
}

@(test)
checker_negated_identity_guard_disjoint_evidence :: proc(t: ^testing.T) {
    input := "// 😀 Non-BMP comment keeps UTF-16 coordinate provenance." +
             "let flag: boolean = false;" +
             "flag = 2 < 3;" +
             "let out: boolean = false;" +
             "if (!flag && true) { out = flag === true; } else { out = flag === false; }" +
             "if (true && !flag) { out = flag === true; } else { out = flag === false; }" +
             "if (!flag || false) { out = flag === true; } else { out = flag === false; }" +
             "if (false || !flag) { out = flag === true; } else { out = flag === false; }" +
             "if ((!flag) && true) { out = flag === true; } else { out = flag === false; }" +
             "if (false || (!!flag)) { out = flag === false; } else { out = flag === true; }" +
             "if (!(!flag && true)) { out = flag === false; } else { out = flag === true; }" +
             "if (!(false || !flag)) { out = flag === false; } else { out = flag === true; }" +
             "const wrong: string = 1;"
    v, ok := source.source_version_create(source.File_Id(850), 1, input)
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
                   !normal.complete && !failed.complete && !all.complete &&
                   len(normal.diagnostics)==17 && len(failed.diagnostics)==17 &&
                   len(all.diagnostics)==17 && len(normal.comparisons)==0 &&
                   len(failed.comparisons)==16 && len(all.comparisons)==16,
                   "sixteen TS2367-like disjoint comparisons and one TS2322-like mismatch")
    if len(normal.diagnostics)==17 {
        for i in 0..<17 {
            a := normal.diagnostics[i]
            b := failed.diagnostics[i]
            c := all.diagnostics[i]
            want := Check_Issue.Disjoint_Literal_Comparison
            if i == 16 { want = .Assignment_Type_Mismatch }
            testing.expect(t, a.issue==want && b.issue==want && c.issue==want &&
                           a.byte_start==b.byte_start && a.byte_start==c.byte_start &&
                           a.byte_end==b.byte_end && a.byte_end==c.byte_end,
                           "source order and byte anchors are trace-mode independent")
        }
    }
    if len(all.comparisons)==16 && len(failed.comparisons)==16 {
        previous := -1
        for i in 0..<16 {
            c := all.comparisons[i]
            testing.expect(t, c.proof==.Disjoint_Literals && !c.overlaps &&
                           c.node_index>previous && c.node_index<len(ast.nodes) &&
                           failed.comparisons[i].node_index==c.node_index,
                           "failure-only comparison evidence matches actual disjointness")
            previous=c.node_index
        }
    }
}

@(test)
checker_negated_identity_guard_nested_mutation_and_join :: proc(t: ^testing.T) {
    input := "// 😀 Nested mutation: no fact crosses a sibling path or the outer join." +
             "let flag: boolean = false;" +
             "flag = 2 < 3;" +
             "let gate: boolean = false;" +
             "gate = 4 > 2;" +
             "let out: boolean = false;" +
             "if (gate) {" +
             "if (!flag && true) {" +
             "out = flag === false;" +
             "flag = 3 < 4;" +
             "out = flag === true;" +
             "} else {" +
             "out = flag === true;" +
             "}" +
             "out = flag === false;" +
             "} else {" +
             "if (!(false || !flag)) {" +
             "out = flag === true;" +
             "} else {" +
             "out = flag === false;" +
             "}" +
             "}" +
             "out = flag === false;"
    v, ok := source.source_version_create(source.File_Id(851), 1, input)
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
                   normal.complete && failed.complete && all.complete &&
                   len(normal.diagnostics)==0 && len(all.diagnostics)==0 &&
                   len(normal.comparisons)==0 && len(failed.comparisons)==0 &&
                   len(all.comparisons)==7,
                   "nested negative guard never leaves a singleton in mutated path")
    if len(all.comparisons)==7 {
        expected := [?]Comparison_Proof{
            .Same_Literal, .Widened_Domain, .Same_Literal,
            .Widened_Domain, .Same_Literal, .Same_Literal,
            .Widened_Domain,
        }
        previous := -1
        for i in 0..<7 {
            c := all.comparisons[i]
            testing.expect(t, c.proof==expected[i] && c.overlaps &&
                           c.node_index>previous,
                           "branch-local inverse proof is invalidated on mutation and join")
            previous=c.node_index
        }
    }
    testing.expect(t, normal.checked_assignments==all.checked_assignments &&
                   normal.checked_declarations==all.checked_declarations,
                   "normal checker work stays unchanged under tracing")
}

@(test)
checker_negated_identity_guard_nonidentities_fail_closed :: proc(t: ^testing.T) {
    cases := [?]string{
        "let flag: boolean = false; flag = 2 < 3; let out: boolean = false;" +
        "if (!flag && false) { out = flag === false; } else { out = flag === true; }",
        "let flag: boolean = false; flag = 2 < 3; let out: boolean = false;" +
        "if (true || !flag) { out = flag === false; } else { out = flag === true; }",
        "let flag: boolean = false; flag = 2 < 3; let out: boolean = false;" +
        "if (flag && !true) { out = flag === true; } else { out = flag === false; }",
    }
    for i in 0..<len(cases) {
        v, ok := source.source_version_create(source.File_Id(852+i), 1, cases[i])
        testing.expect(t, ok, "valid source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file_with_relations(&v, &ast, &bound, .All)
        testing.expect(t, ast.complete && bound.complete &&
                       checked.fatal && !checked.complete &&
                       len(checked.diagnostics)>0,
                       "nonidentity or computed constant cannot invent both-arm facts")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}
