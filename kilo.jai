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
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 1;
    
    tcsetattr(STDIN_FILENO, TCSAFLUSH, *raw);
}

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();

    while true {
        c: u8 = 0;
            
        // read(fd, buffer_ptr, count)
        read(STDIN_FILENO, *c, 1);
    
        // iscntrl(c) check (0-31 and 127)
        if c < 32 || c == 127 {
            print("%\r\n", c);
        } else {
            // Jai's print treats u8 as a number. 
            // to_string(*c, 1) creates a string view to print it as a character.
            char_str := to_string(*c, 1);
            print("% ('%')\r\n", c, char_str);
        }
    
        if c == #char "q" break;
    }
}
