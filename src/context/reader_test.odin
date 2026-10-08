package lexcontext

import "core:testing"
import "../source"
import "../scanner"

@(test)
template_nested_braces_and_nested_templates :: proc(t: ^testing.T) {
    text := "`outer ${ {value: 1} } and ${`inner ${x}` }!`"
    version, ok := source.source_version_create(source.File_Id(100), 1, text)
    testing.expect(t, ok, "UTF-8 input")
    defer source.source_version_destroy(&version)
    reader := reader_init(&version)

    expected := [?]scanner.Token_Kind{
        .Template_Head,
        .Open_Brace, .Identifier, .Colon, .Integer_Literal, .Close_Brace,
        .Template_Middle,
        .Template_Head, .Identifier, .Template_Tail,
        .Template_Tail, .End_Of_File,
    }
    for wanted in expected {
        token := reader_next(&reader)
        testing.expect(t, token.kind == wanted && token.error == .None,
                       "nested template reader yields expected token")
    }
    testing.expect(t, reader.template_depth == 0, "all frames closed")
}

@(test)
template_interpolations_are_source_spanned :: proc(t: ^testing.T) {
    text := "`x ${value} y`"
    version, ok := source.source_version_create(source.File_Id(101), 4, text)
    testing.expect(t, ok, "valid text")
    defer source.source_version_destroy(&version)
    reader := reader_init(&version)
    head := reader_next(&reader)
    testing.expect(t, head.kind == .Template_Head && head.byte_end == 5,
                   "head spans dollar-brace")
    ident := reader_next(&reader)
    testing.expect(t, ident.kind == .Identifier && ident.byte_start == 5,
                   "expression starts after head")
    tail := reader_next(&reader)
    testing.expect(t, tail.kind == .Template_Tail &&
                   tail.byte_start == 10 && tail.byte_end == len(text),
                   "tail starts at matching brace")
    testing.expect(t, reader_next(&reader).kind == .End_Of_File, "EOF after template")
}

@(test)
template_unclosed_fails_closed :: proc(t: ^testing.T) {
    text := "`unfinished ${name"
    version, ok := source.source_version_create(source.File_Id(102), 1, text)
    testing.expect(t, ok, "source is UTF-8 valid")
    defer source.source_version_destroy(&version)
    reader := reader_init(&version)
    testing.expect(t, reader_next(&reader).kind == .Template_Head, "head")
    testing.expect(t, reader_next(&reader).kind == .Identifier, "name")
    bad := reader_next(&reader)
    testing.expect(t, bad.kind == .Invalid && bad.error == .Unterminated_Template,
                   "no false successful EOF")
    again := reader_next(&reader)
    testing.expect(t, again.kind == .Invalid && again.error == .Previous_Failure,
                   "error is sticky")
}

@(test)
slash_requires_explicit_rescan :: proc(t: ^testing.T) {
    text := "8 / 2; /[ab/]+/gi"
    version, ok := source.source_version_create(source.File_Id(103), 1, text)
    testing.expect(t, ok, "valid source")
    defer source.source_version_destroy(&version)
    reader := reader_init(&version)
    testing.expect(t, reader_next(&reader).kind == .Integer_Literal, "left")
    div := reader_next(&reader)
    testing.expect(t, div.kind == .Slash, "ambiguous slash")
    testing.expect(t, reader_next(&reader).kind == .Integer_Literal,
                   "division is not auto converted")
    testing.expect(t, reader_next(&reader).kind == .Semicolon, "separator")
    slash := reader_next(&reader)
    regex := reader_rescan_regex(&reader, slash)
    testing.expect(t, regex.kind == .Regular_Expression_Literal &&
                   regex.byte_start == slash.byte_start &&
                   regex.byte_end == len(text), "explicit regexp rescan")
    testing.expect(t, reader_next(&reader).kind == .End_Of_File, "after regexp")
    invalid := reader_rescan_regex(&reader, slash)
    testing.expect(t, invalid.kind == .Invalid && invalid.error == .Unsupported_Context,
                   "stale slash is never reusable")
}
