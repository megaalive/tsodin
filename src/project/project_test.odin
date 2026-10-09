package project

import "core:testing"
import "core:strings"
import "../binder"

@(test)
config_accepts_only_ordered_explicit_scripts :: proc(t: ^testing.T) {
    cfg, err := parse_config("{\"files\":[\"./a.ts\",\"sub/../b.ts\"],\"compilerOptions\":{\"noEmit\":true}}")
    defer config_destroy(&cfg)
    testing.expect(t, err == .None && len(cfg.roots) == 2 &&
                   cfg.roots[0] == "a.ts" && cfg.roots[1] == "b.ts" && cfg.no_emit,
                   "explicit roots normalize but preserve selection order")
    // TypeScript accepts trailing commas in tsconfig; Odin's JSON parser
    // also accepts these even when the JSON specification is selected.
    trailing, trailing_err := parse_config("{\"files\":[\"a.ts\",],\"compilerOptions\":{\"noEmit\":true,},}")
    defer config_destroy(&trailing)
    testing.expect(t, trailing_err == .None && len(trailing.roots) == 1 &&
                   trailing.roots[0] == "a.ts",
                   "trailing commas are accepted rather than labeled invalid JSON")
}

@(test)
config_rejects_unsupported_semantics_and_aliases :: proc(t: ^testing.T) {
    inputs := [?]struct{text:string, reason:Config_Error}{
        {"{}", .Missing_Files},
        {"{\"files\":[] ,\"compilerOptions\":{\"noEmit\":true}}", .Missing_Files},
        {"{\"files\":[\"a.ts\"],\"extends\":\"base.json\",\"compilerOptions\":{\"noEmit\":true}}", .Unsupported_Config},
        {"{\"files\":[\"a.ts\"],\"include\":[\"**/*\"],\"compilerOptions\":{\"noEmit\":true}}", .Unsupported_Config},
        {"{\"files\":[\"a.ts\"],\"compilerOptions\":{\"strict\":true,\"noEmit\":true}}", .Unsupported_Option},
        {"{\"files\":[\"a.ts\"],\"compilerOptions\":{\"noEmit\":false}}", .Unsupported_Option},
        {"{\"files\":[\"a.ts\",\"./a.ts\"],\"compilerOptions\":{\"noEmit\":true}}", .Duplicate_File},
        {"{\"files\":[\"../outside.ts\"],\"compilerOptions\":{\"noEmit\":true}}", .Invalid_File},
        {"{\"files\":[\"a.d.ts\"],\"compilerOptions\":{\"noEmit\":true}}", .Invalid_File},
        {"{\"files\":[\"a.tsx\"],\"compilerOptions\":{\"noEmit\":true}}", .Invalid_File},
        {"{\"files\":[9],\"compilerOptions\":{\"noEmit\":true}}", .Invalid_File},
    }
    for entry in inputs {
        cfg, err := parse_config(entry.text)
        testing.expect(t, err == entry.reason && len(cfg.roots) == 0,
                       "fail closed and release any previously allocated roots")
        config_destroy(&cfg)
    }
}

@(test)
loader_connects_config_snapshots_parser_and_project_binder :: proc(t: ^testing.T) {
    p, err := load("tests/project/fixtures/valid/tsconfig.json")
    defer project_destroy(&p)
    testing.expect(t, err == .None && p.config_error == .None &&
                   len(p.files) == 2 && p.binding.complete && !p.binding.fatal &&
                   len(p.binding.symbols) == 2 && len(p.binding.references) == 1 &&
                   p.binding.references[0].file_index == 0 &&
                   p.binding.references[0].symbol_index == 1,
                   "two source-backed files resolve an ordered cross-file reference")
    if len(p.files) == 2 {
        testing.expect(t, p.files[0].version.file_id != p.files[1].version.file_id,
                       "loader assigns distinct stable file IDs")
    }
}

@(test)
loader_reports_first_cross_file_conflict_without_success :: proc(t: ^testing.T) {
    p, err := load("tests/project/fixtures/conflict/tsconfig.json")
    defer project_destroy(&p)
    testing.expect(t, err == .None && !p.binding.complete && !p.binding.fatal &&
                   len(p.binding.issues) == 1 &&
                   p.binding.issues[0].kind == binder.Issue_Kind.Duplicate_Declaration &&
                   p.binding.issues[0].file_index == 1,
                   "second configured file owns duplicate diagnostic")
}

@(test)
loader_refuses_missing_root_without_binding_partial_file_set :: proc(t: ^testing.T) {
    p, err := load("tests/project/fixtures/missing/tsconfig.json")
    defer project_destroy(&p)
    testing.expect(t, err == .Root_Read && p.error_file_index == 1 &&
                   len(p.files) == 1 && len(p.binding.symbols) == 0 &&
                   !p.binding.complete,
                   "a missing configured file never causes success on a prefix")
}

@(test)
jsonc_trivia_matches_official_config_string_boundaries :: proc(t: ^testing.T) {
    // Regressions based on Microsoft's pinned tsconfigparsing_test.go.
    input := `{"files":[/* one
    two */"a.ts"], // ignored
    "compilerOptions":{"noEmit":true}}`
    cleaned, ok := strip_jsonc_comments(input)
    testing.expect(t, ok && len(cleaned) == len(input) &&
                   strings.contains(string(cleaned), `"a.ts"`) &&
                   !strings.contains(string(cleaned), "ignored") &&
                   !strings.contains(string(cleaned), "one"),
                   "line and block comments become same-width whitespace")
    delete(cleaned)

    quoted := `{"note":"literal // and /* */ and \\" escaped quote"}`
    same, quoted_ok := strip_jsonc_comments(quoted)
    testing.expect(t, quoted_ok && string(same) == quoted,
                   "comment-like text inside quoted string stays untouched")
    delete(same)

    even_escapes := `{"note":"\\\\", /* actual comment */"files":["a.ts"]}`
    even, even_ok := strip_jsonc_comments(even_escapes)
    testing.expect(t, even_ok && len(even) == len(even_escapes) &&
                   !strings.contains(string(even), "actual comment"),
                   "paired backslashes do not hide the closing quote")
    delete(even)
}

@(test)
jsonc_config_accepts_comments_but_keeps_unsupported_options_closed :: proc(t: ^testing.T) {
    valid := `{ // project roots
        "files": [ /* one */ "a.ts", ],
        "compilerOptions": { /* disable emit */ "noEmit": true, },
    }`
    c, err := parse_config(valid)
    testing.expect(t, err == .None && len(c.roots)==1 && c.roots[0]=="a.ts",
                   "JSONC comments and trailing commas compose with explicit roots")
    config_destroy(&c)

    quoted, quoted_err := parse_config(`{"files":["http://host/a.ts"],"compilerOptions":{"noEmit":true}}`)
    testing.expect(t, quoted_err == .Invalid_File,
                   "comment-like bytes inside a string remain source path data")
    config_destroy(&quoted)

    unsupported, unsupported_err := parse_config(`{/*hey*/"files":["a.ts"],"compilerOptions":{"noEmit":true,"strict":true}}`)
    testing.expect(t, unsupported_err == .Unsupported_Option,
                   "JSONC support does not bypass unsupported option rejection")
    config_destroy(&unsupported)

    invalid := [?]string{
        `{/* unclosed`,
        `{"files":["a.ts"],"compilerOptions":{"noEmit":true}}/*`,
        `{"files":["a.ts"],"compilerOptions":{"noEmit":true}}/`,
        `{"files":["a.ts"],"compilerOptions":{"noEmit":true}} garbage`,
    }
    for source_text in invalid {
        rejected, rejection := parse_config(source_text)
        testing.expect(t, rejection == .Invalid_Json && len(rejected.roots)==0,
                       "unterminated block and stray slash fail closed")
        config_destroy(&rejected)
    }
}

@(test)
project_loader_reads_jsonc_config_from_disk :: proc(t: ^testing.T) {
    p, err := load("tests/project/fixtures/jsonc/tsconfig.json")
    defer project_destroy(&p)
    testing.expect(t, err == .None && len(p.files)==2 &&
                   p.binding.complete && len(p.binding.references)==1,
                   "physical commented tsconfig feeds the existing project binder")
}
