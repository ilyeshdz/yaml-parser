package lexer;

import "core:fmt"

Lexer :: struct {
	input:         string,
	position:      int,
	read_position: int,
	ch:            rune,
	line:          int,
	col:           int,
	within_stream: bool
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

lexer_peek_ahead :: proc(l: ^Lexer, offset: int = 0) -> rune {
	if l.read_position + offset >= len(l.input) {
		return 0
	}
	return cast(rune)l.input[l.read_position + offset]
}

lexer_get_previous_char :: proc(l: ^Lexer) -> rune {
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
		if lexer_peek_ahead(l) == ' ' {
			tok.kind = .Bullet
			tok.text = "-"
			lexer_read_char(l)
		} else if lexer_peek_ahead(l) == '-' && lexer_peek_ahead(l, 1) == '-' {
			tok.kind = .StreamStart if !l.within_stream else .StreamEnd
			l.within_stream = !l.within_stream
			tok.text = "---";
			for x := 0; x < 3; x += 1 {
				lexer_read_char(l)
			}
		} else {
			tok.kind = .Hyphen
			tok.text = "-"
			lexer_read_char(l)
		}

	case '\n', '\r':
		tok.kind = .Newline
		tok.text = "\n"
		lexer_read_char(l);
	case '"', '\'':
		start_position := l.read_position
		lexer_read_char(l)
		tok.kind = .String
		fmt.println("input ", l.input, " start_position ", start_position, " position ", l.position)
		for l.ch != '"' && l.ch != '\'' {
			lexer_read_char(l)
		}
		tok.text = l.input[start_position:l.position]
		lexer_read_char(l)
	case '0'..= '9':
		start := l.position
		is_float := false
		for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' {
			if l.ch == '.' && !is_float {
				is_float = true
			}
			lexer_read_char(l)
		}
		tok.kind = .Float if is_float else .Integer
		tok.text = l.input[start:l.position]
	case:
		// handle both identifiers and numbers

		start := l.position
		tok.kind = .Identifier
		for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' {
			lexer_read_char(l)
		}
		tok.text = l.input[start:l.position]
	}

	return tok
}
