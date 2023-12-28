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

// Parametric memory interface converters for Pretty Secure Processor system
`include "defines.sv"
`include "memory_if.sv"

/*
 * short_to_long_coupler
 * Converts a 32 bit memory interface to a larger memory interface.
 * Use this to attach PSP memory ports to cache memory ports.
 *
 * ASSUMPTION: LINE_BYTES >= 4.
 */
module short_to_long_coupler
    #(
        parameter LINE_BYTES=64
    )
    (
        // This interface better have LINE_BYTES == 4
        mem_if.bus short_in_if,

        // This interface better have LINE_BYTES == #LINE_BYTES as specified by the module parameter!
        mem_if.driver long_out_if,

        input logic reset, clk
    );

    // Size of addresses in bytes:
    parameter ADDRESS_SIZE = 32;

    // Number of address bits excluded due to the line:
    parameter LINE_SIZE = $clog2(LINE_BYTES);

    // Current set, tag, and line offset
    // old_offset is the offset of the previous request
    // old_offset is needed so that this reports the correct 4 byte slice of the returned line
    logic [LINE_SIZE-1:0] offset, old_offset;

    assign offset = short_in_if.addr[LINE_SIZE-1:0];

    initial begin
        // Ensure that the ports fit
        assert($bits(short_in_if.data_i) == 32);
        assert($bits(short_in_if.data_o) == 32);
        assert($bits(short_in_if.data_en) == 4);

        assert($bits(long_out_if.data_i) == 8*LINE_BYTES);
        assert($bits(long_out_if.data_o) == 8*LINE_BYTES);
        assert($bits(long_out_if.data_en) == LINE_BYTES);
    end

    // Map short_in_if <-> long_out_if
    always_comb begin
        // Mask off the long_out_if bits that are just offsets into the line
        long_out_if.addr = short_in_if.addr & {{(ADDRESS_SIZE-LINE_SIZE){1'b1}}, {LINE_SIZE{1'b0}}};

        // Data in is the data in shifted by offset
        long_out_if.data_i = short_in_if.data_i << 8 * offset;

        // Data enable is the data enabled shifted by offset
        long_out_if.data_en = short_in_if.data_en << offset;

        long_out_if.write_en = short_in_if.write_en;
        long_out_if.read_en = short_in_if.read_en;

        // Shift data back down by old offset
        short_in_if.data_o = long_out_if.data_o >> 8 * old_offset;

        short_in_if.hit = long_out_if.hit;
        short_in_if.done = long_out_if.done;
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            old_offset <= 0;
        end
        else begin
            if (short_in_if.read_en || short_in_if.write_en)
                old_offset <= offset;
        end
    end

endmodule // short_to_long_coupler
