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

// lexer_end_of_input closes whatever blocks are still open, then closes the
// document a --- opened, and only after both ends the token stream, so that
// the parser sees the end of the last document instead of a bare Eof
lexer_end_of_input :: proc(l: ^Lexer, tok: ^Token) {
	if len(l.indent_stack) > 1 {
		pop(&l.indent_stack)
		tok.kind = .Dedent
		tok.text = "dedent"
		return
	}

	if l.within_stream {
		l.within_stream = false
		tok.kind = .StreamEnd
		tok.text = "..."
		return
	}

	tok.kind = .Eof
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

// take_digits says how many decimal digits stand at start, counting up to
// limit of them and stopping at the first byte that is not one
take_digits :: proc(text: string, start, limit: int) -> int {
	n := 0
	for start + n < len(text) && n < limit {
		if text[start + n] < '0' || text[start + n] > '9' {
			break
		}
		n += 1
	}
	return n
}

// date_length says how many bytes of a date stand at the start of text, and 0
// when text does not open with one. A date is four digits, a dash, the month,
// a dash and the day, where the month and the day are one digit when the file
// leaves the leading one off.
date_length :: proc(text: string) -> int {
	if len(text) < 8 {
		return 0
	}
	if take_digits(text, 0, 4) != 4 || text[4] != '-' {
		return 0
	}

	month := take_digits(text, 5, 2)
	if month == 0 {
		return 0
	}
	at := 5 + month
	if at >= len(text) || text[at] != '-' {
		return 0
	}
	at += 1

	day := take_digits(text, at, 2)
	if day == 0 {
		return 0
	}

	// the month and the day have to be ones a calendar holds, a date naming a
	// thirteenth month is a typo worth saying something about, and it is left
	// to the number scan to complain about it
	month_value, month_ok := strconv.parse_int(text[5:at - 1], 10)
	day_value, day_ok := strconv.parse_int(text[at:at + day], 10)
	if !month_ok || !day_ok || month_value < 1 || month_value > 12 ||
	   day_value < 1 || day_value > 31 {
		return 0
	}

	return at + day
}

// time_length says how many bytes of a time stand at the start of text, which
// is the hours, the minutes and the seconds, along with the fraction and the
// offset YAML writes behind them when it has them, and 0 when what stands
// there is not a time
time_length :: proc(text: string) -> int {
	n := 0

	// the hours, one or two digits of them
	hours := take_digits(text, n, 2)
	if hours == 0 {
		return 0
	}
	n += hours
	if n >= len(text) || text[n] != ':' {
		return 0
	}
	n += 1

	// the minutes and the seconds are always written with two digits
	if take_digits(text, n, 2) != 2 {
		return 0
	}
	n += 2
	if n >= len(text) || text[n] != ':' {
		return 0
	}
	n += 1

	if take_digits(text, n, 2) != 2 {
		return 0
	}
	n += 2

	// a fraction of a second, a dot with the digits of it behind
	if n < len(text) && text[n] == '.' {
		fraction := take_digits(text, n + 1, len(text))
		if fraction == 0 {
			return n
		}
		n += 1 + fraction
	}

	// the offset is Z, z or a sign in front of the hours with the minutes
	// behind a colon when they are written, and YAML lets a space sit in front
	// of it. What stands behind the time without being one of those is another
	// value altogether, so the time ends where it does.
	offset_at := n
	for offset_at < len(text) && (text[offset_at] == ' ' || text[offset_at] == '\t') {
		offset_at += 1
	}
	if offset_at >= len(text) {
		return n
	}

	switch text[offset_at] {
	case 'Z', 'z':
		return offset_at + 1
	case '+', '-':
		offset_hours := take_digits(text, offset_at + 1, 2)
		if offset_hours == 0 {
			return n
		}
		end := offset_at + 1 + offset_hours
		if end < len(text) && text[end] == ':' && take_digits(text, end + 1, 2) == 2 {
			end += 3
		}
		return end
	}

	return n
}

// timestamp_length says how many bytes of a timestamp stand at the start of
// text, and 0 when text does not open with one. The date on its own is a
// timestamp, and the time behind it is the part YAML writes when it has it.
timestamp_length :: proc(text: string) -> int {
	date := date_length(text)
	if date == 0 {
		return 0
	}
	if date >= len(text) {
		return date
	}

	// the time sits right behind the date or one space behind it, and what
	// stands anywhere else behind the date is not part of a timestamp
	time_at := 0
	if text[date] == 't' || text[date] == 'T' || text[date] == ' ' {
		time_at = date + 1
	} else {
		return date
	}
	if time_at >= len(text) {
		return date
	}

	// a date with a time behind it that is not one keeps the date, the bytes
	// left over are somebody else's problem to report
	time := time_length(text[time_at:])
	if time == 0 {
		return date
	}
	return time_at + time
}

// is_timestamp says whether all of text is written the way YAML writes a
// timestamp, which is what a value typed as one has to look like
is_timestamp :: proc(text: string) -> bool {
	length := timestamp_length(text)
	return length > 0 && length == len(text)
}

// lexer_take_timestamp reads the timestamp standing at the current position
// and hands back the bytes it took, or nothing when what sits there is not one
lexer_take_timestamp :: proc(l: ^Lexer) -> (text: string, found: bool) {
	length := timestamp_length(l.input[l.position:])
	if length == 0 {
		return "", false
	}

	start := l.position
	for _ in 0 ..< length {
		lexer_read_char(l)
	}
	return l.input[start:l.position], true
}

lexer_lex_number :: proc(l: ^Lexer) -> (tok: Token, err: yaml_error.YamlError) {
	tok.line = l.line
	tok.col = l.col

	// a date opens like a number but the dashes standing in the middle of it
	// are what set it apart, so it is read first instead of being handed to a
	// number scan that cannot make sense of them
	if text, found := lexer_take_timestamp(l); found {
		tok.kind = .Timestamp
		tok.text = text
		return
	}

	start := l.position
	is_float := false
	for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' && l.ch != '\t' && l.ch != ',' &&
	    l.ch != '[' && l.ch != ']' && l.ch != '{' && l.ch != '}' && l.ch != 0 {
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

// an anchor or an alias is a sigil followed by a name that runs to the next
// space, a colon or the end of the line, so that a trailing comment or the
// next key does not get swallowed by the name
lexer_lex_name :: proc(l: ^Lexer, kind: Token_Kind) -> (tok: Token, err: yaml_error.YamlError) {
	sigil := "&" if kind == .Anchor else "*"

	tok.kind = kind
	tok.line = l.line
	tok.col = l.col
	lexer_read_char(l)

	start := l.position
	for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' && l.ch != '\t' &&
	    l.ch != ',' && l.ch != '[' && l.ch != ']' && l.ch != '#' && l.ch != 0 {
		lexer_read_char(l)
	}
	tok.text = l.input[start:l.position]

	if tok.text == "" {
		err = yaml_error.LexerError{
			kind    = .UnexpectedCharacter,
			message = fmt.tprintf("%q has to be followed by an anchor name", sigil),
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
			lexer_end_of_input(l, &tok)
			return
		}
		tok.kind = .Newline
		tok.text = "\n"
		return
	}

	// three dots end the document the last --- opened, which is what lets a
	// stream carry more than one of them
	if l.ch == '.' && lexer_peek_ahead(l) == '.' && lexer_peek_ahead(l, 1) == '.' {
		l.within_stream = false
		tok.kind = .StreamEnd
		tok.text = "..."
		lexer_read_char(l)
		lexer_read_char(l)
		lexer_read_char(l)
		return
	}

	switch l.ch {
	case 0:
		lexer_end_of_input(l, &tok)
	case ':':
		tok.kind = .Colon
		tok.text = ":"
		lexer_read_char(l)
	case ',':
		tok.kind = .Comma
		tok.text = ","
		lexer_read_char(l)
	case '[':
		tok.kind = .LBracket
		tok.text = "["
		lexer_read_char(l)
	case ']':
		tok.kind = .RBracket
		tok.text = "]"
		lexer_read_char(l)
	case '{':
		tok.kind = .LBrace
		tok.text = "{"
		lexer_read_char(l)
	case '}':
		tok.kind = .RBrace
		tok.text = "}"
		lexer_read_char(l)
	case '-':
		if lexer_peek_ahead(l) == ' ' {
			tok.kind = .Bullet
			tok.text = "-"
			lexer_read_char(l)
		} else if lexer_peek_ahead(l) == '\n' || lexer_peek_ahead(l) == '\r' || lexer_peek_ahead(l) == 0 {
			// a bullet with nothing behind it holds a collection written on
			// the lines below, which is how the emitter lays one out
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
			// every --- opens a document, so a marker standing between two of
			// them starts the one behind it instead of closing the stream
			tok.kind = .StreamStart
			l.within_stream = true
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

	case '&':
		tok, err = lexer_lex_name(l, .Anchor)
		return
	case '*':
		tok, err = lexer_lex_name(l, .Alias)
		return

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
		for l.ch != ' ' && l.ch != ':' && l.ch != '\n' && l.ch != '\r' && l.ch != '\t' && l.ch != ',' &&
		    l.ch != '[' && l.ch != ']' && l.ch != 0 {
			lexer_read_char(l)
		}
		tok.text = l.input[start:l.position]
	}

	return
}
