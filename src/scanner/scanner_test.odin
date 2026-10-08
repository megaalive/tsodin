package scanner

import "core:testing"
import "../source"

@(test)
scanner_ascii_declaration_subset :: proc(t: ^testing.T) {
    version, ok := source.source_version_create(source.File_Id(9), 1, "const a: number = 42;\nlet b = 'ok';")
    testing.expect(t, ok, "well-formed source")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    expected := [?]Token_Kind{
        .Const, .Identifier, .Colon, .Number_Keyword, .Equals, .Integer_Literal, .Semicolon,
        .Let, .Identifier, .Equals, .String_Literal, .Semicolon, .End_Of_File,
    }
    for wanted in expected {
        token := scanner_next(&s)
        testing.expect(t, token.kind == wanted && token.error == .None, "token must match the supported ASCII subset")
        testing.expect(t, token.byte_end >= token.byte_start, "token byte spans are ordered")
    }
    end := scanner_next(&s)
    testing.expect(t, end.kind == .End_Of_File, "EOF is repeatable")
}

@(test)
scanner_spans_and_source_positions :: proc(t: ^testing.T) {
    version, ok := source.source_version_create(source.File_Id(1), 1, "const x: number = 123;\n")
    testing.expect(t, ok, "source initialized")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    token := scanner_next(&s)
    testing.expect(t, token.kind == .Const && token.byte_start == 0 && token.byte_end == 5, "const span")
    token = scanner_next(&s)
    testing.expect(t, token.kind == .Identifier && token.byte_start == 6 && token.byte_end == 7, "identifier span")
    pos, valid := source.source_position(&version, token.byte_start)
    testing.expect(t, valid && pos.line == 0 && pos.column_utf16 == 6, "scanner spans feed source-index positions")
}

@(test)
scanner_skips_comments_and_line_separators :: proc(t: ^testing.T) {
    version, ok := source.source_version_create(source.File_Id(2), 1, "// text\r\n/* comment */let a = 1;\u2028// end\nconst b = 2;")
    testing.expect(t, ok, "Unicode trivia source")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    expected := [?]Token_Kind{.Let, .Identifier, .Equals, .Integer_Literal, .Semicolon,
                              .Const, .Identifier, .Equals, .Integer_Literal, .Semicolon, .End_Of_File}
    for kind in expected {
        next := scanner_next(&s)
        testing.expect(t, next.kind == kind && next.error == .None, "comments/trivia must be skipped")
    }
}

@(test)
scanner_fails_closed_on_unhandled_constructs :: proc(t: ^testing.T) {
    version, ok := source.source_version_create(source.File_Id(1), 3, "/abc/")
    testing.expect(t, ok, "slash input is valid UTF-8")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    token := scanner_next(&s)
    testing.expect(t, token.kind == .Invalid && token.error == .Unsupported_Syntax,
                   "slash ambiguity must not be treated as valid")
    token = scanner_next(&s)
    testing.expect(t, token.kind == .Invalid && token.error == .Previous_Failure, "scanner failure remains sticky")

    bad_quote, ok2 := source.source_version_create(source.File_Id(1), 4, "'hello")
    testing.expect(t, ok2, "input is valid UTF-8")
    defer source.source_version_destroy(&bad_quote)
    q := scanner_init(&bad_quote)
    token = scanner_next(&q)
    testing.expect(t, token.kind == .Invalid && token.error == .Unterminated_String, "unterminated quote")

    escaped, ok3 := source.source_version_create(source.File_Id(1), 5, "'a\\nb'")
    testing.expect(t, ok3, "escape sample UTF-8")
    defer source.source_version_destroy(&escaped)
    e := scanner_init(&escaped)
    token = scanner_next(&e)
    testing.expect(t, token.kind == .Invalid && token.error == .Unsupported_Syntax, "escape awaits TS oracle")

    unicode, ok4 := source.source_version_create(source.File_Id(1), 6, "const π = 1;")
    testing.expect(t, ok4, "Unicode identifier UTF-8 is well formed")
    defer source.source_version_destroy(&unicode)
    u := scanner_init(&unicode)
    testing.expect(t, scanner_next(&u).kind == .Const, "const token")
    token = scanner_next(&u)
    testing.expect(t, token.kind == .Invalid && token.error == .Unsupported_Syntax, "Unicode identifier is not falsely accepted")
}

@(test)
scanner_unterminated_comment_and_invalid_version :: proc(t: ^testing.T) {
    version, ok := source.source_version_create(source.File_Id(5), 7, "let a = 1;/* oops")
    testing.expect(t, ok, "source initialization")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    for i in 0..<5 {
        token := scanner_next(&s)
        testing.expect(t, token.error == .None, "prefix tokens remain valid")
    }
    token := scanner_next(&s)
    testing.expect(t, token.kind == .Invalid && token.error == .Unterminated_Block_Comment,
                   "unterminated comment reported")
    blank: Scanner
    token = scanner_next(&blank)
    testing.expect(t, token.error == .Invalid_Source, "uninitialized scanner rejects input")
}
