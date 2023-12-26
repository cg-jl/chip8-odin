package cheight

import "core:fmt"
import "core:io"
import "core:math/bits"
import "core:os"
import "core:strings"

// 64x32
Buffer :: [32]u64


Display :: struct {
	// using double buffer technique to be able to diff
	buffers:    [2]Buffer,
	// turn = currently ready buffer, turn ~ 1 = back buffer
	turn:       u32,
	// FIXME: separate command buffer from Display to ease migrating
    // to a graphics library like raylib.
	cmd_buffer: strings.Builder,
}

back_buffer :: proc "contextless" (d: ^Display) -> ^Buffer {
	return &d.buffers[d.turn ~ 1]
}

blit :: proc(d: ^Display) {
	defer strings.builder_reset(&d.cmd_buffer)
	// FIXME: dynamic command buffer instead
	// of relying in stdio
	fmt.sbprint(&d.cmd_buffer, "\x1b[1;1H")
	// NOTE: using diff-based rendering, so that we avoid emitting too many
	// commands to stdout.

	new_buf := &d.buffers[d.turn ~ 1]
	old_buf := &d.buffers[d.turn]

	wrote_anything := false
	for line, line_idx in new_buf {
		old := old_buf[line_idx]
		diff := line ~ old

		@(static)
		buf: [2]cstring = {"", "\x1b[48;5;30m"} // blue-ish color

		wrote_anything |= diff != 0

		for ; diff != 0; diff &= diff - 1 {
			next_bit := u32(bits.count_trailing_zeros(diff))
			// NOTE: trailing_zeros counts from LSB, which is from the rightmost
			// pixel. ANSI cursor is 1-based.
			next_pos := 64 - next_bit
			lane_bit := (line >> next_bit) & 1
			fmt.sbprintf(
				&d.cmd_buffer,
				"\x1b[%v;%vH%s \x1b[m",
				line_idx + 1,
				next_pos,
				buf[lane_bit],
			)
		}
	}


	// NOTE: since we're changing turns, make the old buffer have the same
	// contents, so that the client doesn't have to take into account the
	// diff-based technique and can still use Display as the exact state of the
	// pixels on screen.
	old_buf^ = new_buf^
	d.turn = d.turn ~ 1

	if wrote_anything {

		io.write(os.stream_from_handle(os.stdout), d.cmd_buffer.buf[:])
	}


}
