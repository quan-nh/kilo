#import "Basic";
#import "POSIX";
#load "termios_bindings.jai";

/*** defines ***/

CTRL_KEY :: inline (k: u8) -> u8 {
    return k & 0x1f;
}

/*** data ***/

editor_config :: struct {
  orig_termios: termios;
};

E: editor_config;

/*** terminal ***/

die :: (s: string) {
    write(STDOUT_FILENO, "\x1b[2J".data, 4);
    write(STDOUT_FILENO, "\x1b[H".data, 3);

    // In Jai, we use temp_c_string to convert a Jai string
    // to a null-terminated *u8 for C functions like perror.
    perror(temp_c_string(s));
    exit(1);
}

disable_raw_mode :: () {
  if tcsetattr(STDIN_FILENO, TCSAFLUSH, *E.orig_termios) == -1
    die("tcsetattr");
}

enable_raw_mode :: () {
    if tcgetattr(STDIN_FILENO, *E.orig_termios) == -1 die("tcgetattr");

    raw := E.orig_termios;
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

/*** output ***/

editor_draw_rows :: () {
  for 0..23 {
    write(STDOUT_FILENO, "~\r\n".data, 3);
  }
}

editor_refresh_screen :: () {
  write(STDOUT_FILENO, "\x1b[2J".data, 4);
  write(STDOUT_FILENO, "\x1b[H".data, 3);

  editor_draw_rows();
  write(STDOUT_FILENO, "\x1b[H".data, 3);
}

/*** input ***/

editor_process_keypress :: () {
    c := editor_read_key();

    if c == {
        case #run CTRL_KEY(#char "q");
          write(STDOUT_FILENO, "\x1b[2J".data, 4);
          write(STDOUT_FILENO, "\x1b[H".data, 3);
          exit(0);
    }
}

/*** init ***/

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();

    while true {
        editor_refresh_screen();
        editor_process_keypress();
    }
}
