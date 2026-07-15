package lexer

import "core:fmt"

Lexer :: struct {
	input:         string,
	position:      int,
	read_position: int,
	ch:            rune,
	line:          int,
	col:           int,
}

lexer_init :: proc(input: string) -> Lexer {
	l := Lexer {
		input = input,
		line  = 1,
		col   = 1,
	}
	lexer_read_char(&l)
	return l
}

lexer_read_char :: proc(l: ^Lexer) {
	if l.read_position >= len(l.input) {
		l.ch = 0
	} else {
		l.ch = cast(rune)l.input[l.read_position]
	}
	l.position = l.read_position
	l.read_position += 1
	l.col += 1
}

lexer_peek_char :: proc(l: ^Lexer) -> rune {
	if l.read_position >= len(l.input) {
		return 0
	}
	return cast(rune)l.input[l.read_position]
}

lexer_previous_char :: proc(l: ^Lexer) -> rune {
	if l.position == 0 || l.position > len(l.input) {
		return 0
	}
	return cast(rune)l.input[l.position - 1]
}

lexer_next_token :: proc(l: ^Lexer) -> Token {
	for l.ch == ' ' {
		lexer_read_char(l)
	}

	tok: Token
	tok.col = l.col
	tok.line = l.line

	switch l.ch {
	case 0:
		tok.kind = .Eof
	case ':':
		tok.kind = .Colon
		tok.text = ":"
		lexer_read_char(l)
	case '-':
		tok.kind = .Hyphen
		tok.text = "-"
		lexer_read_char(l);
	case '\n', '\r':
		tok.kind = .Newline
		tok.text = "\n"
		lexer_read_char(l);
	case:
		start := l.position
		tok.kind = .Identifier
		for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' {
			lexer_read_char(l)
		}
		tok.text = l.input[start:l.position]
	}

	return tok
}
