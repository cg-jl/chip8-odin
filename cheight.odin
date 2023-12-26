package cheight

import "core:bufio"
import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:time"


main :: proc() {

	fmt.printf("args: %v\n", os.args)
	if len(os.args) != 2 {
		fmt.fprintln(os.stderr, "usage: ./chip8 <file>")
		return
	}


	// TODO: Could read the file directly to the interpreter's memory, although
	// currently this is a one-time event.
	data, ok := os.read_entire_file(os.args[1], context.allocator)
	if !ok {
		fmt.fprintf(os.stderr, "Could not read binary file '%s'\n", os.args[1])
		return
	}



	// NOTE: Using raw mode to be able to get key presses without buffering
	// until newline.
	init_raw_mode()
	defer end_raw_mode()

	// TODO: circular input buffer?
	buffer: [4096]u8
	inp := os.stream_from_handle(0)

	// NOTE: query size of the screen to create our window.
	// make sure we have enough space for blitting.
	// Make sure we do this before setting nonblocking mode as well.
    save_cursor()
	fmt.print("\x1b[1000;1000H\x1b[6n")
	n, _ := io.read(inp, buffer[:])
	if n < 1 {
		fmt.fprintln(os.stderr, "Could not build window: no terminal's response on window size")
	} else {

		// skip over \x1b[
		n_start := 2
		n_end := n_start
		for buffer[n_end] != ';' {
			n_end += 1
		}
		lines := bytes_to_int(buffer[n_start:n_end])
		m_start := n_end + 1
		m_end := m_start
		for buffer[m_end] != 'R' {
			m_end += 1
		}
		columns := bytes_to_int(buffer[m_start:m_end])


		if lines < 32 || columns < 64 {
            restore_cursor()
			fmt.fprintf(
				os.stderr,
				"Not enough space for blitting the display: want at least a 64x32 space (has %vx%v)\n",
                lines, columns
			)
            return
		}

	}


	disable_reporting_focus()
	when MODE != .editor {
		hide_cursor()
	}
	defer when MODE != .editor {show_cursor()}





	// NOTE: Using non-blocking I/O to handle user input only when it's there
	// and still be able to tick our interpreter. Ideally the interpreter runs
	// in a separate thread so it is not affected by I/O.
	// The other modes (debug & screen painter) want to wait for I/O at least to
	// avoid burning CPU cycles without doing anything.
	when MODE == .exec {
		if err := set_nonblocking(0); err != 0 {
			fmt.printf("error when setting nonblocking: %s\n", cstring(libc.strerror(err)))
			panic("could not configure input appropiately")
		}
	}

	display := Display{}
	cpu := Cpu{}
	rng: rand.Rand
	// TODO: could use a random seed when not debugging...
	rand.init(&rng, 0)


	load_code(&cpu, data)


	target_frame_time := 16 * time.Millisecond

	clear_screen()


	cur_x := 1
	cur_y := 1


	insn_sb := strings.Builder{}
	defer strings.builder_destroy(&insn_sb)

	for running {
		frame_dur: time.Duration = ---
		{
			time.SCOPED_TICK_DURATION(&frame_dur)
			// handle input
			n, _ := io.read(inp, buffer[:])


			if n > 0 {
				for i := 0; i != n; {
					when MODE != .editor {
						// FIXME: I don't have press-release information from the terminal, so I'll
						// clear this every loop for now.
						// FIXME: could use a key queue so that the Cpu handling
						// only counts one key at a time. Should be fine for
						// most frames though.
						cpu.key_mask = 0
						interpret_key(&cpu, buffer[i])
					}
					switch buffer[i] {
					case CTRLC:
						running = false
						i += 1

					case ' ':
						when MODE == .debug {
							strings.builder_reset(&insn_sb)
							insn := decode_current_noadvance(&cpu)
							dasm := disassemble(insn, &insn_sb)
							fmt.printf(
								"\x1b[33;H\x1b[2K pc = %x fetched = %04x %s",
								cpu.pc,
								insn,
								dasm,
							)
							fmt.printf("\x1b[34;H\x1b[2K vs = %v", cpu.gp)
							// NOTE: obviously here we don't fulfill the
							// requirement of 60Hz but for debugging we're
							// stepping each frame.
							tick_60Hz(&cpu, &display, &rng)

						}
						i += 1
					case 27:
						when MODE == .editor {
							i += 1
							if i != n {
								if buffer[i] == 91 {
									i += 1
									if i != n {
										switch buffer[i] {
										case UP_ARROW:
											if cur_y != 1 {
												cur_y -= 1
												fmt.printf("\x1b[A")
											}
										case DOWN_ARROW:
											if cur_y != 32 {
												cur_y += 1
												fmt.printf("\x1b[B")
											}
										case LEFT_ARROW:
											if cur_x != 1 {
												cur_x -= 1
												fmt.printf("\x1b[D")
											}
										case RIGHT_ARROW:
											if cur_x != 64 {
												cur_x += 1
												fmt.printf("\x1b[C")
											}
										case:
										}
										i += 1
									}
								}
							}
						} else {
							i += 1
						}
					case CTRLD:
						when MODE == .editor {
							disp := back_buffer(&display)
							// Save the display into a file
							savefile, err := os.open("display-dump.bin", os.O_WRONLY)
							bytes := cast([^]byte)disp
							if err == 0 {
								defer os.close(savefile)
								os.write(savefile, bytes[0:32 * 8])
							}
						}
						i += 1


					case:
						i += 1
					}
				}
			}

			// editor
			//if n > 0 {
			//	i := 0
			//	for i != n {
			//		switch buffer[i] {
			//		case CTRLC:
			//			running = false
			//			i += 1
			//			continue
			//		case 0x20:
			//			i += 1
			//			disp := back_buffer(&display)
			//			disp[cur_y - 1] ~= 1 << u32(64 - cur_x)
			//		case:
			//			fmt.printf("%v ", buffer[i])
			//			i += 1
			//		}
			//	}
			//}


			when MODE == .exec {
				tick_60Hz(&cpu, &display, &rng)
			}


			when MODE != .exec {
				disp: Buffer
				disp = back_buffer(&display)^
				when MODE == .editor {save_cursor()}
				blit(&display)
				back_buffer(&display)^ = disp
				when MODE == .editor {restore_cursor()}
			}
			when MODE == .exec {
				blit(&display)
			}


		}

		when MODE == .exec {
			// should be running at 60Hz ~ 16ms/frame
			ms := time.duration_milliseconds(frame_dur)
			over := target_frame_time - frame_dur
			//fmt.printf("enjoying %v ms of free time\n", time.duration_milliseconds(over))
			time.accurate_sleep(over)
		}
	}
	fmt.printf("\x1b[32;64H\r\n", flush = true)

}

interpret_key :: proc "contextless" (cpu: ^Cpu, key: u8) {

	// keymap:
	// 1	2	3	C
	// 4	5	6	D
	// 7	8	9	E
	// A	0	B	F
	// FIXME: I cannot get keyboard scancodes from the terminal right now.
	// I will use the dvorak-programmer equivalent of what's given for now:
	// & [ { }
	// ; , . p
	// a o e u
	// ' q j k
	index: u16 = 0
	switch (key) {
	case '&':
		index = 1
	case '[':
		index = 2
	case '{':
		index = 3
	case '}':
		index = 0xC
	case ';':
		index = 4
	case ',':
		index = 5
	case '.':
		index = 6
	case 'p':
		index = 0xD
	case 'a':
		index = 7
	case 'o':
		index = 8
	case 'e':
		index = 9
	case 'u':
		index = 0xE
	case '\'':
		index = 0xA
	case 'q':
		index = 0
	case 'j':
		index = 0xB
	case 'k':
		index = 0xF
	case:
		return
	}
	cpu.key_mask |= 1 << index
}

font_code: []u8 = {0x00, 0xe0, 0xa0, 0x00, 0x60, 0x00, 0x61, 0x00, 0xd0, 0x15}

IBM_LOGO: [32]u64 = {}


bytes_to_int :: proc "contextless" (buf: []u8) -> (val: u64) {
	val = 0
	for ch in buf {
		//assume all of them are digits
		val *= 10
		val += u64(ch - '0')
	}
	return
}

running := true

STDIN := 0

CTRLD :: 'D' - 64
CTRLC :: 'C' - 64
RIGHT_ARROW: u8 = 67
LEFT_ARROW: u8 = 68
UP_ARROW: u8 = 65
DOWN_ARROW: u8 = 66
MODE :: Mode.exec



Mode :: enum {
	editor,
	debug,
	exec,
}
