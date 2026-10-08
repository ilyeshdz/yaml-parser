package main

import "core:fmt"
import "core:os"
import "core:strconv"
import yaml "yaml"
import "yaml/parser"
import yaml_error "yaml/yaml_error"

print_load_error :: proc(err: yaml.Load_Error, filename: string) {
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
  yaml-parser get <file> <key.path> --default <v> print <v> when the path is missing
  yaml-parser set <file> <key.path> <value> replace the value at <key.path>
  yaml-parser add <file> <key.path> <value> add a new key at <key.path>
  yaml-parser del <file> <key.path>    delete the value at <key.path>
  yaml-parser keys <file> [key.path]  list the keys of a mapping, one per line
  yaml-parser len <file> [key.path]   print how many entries a mapping or sequence holds
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
boolean and 2026-10-01 is a timestamp. Pass --string to keep the value a
string instead, so 42 stays the string "42".

A numeric path segment edits a list item, where set replaces the item and add
puts the value in front of it, so adding at the length of the list appends to
it. Adding to a key that is a list without an index appends to the list, and
makes a new key when the key is not there yet. del drops the key or the list
item the path points at and prints the removed value, and takes --doc and
--dry-run like the other editing commands.

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

// Flag_Options says which options a command takes, so that the ones belonging
// to another command can be turned down
Flag_Options :: struct {
	allow_type:    bool,
	allow_dry_run: bool,
	allow_string:  bool,
	allow_default: bool,
}

// Flag_Values is what the options behind the positional arguments asked for
Flag_Values :: struct {
	show_type:    bool,
	dry_run:      bool,
	// store the edited value as a string instead of typing it
	force_string: bool,
	// print this instead of failing when the key path is not found
	default_value: string,
	has_default:   bool,
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
		case "--string":
			if !options.allow_string {
				return Flag_Values{}, fmt.tprintf("unknown option '%s' for %s", args[i], name)
			}
			flags.force_string = true
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
		case "--default":
			if !options.allow_default {
				return Flag_Values{}, fmt.tprintf("unknown option '%s' for %s", args[i], name)
			}
			if i + 1 >= len(args) {
				return Flag_Values{}, "--default needs a value"
			}
			flags.default_value = args[i + 1]
			flags.has_default = true
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
