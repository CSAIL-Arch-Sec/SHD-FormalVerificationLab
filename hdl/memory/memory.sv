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

/*
 * memory
 * Dual-port BRAM backed main memory for instructions & data
 *
 * Parameters:
 * MEM_SIZE- number of bytes in RAM
 * MEM_WIDTH- width of data interface
 *
 * Addresses are log base 2 of MEM_SIZE bytes wide. The lower 2 bits
 * are ignored by this module. The data enable signals are respected
 * and are relative to the address modulo 4.
 *
 * So if you read from address 6 for example, with a width of 32 bits
 * you will receive [byte 4, byte 5, byte 6, byte 7] and data enable pins
 * will operate on those bytes. 
 *
 * (You will NOT get something like [byte 6, byte 7, byte 8, byte 9]).
 */
`include "defines.sv"

module memory
    #(
        // Max aligned address will be 1/4 this:
        parameter MEM_SIZE=MAIN_RAM_SIZE,
        parameter MEM_FILE=MEMORY_FILE
        // 8192 has max aligned address of 2048
    )
    (
        // Port A (READONLY)
        input logic [$clog2(MEM_SIZE)-1:0] addr_a,
        output logic [31:0] data_o_a,
        input logic read_en_a,
        output logic hit_a, done_a,

        // Port B
        input logic [$clog2(MEM_SIZE)-1:0] addr_b,
        input logic [31:0] data_i_b,
        output logic [31:0] data_o_b,
        input logic [3:0] data_en_b,
        input logic write_en_b,
        input logic read_en_b,
        output logic hit_b, done_b,

        // Turn this on to enable tracing on data port (port B)
        input logic enable_tracing,

        input logic reset,
        input logic clk
    );
    /*verilator public_module*/

    // @TODO: Support arbitrary MEM_WIDTH
    // Use BRAM supported byte enable signals
    logic [31:0] ram [(MEM_SIZE/4)-1:0];

    // Strip off 2 lower bits from input addresses:
    logic [$clog2(MEM_SIZE)-3:0] addr_a_aligned, addr_b_aligned;
    assign addr_a_aligned = addr_a >> 2;
    assign addr_b_aligned = addr_b >> 2;

    initial begin
        $readmemh(MEM_FILE, ram);
    end

    // I wonder what happens if both ports try to write to the same address at the same time... Hmm

    always @ (posedge clk) begin
        // Port A (readonly)
        if (read_en_a)
            data_o_a <= ram[addr_a_aligned];
        else
            data_o_a <= 32'hx;
    end

    always @ (posedge clk) begin
        // Port B
        if (write_en_b) begin
            if(data_en_b[0]) ram[addr_b_aligned][7:0] <= data_i_b[7:0];
            if(data_en_b[1]) ram[addr_b_aligned][15:8] <= data_i_b[15:8];
            if(data_en_b[2]) ram[addr_b_aligned][23:16] <= data_i_b[23:16];
            if(data_en_b[3]) ram[addr_b_aligned][31:24] <= data_i_b[31:24];
        end

        if (read_en_b) begin
            data_o_b <= ram[addr_b_aligned];

            if (enable_tracing)
                $display("%x is %x", addr_b, ram[addr_b_aligned]);
        end
        else
            data_o_b <= 32'hx;
    end

    assign hit_a = 1;
    assign hit_b = 1;
    always_ff @ (posedge clk) begin
        if (reset) begin
            done_a <= 0;
            done_b <= 0;
        end
        else begin
            if (read_en_a) done_a <= 1;
            else done_a <= 0;

            if (write_en_b || read_en_b) done_b <= 1;
            else done_b <= 0;
        end
    end

endmodule // memory
