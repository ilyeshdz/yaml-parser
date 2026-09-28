package parser

import lexer_package "../lexer"
import yaml_error "../yaml_error"
import "core:fmt"

Parser :: struct {
	lexer:        ^lexer_package.Lexer,
	current:      lexer_package.Token,
	previous:     lexer_package.Token,
	current_key:  string,
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

parser_parse :: proc(p: ^Parser, allocator := context.allocator) -> (document: YamlDocument, err: yaml_error.YamlError) {
	context.allocator = allocator

	root := new(MappingNode)

	// the root node exists before it is filled in so that an anchor on the
	// document itself can be registered while the mapping is still being read,
	// an alias below it needs to find that anchor first
	root_node := new(YamlNode)
	p.open_node = root_node

	err = skip_newlines(p)
	if err != nil { return }

	err = parser_expect(p, .StreamStart)
	if err != nil { return }

	root_anchor: string
	root_anchor, err = parser_take_anchor(p)
	if err != nil { return }
	if root_anchor != "" {
		p.anchors[root_anchor] = root_node
	}

	err = parse_mapping(p, root)
	if err != nil { return }

	// the node wraps the mapping only once every pair has been appended, so the
	// copy of the pair slice sees the final length
	root_node^ = YamlNode{.Mapping, root^, root_anchor}
	p.open_node = nil
	document = YamlDocument{root_node}
	return
}

parse_mapping :: proc(p: ^Parser, mapping: ^MappingNode) -> (err: yaml_error.YamlError) {
	for {
		err = skip_newlines(p)
		if err != nil { return }
		if p.current.kind == .Dedent || p.current.kind == .Eof || p.current.kind == .StreamEnd {
			return
		}

		// a key that is indented further than the line before it dedented to
		// means the file mixes indentation levels that do not line up
		if p.current.kind == .Indent {
			err = yaml_error.ParserError {
				kind    = .InvalidIndentation,
				message = "unexpected indentation, a key has to line up with the keys above it",
				line    = p.current.line,
				col     = p.current.col,
			}
			return
		}

		// a key is always a plain scalar, so neither an alias nor an anchor is
		// something a key can be, which is what rules out merge keys
		if p.current.kind == .Alias || p.current.kind == .Anchor {
			sigil := "*" if p.current.kind == .Alias else "&"
			err = yaml_error.ParserError {
				kind    = .UnexpectedToken,
				message = fmt.tprintf("%s%q is not a valid key, only a value can be an alias or an anchor", sigil, p.current.text),
				line    = p.current.line,
				col     = p.current.col,
			}
			return
		}

		err = parser_expect(p, .Identifier, .String, .Integer, .Float)
		if err != nil { return }
		key := new(YamlNode)
		key^ = YamlNode{.Scalar, ScalarNode{p.previous.text, scalar_type_from_token(p.previous.kind)}, ""}

		// a merge key would look like a plain one and quietly do nothing, which
		// is worse than saying so
		if p.previous.text == "<<" {
			err = yaml_error.ParserError {
				kind    = .UnexpectedToken,
				message = "merge keys are not supported",
				line    = p.previous.line,
				col     = p.previous.col,
			}
			return
		}

		err = parser_expect(p, .Colon)
		if err != nil { return }

		value: ^YamlNode
		value, err = parse_value(p)
		if err != nil { return }

		append(&mapping.pairs, MappingPair{key, value})
	}
}

// parse_value reads one value, which is either an anchor naming what follows,
// an alias handing back a node that was already read, or the node itself
parse_value :: proc(p: ^Parser) -> (node: ^YamlNode, err: yaml_error.YamlError) {
	err = skip_newlines(p)
	if err != nil { return }

	anchor: string
	anchor, err = parser_take_anchor(p)
	if err != nil { return }

	if p.current.kind == .Alias {
		name := p.current.text
		target, found := p.anchors[name]
		if !found {
			err = yaml_error.ParserError {
				kind    = .UnknownAnchor,
				message = fmt.tprintf("*%s points at an anchor that was never defined", name),
				line    = p.current.line,
				col     = p.current.col,
			}
			return
		}

		// an anchor names a node that is only read from top to bottom, so the
		// one alias that could point at a node still being read is the one
		// taking the document itself, and a tree that contains itself would
		// never stop being printed or written out
		if target == p.open_node {
			err = yaml_error.ParserError {
				kind    = .RecursiveAlias,
				message = fmt.tprintf("*%s points at the node it lives in, an alias cannot contain itself", name),
				line    = p.current.line,
				col     = p.current.col,
			}
			return
		}

		err = parser_advance(p)
		if err != nil { return }
		return target, nil
	}

	node, err = parse_node(p)
	if err != nil { return }

	// the anchor is registered once the node it names is whole, so every alias
	// pointing at that name ends up holding that very node
	if anchor != "" {
		node.anchor = anchor
		p.anchors[anchor] = node
	}

	return
}

parse_node :: proc(p: ^Parser) -> (node: ^YamlNode, err: yaml_error.YamlError) {
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
			node^ = YamlNode{.Sequence, seq, ""}
			return
		}

		nested_mapping := MappingNode{}
		err = parse_mapping(p, &nested_mapping)
		if err != nil { return }
		err = parser_expect(p, .Dedent)
		if err != nil { return }
		node^ = YamlNode{.Mapping, MappingNode{nested_mapping.pairs}, ""}
		return
	}

	if p.current.kind == .Bullet {
		seq := SequenceNode{}
		err = parse_sequence(p, &seq)
		if err != nil { return }
		node^ = YamlNode{.Sequence, seq, ""}
		return
	}

	// an empty value means null
	if p.current.kind == .Dedent || p.current.kind == .Eof || p.current.kind == .StreamEnd || p.previous.kind == .Newline {
		node^ = YamlNode{.Scalar, ScalarNode{"", .Null}, ""}
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
	node^ = YamlNode{.Scalar, ScalarNode{p.previous.text, scalar_type}, ""}
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

// parser_take_anchor consumes the anchor in front of a value and returns its
// name, or an empty name when there is none. The name is checked against the
// ones already handed out here, because a name can only be defined once.
parser_take_anchor :: proc(p: ^Parser) -> (name: string, err: yaml_error.YamlError) {
	err = skip_newlines(p)
	if err != nil { return }

	if p.current.kind != .Anchor {
		return "", nil
	}

	name = p.current.text
	if _, taken := p.anchors[name]; taken {
		err = yaml_error.ParserError {
			kind    = .DuplicateAnchor,
			message = fmt.tprintf("&%s is already defined, an anchor name can only be used once", name),
			line    = p.current.line,
			col     = p.current.col,
		}
		return
	}

	err = parser_advance(p)
	if err != nil { return }

	// an anchor can sit on its own line, with what it names indented below it
	err = skip_newlines(p)
	if err != nil { return }

	return
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
