package main

import "core:fmt"
import "core:os"
import "../source"
import "../scanner"
import lexcontext "../context"

// Developer-only fixture driver; "regex" mode explicitly marks one slash
// as the start of a regexp. This is NOT a TypeScript parser or heuristic.
main :: proc() {
    if len(os.args) != 3 {
        fmt.println("usage: contexttrace <regex|template> <source-file>")
        os.exit(2)
    }
    mode := os.args[1]
    if mode != "regex" && mode != "template" {
        fmt.println("error: unknown lexical fixture mode")
        os.exit(2)
    }
    bytes, err := os.read_entire_file(os.args[2], context.allocator)
    if err != nil {
        fmt.println("error: unable to read fixture")
        os.exit(2)
    }
    defer delete(bytes)
    source_version, valid := source.source_version_create(source.File_Id(1), 1, transmute(string)bytes)
    if !valid {
        fmt.println("error: invalid UTF-8")
        os.exit(2)
    }
    defer source.source_version_destroy(&source_version)
    reader := lexcontext.reader_init(&source_version)
    after_semicolon := false
    for {
        token := lexcontext.reader_next(&reader)
        if mode == "regex" && after_semicolon && token.kind == .Slash {
            token = lexcontext.reader_rescan_regex(&reader, token)
            after_semicolon = false
        }
        if token.error != .None || token.kind == .Invalid {
            fmt.println("error: unsupported lexical fixture")
            os.exit(2)
        }
        start, valid_start := source.source_position(&source_version, token.byte_start)
        finish, valid_finish := source.source_position(&source_version, token.byte_end)
        if !valid_start || !valid_finish {
            fmt.println("error: invalid Unicode span")
            os.exit(2)
        }
        fmt.printf("%d\t%d\t%d\n", int(token.kind), start.absolute_utf16, finish.absolute_utf16)
        if token.kind == .Semicolon {
            after_semicolon = true
        }
        if token.kind == .End_Of_File {
            break
        }
    }
}
