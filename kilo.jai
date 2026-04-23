#import "Basic";
#import "POSIX";
#load "termios_bindings.jai";

/*** defines ***/

CTRL_KEY :: inline (k: u8) -> u8 {
    return k & 0x1f;
}

/*** data ***/

orig_termios: termios;

/*** terminal ***/

die :: (s: string) {
    // In Jai, we use temp_c_string to convert a Jai string 
    // to a null-terminated *u8 for C functions like perror.
    perror(temp_c_string(s));
    exit(1);
}

disable_raw_mode :: () {
  if tcsetattr(STDIN_FILENO, TCSAFLUSH, *orig_termios) == -1
    die("tcsetattr");
}

enable_raw_mode :: () {
    if tcgetattr(STDIN_FILENO, *orig_termios) == -1 die("tcgetattr");
    
    raw := orig_termios;
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_cflag |= (CS8);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 1;
    
    if tcsetattr(STDIN_FILENO, TCSAFLUSH, *raw) == -1 die("tcgetattr");
}

/*** init ***/

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();

    while true {
        c: u8 = 0;
            
        // read(fd, buffer_ptr, count)
        if read(STDIN_FILENO, *c, 1) == -1 && errno() != EAGAIN die("read");
    
        // iscntrl(c) check (0-31 and 127)
        if c < 32 || c == 127 {
            print("%\r\n", c);
        } else {
            // Jai's print treats u8 as a number. 
            // to_string(*c, 1) creates a string view to print it as a character.
            char_str := to_string(*c, 1);
            print("% ('%')\r\n", c, char_str);
        }
    
        if c == CTRL_KEY(113) break;
    }
}
