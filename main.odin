package main

import "core:mem"
import "core:fmt"
import "lexer"
import "parser"

main :: proc() {
    source := `---
schema: "my-custom-schema"
	test: 10
test2: 3.14
	test3: "hello"
---`

    my_lexer := lexer.lexer_init(source)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena)
    defer mem.dynamic_arena_destroy(&arena)
    arena_allocator := mem.dynamic_arena_allocator(&arena)

    my_parser := parser.parser_init(&my_lexer)
    document := parser.parser_parse(&my_parser, arena_allocator)

    for pair in document.root.pairs {
        fmt.println(pair.key, pair.value)
    }
}
