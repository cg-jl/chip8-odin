package cheight

import "core:fmt"
import "core:io"

clear_screen :: proc() {
	save_cursor()
	defer restore_cursor()
	fmt.print("\x1b[2J", flush = true)
}

save_cursor :: proc() {
	fmt.print("\x1b[s", flush = true)
}

restore_cursor :: proc() {
	fmt.print("\x1b[u", flush = true)
}

disable_reporting_focus :: proc() {
	fmt.print("\x1b[1004l", flush = true)
}

hide_cursor :: proc() {
	fmt.print("\x1b[?25l", flush = true)
}

show_cursor :: proc() {
	fmt.print("\x1b[?25h", flush = true)
}
