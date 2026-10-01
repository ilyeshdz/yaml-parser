package main

import "core:mem"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "emitter"
import "lexer"
import "parser"
import yaml_error "yaml_error"

EXIT_OK           :: 0
EXIT_PARSE_ERROR  :: 1
EXIT_USAGE_ERROR  :: 2
EXIT_LOOKUP_ERROR :: 3
EXIT_WRITE_ERROR  :: 4

SAMPLE_NAME :: "the built-in sample"

// set replaces a value that is already there, add puts a new key in
Edit_Mode :: enum {
	Set,
	Add,
}

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
anchored: &shared
	flag: true
	ratio: 2.5
alias_of_anchored: *shared
sequence_key:
	- item1
	- item2
	- item3
# comment before the stream end
...`

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
	Document_Out_Of_Range,
}

Lookup_Error :: struct {
	kind:      Lookup_Error_Kind,
	segment:   string,
	index:     int,
	// how many documents the stream holds, which is what puts a bound on the
	// number --doc can ask for
	count:     int,
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
	case .Document_Out_Of_Range:
		fmt.eprintf("Error: the stream holds %d documents, so document %d cannot be picked\n", err.count, err.index)
	}
}

print_usage :: proc(f: ^os.File) {
	fmt.fprintf(f, `yaml-parser, a YAML parser that pulls single values out of a file

Usage:
  yaml-parser                          parse and print the built-in sample
  yaml-parser dump <file>              parse <file> and print the whole tree
  yaml-parser get <file> <key.path>    print the value found at <key.path>
  yaml-parser get <file> <key.path> -t print the type of that value instead
  yaml-parser set <file> <key.path> <value> replace the value at <key.path>
  yaml-parser add <file> <key.path> <value> add a new key at <key.path>
  yaml-parser help                     print this message

Key paths are dot separated, and a numeric segment indexes a sequence:

  yaml-parser get config.yaml parent_key.child_key.test_it_out
  yaml-parser get config.yaml sequence_key.1

An anchor &name names a value and an alias *name reads that same value, so get
walks through an alias without caring that it is one.

A file can hold more than one document, each one behind a --- marker of its
own, and dump prints every one of them. get, set and add work on the first
document unless --doc <n> asks for another one, where the first document is 0,
and set and add write all of them back out so nothing behind the document they
edit is lost:

  yaml-parser get config.yaml release.1 --doc 1

set and add write the whole file back out, which means comments and the
original spacing are not kept. Pass --dry-run to see the result first. The
value is typed the way the parser would type it, so 1.5 is a float, true is a
boolean and 2026-10-01 is a timestamp.

A numeric path segment edits a list item, where set replaces the item and add
puts the value in front of it, so adding at the length of the list appends to
it. Adding to a key that is a list without an index appends to the list, and
makes a new key when the key is not there yet.

Exit codes:
  0  the value was printed
  1  the file could not be read or parsed
  2  the command was used wrong
  3  the key path was not found, or was already there
  4  the file could not be written
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

	sequence, is_sequence := node.value.(parser.SequenceNode)
	if is_sequence {
		return sequence_edit(sequence, path, value, create)
	}

	mapping, is_mapping := node.value.(parser.MappingNode)
	if !is_mapping {
		kind := Lookup_Error_Kind.Not_A_Collection
		if node.kind == .Sequence {
			kind = .Not_A_Mapping
		}
		return nil, Lookup_Error{kind = kind, segment = path, node_kind = node.kind}
	}

	pairs: [dynamic]parser.MappingPair
	for pair in mapping.pairs {
		append(&pairs, pair)
	}

	first_dot := strings.index_byte(path, '.')

	// a path of one segment is the key to write into this mapping
	if first_dot < 0 {
		index := parser.mapping_pair_index(mapping, path)
		switch {
		case index >= 0 && create:
			// adding to a key that is a sequence appends to it, anything else
			// is already holding a value and is left alone
			existing, is_list := pairs[index].value.value.(parser.SequenceNode)
			if !is_list {
				return nil, Lookup_Error{kind = .Key_Exists, segment = path}
			}
			pairs[index].value = sequence_append(existing, value)
		case index >= 0:
			pairs[index].value = value
		case create:
			append(&pairs, new_pair(path, value))
		case:
			return nil, Lookup_Error{kind = .Key_Not_Found, segment = path}
		}
		return wrap_mapping(pairs), Lookup_Error{}
	}

	// a longer path goes through the key it starts with
	head := path[:first_dot]
	child_path := path[first_dot + 1:]
	if head == "" || child_path == "" {
		return nil, Lookup_Error{kind = .Empty_Segment}
	}

	child_index := parser.mapping_pair_index(mapping, head)
	if child_index < 0 && !create {
		return nil, Lookup_Error{kind = .Key_Not_Found, segment = head}
	}

	source := wrap_mapping(nil)
	if child_index >= 0 {
		source = mapping.pairs[child_index].value
	}

	child, child_err := node_edit(source, child_path, value, create)
	if child_err.kind != .None {
		return nil, child_err
	}

	if child_index >= 0 {
		pairs[child_index].value = child
	} else {
		append(&pairs, new_pair(head, child))
	}

	return wrap_mapping(pairs), Lookup_Error{}
}

new_pair :: proc(segment: string, value: ^parser.YamlNode) -> parser.MappingPair {
	key := new(parser.YamlNode)
	key^ = parser.YamlNode{.Scalar, parser.ScalarNode{segment, .String}, ""}
	return parser.MappingPair{key, value}
}

wrap_mapping :: proc(pairs: [dynamic]parser.MappingPair) -> ^parser.YamlNode {
	node := new(parser.YamlNode)
	node^ = parser.YamlNode{.Mapping, parser.MappingNode{pairs}, ""}
	return node
}

// sequence_edit edits one item of a sequence. The head of the path is the
// index, so the same key path that get walks also walks a list. set replaces
// the item it is given and add puts the value in front of it, which appends
// when the index is the length of the sequence.
sequence_edit :: proc(sequence: parser.SequenceNode, path: string, value: ^parser.YamlNode, create: bool) -> (edited: ^parser.YamlNode, err: Lookup_Error) {
	first_dot := strings.index_byte(path, '.')

	head := path
	child_path := ""
	if first_dot >= 0 {
		head = path[:first_dot]
		child_path = path[first_dot + 1:]
		if head == "" || child_path == "" {
			return nil, Lookup_Error{kind = .Empty_Segment}
		}
	}

	index, is_index := strconv.parse_int(head, 10)
	if !is_index {
		return nil, Lookup_Error{kind = .Not_An_Index, segment = head}
	}
	if index < 0 {
		return nil, Lookup_Error{kind = .Index_Out_Of_Range, segment = head, index = index}
	}

	items: [dynamic]^parser.YamlNode
	for item in sequence.items {
		append(&items, item)
	}

	// the index itself is the item to change
	if child_path == "" {
		if !create {
			if index >= len(items) {
				return nil, Lookup_Error{kind = .Index_Out_Of_Range, segment = head, index = index}
			}
			items[index] = value
			return wrap_sequence(items), Lookup_Error{}
		}

		if index > len(items) {
			return nil, Lookup_Error{kind = .Index_Out_Of_Range, segment = head, index = index}
		}

		inserted: [dynamic]^parser.YamlNode
		for item, position in items {
			if position == index {
				append(&inserted, value)
			}
			append(&inserted, item)
		}
		if index == len(items) {
			append(&inserted, value)
		}
		return wrap_sequence(inserted), Lookup_Error{}
	}

	// the path keeps going, so the item is edited from the inside
	if index >= len(items) {
		return nil, Lookup_Error{kind = .Index_Out_Of_Range, segment = head, index = index}
	}

	child, child_err := node_edit(items[index], child_path, value, create)
	if child_err.kind != .None {
		return nil, child_err
	}
	items[index] = child

	return wrap_sequence(items), Lookup_Error{}
}

sequence_append :: proc(sequence: parser.SequenceNode, value: ^parser.YamlNode) -> ^parser.YamlNode {
	items: [dynamic]^parser.YamlNode
	for item in sequence.items {
		append(&items, item)
	}
	append(&items, value)
	return wrap_sequence(items)
}

wrap_sequence :: proc(items: [dynamic]^parser.YamlNode) -> ^parser.YamlNode {
	node := new(parser.YamlNode)
	node^ = parser.YamlNode{.Sequence, parser.SequenceNode{items}, ""}
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

scalar_node :: proc(text: string) -> ^parser.YamlNode {
	node := new(parser.YamlNode)
	node^ = parser.YamlNode{.Scalar, scalar_from_text(text), ""}
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
	case .Timestamp:
		fmt.println("timestamp")
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

	// a stream holding more than one document is printed whole, and the
	// documents are told apart by a blank line
	for node, index in document.documents {
		if index > 0 {
			fmt.println()
		}
		print_yaml_node(node, 0)
	}
	return EXIT_OK
}

// Flag_Options says which options a command takes, so that the ones belonging
// to another command can be turned down
Flag_Options :: struct {
	allow_type:    bool,
	allow_dry_run: bool,
}

// Flag_Values is what the options behind the positional arguments asked for
Flag_Values :: struct {
	show_type: bool,
	dry_run:   bool,
	// the document of the stream the command works on, 0 being the first one
	document:  int,
}

// parse_flags reads the options trailing the positional arguments of get, set
// and add, and hands back a message when something given is not one of them
parse_flags :: proc(args: []string, name: string, options: Flag_Options) -> (flags: Flag_Values, message: string) {
	i := 0
	for i < len(args) {
		switch args[i] {
		case "-t", "--type":
			if !options.allow_type {
				return Flag_Values{}, fmt.tprintf("unknown option '%s' for %s", args[i], name)
			}
			flags.show_type = true
		case "--dry-run":
			if !options.allow_dry_run {
				return Flag_Values{}, fmt.tprintf("unknown option '%s' for %s", args[i], name)
			}
			flags.dry_run = true
		case "--doc":
			if i + 1 >= len(args) {
				return Flag_Values{}, "--doc needs a document number"
			}
			number, parsed := strconv.parse_int(args[i + 1], 10)
			if !parsed || number < 0 {
				return Flag_Values{}, fmt.tprintf("%s is not a document number", args[i + 1])
			}
			flags.document = number
			i += 1
		case:
			return Flag_Values{}, fmt.tprintf("unknown option '%s' for %s", args[i], name)
		}
		i += 1
	}
	return flags, ""
}

// pick_document hands back the document the flags asked for, or the error that
// says the stream does not hold that many
pick_document :: proc(document: parser.YamlDocument, flags: Flag_Values) -> (node: ^parser.YamlNode, err: Lookup_Error) {
	node = parser.document_at(document, flags.document)
	if node == nil {
		return nil, Lookup_Error {
			kind  = .Document_Out_Of_Range,
			index = flags.document,
			count = len(document.documents),
		}
	}
	return node, Lookup_Error{}
}

run_get :: proc(args: []string, allocator := context.allocator) -> int {
	if len(args) < 2 {
		return report_usage_error("get takes a file and a key path")
	}

	filename := args[0]
	path := args[1]

	flags, flag_message := parse_flags(args[2:], "get", Flag_Options{allow_type = true})
	if flag_message != "" {
		return report_usage_error(flag_message)
	}

	document, err := load_document(filename, allocator)
	if err != nil {
		print_load_error(err, filename)
		return EXIT_PARSE_ERROR
	}

	root, lookup_err := pick_document(document, flags)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	node: ^parser.YamlNode
	node, lookup_err = node_lookup(root, path)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	if flags.show_type {
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

run_edit :: proc(args: []string, mode: Edit_Mode, allocator := context.allocator) -> int {
	name := edit_mode_name(mode)

	if len(args) < 3 {
		return report_usage_error(fmt.tprintf("%s takes a file, a key path and a value", name))
	}

	filename := args[0]
	path := args[1]
	text := args[2]

	flags, flag_message := parse_flags(args[3:], name, Flag_Options{allow_dry_run = true})
	if flag_message != "" {
		return report_usage_error(flag_message)
	}

	source, read_err := os.read_entire_file(filename, context.allocator)
	if read_err != nil {
		fmt.eprintf("Failed to read file %s: %v\n", filename, read_err)
		return EXIT_PARSE_ERROR
	}

	document, err := parse_source(string(source), allocator)
	if err != nil {
		print_load_error(err, filename)
		return EXIT_PARSE_ERROR
	}

	root, lookup_err := pick_document(document, flags)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	value := scalar_node(text)
	edited: ^parser.YamlNode
	edited, lookup_err = node_edit(root, path, value, mode == .Add)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	// the whole stream goes back out, so the documents behind the one being
	// edited are written back instead of being dropped
	document.documents[flags.document] = edited
	output := emitter.emit_stream(document.documents, emitter.detect_indent(string(source)), allocator)

	if flags.dry_run {
		fmt.print(output)
		return EXIT_OK
	}

	write_err := os.write_entire_file_from_string(filename, output)
	if write_err != nil {
		fmt.eprintf("Failed to write file %s: %v\n", filename, write_err)
		return EXIT_WRITE_ERROR
	}

	print_value(value)
	return EXIT_OK
}

edit_mode_name :: proc(mode: Edit_Mode) -> string {
	switch mode {
	case .Set:
		return "set"
	case .Add:
		return "add"
	}
	return ""
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
	case "set":
		return run_edit(args[2:], .Set, allocator)
	case "add":
		return run_edit(args[2:], .Add, allocator)
	}

	return report_usage_error(fmt.tprintf("unknown command '%s'", args[1]))
}

main :: proc() {
	os.exit(run(os.args))
}

print_yaml_node :: proc(node: ^parser.YamlNode, depth: int = 0) {
	written := make(map[^parser.YamlNode]bool)
	print_yaml_node_written(node, depth, &written)
}

// the dump says the same thing the emitter writes: the first time an anchored
// node shows up it is printed under its anchor, and a node that is the very
// same one a second time is printed as an alias
print_yaml_node_written :: proc(node: ^parser.YamlNode, depth: int, written: ^map[^parser.YamlNode]bool) {
    if written[node] {
        for _ in 0 ..< depth {
            fmt.print("  ")
        }
        fmt.printf("*%s\n", node.anchor)
        return
    }
    written[node] = true

    if node.anchor != "" {
        for _ in 0 ..< depth {
            fmt.print("  ")
        }
        fmt.printf("&%s\n", node.anchor)
    }

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
            print_yaml_node_written(pair.value, depth + 1, written)
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
                print_yaml_node_written(item, depth + 1, written)
            }
        }
    }
}
