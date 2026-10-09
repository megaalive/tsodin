package project

// Config comments are lexical trivia, not a change to JSON's value grammar.
// The output is the same byte length, with comment bytes replaced by spaces,
// preserving line endings and strings. All callers own and delete the buffer.
//
// Mirrors the relevant TS config tokenizer cases from Microsoft TypeScript
// tsoptions/tsconfigparsing_test.go (audited at aad4c72). This is a bounded
// adapter, not a replacement for the TypeScript JSON source parser.
strip_jsonc_comments :: proc(text: string) -> ([]u8, bool) {
    out := make([]u8, len(text))
    copy(out, text)
    in_string := false
    i := 0
    for i < len(text) {
        b := text[i]
        if in_string {
            if b == '\\' && i + 1 < len(text) {
                // Backslash escapes exactly the next byte; even numbers of
                // backslashes therefore leave a subsequent quote unescaped.
                i += 2
                continue
            }
            if b == '"' {
                in_string = false
            }
            i += 1
            continue
        }
        if b == '"' {
            in_string = true
            i += 1
            continue
        }
        if b == '/' && i + 1 < len(text) && text[i+1] == '/' {
            out[i] = ' '
            out[i+1] = ' '
            i += 2
            for i < len(text) && text[i] != '\n' && text[i] != '\r' {
                out[i] = ' '
                i += 1
            }
            continue
        }
        if b == '/' && i + 1 < len(text) && text[i+1] == '*' {
            out[i] = ' '
            out[i+1] = ' '
            i += 2
            terminated := false
            for i < len(text) {
                if text[i] == '*' && i+1 < len(text) && text[i+1] == '/' {
                    out[i] = ' '
                    out[i+1] = ' '
                    i += 2
                    terminated = true
                    break
                }
                if text[i] != '\n' && text[i] != '\r' {
                    out[i] = ' '
                }
                i += 1
            }
            if !terminated {
                delete(out)
                return nil, false
            }
            continue
        }
        i += 1
    }
    return out, true
}
