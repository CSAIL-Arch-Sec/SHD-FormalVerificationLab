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
 * Bitmapped graphics RAM
 * Designed for 640 by 480 @ 32 bits per pixel graphics running in simulation
 * Joseph Ravichandran
 * March 2, 2021
 */

module graphics
    (
        // Write-only port to graphics memory
        mem_if.bus graphics_write_port,

        // Write-only port to text RAM
        // Presented as an overlay of ASCII chars over the main screen
        mem_if.bus vram_text_write_port,

        input logic reset, clk
    );
    /* verilator public_module */

    logic[31:0] videoram[(640*480)-1:0];
    logic[7:0] textram[(80*32)-1:0];

    always_ff @ (posedge clk) begin
        if (graphics_write_port.write_en) begin
            // $display("[graphics] Writing %x to %x", graphics_write_port.data_i, graphics_write_port.addr);
            videoram[(graphics_write_port.addr)] <= graphics_write_port.data_i;
        end

        if (vram_text_write_port.write_en) begin
            textram[(vram_text_write_port.addr)] <= vram_text_write_port.data_i;
        end
    end

endmodule
