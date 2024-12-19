package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:sys/posix"

orig_termios: posix.termios

disable_raw_mode :: proc() {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &orig_termios)
}

enable_raw_mode :: proc() {
	posix.tcgetattr(posix.STDIN_FILENO, &orig_termios)

	raw := orig_termios
	raw.c_lflag &~= {.ECHO} | {.ICANON}

	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
}

main :: proc() {
	enable_raw_mode()
	defer disable_raw_mode()

	reader: bufio.Reader
	bufio.reader_init(&reader, os.stream_from_handle(os.stdin))
	defer bufio.reader_destroy(&reader)

	for {
		char, size, err := bufio.reader_read_rune(&reader)
		if err != .None || char == 'q' {
			break
		}
		fmt.printf("Read character: %c\n", char)
	}
}
