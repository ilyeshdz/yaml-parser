package parser;

YamlNodeKind :: enum {
	Scalar,
	Sequence,
	Mapping
}

YamlNode :: struct {
	kind: YamlNodeKind,
	value: union {
		ScalarNode,
		SequenceNode,
		MappingNode,
	},
	// the name an anchor gave this node, empty when nothing anchors it. Every
	// alias pointing at that name ends up holding this very node
	anchor: string,
}

ScalarType :: enum {
	String,
	Integer,
	Float,
	Boolean,
	Null,
}

ScalarNode :: struct {
	value: string,
	type: ScalarType
}

MappingPair :: struct {
	key: ^YamlNode,
	value: ^YamlNode,
}

MappingNode :: struct {
	pairs: [dynamic]MappingPair,
}

SequenceNode :: struct {
	items: [dynamic]^YamlNode,
}

YamlDocument :: struct {
	// every document the stream holds, one entry per --- marker, in the order
	// the file writes them
	documents: [dynamic]^YamlNode,
}

// document_at hands back the document standing at index in the stream, or
// nothing when the stream holds fewer documents than that
document_at :: proc(document: YamlDocument, index: int) -> ^YamlNode {
	if index < 0 || index >= len(document.documents) {
		return nil
	}
	return document.documents[index]
}
