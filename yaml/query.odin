package yaml

import "core:strconv"
import "core:strings"
import "parser"

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
