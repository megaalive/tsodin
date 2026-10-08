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
primitive_checker_does_not_assume_mutable_or_annotated_literals :: proc(t: ^testing.T) {
    cases := [?]string {
        "let flexible = 1; const result = flexible === 2;",
        "const widened: number = 1; const result = widened === 2;",
        "var mutable = false; const result = mutable === true;",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(722), 1, input)
        testing.expect(t, ok, "valid input")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, ast.complete && bound.complete &&
                       checked.fatal && !checked.complete &&
                       len(checked.diagnostics) == 1 &&
                       checked.diagnostics[0].issue == .Incompatible_Operator,
                       "no fabricated literal identity for let/var or annotations")
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
primitive_checker_does_not_invent_same_domain_overlap :: proc(t: ^testing.T) {
    input := "const a: number = 1; const b: number = 2; const uncertain = a === b;"
    v, ok := source.source_version_create(source.File_Id(724), 1, input)
    testing.expect(t, ok, "valid source")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                   !checked.complete && len(checked.diagnostics) == 1 &&
                   checked.diagnostics[0].issue == .Incompatible_Operator,
                   "widened same-base types remain unsupported without flow proof")
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
primitive_checker_mutable_computation_does_not_gain_const_provenance :: proc(t: ^testing.T) {
    input := "let mutable = 1 + 2; const uncertain = mutable === 7;"
    v, ok := source.source_version_create(source.File_Id(727), 1, input)
    testing.expect(t, ok, "valid source snapshot")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete && checked.fatal &&
                   !checked.complete && len(checked.diagnostics) == 1 &&
                   checked.diagnostics[0].issue == .Incompatible_Operator,
                   "mutable inferred value is not granted unproven flow semantics")
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
    input := "let count: number = 1; count = 2; const bad = count === 3;" +
             "count = 4; const bad2 = count !== 2; count = 'wrong';"
    v, ok := source.source_version_create(source.File_Id(734), 1, input)
    testing.expect(t, ok, "source created")
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    bound := binder.bind_program(&v, &ast)
    checked := check_file(&v, &ast, &bound)
    testing.expect(t, ast.complete && bound.complete &&
                   !checked.complete && !checked.fatal &&
                   checked.checked_declarations == 3 &&
                   checked.checked_assignments == 3 &&
                   len(checked.diagnostics) == 3,
                   "disjoint flows and bad assignment are independently reported")
    if len(checked.diagnostics) == 3 {
        testing.expect(t, checked.diagnostics[0].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[1].issue == .Disjoint_Literal_Comparison &&
                       checked.diagnostics[2].issue == .Assignment_Type_Mismatch,
                       "existing TS2367/TS2322 candidate kinds are preserved")
        testing.expect(t, input[checked.diagnostics[0].byte_start:checked.diagnostics[0].byte_end] == "count === 3" &&
                       input[checked.diagnostics[2].byte_start:checked.diagnostics[2].byte_end] == "'wrong'",
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
