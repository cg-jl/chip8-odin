//+build linux
package cheight

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"


termios :: struct {
	// Input mode flags
	c_iflag:  tcflag_t,
	// Output mode flags
	c_oflag:  tcflag_t,
	// Control mode flags
	c_cflag:  tcflag_t,
	// Local mode flags
	c_lflag:  tcflag_t,
	// Line discipline
	c_line:   cc_t,
	// Control characters
	c_cc:     [32]cc_t, // :: [NCCS]int
	// Input speed
	c_ispeed: speed_t,
	c_ospeed: speed_t,
}

foreign import term "system:c"

foreign term {
	tcgetattr :: proc "c" (fd: c.int, termios: ^termios) -> c.int ---
	tcsetattr :: proc "c" (fd: c.int, optional_actions: c.int, termios: ^termios) -> c.int ---
	cfmakeraw :: proc "c" (termios: ^termios) ---
	fcntl :: proc "c" (fd: c.int, option: c.int, arg: c.int) -> c.int ---
}

curr_termios: termios

init_raw_mode :: proc() {
	if tcgetattr(0, &curr_termios) != 0 {
		fmt.printf("tcgetattr: %s\n", cstring(libc.strerror(libc.errno()^)))
		panic("got error from tcgetattr")
	}
	new_termios := curr_termios
	cfmakeraw(&new_termios)
	if tcsetattr(0, TCSANOW, &new_termios) != 0 {
		fmt.printf("tcsetattr: %s\n", cstring(libc.strerror(libc.errno()^)))
		panic("got error from tcsetattr")
	}
}

end_raw_mode :: proc() {
	libc.errno()^ = 0
	if tcsetattr(0, TCSANOW, &curr_termios) != 0 {
		fmt.printf("tcsetattr: %s\n", cstring(libc.strerror(libc.errno()^)))
		panic("got errno from tcsetattr")
	}

}

set_nonblocking :: proc(fd: c.int) -> (err: c.int) {
	err = 0
	F_GETFL: c.int = 3
	F_SETFL: c.int = 4
	flags: c.int
	flags = fcntl(fd, F_GETFL, 0)
	if flags == -1 {
		err = libc.errno()^
		return
	}
	if fcntl(fd, F_SETFL, flags | os.O_NONBLOCK) == -1 {
		err = libc.errno()^
	}
	return

}


TCSANOW: c.int = 0
TCSAFLUSH: c.int = 2

tcflag_t :: c.uint
cc_t :: c.uchar
speed_t :: c.uint
