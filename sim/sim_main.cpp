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

#include "defines.h"
#include <verilated.h>
#include <iostream>
#include <stdlib.h>
#include <pthread.h>
#include "Vpsp.h" // Verilator entrypoint
#include "Vpsp_psp.h" // Actual top SV model
#include "Vpsp_psp_system.h" // Main system module
#include "Vpsp_core.h" // Inner core
#ifndef MITSHD_LAB6
#include "Vpsp_graphics.h" // Graphics controller
#endif
#include "gdb.h" // GDB server
#include "psp.h" // C++ PSP Representation
#include "softserial.h" // Asynchronous serial IO

#ifndef HEADLESS_BUILD
#include "graphics.h" // GTK Wrapper for displaying virtual terminal
#endif // HEADLESS_BUILD

// If this program is called with any arguments, GDB mode is set to true
static bool gdb_mode = false;
extern uint64_t gdb_port;

// See: https://linux.die.net/man/1/verilator
unsigned int main_time = 0;     // Current simulation time
double sc_time_stamp () {       // Called by $time in Verilog
	return main_time;
}

// The wrapper class for the Verilated model
// This is a global pointer- other threads / methods may refer to this
// The Verilated code is not thread-safe, however, some psp system methods are.
// Only sim_main and gdb server (running on 1st created pthread) should ever call
// Verilated methods- the main graphics server thread (main thread) and others can
// only call the thread-safe PrettySecureProcessor methods.
PrettySecureProcessor *psp_system = NULL;

// Top module for Verilated simulation, psp_system is linked to this
static Vpsp *top = NULL;

// The video ram and text overlay buffers
uint32_t *psp_video_ram = NULL;
char *psp_text_overlay_ram = NULL;

static pthread_t simulator_thread, softserial_thread;

/*
 * process_image
 *
 * Process a framebuffer sent from the processor.
 *
 * Simulating this takes a fair amount of time- let's just pull from textram instead for now.
 *
 * Returns 'true' upon completion of a single frame, false if a frame is still in-progress.
 *
 * ar is a bit vector representing a VGA-style graphics port. The name 'ar' comes from the fact
 * that the port I used on the Pynq Z2 to run graphics on real hardware is named 'ar'.
 */

static int x_pos = 0;
static int y_pos = 0;

static int image_buffer[800][800][3];

bool process_image(int ar) {
	static int prev_clk = 0;
	static int prev_hsync = 0;
	int de, vsync, hsync, pxclk, r_out, g_out, b_out;

	// Grab current data packet:
	de = (ar & (1 << 0)) != 0;
	vsync = (ar & (1 << 1)) != 0;
	hsync = (ar & (1 << 2)) != 0;
	pxclk = (ar & (1 << 3)) != 0;
	r_out = (ar & (1 << 4)) != 0;
	g_out = (ar & (1 << 5)) != 0;
	b_out = (ar & (1 << 6)) != 0;

	// Parse packet:
	if ((prev_clk != pxclk) && pxclk) { // always_ff @ (posedge pxclk)
		if (!vsync) y_pos = 0;
		if (!hsync) x_pos = 0;

		image_buffer[y_pos][x_pos][0] = r_out;
		image_buffer[y_pos][x_pos][1] = g_out;
		image_buffer[y_pos][x_pos][2] = b_out;

		// Increment X
		if (de) {
			x_pos++;
		}

		// Increment Y (End of line)
		if (!hsync && prev_hsync) {
			y_pos++;
		}

		prev_hsync = hsync;
	}

	// End of frame
	if (x_pos == 799 && y_pos == 479) {
		printf("[\n");
		for (int j = 0; j < 480; j++) {
			printf("[\n");
			for (int i = 0; i < 800; i++) {
				printf("(%d,%d,%d),\n", image_buffer[j][i][0], image_buffer[j][i][1], image_buffer[j][i][2]);
			}
			printf("],\n");
		}
		printf("],\n");
		return true;
	}

	prev_clk = pxclk;
	return false;
}

/*
 * sim_main
 * Runs the main simulator logic.
 * This can be an independent thread from the graphics thread.
 */
int sim_main() {
	psp_system->reset();

	if (gdb_mode) {
		// Drop into GDB server:
		// If the GDB server returns (eg. socket closed), restart it and
		// wait for another client to connect:
		while (true) {
			gdb_server(psp_system);
		}
		return 0;
	}

	// Otherwise run the CPU without any debugging capabilities.
	psp_system->cont();

	printf("All done.\n");
	return 0;
}

/*
 * main
 *
 * Performs main simulation loop.
 * Halts when we detect the processor looping forever.
 */
int main (int argc, char **argv) {
	if (argc > 1) gdb_mode = true;
	if (argc > 2) gdb_port = atoi(argv[2]);

	Verilated::commandArgs(argc, argv);
	// Verilated::mkdir("logs"); // Setup folder for waves
	// Verilated::traceEverOn(true); // Enable tracing
	top = new Vpsp;

	psp_system = new PrettySecureProcessor(top);
#ifndef MITSHD_LAB6
	psp_video_ram = (uint32_t *)&top->psp->dut->graphics_inst->videoram;
	psp_text_overlay_ram = (char *)&top->psp->dut->graphics_inst->textram;
#else
	psp_video_ram = NULL;
	psp_text_overlay_ram = NULL;
#endif
	srand(time(NULL));

	// Launch the simulator thread
	pthread_create(&simulator_thread, NULL, (void* (*)(void*))sim_main, NULL);

	// Launch the softserial thread
#ifdef USE_SOFTSERIAL
	pthread_create(&softserial_thread, NULL, (void* (*)(void*))softserial_do_io, NULL);
#endif

	// Call graphics from main thread
	// (Quartz on macOS requires graphics calls are all from the main thread)
#ifndef HEADLESS_BUILD
	psp_gtk_main();
#endif // HEADLESS_BUILD

	// Wait for simulator
	pthread_join(simulator_thread, NULL);

	delete top;

	return 0;
}
