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

#ifndef CONFIG_H
#define CONFIG_H

// Global compilation configuration

// Comment this out to disable cache viewer:
// #define USE_CACHES

// Comment this out to disable interconnect viewer:
// #define USE_INTERCONNECT

// Comment this out to disable softserial ncurses:
#define USE_SOFTSERIAL

#define NUM_CORES 2


//------------------------------------------
// GTK defines for interfacing with keyboard
//------------------------------------------

// Found experimentally:
#define KEY_ARROW_LEFT 0xff51
#define KEY_ARROW_RIGHT 0xff53
#define KEY_ARROW_UP 0xff52
#define KEY_ARROW_DOWN 0xff54

// How many pixels does a keypress move the current mouse position?
#define KEY_CUSROR_QUANTUM 16

//----------------------------------
// Rectangles in screen coordinates
//----------------------------------
typedef struct rect_struct_t {
    int x;
    int y;
    int w;
    int h;
} rect_t;

#endif // CONFIG_H
