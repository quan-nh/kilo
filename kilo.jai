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
  quit: bool;
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
    disable_raw_mode(); // Restore terminal first!
    
    write(STDOUT_FILENO, "\x1b[2J".data, 4);
    write(STDOUT_FILENO, "\x1b[H".data, 3);

    // In Jai, we use temp_c_string to convert a Jai string
    // to a null-terminated *u8 for C functions like perror.
    perror(temp_c_string(s));
    exit(1);
}

disable_raw_mode :: () {
  tcsetattr(STDIN_FILENO, TCSAFLUSH, *E.orig_termios);
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

get_cursor_position :: (rows: *int, cols: *int) -> int {
  buf: [32] u8;
  i: u32 = 0;
  
  if write(STDOUT_FILENO, "\x1b[6n".data, 4) != 4 return -1;
  
  while i < buf.count - 1 {
    if read(STDIN_FILENO, *buf[i], 1) != 1 break;
    if buf[i] == #char "R" break;
    i += 1;
  }
  buf[i] = 0;
      
  if buf[0] != 0x1b || buf[1] != #char "[" return -1;
  if sscanf(*buf[2], "%d;%d", rows, cols) != 2 return -1;
  
  return 0;
}

get_window_size :: (rows: *int, cols: *int) -> int {
    ws: winsize;

    // TIOCGWINSZ constant varies by platform.
    // Linux: 0x5413
    // macOS: 0x40087468
    TIOCGWINSZ : u64 : #ifx OS == .MACOS then 0x40087468 else 0x5413;
    
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, *ws) == -1 || ws.ws_col == 0 {
      if write(STDOUT_FILENO, "\x1b[999C\x1b[999B".data, 12) != 12 return -1;
      return get_cursor_position(rows, cols);
      
    } else {
      cols.* = cast(int) ws.ws_col;
      rows.* = cast(int) ws.ws_row;
      return 0;
    }
}

/*** output ***/

editor_draw_rows :: (builder: *String_Builder) {
  for y: 0..E.screenrows-1 {
    append(builder, "~");
    
    if y < E.screenrows - 1 {
      append(builder, "\x1b[K");
      append(builder, "\r\n");
    }
  }
}

editor_refresh_screen :: () {
  builder: String_Builder;  
  
  append(*builder, "\x1b[?25l");
  append(*builder, "\x1b[H");

  editor_draw_rows(*builder);
  
  append(*builder, "\x1b[H");
  append(*builder, "\x1b[?25h");
  
  // Convert builder to a string and write it to stdout
  final_string := builder_to_string(*builder);
  defer free(final_string); // Remember to free the allocated string!
  
  write(STDOUT_FILENO, final_string.data, cast(u64) final_string.count);
}

/*** input ***/

editor_process_keypress :: () {
    c := editor_read_key();

    if c == {
        case #run CTRL_KEY(#char "q");
          write(STDOUT_FILENO, "\x1b[2J".data, 4);
          write(STDOUT_FILENO, "\x1b[H".data, 3);
          E.quit = true;
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

    while !E.quit {
        editor_refresh_screen();
        editor_process_keypress();
    }
}
