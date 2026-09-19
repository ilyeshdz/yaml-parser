package main

import "core:mem"
import "core:fmt"
import "lexer"
import "parser"
import yaml_error "yaml_error"

print_error :: proc(err: yaml_error.YamlError) {
	switch e in err {
	case yaml_error.LexerError:
		fmt.eprintf("Lexer error at %d:%d: %s\n", e.line, e.col, e.message)
	case yaml_error.ParserError:
		fmt.eprintf("Parser error at %d:%d: %s\n", e.line, e.col, e.message)
	}
}

main :: proc() {
	source := `---
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

	my_lexer := lexer.lexer_init(source)
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	arena_allocator := mem.dynamic_arena_allocator(&arena)

	my_parser, p_err := parser.parser_init(&my_lexer)
	if p_err != nil {
		print_error(p_err)
		return
	}
	document, err := parser.parser_parse(&my_parser, arena_allocator)

	if err != nil {
		print_error(err)
		return
	}

	root_node: parser.YamlNode
	root_node.kind = .Mapping
	root_node.value = document.root^
	print_yaml_node(&root_node)
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
            key_str := pair.key.value.(parser.ScalarNode).value
            fmt.printf("%s:\n", key_str)
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
