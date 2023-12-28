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

#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <poll.h>
#include "gdb.h"

// GDB Server for use with Pretty Secure Processor

// System this server was called with
static PrettySecureProcessor *sys = NULL;

// Buffer used to store the current request packet from GDB client
static char pktbuf[PKTBUF_SIZE];

// Buffer used to buffer data from the model 'sys' before sending back to GDB client
static char model_buf[2048];

// Set this to true to enable printf debugging of GDB protocol
#define PRINTF_DEBUGGING false

// Did we receive a "continue" command from GDB?
// If yes, call step_iters repeatedly while watching for future GDB instructions (eg. break)
static bool running_continuously = false;

uint64_t gdb_port = PSPSIM_PORT_DEFAULT;

// Macro to simplify creating handlers for longer commands in handle_packet
// Don't forget to return after handling a packet to prevent the switch statement from taking over!
#define REPLY_TO(x) if (0 == strncmp(x, pkt, strlen(x)))
#define REPLY(x) reply_with(fd, (char *)x)

void gdb_server (PrettySecureProcessor *sys_in) {
	sys = sys_in;

	int socket_fd = socket(AF_INET, SOCK_STREAM, 0);

	struct sockaddr_in addr;
	int addrlen = sizeof(addr);

	if (socket_fd < 0) {
		printf("error creating socket!\n");
	}

	addr.sin_family = AF_INET;
	addr.sin_port = htons( gdb_port );
	addr.sin_addr.s_addr = INADDR_ANY;

	// If there are any old sockets hanging around the kernel, remove them:
	int one = 1;
	setsockopt(socket_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

	if (bind(socket_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		printf("error binding!\n");
		return;
	}

	if (listen(socket_fd, 1) < 0) {
		printf("error listening!\n");
		return;
	}

	printf("Waiting for debugger on port %llu...\n", gdb_port);

	// Socket should be open now I guess
	struct sockaddr peer_addr; // <- contains peer address
	addrlen = sizeof(peer_addr);
	int client_fd = accept(socket_fd, (struct sockaddr *) &peer_addr, (socklen_t *)&addrlen);

	printf("Debugger attached!\n");

	// Event loop: simulate if running continuously, poll for new commands, either handle them or re-loop
	int i = 0;
	while (1) {
		bool stopped_due_to_bp = false;

		// 1. Simulate
		if (running_continuously) {
			stopped_due_to_bp = sys->step_iters(GDB_CONTINUE_NUM_STEPS);

			if (stopped_due_to_bp) {
				running_continuously = false;
			}
		}

		// 2. Check for new GDB packets
		struct pollfd poll_socket_connection = {
			.fd = client_fd,
			.events = POLLIN | POLLPRI,
			.revents = 0,
		};
		int poll_state = poll(&poll_socket_connection, 1, 0);

		// 3. Either reply or just continue waiting/ simulating
		if (0 == poll_state) {
			// No new commands to reply to
			// If we saw a breakpoint, now we can inform GDB
			if (stopped_due_to_bp) {
				reply_with(client_fd, (char *)"S05");
			}
		}
		else {
			// Something to reply to
			memset(pktbuf, '\0', sizeof(pktbuf));
			ssize_t val_read = read(client_fd, pktbuf, sizeof(pktbuf));

			if (val_read < 0) {
				printf("GDB Session Disconnected\n");
				close(client_fd);
				close(socket_fd);
				return;
			}

			pktbuf[val_read] = '\0';

			if (PRINTF_DEBUGGING) {
				printf("[%d] %s\n", i, pktbuf);
			}
			handle_packet(client_fd, pktbuf, sizeof(pktbuf));
			i++;
		}
	}

	close(client_fd);
	close(socket_fd);
	printf("Server is quitting\n");
	return;
}

/*
 * reply_with
 * Sends a string to 'fd' (replying to a GDB packet). Computes checksum and
 * handles creation of header and checksum footer before sending packet.
 *
 * Inputs:
 *  - fd: File descriptor belonging to open socket with GDB client
 *  - msg: NULL-Terminated string to send back!
 */
static inline void reply_with(int fd, char *msg) {
	char formatted_buf[2048];

	formatted_buf[0] = '$';
	strncpy(formatted_buf + 1, msg, sizeof(formatted_buf) - 1);

	size_t len = strlen(formatted_buf);
	if (len > sizeof(formatted_buf) - 5) {
		// Need 1 byte for beginning- '$'
		// Need 4 bytes at end for checksum- '#', byte 1, byte 2, '\0'
		printf("Message too big for our buffer! Not sending.\n");
		return;
	}

	// Compute checksum
	char *chksum = &formatted_buf[len];
	unsigned char chksum_accumulator = 0;
	for (int i = 0; i < strlen(msg); i++) {
		chksum_accumulator += msg[i];
	}

	// Just in case char is ever not 8 bits in the future...
	chksum_accumulator = chksum_accumulator & 0x0ff;
	chksum[0] = '#';

	chksum++;
	snprintf(chksum, 3, "%02x", chksum_accumulator);

	if (PRINTF_DEBUGGING) {
		printf("Replying with: %s\n", formatted_buf);
	}
	send(fd, formatted_buf, strlen(formatted_buf), 0);
}

/*
 * handle_packet
 * Handles replying to a GDB packet.
 *
 * Inputs:
 *  - fd: File descriptor belonging to open socket with GDB client
 *  - pkt: Buffer containing the packet we're replying to
 *  - pkt_len: Length of the buffer
 *
 * Returns:
 *  - None
 *
 * Side Effects:
 *  - May send data to socket 'fd'
 */
void handle_packet (int fd, char *pkt, size_t pkt_len) {
	char *cursor;
	uint32_t num_words;
	uint32_t addr;

	// ACK it:
	send(fd, (char *)"+\0", 2, 0);

	// If we receive a break, the packet will just contain 0x03, reply SIGTRAP and exit
	if (pkt[0] == GDB_PACKET_BREAK) {
		if (running_continuously) { running_continuously = false; REPLY("S05"); return; }
		else { REPLY("OK"); return; }
	}

	// Strip header, dropping the ones that are only '+' and removing the '+'
	// if it is occuring before a longer packet:
	// Sometimes we get multiple acks ('++' in front of a packet), ignore them all:
	// (We are allowed to ignore them, see GDB Server Protocol E.11 Packet Acknowledgement)
	while (pkt[0] == '+') { pkt++; pkt_len--; }
	if (!pkt[0]) { return; }
	if (pkt[0] == '-') { printf("Uh oh, we should probably implement re-transmission!\n"); return; }
	if (pkt[0] != '$') { printf("Invalid packet detected (0x%X): %s\n", pkt[0], pkt); return; }
	pkt_len--;
	pkt++;

	REPLY_TO("qSupported") {
		// These tell the client what reasons it can expect for a break
		// We're telling it we can break on sw or hw breakpoints
		REPLY("swbreak+;hwbreak+");
		return;
	}

	REPLY_TO("Z0") {
		// Insert SW breakpoint
		// @TODO: Refactor this mess:
		cursor = &pkt[3];
		while (*cursor && *cursor != ',') { cursor++; }

		if (!*cursor) { printf("Invalid Z0 (sw breakpoint) request packet\n"); return; }
		*cursor = '\0';

		addr = strtoul(&pkt[3], NULL, 16);
		num_words = strtoul(cursor + 1, NULL, 16);

		if (PRINTF_DEBUGGING) {
			printf("Wants to set breakpoint at %x (kind = %d)\n", addr, num_words);
		}

		if (!sys->set_breakpoint(addr, true)) {
			REPLY("E 01");
		}

		REPLY("OK");
		return;
	}

	REPLY_TO("z0") {
		// Remove SW breakpoint
		// @TODO: Refactor this mess:
		cursor = &pkt[3];
		while (*cursor && *cursor != ',') { cursor++; }

		if (!*cursor) { printf("Invalid z0 (sw breakpoint) request packet\n"); return; }
		*cursor = '\0';

		addr = strtoul(&pkt[3], NULL, 16);
		num_words = strtoul(cursor + 1, NULL, 16);

		if (PRINTF_DEBUGGING) {
			printf("Wants to clear breakpoint at %x (kind = %d)\n", addr, num_words);
		}

		if (!sys->set_breakpoint(addr, false)) {
			REPLY("E 01");
		}

		REPLY("OK");
		return;
	}

	switch(pkt[0]) {

		// Stopped reason
		case '?':
			// See GDB source code file include/gdb/signals.def
			// 05 = Trace/ Breakpoint trap
			REPLY("S05");
		break;

		// Get register values
		case 'g':
			sys->get_regs(model_buf, sizeof(model_buf));
			REPLY(model_buf);
		break;

		// Step single instruction
		case 's':
			sys->step();
			REPLY("S05");
		break;

		// Continue
		case 'c':
			// Schedule the CPU to run continuously while occasionally polling for new GDB commands:
			// (This way we can catch SIGINTs)
			running_continuously = true;
			REPLY("OK");

			// Previously we synchronously ran the CPU until we hit a breakpoint:

			// sys->cont();
			// Report breakpoint:
			// REPLY("S05");
		break;

		// Read some memory
		case 'm':
			cursor = &pkt[1];
			while (*cursor && *cursor != ',') { cursor++; }

			if (!*cursor) { printf("Invalid memory request packet\n"); return; }
			*cursor = '\0';

			// atoi doesn't do hex!!! That was a really annoying bug
			// addr = atoi(&pkt[1]);
			addr = strtoul(&pkt[1], NULL, 16);
			num_words = strtoul(cursor + 1, NULL, 16);

			if (PRINTF_DEBUGGING) {
				printf("Wants to read %d bytes from %x\n", num_words, addr);
			}

			sys->read_mem_buf_printable(model_buf, sizeof(model_buf), addr, num_words);
			REPLY(model_buf);
		break;

		default:
			// By default, reply empty
			REPLY("");
		break;
	}
}
