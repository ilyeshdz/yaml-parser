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
		case .Parser_Expect_Value:
			if p.current.kind == .Eof || p.current.kind == .StreamEnd {
				p.state = .Parser_End
			} else if p.current.kind == .Newline {
				p.state = .Parser_Expect_Newline
			} else {
				parser_expect(p, .Identifier, .String, .Integer, .Float)

				key_node := new(YamlNode)
				key_node^ = YamlNode{.Scalar, ScalarNode{p.current_key, .String}}
				value_node := new(YamlNode)
				value_type := ScalarType.String
				if p.previous.kind == .Integer {
					value_type = ScalarType.Integer
				} else if p.previous.kind == .Float {
					value_type = ScalarType.Float
				}
				value_node^ = YamlNode{.Scalar, ScalarNode{p.previous.text, value_type}}
				pair := MappingPair{key_node, value_node}
				append(&document.root.pairs, pair)

				p.state = .Parser_Expect_Newline
			}
		case .Parser_Expect_Colon:
			parser_expect(p, .Colon)
			p.state = .Parser_Expect_Value
		case .Parser_Expect_Key:
			if p.current.kind == .Dedent {
				parser_advance(p)
				continue
			}
			if p.current.kind == .Indent {
				parser_advance(p)
				continue
			}
			if p.current.kind == .Eof || p.current.kind == .StreamEnd {
				p.state = .Parser_End
				continue
			}

			p.current_key = p.current.text
			parser_expect(p, .Identifier)
			p.state = .Parser_Expect_Colon

		case .Parser_End:
			break
		}
	}
	return
}

// The helpers functions

parser_advance :: proc(p: ^Parser) {
	p.previous = p.current
	p.current = lexer_package.lexer_next_token(p.lexer)
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
