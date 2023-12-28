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

#ifndef PSP_H
#define PSP_H

#include <cstdint>
#include <pthread.h>
#include "Vpsp.h"

/*
 * psp.h
 *
 * A model representing the Pretty Secure Processor
 * from C++. This is used for converting between
 * the Verilated sources and an architectural level
 * more usable by the GDB integration.
 */

// 32 general purpose + pc
#define NUM_REGS 33

// Which idx does PC belong to?
#define PC_REG 32

#define NUM_BREAKPOINTS 64

typedef struct {
	uint32_t addr;
	bool enabled;
} Breakpoint;

class PrettySecureProcessor {

public:
	/*
	 * Construct a new PrettySecureProcessor wrapper.
	 */
	PrettySecureProcessor(Vpsp *system_in);

	/*
	 * reset
	 * Reset the CPU.
	 */
	void reset();

	/*
	 * step
	 * Step the CPU a single instruction.
	 */
	void step();

	/*
	 * step_iters
	 * Like continue except it will return synchronously after a number of iterations.
	 * Returns true if we stopped due to a breakpoint, false otherwise.
	 */
	bool step_iters(size_t num_iters);

	/*
	 * cont
	 * Continue running the CPU until a breakpoint is detected.
	 */
	void cont();

	/*
	 * get_reg
	 * Returns contents of a single register.
	 * Regs x0->x31 are indexed with 0->31, respectively. PC is reg 32.
	 * This is how GDB does it.
	 */
	uint32_t get_reg(uint32_t idx);

	/*
	 * get_regs
	 * Write all regs into a GDB-favorable buffer.
	 */
	void get_regs(char *buf, size_t buf_size);

	/*
	 * set_regs
	 * Set all registers to a given register vector from GDB.
	 */
	void set_regs();

	/*
	 * set_breakpoint
	 * Sets a breakpoint.
	 *
	 * addr- address to break on
	 * enabled- if true, this adds a breakpoint. if false, it disables it (if it exists).
	 *
	 * Returns false if the breakpoint could not be insertted, true otherwise.
	 */
	bool set_breakpoint(uint32_t addr, uint8_t enabled);

	/*
	 * read_mem_byte
	 * Returns a single byte at any alignment from main memory.
	 */
	uint8_t read_mem_byte (uint32_t addr);

	/*
	 * read_mem_buf_printable
	 * Read a buffer from processor RAM into a C++ buffer using
	 * printable ASCII characters (for use with GDB).
	 *
	 * Reads num_bytes bytes from main_mem. addr is not necessarily 4-byte aligned.
	 */
	void read_mem_buf_printable(char *buf, size_t buf_size, uint32_t addr, uint32_t num_bytes);

	/*
	 * print_textram
	 * Print text-mode video ram to the screen with standard out.
	 */
	void print_textram();

	/*
	 * schedule_interrupt
	 * Schedules an interrupt to be fired at the next synchronization point.
	 * This is thread-safe- you can call this from any thread you'd like.
	 */
	void schedule_interrupt(char keycode);

	Vpsp *sys;
	Breakpoint breakpoints[NUM_BREAKPOINTS];

	// Should we fire an interrupt next chance we get?
	// @TODO: Make this variable thread safe between GTK and Verilated model
	bool should_do_interrupt = false;

	// Lock this before accessing should_do_interrupt:
	pthread_mutex_t interrupt_lock;

	// Latest keypress keycode
	char keycode;

	// Are we waiting to send new some serial data to the CPU's softserial device?
	bool serial_data_available = false;

	// If so, what is the serial byte available to send?
	char serial_data;
};

#endif // PSP_H
