package main

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:sys/posix"
import "core:unicode"

/*** defines ***/
KILO_VERSION :: "0.0.1"

CTRL_KEY :: proc(k: rune) -> rune {
	return rune(byte(k) & 0x1f)
}

Editor_Key :: enum {
	ARROW_LEFT = 1000,
	ARROW_RIGHT,
	ARROW_UP,
	ARROW_DOWN,
	PAGE_UP,
	PAGE_DOWN,
}
/*** data ***/

editor_config :: struct {
	cx:           int,
	cy:           int,
	screenrows:   int,
	screencols:   int,
	orig_termios: posix.termios,
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
	_, err := os.read(os.stdin, c[:])
	if err == .EOF {
		return 0
	} else if err != 0 {
		die("read")
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
					case '5':
						return rune(Editor_Key.PAGE_UP)
					case '6':
						return rune(Editor_Key.PAGE_DOWN)
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
				}
			}}
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

/*** output ***/

write_bytes :: proc(bytes: []u8) -> c.ssize_t {
	return posix.write(posix.STDOUT_FILENO, &bytes[0], len(bytes))
}

editor_draw_rows :: proc(ab: ^[dynamic]byte) {
	for y := 0; y < E.screenrows; y += 1 {
		if y == E.screenrows / 3 {
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

		append(ab, 0x1b, '[', 'K')
		if y < E.screenrows - 1 {
			append(ab, '\r', '\n')
		}
	}
}

editor_refresh_screen :: proc() {
	ab: [dynamic]byte
	defer delete(ab)

	append(&ab, 0x1b, '[', '?', '2', '5', 'l')
	append(&ab, 0x1b, '[', 'H')

	editor_draw_rows(&ab)

	buf := make([]byte, 32)
	defer delete(buf)
	fmt.bprintf(buf, "\x1b[%d;%dH", E.cy + 1, E.cx + 1)
	append(&ab, ..buf)

	append(&ab, 0x1b, '[', '?', '2', '5', 'h')

	write_bytes(ab[:])
}

/*** input ***/
editor_move_cursor :: proc(key: rune) {
	switch key {
	case rune(Editor_Key.ARROW_LEFT):
		if E.cx != 0 {
			E.cx -= 1
		}
	case rune(Editor_Key.ARROW_RIGHT):
		if E.cx != E.screencols - 1 {
			E.cx += 1
		}
	case rune(Editor_Key.ARROW_UP):
		if E.cy != 0 {
			E.cy -= 1
		}
	case rune(Editor_Key.ARROW_DOWN):
		if E.cy != E.screenrows - 1 {
			E.cy += 1
		}
	}
}

editor_process_keypress :: proc() -> bool {
	c := editor_read_key()

	switch c {
	case CTRL_KEY('q'):
		editor_refresh_screen()
		return false
	case rune(Editor_Key.PAGE_UP), rune(Editor_Key.PAGE_DOWN):
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
	}
	return true
}

/*** init ***/
init_editor :: proc() {
	if get_window_size(&E.screenrows, &E.screencols) == -1 {die("getWindowSize")}
}

main :: proc() {
	enable_raw_mode()
	defer disable_raw_mode()
	init_editor()

	for {
		editor_refresh_screen()
		if !editor_process_keypress() {
			break
		}
	}
}
