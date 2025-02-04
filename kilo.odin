package main

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:time"
import "core:unicode"

/*** defines ***/
KILO_VERSION :: "0.0.1"
KILO_TAB_STOP :: 8
KILO_QUIT_TIMES :: 3

CTRL_KEY :: proc(k: rune) -> rune {
	return rune(byte(k) & 0x1f)
}

Editor_Key :: enum {
	BACKSPACE = 127,
	ARROW_LEFT = 1000,
	ARROW_RIGHT,
	ARROW_UP,
	ARROW_DOWN,
	DEL_KEY,
	HOME_KEY,
	END_KEY,
	PAGE_UP,
	PAGE_DOWN,
}
/*** data ***/

erow :: struct {
	chars:  string,
	render: string,
}
editor_config :: struct {
	cx:             int,
	cy:             int,
	rx:             int,
	rowoff:         int,
	coloff:         int,
	screenrows:     int,
	screencols:     int,
	numrows:        int,
	row:            [dynamic]erow,
	dirty:          int,
	filename:       string,
	statusmsg:      string,
	statusmsg_time: i64,
	orig_termios:   posix.termios,
}

E: editor_config

/*** terminal ***/

die :: proc(s: string) {
	editor_refresh_screen()
	fmt.panicf("%s: %s\n", s, posix.strerror(posix.errno()))
}

disable_raw_mode :: proc() {
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &E.orig_termios) != .OK {
		die("tcsetattr")
	}
}

enable_raw_mode :: proc() {
	if posix.tcgetattr(posix.STDIN_FILENO, &E.orig_termios) != .OK {
		die("tcgetattr")
	}

	raw := E.orig_termios
	// Disable
	//  ICRNL: Ctrl-M
	//  IXON: Ctrl-S and Ctrl-Q, Ctrl-S stops data from being transmitted to the terminal until you press Ctrl-Q
	raw.c_iflag &~= {.BRKINT} | {.ICRNL} | {.INPCK} | {.ISTRIP} | {.IXON}
	// Turn off all output processing
	raw.c_oflag &~= {.OPOST}
	raw.c_cflag |= {.CS8}
	// Turn off
	//  echo
	//  canonical mode -> reading input byte-by-byte, instead of line-by-line
	//  IEXTEN: Ctrl-V, and Ctrl-O in macOS
	//  ISIG: Ctrl-C and Ctrl-Z signals
	raw.c_lflag &~= {.ECHO} | {.ICANON} | {.IEXTEN} | {.ISIG}
	// VMIN sets the minimum number of bytes of input needed before read() can return
	// set it to 0 so that read() returns as soon as there is any input to be read
	raw.c_cc[.VMIN] = 0
	// VTIME value sets the maximum amount of time to wait before read() returns
	// 1 means 0.1 seconds
	raw.c_cc[.VTIME] = 1

	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
		die("tcsetattr")
	}
}

editor_read_key :: proc() -> rune {
	c: [1]byte
	for {
		nread := posix.read(posix.STDIN_FILENO, &c[0], 1)
		if nread == 1 {break}
		if nread == -1 && posix.errno() == .EAGAIN {
			die("read")
		}
	}

	if (c == 0x1b) {
		seq: [3]byte
		if posix.read(posix.STDIN_FILENO, &seq[0], 1) != 1 {return 0x1b}
		if posix.read(posix.STDIN_FILENO, &seq[1], 1) != 1 {return 0x1b}
		if seq[0] == '[' {
			if seq[1] >= '0' && seq[1] <= '9' {
				if posix.read(posix.STDIN_FILENO, &seq[2], 1) != 1 {return 0x1b}
				if seq[2] == '~' {
					switch seq[1] {
					case '1':
						return rune(Editor_Key.HOME_KEY)
					case '3':
						return rune(Editor_Key.DEL_KEY)
					case '4':
						return rune(Editor_Key.END_KEY)
					case '5':
						return rune(Editor_Key.PAGE_UP)
					case '6':
						return rune(Editor_Key.PAGE_DOWN)
					case '7':
						return rune(Editor_Key.HOME_KEY)
					case '8':
						return rune(Editor_Key.END_KEY)
					}
				}
			} else {
				switch seq[1] {
				case 'A':
					return rune(Editor_Key.ARROW_UP)
				case 'B':
					return rune(Editor_Key.ARROW_DOWN)
				case 'C':
					return rune(Editor_Key.ARROW_RIGHT)
				case 'D':
					return rune(Editor_Key.ARROW_LEFT)
				case 'H':
					return rune(Editor_Key.HOME_KEY)
				case 'F':
					return rune(Editor_Key.END_KEY)
				}
			}
		} else if seq[0] == 'O' {
			switch seq[1] {
			case 'H':
				return rune(Editor_Key.HOME_KEY)
			case 'F':
				return rune(Editor_Key.END_KEY)
			}
		}
		return 0x1b
	} else {
		return rune(c[0])
	}
}

get_cursor_position :: proc(rows: ^int, cols: ^int) -> int {
	buf: [32]byte
	i := 0

	if write_bytes([]u8{0x1b, '[', '6', 'n'}) != 4 {return -1}
	for i < len(buf) - 1 {
		if posix.read(posix.STDIN_FILENO, &buf[i], 1) != 1 {break}
		if buf[i] == 'R' {break}
		i += 1
	}

	if buf[0] != '\x1b' || buf[1] != '[' {return -1}
	if libc.sscanf(cstring(&buf[2]), "%d;%d", rows, cols) != 2 {return -1}
	return 0
}

foreign import libc2 "system:c"
foreign libc2 {
	ioctl :: proc(fd: c.int, request: c.ulong, #c_vararg args: ..any) -> c.int ---
}

winsize :: struct {
	ws_row:    u16,
	ws_col:    u16,
	ws_xpixel: u16,
	ws_ypixel: u16,
}

TIOCGWINSZ :: 0x40087468 // MacOS specific

get_window_size :: proc(rows: ^int, cols: ^int) -> int {
	ws: winsize

	if ioctl(posix.STDOUT_FILENO, TIOCGWINSZ, &ws) == -1 || ws.ws_col == 0 {
		if write_bytes([]u8{0x1b, '[', '9', '9', '9', 'C', 0x1b, '[', '9', '9', '9', 'B'}) !=
		   12 {return -1}
		return get_cursor_position(rows, cols)
	} else {
		cols^ = int(ws.ws_col)
		rows^ = int(ws.ws_row)
		return 0
	}
}

/*** row operations ***/
editor_row_cx_to_rx :: proc(row: ^erow, cx: int) -> int {
	rx := 0
	for j := 0; j < cx; j += 1 {
		if row.chars[j] == '\t' {
			rx += (KILO_TAB_STOP - 1) - (rx % KILO_TAB_STOP)}
		rx += 1
	}
	return rx
}

editor_update_row :: proc(row: ^erow) {
	row.render, _ = strings.replace_all(row.chars, "\t", strings.repeat(" ", KILO_TAB_STOP))
}

editor_insert_row :: proc(at: int, s: string) {
	if at < 0 || at > E.numrows {return}

	row := erow {
		chars = s,
	}
	editor_update_row(&row)
	inject_at(&E.row, at, row)
	E.numrows += 1
	E.dirty += 1
}

editor_del_row :: proc(at: int) {
	if at < 0 || at >= E.numrows {return}
	ordered_remove(&E.row, at)
	E.numrows -= 1
	E.dirty += 1
}

editor_row_insert_char :: proc(row: ^erow, at: int, c: rune) {
	at := at
	if at < 0 || at > len(row.chars) {at = len(row.chars)}

	builder := strings.builder_make()
	// defer strings.builder_destroy(&builder)

	strings.write_string(&builder, row.chars[:at])
	strings.write_rune(&builder, c)
	strings.write_string(&builder, row.chars[at:])

	row.chars = strings.to_string(builder)
	editor_update_row(row)
	E.dirty += 1
}

editor_row_append_string :: proc(row: ^erow, s: string) {
	row.chars = strings.concatenate({row.chars, s})
	editor_update_row(row)
	E.dirty += 1
}

editor_row_del_char :: proc(row: ^erow, at: int) {
	if at < 0 || at >= len(row.chars) {return}

	b := strings.builder_make()
	// defer strings.builder_destroy(&b)

	strings.write_string(&b, row.chars[:at])
	strings.write_string(&b, row.chars[at + 1:])

	row.chars = strings.to_string(b)
	editor_update_row(row)
	E.dirty += 1
}

/*** editor operations ***/
editor_insert_char :: proc(c: rune) {
	if E.cy == E.numrows {
		editor_insert_row(E.numrows, "")
	}
	editor_row_insert_char(&E.row[E.cy], E.cx, c)
	E.cx += 1
}

editor_insert_newline :: proc() {
	if E.cx == 0 {
		editor_insert_row(E.cy, "")
	} else {
		row := &E.row[E.cy]
		editor_insert_row(E.cy + 1, row.chars[E.cx:])
		row = &E.row[E.cy]
		row.chars = row.chars[:E.cx]
		editor_update_row(row)
	}
	E.cy += 1
	E.cx = 0
}

editor_del_char :: proc() {
	if E.cy == E.numrows {return}
	if E.cx == 0 && E.cy == 0 {return}

	row := &E.row[E.cy]
	if E.cx > 0 {
		editor_row_del_char(row, E.cx - 1)
		E.cx -= 1
	} else {
		E.cx = len(E.row[E.cy - 1].chars)
		editor_row_append_string(&E.row[E.cy - 1], row.chars)
		editor_del_row(E.cy)
		E.cy -= 1
	}
}

/*** file i/o ***/
editor_open :: proc(filename: string) {
	E.filename = filename

	data, ok := os.read_entire_file(filename)
	if !ok {
		// could not read file
		return
	}
	defer delete(data)

	it := string(data)
	for line in strings.split_lines_iterator(&it) {
		editor_insert_row(E.numrows, line)
	}
	E.dirty = 0
}

editor_save :: proc() {
	if E.filename == "" {
		E.filename = editor_prompt("Save as: %s (ESC to cancel)")
		if (E.filename == "") {
			editor_set_status_message("Save aborted")
			return
		}
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	for row in E.row {
		strings.write_string(&builder, row.chars)
		strings.write_string(&builder, "\n")
	}

	content := strings.to_string(builder)
	if os.write_entire_file(E.filename, transmute([]u8)content) {
		E.dirty = 0
		editor_set_status_message("%d bytes written to disk", len(content))
	} else {
		editor_set_status_message("Can't save! I/O error: %s", os.get_last_error_string())
	}
}

/*** output ***/

write_bytes :: proc(bytes: []u8) -> c.ssize_t {
	return posix.write(posix.STDOUT_FILENO, &bytes[0], len(bytes))
}

editor_scroll :: proc() {
	if E.cy < E.numrows {
		E.rx = editor_row_cx_to_rx(&E.row[E.cy], E.cx)
	}

	if E.cy < E.rowoff {
		E.rowoff = E.cy
	}
	if E.cy >= E.rowoff + E.screenrows {
		E.rowoff = E.cy - E.screenrows + 1
	}
	if E.rx < E.coloff {
		E.coloff = E.rx
	}
	if E.rx >= E.coloff + E.screencols {
		E.coloff = E.rx - E.screencols + 1
	}
}

editor_draw_rows :: proc(ab: ^[dynamic]byte) {
	for y := 0; y < E.screenrows; y += 1 {
		filerow := y + E.rowoff
		if filerow >= E.numrows {
			if E.numrows == 0 && y == E.screenrows / 3 {
				welcome := fmt.aprintf("Kilo editor -- version %s", KILO_VERSION)
				padding := (E.screencols - len(welcome)) / 2
				if padding > 0 {
					append(ab, "~")
					padding -= 1
				}
				for ; padding > 0; padding -= 1 {append(ab, " ")}
				append(ab, ..transmute([]u8)welcome)
			} else {
				append(ab, '~')
			}
		} else {
			len := len(E.row[filerow].render) - E.coloff
			if len < 0 {len = 0}
			if len > E.screencols {len = E.screencols}
			append(ab, ..transmute([]u8)E.row[filerow].render[E.coloff:E.coloff + len])
		}

		append(ab, 0x1b, '[', 'K')
		append(ab, '\r', '\n')
	}
}

editor_draw_status_bar :: proc(ab: ^[dynamic]byte) {
	append(ab, 0x1b, '[', '7', 'm')

	status := make([]byte, 80)
	rstatus := make([]byte, 80)
	defer delete(status)
	defer delete(rstatus)
	slen := len(
		fmt.bprintf(
			status,
			"%.20s - %d lines %s",
			E.filename != "" ? E.filename : "[No Name]",
			E.numrows,
			E.dirty > 0 ? "(modified)" : "",
		),
	)
	rlen := len(fmt.bprintf(rstatus, "%d/%d", E.cy + 1, E.numrows))
	if slen > E.screencols {slen = E.screencols}
	append(ab, ..status[:slen])

	for slen < E.screencols {
		if E.screencols - slen == rlen {
			append(ab, ..rstatus[:rlen])
			break
		} else {
			append(ab, " ")
			slen += 1
		}
	}

	append(ab, 0x1b, '[', 'm')
	append(ab, '\r', '\n')
}

editor_draw_message_bar :: proc(ab: ^[dynamic]byte) {
	append(ab, 0x1b, '[', 'K')
	msglen := len(E.statusmsg)
	if msglen > E.screencols {msglen = E.screencols}
	if msglen > 0 && time.time_to_unix(time.now()) - E.statusmsg_time < 5 {
		append(ab, ..transmute([]u8)E.statusmsg[:msglen])
	}
}

editor_refresh_screen :: proc() {
	editor_scroll()

	ab: [dynamic]byte
	defer delete(ab)

	append(&ab, 0x1b, '[', '?', '2', '5', 'l')
	append(&ab, 0x1b, '[', 'H')

	editor_draw_rows(&ab)
	editor_draw_status_bar(&ab)
	editor_draw_message_bar(&ab)

	buf := make([]byte, 32)
	defer delete(buf)
	fmt.bprintf(buf, "\x1b[%d;%dH", E.cy - E.rowoff + 1, E.rx - E.coloff + 1)
	append(&ab, ..buf)

	append(&ab, 0x1b, '[', '?', '2', '5', 'h')

	write_bytes(ab[:])
}

editor_set_status_message :: proc(sfmt: string, args: ..any) {
	E.statusmsg = fmt.tprintf(sfmt, ..args)
	E.statusmsg_time = time.time_to_unix(time.now())
}

/*** input ***/

editor_prompt :: proc(prompt: string) -> string {
	builder := strings.builder_make()
	// defer strings.builder_destroy(&builder)

	for {
		editor_set_status_message(prompt, strings.to_string(builder))
		editor_refresh_screen()
		c := editor_read_key()
		if c == rune(Editor_Key.DEL_KEY) || c == CTRL_KEY('h') || c == rune(Editor_Key.BACKSPACE) {
			strings.pop_rune(&builder)
		} else if c == '\x1b' {
			editor_set_status_message("")
			return ""
		} else if c == '\r' {
			if strings.builder_len(builder) != 0 {
				editor_set_status_message("")
				return strings.to_string(builder)
			}
		} else if !unicode.is_control(c) && c < 128 {
			strings.write_rune(&builder, c)
		}
	}
}

editor_move_cursor :: proc(key: rune) {
	row: Maybe(string) = E.cy >= E.numrows ? nil : E.row[E.cy].chars

	switch key {
	case rune(Editor_Key.ARROW_LEFT):
		if E.cx != 0 {
			E.cx -= 1
		} else if E.cy > 0 {
			E.cy -= 1
			E.cx = len(E.row[E.cy].chars)
		}
	case rune(Editor_Key.ARROW_RIGHT):
		value, ok := row.?
		if ok && E.cx < len(value) {
			E.cx += 1
		} else if ok && E.cx == len(value) {
			E.cy += 1
			E.cx = 0
		}
	case rune(Editor_Key.ARROW_UP):
		if E.cy != 0 {
			E.cy -= 1
		}
	case rune(Editor_Key.ARROW_DOWN):
		if E.cy < E.numrows {
			E.cy += 1
		}
	}

	rowlen := E.cy >= E.numrows ? 0 : len(E.row[E.cy].chars)
	if E.cx > rowlen {
		E.cx = rowlen
	}
}

editor_process_keypress :: proc() -> bool {
	@(static) quit_times := KILO_QUIT_TIMES
	c := editor_read_key()

	switch c {
	case '\r':
		editor_insert_newline()
	case CTRL_KEY('q'):
		if E.dirty > 0 && quit_times > 0 {
			editor_set_status_message(
				"WARNING!!! File has unsaved changes. Press Ctrl-Q %d more times to quit.",
				quit_times,
			)
			quit_times -= 1
			return true
		} else {
			write_bytes([]u8{0x1b, '[', '2', 'J'})
			write_bytes([]u8{0x1b, '[', 'H'})
			return false
		}
	case CTRL_KEY('s'):
		editor_save()

	case rune(Editor_Key.HOME_KEY):
		E.cx = 0
	case rune(Editor_Key.END_KEY):
		if E.cy < E.numrows {
			E.cx = len(E.row[E.cy].chars)
		}

	case rune(Editor_Key.BACKSPACE), CTRL_KEY('h'), rune(Editor_Key.DEL_KEY):
		if c == rune(Editor_Key.DEL_KEY) {editor_move_cursor(rune(Editor_Key.ARROW_RIGHT))}
		editor_del_char()

	case rune(Editor_Key.PAGE_UP), rune(Editor_Key.PAGE_DOWN):
		if c == rune(Editor_Key.PAGE_UP) {
			E.cy = E.rowoff
		} else if c == rune(Editor_Key.PAGE_DOWN) {
			E.cy = E.rowoff + E.screenrows - 1
			if E.cy > E.numrows {E.cy = E.numrows}
		}

		for times := E.screenrows; times > 0; times -= 1 {
			editor_move_cursor(
				c == rune(Editor_Key.PAGE_UP) ? rune(Editor_Key.ARROW_UP) : rune(Editor_Key.ARROW_DOWN),
			)
		}
	case rune(Editor_Key.ARROW_LEFT),
	     rune(Editor_Key.ARROW_RIGHT),
	     rune(Editor_Key.ARROW_UP),
	     rune(Editor_Key.ARROW_DOWN):
		editor_move_cursor(c)

	case CTRL_KEY('l'), 0x1b:
		break

	case:
		editor_insert_char(c)
	}

	quit_times = KILO_QUIT_TIMES
	return true
}

/*** init ***/
init_editor :: proc() {
	if get_window_size(&E.screenrows, &E.screencols) == -1 {die("getWindowSize")}
	E.screenrows -= 2
}

main :: proc() {
	enable_raw_mode()
	defer disable_raw_mode()

	init_editor()
	if len(os.args) > 1 {
		editor_open(os.args[1])
	}

	editor_set_status_message("HELP: Ctrl-S = save | Ctrl-Q = quit")

	for {
		editor_refresh_screen()
		if !editor_process_keypress() {
			break
		}
	}
}
