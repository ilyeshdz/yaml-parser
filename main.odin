package main

import "core:mem"
import "core:fmt"
import "core:os"

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
	case "del":
		return run_delete(args[2:], allocator)
	case "keys":
		return run_keys(args[2:], allocator)
	case "len":
		return run_len(args[2:], allocator)
	}

	return report_usage_error(fmt.tprintf("unknown command '%s'", args[1]))
}

main :: proc() {
	os.exit(run(os.args))
}
