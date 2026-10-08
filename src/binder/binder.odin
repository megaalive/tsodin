package binder

import "../parser"
import "../source"

// M3-A: one file scope only; no module/namespace or type-checker claim.
Issue_Kind :: enum {
    Invalid_Source,
    Syntax_Not_Complete,
    Snapshot_Mismatch,
    Duplicate_Declaration,
    Unresolved_Name,
}

Binding_Issue :: struct {
    kind: Issue_Kind,
    byte_start: int,
    byte_end: int,
}

Symbol :: struct {
    name_start: int,
    name_end: int,
    declaration_index: int,
    kind: parser.Declaration_Kind,
    declaration_count: int,
}

Reference :: struct {
    node_index: int,
    symbol_index: int,
    byte_start: int,
    byte_end: int,
}

Binding_Report :: struct {
    file_id: source.File_Id,
    generation: u32,
    symbols: [dynamic]Symbol,
    references: [dynamic]Reference,
    issues: [dynamic]Binding_Issue,
    complete: bool,
    fatal: bool,
}

binding_report_destroy :: proc(r: ^Binding_Report) {
    delete(r.symbols)
    delete(r.references)
    delete(r.issues)
    r^ = Binding_Report{}
}

// FNV-1a on ASCII spellings from the validated source snapshot.
symbol_hash :: proc(name: string) -> u64 {
    value: u64 = 14695981039346656037
    for byte in name {
        value = (value ~ u64(byte)) * 1099511628211
    }
    return value
}

// Empty bucket = 0; positive bucket = 1-based symbol index.
symbol_slot :: proc(text: string, symbols: []Symbol, slots: []int, name: string) -> (int, bool) {
    mask := len(slots) - 1
    slot := int(symbol_hash(name) & u64(mask))
    for _ in 0..<len(slots) {
        entry := slots[slot]
        if entry == 0 {
            return slot, false
        }
        existing := symbols[entry-1]
        if text[existing.name_start:existing.name_end] == name {
            return slot, true
        }
        slot = (slot+1) & mask
    }
    return -1, false
}

// Declared-symbol pass precedes name lookup. The map is temporary and
// allocates one bucket array, never separate heap objects per symbol.
bind_program :: proc(version: ^source.Source_Version, syntax: ^parser.Syntax_Report) -> Binding_Report {
    r: Binding_Report
    if version == nil || !version.initialized || syntax == nil {
        r.fatal = true
        append(&r.issues, Binding_Issue{kind=.Invalid_Source})
        return r
    }
    r.file_id = version.file_id
    r.generation = version.generation
    if syntax.file_id != version.file_id || syntax.generation != version.generation {
        r.fatal = true
        append(&r.issues, Binding_Issue{kind=.Snapshot_Mismatch})
        return r
    }
    if !syntax.complete || syntax.fatal || len(syntax.diagnostics) != 0 {
        r.fatal = true
        append(&r.issues, Binding_Issue{kind=.Syntax_Not_Complete})
        return r
    }
    capacity := 8
    for capacity <= len(syntax.declarations)*2 {
        capacity *= 2
    }
    slots := make([]int, capacity)
    defer delete(slots)
    text := version.owned_text
    for decl, i in syntax.declarations {
        if decl.name_start < 0 || decl.name_start >= decl.name_end ||
           decl.name_end > len(text) {
            r.fatal = true
            append(&r.issues, Binding_Issue{kind=.Invalid_Source})
            return r
        }
        name := text[decl.name_start:decl.name_end]
        slot, exists := symbol_slot(text, r.symbols[:], slots, name)
        if slot < 0 {
            r.fatal = true
            append(&r.issues, Binding_Issue{kind=.Invalid_Source})
            return r
        }
        if exists {
            symbol := &r.symbols[slots[slot]-1]
            if symbol.kind == .Var && decl.kind == .Var {
                symbol.declaration_count += 1
            } else {
                append(&r.issues, Binding_Issue{
                    kind=.Duplicate_Declaration,
                    byte_start=decl.name_start,
                    byte_end=decl.name_end,
                })
            }
        } else {
            id := len(r.symbols)
            append(&r.symbols, Symbol{
                name_start=decl.name_start,
                name_end=decl.name_end,
                declaration_index=i,
                kind=decl.kind,
                declaration_count=1,
            })
            slots[slot] = id+1
        }
    }
    // All expression Name nodes resolve through the same snapshot-owned bytes.
    for node, i in syntax.nodes {
        if node.kind != .Name {
            continue
        }
        if node.byte_start < 0 || node.byte_start >= node.byte_end ||
           node.byte_end > len(text) {
            r.fatal = true
            append(&r.issues, Binding_Issue{kind=.Invalid_Source})
            return r
        }
        slot, found := symbol_slot(text, r.symbols[:], slots, text[node.byte_start:node.byte_end])
        if !found {
            append(&r.issues, Binding_Issue{
                kind=.Unresolved_Name, byte_start=node.byte_start, byte_end=node.byte_end,
            })
        } else {
            append(&r.references, Reference{
                node_index=i, symbol_index=slots[slot]-1,
                byte_start=node.byte_start, byte_end=node.byte_end,
            })
        }
    }
    r.complete = !r.fatal && len(r.issues) == 0
    return r
}
