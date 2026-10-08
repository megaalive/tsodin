package context

import "../source"
import "../scanner"

// Parser-side lexical context, not a TypeScript grammar parser.
TEMPLATE_LIMIT :: 32

Template_Frame :: struct {
    brace_depth: int,
}

Reader :: struct {
    lexer: scanner.Scanner,
    templates: [TEMPLATE_LIMIT]Template_Frame,
    template_depth: int,
    last: scanner.Token,
}

reader_init :: proc(version: ^source.Source_Version) -> Reader {
    return Reader{lexer = scanner.scanner_init(version)}
}

reader_error :: proc(r: ^Reader, error: scanner.Scan_Error) -> scanner.Token {
    r.last = scanner.Token{}
    r.lexer.failed = true
    r.lexer.context_token = scanner.Token{}
    return scanner.Token {
        kind = .Invalid,
        byte_start = r.lexer.offset,
        byte_end = r.lexer.offset,
        error = error,
    }
}

// Template brace frames are fixed-size, source-scoped, and allocation-free.
// Regex/JSX context always requires an explicit parser decision.
reader_next :: proc(r: ^Reader) -> scanner.Token {
    token := scanner.scanner_next(&r.lexer)
    if token.kind == .Invalid {
        r.last = token
        return token
    }
    if token.kind == .End_Of_File && r.template_depth != 0 {
        return reader_error(r, .Unterminated_Template)
    }
    if token.kind == .Template_Head {
        if r.template_depth == TEMPLATE_LIMIT {
            return reader_error(r, .Unsupported_Context)
        }
        r.templates[r.template_depth] = Template_Frame{}
        r.template_depth += 1
    } else if r.template_depth > 0 {
        frame := &r.templates[r.template_depth - 1]
        if token.kind == .Open_Brace {
            frame.brace_depth += 1
        } else if token.kind == .Close_Brace {
            if frame.brace_depth > 0 {
                frame.brace_depth -= 1
            } else {
                token = scanner.scanner_rescan_close_brace_as_template(&r.lexer, token)
                if token.kind == .Template_Tail {
                    r.template_depth -= 1
                }
            }
        }
    }
    r.last = token
    return token
}

// The actual expression parser must opt in. No heuristic guesses regex from
// previous operators, and a stale token can never silently rewind the input.
reader_rescan_regex :: proc(r: ^Reader, slash: scanner.Token) -> scanner.Token {
    if slash.kind != .Slash ||
       r.last.byte_start != slash.byte_start ||
       r.last.byte_end != slash.byte_end ||
       r.last.kind != .Slash {
        return reader_error(r, .Unsupported_Context)
    }
    token := scanner.scanner_rescan_slash_as_regex(&r.lexer, slash)
    r.last = token
    return token
}
