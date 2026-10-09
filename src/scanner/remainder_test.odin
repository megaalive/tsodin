package scanner

import "core:testing"
import "../source"

@(test)
scanner_remainder_token_and_reject_assignment_form :: proc(t: ^testing.T) {
    version, valid := source.source_version_create(
        source.File_Id(920), 1, "const rem = 17 % 5;")
    testing.expect(t, valid, "source version exists")
    defer source.source_version_destroy(&version)
    s := scanner_init(&version)
    expected := [?]Token_Kind{
        .Const, .Identifier, .Equals, .Integer_Literal,
        .Percent, .Integer_Literal, .Semicolon, .End_Of_File,
    }
    for kind in expected {
        token := scanner_next(&s)
        testing.expect(t, token.kind==kind && token.error==.None,
                       "remainder scanner emits the exact token sequence")
        if kind==.Percent {
            testing.expect(t, token.byte_end-token.byte_start==1,
                           "percent occupies one source byte")
        }
    }
    unsupported, ok := source.source_version_create(
        source.File_Id(921), 1, "let n = 8; n %= 3;")
    testing.expect(t, ok, "assignment input is valid UTF-8")
    defer source.source_version_destroy(&unsupported)
    scanner := scanner_init(&unsupported)
    for _ in 0..<6 {
        token := scanner_next(&scanner)
        testing.expect(t, token.kind!=.Invalid, "ordinary prefix is valid")
    }
    next := scanner_next(&scanner)
    testing.expect(t, next.kind==.Invalid && next.error==.Unsupported_Syntax,
                   "unsupported percent-assign must fail closed")
}
