package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

// Evidence is observed from the SAME nested branches as the ordinary checker.
// No independently inferred comparison facts are inserted by this test.
@(test)
comparison_evidence_tracks_nested_mutation_and_both_joins :: proc(t: ^testing.T) {
    input := "let marker: boolean = false; marker = 2 < 3;" +
             "let gate: boolean = false; gate = 4 > 1;" +
             "let out: boolean = false;" +
             "if (marker) {" +
             "  out = marker === true;" +
             "  if (gate) {" +
             "    out = marker === true;" +
             "    marker = 3 > 1;" +
             "    out = marker === false;" +
             "  } else { out = marker === true; }" +
             "  out = marker === false;" +
             "} else { out = marker === false; }" +
             "out = marker === true;"
    v, ok := source.source_version_create(source.File_Id(833), 1, input)
    testing.expect(t, ok, "valid source")
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
                   len(ordinary.diagnostics)==0 &&
                   len(failed.diagnostics)==0 && len(all.diagnostics)==0,
                   "nested joins and mutation remain valid in all trace modes")
    testing.expect(t, len(ordinary.comparisons)==0 &&
                   len(ordinary.relations)==0 && len(failed.comparisons)==0 &&
                   len(all.comparisons)==7,
                   "only opt-in all trace captures seven overlap decisions")
    testing.expect(t, ordinary.checked_declarations==all.checked_declarations &&
                   ordinary.checked_assignments==all.checked_assignments &&
                   failed.checked_assignments==ordinary.checked_assignments,
                   "evidence cannot change checker work or flow results")
    if len(all.comparisons)==7 {
        proofs := [?]Comparison_Proof{
            .Same_Literal, .Same_Literal, .Widened_Domain,
            .Same_Literal, .Widened_Domain, .Same_Literal,
            .Widened_Domain,
        }
        previous := -1
        narrow_count := 0
        widened_count := 0
        for i in 0..<len(all.comparisons) {
            c := all.comparisons[i]
            testing.expect(t, c.proof==proofs[i] && c.overlaps &&
                           c.left==.Boolean && c.right==.Boolean &&
                           c.operator==.Equals_Equals_Equals,
                           "branch narrowing, mutation and joins select the correct proof")
            testing.expect(t, c.node_index>previous && c.node_index<len(ast.nodes) &&
                           ast.nodes[c.node_index].kind==.Binary,
                           "proof nodes preserve real postorder source location")
            node := ast.nodes[c.node_index]
            comparison_text := v.owned_text[node.byte_start:node.byte_end]
            testing.expect(t, comparison_text=="marker === true" ||
                           comparison_text=="marker === false",
                           "all proof spans identify real equality expressions")
            if c.proof==.Same_Literal { narrow_count += 1
            } else if c.proof==.Widened_Domain { widened_count += 1 }
            previous=c.node_index
        }
        testing.expect(t, narrow_count==4 && widened_count==3,
                       "no stale singleton proof survives a mutation or join")
    }
}

// The complementary witness is diagnostic-bearing: disjoint proofs must
// remain source ordered, while a mutation must restore broad-domain overlap.
@(test)
comparison_evidence_nested_disjointness_stays_in_its_branch :: proc(t: ^testing.T) {
    input := "let marker: boolean = false; marker = 2 < 3;" +
             "let gate: boolean = false; gate = 4 > 1;" +
             "let out: boolean = false;" +
             "if (marker) {" +
             "  out = marker === false;" +
             "  if (gate) { out = marker === false; }" +
             "  else { marker = 3 < 5; out = marker === false; }" +
             "  out = marker === false;" +
             "} else { out = marker === true; }" +
             "out = marker === false;"
    v, ok := source.source_version_create(source.File_Id(834), 1, input)
    testing.expect(t, ok, "valid source")
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
                   !ordinary.complete && !failed.complete && !all.complete &&
                   !ordinary.fatal && !failed.fatal && !all.fatal &&
                   len(ordinary.diagnostics)==3 &&
                   len(failed.diagnostics)==3 && len(all.diagnostics)==3,
                   "three supported disjoint comparison diagnostics survive tracing")
    if len(ordinary.diagnostics)==3 && len(failed.diagnostics)==3 &&
       len(all.diagnostics)==3 {
        for i in 0..<3 {
            a := ordinary.diagnostics[i]
            b := failed.diagnostics[i]
            c := all.diagnostics[i]
            testing.expect(t, a.issue==.Disjoint_Literal_Comparison &&
                           b.issue==a.issue && c.issue==a.issue &&
                           b.byte_start==a.byte_start &&
                           b.byte_end==a.byte_end &&
                           c.byte_start==a.byte_start &&
                           c.byte_end==a.byte_end,
                           "trace modes preserve exact internal diagnostic anchors")
        }
    }
    testing.expect(t, len(ordinary.comparisons)==0 &&
                   len(failed.comparisons)==3 && len(all.comparisons)==6,
                   "failure mode records only three real disjoint proofs")
    if len(all.comparisons)==6 && len(failed.comparisons)==3 {
        proofs := [?]Comparison_Proof{
            .Disjoint_Literals, .Disjoint_Literals, .Widened_Domain,
            .Widened_Domain, .Disjoint_Literals, .Widened_Domain,
        }
        previous := -1
        failed_index := 0
        for i in 0..<len(all.comparisons) {
            c := all.comparisons[i]
            testing.expect(t, c.proof==proofs[i] &&
                           c.overlaps==(c.proof==.Widened_Domain) &&
                           c.node_index>previous,
                           "each branch retains its actual disjoint/widened proof")
            if !c.overlaps {
                f := failed.comparisons[failed_index]
                testing.expect(t, f.node_index==c.node_index &&
                               f.proof==c.proof && !f.overlaps,
                               "failures-only trace is an ordered subset of all proofs")
                failed_index += 1
            }
            previous=c.node_index
        }
        testing.expect(t, failed_index==3, "all three failed decisions observed")
    }
}
