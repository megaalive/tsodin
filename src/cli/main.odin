package main

import "core:fmt"
import "core:os"
import "../dump"
import "../project"

VERSION :: "0.0.0-dev"

main :: proc() {
    if len(os.args) == 2 && os.args[1] == "--version" {
        fmt.printf("tsodin %s\n", VERSION)
        return
    }

    if len(os.args) == 1 || (len(os.args) == 2 && os.args[1] == "--help") {
        fmt.println("tsodin — experimental Odin TypeScript checker")
        fmt.println("Usage: tsodin --version | --help | dump --stage=all [--trace-relations] <file.ts> | check -p <tsconfig.json>")
        fmt.println("Project preflight is available; type checking is not implemented.")
        return
    }

    if os.args[1] == "dump" {
        if len(os.args) >= 3 && os.args[2] == "--stage=all" {
            if len(os.args) == 4 && dump.write(os.args[3], false) { return }
            if len(os.args) == 5 && os.args[3] == "--trace-relations" &&
               dump.write(os.args[4], true) { return }
        }
        fmt.eprintln("error: usage: tsodin dump --stage=all [--trace-relations] <file.ts>")
        os.exit(2)
    }

    if os.args[1] == "check" {
        if len(os.args) == 4 && os.args[2] == "-p" {
            p, err := project.load(os.args[3])
            defer project.project_destroy(&p)
            if err != .None {
                fmt.eprintf("error: project preflight failed (%v), config=%v, file=%d\n",
                            err, p.config_error, p.error_file_index)
                os.exit(2)
            }
            if !p.binding.complete {
                fmt.eprintf("error: project preflight incomplete (fatal=%v, issues=%d)\n",
                            p.binding.fatal, len(p.binding.issues))
                os.exit(2)
            }
            fmt.eprintf("unsupported: %d project files parsed and bound; TypeScript type checking is not implemented\n",
                        len(p.files))
            os.exit(2)
        }
        fmt.eprintln("error: tsodin check is not implemented; refusing a false success")
        os.exit(2)
    }

    fmt.eprintln("error: unsupported command; run tsodin --help")
    os.exit(2)
}
