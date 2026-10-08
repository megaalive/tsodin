package source

import "core:strings"

// File_Id identifies a logical file. Generation distinguishes independent
// snapshots of that file; neither value is a pointer or a file-system path.
File_Id :: distinct u32

Line_Start :: struct {
    byte_offset: int,
    utf16_offset: u32,
}

Source_Version :: struct {
    file_id: File_Id,
    generation: u32,

    // INVARIANT: owned_text and line_starts are owned by this value.
    // Call source_version_destroy once; do not copy Source_Version by value.
    // Call create/destroy with the same context allocator.
    owned_text: string,
    line_starts: [dynamic]Line_Start,
    total_utf16: u32,
    initialized: bool,
}

Source_Position :: struct {
    line: int, // Zero-based, matches TS line/column conventions at this boundary
    column_utf16: u32,
    absolute_utf16: u32,
}

// Build one immutable source snapshot. Validation must complete before any
// owned allocation or indexed lookups can observe the source.
source_version_create :: proc(file_id: File_Id, generation: u32, text: string) -> (Source_Version, bool) {
    result: Source_Version

    total, valid := utf16_prefix_units(text, len(text))
    if !valid {
        return result, false
    }

    // Keep the source alive independently of the caller's input buffer.
    result.owned_text = strings.clone(text)
    result.file_id = file_id
    result.generation = generation
    result.initialized = true
    result.total_utf16 = total
    result.line_starts = make([dynamic]Line_Start, 0, 8)
    append(&result.line_starts, Line_Start{0, 0})

    // The preflight proved this byte buffer is well-formed UTF-8.
    // This pass is linear in bytes and tracks global UTF-16 positions.
    i := 0
    units: u32 = 0
    for i < len(result.owned_text) {
        lead := result.owned_text[i]
        if lead == '\r' {
            i += 1
            units += 1
            if i < len(result.owned_text) && result.owned_text[i] == '\n' {
                i += 1
                units += 1
            }
            append(&result.line_starts, Line_Start{i, units})
            continue
        }
        if lead == '\n' {
            i += 1
            units += 1
            append(&result.line_starts, Line_Start{i, units})
            continue
        }
        if lead == 0xE2 && i + 2 < len(result.owned_text) &&
           result.owned_text[i+1] == 0x80 &&
           (result.owned_text[i+2] == 0xA8 || result.owned_text[i+2] == 0xA9) {
            // COMPAT: ECMAScript U+2028 LINE SEPARATOR / U+2029 PARAGRAPH SEPARATOR.
            i += 3
            units += 1
            append(&result.line_starts, Line_Start{i, units})
            continue
        }
        if lead < 0x80 {
            i += 1
            units += 1
        } else if lead < 0xE0 {
            i += 2
            units += 1
        } else if lead < 0xF0 {
            i += 3
            units += 1
        } else {
            i += 4
            units += 2
        }
    }
    return result, true
}

// The snapshot must not be used after destruction; callers can recreate a new
// generation rather than mutating existing offsets in place.
source_version_destroy :: proc(source: ^Source_Version) {
    if !source.initialized {
        return
    }
    delete(source.line_starts)
    delete(source.owned_text)
    source^ = Source_Version{}
}

// Position query: O(log line count + bytes in the containing line).
// The reference decoder validates the requested *line prefix*, so offsets
// inside multibyte scalars fail closed. No full-file rescan per query.
source_position :: proc(source: ^Source_Version, byte_offset: int) -> (Source_Position, bool) {
    result: Source_Position
    if !source.initialized || byte_offset < 0 || byte_offset > len(source.owned_text) {
        return result, false
    }

    low := 0
    high := len(source.line_starts)
    for low + 1 < high {
        mid := low + (high - low) / 2
        if source.line_starts[mid].byte_offset <= byte_offset {
            low = mid
        } else {
            high = mid
        }
    }

    line := source.line_starts[low]
    column, valid := utf16_prefix_units(
        source.owned_text[line.byte_offset:byte_offset],
        byte_offset - line.byte_offset,
    )
    if !valid {
        return result, false
    }
    result.line = low
    result.column_utf16 = column
    result.absolute_utf16 = line.utf16_offset + column
    return result, true
}
