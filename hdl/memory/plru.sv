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

`include "defines.sv"
`include "memory_if.sv"

module plru
    #(parameter NUM_WAYS=4)
    (
        // MRU way = Most Recently Used way; we update the internal state whenever its used
        input logic[$clog2(NUM_WAYS)-1:0] mru_way,

        // LRU way = Combinatorially determined, least recently used way in the PLRU system
        output logic[$clog2(NUM_WAYS)-1:0] lru_way,

        // Set this to true whenever mru_way is valid (being accessed)
        input logic load_mru,
        input logic reset,
        input logic clk
    );

    // This is 1 bigger than it needs to be- index 0 is unused (makes math simpler)
    logic[NUM_WAYS:0] state;

    integer i, j, parent;

    always_comb begin
        // Determine lru according to state vector
        for (i = 1; i < NUM_WAYS; ) begin
            if (state[i] == 1) i = 2 * i + 1;
            else i = 2 * i;
        end
        lru_way = i - NUM_WAYS;
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= 0;
        end
        else begin
            if (load_mru) begin
                // Update state
                for (j = mru_way + NUM_WAYS; j > 0; ) begin
                    parent = $rtoi($floor(j / 2));
                    if (parent == 0) break;
                    if (j % 2 == 0) state[parent] <= 1'b1;
                    else state[parent] <= 1'b0;
                    j = parent;
                end
            end
        end
    end
endmodule // plru
