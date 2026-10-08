package main

import "core:fmt"
import "core:os"
import "../source"
import "../parser"
import "../compat"

// Developer-only syntax diagnostic tracer. It does not perform type checking,
// does not emit TypeScript diagnostic codes, and is NOT the public check CLI.
// Exit 0 = accepted restricted grammar; 1 = syntax diagnostics; 2 = fatal input.
main :: proc() {
    if len(os.args) != 2 {
        fmt.println("usage: syntaxtrace <typescript-source-file>")
        os.exit(2)
    }
    bytes, file_error := os.read_entire_file(os.args[1], context.allocator)
    if file_error != nil {
        fmt.println("error: cannot read the requested source file")
        os.exit(2)
    }
    defer delete(bytes)

    version, valid := source.source_version_create(source.File_Id(1), 1, transmute(string)bytes)
    if !valid {
        fmt.println("error: unsupported or invalid UTF-8 source")
        os.exit(2)
    }
    defer source.source_version_destroy(&version)

    report := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&report)
    for diagnostic in report.diagnostics {
        start, start_ok := source.source_position(&version, diagnostic.byte_start)
        end, end_ok := source.source_position(&version, diagnostic.byte_end)
        if !start_ok || !end_ok {
            fmt.println("error: internal diagnostic points outside valid UTF-8 boundary")
            os.exit(2)
        }
        // Zero-based lines/columns, UTF-16 code units. Internal issue ordinal:
        // NOT a stable TypeScript diagnostic code or a parity claim.
        fmt.printf("DIAG\t%d\t%d\t%d\t%d\t%d\n",
            int(diagnostic.issue),
            start.line,
            start.column_utf16,
            end.line,
            end.column_utf16)
    }
    state: int = 0
    if report.fatal {
        state = 2
    } else if !report.complete {
        state = 1
    }
    fmt.printf("SUMMARY\t%d\t%d\t%d\n",
        len(report.declarations), len(report.diagnostics), state)
    if state != 0 {
        os.exit(state)
    }
}
