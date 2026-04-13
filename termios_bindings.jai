//
// This file was auto-generated using the following command:
//
// jai generate_termios.jai
//



VEOF :: 0;
VEOL :: 1;

VEOL2 :: 2;

VERASE :: 3;

VWERASE :: 4;

VKILL :: 5;

VREPRINT :: 6;

VINTR :: 8;
VQUIT :: 9;
VSUSP :: 10;

VDSUSP :: 11;

VSTART :: 12;
VSTOP :: 13;

VLNEXT :: 14;
VDISCARD :: 15;

VMIN :: 16;
VTIME :: 17;

VSTATUS :: 18;

NCCS :: 20;

IGNBRK :: 0x00000001;
BRKINT :: 0x00000002;
IGNPAR :: 0x00000004;
PARMRK :: 0x00000008;
INPCK :: 0x00000010;
ISTRIP :: 0x00000020;
INLCR :: 0x00000040;
IGNCR :: 0x00000080;
ICRNL :: 0x00000100;
IXON :: 0x00000200;
IXOFF :: 0x00000400;
IXANY :: 0x00000800;

IMAXBEL :: 0x00002000;
IUTF8 :: 0x00004000;

OPOST :: 0x00000001;
ONLCR :: 0x00000002;

OXTABS :: 0x00000004;
ONOEOT :: 0x00000008;

OCRNL :: 0x00000010;
ONOCR :: 0x00000020;
ONLRET :: 0x00000040;
OFILL :: 0x00000080;
NLDLY :: 0x00000300;
TABDLY :: 0x00000c04;
CRDLY :: 0x00003000;
FFDLY :: 0x00004000;
BSDLY :: 0x00008000;
VTDLY :: 0x00010000;
OFDEL :: 0x00020000;

NL0 :: 0x00000000;
NL1 :: 0x00000100;

NL2 :: 0x00000200;
NL3 :: 0x00000300;

TAB0 :: 0x00000000;
TAB1 :: 0x00000400;
TAB2 :: 0x00000800;

TAB3 :: 0x00000004;
CR0 :: 0x00000000;
CR1 :: 0x00001000;
CR2 :: 0x00002000;
CR3 :: 0x00003000;
FF0 :: 0x00000000;
FF1 :: 0x00004000;
BS0 :: 0x00000000;
BS1 :: 0x00008000;
VT0 :: 0x00000000;
VT1 :: 0x00010000;

CIGNORE :: 0x00000001;

CSIZE :: 0x00000300;
CS5 :: 0x00000000;
CS6 :: 0x00000100;
CS7 :: 0x00000200;
CS8 :: 0x00000300;
CSTOPB :: 0x00000400;
CREAD :: 0x00000800;
PARENB :: 0x00001000;
PARODD :: 0x00002000;
HUPCL :: 0x00004000;
CLOCAL :: 0x00008000;

CCTS_OFLOW :: 0x00010000;
CRTSCTS :: CCTS_OFLOW | CRTS_IFLOW;
CRTS_IFLOW :: 0x00020000;
CDTR_IFLOW :: 0x00040000;
CDSR_OFLOW :: 0x00080000;
CCAR_OFLOW :: 0x00100000;
MDMBUF :: 0x00100000;

ECHOKE :: 0x00000001;

ECHOE :: 0x00000002;
ECHOK :: 0x00000004;
ECHO :: 0x00000008;
ECHONL :: 0x00000010;

ECHOPRT :: 0x00000020;
ECHOCTL :: 0x00000040;

ISIG :: 0x00000080;
ICANON :: 0x00000100;

ALTWERASE :: 0x00000200;

IEXTEN :: 0x00000400;

EXTPROC :: 0x00000800;

TOSTOP :: 0x00400000;

FLUSHO :: 0x00800000;
NOKERNINFO :: 0x02000000;
PENDIN :: 0x20000000;

NOFLSH :: 0x80000000;

TCSANOW :: 0;
TCSADRAIN :: 1;
TCSAFLUSH :: 2;

TCSASOFT :: 0x10;

B0 :: 0;
B50 :: 50;
B75 :: 75;
B110 :: 110;
B134 :: 134;
B150 :: 150;
B200 :: 200;
B300 :: 300;
B600 :: 600;
B1200 :: 1200;
B1800 :: 1800;
B2400 :: 2400;
B4800 :: 4800;
B9600 :: 9600;
B19200 :: 19200;
B38400 :: 38400;

B7200 :: 7200;
B14400 :: 14400;
B28800 :: 28800;
B57600 :: 57600;
B76800 :: 76800;
B115200 :: 115200;
B230400 :: 230400;
EXTA :: 19200;
EXTB :: 38400;

TCIFLUSH :: 1;
TCOFLUSH :: 2;
TCIOFLUSH :: 3;
TCOOFF :: 1;
TCOON :: 2;
TCIOFF :: 3;
TCION :: 4;

tcflag_t :: u64;
cc_t :: u8;
speed_t :: u64;

termios :: struct {
    c_iflag:  tcflag_t; /* input flags */
    c_oflag:  tcflag_t; /* output flags */
    c_cflag:  tcflag_t; /* control flags */
    c_lflag:  tcflag_t; /* local flags */
    c_cc:     [20] cc_t; /* control chars */
    c_ispeed: speed_t; /* input speed */
    c_ospeed: speed_t; /* output speed */
}

cfgetispeed :: (unknown0: *termios) -> speed_t #foreign libc;
cfgetospeed :: (unknown0: *termios) -> speed_t #foreign libc;
cfsetispeed :: (unknown0: *termios, unknown1: speed_t) -> s32 #foreign libc;
cfsetospeed :: (unknown0: *termios, unknown1: speed_t) -> s32 #foreign libc;
tcgetattr :: (unknown0: s32, unknown1: *termios) -> s32 #foreign libc;
tcsetattr :: (unknown0: s32, unknown1: s32, unknown2: *termios) -> s32 #foreign libc;
tcdrain :: (unknown0: s32) -> s32 #foreign libc;
tcflow :: (unknown0: s32, unknown1: s32) -> s32 #foreign libc;
tcflush :: (unknown0: s32, unknown1: s32) -> s32 #foreign libc;
tcsendbreak :: (unknown0: s32, unknown1: s32) -> s32 #foreign libc;

cfmakeraw :: (unknown0: *termios) -> void #foreign libc;
cfsetspeed :: (unknown0: *termios, unknown1: speed_t) -> s32 #foreign libc;

#scope_file

#import "Basic"; // For assert

libc :: #library,system "libc";

#run {
    {
        instance: termios;
        assert(((cast(*void)(*instance.c_iflag)) - cast(*void)(*instance)) == 0, "termios.c_iflag has unexpected offset % instead of 0", ((cast(*void)(*instance.c_iflag)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_iflag)) == 8, "termios.c_iflag has unexpected size % instead of 8", size_of(type_of(termios.c_iflag)));
        assert(((cast(*void)(*instance.c_oflag)) - cast(*void)(*instance)) == 8, "termios.c_oflag has unexpected offset % instead of 8", ((cast(*void)(*instance.c_oflag)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_oflag)) == 8, "termios.c_oflag has unexpected size % instead of 8", size_of(type_of(termios.c_oflag)));
        assert(((cast(*void)(*instance.c_cflag)) - cast(*void)(*instance)) == 16, "termios.c_cflag has unexpected offset % instead of 16", ((cast(*void)(*instance.c_cflag)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_cflag)) == 8, "termios.c_cflag has unexpected size % instead of 8", size_of(type_of(termios.c_cflag)));
        assert(((cast(*void)(*instance.c_lflag)) - cast(*void)(*instance)) == 24, "termios.c_lflag has unexpected offset % instead of 24", ((cast(*void)(*instance.c_lflag)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_lflag)) == 8, "termios.c_lflag has unexpected size % instead of 8", size_of(type_of(termios.c_lflag)));
        assert(((cast(*void)(*instance.c_cc)) - cast(*void)(*instance)) == 32, "termios.c_cc has unexpected offset % instead of 32", ((cast(*void)(*instance.c_cc)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_cc)) == 20, "termios.c_cc has unexpected size % instead of 20", size_of(type_of(termios.c_cc)));
        assert(((cast(*void)(*instance.c_ispeed)) - cast(*void)(*instance)) == 56, "termios.c_ispeed has unexpected offset % instead of 56", ((cast(*void)(*instance.c_ispeed)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_ispeed)) == 8, "termios.c_ispeed has unexpected size % instead of 8", size_of(type_of(termios.c_ispeed)));
        assert(((cast(*void)(*instance.c_ospeed)) - cast(*void)(*instance)) == 64, "termios.c_ospeed has unexpected offset % instead of 64", ((cast(*void)(*instance.c_ospeed)) - cast(*void)(*instance)));
        assert(size_of(type_of(termios.c_ospeed)) == 8, "termios.c_ospeed has unexpected size % instead of 8", size_of(type_of(termios.c_ospeed)));
        assert(size_of(termios) == 72, "termios has size % instead of 72", size_of(termios));
    }
}

