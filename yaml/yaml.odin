// Package yaml is the parsing library behind the yaml-parser command. It
// reads YAML text into documents, types plain values the way the parser
// types what it reads, and writes documents back out as YAML, while the
// command itself only handles flags, key paths and printing.
package yaml

import "core:os"
import "core:strconv"
import emitter "emitter"
import lexer "lexer"
import parser "parser"
import yaml_error "yaml_error"

Document :: parser.YamlDocument
Node :: parser.YamlNode

Error :: yaml_error.YamlError

Load_Error :: union {
	os.Error,
	yaml_error.YamlError,
}

// parse_string reads the documents YAML text holds, which is what a file
// holding more than one --- marker is made of
parse_string :: proc(source: string, allocator := context.allocator) -> (document: Document, err: Error) {
	my_lexer := lexer.lexer_init(source)

	my_parser, parser_err := parser.parser_init(&my_lexer)
	if parser_err != nil {
		return {}, parser_err
	}

	return parser.parser_parse(&my_parser, allocator)
}

// load_file reads a file and parses the documents it holds, handing back the
// source too because writing the documents back out keeps its indentation
load_file :: proc(filename: string, allocator := context.allocator) -> (document: Document, source: string, err: Load_Error) {
	bytes, read_err := os.read_entire_file(filename, context.allocator)
	if read_err != nil {
		return {}, "", read_err
	}

	source = string(bytes)
	parsed, parse_err := parse_string(source, allocator)
	if parse_err != nil {
		return {}, "", parse_err
	}

	return parsed, source, nil
}

// render_stream writes every document of a stream back out as YAML, keeping
// the indent unit of the source it was read from
render_stream :: proc(documents: [dynamic]^Node, source: string, allocator := context.allocator) -> string {
	return emitter.emit_stream(documents, emitter.detect_indent(source), allocator)
}

// scalar_from_text types a value the same way the parser types what it reads,
// so a value written by set and add comes back out of get with the same type
scalar_from_text :: proc(text: string) -> parser.ScalarNode {
	switch text {
	case "true", "false":
		return parser.ScalarNode{text, .Boolean}
	case "null", "~":
		return parser.ScalarNode{text, .Null}
	}

	if lexer.is_timestamp(text) {
		return parser.ScalarNode{text, .Timestamp}
	}

	if is_number(text) {
		kind := parser.ScalarType.Integer
		if is_float_text(text) {
			kind = .Float
		}
		return parser.ScalarNode{text, kind}
	}

	return parser.ScalarNode{text, .String}
}

// a dot or an exponent anywhere is what makes the lexer call a number a float
is_float_text :: proc(text: string) -> bool {
	for i in 0 ..< len(text) {
		switch text[i] {
		case '.', 'e', 'E':
			return true
		}
	}
	return false
}

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

	if is_float_text(digits) {
		_, ok := strconv.parse_f64(text)
		return ok
	}

	_, ok := strconv.parse_int(text)
	return ok
}
