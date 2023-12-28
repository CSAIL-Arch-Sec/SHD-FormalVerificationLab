/*
 * Pretty Secure System
 * Joseph Ravichandran
 * UIUC Senior Thesis Spring 2021
 *
 * MIT License
 * Copyright (c) 2021-2023 Joseph Ravichandran
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <verilated.h>
#include "defines.h"
#include "psp.h"
#include "Vpsp_psp.h"
#include "Vpsp_psp_system.h"
#include "Vpsp_core.h"
#include "Vpsp_memory.h"
#ifndef MITSHD_LAB6
#include "Vpsp_psp_single_core__Vz1_Uz1.h"
#else
#include "Vpsp_psp_single_core.h"
#endif
#ifndef MITSHD_LAB6
#include "Vpsp_graphics.h"
#endif
#include "gdb.h"

#include "softserial.h"

PrettySecureProcessor::PrettySecureProcessor(Vpsp *system_in) {
	this->should_do_interrupt = false;
	pthread_mutex_init(&this->interrupt_lock, NULL);
	this->sys = system_in;
	for (int i = 0; i < NUM_BREAKPOINTS; i++) {
		this->breakpoints[i].addr = 0;
		this->breakpoints[i].enabled = false;
	}
}

/*
 * reset
 * Reset the CPU.
 */
void PrettySecureProcessor::reset() {
	// Reset
	this->sys->external_interrupt = 0;
	this->sys->reset = 1;
	this->sys->clk = 0;
	this->sys->eval();
	this->sys->clk = 1;
	this->sys->eval();
	this->sys->reset = 0;

#ifndef QUIET_MODE
	printf("Reset complete.\n");
#endif // QUIET_MODE
}

/*
 * step
 * Step the CPU a single instruction.
 * Stops if the CPU executes an instruction, or reports that it went to sleep.
 * Either way it will tick time forward by 1 clock cycle. This may cause other non-core0 cores
 * to continue executing instructions.
 */
void PrettySecureProcessor::step() {
	pthread_mutex_lock(&this->interrupt_lock);
	if (this->should_do_interrupt) {
		// printf("Doing interrupt\n");
		this->sys->external_interrupt = 1;
		this->sys->keycode = this->keycode;
		// Do not set should_do_interrupt to false here, we reuse this variable
		// as state so that we can clear the interrupt flag to the DUT later in step().
	}

	// As the softserial device is a polling-based device, no need to step the design
	// (We can just asynchronously write the data into the CSRs and eventually the write thing will
	// be read, so long as we do it atomically and while holding the interrupt lock).
	if (this->serial_data_available) {
		if (SOFTSERIAL_FLAGS_CLEAR == this->sys->psp->dut->core0->core->csr_misc[SOFTSERIAL_FLAGS_CSR]) {
			this->sys->psp->dut->core0->core->csr_misc[SOFTSERIAL_FLAGS_CSR] = SOFTSERIAL_FLAGS_WAITING;
			this->sys->psp->dut->core0->core->csr_misc[SOFTSERIAL_IO_CSR_IN] = this->serial_data;
			this->serial_data_available = false;
		}
	}

	this->sys->clk = 0;
	this->sys->eval();

	while (!Verilated::gotFinish()) {
		this->sys->clk = !this->sys->clk;
		this->sys->eval();

		if (this->should_do_interrupt) {
			this->sys->external_interrupt = 0;
			this->should_do_interrupt = false;
		}

		if (this->sys->clk && this->sys->valid && this->sys->shutdown) {
			exit(0);
		}

		if (this->sys->clk && (this->sys->valid || this->sys->core0_sleeping)) {
			break;
		}
	}
	pthread_mutex_unlock(&this->interrupt_lock);
	// printf("Finishing step at PC = %x\n", this->get_reg(PC_REG));
}

/*
 * cont
 * Continue running the CPU until we hit a breakpoint.
 */
void PrettySecureProcessor::cont() {
	bool hit_breakpoint = false;
	int32_t prev_pc = this->get_reg(PC_REG) - 4;

	// Limit how far we can trace when tracing PC
	// int32_t num_steps_remaining = 30000;

	while(!Verilated::gotFinish() && !hit_breakpoint) {
		this->step();

		uint32_t pc = this->get_reg(PC_REG);

		// Break on infinite loop
		// if (pc == prev_pc) {
		// 	printf("Detected infinite loop\n");
		// 	break;
		// }

		// Check for breakpoint
		for (int i = 0; i < NUM_BREAKPOINTS; i++) {
			if (this->breakpoints[i].enabled && pc == this->breakpoints[i].addr) {
				hit_breakpoint = true;
				break;
			}
		}

		// num_steps_remaining--;
		// if (num_steps_remaining == 0) hit_breakpoint = true;

		prev_pc = pc;
	}
}

/*
 * step_iters
 * Like continue except it will return synchronously after a number of iterations.
 * Returns true if we stopped due to a breakpoint, false otherwise.
 */
bool PrettySecureProcessor::step_iters(size_t num_iters) {
	// Limit how far we can trace when tracing PC
	int32_t num_steps_remaining = num_iters;

	while(!Verilated::gotFinish()) {
		this->step();

		uint32_t pc = this->get_reg(PC_REG);

		// Break on infinite loop
		// if (pc == prev_pc) {
		// 	printf("Detected infinite loop\n");
		// 	break;
		// }

		// Check for breakpoint
		for (int i = 0; i < NUM_BREAKPOINTS; i++) {
			if (this->breakpoints[i].enabled && pc == this->breakpoints[i].addr) {
				return true;
			}
		}

		num_steps_remaining--;
		if (num_steps_remaining == 0) return false;
	}

	// Exiting due to $finish is counted as a breakpoint
	return true;
}

/*
 * get_reg
 * Returns contents of a single register.
 * Regs x0->x31 are indexed with 0->31, respectively. PC is reg 32.
 * This is how GDB does it.
 */
inline uint32_t PrettySecureProcessor::get_reg(uint32_t idx) {
	if (idx == PC_REG) {
		return this->sys->pc_out;
	}
	return this->sys->psp->dut->core0->core->regs[idx];
}


/*
 * get_regs
 * Write all regs into a GDB-favorable buffer.
 */
void PrettySecureProcessor::get_regs(char *buf, size_t buf_size) {
	for (int i = 0; i < NUM_REGS; i++) {
		uint32_t reg_val = this->get_reg(i);

		uint32_t reg_val_little_endian = to_little_endian(reg_val);

		size_t bytes_written = snprintf(
			buf,
			buf_size,
			"%08x",
			reg_val_little_endian);

		// Slide along the buffer- but don't overflow it!
		if (buf_size < 8) return;
		buf += 8;
		buf_size -= 8;
	}
}

/*
 * set_breakpoint
 * Sets a breakpoint.
 *
 * addr- address to break on
 * enabled- if true, this adds a breakpoint. if false, it disables it (if it exists).
 *
 * Returns false if the breakpoint could not be insertted, true otherwise.
 */
bool PrettySecureProcessor::set_breakpoint(uint32_t addr, uint8_t enabled) {
	if (enabled) {
		// Add a breakpoint
		for (int i = 0; i < NUM_BREAKPOINTS; i++) {
			if (!this->breakpoints[i].enabled) {
				this->breakpoints[i].enabled = true;
				this->breakpoints[i].addr = addr;
				return true;
			}
		}
		return false;
	}
	else {
		// Remove a breakpoint
		for (int i = 0; i < NUM_BREAKPOINTS; i++) {
			if (this->breakpoints[i].enabled && this->breakpoints[i].addr == addr) {
				this->breakpoints[i].enabled = false;
				this->breakpoints[i].addr = 0;
				return true;
			}
		}
	}

	// Wanted to disable a breakpoint but couldn't find it, so just return true
	return true;
}

/*
 * read_mem_byte
 * Returns a single byte at any alignment from main memory.
 */
uint8_t PrettySecureProcessor::read_mem_byte (uint32_t addr) {
	uint32_t val = this->sys->psp->dut->core0->main_mem->ram[(addr >> 2)];

	return (val >> (8 * (addr & 0x03))) & 0x0ff;
}

/*
 * read_mem_buf_printable
 * Read a buffer from processor RAM into a C++ buffer using
 * printable ASCII characters (for use with GDB).
 */
void PrettySecureProcessor::read_mem_buf_printable(char *buf,
	size_t buf_size, uint32_t addr, uint32_t num_bytes) {
	for (int i = 0; i < num_bytes; i++) {
		uint8_t val = this->read_mem_byte(addr + i);
		size_t bytes_written = snprintf(
				buf,
				buf_size,
				"%02x",
				val
			);

		if (buf_size < 2) return;
		buf += 2;
		buf_size -= 2;
	}
}

void PrettySecureProcessor::print_textram() {
#ifndef MITSHD_LAB6
	printf("+----------------------------Pretty Secure Processor-----------------------------+\n");
	for (int y = 0; y < 32; y++) {
		printf("|");
		for (int x = 0; x < 80; x++) {
			char c = this->sys->psp->dut->graphics_inst->textram[(80*y)+x];
			if (c == '\0') c = ' ';
			if (c == '\n') c = ' ';
			printf("%c", c);
		}
		printf("|\n");
	}
	printf("+--------------------------------------------------------------------------------+\n");
#endif
}

void PrettySecureProcessor::schedule_interrupt(char keycode) {
	pthread_mutex_lock(&this->interrupt_lock);
	this->should_do_interrupt = true;
	this->keycode = keycode;
	pthread_mutex_unlock(&this->interrupt_lock);
}
