package parser

import yaml_error "../yaml_error"
import "core:fmt"

parse_sequence :: proc(p: ^Parser, seq: ^SequenceNode) -> (err: yaml_error.YamlError) {
	for {
		err = skip_newlines(p)
		if err != nil { return }
		if p.current.kind != .Bullet {
			return
		}

		item: ^YamlNode
		item, err = parse_bullet(p)
		if err != nil { return }

		append(&seq.items, item)
	}
}

// parse_bullet reads the item a bullet stands for, which is a scalar, or a
// collection the bullet opens on its own line
parse_bullet :: proc(p: ^Parser) -> (item: ^YamlNode, err: yaml_error.YamlError) {
	err = parser_expect(p, .Bullet)
	if err != nil { return }

	item = new(YamlNode)

	switch {
	case p.current.kind == .Bullet:
		// a bullet behind a bullet opens a list inside the list
		seq := SequenceNode{}
		err = parse_sequence(p, &seq)
		if err != nil { return }
		err = continue_sequence(p, &seq)
		if err != nil { return }
		item^ = YamlNode{.Sequence, seq, ""}
		return

	case is_scalar_kind(p.current.kind):
		// the token behind the bullet is the item itself unless a colon
		// follows it, which makes it the first key of a mapping instead
		first := p.current
		err = parser_advance(p)
		if err != nil { return }

		if p.current.kind != .Colon {
			item^ = YamlNode{.Scalar, scalar_from_token(first), ""}
			return
		}

		key := new(YamlNode)
		key^ = YamlNode{.Scalar, scalar_from_token(first), ""}

		err = parser_advance(p)
		if err != nil { return }

		value: ^YamlNode
		value, err = parse_value(p)
		if err != nil { return }

		mapping := MappingNode{}
		append(&mapping.pairs, MappingPair{key, value})
		err = continue_mapping(p, &mapping)
		if err != nil { return }
		item^ = YamlNode{.Mapping, mapping, ""}
		return

	case:
		// the bullet stands on its own and the item sits on the lines below
		item, err = parse_value(p)
		return
	}
}

// parse_flow_sequence reads a flow sequence like [1, 2, 3], where the items
// sit on one line between brackets instead of on bullets below. The items
// are read like any other value, so anchors, aliases and nested flow
// sequences work the same way, and an empty pair of brackets holds nothing.
parse_flow_sequence :: proc(p: ^Parser, seq: ^SequenceNode) -> (err: yaml_error.YamlError) {
	err = parser_expect(p, .LBracket)
	if err != nil { return }

	err = skip_newlines(p)
	if err != nil { return }

	if p.current.kind == .RBracket {
		err = parser_advance(p)
		return
	}

	for {
		item: ^YamlNode
		item, err = parse_flow_item(p)
		if err != nil { return }
		append(&seq.items, item)

		err = skip_newlines(p)
		if err != nil { return }

		if p.current.kind == .Comma {
			err = parser_advance(p)
			if err != nil { return }
			continue
		}

		if p.current.kind == .RBracket {
			err = parser_advance(p)
			return
		}

		err = yaml_error.ParserError {
			kind    = .ExpectedToken,
			message = fmt.tprintf("expected , or ] but got %s", p.current.kind),
			line    = p.current.line,
			col     = p.current.col,
		}
		return
	}
}

// parse_flow_item reads one item of a flow sequence, which is any value a
// block value could be, including a flow sequence nested in the outer one
parse_flow_item :: proc(p: ^Parser) -> (item: ^YamlNode, err: yaml_error.YamlError) {
	err = skip_newlines(p)
	if err != nil { return }

	item, err = parse_value(p)
	return
}

// continue_sequence carries a list a bullet opened onto the lines that are
// indented under it, which is where the rest of its items are written, and
// closes it again once those lines run out
continue_sequence :: proc(p: ^Parser, seq: ^SequenceNode) -> (err: yaml_error.YamlError) {
	err = skip_newlines(p)
	if err != nil { return }
	if p.current.kind != .Indent {
		return
	}

	err = parser_advance(p)
	if err != nil { return }

	err = parse_sequence(p, seq)
	if err != nil { return }

	err = parser_expect(p, .Dedent)
	return
}

// continue_mapping carries a mapping a bullet opened onto the lines that are
// indented under it, which is where its other keys are written
