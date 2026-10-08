package emitter

import parser "../parser"
import "core:strconv"
import "core:strings"

write_key :: proc(e: ^Emitter, key: ^parser.YamlNode) {
	scalar, is_scalar := key.value.(parser.ScalarNode)
	if !is_scalar {
		strings.write_string(&e.builder, "\"\"")
		return
	}

	// a timestamp goes out the way the file spelled it, quoting it would read
	// it back as the string it looks like instead of a date
	if scalar.type == .Timestamp {
		strings.write_string(&e.builder, scalar.value)
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
