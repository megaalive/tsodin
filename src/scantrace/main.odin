package main

import "core:fmt"
import "core:os"
import "../source"
import "../scanner"

// Developer-only trace command for exact UTF-16 lexical boundary comparisons.
// This is not the tsodin public check command and does not parse/typecheck TS.
main :: proc() {
    if len(os.args) != 2 {
        fmt.println("usage: scantrace <typescript-source-file>")
        os.exit(2)
    }

    bytes, err := os.read_entire_file(os.args[1], context.allocator)
    if err != nil {
        fmt.println("error: unable to read source")
        os.exit(2)
    }
    defer delete(bytes)

    snapshot, valid := source.source_version_create(
        source.File_Id(1), 1, transmute(string)bytes,
    )
    if !valid {
        fmt.println("error: source is not valid UTF-8")
        os.exit(2)
    }
    defer source.source_version_destroy(&snapshot)

    scanner_state := scanner.scanner_init(&snapshot)
    for {
        token := scanner.scanner_next(&scanner_state)
        if token.kind == .Invalid || token.error != .None {
            fmt.printf("error: unsupported token at byte %d (error=%d)\n",
                       token.byte_start, int(token.error))
            os.exit(2)
        }
        start, ok_start := source.source_position(&snapshot, token.byte_start)
        end, ok_end := source.source_position(&snapshot, token.byte_end)
        if !ok_start || !ok_end {
            fmt.println("error: invalid source span")
            os.exit(2)
        }
        fmt.printf("%d\t%d\t%d\n", int(token.kind),
                   start.absolute_utf16, end.absolute_utf16)
        if token.kind == .End_Of_File {
            break
        }
    }
}
