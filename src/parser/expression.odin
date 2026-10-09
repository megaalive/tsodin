package parser

import "../source"
import "../scanner"
import "../compat"
import lexcontext "../context"

// M2-B: compact, source-backed syntax nodes. No checker or TS diagnostic codes.
// Edges are indices into a contiguous node store; -1 means no child.
Expr_Kind :: enum {
    Name,
    Integer,
    Text,
    Unary,
    Binary,
    Group,
    Boolean,
}

Expr_Node :: struct {
    kind: Expr_Kind,
    operator: scanner.Token_Kind,
    byte_start: int,
    byte_end: int,
    left: int,
    right: int,
}

Expr_Declaration :: struct {
    kind: Declaration_Kind,
    byte_start: int,
    byte_end: int,
    name_start: int,
    name_end: int,
    type_kind: Primitive_Type,
    initializer: int, // -1 if no initializer
}

// Source-order events: assignment roots and declarations share one dense node store.
// An explicit if/else uses ordered fork/split/join events. Bounded nested
// conditionals are legal; branch declarations and implicit else fail closed.
Statement_Kind :: enum {
    Declaration,
    Assignment,
    If,
    Else,
    End_If,
}

Expr_Statement :: struct {
    kind: Statement_Kind,
    declaration_index: int, // declaration only; -1 for assignment
    target_node: int,       // assignment only; -1 for declaration
    expression: int,        // expression root or -1 for uninitialized declaration
    byte_start: int,
    byte_end: int,
}

Syntax_Issue :: enum {
    Invalid_Source,
    Unsupported_Profile,
    Unsupported_Lexeme,
    Unsupported_Statement,
    Missing_Name,
    Missing_Type,
    Missing_Initializer,
    Expected_Expression,
    Expected_Close_Paren,
    Expected_Semicolon,
    Nesting_Limit,
    Expected_Equals, // append only: keep syntax issue ordinals stable
    Expected_Open_Brace,
    Expected_Close_Brace,
    Expected_Else,
}

Syntax_Diagnostic :: struct {
    issue: Syntax_Issue,
    byte_start: int,
    byte_end: int,
}

Syntax_Report :: struct {
    file_id: source.File_Id,
    generation: u32,
    nodes: [dynamic]Expr_Node,
    declarations: [dynamic]Expr_Declaration,
    statements: [dynamic]Expr_Statement,
    diagnostics: [dynamic]Syntax_Diagnostic,
    complete: bool, // MUST be false if any diagnostic or fatal scanner state exists
    fatal: bool, // unsupported source/profile/lexeme: no recovery claim
}

syntax_report_destroy :: proc(report: ^Syntax_Report) {
    delete(report.nodes)
    delete(report.declarations)
    delete(report.statements)
    delete(report.diagnostics)
    report^ = Syntax_Report{}
}

Syntax_State :: struct {
    reader: lexcontext.Reader,
    current: scanner.Token,
    report: ^Syntax_Report,
    fatal: bool,
    recursion: int,
    if_depth: int, // independent control-flow nesting bound
}

// The depth bound is a safety limit, not a TypeScript grammar restriction.
SYNTAX_DEPTH_LIMIT :: 64
FLOW_NEST_LIMIT :: 2 // deeper branch scopes fail closed, not silently flattened

syntax_issue :: proc(p: ^Syntax_State, issue: Syntax_Issue) {
    append(&p.report.diagnostics, Syntax_Diagnostic {
        issue = issue,
        byte_start = p.current.byte_start,
        byte_end = p.current.byte_end,
    })
}

syntax_advance :: proc(p: ^Syntax_State) {
    if p.fatal {
        return
    }
    p.current = lexcontext.reader_next(&p.reader)
    if p.current.kind == .Invalid {
        syntax_issue(p, .Unsupported_Lexeme)
        p.fatal = true
    }
}

syntax_node :: proc(p: ^Syntax_State, node: Expr_Node) -> int {
    index := len(p.report.nodes)
    append(&p.report.nodes, node)
    return index
}

// Only the documented ASCII expression operators are accepted. Left
// associativity follows precedence climbing (rhs minimum = priority + 1).
binary_priority :: proc(kind: scanner.Token_Kind) -> int {
    if kind == .Bar_Bar { return 1 }
    if kind == .Ampersand_Ampersand { return 2 }
    if kind == .Equals_Equals_Equals || kind == .Exclamation_Equals_Equals { return 3 }
    if kind == .Less_Than || kind == .Greater_Than ||
       kind == .Less_Than_Equals || kind == .Greater_Than_Equals { return 4 }
    if kind == .Plus || kind == .Minus {
        return 10
    }
    if kind == .Asterisk || kind == .Slash {
        return 20
    }
    return 0
}

syntax_expression :: proc(p: ^Syntax_State, min_priority: int) -> (int, bool) {
    if p.fatal {
        return -1, false
    }
    if p.recursion >= SYNTAX_DEPTH_LIMIT {
        syntax_issue(p, .Nesting_Limit)
        return -1, false
    }
    p.recursion += 1
    defer p.recursion -= 1

    start := p.current
    left := -1
    if start.kind == .Identifier || start.kind == .Integer_Literal ||
       start.kind == .String_Literal || start.kind == .True_Keyword ||
       start.kind == .False_Keyword {
        kind := Expr_Kind.Name
        if start.kind == .Integer_Literal {
            kind = .Integer
        } else if start.kind == .String_Literal {
            kind = .Text
        } else if start.kind == .True_Keyword || start.kind == .False_Keyword {
            kind = .Boolean
        }
        left = syntax_node(p, Expr_Node {
            kind = kind,
            operator = start.kind,
            byte_start = start.byte_start,
            byte_end = start.byte_end,
            left = -1,
            right = -1,
        })
        syntax_advance(p)
    } else if start.kind == .Plus || start.kind == .Minus || start.kind == .Exclamation {
        syntax_advance(p)
        child, valid := syntax_expression(p, 30)
        if !valid {
            return -1, false
        }
        left = syntax_node(p, Expr_Node {
            kind = .Unary,
            operator = start.kind,
            byte_start = start.byte_start,
            byte_end = p.report.nodes[child].byte_end,
            left = child,
            right = -1,
        })
    } else if start.kind == .Open_Paren {
        syntax_advance(p)
        child, valid := syntax_expression(p, 0)
        if !valid {
            return -1, false
        }
        if p.current.kind != .Close_Paren {
            syntax_issue(p, .Expected_Close_Paren)
            return -1, false
        }
        close_end := p.current.byte_end
        syntax_advance(p)
        left = syntax_node(p, Expr_Node {
            kind = .Group,
            byte_start = start.byte_start,
            byte_end = close_end,
            left = child,
            right = -1,
        })
    } else {
        syntax_issue(p, .Expected_Expression)
        return -1, false
    }

    if p.fatal {
        return -1, false
    }
    for {
        priority := binary_priority(p.current.kind)
        if priority == 0 || priority < min_priority {
            break
        }
        op := p.current
        syntax_advance(p)
        right, valid := syntax_expression(p, priority + 1)
        if !valid {
            return -1, false
        }
        left = syntax_node(p, Expr_Node {
            kind = .Binary,
            operator = op.kind,
            byte_start = p.report.nodes[left].byte_start,
            byte_end = p.report.nodes[right].byte_end,
            left = left,
            right = right,
        })
        if p.fatal {
            return -1, false
        }
    }
    return left, true
}

// Synchronize after a syntax error at a declaration boundary. This is
// deliberately bounded and only attempts to recover on lexically valid input.
// In particular, an invalid lexer token halts the whole scan.
syntax_recover :: proc(p: ^Syntax_State) {
    for !p.fatal && p.current.kind != .End_Of_File {
        if p.current.kind == .Semicolon {
            syntax_advance(p)
            return
        }
        if p.current.kind == .Const || p.current.kind == .Let ||
           p.current.kind == .Var {
            return
        }
        syntax_advance(p)
    }
}

syntax_declaration :: proc(p: ^Syntax_State) -> bool {
    start := p.current
    decl: Expr_Declaration
    decl.byte_start = start.byte_start
    decl.initializer = -1
    if start.kind == .Const {
        decl.kind = .Const
    } else if start.kind == .Let {
        decl.kind = .Let
    } else if start.kind == .Var {
        decl.kind = .Var
    } else {
        syntax_issue(p, .Unsupported_Statement)
        return false
    }
    syntax_advance(p)
    if p.fatal {
        return false
    }
    if p.current.kind != .Identifier {
        syntax_issue(p, .Missing_Name)
        return false
    }
    decl.name_start = p.current.byte_start
    decl.name_end = p.current.byte_end
    syntax_advance(p)
    if p.fatal {
        return false
    }
    if p.current.kind == .Colon {
        syntax_advance(p)
        if p.fatal {
            return false
        }
        if p.current.kind == .Number_Keyword {
            decl.type_kind = .Number
        } else if p.current.kind == .String_Keyword {
            decl.type_kind = .String
        } else if p.current.kind == .Boolean_Keyword {
            decl.type_kind = .Boolean
        } else {
            syntax_issue(p, .Missing_Type)
            return false
        }
        syntax_advance(p)
        if p.fatal {
            return false
        }
    }
    if p.current.kind == .Equals {
        syntax_advance(p)
        node, valid := syntax_expression(p, 0)
        if !valid {
            return false
        }
        decl.initializer = node
    } else if decl.kind == .Const {
        syntax_issue(p, .Missing_Initializer)
        return false
    }
    if p.fatal {
        return false
    }
    if p.current.kind != .Semicolon {
        syntax_issue(p, .Expected_Semicolon)
        return false
    }
    decl.byte_end = p.current.byte_end
    syntax_advance(p)
    if p.fatal {
        return false
    }
    declaration_index := len(p.report.declarations)
    append(&p.report.declarations, decl)
    append(&p.report.statements, Expr_Statement{
        kind=.Declaration, declaration_index=declaration_index,
        target_node=-1, expression=decl.initializer,
        byte_start=decl.byte_start, byte_end=decl.byte_end,
    })
    return true
}

// Limited, statement-position assignment: identifier = expression ;
// Arbitrary expressions, destructuring, chained assignments, operators and
// block statements remain unsupported. The target is a normal binder Name.
syntax_assignment :: proc(p: ^Syntax_State) -> bool {
    start := p.current
    target := syntax_node(p, Expr_Node{
        kind=.Name, operator=.Identifier,
        byte_start=start.byte_start, byte_end=start.byte_end,
        left=-1, right=-1,
    })
    syntax_advance(p)
    if p.fatal { return false }
    if p.current.kind != .Equals {
        syntax_issue(p, .Expected_Equals)
        return false
    }
    syntax_advance(p)
    expression, ok := syntax_expression(p, 0)
    if !ok { return false }
    if p.fatal { return false }
    if p.current.kind != .Semicolon {
        syntax_issue(p, .Expected_Semicolon)
        return false
    }
    finish := p.current.byte_end
    syntax_advance(p)
    if p.fatal { return false }
    append(&p.report.statements, Expr_Statement{
        kind=.Assignment, declaration_index=-1,
        target_node=target, expression=expression,
        byte_start=start.byte_start, byte_end=finish,
    })
    return true
}

// Nested if/else depth is intentionally small; statement events stay flat,
// ordered and source-backed rather than creating an object-rich CFG.
syntax_if :: proc(p: ^Syntax_State) -> bool {
    if p.if_depth >= FLOW_NEST_LIMIT {
        syntax_issue(p, .Nesting_Limit)
        return false
    }
    p.if_depth += 1
    defer p.if_depth -= 1
    start := p.current
    syntax_advance(p)
    if p.fatal { return false }
    if p.current.kind != .Open_Paren {
        syntax_issue(p, .Expected_Expression)
        return false
    }
    syntax_advance(p)
    condition, ok := syntax_expression(p, 0)
    if !ok || p.fatal { return false }
    if p.current.kind != .Close_Paren {
        syntax_issue(p, .Expected_Close_Paren)
        return false
    }
    syntax_advance(p)
    if p.fatal { return false }
    if p.current.kind != .Open_Brace {
        syntax_issue(p, .Expected_Open_Brace)
        return false
    }
    append(&p.report.statements, Expr_Statement{
        kind=.If, declaration_index=-1, target_node=-1,
        expression=condition, byte_start=start.byte_start,
        byte_end=p.report.nodes[condition].byte_end,
    })
    syntax_advance(p)
    for !p.fatal && p.current.kind != .Close_Brace &&
        p.current.kind != .End_Of_File {
        if p.current.kind == .If_Keyword {
            if !syntax_if(p) { return false }
        } else if p.current.kind == .Identifier {
            if !syntax_assignment(p) { return false }
        } else {
            syntax_issue(p, .Unsupported_Statement)
            return false
        }
    }
    if p.fatal { return false }
    if p.current.kind != .Close_Brace {
        syntax_issue(p, .Expected_Close_Brace)
        return false
    }
    syntax_advance(p)
    if p.fatal { return false }
    if p.current.kind != .Else_Keyword {
        syntax_issue(p, .Expected_Else)
        return false
    }
    append(&p.report.statements, Expr_Statement{
        kind=.Else, declaration_index=-1, target_node=-1,
        expression=-1, byte_start=p.current.byte_start, byte_end=p.current.byte_end,
    })
    syntax_advance(p)
    if p.fatal { return false }
    if p.current.kind != .Open_Brace {
        syntax_issue(p, .Expected_Open_Brace)
        return false
    }
    syntax_advance(p)
    for !p.fatal && p.current.kind != .Close_Brace &&
        p.current.kind != .End_Of_File {
        if p.current.kind == .If_Keyword {
            if !syntax_if(p) { return false }
        } else if p.current.kind == .Identifier {
            if !syntax_assignment(p) { return false }
        } else {
            syntax_issue(p, .Unsupported_Statement)
            return false
        }
    }
    if p.fatal { return false }
    if p.current.kind != .Close_Brace {
        syntax_issue(p, .Expected_Close_Brace)
        return false
    }
    finish := p.current.byte_end
    syntax_advance(p)
    if p.fatal { return false }
    append(&p.report.statements, Expr_Statement{
        kind=.End_If, declaration_index=-1, target_node=-1,
        expression=-1, byte_start=start.byte_start, byte_end=finish,
    })
    return true
}

// Reports all recoverable syntax errors for this limited grammar. A caller
// must never regard partial recovered declarations as a successful check.
// Unsupported lexical constructs and profile failures remain fatal.
parse_expression_program :: proc(version: ^source.Source_Version, profile: compat.Profile) -> Syntax_Report {
    report: Syntax_Report
    if version == nil || !version.initialized {
        report.fatal = true
        append(&report.diagnostics, Syntax_Diagnostic{issue = .Invalid_Source})
        return report
    }
    report.file_id = version.file_id
    report.generation = version.generation
    if !compat.profile_is_registered(profile) {
        report.fatal = true
        append(&report.diagnostics, Syntax_Diagnostic{issue = .Unsupported_Profile})
        return report
    }
    p := Syntax_State {
        reader = lexcontext.reader_init_with_profile(version, profile),
        report = &report,
    }
    syntax_advance(&p)
    for !p.fatal && p.current.kind != .End_Of_File {
        before_nodes := len(report.nodes)
        before_declarations := len(report.declarations)
        before_statements := len(report.statements)
        ok := false
        if p.current.kind == .If_Keyword {
            ok = syntax_if(&p)
        } else if p.current.kind == .Identifier {
            ok = syntax_assignment(&p)
        } else {
            ok = syntax_declaration(&p)
        }
        if !ok {
            // A failed conditional may already have emitted fork/assignment/
            // join events. Roll back the entire attempted statement together.
            resize(&report.nodes, before_nodes)
            resize(&report.declarations, before_declarations)
            resize(&report.statements, before_statements)
            syntax_recover(&p)
        }
    }
    report.fatal = p.fatal
    report.complete = !p.fatal && len(report.diagnostics) == 0
    return report
}
