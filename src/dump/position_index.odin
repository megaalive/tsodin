package dump

import "../source"

// An opt-in, dump-only sparse absolute UTF-16 index. Source_Version and the
// public source_position reference path remain unchanged. Each checkpoint
// starts at a proven UTF-8 scalar boundary, so a query inside a scalar is
// still rejected by the exact reference decoder.
Position_Checkpoint :: struct {
    byte_offset: int,
    absolute_utf16: u32,
}

Position_Index :: struct {
    version: ^source.Source_Version, // borrowed; must outlive this index
    checkpoints: [dynamic]Position_Checkpoint,
}

POSITION_CHECKPOINT_BYTES :: 256

position_index_destroy :: proc(idx: ^Position_Index) {
    delete(idx.checkpoints)
    idx^ = Position_Index{}
}

// Source_Version already validated all UTF-8 scalars. The loop copies only
// their widths/counts, and checks its final count against that preflight.
position_index_create :: proc(v: ^source.Source_Version) -> (Position_Index, bool) {
    result: Position_Index
    if v == nil || !v.initialized { return result, false }
    result.version = v
    append(&result.checkpoints, Position_Checkpoint{0, 0})
    next_checkpoint := POSITION_CHECKPOINT_BYTES
    i := 0
    absolute: u32 = 0
    for i < len(v.owned_text) {
        if i >= next_checkpoint {
            append(&result.checkpoints, Position_Checkpoint{i, absolute})
            next_checkpoint = i + POSITION_CHECKPOINT_BYTES
        }
        lead := v.owned_text[i]
        if lead < 0x80 {
            i += 1
            absolute += 1
        } else if lead < 0xE0 {
            i += 2
            absolute += 1
        } else if lead < 0xF0 {
            i += 3
            absolute += 1
        } else {
            i += 4
            absolute += 2
        }
    }
    if absolute != v.total_utf16 || i != len(v.owned_text) {
        position_index_destroy(&result)
        return Position_Index{}, false
    }
    return result, true
}

position_utf16 :: proc(idx: ^Position_Index, byte_offset: int) -> (u32, bool) {
    if idx == nil || idx.version == nil || !idx.version.initialized ||
       len(idx.checkpoints) == 0 ||
       byte_offset < 0 || byte_offset > len(idx.version.owned_text) {
        return 0, false
    }
    low := 0
    high := len(idx.checkpoints)
    for low + 1 < high {
        mid := low + (high-low)/2
        if idx.checkpoints[mid].byte_offset <= byte_offset {
            low = mid
        } else {
            high = mid
        }
    }
    checkpoint := idx.checkpoints[low]
    remaining, valid := source.utf16_prefix_units(
        idx.version.owned_text[checkpoint.byte_offset:byte_offset],
        byte_offset - checkpoint.byte_offset,
    )
    if !valid { return 0, false }
    return checkpoint.absolute_utf16 + remaining, true
}
