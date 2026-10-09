package checker

import "core:testing"
import "../source"
import "../parser"
import "../binder"
import "../compat"

@(test)
typeof_never_arms_transfer_only_reachable_assignments :: proc(t: ^testing.T) {
    input := "let x: number | string = 1; let n: number = 0;" +
             "if (typeof x === 'string') { n = 1; } else { n = 2; }" +
             "const stillNumber: number = x;" +
             "if (typeof x !== 'number') { n = 3; } else { n = 4; }" +
             "const sameNumber: number = x;" +
             "if (!(typeof x === 'number')) { n = 5; } else { n = 6; }" +
             "const afterNegation: number = x;" +
             "let y: number | string = 'start';" +
             "if (typeof y === 'number') { n = 7; } else { n = 8; }" +
             "const stillString: string = y;"
    v, ok := source.source_version_create(source.File_Id(971), 1, input)
    testing.expect(t, ok, "valid source")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    checked := check_file(&v, &ast, &bound)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && bound.complete && checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==0 &&
                   checked.checked_declarations==7 && checked.checked_assignments==8,
                   "single reachable arm must keep original union flow")
}

@(test)
typeof_never_arms_check_wrong_literals_both_live_and_dead :: proc(t: ^testing.T) {
    input := "let x: number | string = 1; let n: number = 0;" +
             "if (typeof x === 'string') { n = 'dead'; } else { n = 'live'; }" +
             "if (typeof x !== 'number') { n = 'inverted dead'; } else { n = 'inverted live'; }"
    v, ok := source.source_version_create(source.File_Id(972), 1, input)
    testing.expect(t, ok, "valid source")
    defer source.source_version_destroy(&v)
    ast := parser.parse_expression_program(&v, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    bound := binder.bind_program(&v, &ast)
    defer binder.binding_report_destroy(&bound)
    checked := check_file(&v, &ast, &bound)
    defer report_destroy(&checked)
    testing.expect(t, ast.complete && bound.complete && !checked.complete &&
                   !checked.fatal && len(checked.diagnostics)==4 &&
                   checked.checked_assignments==4,
                   "TS7 mismatches in never arms cannot be dropped")
    for d in checked.diagnostics {
        testing.expect(t, d.issue==.Assignment_Type_Mismatch && d.byte_end>d.byte_start,
                       "all mismatches retain exact source identifiers")
    }
}

@(test)
typeof_never_rejects_unproved_dead_arm_expressions :: proc(t: ^testing.T) {
    cases := [?]string{
        "let x: number | string = 1; let n: number = 0; if (typeof x === 'string') { n = x; } else { n = 2; }",
        "let x: number | string = 1; let n: number = 0; if (typeof x === 'string') { if (n === 1) { n = 1; } else { n = 2; } } else { n = 2; }",
        "let x: number | string = 1; if (typeof x === 'string') { x = 'dead'; } else { x = 2; }",
    }
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(973), 1, input)
        testing.expect(t, ok, "valid UTF8")
        ast := parser.parse_expression_program(&v, compat.ts7_profile())
        bound := binder.bind_program(&v, &ast)
        checked := check_file(&v, &ast, &bound)
        testing.expect(t, !checked.complete && checked.fatal,
                       "dead-arm variable references, nested guards and guard writes fail closed")
        report_destroy(&checked)
        binder.binding_report_destroy(&bound)
        parser.syntax_report_destroy(&ast)
        source.source_version_destroy(&v)
    }
}
