package parser

import "core:testing"
import "../source"
import "../compat"
import "../scanner"

@(test)
parser_remainder_multiplicative_precedence_and_left_associativity :: proc(t: ^testing.T) {
    input := "const value = 10 + 9 % 4 * 2;" +
             "const chain = 12 / 5 % 2;" +
             "const unary = -9 % (2 + 1);"
    version, valid := source.source_version_create(source.File_Id(922), 1, input)
    testing.expect(t, valid, "valid source version")
    defer source.source_version_destroy(&version)
    syntax := parse_expression_program(&version, compat.ts7_profile())
    defer syntax_report_destroy(&syntax)
    testing.expect(t, syntax.complete && !syntax.fatal &&
                   len(syntax.diagnostics)==0 && len(syntax.declarations)==3,
                   "multiplicative remainder expressions parse fully")
    root := syntax.nodes[syntax.declarations[0].initializer]
    testing.expect(t, root.kind==.Binary && root.operator==.Plus,
                   "addition binds less tightly than remainder")
    product := syntax.nodes[root.right]
    testing.expect(t, product.kind==.Binary && product.operator==.Asterisk,
                   "percent and multiplication have identical precedence")
    remainder := syntax.nodes[product.left]
    testing.expect(t, remainder.kind==.Binary && remainder.operator==.Percent,
                   "remainder binds to the left of following multiplication")
    chain := syntax.nodes[syntax.declarations[1].initializer]
    testing.expect(t, chain.kind==.Binary && chain.operator==.Percent &&
                   syntax.nodes[chain.left].operator==.Slash,
                   "division and remainder are left associative")
    unary := syntax.nodes[syntax.declarations[2].initializer]
    testing.expect(t, unary.kind==.Binary && unary.operator==.Percent &&
                   syntax.nodes[unary.left].kind==.Unary &&
                   syntax.nodes[unary.left].operator==.Minus &&
                   syntax.nodes[unary.right].kind==.Group,
                   "unary and parentheses bind above remainder")
}
