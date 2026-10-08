package main

import "core:fmt"
import "core:os"
import "../source"
import "../parser"
import "../binder"
import "../checker"
import "../compat"

// Developer-only checker trace. The public tsodin check command still rejects
// unsupported work. Internal diagnostic kinds are NOT TypeScript codes.
// Exit: 0 completed supported slice, 1 type mismatch, 2 unsupported/fatal.
main :: proc() {
    if len(os.args) != 2 {
        fmt.println("usage: checktrace <typescript-source-file>")
        os.exit(2)
    }
    bytes, err := os.read_entire_file(os.args[1], context.allocator)
    if err != nil {
        fmt.println("error: unable to read source")
        os.exit(2)
    }
    defer delete(bytes)
    version, valid := source.source_version_create(source.File_Id(1), 1, transmute(string)bytes)
    if !valid {
        fmt.println("error: source is not well-formed UTF-8")
        os.exit(2)
    }
    defer source.source_version_destroy(&version)
    syntax := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&syntax)
    bound := binder.bind_program(&version, &syntax)
    defer binder.binding_report_destroy(&bound)
    checked := checker.check_file(&version, &syntax, &bound)
    defer checker.report_destroy(&checked)
    for issue in checked.diagnostics {
        start, a := source.source_position(&version, issue.byte_start)
        end, b := source.source_position(&version, issue.byte_end)
        if !a || !b {
            fmt.println("error: checker diagnostic has invalid UTF-16 boundary")
            os.exit(2)
        }
        fmt.printf("DIAG\t%d\t%d\t%d\t%d\t%d\n",
                   int(issue.issue), start.line, start.column_utf16,
                   end.line, end.column_utf16)
    }
    exit_code: int = 0
    if checked.fatal {
        exit_code = 2
    } else if !checked.complete {
        exit_code = 1
    }
    fmt.printf("SUMMARY\t%d\t%d\t%d\n",
               checked.checked_declarations, len(checked.diagnostics), exit_code)
    if exit_code != 0 {
        os.exit(exit_code)
    }
}
