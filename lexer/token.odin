package lexer

Token :: struct {
	kind: Token_Kind,
	text: string,
	line: int,
	col: int
}

Token_Kind :: enum {
	Indent,
	Dedent,
	Eof,
	Colon,
	Bullet,
	StreamStart,
	StreamEnd,
	Hyphen,
	Anchor,
	Alias,
	Newline,
	Identifier,
	String,
	Integer,
	Float
}
