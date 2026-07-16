package parser

import lexer_package "../lexer"
import "core:fmt"

Parser_State :: enum {
	Parser_Start,
	Parser_End,
	Parser_Expect_Key,
	Parser_Expect_Newline,
	Parser_Expect_Colon,
	Parser_Expect_Value,
}

Parser :: struct {
	lexer:        ^lexer_package.Lexer,
	current:      lexer_package.Token,
	previous:     lexer_package.Token,
	state:        Parser_State,
	current_key:  string,
	indent_stack: [dynamic]int,
}

parser_init :: proc(lexer: ^lexer_package.Lexer) -> Parser {
	return Parser {
		lexer,
		lexer_package.lexer_next_token(lexer),
		lexer_package.Token{},
		.Parser_Start,
		"",
		[dynamic]int{},
	}
}

parser_parse :: proc(p: ^Parser, allocator := context.allocator) -> (document: YamlDocument) {
	context.allocator = allocator

	document = YamlDocument{new(MappingNode)}

	for p.state != .Parser_End {
		switch p.state {
		case .Parser_Start:
			parser_expect(p, .StreamStart)
			p.state = .Parser_Expect_Newline
		case .Parser_Expect_Newline:
			parser_expect(p, .Newline)
			p.state = .Parser_Expect_Key
		case .Parser_Expect_Key:
			if p.current.kind == .StreamEnd {
				p.state = .Parser_End
				continue
			}
			p.current_key = p.current.text
			parser_expect(p, .Identifier)
			p.state = .Parser_Expect_Colon
		case .Parser_Expect_Colon:
			parser_expect(p, .Colon)
			p.state = .Parser_Expect_Value
		case .Parser_Expect_Value:
			if p.current.kind == .Eof || p.current.kind == .StreamEnd {
				p.state = .Parser_End
			} else if p.current.kind == .Indent {
				fmt.println("something");
				append(&p.indent_stack, p.indent_stack[len(p.indent_stack) - 1] + 1)
			} else if p.current.kind == .Dedent {
				append(&p.indent_stack, p.indent_stack[len(p.indent_stack) - 1] - 1)
			} else {
				parser_expect(p, .Identifier, .String, .Integer, .Float)
				p.state = .Parser_Expect_Newline
				key_node := new(YamlNode)
				key_node^ = YamlNode{.Scalar, ScalarNode{p.current_key, .String}}
				value_node := new(YamlNode)
				value_node^ = YamlNode{.Scalar, ScalarNode{p.previous.text, .String}}
				pair := MappingPair{key_node, value_node}
				append(&document.root.pairs, pair)
			}
		case .Parser_End:
			fmt.println("parser finished")
			break
		}
	}
	return
}

// The helpers functions

parser_advance :: proc(p: ^Parser) {
	p.previous = p.current
	p.current = lexer_package.lexer_next_token(p.lexer)
	fmt.println(p.current)
}

parser_match :: proc(p: ^Parser, kind: lexer_package.Token_Kind) -> bool {
	if p.current.kind == kind {
		return true
	}

	return false
}

parser_expect :: proc(p: ^Parser, kinds: ..lexer_package.Token_Kind) {
	for k in kinds {
		if parser_match(p, k) {
			parser_advance(p)
			return
		}
	}

	fmt.println("expected", kinds, "but got", p.current.kind)
	panic("")
}
