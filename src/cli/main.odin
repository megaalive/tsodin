package main

import "core:fmt"
import "core:os"

VERSION :: "0.0.0-dev"

main :: proc() {
    if len(os.args) == 2 && os.args[1] == "--version" {
        fmt.printf("tsodin %s\n", VERSION)
        return
    }

    if len(os.args) == 1 || (len(os.args) == 2 && os.args[1] == "--help") {
        fmt.println("tsodin — experimental Odin TypeScript checker")
        fmt.println("Usage: tsodin --version | --help")
        fmt.println("The check command is not implemented; no compatibility claims.")
        return
    }

    if os.args[1] == "check" {
        fmt.println("error: tsodin check is not implemented; refusing a false success")
        os.exit(2)
    }

    fmt.println("error: unsupported command; run tsodin --help")
    os.exit(2)
}
