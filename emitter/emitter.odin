package emitter

import parser "../parser"
import "core:fmt"
import "core:strings"

DEFAULT_INDENT :: "\t"

Emitter :: struct {
	builder: strings.Builder,
	indent:  string,
	// the name every node already written went out under, which is what turns
	// the second node sharing a value with the first one into an alias
	written: map[^parser.YamlNode]string,
}

// a node is written either as the declaration of an anchor, as an alias
// pointing back at one, or as itself when no anchor has anything to do with it
Node_Reference :: struct {
	text:     string,
	is_alias: bool,
}

// Odin has no methods, so every writer procedure takes the emitter first, the
// same way core:os does it for a file.

// emit_document writes a single document behind its --- marker
emit_document :: proc(node: ^parser.YamlNode, indent := DEFAULT_INDENT, allocator := context.allocator) -> string {
	e := emitter_init(indent, allocator)
	write_document(&e, node)
	return strings.to_string(e.builder)
}

// emit_stream writes every document of a stream, each one behind its own
// marker, so that a file holding more than one of them comes back out whole
// instead of stopping at the first
emit_stream :: proc(documents: [dynamic]^parser.YamlNode, indent := DEFAULT_INDENT, allocator := context.allocator) -> string {
	e := emitter_init(indent, allocator)
	for node in documents {
		write_document(&e, node)
		// an anchor only means something inside the document that named it, so
		// the ones written so far mean nothing to the document behind this one
		clear(&e.written)
	}
	return strings.to_string(e.builder)
}

write_document :: proc(e: ^Emitter, node: ^parser.YamlNode) {
	// the parser refuses to read a document that does not open with a marker
	strings.write_string(&e.builder, "---\n")

	// an anchor on the document itself has nothing in front of it, so it goes
	// on the line under the marker, and the block it names stays as it is
	if node.anchor != "" {
		strings.write_string(&e.builder, "&")
		strings.write_string(&e.builder, node.anchor)
		strings.write_string(&e.builder, "\n")
		e.written[node] = node.anchor
	}

	write_node(e, node, 0)

	// the marker that closes a document is what tells the parser where the one
	// behind it begins
	strings.write_string(&e.builder, "...\n")
}

// detect_indent guesses the indent unit of a source document from its shortest
// indented line, so rewriting a file does not turn its tabs into spaces.
detect_indent :: proc(source: string) -> string {
	shortest := 0
	unit_start := 0
	start := 0

	for start <= len(source) {
		end := start
		for end < len(source) && source[end] != '\n' {
			end += 1
		}

		width := 0
		for start + width < end && (source[start + width] == ' ' || source[start + width] == '\t') {
			width += 1
		}

		// a line holding nothing but whitespace tells us nothing
		if width > 0 && start + width < end && (shortest == 0 || width < shortest) {
			shortest = width
			unit_start = start
		}

		if end >= len(source) {
			break
		}
		start = end + 1
	}

	if shortest == 0 {
		return DEFAULT_INDENT
	}
	return source[unit_start:unit_start + shortest]
}

emitter_init :: proc(indent: string, allocator := context.allocator) -> Emitter {
	e := Emitter {
		builder = strings.builder_make_none(allocator),
		indent  = indent,
		written = make(map[^parser.YamlNode]string),
	}
	return e
}

// node_reference names a node the first time it is written and hands back the
// alias that points at it every time after that, since the parser gave every
// alias the very same node.
node_reference :: proc(e: ^Emitter, node: ^parser.YamlNode) -> Node_Reference {
	name, already_written := e.written[node]
	if already_written {
		return Node_Reference{fmt.tprintf("*%s", name), true}
	}

	if node.anchor == "" {
		return Node_Reference{}
	}

	e.written[node] = node.anchor
	return Node_Reference{fmt.tprintf("&%s", node.anchor), false}
}

write_node :: proc(e: ^Emitter, node: ^parser.YamlNode, depth: int) {
	switch v in node.value {
	case parser.MappingNode:
		for pair in v.pairs {
			write_indent(e, depth)
			write_key(e, pair.key)
			strings.write_string(&e.builder, ":")
			write_value(e, pair.value, depth)
		}
	case parser.SequenceNode:
		for item in v.items {
			write_indent(e, depth)
			strings.write_string(&e.builder, "-")
			write_value(e, item, depth)
		}
	case parser.ScalarNode:
		write_indent(e, depth)
		write_scalar(e, v)
		strings.write_string(&e.builder, "\n")
	}
}

// write_value writes what follows a colon or a bullet. An anchor sits in front
// of the value it names, and a block it names goes on the lines below it, while
// an alias stands on its own because it already is the whole value.
write_value :: proc(e: ^Emitter, value: ^parser.YamlNode, depth: int) {
	reference := node_reference(e, value)

	switch v in value.value {
	case parser.MappingNode, parser.SequenceNode:
		strings.write_string(&e.builder, " ")
		if seq, is_seq := value.value.(parser.SequenceNode); is_seq && len(seq.items) == 0 && !reference.is_alias {
			// an empty sequence has no block form, so it goes out in flow
			// brackets, which is the only way it reads back as a sequence
			if reference.text != "" {
				strings.write_string(&e.builder, reference.text)
				strings.write_string(&e.builder, " ")
			}
			strings.write_string(&e.builder, "[]\n")
			return
		}
		if reference.text == "" {
			strings.write_string(&e.builder, "\n")
			write_node(e, value, depth + 1)
			return
		}
		strings.write_string(&e.builder, reference.text)
		strings.write_string(&e.builder, "\n")
		if !reference.is_alias {
			write_node(e, value, depth + 1)
		}

	case parser.ScalarNode:
		strings.write_string(&e.builder, " ")
		if reference.is_alias {
			strings.write_string(&e.builder, reference.text)
			strings.write_string(&e.builder, "\n")
			return
		}
		if reference.text != "" {
			strings.write_string(&e.builder, reference.text)
			strings.write_string(&e.builder, " ")
		}
		write_scalar(e, v)
		strings.write_string(&e.builder, "\n")
	}
}

write_indent :: proc(e: ^Emitter, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(&e.builder, e.indent)
	}
}
