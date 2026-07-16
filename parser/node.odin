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
	root: ^MappingNode,
}
