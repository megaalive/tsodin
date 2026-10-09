package main

import "core:fmt"
import "core:os"
import "../source"
import "../parser"
import "../binder"
import "../checker"
import "../compat"

// Internal CHECKER-ONLY performance probe. Parse and bind once, then repeat
// the real .None checker path; no diagnostics or semantic work are skipped.
// All historical lanes build this identical driver at the same Odin revision.
BENCH_REPETITIONS :: 8192

main :: proc() {
    if len(os.args) != 2 {
        fmt.println("usage: checkbench <typescript-source-file>")
        os.exit(2)
    }
    bytes, file_error := os.read_entire_file(os.args[1], context.allocator)
    if file_error != nil {
        fmt.println("error: cannot read benchmark input")
        os.exit(2)
    }
    defer delete(bytes)

    version, valid := source.source_version_create(
        source.File_Id(1), 1, transmute(string)bytes)
    if !valid {
        fmt.println("error: benchmark input must be valid UTF-8")
        os.exit(2)
    }
    defer source.source_version_destroy(&version)
    syntax := parser.parse_expression_program(&version, compat.ts7_profile())
    defer parser.syntax_report_destroy(&syntax)
    if !syntax.complete || syntax.fatal || len(syntax.diagnostics) != 0 {
        fmt.println("error: syntax rejected by the restricted checker")
        os.exit(2)
    }
    bound := binder.bind_program(&version, &syntax)
    defer binder.binding_report_destroy(&bound)
    if !bound.complete || bound.fatal || len(bound.issues) != 0 {
        fmt.println("error: binder rejected benchmark input")
        os.exit(2)
    }

    checksum: u64 = 0
    diagnostic_count: int = -1
    for _ in 0..<BENCH_REPETITIONS {
        // PERF: the actual public-internal checker .None path, with normal
        // transient allocations and report destruction on every iteration.
        checked := checker.check_file(&version, &syntax, &bound)
        if checked.fatal {
            fmt.println("error: checker failed closed on the benchmark input")
            checker.report_destroy(&checked)
            os.exit(2)
        }
        if diagnostic_count == -1 {
            diagnostic_count = len(checked.diagnostics)
        } else if len(checked.diagnostics) != diagnostic_count {
            fmt.println("error: nondeterministic diagnostic count")
            checker.report_destroy(&checked)
            os.exit(2)
        }
        // Consume each real checker's result, including diagnostic identity
        // and byte ranges, to discourage dead-work removal.
        checksum += u64(checked.checked_declarations) * 257
        checksum += u64(checked.checked_assignments) * 31
        checksum += u64(len(checked.diagnostics)) * 19
        if checked.complete { checksum += 1 }
        for issue in checked.diagnostics {
            checksum += u64(int(issue.issue)) * 101
            checksum += u64(issue.byte_start) * 7
            checksum += u64(issue.byte_end)
        }
        checker.report_destroy(&checked)
    }
    fmt.printf("RESULT\t%d\t%d\t%d\n",
        BENCH_REPETITIONS, diagnostic_count, checksum)
}
