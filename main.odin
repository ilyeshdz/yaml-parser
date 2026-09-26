package main

import "core:mem"
import "core:fmt"
import "core:os"
import "lexer"
import "parser"
import yaml_error "yaml_error"

EXIT_OK          :: 0
EXIT_PARSE_ERROR :: 1
EXIT_USAGE_ERROR :: 2

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

print_load_error :: proc(err: Load_Error, filename: string) {
	switch e in err {
	case os.Error:
		fmt.eprintf("Failed to read file %s: %v\n", filename, e)
	case yaml_error.YamlError:
		print_error(e)
	}
}

print_usage :: proc(f: ^os.File) {
	fmt.fprintf(f, `yaml-parser, a YAML parser for YAML files

Usage:
  yaml-parser                          parse and print the built-in sample
  yaml-parser dump <file>              parse <file> and print the whole tree
  yaml-parser help                     print this message

Exit codes:
  0  the value was printed
  1  the file could not be read or parsed
  2  the command was used wrong
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
