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

#include "config.h"
#ifdef USE_INTERCONNECT

#include "interconnect_viewer.h"
#include "graphics.h"
#include "font.h"
#include "interconnect_background.h"
#include "psp.h"
#include "Vpsp.h"
#include "Vpsp_psp.h"
#include "Vpsp_psp_system.h"
#include "Vpsp_ring_stop.h"
#include "Vpsp_ring_to_mem__Lz1.h"
#include "Vpsp_mem_to_ring__N9_Rz1.h"
#include <stdlib.h>



static uint8_t ic_window[IC_WINDOW_W*IC_WINDOW_H*3];
static GtkWidget *ic_window_object;
static GtkWidget *ic_window_widget;
static GdkPixbuf *ic_window_pixbuf;

// There are extra ones for offloading network latency but we only have 4 with inputs/ outputs
#define NUM_RING_STOPS 4
static Vpsp_ring_stop *ring_stops[NUM_RING_STOPS];

static Vpsp_mem_to_ring__N9_Rz1 *core_injectors[NUM_CORES];
static Vpsp_ring_to_mem__Lz1 *llc_injector, *graphics_injector;

extern PrettySecureProcessor *psp_system;

static inline void draw_px(int x, int y, int color) {
    if (x < IC_WINDOW_W && y < IC_WINDOW_H) {
        ic_window[(3*(x+(y*640)))+0] = (color >> 16) &  0x0ff;
        ic_window[(3*(x+(y*640)))+1] = (color >> 8)  &  0x0ff;
        ic_window[(3*(x+(y*640)))+2] = (color >> 0)  &  0x0ff;
    }
}

static inline void draw_rect_filled_in(int x, int y, int w, int h, int color) {
    for (int i = x; i < x + w; i++) {
        for (int j = y; j < y + h; j++) {
            draw_px(i, j, color);
        }
    }
}

static inline void draw_rect_outline(int x, int y, int w, int h, int color) {
    for (int i = x; i < x + w; i++) {
        draw_px(i, y, color);
    }
    for (int i = x; i < x + w; i++) {
        draw_px(i, y+h-1, color);
    }
    for (int j = y; j < y + h; j++) {
        draw_px(x, j, color);
    }
    for (int j = y; j < y + h; j++) {
        draw_px(x+w-1, j, color);
    }
}

/*
 * draw_char
 * Draw a character to the screen
 * Coords are in VGA-space: x is screen position / 8, y is screen position / 16
 */
static inline void draw_char(int x, int y, char c, uint32_t col) {
    for (int j = 0; j < 16; j++) {
        uint8_t bitvector = vgafont16[(c * 16) + j];
        for (int i = 0; i < 8; i++) {
            if ((1 & (bitvector >> (8-i))) != 0) {
                draw_px((8*x)+i, (16*y)+j, col);
            }
        }
    }
}

/*
 * draw_string
 * Draw a string to video RAM
 */
static inline void draw_string(int x, int y, char *str, uint32_t col) {
    size_t len = strlen(str);
    for (int i = 0; i < len; i++) {
        draw_char(x+i, y, str[i], col);
    }
}

static inline bool in_bounds(int x, int y, rect_t r) {
    return ((x > r.x) && (x < r.x + r.w) && (y > r.y) && (y < r.y + r.h));
}

void replace_color (uint32_t findcol, uint32_t replcol) {
    for (int i = 0; i < IC_WINDOW_W; i++) {
        for (int j = 0; j < IC_WINDOW_H; j++) {
            int idx = i+(j*IC_WINDOW_W);

            int source_r = ic_window[3*idx+0];
            int source_g = ic_window[3*idx+1];
            int source_b = ic_window[3*idx+2];

            int findcol_r = 0x0ff & (findcol >> 16);
            int findcol_g = 0x0ff & (findcol >> 8);
            int findcol_b = 0x0ff & (findcol);

            int replcol_r = 0x0ff & (replcol >> 16);
            int replcol_g = 0x0ff & (replcol >> 8);
            int replcol_b = 0x0ff & (replcol);

            if (source_r == findcol_r && source_g == findcol_g && source_b == findcol_b) {
                ic_window[3*idx+0] = replcol_r;
                ic_window[3*idx+1] = replcol_g;
                ic_window[3*idx+2] = replcol_b;
            }
        }
    }
}

/*
 * draw_ic_window
 * Draws the ic window
 */
void draw_ic_window(void) {
    draw_rect_filled_in(0, 0, IC_WINDOW_W, IC_WINDOW_H, 0x4444444);

    // Copy background over
    for (int i = 0; i < IC_WINDOW_W; i++) {
        for (int j = 0; j < IC_WINDOW_H; j++) {
            ic_window[3*(i+(j*IC_WINDOW_W))+0] = ic_background[3*(i+(j*IC_WINDOW_W))+0];
            ic_window[3*(i+(j*IC_WINDOW_W))+1] = ic_background[3*(i+(j*IC_WINDOW_W))+1];
            ic_window[3*(i+(j*IC_WINDOW_W))+2] = ic_background[3*(i+(j*IC_WINDOW_W))+2];
        }
    }

    uint32_t active_color = 0xffffff;
    uint32_t inactive_color = 0x000000;

    uint32_t ring_stop_colors[NUM_RING_STOPS];

    for (int i = 0; i < NUM_RING_STOPS; i++) {
        ring_stop_colors[i] = ring_stops[i]->is_active ? active_color : inactive_color;
    }

    uint32_t core_colors[NUM_CORES];
    for (int i = 0; i < NUM_CORES; i++) {
        core_colors[i] = core_injectors[i]->state != 0 ? active_color : inactive_color;
    }

    // Color specific components
    replace_color(CORE0_COLOR, core_colors[0] == inactive_color ? 0 : CORE0_COLOR);
    replace_color(CORE1_COLOR, core_colors[1] == inactive_color ? 0 : CORE1_COLOR);
    replace_color(RS0_COLOR, ring_stop_colors[0]);
    replace_color(RS1_COLOR, ring_stop_colors[1]);
    replace_color(RS2_COLOR, ring_stop_colors[2]);
    replace_color(RS3_COLOR, ring_stop_colors[3]);
    replace_color(LLC_COLOR, llc_injector->state != 0 ? active_color : inactive_color);
}

/*
 * ic_viewer_callback
 * Refresh ic viewer GTK window
 */
gint ic_viewer_callback (gpointer data) {
    draw_ic_window();
    gtk_image_set_from_pixbuf((GtkImage *)ic_window_widget, ic_window_pixbuf);
    gtk_widget_queue_draw(ic_window_object);
    g_timeout_add(IC_WINDOW_REFRESH_QUANTUM, ic_viewer_callback, 0);

    return 0;
}

// Activate ic window
void ic_viewer_gtk_activate(GtkApplication *app) {

    // @TODO: Find a way to fix Verilator name mangling
    // @TODO: Check that these indeces are still correct after Jan 25 2023 adding extra injectors to each core.
    // (For now, the interconnect viewer is considered depreacated)
    ring_stops[0] = psp_system->sys->psp->dut->mem_ring_itfs_gen__BRA__0__KET____DOT__stop_inst;
    ring_stops[1] = psp_system->sys->psp->dut->mem_ring_itfs_gen__BRA__1__KET____DOT__stop_inst;
    ring_stops[2] = psp_system->sys->psp->dut->mem_ring_itfs_gen__BRA__2__KET____DOT__stop_inst;
    ring_stops[3] = psp_system->sys->psp->dut->mem_ring_itfs_gen__BRA__3__KET____DOT__stop_inst;
    // Jan 25 2023: Added a second injector for each core, vertial memory injector is the lower indexed one,
    // and a new uncacheable request injector has been added alongside them.
    core_injectors[0] = psp_system->sys->psp->dut->core_m2r_couplers__BRA__0__KET____DOT__m2r_inst;
    core_injectors[1] = psp_system->sys->psp->dut->core_m2r_couplers__BRA__2__KET____DOT__m2r_inst;
    llc_injector = psp_system->sys->psp->dut->mem_r2m_couplers__BRA__4__KET____DOT__r2m_inst;
    graphics_injector = psp_system->sys->psp->dut->mem_r2m_couplers__BRA__5__KET____DOT__r2m_inst;

    draw_ic_window();
    ic_window_pixbuf = gdk_pixbuf_new_from_data(
            (guchar *)ic_window,
            GDK_COLORSPACE_RGB,
            false, // no alpha
            8, // 8 bits per color sample
            IC_WINDOW_W,
            IC_WINDOW_H,
            3 * IC_WINDOW_W, // Row length
            NULL, // Destructor for image data
            0
        );

    ic_window_widget = gtk_image_new_from_pixbuf(ic_window_pixbuf);

    ic_window_object = gtk_application_window_new(app);
    gtk_window_set_title (GTK_WINDOW(ic_window_object), "Ring Interconnect Viewer");
    gtk_window_set_default_size (GTK_WINDOW(ic_window_object), IC_WINDOW_W, IC_WINDOW_H);

    gtk_container_add(GTK_CONTAINER(ic_window_object), ic_window_widget);

    gtk_widget_show_all(ic_window_object);
}

#endif // USE_INTERCONNECT
