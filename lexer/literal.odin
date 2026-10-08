package lexer

import yaml_error "../yaml_error"
import "core:fmt"
import "core:strconv"

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
