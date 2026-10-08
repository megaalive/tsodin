package scanner

import "../source"

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
}

Scan_Error :: enum {
    None,
    Invalid_Source,
    Unsupported_Syntax,
    Unterminated_String,
    Unterminated_Block_Comment,
    Previous_Failure,
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
    offset: int,
    failed: bool,
}

scanner_init :: proc(version: ^source.Source_Version) -> Scanner {
    return Scanner{version=version}
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
    return Token{kind=.Invalid, byte_start=start, byte_end=s.offset, error=error}
}

scanner_next :: proc(s: ^Scanner) -> Token {
    if s.failed {
        return Token{kind=.Invalid, byte_start=s.offset, byte_end=s.offset, error=.Previous_Failure}
    }
    if s.version == nil || !s.version.initialized {
        return scanner_error(s, 0, .Invalid_Source)
    }

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
    }
    s.offset += 1
    if kind == .Invalid {
        return scanner_error(s, start, .Unsupported_Syntax)
    }
    return Token{kind=kind, byte_start=start, byte_end=s.offset}
}
