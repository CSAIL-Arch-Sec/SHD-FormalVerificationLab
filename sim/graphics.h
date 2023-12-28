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

#ifndef GRAPHICS_H
#define GRAPHICS_H

#include "defines.h"

#ifndef MITSHD_LAB6

/*
 * Graphics Library for use with PSP simulator.
 * This will handle drawing a virtual TFT terminal as well
 * as other interface elements (such as the interactive memory
 * viewer, cache viewer, interconnect viewer, etc.)
 */

#include <gtk/gtk.h>

/*
 * psp_gtk_main
 * Launch all GTK portions of the simulator
 */
int psp_gtk_main ();

// How many ms between image refreshes?
#define IMAGE_REFRESH_QUANTUM 30

// Screen dimensions
#define SCREEN_WIDTH 640
#define SCREEN_HEIGHT 480

// Dimensions for the text overlay
#define TEXT_OVERLAY_NUM_COLUMNS 80
#define TEXT_OVERLAY_NUM_ROWS 30

#endif // !MITSHD_LAB6

#endif // GRAPHICS_H
