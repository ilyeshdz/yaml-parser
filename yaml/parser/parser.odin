package parser

import lexer_package "../lexer"
import yaml_error "../yaml_error"
import "core:fmt"

Parser :: struct {
	lexer:        ^lexer_package.Lexer,
	current:      lexer_package.Token,
	previous:     lexer_package.Token,
	// the nodes anchors have named so far, so an alias can be resolved to the
	// node that was already parsed instead of being read a second time
	anchors:      map[string]^YamlNode,
	// the node the document is being read into, still empty when an alias names
	// it, which is the one way an alias can end up pointing at itself
	open_node:    ^YamlNode,
}

parser_init :: proc(lexer: ^lexer_package.Lexer) -> (Parser, yaml_error.YamlError) {
	p := Parser {
		lexer        = lexer,
		anchors      = make(map[string]^YamlNode),
	}
	tok, err := lexer_package.lexer_next_token(lexer)
	if err != nil {
		return p, err
	}
	p.current = tok
	return p, nil
}

// parser_parse reads every document of a stream, which is what a file holding
// more than one --- marker is made of. Each document gets its own anchors,
// because a name one document gives is not seen by the ones behind it.
scalar_type_from_token :: proc(kind: lexer_package.Token_Kind) -> ScalarType {
	#partial switch kind {
	case .Integer:
		return .Integer
	case .Float:
		return .Float
	case .Timestamp:
		return .Timestamp
	case:
		return .String
	}
}

// parser_take_anchor consumes the anchor in front of a value and returns its
// name, or an empty name when there is none. The name is checked against the
// ones already handed out here, because a name can only be defined once.
scalar_from_token :: proc(tok: lexer_package.Token) -> ScalarNode {
	scalar_type := scalar_type_from_token(tok.kind)
	if tok.kind == .Identifier {
		switch tok.text {
		case "true", "false":
			scalar_type = .Boolean
		case "null", "~":
			scalar_type = .Null
		}
	}
	return ScalarNode{tok.text, scalar_type}
}

is_scalar_kind :: proc(kind: lexer_package.Token_Kind) -> bool {
	return kind == .Identifier || kind == .String || kind == .Integer ||
	       kind == .Float || kind == .Timestamp
}

// is_implicit_document_start reports whether a token can open a document
// without a --- marker, which is how a plain file holding a single mapping
// begins
is_implicit_document_start :: proc(kind: lexer_package.Token_Kind) -> bool {
	#partial switch kind {
	case .Identifier, .String, .Integer, .Float, .Timestamp, .Anchor, .Alias:
		return true
	}
	return false
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
