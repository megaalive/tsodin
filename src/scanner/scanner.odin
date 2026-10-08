package scanner

import "../source"
import "../compat"

// M1-B explicitly limited ASCII lexical subset. Context-sensitive slash,
// template, JSX, Unicode identifiers, number formats and escaped strings
// intentionally fail closed until a pinned TypeScript oracle validates them.
Token_Kind :: enum {
    Invalid,
    End_Of_File,
    Identifier,
    Integer_Literal,
    String_Literal,
    Let,
    Const,
    Var,
    Number_Keyword,
    String_Keyword,
    Boolean_Keyword,
    Colon,
    Semicolon,
    Equals,
    Comma,
    Open_Paren,
    Close_Paren,
    Open_Brace,
    Close_Brace,
    Plus,
    Minus,
    Asterisk,
    // Appended only: preserve the ordinals used by the pinned lexical witness.
    Slash,
    Slash_Equals,
    Less_Than,
    Greater_Than,
    Regular_Expression_Literal,
    No_Substitution_Template,
    Template_Head,
    Template_Middle,
    Template_Tail,
    Jsx_Tag_Start,
    Jsx_Text,
}

Scan_Error :: enum {
    None,
    Invalid_Source,
    Unsupported_Syntax,
    Unterminated_String,
    Unterminated_Block_Comment,
    Previous_Failure,
    Unsupported_Profile,
    Unsupported_Context,
    Unterminated_Regular_Expression,
    Unterminated_Template,
}

Token :: struct {
    kind: Token_Kind,
    byte_start: int,
    byte_end: int,
    error: Scan_Error,
}

Scanner :: struct {
    // INVARIANT: the owning immutable Source_Version must outlive this scanner.
    version: ^source.Source_Version,
    profile: compat.Profile,
    offset: int,
    failed: bool,
    // A contextual rescan can consume only the last lexed boundary token.
    context_token: Token,
    jsx_text_mode: bool,
}

// Existing callers use the pinned profile, but every scanner instance
// explicitly carries the selected compatibility contract.
scanner_init :: proc(version: ^source.Source_Version) -> Scanner {
    return scanner_init_with_profile(version, compat.ts7_profile())
}

scanner_init_with_profile :: proc(version: ^source.Source_Version, profile: compat.Profile) -> Scanner {
    return Scanner{version=version, profile=profile}
}

ascii_identifier_start :: proc(b: u8) -> bool {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') ||
           b == '_' || b == '$'
}

ascii_identifier_continue :: proc(b: u8) -> bool {
    return ascii_identifier_start(b) || (b >= '0' && b <= '9')
}

scanner_error :: proc(s: ^Scanner, start: int, error: Scan_Error) -> Token {
    s.failed = true
    s.context_token = Token{}
    s.jsx_text_mode = false
    return Token{kind=.Invalid, byte_start=start, byte_end=s.offset, error=error}
}

scanner_next :: proc(s: ^Scanner) -> Token {
    if s.failed {
        return Token{kind=.Invalid, byte_start=s.offset, byte_end=s.offset, error=.Previous_Failure}
    }
    if s.version == nil || !s.version.initialized {
        return scanner_error(s, 0, .Invalid_Source)
    }

    // Never parse a future TS edition using an unreviewed older policy.
    if !compat.profile_is_registered(s.profile) {
        return scanner_error(s, s.offset, .Unsupported_Profile)
    }

    if s.jsx_text_mode {
        return scanner_error(s, s.offset, .Unsupported_Context)
    }
    s.context_token = Token{}
    text := s.version.owned_text

    // Trivia is skipped, never exposed as a semantic token.
    for s.offset < len(text) {
        c := text[s.offset]
        if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
            s.offset += 1
            continue
        }
        if c == 0xE2 && s.offset + 2 < len(text) && text[s.offset+1] == 0x80 &&
           (text[s.offset+2] == 0xA8 || text[s.offset+2] == 0xA9) {
            s.offset += 3
            continue
        }

        if c == '/' && s.offset + 1 < len(text) {
            next := text[s.offset+1]
            if next == '/' {
                s.offset += 2
                for s.offset < len(text) {
                    b := text[s.offset]
                    if b == '\r' || b == '\n' {
                        break
                    }
                    if b == 0xE2 && s.offset + 2 < len(text) &&
                       text[s.offset+1] == 0x80 &&
                       (text[s.offset+2] == 0xA8 || text[s.offset+2] == 0xA9) {
                        break
                    }
                    s.offset += 1
                }
                continue
            }
            if next == '*' {
                start := s.offset
                s.offset += 2
                closed := false
                for s.offset + 1 < len(text) {
                    if text[s.offset] == '*' && text[s.offset+1] == '/' {
                        s.offset += 2
                        closed = true
                        break
                    }
                    s.offset += 1
                }
                if !closed {
                    s.offset = len(text)
                    return scanner_error(s, start, .Unterminated_Block_Comment)
                }
                continue
            }
        }
        break
    }

    start := s.offset
    if start == len(text) {
        return Token{kind=.End_Of_File, byte_start=start, byte_end=start}
    }

    c := text[start]
    if c == '`' {
        return scan_template_part(s, false)
    }
    if ascii_identifier_start(c) {
        s.offset += 1
        for s.offset < len(text) && ascii_identifier_continue(text[s.offset]) {
            s.offset += 1
        }
        lexeme := text[start:s.offset]
        kind := Token_Kind.Identifier
        if lexeme == "let" {
            kind = .Let
        } else if lexeme == "const" {
            kind = .Const
        } else if lexeme == "var" {
            kind = .Var
        } else if lexeme == "number" {
            kind = .Number_Keyword
        } else if lexeme == "string" {
            kind = .String_Keyword
        } else if lexeme == "boolean" {
            kind = .Boolean_Keyword
        }
        return Token{kind=kind, byte_start=start, byte_end=s.offset}
    }

    if c >= '0' && c <= '9' {
        s.offset += 1
        for s.offset < len(text) && text[s.offset] >= '0' && text[s.offset] <= '9' {
            s.offset += 1
        }
        return Token{kind=.Integer_Literal, byte_start=start, byte_end=s.offset}
    }

    if c == '"' || c == '\'' {
        quote := c
        s.offset += 1
        for s.offset < len(text) {
            at := text[s.offset]
            if at == quote {
                s.offset += 1
                return Token{kind=.String_Literal, byte_start=start, byte_end=s.offset}
            }
            if at == '\\' || at >= 0x80 {
                // No invented semantics for escapes or non-ASCII string bodies yet.
                s.offset += 1
                return scanner_error(s, start, .Unsupported_Syntax)
            }
            if at == '\n' || at == '\r' {
                return scanner_error(s, start, .Unterminated_String)
            }
            s.offset += 1
        }
        return scanner_error(s, start, .Unterminated_String)
    }

    kind := Token_Kind.Invalid
    switch c {
    case ':': kind = .Colon
    case ';': kind = .Semicolon
    case '=': kind = .Equals
    case ',': kind = .Comma
    case '(': kind = .Open_Paren
    case ')': kind = .Close_Paren
    case '{': kind = .Open_Brace
    case '}': kind = .Close_Brace
    case '+': kind = .Plus
    case '-': kind = .Minus
    case '*': kind = .Asterisk
    case '/':
        if start + 1 < len(text) && text[start+1] == '=' {
            kind = .Slash_Equals
            s.offset += 1
        } else {
            kind = .Slash
        }
    case '<': kind = .Less_Than
    case '>': kind = .Greater_Than
    }
    s.offset += 1
    if kind == .Slash || kind == .Close_Brace ||
       kind == .Less_Than || kind == .Greater_Than {
        s.context_token = Token{kind=kind, byte_start=start, byte_end=s.offset}
    }
    if kind == .Invalid {
        return scanner_error(s, start, .Unsupported_Syntax)
    }
    return Token{kind=kind, byte_start=start, byte_end=s.offset}
}


// Contextual rescans are parser decisions; scanner_next never guesses from
// neighboring token kinds whether '/' is division or a regex.
context_token_matches :: proc(s: ^Scanner, token: Token, kind: Token_Kind) -> bool {
    return !s.failed && s.version != nil && s.version.initialized &&
           compat.profile_is_registered(s.profile) &&
           token.kind == kind && s.context_token.kind == kind &&
           token.byte_start == s.context_token.byte_start &&
           token.byte_end == s.context_token.byte_end && s.offset == token.byte_end
}

// A subset of ASCII regex bodies, character classes and ASCII flags. This is
// a lexical span operation, NOT validation of JavaScript regex semantics.
scanner_rescan_slash_as_regex :: proc(s: ^Scanner, slash: Token) -> Token {
    if !context_token_matches(s, slash, .Slash) {
        return scanner_error(s, s.offset, .Unsupported_Context)
    }
    text := s.version.owned_text
    start := slash.byte_start
    in_class := false
    escaped := false
    s.context_token = Token{}

    for s.offset < len(text) {
        c := text[s.offset]
        if c == '\n' || c == '\r' ||
           (c == 0xE2 && s.offset + 2 < len(text) &&
            text[s.offset+1] == 0x80 &&
            (text[s.offset+2] == 0xA8 || text[s.offset+2] == 0xA9)) {
            return scanner_error(s, start, .Unterminated_Regular_Expression)
        }
        if c >= 0x80 {
            return scanner_error(s, start, .Unsupported_Syntax)
        }
        s.offset += 1
        if escaped {
            escaped = false
            continue
        }
        if c == '\\' {
            escaped = true
            continue
        }
        if c == '[' {
            in_class = true
            continue
        }
        if c == ']' && in_class {
            in_class = false
            continue
        }
        if c == '/' && !in_class {
            // Only flags from the supported lexical subset are accepted.
            flags: u32 = 0
            for s.offset < len(text) {
                f := text[s.offset]
                if (f >= 'a' && f <= 'z') || (f >= 'A' && f <= 'Z') {
                    allowed := "dgimsuvy"
                    index := -1
                    for j in 0..<len(allowed) {
                        if allowed[j] == f {
                            index = j
                            break
                        }
                    }
                    if index < 0 || (flags & (u32(1) << u32(index))) != 0 {
                        s.offset += 1
                        return scanner_error(s, start, .Unsupported_Syntax)
                    }
                    flags |= u32(1) << u32(index)
                    s.offset += 1
                } else {
                    break
                }
            }
            // Unicode and Unicode-sets flags cannot be combined.
            if (flags & (u32(1) << 5)) != 0 && (flags & (u32(1) << 6)) != 0 {
                return scanner_error(s, start, .Unsupported_Syntax)
            }
            return Token{kind=.Regular_Expression_Literal, byte_start=start, byte_end=s.offset}
        }
    }
    return scanner_error(s, start, .Unterminated_Regular_Expression)
}

// A template tail starts at the closing '}' token, which the parser must
// explicitly request rescanning. This matches the lexer/parser boundary.
scan_template_part :: proc(s: ^Scanner, resuming: bool) -> Token {
    text := s.version.owned_text
    start := s.offset
    if start >= len(text) {
        return scanner_error(s, start, .Unterminated_Template)
    }
    opener := text[start]
    if (!resuming && opener != '`') || (resuming && opener != '}') {
        return scanner_error(s, start, .Unsupported_Context)
    }
    s.offset += 1
    for s.offset < len(text) {
        c := text[s.offset]
        if c == '\\' {
            // Escape the next byte for delimiter purposes. UTF-8 was validated
            // by Source_Version before this scan; raw text is left unchanged.
            s.offset += 1
            if s.offset == len(text) {
                return scanner_error(s, start, .Unterminated_Template)
            }
            s.offset += 1
            continue
        }
        if c == '`' {
            s.offset += 1
            kind := Token_Kind.No_Substitution_Template
            if resuming {
                kind = .Template_Tail
            }
            return Token{kind=kind, byte_start=start, byte_end=s.offset}
        }
        if c == '$' && s.offset + 1 < len(text) && text[s.offset+1] == '{' {
            s.offset += 2
            kind := Token_Kind.Template_Head
            if resuming {
                kind = .Template_Middle
            }
            return Token{kind=kind, byte_start=start, byte_end=s.offset}
        }
        s.offset += 1
    }
    return scanner_error(s, start, .Unterminated_Template)
}

scanner_rescan_close_brace_as_template :: proc(s: ^Scanner, closing: Token) -> Token {
    if !context_token_matches(s, closing, .Close_Brace) {
        return scanner_error(s, s.offset, .Unsupported_Context)
    }
    s.offset = closing.byte_start
    s.context_token = Token{}
    return scan_template_part(s, true)
}

scanner_rescan_less_than_as_jsx_tag_start :: proc(s: ^Scanner, less: Token) -> Token {
    if !context_token_matches(s, less, .Less_Than) {
        return scanner_error(s, s.offset, .Unsupported_Context)
    }
    s.context_token = Token{}
    return Token{kind=.Jsx_Tag_Start, byte_start=less.byte_start, byte_end=less.byte_end}
}

// JSX text is selected only after the parser knows it just read an opening
// tag's '>'. The default scanner never treats ordinary TS operators as JSX.
scanner_begin_jsx_text :: proc(s: ^Scanner, greater: Token) -> bool {
    if !context_token_matches(s, greater, .Greater_Than) {
        s.failed = true
        s.context_token = Token{}
        return false
    }
    s.context_token = Token{}
    s.jsx_text_mode = true
    return true
}

scanner_next_jsx_text :: proc(s: ^Scanner) -> Token {
    if s.failed || !s.jsx_text_mode || s.version == nil ||
       !s.version.initialized || !compat.profile_is_registered(s.profile) {
        return scanner_error(s, s.offset, .Unsupported_Context)
    }
    text := s.version.owned_text
    start := s.offset
    for s.offset < len(text) {
        c := text[s.offset]
        if c == '<' || c == '{' {
            break
        }
        // Raw JSX text may include spaces, line breaks or valid UTF-8.
        s.offset += 1
    }
    if s.offset > start {
        return Token{kind=.Jsx_Text, byte_start=start, byte_end=s.offset}
    }
    s.jsx_text_mode = false
    return scanner_next(s)
}
