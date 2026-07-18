package parser

import lexer_package "../lexer"
import "core:fmt"

Parser :: struct {
	lexer:        ^lexer_package.Lexer,
	current:      lexer_package.Token,
	previous:     lexer_package.Token,
	current_key:  string,
	indent_stack: [dynamic]int,
}

parser_init :: proc(lexer: ^lexer_package.Lexer) -> Parser {
	return Parser {
		lexer,
		lexer_package.lexer_next_token(lexer),
		lexer_package.Token{},
		"",
		[dynamic]int{},
	}
}

parser_parse :: proc(p: ^Parser, allocator := context.allocator) -> (document: YamlDocument) {
	context.allocator = allocator

	document = YamlDocument{new(MappingNode)}
	mapping := MappingNode{}

	parser_expect(p, .StreamStart)
	parse_mapping(p, &mapping)

	document.root = &mapping

	return
}

parse_mapping :: proc(p: ^Parser, mapping: ^MappingNode) {
	for {
		skip_newlines(p)
		if p.current.kind == .Indent || p.current.kind == .Dedent || p.current.kind == .Eof || p.current.kind == .StreamEnd {
			parser_advance(p)
			return
		}

		parser_expect(p, .Identifier)
		key := new(YamlNode)
		key^ = YamlNode {
			.Scalar,
			ScalarNode {
				p.previous.text,
				.String
			}
		}
		parser_expect(p, .Colon)

		if p.current.kind == .Newline {
			break
		}

		parser_expect(p, .Identifier, .String, .Float, .Integer)
		value := new(YamlNode)
		value^ = YamlNode {
			.Scalar,
			ScalarNode {
				p.previous.text,
				.String
			}
		}

		append(&mapping.pairs, MappingPair{key, value})
	}
}

skip_newlines :: proc(p: ^Parser) {
	for p.current.kind == .Newline {
		parser_advance(p)
	}
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
