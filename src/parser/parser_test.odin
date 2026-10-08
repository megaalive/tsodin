package parser

import "core:testing"
import "../source"
import "../compat"

@(test)
parse_primitive_declarations :: proc(t: ^testing.T) {
    text := "const answer: number = 42;\nlet label: string = 'ok';\nvar ready: boolean;"
    version, ok := source.source_version_create(source.File_Id(210), 5, text)
    testing.expect(t, ok, "valid source version")
    defer source.source_version_destroy(&version)
    program, error := parse_declarations(&version, compat.ts7_profile())
    testing.expect(t, error == .None, "declared grammar must parse")
    defer program_destroy(&program)
    testing.expect(t, program.file_id == version.file_id &&
                   program.generation == version.generation &&
                   len(program.declarations) == 3, "program identity and declaration count")
    first := program.declarations[0]
    testing.expect(t, first.kind == .Const && first.type_kind == .Number &&
                   first.literal_kind == .Integer, "typed const with number")
    testing.expect(t, text[first.name_start:first.name_end] == "answer" &&
                   text[first.literal_start:first.literal_end] == "42",
                   "source spans preserve original spellings")
    second := program.declarations[1]
    testing.expect(t, second.kind == .Let && second.type_kind == .String &&
                   second.literal_kind == .String &&
                   text[second.name_start:second.name_end] == "label", "typed let")
    third := program.declarations[2]
    testing.expect(t, third.kind == .Var && third.type_kind == .Boolean &&
                   third.literal_kind == .None && third.byte_end == len(text),
                   "uninitialized var declaration")
}

@(test)
parse_unicode_trivia_with_utf16_mapping :: proc(t: ^testing.T) {
    text := "// 😀 note\r\nconst x: number = 42;"
    version, ok := source.source_version_create(source.File_Id(211), 1, text)
    testing.expect(t, ok, "valid UTF-8 input")
    defer source.source_version_destroy(&version)
    program, error := parse_declarations(&version, compat.ts7_profile())
    testing.expect(t, error == .None && len(program.declarations) == 1, "ASCII grammar after Unicode trivia")
    defer program_destroy(&program)
    first := program.declarations[0]
    position, valid := source.source_position(&version, first.name_start)
    testing.expect(t, valid && position.line == 1 && position.column_utf16 == 6,
                   "byte-based node name maps to correct UTF-16 column")
}

@(test)
parse_rejects_all_unsupported_or_incomplete_syntax :: proc(t: ^testing.T) {
    examples := [?]string{
        "const = 1;",
        "const answer: thing = 1;",
        "const answer: number;",
        "let answer = 1",
        "let result = 8 / 2;",
        "export const answer = 42;",
        "let text = 'a\\nb';",
        "const x = `template`;",
    }
    for text in examples {
        version, ok := source.source_version_create(source.File_Id(212), 1, text)
        testing.expect(t, ok, "fixtures must be valid UTF-8")
        program, error := parse_declarations(&version, compat.ts7_profile())
        testing.expect(t, error != .None && len(program.declarations) == 0,
                       "parser fails closed without partial success")
        program_destroy(&program)
        source.source_version_destroy(&version)
    }
}

@(test)
parse_unknown_profiles_and_empty_inputs :: proc(t: ^testing.T) {
    empty, ok := source.source_version_create(source.File_Id(213), 2, "")
    testing.expect(t, ok, "empty input can be parsed")
    defer source.source_version_destroy(&empty)
    program, error := parse_declarations(&empty, compat.ts7_profile())
    testing.expect(t, error == .None && len(program.declarations) == 0,
                   "empty source is a complete empty program")
    program_destroy(&program)
    unknown := compat.Profile{version = compat.Version{8, 0, 0},
                              scanner_edition = .ASCII_Subset_V1}
    rejected, error_unknown := parse_declarations(&empty, unknown)
    testing.expect(t, error_unknown == .Unsupported_Profile &&
                   len(rejected.declarations) == 0, "unregistered TS8 rejected")
    blank: source.Source_Version
    invalid, error_invalid := parse_declarations(&blank, compat.ts7_profile())
    testing.expect(t, error_invalid == .Invalid_Source &&
                   len(invalid.declarations) == 0, "uninitialized source rejected")
}
