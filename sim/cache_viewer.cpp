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

#ifndef MITSHD_LAB6

#include "cache_viewer.h"
#include "graphics.h"
#include "font.h"
#include "psp.h"
#include "Vpsp.h"
#include "Vpsp_psp.h"
#include "Vpsp_psp_system.h"
#include "Vpsp_psp_single_core__Vz1_Uz1.h"
#include <math.h> // For log2

#ifdef USE_CACHES

static uint8_t cache_window[CACHE_WINDOW_W*CACHE_WINDOW_H*3];
static GtkWidget *cache_window_object;
static GtkWidget *cache_window_widget;
static GdkPixbuf *cache_window_pixbuf;

static icache_t *icache = NULL;
static dcache_t *dcache = NULL;
static l2_cache_t *l2 = NULL;

extern PrettySecureProcessor *psp_system;

static rect_t mouse;

// How many bits to shift the tag by before indexing into color table
#define DOMAIN_TAG_SHIFT_AMOUNT 4

char cache_line_state_strings[3][16] = {
    "Invalid",
    "Modified",
    "Shared"
};

uint32_t color_lut[8] = {
    0xff00ff,
    0x00ff00,
    0x00ffff,
    0xffff00,
    0xff0000,
    0x0000ff,
    0xffffff,
    0x888888
};

static inline void draw_px(int x, int y, int color) {
    if (x < CACHE_WINDOW_W && y < CACHE_WINDOW_H) {
        cache_window[(3*(x+(y*640)))+0] = (color >> 16) &  0x0ff;
        cache_window[(3*(x+(y*640)))+1] = (color >> 8)  &  0x0ff;
        cache_window[(3*(x+(y*640)))+2] = (color >> 0)  &  0x0ff;
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

/*
 * draw_cache_window
 * Draws a cache window and populates it with all lines
 */
template <typename xcache_t>
static inline void draw_cache_window (xcache_t *xcache, rect_t bounds, char *title, int n_sets, int n_ways) {
    int selected_set = 0;
    int selected_way = 0;
    bool something_selected = false;

    uint32_t set_shift_amount = (uint32_t)(log2(PSP_LINE_BYTES));
    uint32_t tag_shift_amount = (uint32_t)(log2(n_sets) + set_shift_amount);

    draw_rect_outline(bounds.x, bounds.y, bounds.w, bounds.h, 0xffffff);
    draw_string((bounds.x)/8, (bounds.y + bounds.h)/16, title, 0xffffff);

    for (int cur_set = 0; cur_set < n_sets; cur_set++) {
        for (int cur_way = 0; cur_way < n_ways; cur_way++) {
            uint32_t color_bit = (uint32_t)xcache->tags[cur_set][cur_way] >> DOMAIN_TAG_SHIFT_AMOUNT;

            if ((uint32_t)xcache->tags[cur_set][cur_way] > 0x2000) color_bit = 4;
            else color_bit = 1;

            rect_t box_bounds = {
                .x = (bounds.x + 4) + cur_way * 2 * CACHE_LINE_BOX_H,
                .y = 20 + cur_set * 2 * CACHE_LINE_BOX_W,
                .w = CACHE_LINE_BOX_W,
                .h = CACHE_LINE_BOX_H
            };

            if (in_bounds(mouse.x, mouse.y, box_bounds)) {
                draw_rect_filled_in(
                    box_bounds.x - 3,
                    box_bounds.y - 3,
                    box_bounds.w + 6,
                    box_bounds.h + 6,
                    0xffffff
                );

                something_selected = true;
                selected_set = cur_set;
                selected_way = cur_way;
            }

            switch ((cache_line_state_t)xcache->line_states[cur_set][cur_way]) {
                case CACHE_INVALID:
                    draw_rect_filled_in(
                        box_bounds.x,
                        box_bounds.y,
                        box_bounds.w,
                        box_bounds.h,
                        0
                    );
                break;

                case CACHE_MODIFIED:
                    draw_rect_outline(
                        box_bounds.x - 1,
                        box_bounds.y - 1,
                        box_bounds.w + 2,
                        box_bounds.h + 2,
                        0xffffff
                    );

                // NO BREAK- this case is both CACHE_MODIFIED and CACHE_SHARED
                case CACHE_SHARED:
                    draw_rect_filled_in(
                        box_bounds.x,
                        box_bounds.y,
                        box_bounds.w,
                        box_bounds.h,
                        color_lut[color_bit % 8]
                    );
                break;
            }
        }
    }

    char selected_string[64];

    if (something_selected) {
        uint32_t selected_tag = xcache->tags[selected_set][selected_way];
        uint32_t addr = (selected_tag << tag_shift_amount);
        addr |= selected_set << set_shift_amount;

        uint32_t color_bit = selected_tag >> DOMAIN_TAG_SHIFT_AMOUNT;

        if (selected_tag > 0x2000) color_bit = 4;
        else color_bit = 1;

        cache_line_state_t line_state = (cache_line_state_t)xcache->line_states[selected_set][selected_way];

        // Show info on the line
        draw_rect_outline(
            FONT_CHAR_W,
            19 * FONT_CHAR_H - (FONT_CHAR_H / 2),
            28 * FONT_CHAR_W,
            8 * FONT_CHAR_H,
            0xffffff
        );

        draw_rect_filled_in(
            FONT_CHAR_W + (26 * FONT_CHAR_W),
            19 * FONT_CHAR_H,
            8,
            8,
            line_state != CACHE_INVALID ? color_lut[color_bit % 8] : 0
        );

        draw_string(2, 19, (char *)"Selected Line", 0xaaaaaa);

        snprintf(selected_string, sizeof(selected_string), "addr: %x", addr);
        draw_string(2, 20, selected_string, 0xffffff);

        snprintf(selected_string, sizeof(selected_string), "tag: %x", selected_tag);
        draw_string(2, 21, selected_string, 0xffffff);

        snprintf(selected_string, sizeof(selected_string), "set: %x", selected_set);
        draw_string(2, 22, selected_string, 0xffffff);

        snprintf(selected_string, sizeof(selected_string), "domain: %x", selected_tag >> DOMAIN_TAG_SHIFT_AMOUNT);
        draw_string(2, 23, selected_string, 0xffffff);

        snprintf(selected_string, sizeof(selected_string), "status: %s", cache_line_state_strings[line_state]);
        draw_string(2, 24, selected_string, 0xffffff);

        snprintf(selected_string, sizeof(selected_string), "cache: %s", title);
        draw_string(2, 25, selected_string, 0xffffff);

        // Show all contents at that line
        draw_rect_outline(
            CACHE_WINDOW_W - (30 * FONT_CHAR_W),
            3 * FONT_CHAR_H/2,
            28 * FONT_CHAR_W,
            (2 + (PSP_LINE_BYTES / 4)) * FONT_CHAR_H,
            0xffffff
        );

        draw_string((CACHE_WINDOW_W / FONT_CHAR_W) - 29, 2, (char *)"Data", 0xaaaaaa);

        for (int word_counter = 0; word_counter < PSP_LINE_BYTES / 4; word_counter++) {
            snprintf(selected_string, sizeof(selected_string), "%08x: %08x",
                addr + 4 * word_counter,
                (uint32_t)xcache->ram[selected_set][selected_way][word_counter]
            );
            draw_string((CACHE_WINDOW_W / FONT_CHAR_W) - 29, 3 + word_counter, selected_string, 0xffffff);
        }
    }
}

/*
 * draw_cache_window
 * Draws the cache window
 */
void draw_cache_window(void) {
    draw_rect_filled_in(0, 0, CACHE_WINDOW_W, CACHE_WINDOW_H, 0x4444444);

    // Draw the background stuff:
    rect_t icache_rect = {.x = 16, .y = 16, .w = 16 * N_WAYS_L1, .h = 16 * N_SETS};
    rect_t dcache_rect = {.x = (16 + icache_rect.x + icache_rect.w), .y = (16), .w = (16 * N_WAYS_L1), .h = (16 * N_SETS)};
    rect_t l2_rect = {.x = (16 + dcache_rect.x + dcache_rect.w), .y = (16), .w = (16 * N_WAYS_L2), .h = (16 * N_SETS)};

    draw_cache_window <icache_t> (icache, icache_rect, (char *)"icache", N_SETS, N_WAYS_L1);
    draw_cache_window <dcache_t> (dcache, dcache_rect, (char *)"dcache", N_SETS, N_WAYS_L1);
    draw_cache_window <l2_cache_t> (l2, l2_rect, (char *)"l2", N_SETS, N_WAYS_L2);
}

/*
 * cache_viewer_callback
 * Refresh cache viewer GTK window
 */
gint cache_viewer_callback (gpointer data) {
    draw_cache_window();
    gtk_image_set_from_pixbuf((GtkImage *)cache_window_widget, cache_window_pixbuf);
    gtk_widget_queue_draw(cache_window_object);
    g_timeout_add(CACHE_WINDOW_REFRESH_QUANTUM, cache_viewer_callback, 0);

    return 0;
}

/*
 * cache_window_click
 * Handle mouse clicks
 */
gboolean cache_window_click (GtkWidget *cache_window_clicked, GdkEventButton *event, gpointer userdata) {
    int x_pos = (int)event->x;
    int y_pos = (int)event->y;

    mouse.x = x_pos;
    mouse.y = y_pos;

    return 1;
}

gboolean cache_viewer_keypress (GtkWidget *widget, GdkEventKey *event, gpointer data) {
    if (KEY_ARROW_LEFT == event->keyval) {
        if (mouse.x > KEY_CUSROR_QUANTUM)
            mouse.x -= KEY_CUSROR_QUANTUM;
    }

    if (KEY_ARROW_RIGHT == event->keyval) {
        if (mouse.x + KEY_CUSROR_QUANTUM < CACHE_WINDOW_W)
            mouse.x += KEY_CUSROR_QUANTUM;
    }

    if (KEY_ARROW_UP == event->keyval) {
        if (mouse.y > KEY_CUSROR_QUANTUM)
            mouse.y -= KEY_CUSROR_QUANTUM;
    }

    if (KEY_ARROW_DOWN == event->keyval) {
        if (mouse.y + KEY_CUSROR_QUANTUM < CACHE_WINDOW_H)
            mouse.y += KEY_CUSROR_QUANTUM;
    }

    return 1;
}

// Activate cache window
void cache_viewer_gtk_activate(GtkApplication *app) {
    icache = psp_system->sys->psp->dut->core0->l1i_cache;
    dcache = psp_system->sys->psp->dut->core0->l1d_cache;
    l2 = psp_system->sys->psp->dut->core0->l2_cache;

    draw_cache_window();
    cache_window_pixbuf = gdk_pixbuf_new_from_data(
            (guchar *)cache_window,
            GDK_COLORSPACE_RGB,
            false, // no alpha
            8, // 8 bits per color sample
            640,
            480,
            3 * 640, // Row length
            NULL, // Destructor for image data
            0
        );

    cache_window_widget = gtk_image_new_from_pixbuf(cache_window_pixbuf);

    cache_window_object = gtk_application_window_new(app);
    gtk_window_set_title (GTK_WINDOW(cache_window_object), "Cache Viewer");
    gtk_window_set_default_size (GTK_WINDOW(cache_window_object), 640, 480);

    gtk_container_add(GTK_CONTAINER(cache_window_object), cache_window_widget);

    // Setup mouse handler
    // See: https://stackoverflow.com/questions/23516968/g-signal-connect-for-right-mouse-click/23517810#23517810
    gtk_widget_add_events(cache_window_object, GDK_BUTTON_MOTION_MASK);
    g_signal_connect(
        G_OBJECT(cache_window_object),
        "button-press-event",
        G_CALLBACK(cache_window_click),
        NULL
    );

    // Setup keyboard handler
    gtk_widget_add_events(cache_window_object, GDK_KEY_PRESS_MASK);
    g_signal_connect(G_OBJECT(cache_window_object), "key_press_event", G_CALLBACK(cache_viewer_keypress), NULL);

    gtk_widget_show_all(cache_window_object);
}

#endif // USE_CACHES

#endif // !MITSHD_LAB6
