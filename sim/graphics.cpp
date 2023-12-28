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

#include "graphics.h"
#include "psp.h"
#include "cache_viewer.h"
#include "interconnect_viewer.h"
#include "font.h"

// Image in GTK format
static uint8_t gtk_image_buf[SCREEN_WIDTH*SCREEN_HEIGHT*3];

// Video RAM inside processor system:
extern uint32_t *psp_video_ram;

// Text overlay RAM inside processor system:
extern char *psp_text_overlay_ram;

// Processor simulation handle (mostly non thread-safe, do not call any simulation methods here)
extern PrettySecureProcessor *psp_system;

static GtkWidget *window;
static GtkWidget *image_widget;
static GdkPixbuf *image_pixbuf;

/*
 * draw_char
 * Draw a character to the screen
 * Coords are in VGA-space: x is screen position / 8, y is screen position / 16
 */
void draw_char(uint8_t *screen_buf, int x, int y, char c, uint32_t col) {
    for (int j = 0; j < FONT_CHAR_H; j++) {
        uint8_t bitvector = vgafont16[(c * FONT_CHAR_H) + j];
        for (int i = 0; i < FONT_CHAR_W; i++) {
            if ((1 & (bitvector >> (FONT_CHAR_W-i))) != 0) {
                uint32_t screen_x = (FONT_CHAR_W * x) + i;
                uint32_t screen_y = (FONT_CHAR_H * y) + j;

                uint32_t screen_idx = (3*(screen_x+(screen_y*SCREEN_WIDTH)));
                screen_buf[screen_idx+0] = (col >> 16) &  0x0ff;
                screen_buf[screen_idx+1] = (col >> 8)  &  0x0ff;
                screen_buf[screen_idx+2] = (col >> 0)  &  0x0ff;
            }
        }
    }
}


// Convert image from PSP system -> GTK
void render_image(uint32_t *psp_image, char *psp_textram) {
    for (int i = 0; i < SCREEN_WIDTH; i++) {
        for (int j = 0; j < SCREEN_HEIGHT; j++) {
            gtk_image_buf[(3*(i+(j*SCREEN_WIDTH)))+0] = (psp_image[(i+(j*SCREEN_WIDTH))] >> 16) &  0x0ff;
            gtk_image_buf[(3*(i+(j*SCREEN_WIDTH)))+1] = (psp_image[(i+(j*SCREEN_WIDTH))] >> 8)  &  0x0ff;
            gtk_image_buf[(3*(i+(j*SCREEN_WIDTH)))+2] = (psp_image[(i+(j*SCREEN_WIDTH))] >> 0)  &  0x0ff;
        }
    }

    // Draw the text mode overlay
    for (int i = 0; i < TEXT_OVERLAY_NUM_COLUMNS; i++) {
        for (int j = 0; j < TEXT_OVERLAY_NUM_ROWS; j++) {
            if (psp_textram[i+(j*TEXT_OVERLAY_NUM_COLUMNS)] != 0) {
                draw_char(gtk_image_buf, i, j, psp_textram[i+(j*TEXT_OVERLAY_NUM_COLUMNS)], 0x00ffffff);
            }
        }
    }
}

/*
 * render_image_callback
 * Periodically called by GTK, use this as an opportunity to refresh the screen.
 */
gint render_image_callback (gpointer data) {
    render_image(psp_video_ram, psp_text_overlay_ram);
    gtk_image_set_from_pixbuf((GtkImage *)image_widget, image_pixbuf);
    gtk_widget_queue_draw(window);
    g_timeout_add(IMAGE_REFRESH_QUANTUM, render_image_callback, 0);

    return 0;
}

/*
 * keypress_callback
 * Handle a key press
 */
gint keypress_callback (GtkWidget *widget, GdkEventKey *event, gpointer data) {
    char code_to_send = (char) *event->string;

    // Newline correction
    if (code_to_send == 0x0d) code_to_send = 0x0a;

    // printf("Keycode %x\n", code_to_send);
    if (psp_system != NULL) {
        psp_system->schedule_interrupt(code_to_send);
    }
    return 0;
}

// Activate GTK app and render snapshot of terminal screen
static void gtk_activate(GtkApplication *app, gpointer user_data) {
    // Launch other windows than the main framebuffer:
#ifdef USE_CACHES
    cache_viewer_gtk_activate(app);
#endif

#ifdef USE_INTERCONNECT
    ic_viewer_gtk_activate(app);
#endif

    // Launch main framebuffer:
    render_image(psp_video_ram, psp_text_overlay_ram);

    image_pixbuf = gdk_pixbuf_new_from_data(
            (guchar *)gtk_image_buf,
            GDK_COLORSPACE_RGB,
            false, // no alpha
            8, // 8 bits per color sample
            640,
            480,
            3 * 640, // Row length
            NULL, // Destructor for image data
            0
        );

    image_widget = gtk_image_new_from_pixbuf(image_pixbuf);

    window = gtk_application_window_new(app);
    gtk_window_set_title (GTK_WINDOW(window), "Pretty Secure Processor");
    gtk_window_set_default_size (GTK_WINDOW(window), 640, 480);

    gtk_container_add(GTK_CONTAINER(window), image_widget);

    // Setup keyboard handler (for issuing interrupts)
    // More info: https://stackoverflow.com/questions/44098084/how-do-i-handle-keyboard-events-in-gtk3
    // More info: https://developer.gnome.org/gtk-tutorial/stable/x182.html
    gtk_widget_add_events(window, GDK_KEY_PRESS_MASK);
    g_signal_connect(G_OBJECT(window), "key_press_event", G_CALLBACK(keypress_callback), NULL);

    gtk_widget_show_all(window);
}

// Launch GTK system
int psp_gtk_main () {
    GtkApplication *app;
    int status;

    app = gtk_application_new("org.jprx.psp_simulator", G_APPLICATION_FLAGS_NONE);
    g_signal_connect(app, "activate", G_CALLBACK(gtk_activate), NULL);

    // Launch windows refresh callbacks:
    g_timeout_add(IMAGE_REFRESH_QUANTUM, render_image_callback, 0);
#ifdef USE_CACHES
    g_timeout_add(IMAGE_REFRESH_QUANTUM, cache_viewer_callback, 0);
#endif

#ifdef USE_INTERCONNECT
    g_timeout_add(IMAGE_REFRESH_QUANTUM, ic_viewer_callback, 0);
#endif

    status = g_application_run(G_APPLICATION(app), 0, NULL);
    g_object_unref(app);

    return status;
}

#endif // !MITSHD_LAB6
