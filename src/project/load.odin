package project

import "core:os"
import "core:path/filepath"
import "../binder"
import "../compat"
import "../parser"
import "../source"

Load_Error :: enum {
    None,
    Config_Read,
    Config_Invalid,
    Root_Read,
    Invalid_Source,
}

Loaded_File :: struct {
    path: string, // owned absolute-or-config-relative normalized OS path
    version: ^source.Source_Version,
    syntax: ^parser.Syntax_Report,
}

Project :: struct {
    config: Config,
    files: [dynamic]Loaded_File,
    binding: binder.Project_Report,
    error_file_index: int,
    config_error: Config_Error,
}

project_destroy :: proc(p: ^Project) {
    binder.project_report_destroy(&p.binding)
    for f in p.files {
        parser.syntax_report_destroy(f.syntax)
        source.source_version_destroy(f.version)
        free(f.syntax)
        free(f.version)
        delete(f.path)
    }
    delete(p.files)
    config_destroy(&p.config)
    p^ = Project{}
}

// Snapshot ownership is stable: each source/AST has its own allocation and
// cannot be invalidated by dynamic-array growth. Bind only after all roots
// were read and parsed. The caller must destroy even a failed partial load.
load :: proc(config_path: string) -> (Project, Load_Error) {
    p: Project
    p.error_file_index = -1
    bytes, read_err := os.read_entire_file(config_path, context.allocator)
    if read_err != nil {
        return p, .Config_Read
    }
    parsed, parse_err := parse_config(string(bytes))
    delete(bytes)
    if parse_err != .None {
        p.config_error = parse_err
        return p, .Config_Invalid
    }
    p.config = parsed
    for relative, i in p.config.roots {
        path, join_err := filepath.join({filepath.dir(config_path), relative})
        if join_err != nil {
            p.error_file_index = i
            return p, .Root_Read
        }
        data, file_err := os.read_entire_file(path, context.allocator)
        if file_err != nil {
            p.error_file_index = i
            delete(path)
            return p, .Root_Read
        }
        version, valid := source.source_version_create(source.File_Id(i+1), 1, string(data))
        delete(data)
        if !valid {
            p.error_file_index = i
            delete(path)
            return p, .Invalid_Source
        }
        f := Loaded_File{path=path,version=new(source.Source_Version),
                         syntax=new(parser.Syntax_Report)}
        f.version^ = version
        f.syntax^ = parser.parse_expression_program(f.version, compat.ts7_profile())
        append(&p.files, f)
    }
    files := make([]binder.Project_File, len(p.files))
    defer delete(files)
    for f, i in p.files {
        files[i] = binder.Project_File{mode=.Script, source_version=f.version, syntax=f.syntax}
    }
    p.binding = binder.bind_script_project(files)
    return p, .None
}
