package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
checker_boolean_identity_guards_narrow_both_paths :: proc(t: ^testing.T) {
    input := "let flag: boolean = false; flag = 2 < 3;" +
             "let out: boolean = false;" +
             "if (flag && true) { out = flag === true; } else { out = flag === false; }" +
             "if (true && flag) { out = flag === true; } else { out = flag === false; }" +
             "if (flag || false) { out = flag === true; } else { out = flag === false; }" +
             "if (false || flag) { out = flag === true; } else { out = flag === false; }" +
             "if (!(flag && true)) { out = flag === false; } else { out = flag === true; }" +
             "if (!(false || flag)) { out = flag === false; } else { out = flag === true; }" +
             "const after: boolean = flag === false;"
    v, ok := source.source_version_create(source.File_Id(844), 1, input)
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
                   len(failed.comparisons)==0 && len(all.comparisons)==13,
                   "four identities and negations narrow both branches, joins stay wide")
    if len(all.comparisons)==13 {
        previous := -1
        for i in 0..<13 {
            c := all.comparisons[i]
            want := Comparison_Proof.Same_Literal
            if i == 12 { want = .Widened_Domain }
            testing.expect(t, c.proof==want && c.overlaps &&
                           c.left==.Boolean && c.right==.Boolean &&
                           c.node_index>previous,
                           "each conditional arm uses its proved fact; no post-join singleton")
            previous=c.node_index
        }
    }
    testing.expect(t, normal.checked_assignments==all.checked_assignments &&
                   normal.checked_declarations==all.checked_declarations &&
                   len(normal.relations)==0,
                   "normal checking cannot change due to opt-in proof tracing")
}

@(test)
checker_boolean_identity_guards_disjointness_in_source_order :: proc(t: ^testing.T) {
    input := "let flag: boolean = false; flag = 2 < 3;" +
             "let out: boolean = false;" +
             "if (flag && true) { out = flag === false; } else { out = flag === true; }" +
             "if (true && flag) { out = flag === false; } else { out = flag === true; }" +
             "if (flag || false) { out = flag === false; } else { out = flag === true; }" +
             "if (false || flag) { out = flag === false; } else { out = flag === true; }" +
             "if (!(flag && true)) { out = flag === true; } else { out = flag === false; }" +
             "if (!(false || flag)) { out = flag === true; } else { out = flag === false; }" +
             "const wrong: string = 1;"
    v, ok := source.source_version_create(source.File_Id(845), 1, input)
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
                   len(normal.diagnostics)==13 &&
                   len(failed.diagnostics)==13 && len(all.diagnostics)==13 &&
                   len(normal.comparisons)==0 &&
                   len(failed.comparisons)==12 && len(all.comparisons)==12,
                   "twelve branch-local TS2367 candidates and one TS2322 candidate")
    if len(normal.diagnostics)==13 {
        for i in 0..<13 {
            a := normal.diagnostics[i]
            b := failed.diagnostics[i]
            c := all.diagnostics[i]
            want := Check_Issue.Disjoint_Literal_Comparison
            if i == 12 { want = .Assignment_Type_Mismatch }
            testing.expect(t, a.issue==want && b.issue==want && c.issue==want &&
                           a.byte_start==b.byte_start && a.byte_start==c.byte_start &&
                           a.byte_end==b.byte_end && a.byte_end==c.byte_end,
                           "independent trace modes preserve exact diagnostic spans")
        }
    }
    if len(all.comparisons)==12 && len(failed.comparisons)==12 {
        previous := -1
        for i in 0..<12 {
            c := all.comparisons[i]
            testing.expect(t, c.proof==.Disjoint_Literals && !c.overlaps &&
                           c.node_index>previous &&
                           failed.comparisons[i].node_index==c.node_index,
                           "each disjoint proof is a real source-ordered equality node")
            previous=c.node_index
        }
    }
}

@(test)
checker_boolean_identity_guards_mutation_and_join :: proc(t: ^testing.T) {
    input := "let flag: boolean = false; flag = 2 < 3;" +
             "let gate: boolean = false; gate = 4 > 2;" +
             "let out: boolean = false;" +
             "if (gate) {" +
             "  if (flag && true) { flag = 3 < 4; out = flag === false; }" +
             "  else { out = flag === false; }" +
             "  out = flag === true;" +
             "} else {" +
             "  if (!(false || flag)) { out = flag === false; }" +
             "  else { out = flag === true; }" +
             "}" +
             "out = flag === true;"
    v, ok := source.source_version_create(source.File_Id(846), 1, input)
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
                   len(all.comparisons)==6,
                   "nested identity guard facts are local to current branch")
    if len(all.comparisons)==6 {
        proofs := [?]Comparison_Proof{
            .Widened_Domain, .Same_Literal, .Widened_Domain,
            .Same_Literal, .Same_Literal, .Widened_Domain,
        }
        previous := -1
        for i in 0..<6 {
            c := all.comparisons[i]
            testing.expect(t, c.proof==proofs[i] && c.overlaps &&
                           c.node_index>previous,
                           "mutated then-arm and outer join cannot reuse stale fact")
            previous=c.node_index
        }
    }
}

@(test)
checker_boolean_nonidentity_guards_still_fail_closed :: proc(t: ^testing.T) {
    cases := [?]string{
        "if (flag && false) { out = flag === true; } else { out = flag === false; }",
        "if (true || flag) { out = flag === true; } else { out = flag === false; }",
    }
    for i in 0..<len(cases) {
        input := "let flag: boolean = false; flag = 2 < 3;" +
                 "let out: boolean = false;" + cases[i]
        v, ok := source.source_version_create(source.File_Id(847+i), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file_with_relations(&v, &ast, &bound, .All)
        testing.expect(t, ast.complete && bound.complete &&
                       checked.fatal && !checked.complete &&
                       len(checked.diagnostics)>0,
                       "non-identity short-circuit conditions cannot invent both arm facts")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}
