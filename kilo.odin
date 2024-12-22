package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:sys/posix"
import "core:unicode"

/*** defines ***/

CTRL_KEY :: proc(k: rune) -> rune {
	return rune(byte(k) & 0x1f)
}

/*** data ***/

editor_config :: struct {
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

editor_read_key :: proc(reader: ^bufio.Reader) -> rune {
	char, _, err := bufio.reader_read_rune(reader)
	if err == .EOF {
		return 0
	} else if err != .None {
		die("read")
	}
	return char
}

/*** output ***/

write_bytes :: proc(bytes: []u8) {
	posix.write(posix.STDOUT_FILENO, &bytes[0], len(bytes))
}

editor_draw_rows :: proc() {
	for y := 0; y < 24; y += 1 {
		write_bytes([]u8{'~', '\r', '\n'})
	}
}

editor_refresh_screen :: proc() {
	write_bytes([]u8{0x1b, '[', '2', 'J'})
	write_bytes([]u8{0x1b, '[', 'H'})

	editor_draw_rows()

	write_bytes([]u8{0x1b, '[', 'H'})
}

/*** input ***/

editor_process_keypress :: proc(reader: ^bufio.Reader) -> bool {
	c := editor_read_key(reader)

	// if (unicode.is_control(c)) {
	// 	fmt.printf("%d\r\n", c)
	// } else {
	// 	fmt.printf("%d ('%c')\r\n", c, c)
	// }

	switch c {
	case CTRL_KEY('q'):
		editor_refresh_screen()
		return false
	}
	return true
}

/*** init ***/

main :: proc() {
	enable_raw_mode()
	defer disable_raw_mode()

	reader: bufio.Reader
	bufio.reader_init(&reader, os.stream_from_handle(os.stdin))
	defer bufio.reader_destroy(&reader)

	for {
		editor_refresh_screen()
		if !editor_process_keypress(&reader) {
			break
		}
	}
}
