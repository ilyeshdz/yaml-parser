package lexer

import "core:strconv"

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
