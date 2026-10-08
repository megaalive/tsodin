package source

import "core:testing"

@(test)
source_index_empty_and_ascii :: proc(t: ^testing.T) {
    version, ok := source_version_create(File_Id(3), 1, "")
    testing.expect(t, ok, "empty source initializes")
    defer source_version_destroy(&version)
    testing.expect(t, len(version.line_starts) == 1, "empty file has one line")
    testing.expect(t, version.total_utf16 == 0, "empty file has zero units")
    pos, valid := source_position(&version, 0)
    testing.expect(t, valid && pos.line == 0 && pos.column_utf16 == 0, "empty position")
    _, valid = source_position(&version, 1)
    testing.expect(t, !valid, "past-end fails closed")

    ascii, ok2 := source_version_create(File_Id(3), 2, "abc\ndef")
    testing.expect(t, ok2 && ascii.generation == 2, "new source generation")
    defer source_version_destroy(&ascii)
    testing.expect(t, len(ascii.line_starts) == 2, "LF creates a second line")
    pos, valid = source_position(&ascii, 4)
    testing.expect(t, valid && pos.line == 1 && pos.column_utf16 == 0 &&
                   pos.absolute_utf16 == 4, "line start position")
    pos, valid = source_position(&ascii, 7)
    testing.expect(t, valid && pos.line == 1 && pos.column_utf16 == 3 &&
                   pos.absolute_utf16 == 7, "last byte position")
}

@(test)
source_index_unicode_and_crlf :: proc(t: ^testing.T) {
    text := "a😀é\r\nB\u2028C\u2029D\rE\n"
    version, ok := source_version_create(File_Id(8), 100, text)
    testing.expect(t, ok, "Unicode source is valid")
    defer source_version_destroy(&version)
    testing.expect(t, len(version.line_starts) == 6, "CRLF and Unicode separators count as one line break each")
    testing.expect(t, version.total_utf16 == 14, "global UTF-16 count includes CRLF pair")
    // Byte offset 7: after a (1), emoji (4), e-acute (2).
    pos, valid := source_position(&version, 7)
    testing.expect(t, valid && pos.line == 0 && pos.column_utf16 == 4, "non-BMP column is two units")
    _, valid = source_position(&version, 3)
    testing.expect(t, !valid, "inside emoji is not a valid UTF-16 position")
    pos, valid = source_position(&version, 9)
    testing.expect(t, valid && pos.line == 1 && pos.column_utf16 == 0 &&
                   pos.absolute_utf16 == 6, "CRLF starts next line after both units")
    pos, valid = source_position(&version, 13)
    testing.expect(t, valid && pos.line == 2 && pos.column_utf16 == 0 &&
                   pos.absolute_utf16 == 8, "U+2028 separator is one UTF-16 unit")
    pos, valid = source_position(&version, 17)
    testing.expect(t, valid && pos.line == 3 && pos.column_utf16 == 0 &&
                   pos.absolute_utf16 == 10, "U+2029 separator")
    pos, valid = source_position(&version, len(text))
    testing.expect(t, valid && pos.line == 5 && pos.column_utf16 == 0 &&
                   pos.absolute_utf16 == version.total_utf16, "trailing newline creates empty line")
}

@(test)
source_index_rejects_invalid_utf8 :: proc(t: ^testing.T) {
    invalid := string([]u8{0x61, 0xE2, 0x28, 0xA1})
    version, ok := source_version_create(File_Id(1), 0, invalid)
    testing.expect(t, !ok && !version.initialized, "malformed UTF-8 must fail closed")
    source_version_destroy(&version)
    bad_surrogate := string([]u8{0xED, 0xA0, 0x80})
    _, ok = source_version_create(File_Id(1), 1, bad_surrogate)
    testing.expect(t, !ok, "UTF-8 surrogate encoding is rejected")
    bad_scalar := string([]u8{0xF4, 0x90, 0x80, 0x80})
    _, ok = source_version_create(File_Id(1), 1, bad_scalar)
    testing.expect(t, !ok, "out-of-range Unicode scalar is rejected")
}

@(test)
source_index_snapshot_identity :: proc(t: ^testing.T) {
    v1, ok1 := source_version_create(File_Id(12), 7, "a\n")
    v2, ok2 := source_version_create(File_Id(12), 8, "a😀\n")
    testing.expect(t, ok1 && ok2, "both independent versions initialize")
    defer source_version_destroy(&v1)
    defer source_version_destroy(&v2)
    testing.expect(t, v1.file_id == v2.file_id && v1.generation != v2.generation, "stable file id and distinct version")
    pos1, valid1 := source_position(&v1, 2)
    pos2, valid2 := source_position(&v2, 6)
    testing.expect(t, valid1 && valid2 && pos1.absolute_utf16 == 2 && pos2.absolute_utf16 == 4, "independent offsets")
    source_version_destroy(&v1)
    _, valid1 = source_position(&v1, 0)
    testing.expect(t, !valid1, "destroyed version rejects queries")
}
