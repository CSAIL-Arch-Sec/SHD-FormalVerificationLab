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

/*
 * mem_to_graphics
 * An adapter port for converting a CACHE_LINE_BYTES wide memory interface to talk to graphics
 */
module mem_to_graphics
    (
        // Either full graphics or text overlay addresses:
        mem_if.bus mem_in_port,

        mem_bounds.server bounds_checker,

        // Output ports to graphics and text overlay RAM
        mem_if.driver graphics_write_port,
        mem_if.driver vram_text_write_port,

        input logic reset, clk
    );

    logic in_graphics_mem, in_text_mem;

    // Use these to check the bounds address (done the cycle before ring 2 mem gives us the official request)
    logic bounds_checker_in_graphics_mem, bounds_checker_in_text_mem;

    always_comb begin
        in_graphics_mem = (mem_in_port.addr >= GRAPHICS_MEM_BASE)
                                    && (mem_in_port.addr < GRAPHICS_MEM_BASE + GRAPHICS_MEM_SIZE);
        in_text_mem = (mem_in_port.addr >= TFT_MEM_BASE)
                                    && (mem_in_port.addr < TFT_MEM_BASE + TFT_MEM_SIZE);

        // Framebuffer graphics port
        graphics_write_port.addr = (mem_in_port.addr - GRAPHICS_MEM_BASE) >> 2;
        graphics_write_port.data_i = mem_in_port.data_i[31:0];
        graphics_write_port.data_en = 0;
        graphics_write_port.write_en = mem_in_port.write_en & in_graphics_mem;
        graphics_write_port.read_en = 0;

        // Text-mode graphics port
        vram_text_write_port.write_en = mem_in_port.write_en & in_text_mem;

        case (mem_in_port.data_en[3:0])
            4'b0001: vram_text_write_port.data_i = mem_in_port.data_i;
            4'b0010: vram_text_write_port.data_i = mem_in_port.data_i >> 8;
            4'b0100: vram_text_write_port.data_i = mem_in_port.data_i >> 16;
            4'b1000: vram_text_write_port.data_i = mem_in_port.data_i >> 24;
            default: vram_text_write_port.data_i = mem_in_port.data_i;
        endcase

        case (mem_in_port.data_en[3:0])
            4'b0001: vram_text_write_port.addr = mem_in_port.addr - TFT_MEM_BASE;
            4'b0010: vram_text_write_port.addr = mem_in_port.addr - TFT_MEM_BASE + 1;
            4'b0100: vram_text_write_port.addr = mem_in_port.addr - TFT_MEM_BASE + 2;
            4'b1000: vram_text_write_port.addr = mem_in_port.addr - TFT_MEM_BASE + 3;
            default: vram_text_write_port.addr = mem_in_port.addr - TFT_MEM_BASE;
        endcase

        // Default reply
        mem_in_port.hit = 0;

        // Forward responses back up
        if ((mem_in_port.write_en || mem_in_port.read_en) && (in_graphics_mem || in_text_mem)) begin
            // @ASSUMPTION: Single cycle writes!
            mem_in_port.hit = 1;
        end
    end

    // Check bounds
    // This will probably create a horrible critical path- we should add a separate bounds checking state here or something
    // This works great for simulation though
    always_comb begin
        bounds_checker_in_graphics_mem = (bounds_checker.check_addr >= GRAPHICS_MEM_BASE)
                                    && (bounds_checker.check_addr < GRAPHICS_MEM_BASE + GRAPHICS_MEM_SIZE);
        bounds_checker_in_text_mem = (bounds_checker.check_addr >= TFT_MEM_BASE)
                                    && (bounds_checker.check_addr < TFT_MEM_BASE + TFT_MEM_SIZE);

        bounds_checker.in_bounds = (bounds_checker_in_text_mem || bounds_checker_in_graphics_mem);
    end

    always_ff @ (posedge clk) begin
        mem_in_port.done <= mem_in_port.hit;
    end

endmodule // mem_to_graphics
