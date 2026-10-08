package binder

import "core:testing"
import "../source"
import "../parser"
import "../compat"

@(test)
script_files_share_globals_and_forward_resolve :: proc(t: ^testing.T) {
    a, ok1 := source.source_version_create(source.File_Id(501), 1, "const answer: number = later + 1; var shared = 2;")
    b, ok2 := source.source_version_create(source.File_Id(502), 1, "let later = 3; var shared = 4;")
    testing.expect(t, ok1 && ok2, "two script source versions")
    defer source.source_version_destroy(&a)
    defer source.source_version_destroy(&b)
    p1 := parser.parse_expression_program(&a, compat.ts7_profile())
    p2 := parser.parse_expression_program(&b, compat.ts7_profile())
    defer parser.syntax_report_destroy(&p1)
    defer parser.syntax_report_destroy(&p2)
    testing.expect(t, p1.complete && p2.complete, "both script ASTs complete")
    files := [?]Project_File{
        Project_File{source_version=&a,syntax=&p1},
        Project_File{source_version=&b,syntax=&p2},
    }
    r := bind_script_project(files[:])
    defer project_report_destroy(&r)
    testing.expect(t, r.complete && !r.fatal && len(r.issues)==0, "global lookup succeeds")
    testing.expect(t, len(r.symbols)==3 && len(r.references)==1,
                   "three unique top-level names and one forward reference")
    testing.expect(t, r.references[0].file_index==0 && r.references[0].symbol_index==2,
                   "file 0 resolves declaration in file 1")
    testing.expect(t, r.symbols[1].declaration_count==2 && r.symbols[1].kind==.Var,
                   "cross-file var declarations merge")
}

@(test)
script_files_report_cross_file_lexical_conflicts :: proc(t: ^testing.T) {
    a, ok1 := source.source_version_create(source.File_Id(503), 1, "let clash = 1;")
    b, ok2 := source.source_version_create(source.File_Id(504), 1, "const clash = 2;")
    testing.expect(t, ok1 && ok2, "valid inputs")
    defer source.source_version_destroy(&a)
    defer source.source_version_destroy(&b)
    p1 := parser.parse_expression_program(&a, compat.ts7_profile())
    p2 := parser.parse_expression_program(&b, compat.ts7_profile())
    defer parser.syntax_report_destroy(&p1)
    defer parser.syntax_report_destroy(&p2)
    files := [?]Project_File{
        Project_File{source_version=&a,syntax=&p1},
        Project_File{source_version=&b,syntax=&p2},
    }
    r := bind_script_project(files[:])
    defer project_report_destroy(&r)
    testing.expect(t, !r.complete && !r.fatal && len(r.issues)==1 &&
                   r.issues[0].kind==.Duplicate_Declaration &&
                   r.issues[0].file_index==1,"conflict attributed to second file")
    issue := r.issues[0]
    testing.expect(t, b.owned_text[issue.byte_start:issue.byte_end]=="clash",
                   "source spans are local to reported file index")
}

@(test)
script_project_rejects_unresolved_and_mixed_versions :: proc(t: ^testing.T) {
    a, ok1 := source.source_version_create(source.File_Id(505), 1, "let a = absent;")
    b, ok2 := source.source_version_create(source.File_Id(506), 1, "let b = 1;")
    testing.expect(t, ok1 && ok2, "valid UTF8")
    defer source.source_version_destroy(&a)
    defer source.source_version_destroy(&b)
    p1 := parser.parse_expression_program(&a, compat.ts7_profile())
    p2 := parser.parse_expression_program(&b, compat.ts7_profile())
    defer parser.syntax_report_destroy(&p1)
    defer parser.syntax_report_destroy(&p2)
    files := [?]Project_File{
        Project_File{source_version=&a,syntax=&p1},
        Project_File{source_version=&b,syntax=&p2},
    }
    r := bind_script_project(files[:])
    testing.expect(t, !r.complete && !r.fatal && len(r.issues)==1 &&
                   r.issues[0].kind==.Unresolved_Name && r.issues[0].file_index==0,
                   "unresolved global cannot be hidden")
    project_report_destroy(&r)

    other, ok3 := source.source_version_create(source.File_Id(506), 2, "let b = 2;")
    testing.expect(t, ok3, "new source generation")
    defer source.source_version_destroy(&other)
    files[1].source_version=&other
    stale := bind_script_project(files[:])
    testing.expect(t, stale.fatal && !stale.complete &&
                   stale.issues[0].kind==.Snapshot_Mismatch &&
                   len(stale.symbols)==0,"stale parser AST forbidden")
    project_report_destroy(&stale)
    files[1].source_version=&a
    alias := bind_script_project(files[:])
    testing.expect(t, alias.fatal && !alias.complete &&
                   alias.issues[0].kind==.Snapshot_Mismatch, "wrong file identity refused")
    project_report_destroy(&alias)
}

@(test)
script_project_rejects_incomplete_files :: proc(t: ^testing.T) {
    a, ok1 := source.source_version_create(source.File_Id(507), 1, "let ok = 1;")
    b, ok2 := source.source_version_create(source.File_Id(508), 1, "let broken = 1 + ;")
    testing.expect(t, ok1 && ok2, "UTF8 sources")
    defer source.source_version_destroy(&a)
    defer source.source_version_destroy(&b)
    p1 := parser.parse_expression_program(&a, compat.ts7_profile())
    p2 := parser.parse_expression_program(&b, compat.ts7_profile())
    defer parser.syntax_report_destroy(&p1)
    defer parser.syntax_report_destroy(&p2)
    files := [?]Project_File{
        Project_File{source_version=&a,syntax=&p1},
        Project_File{source_version=&b,syntax=&p2},
    }
    r := bind_script_project(files[:])
    defer project_report_destroy(&r)
    testing.expect(t, r.fatal && !r.complete && len(r.symbols)==0 &&
                   r.issues[0].kind==.Syntax_Not_Complete &&
                   r.issues[0].file_index==1,
                   "one invalid file prevents incomplete global success")
}

@(test)
script_project_rejects_explicit_external_modules :: proc(t: ^testing.T) {
    text := "const local: number = 42;"
    version, ok := source.source_version_create(source.File_Id(509), 1, text)
    testing.expect(t, ok, "verified UTF-8")
    defer source.source_version_destroy(&version)
    ast := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&ast)
    testing.expect(t, ast.complete, "restricted grammar accepts simple local declaration")
    modules := [?]Project_File{
        Project_File{source_version=&version,syntax=&ast,mode=.External_Module},
    }
    refused := bind_script_project(modules[:])
    testing.expect(t, refused.fatal && !refused.complete &&
                   len(refused.symbols)==0 && len(refused.references)==0 &&
                   len(refused.issues)==1 &&
                   refused.issues[0].kind==.Unsupported_File_Mode,
                   "external module must never be merged as script global")
    project_report_destroy(&refused)

    // Exactly the same syntax can be a script if its loader proves that mode.
    modules[0].mode=.Script
    accepted := bind_script_project(modules[:])
    testing.expect(t, accepted.complete && !accepted.fatal &&
                   len(accepted.symbols)==1,
                   "verified script retains previous M3-B behavior")
    project_report_destroy(&accepted)
}
