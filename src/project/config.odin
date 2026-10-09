package project

import "core:encoding/json"
import "core:path/filepath"
import "core:strings"

// P0C: explicit, relative .ts roots only. This is NOT a general tsconfig
// parser. The accepted JSONC subset allows comments and trailing commas.
Config_Error :: enum {
    None,
    Invalid_Json,
    Unsupported_Config,
    Missing_Files,
    Invalid_File,
    Duplicate_File,
    Unsupported_Option,
}

Config :: struct {
    roots: [dynamic]string, // owned normalized paths, in explicit files order
    no_emit: bool,
}

config_destroy :: proc(c: ^Config) {
    for path in c.roots {
        delete(path)
    }
    delete(c.roots)
    c^ = Config{}
}

// No wildcard/absolute/parent traversal roots, JS, JSX, TSX, declaration
// files or inherited configuration until those semantics are implemented.
config_root_path :: proc(path: string) -> (string, bool) {
    if len(path) == 0 || filepath.is_abs(path) ||
       strings.contains(path, ":") || strings.contains(path, "\\") ||
       strings.contains(path, "*") || strings.contains(path, "?") {
        return "", false
    }
    clean, err := filepath.clean(path)
    if err != nil {
        return "", false
    }
    if clean == "." || clean == ".." ||
       strings.has_prefix(clean, "../") || strings.has_prefix(clean, "..\\") ||
       !strings.has_suffix(clean, ".ts") || strings.has_suffix(clean, ".d.ts") {
        delete(clean)
        return "", false
    }
    return clean, true
}

// Reject unknown properties and options instead of silently changing the
// meaning of a real TypeScript project. Comments are lexically stripped.
parse_config :: proc(text: string) -> (Config, Config_Error) {
    c: Config
    sanitized, comments_ok := strip_jsonc_comments(text)
    if !comments_ok {
        return c, .Invalid_Json
    }
    defer delete(sanitized)
    value, err := json.parse_string(string(sanitized), .JSON)
    if err != .None {
        return c, .Invalid_Json
    }
    defer json.destroy_value(value)
    root, is_object := value.(json.Object)
    if !is_object {
        return c, .Unsupported_Config
    }
    for key in root {
        if key != "files" && key != "compilerOptions" {
            return c, .Unsupported_Config
        }
    }
    file_value, has_files := root["files"]
    if !has_files {
        return c, .Missing_Files
    }
    files, is_array := file_value.(json.Array)
    if !is_array || len(files) == 0 {
        return c, .Missing_Files
    }
    options_value, has_options := root["compilerOptions"]
    if !has_options {
        return c, .Unsupported_Option
    }
    options, options_ok := options_value.(json.Object)
    if !options_ok {
        return c, .Unsupported_Option
    }
    for key, option in options {
        if key != "noEmit" {
            return c, .Unsupported_Option
        }
        enabled, valid := option.(bool)
        if !valid || !enabled {
            return c, .Unsupported_Option
        }
        c.no_emit = true
    }
    if !c.no_emit {
        return c, .Unsupported_Option
    }
    for file in files {
        name, is_string := file.(string)
        if !is_string {
            config_destroy(&c)
            return Config{}, .Invalid_File
        }
        normalized, ok := config_root_path(name)
        if !ok {
            config_destroy(&c)
            return Config{}, .Invalid_File
        }
        duplicate := false
        for existing in c.roots {
            if existing == normalized {
                duplicate = true
                break
            }
        }
        if duplicate {
            delete(normalized)
            config_destroy(&c)
            return Config{}, .Duplicate_File
        }
        append(&c.roots, normalized)
    }
    return c, .None
}
