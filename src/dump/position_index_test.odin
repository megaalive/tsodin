package dump

import "core:testing"
import "../source"

@(test)
position_index_preserves_scalar_boundaries_and_source_reference :: proc(t: ^testing.T) {
    // Deliberately straddle a 256-byte checkpoint with a four-byte scalar.
    input := make([]u8, 1024)
    defer delete(input)
    for i in 0..<len(input) { input[i] = 'a' }
    input[255] = 0xF0
    input[256] = 0x9F
    input[257] = 0x98
    input[258] = 0x80
    v, ok := source.source_version_create(source.File_Id(777), 1, transmute(string)input)
    testing.expect(t, ok, "valid Unicode crossing the checkpoint boundary")
    defer source.source_version_destroy(&v)
    idx, valid := position_index_create(&v)
    testing.expect(t, valid && len(idx.checkpoints)>2, "sparse owned checkpoints")
    defer position_index_destroy(&idx)
    for pos in 0..=len(v.owned_text) {
        expected, supported := source.source_position(&v, pos)
        actual, has_actual := position_utf16(&idx, pos)
        testing.expect(t, has_actual == supported &&
                       (!supported || expected.absolute_utf16 == actual),
                       "indexed and reference mappings agree at every byte offset")
    }
    _, invalid := position_utf16(&idx, len(v.owned_text)+1)
    testing.expect(t, !invalid, "out-of-range offsets fail closed")
}

@(test)
position_index_preserves_line_separators_and_empty_source :: proc(t: ^testing.T) {
    cases := [?]string{"", "a😀é\r\nB\u2028C\u2029D\rE\n", "abc"}
    for input in cases {
        v, ok := source.source_version_create(source.File_Id(778), 1, input)
        testing.expect(t, ok, "valid UTF-8 source")
        idx, indexed := position_index_create(&v)
        testing.expect(t, indexed, "index accepts existing immutable snapshot")
        for pos in 0..=len(v.owned_text) {
            expected, valid := source.source_position(&v, pos)
            actual, matched := position_utf16(&idx, pos)
            testing.expect(t, valid == matched &&
                           (!valid || expected.absolute_utf16 == actual),
                           "line breaks and non-BMP preserve absolute UTF-16")
        }
        position_index_destroy(&idx)
        source.source_version_destroy(&v)
    }
}
