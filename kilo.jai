#import "Basic";
#import "POSIX";
#load "termios_bindings.jai";

/*** defines ***/

CTRL_KEY :: inline (k: u8) -> u8 {
    return k & 0x1f;
}

/*** data ***/

editor_config :: struct {
  screenrows: int;
  screencols: int;
  orig_termios: termios;
};

E: editor_config;

winsize :: struct {
    ws_row:    u16;
    ws_col:    u16;
    ws_xpixel: u16; // unused
    ws_ypixel: u16; // unused
}

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

get_window_size :: (rows: *int, cols: *int) -> s32 {
    ws: winsize;

    // TIOCGWINSZ constant varies by platform.
    // Linux: 0x5413
    // macOS: 0x40087468
    TIOCGWINSZ : u64 : #ifx OS == .MACOS then 0x40087468 else 0x5413;

    if ioctl(STDOUT_FILENO, TIOCGWINSZ, *ws) == -1 || ws.ws_col == 0 {
        return -1;
    }

    cols.* = cast(int) ws.ws_col;
    rows.* = cast(int) ws.ws_row;
    return 0;
}

/*** output ***/

editor_draw_rows :: () {
  for 1..E.screenrows {
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

init_editor :: () {
  if get_window_size(*E.screenrows, *E.screencols) == -1 die("getWindowSize");
}

main :: () {
    enable_raw_mode();
    defer disable_raw_mode();
    init_editor();

    while true {
        editor_refresh_screen();
        editor_process_keypress();
    }
}
