package main

import "core:fmt"
import "core:strings"
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

print_value :: proc(node: ^parser.YamlNode) {
	if scalar, is_scalar := node.value.(parser.ScalarNode); is_scalar {
		fmt.println(scalar.value)
		return
	}

	print_yaml_node(node, 0)
}

// print_default prints the --default value of a get whose key path missed,
// typed the way a value written by set would be when -t asks for the type
print_default :: proc(flags: Flag_Values, allocator := context.allocator) {
	if flags.show_type {
		print_scalar_type(scalar_node(flags.default_value))
		return
	}
	fmt.println(flags.default_value)
}

print_scalar_type :: proc(node: ^parser.YamlNode) {
	switch node.kind {
	case .Mapping:
		fmt.println("mapping")
		return
	case .Sequence:
		fmt.println("sequence")
		return
	case .Scalar:
	}

	scalar := node.value.(parser.ScalarNode)

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

print_yaml_node :: proc(node: ^parser.YamlNode, depth: int = 0) {
	written := make(map[^parser.YamlNode]bool)
	print_yaml_node_written(node, depth, &written)
}

// format_dump_scalar prints a scalar the way the emitter writes one, so a
// value holding a newline stays on one line instead of breaking the tree
format_dump_scalar :: proc(scalar: parser.ScalarNode) -> string {
	if scalar.value == "" {
		if scalar.type == .Null {
			return "null"
		}
		return "\"\""
	}

	needs_quotes := false
	for i in 0 ..< len(scalar.value) {
		switch scalar.value[i] {
		case '"', '\\', '\n', '\r', '\t':
			needs_quotes = true
		}
	}
	if !needs_quotes {
		return scalar.value
	}

	builder := strings.builder_make_none(context.allocator)
	strings.write_string(&builder, "\"")
	for i in 0 ..< len(scalar.value) {
		switch scalar.value[i] {
		case '"':
			strings.write_string(&builder, "\\\"")
		case '\\':
			strings.write_string(&builder, "\\\\")
		case '\n':
			strings.write_string(&builder, "\\n")
		case '\r':
			strings.write_string(&builder, "\\r")
		case '\t':
			strings.write_string(&builder, "\\t")
		case:
			strings.write_byte(&builder, scalar.value[i])
		}
	}
	strings.write_string(&builder, "\"")
	return strings.to_string(builder)
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
        fmt.println(format_dump_scalar(v))
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
                fmt.printf("- %s\n", format_dump_scalar(item.value.(parser.ScalarNode)))
            } else {
                fmt.println("-")
                print_yaml_node_written(item, depth + 1, written)
            }
        }
    }
}
