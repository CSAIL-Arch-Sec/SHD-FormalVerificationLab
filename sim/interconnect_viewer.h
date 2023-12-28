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

#ifndef INTERCONNECT_VIEWER_H
#define INTERCONNECT_VIEWER_H

#include "config.h"

#ifdef USE_INTERCONNECT

#include <gtk/gtk.h>

gint ic_viewer_callback (gpointer data);
void ic_viewer_gtk_activate(GtkApplication *app);

#define IC_WINDOW_REFRESH_QUANTUM 30

#define IC_WINDOW_W ((640))
#define IC_WINDOW_H ((480))

// Color map
#define CORE0_COLOR 0x00ffff
#define CORE1_COLOR 0xff00ff
#define RS0_COLOR 0xff0000
#define RS1_COLOR 0xffff00
#define RS2_COLOR 0x0000ff
#define RS3_COLOR 0x00ff00
#define LLC_COLOR 0x808080
#define GRAPHICS_COLOR 0x000000

#endif // USE_INTERCONNECT

#endif // INTERCONNECT_VIEWER_H
