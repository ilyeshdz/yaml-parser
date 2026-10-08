package parser

import yaml_error "../yaml_error"
import "core:fmt"

parser_parse :: proc(p: ^Parser, allocator := context.allocator) -> (document: YamlDocument, err: yaml_error.YamlError) {
	context.allocator = allocator

	for {
		err = skip_newlines(p)
		if err != nil { return }

		if p.current.kind == .Eof {
			return
		}

		// the marker behind a document closes it, and the document behind the
		// closing marker has a --- of its own waiting
		if p.current.kind == .StreamEnd {
			err = parser_advance(p)
			if err != nil { return }
			continue
		}

		// a file can hold a single document without any marker, which is
		// how plain files without a --- open
		if p.current.kind != .StreamStart {
			if len(document.documents) > 0 || !is_implicit_document_start(p.current.kind) {
				err = yaml_error.ParserError {
					kind    = .UnexpectedToken,
					message = fmt.tprintf("a document has to open with ---, got %s", p.current.kind),
					line    = p.current.line,
					col     = p.current.col,
				}
				return
			}
		} else {
			err = parser_advance(p)
			if err != nil { return }
		}

		clear(&p.anchors)

		root := new(MappingNode)

		// the node exists before it is filled in so that an anchor on the
		// document itself can be registered while the mapping is still being
		// read, an alias below it needs to find that anchor first
		root_node := new(YamlNode)
		p.open_node = root_node

		root_anchor: string
		root_anchor, err = parser_take_anchor(p)
		if err != nil { return }
		if root_anchor != "" {
			p.anchors[root_anchor] = root_node
		}

		err = parse_mapping(p, root)
		if err != nil { return }

		// the node wraps the mapping only once every pair has been appended,
		// so the copy of the pair slice sees the final length
		root_node^ = YamlNode{.Mapping, root^, root_anchor}
		p.open_node = nil
		append(&document.documents, root_node)
	}
}
