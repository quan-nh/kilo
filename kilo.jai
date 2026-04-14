#import "Basic";
#import "POSIX";
#load "termios_bindings.jai";

orig_termios: termios;

disable_raw_mode :: () {
  tcsetattr(STDIN_FILENO, TCSAFLUSH, *orig_termios);
}

enable_raw_mode :: () {
    tcgetattr(STDIN_FILENO, *orig_termios);
    
    raw := orig_termios;
    raw.c_lflag &= ~(ECHO);
    
    tcsetattr(STDIN_FILENO, TCSAFLUSH, *raw);
}

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();

    c: u8;
    while read(STDIN_FILENO, *c, 1) == 1 && c != #char "q" {
        // Just reading
    }
}
