package scanner

import "core:testing"
import "../source"
import "../compat"

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
    testing.expect(t, token.kind == .Slash && token.error == .None,
                   "slash remains unclassified until the parser chooses a context")
    token = scanner_rescan_slash_as_regex(&s, token)
    testing.expect(t, token.kind == .Regular_Expression_Literal &&
                   token.byte_start == 0 && token.byte_end == 5,
                   "explicit slash rescan selects regex literal")
    token = scanner_next(&s)
    testing.expect(t, token.kind == .End_Of_File, "regex ends exactly at the delimiter")

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

@(test)
scanner_requires_explicitly_registered_edition :: proc(t: ^testing.T) {
    version, ok := source.source_version_create(source.File_Id(31), 1, "const x = 42;")
    testing.expect(t, ok, "valid fixture")
    defer source.source_version_destroy(&version)

    unknown := compat.Profile {
        version = compat.Version{8, 0, 0},
        scanner_edition = .ASCII_Subset_V1,
    }
    future := scanner_init_with_profile(&version, unknown)
    token := scanner_next(&future)
    testing.expect(t, token.kind == .Invalid && token.error == .Unsupported_Profile,
                   "unreviewed TypeScript 8 edition fails closed")
    token = scanner_next(&future)
    testing.expect(t, token.error == .Previous_Failure, "unsupported profile failure is sticky")

    pinned := scanner_init_with_profile(&version, compat.ts7_profile())
    token = scanner_next(&pinned)
    testing.expect(t, token.kind == .Const, "explicit registered TS7 profile scans")
}


@(test)
scanner_slash_is_contextual :: proc(t: ^testing.T) {
    division, ok := source.source_version_create(source.File_Id(44), 1, "const ratio = 8 / 2;")
    testing.expect(t, ok, "division source")
    defer source.source_version_destroy(&division)
    s := scanner_init(&division)
    expected := [?]Token_Kind{.Const, .Identifier, .Equals, .Integer_Literal, .Slash,
                              .Integer_Literal, .Semicolon, .End_Of_File}
    for kind in expected {
        got := scanner_next(&s)
        testing.expect(t, got.kind == kind && got.error == .None,
                       "division must remain a separate slash token")
    }

    pattern, ok2 := source.source_version_create(source.File_Id(45), 1, "/[ab/]+/gi;")
    testing.expect(t, ok2, "regexp source")
    defer source.source_version_destroy(&pattern)
    r := scanner_init(&pattern)
    slash := scanner_next(&r)
    testing.expect(t, slash.kind == .Slash, "slash is undecided in ordinary scan")
    expr := scanner_rescan_slash_as_regex(&r, slash)
    testing.expect(t, expr.kind == .Regular_Expression_Literal &&
                   expr.byte_start == 0 && expr.byte_end == 10 &&
                   expr.error == .None, "regexp with class slash and flags")
    semi := scanner_next(&r)
    testing.expect(t, semi.kind == .Semicolon && semi.byte_start == 10, "regexp byte span")
    stale := scanner_rescan_slash_as_regex(&r, slash)
    testing.expect(t, stale.kind == .Invalid && stale.error == .Unsupported_Context,
                   "stale rescan must not rewind past later tokens")
    testing.expect(t, scanner_next(&r).error == .Previous_Failure, "misuse is sticky")
}

@(test)
scanner_regexp_errors_are_sticky :: proc(t: ^testing.T) {
    examples := [?]string{"/[ab/", "/ab\nc/", "/abc/gg", "/abc/uv"}
    for input in examples {
        v, ok := source.source_version_create(source.File_Id(46), 1, input)
        testing.expect(t, ok, "source initialized")
        r := scanner_init(&v)
        slash := scanner_next(&r)
        testing.expect(t, slash.kind == .Slash, "slash token first")
        expr := scanner_rescan_slash_as_regex(&r, slash)
        testing.expect(t, expr.kind == .Invalid && expr.error != .None,
                       "malformed or unsupported regexp rejected")
        testing.expect(t, scanner_next(&r).error == .Previous_Failure,
                       "regexp failure remains sticky")
        source.source_version_destroy(&v)
    }
}


@(test)
scanner_template_segments_are_parser_controlled :: proc(t: ^testing.T) {
    input := "`a ${one} b ${two}!`"
    version, ok := source.source_version_create(source.File_Id(47), 1, input)
    testing.expect(t, ok, "template source")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    head := scanner_next(&s)
    testing.expect(t, head.kind == .Template_Head && head.byte_start == 0 &&
                   head.byte_end == 5, "head includes the opening delimiter")
    one := scanner_next(&s)
    testing.expect(t, one.kind == .Identifier && one.byte_start == 5 && one.byte_end == 8,
                   "interpolated identifier scanned normally")
    close_one := scanner_next(&s)
    testing.expect(t, close_one.kind == .Close_Brace && close_one.byte_end == 9,
                   "ordinary brace awaits parser rescan")
    middle := scanner_rescan_close_brace_as_template(&s, close_one)
    testing.expect(t, middle.kind == .Template_Middle &&
                   middle.byte_start == 8 && middle.byte_end == 14, "template middle")
    two := scanner_next(&s)
    testing.expect(t, two.kind == .Identifier && two.byte_start == 14 && two.byte_end == 17,
                   "second interpolation")
    close_two := scanner_next(&s)
    tail := scanner_rescan_close_brace_as_template(&s, close_two)
    testing.expect(t, tail.kind == .Template_Tail && tail.byte_start == 17 &&
                   tail.byte_end == len(input), "template tail")
    testing.expect(t, scanner_next(&s).kind == .End_Of_File, "template ends cleanly")

    plain, good := source.source_version_create(source.File_Id(48), 1, "`plain`")
    testing.expect(t, good, "plain template")
    defer source.source_version_destroy(&plain)
    p := scanner_init(&plain)
    token := scanner_next(&p)
    testing.expect(t, token.kind == .No_Substitution_Template &&
                   token.byte_end == 7, "no-substitution template is one token")

    broken, valid := source.source_version_create(source.File_Id(49), 1, "`missing")
    testing.expect(t, valid, "unterminated template input is valid UTF-8")
    defer source.source_version_destroy(&broken)
    b := scanner_init(&broken)
    fail := scanner_next(&b)
    testing.expect(t, fail.kind == .Invalid && fail.error == .Unterminated_Template,
                   "unclosed template rejected")
    testing.expect(t, scanner_next(&b).error == .Previous_Failure,
                   "template failure stays sticky")
}

@(test)
scanner_jsx_text_requires_explicit_context :: proc(t: ^testing.T) {
    input := "<div>Hello 😀</div>"
    version, ok := source.source_version_create(source.File_Id(50), 1, input)
    testing.expect(t, ok, "JSX source initialized")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    less := scanner_next(&s)
    testing.expect(t, less.kind == .Less_Than, "less-than before parser choice")
    tag := scanner_rescan_less_than_as_jsx_tag_start(&s, less)
    testing.expect(t, tag.kind == .Jsx_Tag_Start && tag.byte_start == 0 &&
                   tag.byte_end == 1, "JSX tag start is explicit")
    name := scanner_next(&s)
    testing.expect(t, name.kind == .Identifier, "tag name")
    greater := scanner_next(&s)
    testing.expect(t, greater.kind == .Greater_Than, "opening tag end")
    testing.expect(t, scanner_begin_jsx_text(&s, greater), "JSX text mode entered")
    raw_text := scanner_next_jsx_text(&s)
    testing.expect(t, raw_text.kind == .Jsx_Text &&
                   raw_text.byte_start == 5 && raw_text.byte_end == 15,
                   "JSX text retains raw emoji bytes")
    start, ok_start := source.source_position(&version, raw_text.byte_start)
    finish, ok_end := source.source_position(&version, raw_text.byte_end)
    testing.expect(t, ok_start && ok_end && start.absolute_utf16 == 5 &&
                   finish.absolute_utf16 == 13, "Unicode JSX UTF-16 positions")
    closing_less := scanner_next_jsx_text(&s)
    testing.expect(t, closing_less.kind == .Less_Than, "JSX text ends at next markup")
    testing.expect(t, scanner_next(&s).kind == .Slash, "closing tag slash")
    testing.expect(t, scanner_next(&s).kind == .Identifier, "closing tag name")
    testing.expect(t, scanner_next(&s).kind == .Greater_Than, "closing tag end")
    testing.expect(t, scanner_next(&s).kind == .End_Of_File, "JSX EOF")
}

@(test)
scanner_jsx_wrong_mode_fails_closed :: proc(t: ^testing.T) {
    v, ok := source.source_version_create(source.File_Id(51), 1, ">hello<")
    testing.expect(t, ok, "valid source")
    defer source.source_version_destroy(&v)
    s := scanner_init(&v)
    greater := scanner_next(&s)
    testing.expect(t, scanner_begin_jsx_text(&s, greater), "explicit mode entry")
    invalid := scanner_next(&s)
    testing.expect(t, invalid.kind == .Invalid && invalid.error == .Unsupported_Context,
                   "ordinary scanner cannot silently skip JSX raw text")
    testing.expect(t, scanner_next(&s).error == .Previous_Failure, "mode misuse sticky")
}


@(test)
scanner_boolean_literal_keywords_are_distinct :: proc(t: ^testing.T) {
    source_text := "const yes: boolean = true; let no = false; let trueValue = true;"
    v, ok := source.source_version_create(source.File_Id(610), 1, source_text)
    testing.expect(t, ok, "boolean fixture valid")
    defer source.source_version_destroy(&v)
    s := scanner_init(&v)
    expected := [?]Token_Kind{
        .Const, .Identifier, .Colon, .Boolean_Keyword, .Equals,
        .True_Keyword, .Semicolon, .Let, .Identifier, .Equals,
        .False_Keyword, .Semicolon, .Let, .Identifier, .Equals,
        .True_Keyword, .Semicolon, .End_Of_File,
    }
    for wanted in expected {
        tok := scanner_next(&s)
        testing.expect(t, tok.kind == wanted && tok.error == .None,
                       "boolean keywords require complete lexeme match")
    }
}


@(test)
scanner_comparison_and_logical_longest_tokens :: proc(t: ^testing.T) {
    input := "a < b <= c > d >= e === f !== g && h || !i;"
    v, ok := source.source_version_create(source.File_Id(710), 1, input)
    testing.expect(t, ok, "valid token source")
    defer source.source_version_destroy(&v)
    s := scanner_init(&v)
    expected := [?]Token_Kind{
        .Identifier, .Less_Than, .Identifier, .Less_Than_Equals,
        .Identifier, .Greater_Than, .Identifier, .Greater_Than_Equals,
        .Identifier, .Equals_Equals_Equals, .Identifier, .Exclamation_Equals_Equals,
        .Identifier, .Ampersand_Ampersand, .Identifier, .Bar_Bar,
        .Exclamation, .Identifier, .Semicolon, .End_Of_File,
    }
    for wanted in expected {
        token := scanner_next(&s)
        testing.expect(t, token.kind == wanted && token.error == .None,
                       "longest token match and stable ordering")
    }
}

@(test)
scanner_rejects_unimplemented_loose_equality :: proc(t: ^testing.T) {
    cases := [?]string{"a == b;", "a != b;", "a & b;", "a | b;"}
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(711), 1, input)
        testing.expect(t, ok, "valid UTF-8 source")
        s := scanner_init(&v)
        _ = scanner_next(&s)
        token := scanner_next(&s)
        testing.expect(t, token.kind == .Invalid && token.error == .Unsupported_Syntax,
                       "unsupported punctuation fails closed")
        testing.expect(t, scanner_next(&s).error == .Previous_Failure,
                       "failure must remain sticky")
        source.source_version_destroy(&v)
    }
}
