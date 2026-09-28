package yaml_error

LexerErrorKind :: enum {
	UnexpectedCharacter,
	UnterminatedString,
	InvalidNumber,
}

LexerError :: struct {
	kind:    LexerErrorKind,
	message: string,
	line:    int,
	col:     int,
}

ParserErrorKind :: enum {
	UnexpectedToken,
	ExpectedToken,
	MissingValue,
	InvalidIndentation,
	UnknownAnchor,
	DuplicateAnchor,
	RecursiveAlias,
}

ParserError :: struct {
	kind:    ParserErrorKind,
	message: string,
	line:    int,
	col:     int,
}

YamlError :: union {
	LexerError,
	ParserError,
}
