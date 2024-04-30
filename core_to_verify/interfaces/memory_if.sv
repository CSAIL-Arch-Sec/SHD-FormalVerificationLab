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

`ifndef MEMORY_IF
`define MEMORY_IF

/*
 * mem_if
 *
 * An interface connecting a synchronous memory bus.
 */
interface mem_if #(
        parameter LINE_BYTES=4 // How many bytes per line
    );

    logic [31:0] addr; // This must be aligned to LINE_BYTES
    logic [8*LINE_BYTES-1:0] data_i; // Data in
    logic [8*LINE_BYTES-1:0] data_o; // Data out
    logic [LINE_BYTES-1:0] data_en; // Data enable bit vector
    logic write_en, read_en; // Read/ Write commands

    // Will this address's value be ready NEXT cycle?
    // This what, whatever asserted address knows whether or not data WILL be valid next cycle
    logic hit;

    // This is hit, delayed by a single cycle
    logic done;

    // Connect this to the device using the bus
    modport driver (
        input data_o, hit, done,
        output addr, data_i, data_en, write_en, read_en
    );

    // Connect this to the memory module
    modport bus (
        input addr, data_i, data_en, write_en, read_en,
        output data_o, hit, done
    );

endinterface

/*
 * mem_bounds
 * An interface representing a bounded memory region
 */
interface mem_bounds ();
    logic[31:0] check_addr;
    logic in_bounds;

    // The one who determines in_bounds
    modport server (
        output in_bounds,
        input check_addr
    );

    // The one who receives in_bounds
    modport client (
        input in_bounds,
        output check_addr
    );

endinterface // mem_bounds

`endif // MEMORY_IF
