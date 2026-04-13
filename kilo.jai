#import "Basic";
#import "POSIX";
#load "termios_bindings.jai";

enableRawMode :: () {
    raw: termios;
    tcgetattr(STDIN_FILENO, *raw);
    raw.c_lflag &= ~(ECHO);
    tcsetattr(STDIN_FILENO, TCSAFLUSH, *raw);
}

main :: () {
    enableRawMode();

    c: u8;
    while read(STDIN_FILENO, *c, 1) == 1 && c != #char "q" {
        // Just reading
    }
}
