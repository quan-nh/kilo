#import "Basic";
#import "POSIX";
#import "File";
#import "String";
System :: #import "System";
#load "termios_bindings.jai";

/*** defines ***/

KILO_VERSION :: "0.0.1";
KILO_TAB_STOP :: 8;

CTRL_KEY :: inline (k: u8) -> u8 {
    return k & 0x1f;
}

editor_key :: enum {
    BACKSPACE :: 127;
    ARROW_LEFT  :: 1000;
    ARROW_RIGHT;
    ARROW_UP;
    ARROW_DOWN;
    DEL_KEY;
    HOME_KEY;
    END_KEY;
    PAGE_UP;
    PAGE_DOWN;
}
using editor_key;

/*** data ***/

erow :: struct {
    chars: string;
    render: string;
}

editor_config :: struct {
    cx, cy: int;
    rx: int;
    rowoff: int;
    coloff: int;
    screenrows: int;
    screencols: int;
    numrows: int;
    rows: [..]erow;
    filename: string;
    statusmsg: string;
    statusmsg_time: time_t;
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

editor_read_key :: () -> int {
    nread: int;
    c: u8;
    while true {
        nread = read(STDIN_FILENO, *c, 1);
        if nread == 1 break;
        if nread == -1 && errno() != EAGAIN die("read");
    }

    if c == 0x1b {
        seq: [3]u8;

        if read(STDIN_FILENO, *seq[0], 1) != 1 return 0x1b;
        if read(STDIN_FILENO, *seq[1], 1) != 1 return 0x1b;

        if seq[0] == #char "[" {
            if seq[1] >= #char "0" && seq[1] <= #char "9" {
                if read(STDIN_FILENO, *seq[2], 1) != 1 return 0x1b;
                if seq[2] == #char "~" {
                    if seq[1] == {
                        case #char "1"; return cast(int) HOME_KEY;
                        case #char "3"; return cast(int) DEL_KEY;
                        case #char "4"; return cast(int) END_KEY;
                        case #char "5"; return cast(int) PAGE_UP;
                        case #char "6"; return cast(int) PAGE_DOWN;
                        case #char "7"; return cast(int) HOME_KEY;
                        case #char "8"; return cast(int) END_KEY;
                    }
                }
            } else {
                if seq[1] == {
                    case #char "A"; return cast(int) ARROW_UP;
                    case #char "B"; return cast(int) ARROW_DOWN;
                    case #char "C"; return cast(int) ARROW_RIGHT;
                    case #char "D"; return cast(int) ARROW_LEFT;
                    case #char "H"; return cast(int) HOME_KEY;
                    case #char "F"; return cast(int) END_KEY;
                }
            }
        } else if seq[0] == #char "O" {
            if seq[1] == {
                case #char "H"; return cast(int) HOME_KEY;
                case #char "F"; return cast(int) END_KEY;
            }
        }

        return 0x1b;
    } else {
        return c;
    }
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

/*** row operations ***/

editor_insert_char :: (c: int) {
    if E.cy == E.rows.count {
        editor_append_row("");
        E.numrows = E.rows.count;
    }
    editor_row_insert_char(*E.rows[E.cy], E.cx, c);
    E.cx += 1;
}

editor_row_cx_to_rx :: (row: *erow, cx: int) -> int {
    rx := 0;
    for j: 0..cx-1 {
        if row.chars[j] == #char "\t" {
            rx += (KILO_TAB_STOP - 1) - (rx % KILO_TAB_STOP);
        }
        rx += 1;
    }
    return rx;
}

editor_update_row :: (row: *erow) {
    builder: String_Builder;

    idx := 0;
    for i: 0..row.chars.count-1 {
        if row.chars[i] == #char "\t" {
            append(*builder, " ");
            idx += 1;
            while idx % KILO_TAB_STOP != 0 {
                append(*builder, " ");
                idx += 1;
            }
        } else {
            append(*builder, row.chars[i]);
            idx += 1;
        }
    }

    // Free old render if it exists
    if row.render.data free(row.render.data);
    row.render = builder_to_string(*builder);
}

editor_append_row :: (s: string) {
	row := erow.{chars = s};
	editor_update_row(*row);
	array_add(*E.rows, row);
}

editor_row_insert_char :: (row: *erow, at: int, c: int) {
    if at < 0 || at > row.chars.count then at = row.chars.count;

    row.chars.data = realloc(row.chars.data, row.chars.count + 2, row.chars.count);

    // Shift characters using a while loop (downwards to avoid overwriting)
    i := row.chars.count;
    while i > at {
        row.chars.data[i] = row.chars.data[i-1];
        i -= 1;
    }

    row.chars.data[at] = cast(u8) c;
    row.chars.count += 1;
    row.chars.data[row.chars.count] = 0; // Null terminator for C-interop safety

    editor_update_row(row);
}

/*** file i/o ***/

editor_rows_to_string :: () -> string {
    builder: String_Builder;
    for 0..E.numrows-1 {
        append(*builder, E.rows[it].chars);
        append(*builder, "\n");
    }
    return builder_to_string(*builder);
}

editor_open :: (filename: string) {
    E.filename = filename;
    content, success := read_entire_file(filename);
    if !success die("read_entire_file");
    defer free(content);

    // Split the content into lines
    lines := split(content, "\n");

    for * line: lines {
        // Remove trailing \r if it exists
        if line.count > 0 && line.*[line.count - 1] == #char "\r" {
            line.count -= 1;
        }

        // Add to our rows array
        editor_append_row(copy_string(line.*));
    }

    E.numrows = E.rows.count;
}

editor_save :: () {
    if !E.filename return;

    buf := editor_rows_to_string();
    defer free(buf);

    success := write_entire_file(E.filename, buf);
    if success {
        editor_set_status_message("% bytes written to disk", buf.count);
    } else {
        editor_set_status_message("Can't save! I/O error: %", System.get_error_string(errno()));
    }
}

/*** output ***/

editor_scroll :: () {
    E.rx = E.cx;
    if E.cy < E.numrows {
        E.rx = editor_row_cx_to_rx(*E.rows[E.cy], E.cx);
    }

    if E.cy < E.rowoff {
        E.rowoff = E.cy;
    }
    if E.cy >= E.rowoff + E.screenrows {
        E.rowoff = E.cy - E.screenrows + 1;
    }
    if E.rx < E.coloff {
        E.coloff = E.rx;
    }
    if E.rx >= E.coloff + E.screencols {
        E.coloff = E.rx - E.screencols + 1;
    }
}

editor_draw_rows :: (builder: *String_Builder) {
    for y: 0..E.screenrows-1 {
        filerow := y + E.rowoff;
        if filerow >= E.numrows {
            if E.numrows == 0 && y == E.screenrows / 3 {
                welcome := tprint("Kilo editor -- version %", KILO_VERSION);
                if welcome.count > E.screencols welcome.count = E.screencols;

                // Calculate padding for centering
                padding := (E.screencols - welcome.count) / 2;
                if padding {
                    append(builder, "~");
                    padding -= 1;
                }
                while padding > 0 {
                    append(builder, " ");
                    padding -= 1;
                }

                append(builder, welcome);
            } else {
                append(builder, "~");
            }
        } else {
            len := E.rows[filerow].render.count - E.coloff;
            if len < 0 len = 0;
            if len > E.screencols len = E.screencols;

            append(builder, string.{len, E.rows[filerow].render.data + E.coloff});
        }

        append(builder, "\x1b[K");
        append(builder, "\r\n");
    }
}

editor_draw_status_bar :: (builder: *String_Builder) {
    append(builder, "\x1b[7m");

    filename := ifx E.filename then E.filename else "[No Name]";
    display_filename := filename;
    if display_filename.count > 20 display_filename.count = 20;

    status := tprint("% - % lines", display_filename, E.numrows);
    if status.count > E.screencols status.count = E.screencols;
    append(builder, status);

    rstatus := tprint("%/%", E.cy + 1, E.numrows);

    len := status.count;
    while len < E.screencols {
        if E.screencols - len == rstatus.count {
            append(builder, rstatus);
            break;
        } else {
            append(builder, " ");
            len += 1;
        }
    }

    append(builder, "\x1b[m");
    append(builder, "\r\n");
}

editor_draw_message_bar :: (builder: *String_Builder) {
    append(builder, "\x1b[K");

    msg := E.statusmsg;
    if msg.count > E.screencols msg.count = E.screencols;

    if msg.count && time(null) - E.statusmsg_time < 5 {
        append(builder, msg);
    }
}

editor_refresh_screen :: () {
    editor_scroll();

    builder: String_Builder;

    append(*builder, "\x1b[?25l");
    append(*builder, "\x1b[H");

    editor_draw_rows(*builder);
    editor_draw_status_bar(*builder);
    editor_draw_message_bar(*builder);

    print_to_builder(*builder, "\x1b[%;%H", E.cy - E.rowoff + 1, E.rx - E.coloff + 1);

    append(*builder, "\x1b[?25h");

    // Convert builder to a string and write it to stdout
    final_string := builder_to_string(*builder);
    defer free(final_string); // Remember to free the allocated string!

    write(STDOUT_FILENO, final_string.data, cast(u64) final_string.count);
}

editor_set_status_message :: (fmt: string, args: ..Any) {
    if E.statusmsg.data free(E.statusmsg);

    formatted := tprint(fmt, ..args);
    E.statusmsg = copy_string(formatted);
    E.statusmsg_time = time(null);
}

/*** input ***/

editor_move_cursor :: (key: editor_key) {
    row: *erow = ifx E.cy >= E.numrows then null else *E.rows[E.cy];

    if key == {
        case .ARROW_LEFT;
            if E.cx != 0 {
                E.cx -= 1;
            } else if (E.cy > 0) {
                E.cy -= 1;
                E.cx = E.rows[E.cy].chars.count;
            }
        case .ARROW_RIGHT;
            if row && E.cx < row.chars.count {
                E.cx += 1;
            } else if row && E.cx == row.chars.count {
                E.cy += 1;
                E.cx = 0;
            }
        case .ARROW_UP;
            if E.cy != 0 {E.cy -= 1;}
        case .ARROW_DOWN;
            if E.cy < E.numrows {E.cy += 1;}
    }

    row = ifx E.cy >= E.numrows then null else *E.rows[E.cy];
    rowlen := ifx row then row.chars.count else 0;
    if E.cx > rowlen {
        E.cx = rowlen;
    }
}

editor_process_keypress :: () {
    c := editor_read_key();

    if c == {
        case #char "\r";
            /* TODO */

        case #run CTRL_KEY(#char "q");
            write(STDOUT_FILENO, "\x1b[2J".data, 4);
            write(STDOUT_FILENO, "\x1b[H".data, 3);
            E.quit = true;

        case #run CTRL_KEY(#char "s");
            editor_save();

        case cast(int) HOME_KEY;
            E.cx = 0;

        case cast(int) END_KEY;
            if E.cy < E.numrows
                E.cx = E.rows[E.cy].chars.count;

        case cast(int) BACKSPACE;     #through;
        case #run CTRL_KEY(#char "h"); #through;
        case cast(int) DEL_KEY;
            /* TODO */

        case cast(int) PAGE_UP;   #through;
        case cast(int) PAGE_DOWN;
            if c == cast(int) PAGE_UP {
                E.cy = E.rowoff;
            } else if c == cast(int) PAGE_DOWN {
                E.cy = E.rowoff + E.screenrows - 1;
                if (E.cy > E.numrows) E.cy = E.numrows;
            }

            for 1..E.screenrows {
                key_to_move := ifx c == cast(int) PAGE_UP then ARROW_UP else ARROW_DOWN;
                editor_move_cursor(key_to_move);
            }

        case cast(int) ARROW_UP;   #through;
        case cast(int) ARROW_DOWN; #through;
        case cast(int) ARROW_LEFT; #through;
        case cast(int) ARROW_RIGHT;
            editor_move_cursor(cast(editor_key) c);

        case #run CTRL_KEY(#char "l"); #through;
        case 0x1b;
            // Nothing.

        case;
            editor_insert_char(c);
    }
}

/*** init ***/

init_editor :: () {
    if get_window_size(*E.screenrows, *E.screencols) == -1 die("getWindowSize");
    E.screenrows -= 2;
}

main :: () {
    args := get_command_line_arguments();

    enable_raw_mode();
    defer disable_raw_mode();

    init_editor();

    // args[0] is always the program name (e.g., "./kilo")
    if args.count > 1 {
        editor_open(args[1]);
    }

    editor_set_status_message("HELP: Ctrl-S = save | Ctrl-Q = quit");

    while !E.quit {
        editor_refresh_screen();
        editor_process_keypress();
    }

    if E.statusmsg.data free(E.statusmsg);
}

