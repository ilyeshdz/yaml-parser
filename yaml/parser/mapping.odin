package parser

import yaml_error "../yaml_error"
import "core:fmt"

parse_mapping :: proc(p: ^Parser, mapping: ^MappingNode) -> (err: yaml_error.YamlError) {
	for {
		err = skip_newlines(p)
		if err != nil { return }
		// a marker of any kind ends the mapping it stands in front of, so the
		// parser comes back here for the document behind it
		if p.current.kind == .Dedent || p.current.kind == .Eof ||
		   p.current.kind == .StreamEnd || p.current.kind == .StreamStart {
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

		err = parser_expect(p, .Identifier, .String, .Integer, .Float, .Timestamp)
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

		// a key written twice would read back as whichever of the two the
		// lookup happens to reach first, so the file is said to be wrong instead
		if mapping_pair_index(mapping^, p.previous.text) >= 0 {
			err = yaml_error.ParserError {
				kind    = .DuplicateKey,
				message = fmt.tprintf("key %q is already defined in this mapping, the second one would never be read", p.previous.text),
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
continue_mapping :: proc(p: ^Parser, mapping: ^MappingNode) -> (err: yaml_error.YamlError) {
	err = skip_newlines(p)
	if err != nil { return }
	if p.current.kind != .Indent {
		return
	}

	err = parser_advance(p)
	if err != nil { return }

	err = parse_mapping(p, mapping)
	if err != nil { return }

	err = parser_expect(p, .Dedent)
	return
}


// The helpers functions
