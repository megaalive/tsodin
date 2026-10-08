package source

import "core:testing"

@(test)
ascii_and_empty_prefixes :: proc(t: ^testing.T) {
    count, valid := utf16_prefix_units("abc", 0)
    testing.expect(t, valid && count == 0, "empty byte prefix is valid")
    count, valid = utf16_prefix_units("abc", 3)
    testing.expect(t, valid && count == 3, "ASCII bytes map one-to-one")
}

@(test)
supplementary_unicode_prefixes :: proc(t: ^testing.T) {
    text := "a😀é\n"
    count, valid := utf16_prefix_units(text, 1)
    testing.expect(t, valid && count == 1, "ASCII prefix")
    count, valid = utf16_prefix_units(text, 5)
    testing.expect(t, valid && count == 3, "supplementary scalar counts as two UTF-16 units")
    count, valid = utf16_prefix_units(text, 7)
    testing.expect(t, valid && count == 4, "two-byte scalar counts as one UTF-16 unit")
    count, valid = utf16_prefix_units(text, 8)
    testing.expect(t, valid && count == 5, "newline is one code unit")
}

@(test)
invalid_offsets_fail_closed :: proc(t: ^testing.T) {
    text := "a😀"
    _, valid := utf16_prefix_units(text, -1)
    testing.expect(t, !valid, "negative offsets are invalid")
    _, valid = utf16_prefix_units(text, 2)
    testing.expect(t, !valid, "inside a UTF-8 scalar is invalid")
    _, valid = utf16_prefix_units(text, 6)
    testing.expect(t, !valid, "past end is invalid")
}

@(test)
crlf_offsets :: proc(t: ^testing.T) {
    count, valid := utf16_prefix_units("x\r\n", 3)
    testing.expect(t, valid && count == 3, "CRLF are two code units in the raw buffer")
}
