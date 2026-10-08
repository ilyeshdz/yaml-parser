package parser

import yaml_error "../yaml_error"
import "core:fmt"

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

	if p.current.kind == .LBracket {
		seq := SequenceNode{}
		err = parse_flow_sequence(p, &seq)
		if err != nil { return }
		node^ = YamlNode{.Sequence, seq, ""}
		return
	}

	// an empty value means null
	if p.current.kind == .Dedent || p.current.kind == .Eof ||
	   p.current.kind == .StreamEnd || p.current.kind == .StreamStart ||
	   p.previous.kind == .Newline {
		node^ = YamlNode{.Scalar, ScalarNode{"", .Null}, ""}
		return
	}

	err = parser_expect(p, .Identifier, .String, .Float, .Integer, .Timestamp)
	if err != nil { return }

	node^ = YamlNode{.Scalar, scalar_from_token(p.previous), ""}
	return
}

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

// scalar_from_token types a token the way the file says it, so a word like
// true or null is not read back as the string it looks like
