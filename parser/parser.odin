package parser

import lexer_package "../lexer"
import yaml_error "../yaml_error"
import "core:fmt"

Parser :: struct {
	lexer:        ^lexer_package.Lexer,
	current:      lexer_package.Token,
	previous:     lexer_package.Token,
	current_key:  string,
	indent_stack: [dynamic]int,
}

parser_init :: proc(lexer: ^lexer_package.Lexer) -> (Parser, yaml_error.YamlError) {
	p := Parser {
		lexer        = lexer,
		indent_stack = [dynamic]int{},
	}
	tok, err := lexer_package.lexer_next_token(lexer)
	if err != nil {
		return p, err
	}
	p.current = tok
	return p, nil
}

parser_parse :: proc(p: ^Parser, allocator := context.allocator) -> (document: YamlDocument, err: yaml_error.YamlError) {
	context.allocator = allocator

	root := new(MappingNode)
	document = YamlDocument{root}

	err = skip_newlines(p)
	if err != nil { return }

	err = parser_expect(p, .StreamStart)
	if err != nil { return }

	err = parse_mapping(p, root)
	if err != nil { return }

	return
}

parse_mapping :: proc(p: ^Parser, mapping: ^MappingNode) -> (err: yaml_error.YamlError) {
	for {
		err = skip_newlines(p)
		if err != nil { return }
		if p.current.kind == .Dedent || p.current.kind == .Eof || p.current.kind == .StreamEnd {
			return
		}

		err = parser_expect(p, .Identifier, .String, .Integer, .Float)
		if err != nil { return }
		key := new(YamlNode)
		key^ = YamlNode{.Scalar, ScalarNode{p.previous.text, scalar_type_from_token(p.previous.kind)}}
		err = parser_expect(p, .Colon)
		if err != nil { return }

		value: ^YamlNode
		value, err = parse_value(p)
		if err != nil { return }

		append(&mapping.pairs, MappingPair{key, value})
	}
}

parse_value :: proc(p: ^Parser) -> (node: ^YamlNode, err: yaml_error.YamlError) {
	err = skip_newlines(p)
	if err != nil { return }

	node = new(YamlNode)

	if p.current.kind == .Indent {
		err = parser_advance(p)
		if err != nil { return }

		if p.current.kind == .Bullet {
			seq := SequenceNode{}
			err = parse_sequence(p, &seq)
			if err != nil { return }
			err = parser_expect(p, .Dedent)
			if err != nil { return }
			node^ = YamlNode{.Sequence, seq}
			return
		}

		nested_mapping := MappingNode{}
		err = parse_mapping(p, &nested_mapping)
		if err != nil { return }
		err = parser_expect(p, .Dedent)
		if err != nil { return }
		node^ = YamlNode{.Mapping, MappingNode{nested_mapping.pairs}}
		return
	}

	if p.current.kind == .Bullet {
		seq := SequenceNode{}
		err = parse_sequence(p, &seq)
		if err != nil { return }
		node^ = YamlNode{.Sequence, seq}
		return
	}

	// an empty value means null
	if p.current.kind == .Dedent || p.current.kind == .Eof || p.current.kind == .StreamEnd || p.previous.kind == .Newline {
		node^ = YamlNode{.Scalar, ScalarNode{"", .Null}}
		return
	}

	err = parser_expect(p, .Identifier, .String, .Float, .Integer)
	if err != nil { return }

	scalar_type := scalar_type_from_token(p.previous.kind)
	if p.previous.kind == .Identifier {
		switch p.previous.text {
		case "true", "false":
			scalar_type = .Boolean
		case "null", "~":
			scalar_type = .Null
		}
	}
	node^ = YamlNode{.Scalar, ScalarNode{p.previous.text, scalar_type}}
	return
}

parse_sequence :: proc(p: ^Parser, seq: ^SequenceNode) -> (err: yaml_error.YamlError) {
	for {
		err = skip_newlines(p)
		if err != nil { return }
		if p.current.kind != .Bullet {
			return
		}

		err = parser_expect(p, .Bullet)
		if err != nil { return }

		item: ^YamlNode
		item, err = parse_value(p)
		if err != nil { return }

		append(&seq.items, item)
	}
}


// The helpers functions

scalar_type_from_token :: proc(kind: lexer_package.Token_Kind) -> ScalarType {
	#partial switch kind {
	case .Integer:
		return .Integer
	case .Float:
		return .Float
	case:
		return .String
	}
}

skip_newlines :: proc(p: ^Parser) -> (err: yaml_error.YamlError) {
	for p.current.kind == .Newline {
		err = parser_advance(p)
		if err != nil { return }
	}
	return
}

parser_advance :: proc(p: ^Parser) -> (err: yaml_error.YamlError) {
	p.previous = p.current
	tok, lexer_err := lexer_package.lexer_next_token(p.lexer)
	if lexer_err != nil {
		return lexer_err
	}
	p.current = tok
	return
}

parser_match :: proc(p: ^Parser, kind: lexer_package.Token_Kind) -> bool {
	if p.current.kind == kind {
		return true
	}

	return false
}

parser_expect :: proc(p: ^Parser, kinds: ..lexer_package.Token_Kind) -> (err: yaml_error.YamlError) {
	for k in kinds {
		if parser_match(p, k) {
			err = parser_advance(p)
			return
		}
	}

	err = yaml_error.ParserError {
		kind    = .ExpectedToken,
		message = fmt.tprintf("expected %v but got %s", kinds, p.current.kind),
		line    = p.current.line,
		col     = p.current.col,
	}
	return
}
