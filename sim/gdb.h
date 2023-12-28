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

#ifndef GDB_H
#define GDB_H

#include "psp.h"

/*
 * Launch gdb server
 */
void gdb_server (PrettySecureProcessor *sys_in);

static inline void reply_with(int fd, char *msg);
void handle_packet (int fd, char *pkt, size_t pkt_len);

#define PSPSIM_PORT_DEFAULT ((5050))
#define PKTBUF_SIZE 2048

#define GDB_PACKET_BREAK 0x03
#define GDB_CONTINUE_NUM_STEPS 1

/*
 * GDB stubs are at minimum required to implement the following packets:
 *
 * ? - reason for halting
 * g/G - register access
 * m/M - memory access
 * c - continue execution
 * s - step execution
 *
 * Multi-threaded systems also need to implement:
 * vCont
 *
 * Any unimplemented commands should reply with the empty response:
 * $#00
 *
 * Packets are defined as:
 * $packet-data#cheksum
 */

/*
 * to_little_endian
 * Convert a value from big-endian to little-endian.
 */
static inline uint32_t to_little_endian(uint32_t val) {
	return ((val & (0x0ff << 0)) << 24) | \
		((val & (0x0ff << 8)) << 8) | \
		((val & (0x0ff << 16)) >> 8) | \
		((val & (0x0ff << 24)) >> 24);
}

#endif // GDB_H
