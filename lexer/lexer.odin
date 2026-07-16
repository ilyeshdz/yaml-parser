package lexer

Lexer :: struct {
	input:         string,
	position:      int,
	read_position: int,
	ch:            rune,
	line:          int,
	col:           int,
	within_stream: bool,
	indent_stack:  [dynamic]int,
	is_new_line:   bool,
}

lexer_init :: proc(input: string) -> Lexer {
	l := Lexer {
		input = input,
		line  = 1,
		col   = 1,
	}
	append(&l.indent_stack, 0)
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
	if !l.is_new_line {
		for l.ch == ' ' || l.ch == '\t' {
			lexer_read_char(l)
		}
	}

	tok: Token
	tok.col = l.col
	tok.line = l.line

	if l.is_new_line {
		l.is_new_line = false
		leading_space := 0
		for l.ch == ' ' || l.ch == '\t' {
			leading_space += 1
			lexer_read_char(l)
		}

		previous_indent := l.indent_stack[len(l.indent_stack) - 1]

		if leading_space > previous_indent {
			append(&l.indent_stack, leading_space)
			tok.kind = .Indent
			tok.text = "indent"
			return tok
		} else if leading_space < previous_indent {
			pop(&l.indent_stack)
			tok.kind = .Dedent
			tok.text = "dedent"
			return tok
		}
	}

	switch l.ch {
	case 0:
		// handle end of file
		tok.kind = .Eof
	case ':':
		// handle colon
		tok.kind = .Colon
		tok.text = ":"
		lexer_read_char(l)
	case '-':
		// handle both bullets and hyphens as well as stream start/end
		if lexer_peek_ahead(l) == ' ' {
			tok.kind = .Bullet
			tok.text = "-"
			lexer_read_char(l)
		} else if lexer_peek_ahead(l) == '-' && lexer_peek_ahead(l, 1) == '-' {
			tok.kind = .StreamStart if !l.within_stream else .StreamEnd
			l.within_stream = !l.within_stream
			tok.text = "---"
			for x := 0; x < 3; x += 1 {
				lexer_read_char(l)
			}
		} else {
			tok.kind = .Hyphen
			tok.text = "-"
			lexer_read_char(l)
		}

	case '\n', '\r':
		// handle newlines & indentation
		tok.kind = .Newline
		tok.text = "\n"
		l.line += 1
		l.is_new_line = true
		lexer_read_char(l)

	case '"', '\'':
		// handle strings
		start_position := l.read_position
		lexer_read_char(l)
		tok.kind = .String
		for l.ch != '"' && l.ch != '\'' {
			lexer_read_char(l)
		}
		tok.text = l.input[start_position:l.position]
		lexer_read_char(l)
	case '0' ..= '9':
		// handle both integers and floats
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
		start := l.position
		tok.kind = .Identifier
		for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' {
			lexer_read_char(l)
		}
		tok.text = l.input[start:l.position]
		lexer_read_char(l)
	}

	return tok
}
