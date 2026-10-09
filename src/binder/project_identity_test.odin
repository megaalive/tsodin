package binder

import "core:testing"
import "../source"
import "../parser"
import "../compat"

@(test)
project_empty_root_set_refuses_false_success :: proc(t: ^testing.T) {
    empty := [?]Project_File{}
    r := bind_script_project(empty[:])
    defer project_report_destroy(&r)
    testing.expect(t, !r.complete && r.fatal && len(r.issues)==1 &&
                   r.issues[0].kind==.Invalid_Source &&
                   r.issues[0].file_index==-1 &&
                   len(r.symbols)==0 && len(r.references)==0,
                   "no configured files must never become a valid checked project")
}

@(test)
project_file_id_collisions_and_duplicate_owner_are_deterministic :: proc(t: ^testing.T) {
    // Capacity 8: 704 and 712 deliberately collide, but are distinct IDs.
    a, a_ok := source.source_version_create(source.File_Id(704), 1, "const first: number = 1;")
    b, b_ok := source.source_version_create(source.File_Id(712), 1, "const second: string = 'two';")
    c, c_ok := source.source_version_create(source.File_Id(704), 2, "const third: boolean = true;")
    testing.expect(t, a_ok && b_ok && c_ok, "three valid independent snapshots")
    defer source.source_version_destroy(&a)
    defer source.source_version_destroy(&b)
    defer source.source_version_destroy(&c)
    p1 := parser.parse_expression_program(&a, compat.ts7_profile())
    p2 := parser.parse_expression_program(&b, compat.ts7_profile())
    p3 := parser.parse_expression_program(&c, compat.ts7_profile())
    defer parser.syntax_report_destroy(&p1)
    defer parser.syntax_report_destroy(&p2)
    defer parser.syntax_report_destroy(&p3)
    files := [?]Project_File{
        Project_File{source_version=&a,syntax=&p1},
        Project_File{source_version=&b,syntax=&p2},
        Project_File{source_version=&c,syntax=&p3},
    }
    distinct := bind_script_project(files[:2])
    testing.expect(t, distinct.complete && !distinct.fatal &&
                   len(distinct.symbols)==2 && len(distinct.issues)==0 &&
                   distinct.symbols[0].file_index==0 &&
                   distinct.symbols[1].file_index==1,
                   "colliding hash buckets do not alias logical file identities")
    project_report_destroy(&distinct)

    for _ in 0..<2 {
        duplicate := bind_script_project(files[:])
        testing.expect(t, !duplicate.complete && duplicate.fatal &&
                       len(duplicate.issues)==1 && len(duplicate.symbols)==0 &&
                       duplicate.issues[0].kind==.Invalid_Source &&
                       duplicate.issues[0].file_index==2,
                       "later duplicate File_Id is deterministic and atomic")
        project_report_destroy(&duplicate)
    }
    files[2].source_version=&b
    mismatch := bind_script_project(files[:])
    testing.expect(t, mismatch.fatal && !mismatch.complete &&
                   len(mismatch.issues)==1 &&
                   mismatch.issues[0].kind==.Snapshot_Mismatch &&
                   mismatch.issues[0].file_index==2,
                   "snapshot identity validation precedes duplicate File_Id check")
    project_report_destroy(&mismatch)
}

@(test)
project_file_selection_order_keeps_deterministic_symbol_ownership :: proc(t: ^testing.T) {
    a, ok_a := source.source_version_create(source.File_Id(128), 1, "const alpha = 1;")
    b, ok_b := source.source_version_create(source.File_Id(136), 1, "const beta = 2;")
    testing.expect(t, ok_a && ok_b, "valid sources")
    defer source.source_version_destroy(&a)
    defer source.source_version_destroy(&b)
    sa := parser.parse_expression_program(&a, compat.ts7_profile())
    sb := parser.parse_expression_program(&b, compat.ts7_profile())
    defer parser.syntax_report_destroy(&sa)
    defer parser.syntax_report_destroy(&sb)
    files := [?]Project_File{
        Project_File{source_version=&b,syntax=&sb},
        Project_File{source_version=&a,syntax=&sa},
    }
    for _ in 0..<2 {
        report := bind_script_project(files[:])
        testing.expect(t, report.complete && len(report.symbols)==2 &&
                       report.symbols[0].file_index==0 &&
                       report.symbols[1].file_index==1,
                       "symbol indices use declared input order, not probe bucket order")
        project_report_destroy(&report)
    }
}
