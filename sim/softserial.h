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

// Softserial is the simulator name for the CSR-based serial port
// This device is controlled via polling and synchronized reads / writes to a CSR

#ifndef SOFTSERIAL_H
#define SOFTSERIAL_H

#include "config.h"

// Flags register:
#define SOFTSERIAL_FLAGS_CSR 0x200
// Into CPU:
#define SOFTSERIAL_IO_CSR_IN 0x201
// Out from CPU:
#define SOFTSERIAL_IO_CSR_OUT 0x202

// Possible values for the SOFTSERIAL_FLAGS_CSR
// Clear == ready for new data, Waiting == processor has yet to read some data
#define SOFTSERIAL_FLAGS_CLEAR 0
#define SOFTSERIAL_FLAGS_WAITING 1

// Simulator-side loop to wait for stdio input
void softserial_do_io(void);

// How many usec should the softserial thread wait for the simulated device (on the simulator thread)
// to continue before retrying to lock the core and issue a new serial byte?
#define SOFTSERIAL_POLL_PERIOD 100

#endif // SOFTSERIAL_H
