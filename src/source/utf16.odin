package source

// Reference-only conversion from a UTF-8 byte prefix into UTF-16 code units.
// INVARIANT: byte_end must end at a Unicode scalar boundary and the source must
// contain well-formed UTF-8. A failed conversion must not return a usable span.
// COMPAT: JavaScript/TypeScript diagnostics use UTF-16 code-unit offsets.
// PERF: this O(prefix length) reference implementation must not become the
// per-diagnostic production path; a source-owned line index comes in M1.
utf16_prefix_units :: proc(text: string, byte_end: int) -> (u32, bool) {
    if byte_end < 0 || byte_end > len(text) {
        return 0, false
    }

    units: u32 = 0
    i := 0
    for i < byte_end {
        lead := text[i]
        if lead < 0x80 {
            units += 1
            i += 1
            continue
        }

        width := 0
        scalar: u32 = 0
        minimum: u32 = 0
        if lead >= 0xC2 && lead <= 0xDF {
            width = 2
            scalar = u32(lead & 0x1F)
            minimum = 0x80
        } else if lead >= 0xE0 && lead <= 0xEF {
            width = 3
            scalar = u32(lead & 0x0F)
            minimum = 0x800
        } else if lead >= 0xF0 && lead <= 0xF4 {
            width = 4
            scalar = u32(lead & 0x07)
            minimum = 0x10000
        } else {
            return 0, false
        }

        // A partial UTF-8 scalar does not have a valid UTF-16 prefix offset.
        if i + width > byte_end {
            return 0, false
        }
        for j := 1; j < width; j += 1 {
            continuation := text[i+j]
            if continuation & 0xC0 != 0x80 {
                return 0, false
            }
            scalar = (scalar << 6) | u32(continuation & 0x3F)
        }

        if scalar < minimum || scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF) {
            return 0, false
        }

        units += 1
        if scalar > 0xFFFF {
            units += 1
        }
        i += width
    }

    return units, true
}
