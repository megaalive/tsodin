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


@(test)
primitive_checker_boolean_inference_and_type_errors :: proc(t: ^testing.T) {
    ok_text := "const enabled: boolean = true; let disabled = false; const flag: boolean = disabled;"
    v, valid := source.source_version_create(source.File_Id(612), 1, ok_text)
    testing.expect(t, valid, "valid boolean source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && checked.checked_declarations == 3,
                   "boolean literals and inferred local references pass")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)

    bad_text := "const flag: boolean = 1; const total: number = true;"
    bad, valid_bad := source.source_version_create(source.File_Id(613), 2, bad_text)
    testing.expect(t, valid_bad, "valid mismatch fixture bytes")
    bad_ast := parser.parse_expression_program(&bad, compat.ts7_profile())
    bad_bound := binder.bind_program(&bad, &bad_ast)
    mismatches := check_file(&bad, &bad_ast, &bad_bound)
    testing.expect(t, bad_ast.complete && bad_bound.complete &&
                   !mismatches.complete && !mismatches.fatal &&
                   len(mismatches.diagnostics) == 2 &&
                   mismatches.checked_declarations == 2,
                   "number-to-boolean and boolean-to-number both mismatch")
    testing.expect(t, mismatches.diagnostics[0].issue == .Assignment_Type_Mismatch &&
                   mismatches.diagnostics[1].issue == .Assignment_Type_Mismatch,
                   "mismatch kind matches existing narrow TS2322 mapper")
    testing.expect(t, bad_text[mismatches.diagnostics[0].byte_start:mismatches.diagnostics[0].byte_end] == "flag" &&
                   bad_text[mismatches.diagnostics[1].byte_start:mismatches.diagnostics[1].byte_end] == "total",
                   "mismatch spans attach to declaration names")
    report_destroy(&mismatches)
    binder.binding_report_destroy(&bad_bound)
    parser.syntax_report_destroy(&bad_ast)
    source.source_version_destroy(&bad)
}

@(test)
primitive_checker_rejects_unsupported_boolean_arithmetic :: proc(t: ^testing.T) {
    text := "const impossible = true + 1;"
    v, ok := source.source_version_create(source.File_Id(614), 1, text)
    testing.expect(t, ok, "valid source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, checked.fatal && !checked.complete &&
                   len(checked.diagnostics) == 1 &&
                   checked.diagnostics[0].issue == .Incompatible_Operator,
                   "boolean arithmetic must never be reported as valid")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}


@(test)
primitive_checker_comparisons_and_boolean_logic :: proc(t: ^testing.T) {
    valid_sources := [?]string{
        "const less: boolean = 1 + 2 < 4; const max: boolean = 5 >= 4; const either = !false || true && false;",
        "const n: number = 2; const equal: boolean = n === n; const different: boolean = 1 !== 1;",
        "const label: string = 'hi'; const same = label === label; const boolEqual = true === true;",
    }
    for input in valid_sources {
        v, ok := source.source_version_create(source.File_Id(713), 1, input)
        testing.expect(t, ok, "valid source created")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics) == 0,
                       "bounded comparisons/equality/boolean logic accepted")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_refuses_unproven_literal_overlap :: proc(t: ^testing.T) {
    bad_sources := [?]string{
        "const bad = 1 && true;",
        "const bad = !2;",
        "const bad = 'hi' < 'there';",
    }
    for input in bad_sources {
        v, ok := source.source_version_create(source.File_Id(714), 1, input)
        testing.expect(t, ok, "valid source created")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics) > 0 &&
                       checked.diagnostics[0].issue == .Incompatible_Operator,
                       "unsupported semantic case must fail closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}


@(test)
primitive_checker_literal_value_identity_and_disjoint_diagnostics :: proc(t: ^testing.T) {
    good := "const sameText: boolean = 'same' === \"same\"; const sameNumber = 3 !== 3; const sameFlag = false === false;"
    v, ok := source.source_version_create(source.File_Id(715), 1, good)
    testing.expect(t, ok, "valid UTF-8 literal source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   len(checked.diagnostics) == 0 && checked.checked_declarations == 3,
                   "equal literal values preserve primitive boolean result")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)

    bad := "const a = 1 === 2; const b = true !== false; const c = 'red' === \"blue\";"
    v2, ok2 := source.source_version_create(source.File_Id(716), 1, bad)
    testing.expect(t, ok2, "valid mismatch source")
    ast2 := parser.parse_expression_program(&v2, compat.ts7_profile())
    bound2 := binder.bind_program(&v2, &ast2)
    checked2 := check_file(&v2, &ast2, &bound2)
    testing.expect(t, ast2.complete && bound2.complete && !checked2.complete &&
                   !checked2.fatal && len(checked2.diagnostics) == 3 &&
                   checked2.checked_declarations == 3,
                   "all disjoint literal comparisons reported without fatal stop")
    for issue in checked2.diagnostics {
        testing.expect(t, issue.issue == .Disjoint_Literal_Comparison &&
                       issue.byte_start < issue.byte_end,
                       "disjoint literal comparison has a source-backed span")
    }
    testing.expect(t, bad[checked2.diagnostics[0].byte_start:checked2.diagnostics[0].byte_end] == "1 === 2" &&
                   bad[checked2.diagnostics[1].byte_start:checked2.diagnostics[1].byte_end] == "true !== false" &&
                   bad[checked2.diagnostics[2].byte_start:checked2.diagnostics[2].byte_end] == "'red' === \"blue\"",
                   "diagnostics cover comparison expressions")
    report_destroy(&checked2)
    binder.binding_report_destroy(&bound2)
    parser.syntax_report_destroy(&ast2)
    source.source_version_destroy(&v2)
}


@(test)
primitive_checker_const_literal_alias_provenance :: proc(t: ^testing.T) {
    valid_sources := [?]string {
        "const count = 7; const alias = count; const same = 7; const equal: boolean = alias === same;",
        "const text = 'same'; const copy = text; const equal: boolean = copy === \"same\";",
        "const yes = true; const copy = yes; const equal: boolean = copy !== true;",
    }
    for input in valid_sources {
        v, ok := source.source_version_create(source.File_Id(720), 1, input)
        testing.expect(t, ok, "valid constant alias source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete &&
                       checked.complete && !checked.fatal &&
                       len(checked.diagnostics) == 0,
                       "identical inferred const literal values are accepted")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }

    input := "const low = 1; const high = 2; const copy = low; const bad = copy === high;" +
             "const yes = true; const no = false; const bad2 = yes !== no;"
    v, ok := source.source_version_create(source.File_Id(721), 1, input)
    testing.expect(t, ok, "disjoint constant alias source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete &&
                   !checked.complete && !checked.fatal &&
                   len(checked.diagnostics) == 2 &&
                   checked.checked_declarations == 7,
                   "disjoint aliases produce nonfatal diagnostics and continue")
    for issue in checked.diagnostics {
        testing.expect(t, issue.issue == .Disjoint_Literal_Comparison,
                       "distinct const literals map to disjoint comparison")
    }
    testing.expect(t, input[checked.diagnostics[0].byte_start:checked.diagnostics[0].byte_end] == "copy === high" &&
                   input[checked.diagnostics[1].byte_start:checked.diagnostics[1].byte_end] == "yes !== no",
                   "diagnostics preserve comparison source spans")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_widens_mutable_and_annotated_primitive_domains :: proc(t: ^testing.T) {
    cases := [?]string {
        "let flexible = 1; const result = flexible === 2;",
        "const widened: number = 1; const result = widened === 2;",
        "const typed: string = 'left'; const result = typed !== 'right';",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(722), 1, input)
        testing.expect(t, ok, "valid input")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete &&
                       !checked.fatal && checked.complete &&
                       len(checked.diagnostics) == 0,
                       "number/string domains widen without inventing literal facts")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}


@(test)
primitive_checker_proves_disjoint_base_domains_without_literal_flow :: proc(t: ^testing.T) {
    input := "const count: number = 1; const label: string = '1';" +
             "const different = count === label;" +
             "let enabled: boolean = true; const total = 2 + 2;" +
             "const different2 = enabled !== total;" +
             "const badAssignment: string = count < total;"
    v, ok := source.source_version_create(source.File_Id(723), 1, input)
    testing.expect(t, ok, "cross-primitive source is valid")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete &&
                   !checked.complete && !checked.fatal &&
                   checked.checked_declarations == 7 &&
                   len(checked.diagnostics) == 3,
                   "checker reports both domain disjointness and assignment mismatch")
    testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Primitive_Domains &&
                   checked.diagnostics[1].issue == .Disjoint_Primitive_Domains &&
                   checked.diagnostics[2].issue == .Assignment_Type_Mismatch,
                   "stable, source-ordered internal issue IDs")
    testing.expect(t, input[checked.diagnostics[0].byte_start:checked.diagnostics[0].byte_end] == "count === label" &&
                   input[checked.diagnostics[1].byte_start:checked.diagnostics[1].byte_end] == "enabled !== total" &&
                   input[checked.diagnostics[2].byte_start:checked.diagnostics[2].byte_end] == "badAssignment",
                   "full expression spans and declaration-name mismatch span")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_accepts_annotated_wide_same_domain_overlap :: proc(t: ^testing.T) {
    input := "const a: number = 1; const b: number = 2; const uncertain = a === b;"
    v, ok := source.source_version_create(source.File_Id(724), 1, input)
    testing.expect(t, ok, "valid source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 0,
                   "explicit number annotations provide wide same-base overlap")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}


@(test)
primitive_checker_computed_wide_domains :: proc(t: ^testing.T) {
    input := "const total = 1 + 2; const alias = total; const check = alias === 9;" +
             "const text = 'a' + 'b'; const copy = text; const textCheck = copy !== 'z';" +
             "const greater = 3 > 1; const flag = greater; const flagCheck = flag === false;"
    v, ok := source.source_version_create(source.File_Id(725), 1, input)
    testing.expect(t, ok, "valid source snapshot")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && checked.checked_declarations == 9 &&
                   len(checked.diagnostics) == 0,
                   "widened numeric, string and comparison results pass through const aliases")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_wide_domains_preserve_disjointness :: proc(t: ^testing.T) {
    input := "const num = 1 + 2; const text = 'a' + 'b'; const bad = num === text;" +
             "const flag = 2 < 3; const bad2 = flag !== num;" +
             "const first = 1; const second = 2; const bad3 = first === second;" +
             "const wrong: string = num;"
    v, ok := source.source_version_create(source.File_Id(726), 1, input)
    testing.expect(t, ok, "valid source snapshot")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete &&
                   !checked.complete && !checked.fatal &&
                   checked.checked_declarations == 9 &&
                   len(checked.diagnostics) == 4,
                   "all four errors stay visible after introducing widened facts")
    if len(checked.diagnostics) == 4 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Primitive_Domains &&
                       checked.diagnostics[1].issue == .Disjoint_Primitive_Domains &&
                       checked.diagnostics[2].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[3].issue == .Assignment_Type_Mismatch,
                       "widened tracking does not suppress independent TS2367/TS2322 candidates")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_mutable_computation_remains_wide :: proc(t: ^testing.T) {
    input := "let mutable = 1 + 2; const uncertain = mutable === 7;"
    v, ok := source.source_version_create(source.File_Id(727), 1, input)
    testing.expect(t, ok, "valid source snapshot")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 0,
                   "computed mutable numbers have a wide domain, not a literal identity")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}


@(test)
primitive_checker_straightline_assignment_flow :: proc(t: ^testing.T) {
    input := "let count: number = 1; count = 2; const same = count === 2;" +
             "count = 1 + 2; const broad = count === 9;" +
             "let label: string = 'old'; label = 'new'; const sameText = label === 'new';"
    v, ok := source.source_version_create(source.File_Id(733), 1, input)
    testing.expect(t, ok, "valid UTF-8 source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && checked.checked_declarations == 5 &&
                   checked.checked_assignments == 3 &&
                   len(checked.diagnostics) == 0,
                   "assignment transfers update current literal and widened facts")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_assignment_errors_continue_without_false_success :: proc(t: ^testing.T) {
    input := "let count: number = 1; count = 2; const possible = count === 3;" +
             "count = 4; const possible2 = count !== 2;" +
             "const low = 1; const high = 2; const bad = low === high;" +
             "count = 'wrong';"
    v, ok := source.source_version_create(source.File_Id(734), 1, input)
    testing.expect(t, ok, "source created")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete &&
                   !checked.complete && !checked.fatal &&
                   checked.checked_declarations == 6 &&
                   checked.checked_assignments == 3 &&
                   len(checked.diagnostics) == 2,
                   "widened let comparisons stay valid; disjoint const and bad assignment fail")
    if len(checked.diagnostics) == 2 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[1].issue == .Assignment_Type_Mismatch,
                       "existing TS2367/TS2322 candidate kinds are preserved")
        testing.expect(t, input[checked.diagnostics[0].byte_start:checked.diagnostics[0].byte_end] == "low === high" &&
                       input[checked.diagnostics[1].byte_start:checked.diagnostics[1].byte_end] == "count",
                       "comparison and assignment RHS diagnostics have real source spans")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_refuses_unsupported_assignment_targets :: proc(t: ^testing.T) {
    cases := [?]string {
        "const frozen = 1; frozen = 2;",
        "var legacy = 1; legacy = 2;",
        "let unassigned: number; unassigned = 2;",
        "later = 1; let later = 2;",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(735), 1, input)
        testing.expect(t, ok, "valid input")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, !checked.complete && checked.fatal &&
                       len(checked.diagnostics) > 0 &&
                       checked.diagnostics[0].issue == .Unsupported_Assignment_Target,
                       "unsafe mutable/control-flow target must fail closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_conditional_narrowing_and_join :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let verdict: boolean = false;" +
             "if (code === 2) { verdict = code === 2; } else { verdict = code === 3; }" +
             "const merged: boolean = verdict === true; const restored = code === 9;"
    v, ok := source.source_version_create(source.File_Id(742), 1, input)
    testing.expect(t, ok, "snapshot accepted")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && checked.checked_declarations == 4 &&
                   checked.checked_assignments == 3 && len(checked.diagnostics) == 0,
                   "true arm narrows; false arm restores entry; merged facts remain broad")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_conditional_disjoint_and_assignment_error :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let verdict: boolean = false;" +
             "if (code === 2) { verdict = code === 3; } else { verdict = 'wrong'; }" +
             "const after = code === 4;"
    v, ok := source.source_version_create(source.File_Id(743), 1, input)
    testing.expect(t, ok, "snapshot accepted")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 2,
                   "both branch-local diagnostics are retained without false success")
    if len(checked.diagnostics) == 2 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[1].issue == .Assignment_Type_Mismatch &&
                       input[checked.diagnostics[0].byte_start:checked.diagnostics[0].byte_end] == "code === 3" &&
                       input[checked.diagnostics[1].byte_start:checked.diagnostics[1].byte_end] == "verdict",
                       "candidate TS2367 and TS2322 locations are source-backed")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_conditional_unproved_guard_is_fatal :: proc(t: ^testing.T) {
    cases := [?]string {
        "let code: number = 1; code = 1 + 2; if (code > 2) { code = 3; } else { code = 4; }",
        "let code: number = 1; code = 1 + 2; if (code !== code) { code = 3; } else { code = 4; }",
        "let code: number = 1; code = 1 + 2; if (code !== 2 + 1) { code = 3; } else { code = 4; }",
        "let code: number = 1; code = 1 + 2; if (code === code) { code = 3; } else { code = 4; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(744), 1, input)
        testing.expect(t, ok, "snapshot accepted")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics) > 0 &&
                       checked.diagnostics[0].issue == .Unsupported_Condition,
                       "unproved guard fails closed without evaluating branch mutations")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_negative_guard_else_narrowing :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let verdict: boolean = false;" +
             "if (code !== 2) { verdict = code === 2; } else { verdict = code === 2; }" +
             "const merged: boolean = verdict === true; const restored = code === 9;"
    v, ok := source.source_version_create(source.File_Id(745), 1, input)
    testing.expect(t, ok, "snapshot accepted")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && checked.checked_declarations == 4 &&
                   checked.checked_assignments == 3 && len(checked.diagnostics) == 0,
                   "negative true arm remains wide, else is exact, join restores broad")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_negative_guard_else_errors :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let verdict: boolean = false;" +
             "if (code !== 2) { verdict = code === 3; }" +
             "else { verdict = code === 3; verdict = 'bad'; } const after = code === 4;"
    v, ok := source.source_version_create(source.File_Id(746), 1, input)
    testing.expect(t, ok, "snapshot accepted")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 2,
                   "negative else path emits disjoint and assignment diagnostics")
    if len(checked.diagnostics) == 2 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[1].issue == .Assignment_Type_Mismatch &&
                       input[checked.diagnostics[0].byte_start:checked.diagnostics[0].byte_end] == "code === 3" &&
                       input[checked.diagnostics[1].byte_start:checked.diagnostics[1].byte_end] == "verdict",
                       "candidate code and UTF-16 spans remain source-backed")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_negative_guard_assignment_invalidates_else_fact :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let verdict: boolean = false;" +
             "if (code !== 2) { verdict = code === 2; }" +
             "else { code = 9; verdict = code === 3; } const after = code === 7;"
    v, ok := source.source_version_create(source.File_Id(747), 1, input)
    testing.expect(t, ok, "snapshot accepted")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 0 &&
                   checked.checked_declarations == 3 && checked.checked_assignments == 4,
                   "assignment widens else and join; no stale singleton survives")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_negated_and_boolean_guard_valid :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2; let out: boolean = false;" +
        "if (!(n === 2)) { out = n === 3; } else { out = n === 2; }" +
        "const restored: boolean = n === 9;",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag) { out = flag === true; } else { out = flag === false; }" +
        "if (!flag) { out = flag === false; } else { out = flag === true; }" +
        "const after: boolean = flag === false;",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag === false) { out = flag === false; } else { out = flag === true; }" +
        "if (!!(n !== 2)) { out = n === 3; } else { out = n === 2; }",
        "let n: number = 1; n = 1 + 2; let out: boolean = false;" +
        "if (!(n !== 2)) { out = n === 2; } else { out = n === 3; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(748), 1, input)
        testing.expect(t, ok, "snapshot")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics) == 0,
                       "proven boolean/negated paths stay accepted")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_boolean_guard_disjoint_paths :: proc(t: ^testing.T) {
    input := "let n: number = 1; n = 1 + 2; let ready: boolean = false;" +
             "ready = n === 2; let result: boolean = false;" +
             "if (ready) { result = ready === false; } else { result = ready === true; }"
    v, ok := source.source_version_create(source.File_Id(749), 1, input)
    testing.expect(t, ok, "snapshot")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 2,
                   "each boolean path independently proves TS2367 candidates")
    if len(checked.diagnostics) == 2 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[1].issue == .Disjoint_Literal_Comparison,
                       "boolean synthetics compare to source literals with stable issue IDs")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_negated_condition_fail_closed :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2; if (!(n > 2)) { n = 3; } else { n = 4; }",
        "let n: number = 1; n = 1 + 2; if (!(n === n)) { n = 3; } else { n = 4; }",
        "let n: number = 1; n = 1 + 2; if (!(2 === n)) { n = 3; } else { n = 4; }",
        "let n: number = 1; n = 1 + 2; if (!(n === 2 && true)) { n = 3; } else { n = 4; }",
        "let n: number = 1; n = 1 + 2; if (!!(n !== 2 || false)) { n = 3; } else { n = 4; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(750), 1, input)
        testing.expect(t, ok, "snapshot")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, !checked.complete && checked.fatal &&
                       len(checked.diagnostics) > 0 &&
                       checked.diagnostics[0].issue == .Unsupported_Condition,
                       "unproved compound/reversed guard cannot succeed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_nested_two_levels_preserve_parent_narrowing :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let ready: boolean = false;" +
             "ready = code === 2; let result: boolean = false;" +
             "if (code === 2) {" +
             "  if (ready) { result = code === 2; result = ready === true; }" +
             "  else { result = code === 2; result = ready === false; }" +
             "  result = code === 2;" +
             "} else {" +
             "  if (!ready) { result = ready === false; }" +
             "  else { result = ready === true; }" +
             "  result = code === 9;" +
             "} const after: boolean = code === 4;"
    v, ok := source.source_version_create(source.File_Id(752), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 0 &&
                   checked.checked_declarations == 4 &&
                   checked.checked_assignments == 10,
                   "child joins keep parent code literal and do not leak ready facts")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_nested_diagnostics_are_path_local :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let ready: boolean = false;" +
             "ready = code === 2; let result: boolean = false;" +
             "if (code === 2) {" +
             "  if (ready) { result = code === 3; result = ready === false; }" +
             "  else { result = code === 4; }" +
             "} else {" +
             "  if (!ready) { result = ready === true; }" +
             "  else { result = 'wrong'; }" +
             "} const after: boolean = code === 9;"
    v, ok := source.source_version_create(source.File_Id(753), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && checked.checked_declarations == 4 &&
                   len(checked.diagnostics) == 5,
                   "four child-local disjoint facts and one assignment mismatch")
    if len(checked.diagnostics) == 5 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[1].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[2].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[3].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[4].issue == .Assignment_Type_Mismatch,
                       "nested path diagnostics retain stable candidate code ordering")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_nested_mutation_invalidates_parent_fact :: proc(t: ^testing.T) {
    input := "let code: number = 1; code = 1 + 2; let ready: boolean = false;" +
             "ready = code === 2; let result: boolean = false;" +
             "if (code === 2) {" +
             "  if (ready) { code = 7; result = code === 3; }" +
             "  else { result = code === 2; }" +
             "  result = code === 4;" +
             "} else { result = code === 9; }"
    v, ok := source.source_version_create(source.File_Id(754), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 0,
                   "child mutation widens parent then arm and leaves else independent")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_compound_short_circuit_facts :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2; let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3; let out: boolean = false;" +
        "if (a && b) { out = a === true; out = b === true; } else { out = a === b; }" +
        "const after: boolean = a === false;",
        "let n: number = 1; n = 1 + 2; let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3; let out: boolean = false;" +
        "if (a || b) { out = a === false; } else { out = a === false; out = b === false; }",
        "let n: number = 1; n = 1 + 2; let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3; let out: boolean = false;" +
        "if (!(a && !b)) { out = a === false; } else {" +
        " out = a === true; out = b === false; a = n === 2; out = a === true; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(760), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics) == 0,
                       "pure independent guards yield only entailed facts")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_compound_guard_disjoint_diagnostics :: proc(t: ^testing.T) {
    input := "let n: number = 1; n = 1 + 2; let a: boolean = false; a = n === 2;" +
             "let b: boolean = false; b = n === 3; let out: boolean = false;" +
             "if (a && b) { out = a === false; out = b === false; } else { out = 'bad'; }" +
             "if (a || b) { out = a === false; } else {" +
             " out = a === true; out = b === true; }"
    v, ok := source.source_version_create(source.File_Id(761), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics) == 5,
                   "AND true / OR false prove four disjoint comparisons")
    if len(checked.diagnostics) == 5 {
        testing.expect(t,
            checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
            checked.diagnostics[1].issue == .Disjoint_Literal_Comparison &&
            checked.diagnostics[2].issue == .Assignment_Type_Mismatch &&
            checked.diagnostics[3].issue == .Disjoint_Literal_Comparison &&
            checked.diagnostics[4].issue == .Disjoint_Literal_Comparison,
            "compound narrowing respects ordered TS2367 and TS2322 candidates")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_compound_guard_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3; let out: boolean = false;"
    cases := [?]string {
        prefix + "if (a && !a) { out = a; } else { out = false; }",
        prefix + "if (a || !a) { out = true; } else { out = !a; }",
        // M4-G5F8L accepts a&&true / a||false as identities; these
        // nonidentity constants remain unsafe for two-arm narrowing.
        prefix + "if (a && false) { out = true; } else { out = false; }",
        prefix + "if (a || true) { out = true; } else { out = false; }",
        prefix + "if (a && (b || a)) { out = true; } else { out = false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(762), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics) > 0 &&
                       checked.diagnostics[0].issue == .Unsupported_Condition,
                       "unproved or repeated compound guard stays fail-closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_rhs_conditional_context_and_idempotent_guards :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag && flag) { out = flag === true; } else { out = flag === false; }" +
        "if (flag || flag) { out = flag === true; } else { out = flag === false; }",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag && (flag === true)) { out = flag === true; }" +
        "else { out = flag === false; }",
        "let n: number = 1; n = 1 + 2; let out: boolean = false;" +
        "if (n === 2 && n === 2) { out = n === 2; }" +
        "else { out = n === 4; }",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (!(flag && flag)) { out = flag === false; }" +
        "else { out = flag === true; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(770), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics) == 0,
                       "RHS context remains temporary and repeated guards join soundly")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_rhs_context_disjoint_and_contradiction_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let flag: boolean = false; flag = n === 2;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix + "if (flag && (flag === false)) { out = true; } else { out = false; }",
        prefix + "if (flag && !flag) { out = flag; } else { out = false; }",
        prefix + "if (flag || !flag) { out = true; } else { out = !flag; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(771), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics) > 0,
                       "unreachable and contradictory compound branches remain unsupported")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_boolean_contradiction_empty_arm_and_live_join :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag && !flag) { } else { out = flag === false; }" +
        "if (flag || !flag) { out = flag === true; } else { }" +
        "const after: boolean = flag === false;",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (!(flag && !flag)) { out = flag === true; } else { }" +
        "if (!(flag || !flag)) { } else { out = flag === false; }",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag && !flag) { } else { flag = n === 3; }" +
        "if (flag || !flag) { flag = n === 4; } else { }" +
        "const restored: boolean = flag === false;",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let other: boolean = false; other = n === 3;" +
        "let out: boolean = false;" +
        "if (flag) {" +
        "if (other && !other) { } else { out = flag === true; }" +
        "if (other || !other) { out = flag === true; } else { }" +
        "} else { out = flag === false; }" +
        "const after: boolean = flag === false;",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(780), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics) == 0,
                       "empty dead arms are not merged; live branch flow survives")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_contradiction_dead_arm_statements_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
              "flag = n === 2; let out: boolean = false;"
    cases := [?]string {
        prefix + "if (flag && !flag) { out = flag; } else { }",
        prefix + "if (flag || !flag) { } else { out = flag; }",
        prefix + "if (!(flag && !flag)) { } else { out = !flag; }",
        prefix + "if (!(flag || !flag)) { out = !flag; } else { }",
        prefix + "if (flag && !flag) {" +
        "if (flag) { out = true; } else { out = false; }" +
        "} else { out = true; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(781), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics)>0 &&
                       checked.diagnostics[0].issue == .Unsupported_Condition,
                       "never-state semantics are not invented for dead-arm statements")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_typechecks_dead_arm_literal_assignments_without_transfer :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let out: boolean = false;" +
        "if (flag && !flag) { out = true; out = false; }" +
        "else { out = flag === false; }" +
        "if (flag || !flag) { out = flag === true; }" +
        "else { out = true; }" +
        "const after: boolean = flag === false;",
        "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
        "flag = n === 2; let other: boolean = false;" +
        "other = n === 3; let out: boolean = false;" +
        "if (flag) {" +
        "if (other && !other) { out = true; } else { out = flag === true; }" +
        "} else { out = flag === false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(790), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics)==0,
                       "direct dead-arm literals are checked without leaking assignments")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_dead_arm_mismatch_is_not_hidden :: proc(t: ^testing.T) {
    input := "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
             "flag = n === 2; let out: boolean = false;" +
             "if (flag && !flag) { out = 'dead error'; } else { out = 'live error'; }" +
             "if (flag || !flag) { out = true; } else { out = 12; }"
    v, ok := source.source_version_create(source.File_Id(791), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==3,
                   "dead and live primitive mismatches each preserve TS2322 candidate")
    for d in checked.diagnostics {
        testing.expect(t, d.issue == .Assignment_Type_Mismatch,
                       "dead-arm type mismatches are not suppressed")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_dead_arm_unsupported_semantics_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2; let flag: boolean = false;" +
              "flag = n === 2; let out: boolean = false;"
    cases := [?]string {
        prefix + "if (flag && !flag) { flag = true; } else { out = true; }",
        prefix + "if (flag && !flag) { out = flag; } else { out = false; }",
        prefix + "if (flag || !flag) { out = true; } else { out = !flag; }",
        prefix + "if (flag && !flag) {" +
        "if (flag) { out = true; } else { out = false; }" +
        "} else { out = true; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(792), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics)>0 &&
                       checked.diagnostics[0].issue == .Unsupported_Condition,
                       "unproved unreachable semantics cannot become success")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_three_independent_boolean_guard_paths :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2;" +
        "let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3;" +
        "let c: boolean = false; c = n === 4;" +
        "let out: boolean = false;" +
        "if (a && b && c) {" +
        "out = a === true; out = b === true; out = c === true;" +
        "} else { out = a === false; }" +
        "if (a || b || c) { out = a === false; }" +
        "else { out = a === false; out = b === false; out = c === false; }" +
        "const after: boolean = c === false;",
        "let n: number = 1; n = 1 + 2;" +
        "let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3;" +
        "let c: boolean = false; c = n === 4;" +
        "let out: boolean = false;" +
        "if (!(a && !b && c)) { out = b === true; }" +
        "else { out = a === true; out = b === false; out = c === true; }" +
        "if (!(a || b || c)) {" +
        "out = a === false; out = b === false; out = c === false;" +
        "} else { out = b === true; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(800), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics)==0,
                       "three independent pure names narrow only decisive arm")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_three_guard_fail_closed_boundaries :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3;" +
              "let c: boolean = false; c = n === 4;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix + "if (a && b && a) { out = true; } else { out = false; }",
        prefix + "if (a || b || b) { out = true; } else { out = false; }",
        prefix + "if (a && (b || (c && a))) { out = true; } else { out = false; }",
        prefix + "if (a && b && (c === true)) { out = true; } else { out = false; }",
        prefix + "if (a && b && c && a) { out = true; } else { out = false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(801), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics)>0,
                       "repeated, mixed, computed or four-way chains stay unsupported")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_three_way_guard_nested_mutation_join :: proc(t: ^testing.T) {
    input := "let n: number = 1; n = 1 + 2;" +
             "let a: boolean = false; a = n === 2;" +
             "let b: boolean = false; b = n === 3;" +
             "let c: boolean = false; c = n === 4;" +
             "let d: boolean = false; d = n === 5;" +
             "let out: boolean = false;" +
             "if (a && b && c) {" +
             "if (d) { out = a === true; out = c === true; b = n === 7; }" +
             "else { out = b === true; out = c === true; }" +
             "out = c === true; out = b === false;" +
             "} else { out = a === false; }" +
             "const after: boolean = a === false;"
    v, ok := source.source_version_create(source.File_Id(810), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==0,
                   "inner mutation invalidates b but retains a/c facts in outer then")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_three_way_guard_nested_diagnostics :: proc(t: ^testing.T) {
    input := "let n: number = 1; n = 1 + 2;" +
             "let a: boolean = false; a = n === 2;" +
             "let b: boolean = false; b = n === 3;" +
             "let c: boolean = false; c = n === 4;" +
             "let d: boolean = false; d = n === 5;" +
             "let out: boolean = false;" +
             "if (a && b && c) {" +
             "if (d) { out = a === false; }" +
             "else { out = c === false; }" +
             "out = c === false;" +
             "} else { out = 'wrong'; }" +
             "if (a || b || c) { out = a === false; }" +
             "else { out = b === true; }"
    v, ok := source.source_version_create(source.File_Id(811), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==5,
                   "nested path-local disjoint comparisons and mismatch remain visible")
    if len(checked.diagnostics) == 5 {
        testing.expect(t,
            checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
            checked.diagnostics[1].issue == .Disjoint_Literal_Comparison &&
            checked.diagnostics[2].issue == .Disjoint_Literal_Comparison &&
            checked.diagnostics[3].issue == .Assignment_Type_Mismatch &&
            checked.diagnostics[4].issue == .Disjoint_Literal_Comparison,
            "three-way nested error code order stays source-backed")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_mixed_rhs_boolean_guard_decisive_facts :: proc(t: ^testing.T) {
    cases := [?]string {
        "let n: number = 1; n = 1 + 2;" +
        "let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3;" +
        "let c: boolean = false; c = n === 4;" +
        "let out: boolean = false;" +
        "if (a && (b || c)) { out = a === true; out = b === false; }" +
        "else { out = a === false; }" +
        "if (a || (b && c)) { out = a === false; }" +
        "else { out = a === false; out = c === false; }" +
        "const after: boolean = a === false;",
        "let n: number = 1; n = 1 + 2;" +
        "let a: boolean = false; a = n === 2;" +
        "let b: boolean = false; b = n === 3;" +
        "let c: boolean = false; c = n === 4;" +
        "let out: boolean = false;" +
        "if (!(a && (b || c))) { out = a === false; }" +
        "else { out = a === true; }" +
        "if (!(a || (b && c))) { out = a === false; }" +
        "else { out = b === false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(820), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics)==0,
                       "only outer left Boolean is entailed by mixed RHS formula")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_mixed_rhs_boolean_guard_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3;" +
              "let c: boolean = false; c = n === 4;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix + "if (a && (b || a)) { out = true; } else { out = false; }",
        prefix + "if (a || (b && b)) { out = true; } else { out = false; }",
        prefix + "if (a && (b || (c && a))) { out = true; } else { out = false; }",
        prefix + "if ((a || (b && c)) && a) { out = true; } else { out = false; }",
        prefix + "if (a && (b || true)) { out = true; } else { out = false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(821), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics)>0,
                       "unproved, repeated, mixed-left or computed guards remain unsupported")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_mixed_left_decisive_facts :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3;" +
              "let c: boolean = false; c = n === 4;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix +
        "if ((a && b) || c) { out = a === false; out = c === false; }" +
        "else { out = c === false; out = b === true; }" +
        "if ((a || b) && c) { out = c === true; out = a === false; }" +
        "else { out = c === true; out = a === true; }" +
        "const after: boolean = c === true;",
        prefix +
        "if (!((a && b) || c)) { out = c === false; }" +
        "else { out = a === true; out = c === true; }" +
        "if (!((a || b) && c)) { out = c === false; }" +
        "else { out = c === true; out = b === false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(822), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics)==0,
                       "only the rightmost Boolean is proven on a decisive arm")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_mixed_left_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3;" +
              "let c: boolean = false; c = n === 4;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix + "if ((a && a) || c) { out = true; } else { out = false; }",
        prefix + "if ((a || b) && a) { out = true; } else { out = false; }",
        prefix + "if ((!a && b) || c) { out = true; } else { out = false; }",
        prefix + "if ((a && (b || c)) || b) { out = true; } else { out = false; }",
        prefix + "if ((a && b) || (n === 4)) { out = true; } else { out = false; }",
        prefix + "a = true; if ((a && b) || c) { out = true; } else { out = false; }",
        prefix + "c = false; if ((a || b) && c) { out = true; } else { out = false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(823), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics)>0,
                       "repeated, negated, computed, nested or non-wide guards fail closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}


@(test)
primitive_checker_mixed_nested_mutation_join :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3;" +
              "let c: boolean = false; c = n === 4;" +
              "let d: boolean = false; d = n === 5;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix +
        "if ((a && b) || c) {" +
        "if (d) { c = n === 7; } else { out = a === true; }" +
        "out = c === false;" +
        "} else {" +
        "if (d) { out = c === false; c = n === 8; }" +
        "else { out = c === false; }" +
        "out = c === true;" +
        "}" +
        "if ((a || b) && c) {" +
        "if (d) { out = c === true; c = n === 9; }" +
        "else { out = c === true; }" +
        "out = c === false;" +
        "} else { out = c === false; }",
        prefix +
        "if (!(a && (b || c))) {" +
        "if (d) { out = a === false; } else { out = b === true; }" +
        "} else {" +
        "if (d) { out = a === true; a = n === 10; }" +
        "else { out = a === true; }" +
        "out = a === false;" +
        "}" +
        "if (!((a || b) && c)) { out = a === false; }" +
        "else {" +
        "if (d) { out = c === true; c = n === 11; }" +
        "else { out = c === true; }" +
        "out = c === false;" +
        "}",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(824), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.complete &&
                       !checked.fatal && len(checked.diagnostics)==0,
                       "mixed parent facts survive child splits and widen after mutation")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}

@(test)
primitive_checker_mixed_nested_source_order_diagnostics :: proc(t: ^testing.T) {
    input := "let n: number = 1; n = 1 + 2;" +
             "let a: boolean = false; a = n === 2;" +
             "let b: boolean = false; b = n === 3;" +
             "let c: boolean = false; c = n === 4;" +
             "let d: boolean = false; d = n === 5;" +
             "let out: boolean = false;" +
             "if ((a && b) || c) { out = b === false; } else {" +
             "if (d) { out = c === true; } else { out = c === true; }" +
             "out = c === true;" +
             "}" +
             "if ((a || b) && c) {" +
             "if (d) { out = c === false; }" +
             "else { c = n === 7; out = c === false; }" +
             "out = c === false;" +
             "} else { out = 'bad'; }" +
             "if (!(a && (b || c))) { out = a === true; }" +
             "else { if (d) { out = a === false; } else { out = a === false; } }" +
             "if (!((a && b) || c)) {" +
             "if (d) { out = c === true; } else { out = c === true; }" +
             "} else { out = a === true; }"
    v, ok := source.source_version_create(source.File_Id(825), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==9,
                   "child-local, post-child and negated parent facts retain 9 errors")
    if len(checked.diagnostics) == 9 {
        for i in 0..<9 {
            expected := Check_Issue.Disjoint_Literal_Comparison
            if i == 4 { expected = .Assignment_Type_Mismatch }
            testing.expect(t, checked.diagnostics[i].issue == expected,
                           "mixed nested disjointness and mismatch retain lexical order")
        }
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_mixed_nested_fail_closed :: proc(t: ^testing.T) {
    prefix :: "let n: number = 1; n = 1 + 2;" +
              "let a: boolean = false; a = n === 2;" +
              "let b: boolean = false; b = n === 3;" +
              "let c: boolean = false; c = n === 4;" +
              "let d: boolean = false; d = n === 5;" +
              "let out: boolean = false;"
    cases := [?]string {
        prefix + "if ((a && b) || c) { out = true; }" +
        "else { if (c) { out = true; } else { out = false; } }",
        prefix + "if ((a || b) && c) {" +
        "if (c) { out = true; } else { out = false; }" +
        "} else { out = true; }",
        prefix + "if (a && (b || c)) {" +
        "if (a) { out = true; } else { out = false; }" +
        "} else { out = true; }",
        prefix + "if (((a && b) || c) && d) { out = true; }" +
        "else { out = false; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(826), 1, input)
        testing.expect(t, ok, "source")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                       !checked.complete && len(checked.diagnostics)>0,
                       "unproved nested and already narrowed guards fail closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}


@(test)
primitive_checker_bounded_relation_trace_decisions :: proc(t: ^testing.T) {
    input := "let x: number = 'bad';" +
             "let y: number = 1;" +
             "y = 'bad';" +
             "y = 2;"
    v, ok := source.source_version_create(source.File_Id(827), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    ordinary := check_file(&v, &ast, &bound)
    testing.expect(t, len(ordinary.relations) == 0 && len(ordinary.diagnostics) == 2,
                   "the ordinary checker path never allocates relation trace records")
    report_destroy(&ordinary)

    failed := check_file_with_relations(&v, &ast, &bound, .Failures)
    testing.expect(t, len(failed.relations) == 2 && len(failed.diagnostics) == 2 &&
                   !failed.fatal, "default evidence records only actual failed checks")
    if len(failed.relations) == 2 {
        a := failed.relations[0]
        b := failed.relations[1]
        testing.expect(t, a.source == .Text && a.target == .Number &&
                       a.relation_kind == .Variable && a.declaration_index == 0 &&
                       a.node_index >= 0 && !a.result,
                       "variable initializer failure uses its true expression and declaration")
        testing.expect(t, b.source == .Text && b.target == .Number &&
                       b.relation_kind == .Assignment && b.declaration_index == 1 &&
                       b.node_index > a.node_index && !b.result,
                       "reassignment failure uses the actual RHS and target declaration")
    }
    report_destroy(&failed)

    all := check_file_with_relations(&v, &ast, &bound, .All)
    testing.expect(t, len(all.relations) == 4 && len(all.diagnostics) == 2 &&
                   !all.fatal, "opt-in all mode records passed and failed checks")
    if len(all.relations) == 4 {
        testing.expect(t, !all.relations[0].result && all.relations[1].result &&
                       !all.relations[2].result && all.relations[3].result,
                       "relations preserve statement order and direct decision values")
        testing.expect(t, all.relations[1].relation_kind == .Variable &&
                       all.relations[3].relation_kind == .Assignment &&
                       all.relations[3].source == .Number &&
                       all.relations[3].target == .Number,
                       "successful primitive checks must be actual recorded decisions")
    }
    report_destroy(&all)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_bounded_relation_trace_unsupported :: proc(t: ^testing.T) {
    input := "let n: number = missing;"
    v, ok := source.source_version_create(source.File_Id(828), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file_with_relations(&v, &ast, &bound, .All)
    testing.expect(t, !bound.complete && checked.fatal && !checked.complete &&
                   len(checked.relations) == 0,
                   "unsupported binding must not invent type relation decisions")
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_relation_trace_nested_flow_source_order :: proc(t: ^testing.T) {
    // Existing proven nested-flow fixture: tracing cannot perturb mutation,
    // branch joins, statement order, or checker diagnostics.
    input := "let code: number = 1; code = 1 + 2; let ready: boolean = false;" +
             "ready = code === 2; let result: boolean = false;" +
             "if (code === 2) {" +
             "  if (ready) { result = code === 2; result = ready === true; }" +
             "  else { result = code === 2; result = ready === false; }" +
             "  result = code === 2;" +
             "} else {" +
             "  if (!ready) { result = ready === false; }" +
             "  else { result = ready === true; }" +
             "  result = code === 9;" +
             "} const after: boolean = code === 4;"
    v, ok := source.source_version_create(source.File_Id(829), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    ordinary := check_file(&v, &ast, &bound)
    traced := check_file_with_relations(&v, &ast, &bound, .All)
    failed := check_file_with_relations(&v, &ast, &bound, .Failures)
    testing.expect(t, ast.complete && bound.complete && ordinary.complete &&
                   traced.complete && failed.complete && !traced.fatal &&
                   len(ordinary.relations)==0 && len(ordinary.diagnostics)==0 &&
                   len(failed.relations)==0 && len(failed.diagnostics)==0 &&
                   len(traced.diagnostics)==0,
                   "opt-in relations leave proven nested-flow checking unchanged")
    testing.expect(t, traced.checked_declarations==4 &&
                   traced.checked_assignments==10 && len(traced.relations)==14,
                   "each annotated declaration and assignment has one real decision")
    prior := -1
    for relation in traced.relations {
        testing.expect(t, relation.node_index > prior &&
                       relation.node_index < len(ast.nodes) &&
                       relation.declaration_index >= 0 &&
                       relation.declaration_index < len(ast.declarations) &&
                       relation.source==relation.target && relation.result,
                       "nested and post-join decisions retain true source order")
        prior=relation.node_index
    }
    report_destroy(&failed)
    report_destroy(&traced)
    report_destroy(&ordinary)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_comparison_evidence_is_not_assignability :: proc(t: ^testing.T) {
    input := "const broad = 1 + 2;" +
             "const disjoint = 1 !== 2;" +
             "const identical = 'x' === 'x';" +
             "const same = broad === broad;" +
             "const possible = broad !== 9;" +
             "const domains = broad === 'x';" +
             "const mismatch: number = 'bad';"
    v, ok := source.source_version_create(source.File_Id(830), 1, input)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    ordinary := check_file(&v, &ast, &bound)
    failed := check_file_with_relations(&v, &ast, &bound, .Failures)
    all := check_file_with_relations(&v, &ast, &bound, .All)
    testing.expect(t, ast.complete && bound.complete &&
                   !ordinary.fatal && !failed.fatal && !all.fatal &&
                   len(ordinary.relations)==0 && len(ordinary.comparisons)==0 &&
                   len(ordinary.diagnostics)==3 &&
                   len(failed.diagnostics)==len(ordinary.diagnostics) &&
                   len(all.diagnostics)==len(ordinary.diagnostics),
                   "ordinary checking has no trace allocation or diagnostic drift")
    testing.expect(t, len(failed.comparisons)==2 && len(all.comparisons)==5 &&
                   len(failed.relations)==1 && len(all.relations)==1,
                   "failed/all modes separate comparison proofs from assignments")
    if len(all.comparisons)==5 {
        first := all.comparisons[0]
        same := all.comparisons[1]
        symbol := all.comparisons[2]
        broad := all.comparisons[3]
        different := all.comparisons[4]
        testing.expect(t, first.proof==.Disjoint_Literals &&
                       first.operator==.Exclamation_Equals_Equals && !first.overlaps &&
                       same.proof==.Same_Literal && same.overlaps &&
                       symbol.proof==.Same_Symbol && symbol.overlaps &&
                       broad.proof==.Widened_Domain && broad.overlaps &&
                       different.proof==.Disjoint_Domains && !different.overlaps &&
                       different.left==.Number && different.right==.Text &&
                       different.operator==.Equals_Equals_Equals,
                       "record exactly the five actual comparison proof branches")
        previous := -1
        for comparison in all.comparisons {
            testing.expect(t, comparison.node_index>previous &&
                           comparison.node_index<len(ast.nodes) &&
                           ast.nodes[comparison.node_index].kind==.Binary,
                           "comparison records preserve postorder source IDs")
            previous = comparison.node_index
        }
    }
    if len(failed.comparisons)==2 {
        testing.expect(t, !failed.comparisons[0].overlaps &&
                       !failed.comparisons[1].overlaps &&
                       failed.comparisons[0].proof==.Disjoint_Literals &&
                       failed.comparisons[1].proof==.Disjoint_Domains,
                       "failure trace has only proven disjoint comparisons")
    }
    if len(all.relations)==1 {
        testing.expect(t, all.relations[0].source==.Text &&
                       all.relations[0].target==.Number &&
                       !all.relations[0].result,
                       "incompatible initializer remains a distinct relation record")
    }
    report_destroy(&all)
    report_destroy(&failed)
    report_destroy(&ordinary)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)
}

@(test)
primitive_checker_comparison_trace_fails_closed_and_preserves_joins :: proc(t: ^testing.T) {
    // Explicit number annotations establish wide domains, not singletons.
    // Trace mode observes that decision without changing the checker result.
    annotated := "const a: number = 1; const b: number = 2;" +
                 "const overlap = a === b;"
    v, ok := source.source_version_create(source.File_Id(831), 1, annotated)
    testing.expect(t, ok, "source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file_with_relations(&v, &ast, &bound, .All)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==0 &&
                   len(checked.comparisons)==1,
                   "annotated same-domain comparison has one genuine overlap proof")
    if len(checked.comparisons)==1 {
        testing.expect(t, checked.comparisons[0].proof==.Widened_Domain &&
                       checked.comparisons[0].overlaps,
                       "trace records widened annotation at the comparison site")
    }
    report_destroy(&checked)
    binder.binding_report_destroy(&bound)
    parser.syntax_report_destroy(&ast)
    source.source_version_destroy(&v)

    // Existing nested mutation/join witness: opt-in comparison evidence is
    // strictly observational and cannot change flow state or diagnoses.
    nested := "let code: number = 1; code = 1 + 2; let ready: boolean = false;" +
              "ready = code === 2; let result: boolean = false;" +
              "if (code === 2) {" +
              "  if (ready) { result = code === 2; result = ready === true; }" +
              "  else { result = code === 2; result = ready === false; }" +
              "  result = code === 2;" +
              "} else {" +
              "  if (!ready) { result = ready === false; }" +
              "  else { result = ready === true; }" +
              "  result = code === 9;" +
              "} const after: boolean = code === 4;"
    v2, ok2 := source.source_version_create(source.File_Id(832), 1, nested)
    testing.expect(t, ok2, "nested source")
    ast2 := parser.parse_expression_program(&v2, compat.ts7_profile())
    bound2 := binder.bind_program(&v2, &ast2)
    normal := check_file(&v2, &ast2, &bound2)
    traced := check_file_with_relations(&v2, &ast2, &bound2, .All)
    testing.expect(t, ast2.complete && bound2.complete &&
                   normal.complete && traced.complete &&
                   len(normal.comparisons)==0 && len(normal.diagnostics)==0 &&
                   len(traced.diagnostics)==0 && len(traced.comparisons)>0 &&
                   normal.checked_assignments==traced.checked_assignments,
                   "comparison evidence leaves nested mutation and joins unchanged")
    previous := -1
    for comparison in traced.comparisons {
        testing.expect(t, comparison.node_index>previous &&
                       comparison.node_index<len(ast2.nodes) &&
                       comparison.operator==.Equals_Equals_Equals,
                       "nested comparison records remain source ordered")
        previous=comparison.node_index
    }
    report_destroy(&traced)
    report_destroy(&normal)
    binder.binding_report_destroy(&bound2)
    parser.syntax_report_destroy(&ast2)
    source.source_version_destroy(&v2)
}
