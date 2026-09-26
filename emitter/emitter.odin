package emitter

import parser "../parser"
import "core:strconv"
import "core:strings"

DEFAULT_INDENT :: "\t"

Emitter :: struct {
	builder: strings.Builder,
	indent:  string,
}

// Odin has no methods, so every writer procedure takes the emitter first, the
// same way core:os does it for a file.

emit_document :: proc(node: ^parser.YamlNode, indent := DEFAULT_INDENT, allocator := context.allocator) -> string {
	e := emitter_init(indent, allocator)
	// the parser refuses to read a document that does not open with a marker
	strings.write_string(&e.builder, "---\n")
	write_node(&e, node, 0)
	return strings.to_string(e.builder)
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
	}
	return e
}

write_node :: proc(e: ^Emitter, node: ^parser.YamlNode, depth: int) {
	switch v in node.value {
	case parser.MappingNode:
		for pair in v.pairs {
			write_indent(e, depth)
			write_key(e, pair.key)
			strings.write_string(&e.builder, ":")
			write_pair_value(e, pair.value, depth)
		}
	case parser.SequenceNode:
		for item in v.items {
			write_indent(e, depth)
			strings.write_string(&e.builder, "-")
			write_item_value(e, item, depth)
		}
	case parser.ScalarNode:
		write_indent(e, depth)
		write_scalar(e, v)
		strings.write_string(&e.builder, "\n")
	}
}

write_pair_value :: proc(e: ^Emitter, value: ^parser.YamlNode, depth: int) {
	switch v in value.value {
	case parser.MappingNode, parser.SequenceNode:
		strings.write_string(&e.builder, "\n")
		write_node(e, value, depth + 1)
	case parser.ScalarNode:
		strings.write_string(&e.builder, " ")
		write_scalar(e, v)
		strings.write_string(&e.builder, "\n")
	}
}

write_item_value :: proc(e: ^Emitter, item: ^parser.YamlNode, depth: int) {
	switch v in item.value {
	case parser.MappingNode, parser.SequenceNode:
		strings.write_string(&e.builder, "\n")
		write_node(e, item, depth + 1)
	case parser.ScalarNode:
		strings.write_string(&e.builder, " ")
		write_scalar(e, v)
		strings.write_string(&e.builder, "\n")
	}
}

write_indent :: proc(e: ^Emitter, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(&e.builder, e.indent)
	}
}

write_key :: proc(e: ^Emitter, key: ^parser.YamlNode) {
	scalar, is_scalar := key.value.(parser.ScalarNode)
	if !is_scalar {
		strings.write_string(&e.builder, "\"\"")
		return
	}

	if is_plain(scalar.value) {
		strings.write_string(&e.builder, scalar.value)
		return
	}
	write_quoted(e, scalar.value)
}

write_scalar :: proc(e: ^Emitter, scalar: parser.ScalarNode) {
	#partial switch scalar.type {
	case .String:
		if is_plain(scalar.value) {
			strings.write_string(&e.builder, scalar.value)
			return
		}
		write_quoted(e, scalar.value)
	case .Null:
		// a key that was written without a value reads back as an empty null
		if scalar.value == "" {
			strings.write_string(&e.builder, "null")
			return
		}
		strings.write_string(&e.builder, scalar.value)
	case:
		strings.write_string(&e.builder, scalar.value)
	}
}

write_quoted :: proc(e: ^Emitter, text: string) {
	strings.write_string(&e.builder, "\"")

	for i in 0 ..< len(text) {
		switch text[i] {
		case '"':
			strings.write_string(&e.builder, "\\\"")
		case '\\':
			strings.write_string(&e.builder, "\\\\")
		case '\n':
			strings.write_string(&e.builder, "\\n")
		case '\r':
			strings.write_string(&e.builder, "\\r")
		case '\t':
			strings.write_string(&e.builder, "\\t")
		case:
			strings.write_byte(&e.builder, text[i])
		}
	}

	strings.write_string(&e.builder, "\"")
}

// is_plain reports whether a scalar can be written without quotes and still be
// read back as the very same string.
is_plain :: proc(text: string) -> bool {
	if text == "" {
		return false
	}

	switch text {
	case "true", "false", "null", "~",
	     "True", "False", "Null",
	     "TRUE", "FALSE", "NULL",
	     "yes", "no", "on", "off",
	     "Yes", "No", "On", "Off":
		return false
	}

	if !is_plain_start(text[0]) {
		return false
	}

	for i in 1 ..< len(text) {
		if !is_plain_char(text[i]) {
			return false
		}
	}

	return !is_number(text)
}

is_plain_start :: proc(c: byte) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

is_plain_char :: proc(c: byte) -> bool {
	return is_plain_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.'
}

// is_number follows the lexer: a dot or an exponent anywhere makes it a float,
// and anything that does not parse is not a number at all.
is_number :: proc(text: string) -> bool {
	if text == "" {
		return false
	}

	digits := text
	if digits[0] == '-' || digits[0] == '+' {
		digits = digits[1:]
	}
	if digits == "" {
		return false
	}

	is_float := false
	for i in 0 ..< len(digits) {
		switch digits[i] {
		case '.', 'e', 'E':
			is_float = true
		}
	}

	if is_float {
		_, ok := strconv.parse_f64(text)
		return ok
	}

	_, ok := strconv.parse_int(text)
	return ok
}
