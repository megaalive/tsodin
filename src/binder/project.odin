package binder

import "../parser"
import "../source"

// M3-B: explicitly-selected, script-global multi-file scope.
// No imports, exports, modules, packages, or tsconfig resolution.
Project_File :: struct {
    source_version: ^source.Source_Version,
    syntax: ^parser.Syntax_Report,
}

Project_Symbol :: struct {
    file_index: int,
    declaration_index: int,
    name_start: int,
    name_end: int,
    kind: parser.Declaration_Kind,
    declaration_count: int,
}

Project_Reference :: struct {
    file_index: int,
    node_index: int,
    symbol_index: int,
    byte_start: int,
    byte_end: int,
}

Project_Issue :: struct {
    kind: Issue_Kind,
    file_index: int,
    byte_start: int,
    byte_end: int,
}

Project_Report :: struct {
    symbols: [dynamic]Project_Symbol,
    references: [dynamic]Project_Reference,
    issues: [dynamic]Project_Issue,
    complete: bool,
    fatal: bool,
}

project_report_destroy :: proc(r: ^Project_Report) {
    delete(r.symbols)
    delete(r.references)
    delete(r.issues)
    r^ = Project_Report{}
}

project_slot :: proc(files: []Project_File, symbols: []Project_Symbol, slots: []int, name: string) -> (int, bool) {
    mask := len(slots)-1
    slot := int(symbol_hash(name) & u64(mask))
    for _ in 0..<len(slots) {
        entry := slots[slot]
        if entry == 0 {
            return slot, false
        }
        symbol := symbols[entry-1]
        text := files[symbol.file_index].source_version.owned_text
        if text[symbol.name_start:symbol.name_end] == name {
            return slot, true
        }
        slot = (slot+1) & mask
    }
    return -1, false
}

project_fatal :: proc(r: ^Project_Report, issue: Issue_Kind, file_index: int) {
    r.fatal = true
    r.complete = false
    append(&r.issues, Project_Issue{kind=issue,file_index=file_index})
}

// Preflight every file before allocating the symbol table. Distinct logical
// file IDs are mandatory, and all syntax results must be fully successful.
// The caller retains ownership of all source versions and ASTs.
project_preflight :: proc(files: []Project_File, r: ^Project_Report) -> bool {
    for f, i in files {
        if f.source_version == nil || !f.source_version.initialized || f.syntax == nil {
            project_fatal(r, .Invalid_Source, i)
            return false
        }
        v := f.source_version
        ast := f.syntax
        if v.file_id != ast.file_id || v.generation != ast.generation {
            project_fatal(r, .Snapshot_Mismatch, i)
            return false
        }
        if !ast.complete || ast.fatal || len(ast.diagnostics)>0 {
            project_fatal(r, .Syntax_Not_Complete, i)
            return false
        }
        for previous in 0..<i {
            if files[previous].source_version.file_id == v.file_id {
                project_fatal(r, .Invalid_Source, i)
                return false
            }
        }
    }
    return true
}

// Declarations from every script file are collected before any references
// are resolved. Symbol IDs are deterministic for the chosen file order.
bind_script_project :: proc(files: []Project_File) -> Project_Report {
    r: Project_Report
    if !project_preflight(files, &r) {
        return r
    }
    count := 0
    for f in files {
        count += len(f.syntax.declarations)
    }
    capacity := 8
    for capacity <= count*2 {
        capacity *= 2
    }
    slots := make([]int, capacity)
    defer delete(slots)

    for f, file_index in files {
        text := f.source_version.owned_text
        for decl, decl_index in f.syntax.declarations {
            if decl.name_start < 0 || decl.name_start >= decl.name_end || decl.name_end > len(text) {
                project_fatal(&r, .Invalid_Source, file_index)
                return r
            }
            name := text[decl.name_start:decl.name_end]
            slot, found := project_slot(files, r.symbols[:], slots, name)
            if slot < 0 {
                project_fatal(&r, .Invalid_Source, file_index)
                return r
            }
            if found {
                symbol := &r.symbols[slots[slot]-1]
                if symbol.kind == .Var && decl.kind == .Var {
                    symbol.declaration_count += 1
                } else {
                    append(&r.issues, Project_Issue{
                        kind=.Duplicate_Declaration, file_index=file_index,
                        byte_start=decl.name_start, byte_end=decl.name_end,
                    })
                }
            } else {
                id := len(r.symbols)
                append(&r.symbols, Project_Symbol{
                    file_index=file_index, declaration_index=decl_index,
                    name_start=decl.name_start, name_end=decl.name_end,
                    kind=decl.kind, declaration_count=1,
                })
                slots[slot] = id+1
            }
        }
    }
    for f, file_index in files {
        text := f.source_version.owned_text
        for node, node_index in f.syntax.nodes {
            if node.kind != .Name {
                continue
            }
            if node.byte_start < 0 || node.byte_start >= node.byte_end || node.byte_end > len(text) {
                project_fatal(&r, .Invalid_Source, file_index)
                return r
            }
            name := text[node.byte_start:node.byte_end]
            slot, found := project_slot(files, r.symbols[:], slots, name)
            if !found {
                append(&r.issues, Project_Issue{
                    kind=.Unresolved_Name,file_index=file_index,
                    byte_start=node.byte_start,byte_end=node.byte_end,
                })
            } else {
                append(&r.references, Project_Reference{
                    file_index=file_index,node_index=node_index,
                    symbol_index=slots[slot]-1,
                    byte_start=node.byte_start,byte_end=node.byte_end,
                })
            }
        }
    }
    r.complete = !r.fatal && len(r.issues)==0
    return r
}
