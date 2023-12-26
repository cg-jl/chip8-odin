package cheight


import "core:fmt"
import "core:math/bits"
import "core:math/rand"
import "core:strings"

Cpu :: struct {
	memory:             [4096]byte,
	index_register:     u16, // u12
	pc:                 u16, // u12
	call_stack:         [256]u16, // limit the call stack to detect stack overflows
	call_stack_pointer: u8,
	// NOTE: If the frequency of the CPU is different than 60Hz, these two
	// must be updated and handled in a separate thread.
	delay:              u8, // 60Hz timer
	// FIXME: The 'beep' sound is currently unavailable under the terminal
	// display mode. Look into updating the streams with raylib.
	beep:               u8, // 60Hz timer, gives beep as long as it's not 0
	// NOTE: These must be set externally.
	present_keys:       u8,
	gp:                 [16]u8, // V0-VF
	key_mask:           u16, // Which keys are being pressed right now.
}

@(private)
read_insn_byte :: proc "contextless" (cpu: ^Cpu) -> (b: u8) {
	b = cpu.memory[cpu.pc]
	cpu.pc += 1
	return
}

decode_current_noadvance :: proc "contextless" (cpu: ^Cpu) -> (insn: u16) {
	old := cpu.pc
	insn = fetch(cpu)
	cpu.pc = old
	return
}

disassemble :: proc(insn: u16, sb: ^strings.Builder) -> string {

	switch (insn >> 12) {
	case 0x0:
		switch (insn & 0xff) {
		case 0xE0:
			return "clear screen"
		case 0xEE:
			return "return"
		case:
		// invalid

		}
	case 0x1:
		// jump NNN
		return fmt.sbprintf(sb, "jump %03x", insn & 0xfff)
	case 0x2:
		// subroutine
		return fmt.sbprintf(sb, "subroutine %03x", insn & 0xfff)

	case 0x3:
		reg := (insn >> 8) & 0xf
		return fmt.sbprintf(sb, "skip if V%X == %v", reg, insn & 0xff)
	case 0x4:
		reg := (insn >> 8) & 0xf
		return fmt.sbprintf(sb, "skip if V%X != %v", reg, insn & 0xff)
	case 0x5:
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf
		return fmt.sbprintf(sb, "skip if V%X == V%X", x, y)
	case 0x9:
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf
		return fmt.sbprintf(sb, "skip if V%X != V%X", x, y)


	case 0xA:
		// ANNN set index register I
		return fmt.sbprintf(sb, "set I to %03x", insn & 0xfff)
	case 0x6:
		// 6XNN set register vx
		reg := (insn >> 8) & 0xf
		return fmt.sbprintf(sb, "V%X = %v", reg, insn & 0xff)
	case 0x7:
		// 7xnn add value to register vx
		reg := (insn >> 8) & 0xf
		return fmt.sbprintf(sb, "V%X += %v", reg, insn & 0xff)
	case 0xD:
		// DXYN display
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf
		n := insn & 0xf
		return fmt.sbprintf(sb, "draw @ V%X, V%X, height = %v", x, y, n)
	case 0x8:
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf
		switch (insn & 0xf) {
		case 0:
			// set vx to vy
			return fmt.sbprintf(sb, "V%X = V%X", x, y)
		case 1:
			// OR
			return fmt.sbprintf(sb, "V%X |= V%X", x, y)
		case 2:
			// AND
			return fmt.sbprintf(sb, "V%X &= V%X", x, y)
		case 3:
			// XOR
			return fmt.sbprintf(sb, "V%X XOR= V%X", x, y)
		case 4:
			// add
			return fmt.sbprintf(sb, "V%X += V%X", x, y)
		case 5:
			return fmt.sbprintf(sb, "V%X = V%X - V%X", x, x, y)
		case 7:
			return fmt.sbprintf(sb, "V%X = V%X - V%X", x, y, x)


		}
	}
	return "<unknown>"
}

@(private)
fetch :: proc "contextless" (cpu: ^Cpu) -> (insn: u16) {
	hi := u16(read_insn_byte(cpu)) << 8
	lo := u16(read_insn_byte(cpu))
	insn = hi | lo
	return
}


tick_delay_60Hz :: proc "contextless" (cpu: ^Cpu) {
	if cpu.delay > 0 {
		cpu.delay -= 1
	}
}
tick_beep_60Hz :: proc "contextless" (cpu: ^Cpu) {
	if cpu.beep > 0 {
		cpu.beep -= 1
	}
}

// Assume the caller maintains a 60Hz call frequency, so ticks the timers for it
// and interprets the next instruction.
tick_60Hz :: proc(cpu: ^Cpu, display: ^Display, rng: ^rand.Rand) {
	tick_delay_60Hz(cpu)
	tick_beep_60Hz(cpu)
	next_instruction(cpu, display, rng)
}

// Interprets the next instruction, without ticking the timers
next_instruction :: proc(cpu: ^Cpu, display: ^Display, rng: ^rand.Rand) {

	insn := fetch(cpu)
	switch (insn >> 12) {
	case 0x0:
		switch (insn & 0xff) {
		case 0xE0:
			// clear screen
			backbuf := back_buffer(display)
			for _, i in backbuf {
				backbuf[i] = 0
			}
			return
		case 0xEE:
			// return from subroutine
			cpu.call_stack_pointer -= 1
			cpu.pc = cpu.call_stack[cpu.call_stack_pointer]
			return
		case:
		// invalid

		}
	case 0x1:
		// jump NNN
		cpu.pc = insn & 0xfff
		return
	case 0x2:
		// subroutine
		cpu.call_stack[cpu.call_stack_pointer] = cpu.pc
		cpu.call_stack_pointer += 1
		cpu.pc = insn & 0xfff
		return

	case 0x3:
		reg := (insn >> 8) & 0xf
		if (u16(cpu.gp[reg]) == insn & 0xff) {
			cpu.pc += 2
		}
		return
	case 0x4:
		reg := (insn >> 8) & 0xf
		if (u16(cpu.gp[reg]) != insn & 0xff) {
			cpu.pc += 2
		}
		return
	case 0x5:
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf

		if (cpu.gp[x] == cpu.gp[y]) {
			cpu.pc += 2
		}
		return
	case 0x9:
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf

		if (cpu.gp[x] != cpu.gp[y]) {
			cpu.pc += 2
		}
		return


	case 0xA:
		// ANNN set index register I
		cpu.index_register = insn & 0xfff
		return
	case 0x6:
		// 6XNN set register vx
		reg := (insn >> 8) & 0xf
		cpu.gp[reg] = u8(insn & 0xff)
		return
	case 0x7:
		// 7xnn add value to register vx
		reg := (insn >> 8) & 0xf
		cpu.gp[reg] += u8(insn & 0xff)
		return
	case 0xD:
		// DXYN display
		// wrap start coordinates
		x_start := uint(cpu.gp[(insn >> 8) & 0xf] & 63)
		y := uint(cpu.gp[(insn >> 4) & 0xf] & 31)
		n := uint(insn & 0xf)

		// clip vertically
		if y + n > 31 {
			n = 31 - y
		}

		// NOTE: for this to work, the MSbit (Most Significant bit) of each lane
		// in the display buffer must coincide with the leftmost pixel of such
		// lane in the blitted-to screen.
		backbuf := back_buffer(display)
		sprite_bytes := cpu.memory[cpu.index_register:][:n]
		any_pixels_went_off: u8 = 0
		for sprite_byte, lane_idx_i in sprite_bytes {
			lane_idx := uint(lane_idx_i)
			sprite_lane := u64(sprite_byte) << (64 - 8)
			// shift it so the MSbit of the sprite lane is aligned
			// to the x coordinate. Since we're using a logical shift
			// (unsigned), this will also do the clipping.
			sprite_lane >>= x_start
			old_lane := backbuf[y + lane_idx]
			// detect where (1 XOR 1) will occur.
			turned_off_pixels: u64 = old_lane & sprite_lane
			any_pixels_went_off |= u8(turned_off_pixels != 0)

			// set the new lane
			backbuf[y + lane_idx] = old_lane ~ sprite_lane
		}
		cpu.gp[VF] = any_pixels_went_off
		return
	case 0x8:
		x := (insn >> 8) & 0xf
		y := (insn >> 4) & 0xf
		switch (insn & 0xf) {
		case 0:
			// set vx to vy
			cpu.gp[x] = cpu.gp[y]
			return
		case 1:
			// OR
			cpu.gp[x] |= cpu.gp[y]
			return
		case 2:
			// AND
			cpu.gp[x] &= cpu.gp[y]
			return
		case 3:
			// XOR
			cpu.gp[x] ~= cpu.gp[y]
			return
		case 4:
			// add
			new, had_overflow := bits.overflowing_add(cpu.gp[x], cpu.gp[y])
			cpu.gp[x] = new
			cpu.gp[VF] = u8(had_overflow)
			return
		case 5:
			flag := u8(cpu.gp[x] > cpu.gp[y])
			cpu.gp[x] -= cpu.gp[y]
			cpu.gp[VF] = flag
			return
		case 7:
			flag := u8(cpu.gp[y] > cpu.gp[x])
			cpu.gp[x] = cpu.gp[y] - cpu.gp[x]
			cpu.gp[VF] = flag
			return

		case 6:
			// TODO: configurable old behavior?
			cpu.gp[x] >>= 1
			return
		case 0xE:
			// TODO: configurable old behavior?
			cpu.gp[x] <<= 1
			return

		case:
		// invalid

		}
	case 0xB:
		// TODO: configurable behavior for BXNN vs BNNN (just V0)?
		cpu.pc = insn & 0xfff
		return
	case 0xC:
		x := (insn >> 8) & 0xf
		r := transmute(u32)rand.int31(rng)
		cpu.gp[x] = u8(r & 0xff)
		return
	case 0xE:
		x := (insn >> 8) & 0xf
		mask: u16 = 1 << cpu.gp[x]
		switch (insn & 0xff) {
		case 0x9E:
			// pressed
			if cpu.key_mask & mask != 0 {
				cpu.pc += 2
			}
			return

		case 0xA1:
			// not pressed
			if cpu.key_mask & mask == 0 {
				cpu.pc += 2
			}
			return
		case:
		// invalid
		}
	case 0xF:
		x := (insn >> 8) & 0xf
		switch (insn & 0xff) {
		case 0x07:
			cpu.gp[x] = cpu.delay
			return
		case 0x15:
			cpu.delay = cpu.gp[x]
			return
		case 0x18:
			cpu.beep = cpu.gp[x]
			return
		case 0x1E:
			cpu.index_register += u16(cpu.gp[x])
			cpu.gp[VF] = u8(cpu.index_register > 0x1000)
			return
		case 0x0A:
			if cpu.key_mask == 0 {
				cpu.pc -= 2 // loop.
			} else {
				// NOTE: Since we're checking each frame, this shouldn't be
				// problematic, however it would be nicer to have a queue
				// system instead of just a mask.
				cpu.gp[x] = u8(bits.count_trailing_zeros(cpu.key_mask))

			}
			return
		case 0x29:
			// font character
			// we currently load the fonts @ 0
			cpu.gp[x] = 0
			return
		case 0x33:
			n := cpu.gp[x]
			cpu.memory[cpu.index_register] = n / 100
			cpu.memory[cpu.index_register + 1] = (n % 100) / 10
			cpu.memory[cpu.index_register + 2] = n % 10
			return
		case 0x55:
			// TODO: configurable old behavior?
			copy(cpu.memory[cpu.index_register:][:x + 1], cpu.gp[:x + 1])
			return


		case 0x65:
			// TODO: configurable old behavior?
			copy(cpu.gp[:x + 1], cpu.memory[cpu.index_register:][:x + 1])
			return


		}


	}
	fmt.printf("unhandled insn: %x\n", insn)
	panic("AAAAAA")
}

load_code :: proc(cpu: ^Cpu, code: []u8) {
	if (len(code) >= (4096 - 0x200)) {
		// offset it at zero
		cpu.pc = 0
		copy(cpu.memory[:], code)
	} else {
		cpu.pc = 0x200
		copy(cpu.memory[0x200:], code)
	}

	// load the font at 0x050
	copy(cpu.memory[:], font)
}


@(private)
font: []u8 = {
	0xF0,
	0x90,
	0x90,
	0x90,
	0xF0, // 0
	0x20,
	0x60,
	0x20,
	0x20,
	0x70, // 1
	0xF0,
	0x10,
	0xF0,
	0x80,
	0xF0, // 2
	0xF0,
	0x10,
	0xF0,
	0x10,
	0xF0, // 3
	0x90,
	0x90,
	0xF0,
	0x10,
	0x10, // 4
	0xF0,
	0x80,
	0xF0,
	0x10,
	0xF0, // 5
	0xF0,
	0x80,
	0xF0,
	0x90,
	0xF0, // 6
	0xF0,
	0x10,
	0x20,
	0x40,
	0x40, // 7
	0xF0,
	0x90,
	0xF0,
	0x90,
	0xF0, // 8
	0xF0,
	0x90,
	0xF0,
	0x10,
	0xF0, // 9
	0xF0,
	0x90,
	0xF0,
	0x90,
	0x90, // A
	0xE0,
	0x90,
	0xE0,
	0x90,
	0xE0, // B
	0xF0,
	0x80,
	0x80,
	0x80,
	0xF0, // C
	0xE0,
	0x90,
	0x90,
	0x90,
	0xE0, // D
	0xF0,
	0x80,
	0xF0,
	0x80,
	0xF0, // E
	0xF0,
	0x80,
	0xF0,
	0x80,
	0x80, // f
}

VF: uint = 0xf
