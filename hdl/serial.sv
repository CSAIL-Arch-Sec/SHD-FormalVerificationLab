/*
 * Pretty Secure System
 * Joseph Ravichandran
 * Additions to Pretty Secure System (PSP-NG) for MIT Secure Hardware Design
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

/*
 * serial
 *
 * For those who are too cool for framebuffer/ vga graphics...
 */

`include "defines.sv"
`include "memory_if.sv"

module serial(
    // Write port to the serial device
    mem_if.bus mem_in_port,

    // Bounds check server (to tell corresponding ring stop when to accept packets)
    mem_bounds.server bounds_checker,

    input logic reset, clk
);

    // Stored serial character
    logic[7:0] charbuf;

    // Bounds checker request is valid in a different cycle than the memory line
    // Keep a second combinatorial signal around for knowing when we are responding to a valid
    // memory transaction (not just acknowledging a bus transaction on the bounds checker server modport)
    logic mem_req_in_bounds;

    // Check if this request lives within the bounds of this memory peripheral
    assign bounds_checker.in_bounds = (bounds_checker.check_addr >= SERIAL_MEM_BASE)
                                && (bounds_checker.check_addr < SERIAL_MEM_BASE + SERIAL_MEM_SIZE);

    // Handle the memory requests (recall that these are a separate cycle than the bounds check requests)
    // We should treat the memory read/ writes as an adjacent server to the bounds check requests
    assign mem_req_in_bounds = (mem_in_port.addr >= SERIAL_MEM_BASE)
                                && (mem_in_port.addr < SERIAL_MEM_BASE + SERIAL_MEM_SIZE);
    always_comb begin
        mem_in_port.hit = 0;
        if ((mem_in_port.write_en || mem_in_port.read_en) && mem_req_in_bounds) begin
            // @ASSUMPTION: Single cycle read/ writes!
            // (Fair assumption as serial is a register-based MMIO device)
            mem_in_port.hit = 1;
        end
    end

    always_ff @(posedge clk) begin
        if (mem_in_port.write_en && mem_req_in_bounds) begin
            charbuf <= mem_in_port.data_i[7:0];
            $write("%c", mem_in_port.data_i[7:0]);
        end
    end

    // Done is just hit delayed by a cycle
    always_ff @ (posedge clk) begin
        mem_in_port.done <= mem_in_port.hit;
    end

endmodule : serial
