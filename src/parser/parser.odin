package parser

import "../source"
import "../compat"
import lexcontext "../context"

// M2-A narrow syntax slice. Parsed declarations are source-owned spans;
// no strings, objects, or type graph allocated per node.
Declaration_Kind :: enum {
    Var,
    Let,
    Const,
}

Primitive_Type :: enum {
    Inferred,
    Number,
    String,
    Boolean,
}

Literal_Kind :: enum {
    None,
    Integer,
    String,
}

Parse_Error :: enum {
    None,
    Invalid_Source,
    Unsupported_Profile,
    Unsupported_Syntax,
    Missing_Name,
    Missing_Type,
    Missing_Initializer,
    Missing_Semicolon,
}

Declaration :: struct {
    kind: Declaration_Kind,
    byte_start: int,
    byte_end: int,
    name_start: int,
    name_end: int,
    type_kind: Primitive_Type,
    literal_kind: Literal_Kind,
    literal_start: int,
    literal_end: int,
}

Program :: struct {
    file_id: source.File_Id,
    generation: u32,
    declarations: [dynamic]Declaration,
}

// Owns declaration storage. The source version must outlive any interpretation
// of the borrowed name/literal spans; Program stores no source pointers.
program_destroy :: proc(program: ^Program) {
    delete(program.declarations)
    program^ = Program{}
}

// A failed parse returns an EMPTY program, not a partial declaration list.
// Compatibility checks are explicit, and the complete input must be consumed.
// C0 TypeScript syntax-diagnostic parity is NOT established by this subset.
parse_declarations :: proc(version: ^source.Source_Version, profile: compat.Profile) -> (Program, Parse_Error) {
    if version == nil || !version.initialized {
        return Program{}, .Invalid_Source
    }
    if !compat.profile_is_registered(profile) {
        return Program{}, .Unsupported_Profile
    }

    program := Program {
        file_id = version.file_id,
        generation = version.generation,
        declarations = make([dynamic]Declaration, 0, 8),
    }
    reader := lexcontext.reader_init_with_profile(version, profile)
    for {
        token := lexcontext.reader_next(&reader)
        if token.kind == .End_Of_File {
            return program, .None
        }
        if token.kind == .Invalid {
            delete(program.declarations)
            return Program{}, .Unsupported_Syntax
        }
        declaration: Declaration
        declaration.byte_start = token.byte_start
        if token.kind == .Var {
            declaration.kind = .Var
        } else if token.kind == .Let {
            declaration.kind = .Let
        } else if token.kind == .Const {
            declaration.kind = .Const
        } else {
            delete(program.declarations)
            return Program{}, .Unsupported_Syntax
        }
        name := lexcontext.reader_next(&reader)
        if name.kind != .Identifier {
            delete(program.declarations)
            return Program{}, .Missing_Name
        }
        declaration.name_start = name.byte_start
        declaration.name_end = name.byte_end

        current := lexcontext.reader_next(&reader)
        if current.kind == .Colon {
            type_token := lexcontext.reader_next(&reader)
            if type_token.kind == .Number_Keyword {
                declaration.type_kind = .Number
            } else if type_token.kind == .String_Keyword {
                declaration.type_kind = .String
            } else if type_token.kind == .Boolean_Keyword {
                declaration.type_kind = .Boolean
            } else {
                delete(program.declarations)
                return Program{}, .Missing_Type
            }
            current = lexcontext.reader_next(&reader)
        } else {
            declaration.type_kind = .Inferred
        }

        if current.kind == .Equals {
            literal := lexcontext.reader_next(&reader)
            if literal.kind == .Integer_Literal {
                declaration.literal_kind = .Integer
            } else if literal.kind == .String_Literal {
                declaration.literal_kind = .String
            } else {
                delete(program.declarations)
                return Program{}, .Missing_Initializer
            }
            declaration.literal_start = literal.byte_start
            declaration.literal_end = literal.byte_end
            current = lexcontext.reader_next(&reader)
        } else if declaration.kind == .Const {
            // A const declaration requires an initializer in this grammar.
            delete(program.declarations)
            return Program{}, .Missing_Initializer
        }

        if current.kind != .Semicolon {
            delete(program.declarations)
            return Program{}, .Missing_Semicolon
        }
        declaration.byte_end = current.byte_end
        append(&program.declarations, declaration)
    }
}
