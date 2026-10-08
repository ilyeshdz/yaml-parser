package main

import "core:strconv"
import "core:strings"
import "lexer"
import "parser"

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

// node_delete returns a copy of the document with one key dropped. Like
// node_edit it only rebuilds the spine from the root down to the change, and
// hands back the removed node so the caller can print what went away.
node_delete :: proc(node: ^parser.YamlNode, path: string) -> (edited: ^parser.YamlNode, removed: ^parser.YamlNode, err: Lookup_Error) {
	if path == "" {
		return nil, nil, Lookup_Error{kind = .Empty_Path}
	}

	sequence, is_sequence := node.value.(parser.SequenceNode)
	if is_sequence {
		return sequence_delete(sequence, path)
	}

	mapping, is_mapping := node.value.(parser.MappingNode)
	if !is_mapping {
		kind := Lookup_Error_Kind.Not_A_Collection
		if node.kind == .Sequence {
			kind = .Not_A_Mapping
		}
		return nil, nil, Lookup_Error{kind = kind, segment = path, node_kind = node.kind}
	}

	first_dot := strings.index_byte(path, '.')

	// a path of one segment is the key to drop from this mapping
	if first_dot < 0 {
		index := parser.mapping_pair_index(mapping, path)
		if index < 0 {
			return nil, nil, Lookup_Error{kind = .Key_Not_Found, segment = path}
		}
		pairs: [dynamic]parser.MappingPair
		for pair, position in mapping.pairs {
			if position != index {
				append(&pairs, pair)
			}
		}
		return wrap_mapping(pairs), mapping.pairs[index].value, Lookup_Error{}
	}

	// a longer path drops the key from inside the value it starts with
	head := path[:first_dot]
	child_path := path[first_dot + 1:]
	if head == "" || child_path == "" {
		return nil, nil, Lookup_Error{kind = .Empty_Segment}
	}

	child_index := parser.mapping_pair_index(mapping, head)
	if child_index < 0 {
		return nil, nil, Lookup_Error{kind = .Key_Not_Found, segment = head}
	}

	child, dropped, child_err := node_delete(mapping.pairs[child_index].value, child_path)
	if child_err.kind != .None {
		return nil, nil, child_err
	}

	pairs: [dynamic]parser.MappingPair
	for pair in mapping.pairs {
		append(&pairs, pair)
	}
	pairs[child_index].value = child

	return wrap_mapping(pairs), dropped, Lookup_Error{}
}

// sequence_delete drops one item of a sequence. The head of the path is the
// index of the item to drop, or of the item to drop from the inside when the
// path keeps going.
sequence_delete :: proc(sequence: parser.SequenceNode, path: string) -> (edited: ^parser.YamlNode, removed: ^parser.YamlNode, err: Lookup_Error) {
	first_dot := strings.index_byte(path, '.')

	head := path
	child_path := ""
	if first_dot >= 0 {
		head = path[:first_dot]
		child_path = path[first_dot + 1:]
		if head == "" || child_path == "" {
			return nil, nil, Lookup_Error{kind = .Empty_Segment}
		}
	}

	index, is_index := strconv.parse_int(head, 10)
	if !is_index {
		return nil, nil, Lookup_Error{kind = .Not_An_Index, segment = head}
	}
	if index < 0 || index >= len(sequence.items) {
		return nil, nil, Lookup_Error{kind = .Index_Out_Of_Range, segment = head, index = index}
	}

	// the index itself is the item to drop
	if child_path == "" {
		items: [dynamic]^parser.YamlNode
		for item, position in sequence.items {
			if position != index {
				append(&items, item)
			}
		}
		return wrap_sequence(items), sequence.items[index], Lookup_Error{}
	}

	// the path keeps going, so the item is dropped from the inside
	child, dropped, child_err := node_delete(sequence.items[index], child_path)
	if child_err.kind != .None {
		return nil, nil, child_err
	}

	items: [dynamic]^parser.YamlNode
	for item in sequence.items {
		append(&items, item)
	}
	items[index] = child

	return wrap_sequence(items), dropped, Lookup_Error{}
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

scalar_node :: proc(text: string, force_string := false) -> ^parser.YamlNode {
	node := new(parser.YamlNode)
	if force_string {
		node^ = parser.YamlNode{.Scalar, parser.ScalarNode{text, .String}, ""}
		return node
	}
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
