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
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    
    tcsetattr(STDIN_FILENO, TCSAFLUSH, *raw);
}

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();

    c: u8;
    while read(STDIN_FILENO, *c, 1) == 1 && c != #char "q" {
        if c < 32 || c == 127 {
            print("%\r\n", c);
        } else {
            // to_string creates a string view of the u8
            char_str := to_string(*c, 1);
            print("% ('%')\r\n", c, char_str);
        }
    }
}
