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

#ifndef CACHE_VIEWER_H
#define CACHE_VIEWER_H

#include "config.h"

#ifdef USE_CACHES

#include <gtk/gtk.h>

#include "Vpsp_cache__N4_Uz3_LBz5.h"
#include "Vpsp_cache__N4_Uz4_LBz6.h"
#include "Vpsp_cache__N8_Uz7_LBz8.h"

// Refresh cache window
gint cache_viewer_callback (gpointer data);

// Activate the cache window
void cache_viewer_gtk_activate(GtkApplication *app);

// Typedef away the Verilator cache class names
typedef Vpsp_cache__N4_Uz3_LBz5 dcache_t;
typedef Vpsp_cache__N4_Uz4_LBz6 icache_t;
typedef Vpsp_cache__N8_Uz7_LBz8 l2_cache_t;

#define CACHE_WINDOW_REFRESH_QUANTUM 30

#define CACHE_WINDOW_W ((640))
#define CACHE_WINDOW_H ((480))

#define N_WAYS_L1 4
#define N_WAYS_L2 8
#define N_SETS 16
#define PSP_LINE_BYTES 64

#define CACHE_LINE_BOX_W 8
#define CACHE_LINE_BOX_H 8

// Cache coherence states
typedef enum {
    CACHE_INVALID    = 0,     // Invalid line
    CACHE_MODIFIED   = 1,     // Modified line
    CACHE_SHARED     = 2      // Shared line (unmodified, read only)
} cache_line_state_t;

#endif // USE_CACHES

#endif // CACHE_VIEWER_H
