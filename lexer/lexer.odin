package lexer

import yaml_error "../yaml_error"
import "core:fmt"
import "core:strconv"

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
	line_indent:   int,
	has_line_indent: bool,
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

// consumes a comment starting at '#', up to and including the end of the line
lexer_skip_comment :: proc(l: ^Lexer) {
	for l.ch != '\n' && l.ch != '\r' && l.ch != 0 {
		lexer_read_char(l)
	}
	if l.ch != 0 {
		l.line += 1
		l.col = 0
		l.is_new_line = true
		l.has_line_indent = false
		lexer_read_char(l)
	}
}

// copies the string content seen so far into the builder the first time an
// escape sequence is encountered
lexer_backfill_escape :: proc(l: ^Lexer, builder: ^[dynamic]byte, has_escape: ^bool, start_position: int) {
	if !has_escape^ {
		has_escape^ = true
		for i in start_position ..< l.position {
			append(builder, l.input[i])
		}
	}
}

lexer_lex_number :: proc(l: ^Lexer) -> (tok: Token, err: yaml_error.YamlError) {
	tok.line = l.line
	tok.col = l.col
	start := l.position
	is_float := false
	for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' && l.ch != '\t' {
		if (l.ch == '.' || l.ch == 'e' || l.ch == 'E') && !is_float {
			is_float = true
		}
		lexer_read_char(l)
	}
	tok.text = l.input[start:l.position]
	tok.kind = .Float if is_float else .Integer

	valid := false
	if is_float {
		_, valid = strconv.parse_f64(tok.text)
	} else {
		_, valid = strconv.parse_int(tok.text)
	}
	if !valid {
		err = yaml_error.LexerError {
			kind    = .InvalidNumber,
			message = fmt.tprintf("invalid number literal %q", tok.text),
			line    = tok.line,
			col     = tok.col,
		}
	}
	return
}

lexer_next_token :: proc(l: ^Lexer) -> (tok: Token, err: yaml_error.YamlError) {
	if !l.is_new_line {
		for l.ch == ' ' || l.ch == '\t' {
			lexer_read_char(l)
		}
	}

	tok.col = l.col
	tok.line = l.line

	if l.is_new_line {
		// comment-only lines must not affect indentation, so re-run the
		// new-line/indent decision for each line until real content is found
		for {
			l.is_new_line = false

			// a line that is dedenting keeps the indentation it was measured
			// with, otherwise the spaces are gone and every dedent looks like
			// a dedent to column zero
			leading_space := l.line_indent
			if !l.has_line_indent {
				leading_space = 0
				for l.ch == ' ' || l.ch == '\t' {
					leading_space += 1
					lexer_read_char(l)
				}
				l.line_indent = leading_space
				l.has_line_indent = true
			}

			if l.ch == '#' {
				lexer_skip_comment(l)
				l.has_line_indent = false
				continue
			}

			previous_indent := l.indent_stack[len(l.indent_stack) - 1]

			if leading_space > previous_indent {
				append(&l.indent_stack, leading_space)
				tok.kind = .Indent
				tok.text = "indent"
				return
			} else if leading_space < previous_indent {
				pop(&l.indent_stack)
				l.is_new_line = true
				tok.kind = .Dedent
				tok.text = "dedent"
				return
			}
			break
		}
	}

	// trailing comments
	if l.ch == '#' {
		lexer_skip_comment(l)
		if l.ch == 0 {
			if len(l.indent_stack) > 1 {
				pop(&l.indent_stack)
				tok.kind = .Dedent
				tok.text = "dedent"
				return
			}
			tok.kind = .Eof
			return
		}
		tok.kind = .Newline
		tok.text = "\n"
		return
	}

	switch l.ch {
	case 0:
		if len(l.indent_stack) > 1 {
			pop(&l.indent_stack)
			tok.kind = .Dedent
			tok.text = "dedent"
			return
		}
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
			if len(l.indent_stack) > 1 {
				pop(&l.indent_stack)
				tok.kind = .Dedent
				tok.text = "dedent"
				return
			}
			tok.kind = .StreamStart if !l.within_stream else .StreamEnd
			l.within_stream = !l.within_stream
			tok.text = "---"
			for x := 0; x < 3; x += 1 {
				lexer_read_char(l)
			}
		} else if lexer_peek_ahead(l) >= '0' && lexer_peek_ahead(l) <= '9' {
			tok, err = lexer_lex_number(l)
			return
		} else {
			tok.kind = .Hyphen
			tok.text = "-"
			lexer_read_char(l)
		}

	case '\n', '\r':
		tok.kind = .Newline
		tok.text = "\n"
		l.line += 1
		l.col = 0
		l.is_new_line = true
		l.has_line_indent = false
		lexer_read_char(l)

	case '"', '\'':
		quote := l.ch
		start_position := l.read_position
		lexer_read_char(l)
		tok.kind = .String

		has_escape := false
		builder: [dynamic]byte
		for {
			if l.ch == 0 {
				err = yaml_error.LexerError {
					kind    = .UnterminatedString,
					message = "unterminated string literal",
					line    = l.line,
					col     = l.col,
				}
				return
			}
			if l.ch == quote {
				if quote == '\'' && lexer_peek_ahead(l) == '\'' {
					lexer_backfill_escape(l, &builder, &has_escape, start_position)
					append(&builder, cast(byte)'\'')
					lexer_read_char(l)
					lexer_read_char(l)
					continue
				}
				break
			}
			if l.ch == '\\' {
				lexer_backfill_escape(l, &builder, &has_escape, start_position)
				lexer_read_char(l)
				if l.ch == 0 {
					err = yaml_error.LexerError {
						kind    = .UnterminatedString,
						message = "unterminated string literal",
						line    = l.line,
						col     = l.col,
					}
					return
				}
				switch l.ch {
				case 'n': append(&builder, cast(byte)'\n')
				case 't': append(&builder, cast(byte)'\t')
				case 'r': append(&builder, cast(byte)'\r')
				case '0': append(&builder, 0)
				case '\\': append(&builder, cast(byte)'\\')
				case '"': append(&builder, cast(byte)'"')
				case '\'': append(&builder, cast(byte)'\'')
				case:
					append(&builder, cast(byte)l.ch)
				}
				lexer_read_char(l)
			} else {
				if has_escape {
					append(&builder, cast(byte)l.ch)
				}
				lexer_read_char(l)
			}
		}

		if has_escape {
			tok.text = string(builder[:])
			delete(builder)
		} else {
			tok.text = l.input[start_position:l.position]
		}
		lexer_read_char(l)
	case '0' ..= '9':
		tok, err = lexer_lex_number(l)
		return

	case:
		start := l.position
		tok.kind = .Identifier
		for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' && l.ch != '\t' {
			lexer_read_char(l)
		}
		tok.text = l.input[start:l.position]
	}

	return
}
