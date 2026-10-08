package yaml

import "parser"

// Builders make nodes by hand, for documents a program writes instead of
// reads. The counterparts that type text the way the parser would are
// scalar_from_text for inference and the accessors in query.odin for reading
// back out what was built.

// make_scalar makes a scalar node holding value as the given type, which is
// a plain string unless the caller says otherwise
make_scalar :: proc(value: string, type: parser.ScalarType = .String) -> ^Node {
	node := new(Node)
	node^ = Node{.Scalar, parser.ScalarNode{value, type}, ""}
	return node
}

// make_pair makes the mapping entry holding value under a plain string key
make_pair :: proc(key: string, value: ^Node) -> parser.MappingPair {
	k := new(Node)
	k^ = Node{.Scalar, parser.ScalarNode{key, .String}, ""}
	return parser.MappingPair{k, value}
}

// make_mapping makes a mapping node holding the given entries in order
make_mapping :: proc(pairs: ..parser.MappingPair) -> ^Node {
	entries: [dynamic]parser.MappingPair
	for pair in pairs {
		append(&entries, pair)
	}
	node := new(Node)
	node^ = Node{.Mapping, parser.MappingNode{entries}, ""}
	return node
}

// make_sequence makes a sequence node holding the given items in order
make_sequence :: proc(items: ..^Node) -> ^Node {
	list: [dynamic]^Node
	for item in items {
		append(&list, item)
	}
	node := new(Node)
	node^ = Node{.Sequence, parser.SequenceNode{list}, ""}
	return node
}

// make_document makes a document holding the given root nodes, one per ---
// marker when it is written back out
make_document :: proc(nodes: ..^Node) -> Document {
	document: Document
	for node in nodes {
		append(&document.documents, node)
	}
	return document
}
