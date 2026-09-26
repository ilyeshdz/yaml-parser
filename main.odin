package main

import "core:mem"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "lexer"
import "parser"
import yaml_error "yaml_error"

EXIT_OK           :: 0
EXIT_PARSE_ERROR  :: 1
EXIT_USAGE_ERROR  :: 2
EXIT_LOOKUP_ERROR :: 3

SAMPLE_NAME :: "the built-in sample"

SAMPLE_DOCUMENT :: `---
# a leading comment
name: yaml-parser
version: 1.5
build: 20260803
pi: 3.14159
count: -42
hex: 0x1F
scientific: 1.5e3
enabled: true
disabled: false
nothing: null
tilde: ~
empty_value:
quoted_key: "hello world"
'single quoted key': works
escaped: "line1\nline2\tend"
with_comment: 42 # trailing comment

parent_key:
	child_key:
		test_it_out: value
		flag: true
		ratio: 2.5
	score: 0
sequence_key:
	- item1
	- item2
	- item3
# comment before the stream end
---`

print_error :: proc(err: yaml_error.YamlError) {
	switch e in err {
	case yaml_error.LexerError:
		fmt.eprintf("Lexer error at %d:%d: %s\n", e.line, e.col, e.message)
	case yaml_error.ParserError:
		fmt.eprintf("Parser error at %d:%d: %s\n", e.line, e.col, e.message)
	}
}

Load_Error :: union {
	os.Error,
	yaml_error.YamlError,
}

Lookup_Error_Kind :: enum {
	None,
	Empty_Path,
	Empty_Segment,
	Key_Not_Found,
	Key_Exists,
	Not_A_Collection,
	Not_A_Mapping,
	Not_An_Index,
	Index_Out_Of_Range,
}

Lookup_Error :: struct {
	kind:      Lookup_Error_Kind,
	segment:   string,
	index:     int,
	node_kind: parser.YamlNodeKind,
}

print_load_error :: proc(err: Load_Error, filename: string) {
	switch e in err {
	case os.Error:
		fmt.eprintf("Failed to read file %s: %v\n", filename, e)
	case yaml_error.YamlError:
		print_error(e)
	}
}

print_lookup_error :: proc(err: Lookup_Error, path: string) {
	switch err.kind {
	case .None:
		return
	case .Empty_Path:
		fmt.eprintf("Error: the key path is empty\n")
	case .Empty_Segment:
		fmt.eprintf("Error: path '%s' has an empty segment\n", path)
	case .Key_Not_Found:
		fmt.eprintf("Error: no key '%s' in path '%s'\n", err.segment, path)
	case .Key_Exists:
		fmt.eprintf("Error: key '%s' already exists in path '%s'\n", err.segment, path)
	case .Not_A_Collection:
		fmt.eprintf("Error: '%s' holds a %v, so the rest of path '%s' cannot be resolved\n", err.segment, err.node_kind, path)
	case .Not_A_Mapping:
		fmt.eprintf("Error: '%s' is a %v, so no key can live inside it\n", err.segment, err.node_kind)
	case .Not_An_Index:
		fmt.eprintf("Error: '%s' holds a sequence, so '%s' has to be an index\n", err.segment, err.segment)
	case .Index_Out_Of_Range:
		fmt.eprintf("Error: index %d is out of range for the sequence at '%s'\n", err.index, err.segment)
	}
}

print_usage :: proc(f: ^os.File) {
	fmt.fprintf(f, `yaml-parser, a YAML parser that pulls single values out of a file

Usage:
  yaml-parser                          parse and print the built-in sample
  yaml-parser dump <file>              parse <file> and print the whole tree
  yaml-parser get <file> <key.path>    print the value found at <key.path>
  yaml-parser get <file> <key.path> -t print the type of that value instead
  yaml-parser help                     print this message

Key paths are dot separated, and a numeric segment indexes a sequence:

  yaml-parser get config.yaml parent_key.child_key.test_it_out
  yaml-parser get config.yaml sequence_key.1

Exit codes:
  0  the value was printed
  1  the file could not be read or parsed
  2  the command was used wrong
  3  the key path was not found
`)
}

report_usage_error :: proc(message: string) -> int {
	fmt.eprintf("Error: %s\n\n", message)
	print_usage(os.stderr)
	return EXIT_USAGE_ERROR
}

parse_source :: proc(source: string, allocator := context.allocator) -> (document: parser.YamlDocument, err: Load_Error) {
	my_lexer := lexer.lexer_init(source)

	my_parser, parser_err := parser.parser_init(&my_lexer)
	if parser_err != nil {
		return {}, parser_err
	}

	parsed, parse_err := parser.parser_parse(&my_parser, allocator)
	if parse_err != nil {
		return {}, parse_err
	}

	return parsed, nil
}

load_document :: proc(filename: string, allocator := context.allocator) -> (document: parser.YamlDocument, err: Load_Error) {
	source, read_err := os.read_entire_file(filename, context.allocator)
	if read_err != nil {
		return {}, read_err
	}

	return parse_source(string(source), allocator)
}

node_lookup :: proc(root: ^parser.YamlNode, path: string) -> (node: ^parser.YamlNode, err: Lookup_Error) {
	if path == "" {
		return nil, Lookup_Error{kind = .Empty_Path}
	}

	node = root
	remaining := path

	for segment in strings.split_iterator(&remaining, ".") {
		if segment == "" {
			return nil, Lookup_Error{kind = .Empty_Segment}
		}

		switch v in node.value {
		case parser.MappingNode:
			found := false
			for pair in v.pairs {
				key, is_scalar := pair.key.value.(parser.ScalarNode)
				if !is_scalar || key.value != segment {
					continue
				}
				node = pair.value
				found = true
				break
			}
			if !found {
				return nil, Lookup_Error{kind = .Key_Not_Found, segment = segment}
			}
		case parser.SequenceNode:
			index, is_index := strconv.parse_int(segment, 10)
			if !is_index {
				return nil, Lookup_Error{kind = .Not_An_Index, segment = segment}
			}
			if index < 0 || index >= len(v.items) {
				return nil, Lookup_Error{kind = .Index_Out_Of_Range, segment = segment, index = index}
			}
			node = v.items[index]
		case parser.ScalarNode:
			return nil, Lookup_Error{kind = .Not_A_Collection, segment = segment, node_kind = node.kind}
		}
	}

	return node, Lookup_Error{}
}

// node_edit returns a copy of the document with one key changed. Nodes are
// never touched in place, because a mapping lives inside a union and a union
// cannot hand out a pointer to what it holds, so only the spine from the root
// down to the change is rebuilt. When create is true a missing key is added,
// along with any mapping the path needs on its way there.
node_edit :: proc(node: ^parser.YamlNode, path: string, value: ^parser.YamlNode, create: bool) -> (edited: ^parser.YamlNode, err: Lookup_Error) {
	if path == "" {
		return nil, Lookup_Error{kind = .Empty_Path}
	}

	dot := strings.last_index_byte(path, '.')
	segment := path
	parent_path := ""
	head := ""
	if dot >= 0 {
		segment = path[dot + 1:]
		parent_path = path[:dot]
		head = parent_path
		if head_dot := strings.index_byte(head, '.'); head_dot >= 0 {
			head = head[:head_dot]
		}
	}

	if segment == "" {
		return nil, Lookup_Error{kind = .Empty_Segment}
	}

	mapping, is_mapping := node.value.(parser.MappingNode)
	if !is_mapping {
		kind := Lookup_Error_Kind.Not_A_Collection
		if node.kind == .Sequence {
			kind = .Not_A_Mapping
		}
		return nil, Lookup_Error{kind = kind, segment = segment, node_kind = node.kind}
	}

	// the rest of the path is edited first, so the change lands bottom up
	child_index := -1
	child: ^parser.YamlNode
	if parent_path != "" {
		child_index = mapping_pair_index(mapping, head)
		if child_index < 0 && !create {
			return nil, Lookup_Error{kind = .Key_Not_Found, segment = head}
		}

		source := wrap_mapping(nil)
		if child_index >= 0 {
			source = mapping.pairs[child_index].value
		}

		child, err = node_edit(source, parent_path, value, create)
		if err.kind != .None {
			return nil, err
		}
	}

	pairs: [dynamic]parser.MappingPair
	for pair in mapping.pairs {
		append(&pairs, pair)
	}
	if child_index >= 0 {
		pairs[child_index].value = child
	}
	if child_index < 0 && parent_path != "" {
		append(&pairs, new_pair(head, child))
	}

	// the recursion already dealt with the last segment when the path continues
	if parent_path != "" {
		return wrap_mapping(pairs), Lookup_Error{}
	}

	index := mapping_pair_index(mapping, segment)
	switch {
	case index >= 0 && create:
		return nil, Lookup_Error{kind = .Key_Exists, segment = segment}
	case index >= 0:
		pairs[index].value = value
	case create:
		append(&pairs, new_pair(segment, value))
	case:
		return nil, Lookup_Error{kind = .Key_Not_Found, segment = segment}
	}

	return wrap_mapping(pairs), Lookup_Error{}
}

mapping_pair_index :: proc(mapping: parser.MappingNode, segment: string) -> int {
	for pair, index in mapping.pairs {
		key, is_scalar := pair.key.value.(parser.ScalarNode)
		if is_scalar && key.value == segment {
			return index
		}
	}
	return -1
}

new_pair :: proc(segment: string, value: ^parser.YamlNode) -> parser.MappingPair {
	key := new(parser.YamlNode)
	key^ = parser.YamlNode{.Scalar, parser.ScalarNode{segment, .String}}
	return parser.MappingPair{key, value}
}

wrap_mapping :: proc(pairs: [dynamic]parser.MappingPair) -> ^parser.YamlNode {
	node := new(parser.YamlNode)
	node^ = parser.YamlNode{.Mapping, parser.MappingNode{pairs}}
	return node
}

// scalar_from_text types a value the same way the parser types what it reads,
// so a value written by set and add comes back out of get with the same type.
scalar_from_text :: proc(text: string) -> parser.ScalarNode {
	switch text {
	case "true", "false":
		return parser.ScalarNode{text, .Boolean}
	case "null", "~":
		return parser.ScalarNode{text, .Null}
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

scalar_node :: proc(text: string) -> ^parser.YamlNode {
	node := new(parser.YamlNode)
	node^ = parser.YamlNode{.Scalar, scalar_from_text(text)}
	return node
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

print_value :: proc(node: ^parser.YamlNode) {
	if scalar, is_scalar := node.value.(parser.ScalarNode); is_scalar {
		fmt.println(scalar.value)
		return
	}

	print_yaml_node(node, 0)
}

print_scalar_type :: proc(node: ^parser.YamlNode) {
	scalar, is_scalar := node.value.(parser.ScalarNode)
	if !is_scalar {
		return
	}

	switch scalar.type {
	case .String:
		fmt.println("string")
	case .Integer:
		fmt.println("integer")
	case .Float:
		fmt.println("float")
	case .Boolean:
		fmt.println("boolean")
	case .Null:
		fmt.println("null")
	}
}

run_dump :: proc(filename: string, allocator := context.allocator) -> int {
	label := filename
	document: parser.YamlDocument
	err: Load_Error

	if filename == "" {
		label = SAMPLE_NAME
		document, err = parse_source(SAMPLE_DOCUMENT, allocator)
	} else {
		document, err = load_document(filename, allocator)
	}

	if err != nil {
		print_load_error(err, label)
		return EXIT_PARSE_ERROR
	}

	print_yaml_node(document.root, 0)
	return EXIT_OK
}

run_get :: proc(args: []string, allocator := context.allocator) -> int {
	if len(args) < 2 {
		return report_usage_error("get takes a file and a key path")
	}
	if len(args) > 3 {
		return report_usage_error("get takes a file, a key path and an optional -t")
	}

	filename := args[0]
	path := args[1]

	show_type := false
	if len(args) == 3 {
		if args[2] != "-t" && args[2] != "--type" {
			return report_usage_error(fmt.tprintf("unknown option '%s' for get", args[2]))
		}
		show_type = true
	}

	document, err := load_document(filename, allocator)
	if err != nil {
		print_load_error(err, filename)
		return EXIT_PARSE_ERROR
	}

	node, lookup_err := node_lookup(document.root, path)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	if show_type {
		if node.kind != .Scalar {
			fmt.eprintf("Error: '%s' is a %v, so it has no scalar type\n", path, node.kind)
			return EXIT_USAGE_ERROR
		}
		print_scalar_type(node)
		return EXIT_OK
	}

	print_value(node)
	return EXIT_OK
}

run :: proc(args: []string) -> int {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)

	if len(args) < 2 {
		return run_dump("", allocator)
	}

	switch args[1] {
	case "help", "-h", "--help":
		print_usage(os.stdout)
		return EXIT_OK
	case "dump":
		if len(args) > 3 {
			return report_usage_error("dump takes a single file")
		}
		filename := ""
		if len(args) == 3 {
			filename = args[2]
		}
		return run_dump(filename, allocator)
	case "get":
		return run_get(args[2:], allocator)
	}

	return report_usage_error(fmt.tprintf("unknown command '%s'", args[1]))
}

main :: proc() {
	os.exit(run(os.args))
}

print_yaml_node :: proc(node: ^parser.YamlNode, depth: int = 0) {
    switch v in node.value {
    case parser.ScalarNode:
        for _ in 0 ..< depth {
            fmt.print("  ")
        }
        fmt.println(v.value)
    case parser.MappingNode:
        for pair in v.pairs {
            for _ in 0 ..< depth {
                fmt.print("  ")
            }
            if pair.key.kind == .Scalar {
                fmt.printf("%s:\n", pair.key.value.(parser.ScalarNode).value)
            } else {
                fmt.printf("<complex key>:\n")
            }
            print_yaml_node(pair.value, depth + 1)
        }
    case parser.SequenceNode:
        for item in v.items {
            for _ in 0 ..< depth {
                fmt.print("  ")
            }
            if item.kind == .Scalar {
                fmt.printf("- %s\n", item.value.(parser.ScalarNode).value)
            } else {
                fmt.println("-")
                print_yaml_node(item, depth + 1)
            }
        }
    }
}
