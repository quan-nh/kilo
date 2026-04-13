#import "Basic";
#import "POSIX";

main :: () {
    c: u8;
    // read returns s64 (ssize_t). It returns 1 on success, 0 on EOF, and -1 on error.
    while read(STDIN_FILENO, *c, 1) == 1 && c != #char "q" {
        // Loop body (if any)
    }
}