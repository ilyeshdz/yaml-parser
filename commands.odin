package main

import "core:fmt"
import "core:os"
import "emitter"
import "lexer"
import "parser"

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

run_get :: proc(args: []string, allocator := context.allocator) -> int {
	if len(args) < 2 {
		return report_usage_error("get takes a file and a key path")
	}

	filename := args[0]
	path := args[1]

	flags, flag_message := parse_flags(args[2:], "get", Flag_Options{allow_type = true, allow_default = true})
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
		if flags.has_default {
			print_default(flags, allocator)
			return EXIT_OK
		}
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	node: ^parser.YamlNode
	node, lookup_err = node_lookup(root, path)
	if lookup_err.kind != .None {
		if flags.has_default {
			print_default(flags, allocator)
			return EXIT_OK
		}
		print_lookup_error(lookup_err, path)
		return EXIT_LOOKUP_ERROR
	}

	if flags.show_type {
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

	flags, flag_message := parse_flags(args[3:], name, Flag_Options{allow_dry_run = true, allow_string = true})
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

	value := scalar_node(text, flags.force_string)
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

// run_delete drops the value at a key path and prints what went away, writing
// the whole stream back out the way set and add do
// run_keys prints the keys of the mapping at a key path, one per line, and
// run_len prints how many entries a mapping or a sequence holds. Both walk
// the path like get does and read the whole document when no path is given.
run_keys :: proc(args: []string, allocator := context.allocator) -> int {
	if len(args) < 1 {
		return report_usage_error("keys takes a file and an optional key path")
	}

	filename := args[0]
	path := ""
	rest := args[1:]
	if len(args) >= 2 && !is_flag(args[1]) {
		path = args[1]
		rest = args[2:]
	}

	flags, flag_message := parse_flags(rest, "keys", Flag_Options{})
	if flag_message != "" {
		return report_usage_error(flag_message)
	}

	node, code := lookup_collection(filename, path, flags, allocator)
	if code != EXIT_OK {
		return code
	}

	mapping, is_mapping := node.value.(parser.MappingNode)
	if !is_mapping {
		fmt.eprintf("Error: '%s' is a %v, so it has no keys\n", path, node.kind)
		return EXIT_LOOKUP_ERROR
	}

	for pair in mapping.pairs {
		if key, is_scalar := pair.key.value.(parser.ScalarNode); is_scalar {
			fmt.println(key.value)
		}
	}
	return EXIT_OK
}

run_len :: proc(args: []string, allocator := context.allocator) -> int {
	if len(args) < 1 {
		return report_usage_error("len takes a file and an optional key path")
	}

	filename := args[0]
	path := ""
	rest := args[1:]
	if len(args) >= 2 && !is_flag(args[1]) {
		path = args[1]
		rest = args[2:]
	}

	flags, flag_message := parse_flags(rest, "len", Flag_Options{})
	if flag_message != "" {
		return report_usage_error(flag_message)
	}

	node, code := lookup_collection(filename, path, flags, allocator)
	if code != EXIT_OK {
		return code
	}

	switch v in node.value {
	case parser.MappingNode:
		fmt.println(len(v.pairs))
	case parser.SequenceNode:
		fmt.println(len(v.items))
	case parser.ScalarNode:
		fmt.eprintf("Error: '%s' is a scalar, so it has no length\n", path)
		return EXIT_LOOKUP_ERROR
	}
	return EXIT_OK
}

// is_flag reports whether an argument is an option instead of a key path,
// which is how keys and len tell a missing path from a path to read
is_flag :: proc(arg: string) -> bool {
	return len(arg) > 2 && arg[:2] == "--" || len(arg) > 1 && arg[0] == '-'
}

// lookup_collection loads a file and walks it to the node a key path points
// at, or to the document itself when the path is empty
lookup_collection :: proc(filename: string, path: string, flags: Flag_Values, allocator := context.allocator) -> (node: ^parser.YamlNode, code: int) {
	document, err := load_document(filename, allocator)
	if err != nil {
		print_load_error(err, filename)
		return nil, EXIT_PARSE_ERROR
	}

	root, lookup_err := pick_document(document, flags)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return nil, EXIT_LOOKUP_ERROR
	}

	if path == "" {
		return root, EXIT_OK
	}

	node, lookup_err = node_lookup(root, path)
	if lookup_err.kind != .None {
		print_lookup_error(lookup_err, path)
		return nil, EXIT_LOOKUP_ERROR
	}

	return node, EXIT_OK
}

run_delete :: proc(args: []string, allocator := context.allocator) -> int {
	if len(args) < 2 {
		return report_usage_error("del takes a file and a key path")
	}

	filename := args[0]
	path := args[1]

	flags, flag_message := parse_flags(args[2:], "del", Flag_Options{allow_dry_run = true})
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

	edited, removed: ^parser.YamlNode
	edited, removed, lookup_err = node_delete(root, path)
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

	print_value(removed)
	return EXIT_OK
}
