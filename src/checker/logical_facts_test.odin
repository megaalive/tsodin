package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

// Boolean-only logical operators return their operand values. Literal facts
// need a proof; an unknown operand may not be evaluated at runtime.
@(test)
checker_boolean_logical_facts_and_wide_domains :: proc(t: ^testing.T) {
    input := "const a = true && false; const b = false || true;" +
             "const c = !!true && (!false || false);" +
             "let gate: boolean = false; gate = 2 < 3;" +
             "const d = gate && false; const e = gate || true;" +
             "const f = gate && gate; const g = gate || gate;" +
             "const h = true && gate; const i = false || gate;" +
             "const j = gate && true; const k = gate || false;" +
             "const l = false && gate; const m = true || gate;" +
             "const testA = a === false; const testB = b === true;" +
             "const testC = c === true; const testD = d !== false;" +
             "const testE = e === true; const testF = f === true;" +
             "const testG = g !== false; const testH = h === true;" +
             "const testI = i === false; const testJ = j !== false;" +
             "const testK = k === true; const testL = l === false;" +
             "const testM = m === true;"
    v, ok := source.source_version_create(source.File_Id(841), 1, input)
    testing.expect(t, ok, "valid source")
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
                   !normal.fatal && !failed.fatal && !all.fatal &&
                   len(normal.diagnostics)==0 && len(all.diagnostics)==0 &&
                   len(normal.comparisons)==0 && len(failed.comparisons)==0 &&
                   len(all.comparisons)==13,
                   "all thirteen Boolean logical fact comparisons are supported")
    if len(all.comparisons)==13 {
        singleton := [?]bool{
            true,true,true,true,true,false,false,
            false,false,false,false,true,true,
        }
        previous := -1
        for i in 0..<13 {
            comparison := all.comparisons[i]
            want := Comparison_Proof.Widened_Domain
            if singleton[i] { want = .Same_Literal }
            testing.expect(t, comparison.proof==want && comparison.overlaps &&
                           comparison.left==.Boolean && comparison.right==.Boolean &&
                           comparison.node_index>previous,
                           "each Boolean logical result preserves its exact proof category")
            previous=comparison.node_index
        }
    }
    testing.expect(t, normal.checked_declarations==all.checked_declarations &&
                   normal.checked_assignments==all.checked_assignments &&
                   len(normal.relations)==0,
                   "normal checker has no evidence allocation or work drift")
}

@(test)
checker_boolean_logical_facts_diagnose_disjointness :: proc(t: ^testing.T) {
    input := "const a = true && false; const badA = a === true;" +
             "const b = false || true; const badB = b !== false;" +
             "const c = !!true && (!false || false);" +
             "const badC = c === false;" +
             "let gate: boolean = false; gate = 2 < 3;" +
             "const alwaysFalse = gate && false;" +
             "const badD = alwaysFalse === true;" +
             "const alwaysTrue = gate || true;" +
             "const badE = alwaysTrue === false;" +
             "const wrong: string = alwaysTrue;"
    v, ok := source.source_version_create(source.File_Id(842), 1, input)
    testing.expect(t, ok, "valid source")
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
                   len(normal.diagnostics)==6 && len(failed.diagnostics)==6 &&
                   len(all.diagnostics)==6 &&
                   len(normal.comparisons)==0 && len(failed.comparisons)==5 &&
                   len(all.comparisons)==5,
                   "five provably disjoint logical comparisons and one type mismatch")
    if len(normal.diagnostics)==6 {
        for i in 0..<6 {
            a := normal.diagnostics[i]
            b := failed.diagnostics[i]
            c := all.diagnostics[i]
            want := Check_Issue.Disjoint_Literal_Comparison
            if i == 5 { want = .Assignment_Type_Mismatch }
            testing.expect(t, a.issue==want && b.issue==want && c.issue==want &&
                           a.byte_start==b.byte_start && b.byte_start==c.byte_start &&
                           a.byte_end==b.byte_end && b.byte_end==c.byte_end,
                           "strict logical disjointness keeps source-ordered diagnostics")
        }
    }
    if len(all.comparisons)==5 {
        previous := -1
        for i in 0..<5 {
            c := all.comparisons[i]
            testing.expect(t, c.proof==.Disjoint_Literals && !c.overlaps &&
                           c.node_index>previous &&
                           failed.comparisons[i].node_index==c.node_index,
                           "no fake overlap is emitted for logically impossible comparisons")
            previous=c.node_index
        }
    }
}

@(test)
checker_boolean_logical_join_and_mutation_keep_true_facts :: proc(t: ^testing.T) {
    input := "let gate: boolean = false; gate = 2 < 3;" +
             "let output: boolean = false;" +
             "if (gate) {" +
             "  output = gate && false;" +
             "  output = output === false;" +
             "  gate = 4 > 2;" +
             "  output = gate || true;" +
             "  output = output === true;" +
             "} else {" +
             "  output = gate || true;" +
             "  output = output === true;" +
             "}" +
             "output = gate && gate;" +
             "output = output === false;"
    v, ok := source.source_version_create(source.File_Id(843), 1, input)
    testing.expect(t, ok, "source")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    normal := check_file(&v, &ast, &bound)
    defer report_destroy(&normal)
    traced := check_file_with_relations(&v, &ast, &bound, .All)
    defer report_destroy(&traced)
    testing.expect(t, ast.complete && bound.complete &&
                   normal.complete && traced.complete &&
                   len(normal.diagnostics)==0 && len(traced.diagnostics)==0 &&
                   len(normal.comparisons)==0 && len(traced.comparisons)==4 &&
                   normal.checked_assignments==traced.checked_assignments,
                   "mutation in one branch cannot leak singleton facts across join")
    if len(traced.comparisons)==4 {
        previous := -1
        for i in 0..<4 {
            c := traced.comparisons[i]
            want := Comparison_Proof.Same_Literal
            if i == 3 { want = .Widened_Domain }
            testing.expect(t, c.proof==want && c.overlaps &&
                           c.node_index>previous,
                           "logical singleton and post-join widened proofs are source ordered")
            previous=c.node_index
        }
    }
}
