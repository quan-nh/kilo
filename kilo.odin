package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:sys/posix"
import "core:unicode"

/*** data ***/

orig_termios: posix.termios

/*** terminal ***/

die :: proc(s: string) {
	fmt.panicf("%s: %s\n", s, posix.strerror(posix.errno()))
}

disable_raw_mode :: proc() {
	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &orig_termios) != .OK {
		die("tcsetattr")
	}
}

enable_raw_mode :: proc() {
	if posix.tcgetattr(posix.STDIN_FILENO, &orig_termios) != .OK {
		die("tcgetattr")
	}

	raw := orig_termios
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
	raw.c_cc[.VTIME] = 1

	if posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw) != .OK {
		die("tcsetattr")
	}
}

/*** init ***/

main :: proc() {
	enable_raw_mode()
	defer disable_raw_mode()

	reader: bufio.Reader
	bufio.reader_init(&reader, os.stream_from_handle(os.stdin))
	defer bufio.reader_destroy(&reader)

	for {
		char, _, err := bufio.reader_read_rune(&reader)
		if err == .EOF {
			fmt.println("0\r\n")
		} else if err != .None {
			die("read")
		}

		if (unicode.is_control(char)) {
			fmt.printf("%d\r\n", char)
		} else {
			fmt.printf("%d ('%c')\r\n", char, char)
		}

		if char == 'q' {
			break
		}
	}
}
