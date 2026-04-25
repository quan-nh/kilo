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

editor_read_key :: () -> u8 {
  nread: int;
  c: u8;
  while true {
    nread = read(STDIN_FILENO, *c, 1);
    if nread == 1 break;
    if nread == -1 && errno() != EAGAIN die("read");
  }
  return c;
}

/*** input ***/

editor_process_keypress :: () {
    c := editor_read_key();

    if c == {
        case #run CTRL_KEY(#char "q");
            exit(0);
    }
}

/*** init ***/

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();

    while true {
        editor_process_keypress();
    }
}
