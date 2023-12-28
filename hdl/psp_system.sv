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
 * Joseph Ravichandran
 * December 6, 2020
 */
`include "memory_if.sv"
`include "rvfi_if.sv"
`include "defines.sv"

/*
 * psp_system
 * A pretty secure processor system.
 */
module psp_system
    (
        output logic [3:0] led,
        output logic[12:0] ar,
        input logic [3:0] btn,

        // Keyboard interrupts
        input logic keyboard_interrupt,
        input logic [7:0] keycode,

        input logic reset, clk
    );
    /*verilator public_module*/

// MIT SHD Lab 6: Don't Generate the Ring
`ifndef MITSHD_LAB6
    // IPI Interconnect
    // ipi_ring_inner is the in of ring stop if_idx, and the out of ring_stop if_idx - 1
    // There are only NUM_CORES stops on the IPI ring- this ring doesn't go to LLC slices / graphics server
    ring_if ipi_ring_inner[NUM_RING_STOPS]();
    ring_if ipi_ring_injector[NUM_RING_STOPS]();
    ring_if ipi_ring_stop_out[NUM_RING_STOPS]();
    generate
        for (genvar if_idx = 0; if_idx < NUM_CORES; if_idx++) begin : ipi_ring_itfs
            ring_stop stop_inst (
                .injector_port(ipi_ring_injector[if_idx]),
                .stop_out_port(ipi_ring_stop_out[if_idx]),

                .ring_in_port(ipi_ring_inner[if_idx]),
                .ring_out_port(ipi_ring_inner[(if_idx + 1) % NUM_CORES]),

                .ring_id(if_idx),

                .reset(reset),
                .clk(clk)
            );
        end : ipi_ring_itfs
    endgenerate

    // Memory Interconnect
    // This is the big bus that links all L2s to the shared LLC and graphics memory / serial port
    // See tb_ring_caches for a testbench for this style of ring
    // IDs 0->((2xNUM_CORES)-1) are cores, id 2xNUM_CORES to NUM_CORES + NUM_SERVERS - 1 is the memory server
    mem_if #(.LINE_BYTES(CACHE_LINE_BYTES)) mem_ring_itfs[NUM_RING_STOPS]();

    // These are only used by memory servers so that ring to mem knows when to not request from lower memory:
    mem_bounds mem_ring_bounds[NUM_RING_STOPS]();

    ring_if mem_ring_inner[NUM_RING_STOPS]();
    ring_if mem_ring_injector[NUM_RING_STOPS]();
    ring_if mem_ring_stop_out[NUM_RING_STOPS]();

    generate
        // All ring stops
        for (genvar if_idx = 0; if_idx < NUM_RING_STOPS; if_idx++) begin : mem_ring_itfs_gen
            ring_stop stop_inst (
                .injector_port(mem_ring_injector[if_idx]),
                .stop_out_port(mem_ring_stop_out[if_idx]),

                .ring_in_port(mem_ring_inner[if_idx]),
                .ring_out_port(mem_ring_inner[(if_idx + 1) % NUM_RING_STOPS]),

                .ring_id(if_idx),

                .reset(reset),
                .clk(clk)
            );
        end : mem_ring_itfs_gen

        // mem_to_ring couplers for each core (memory down to -> ring)
        for (genvar core_idx = 0; core_idx < 2*NUM_CORES; core_idx++) begin : core_m2r_couplers
            mem_to_ring #(.NUM_OTHER_RING_STOPS(NUM_RING_STOPS)) m2r_inst (
                .request_mem(mem_ring_itfs[core_idx]),
                .injector(mem_ring_injector[core_idx]),
                .receiver(mem_ring_stop_out[core_idx]),
                .core_id(core_idx),
                .reset(reset),
                .clk(clk)
            );
        end : core_m2r_couplers

        // ring_to_mem couplers for each memory server (ring down to -> memory)
        for (genvar mem_server_idx = 2*NUM_CORES; mem_server_idx < NUM_RING_STOPS; mem_server_idx++) begin : mem_r2m_couplers
            ring_to_mem r2m_inst (
                .lower_mem(mem_ring_itfs[mem_server_idx]),
                .bounds_checker(mem_ring_bounds[mem_server_idx]),
                .injector(mem_ring_injector[mem_server_idx]),
                .receiver(mem_ring_stop_out[mem_server_idx]),
                .core_id(mem_server_idx),
                .reset(reset),
                .clk(clk)
            );
        end : mem_r2m_couplers
    endgenerate

    // Cores
    // Only core0 can be debugged / receive interrupts!
    // Don't use generate loop on core0 as we need to access it directly from C++
    psp_single_core core0 (
        .vertical_mem_ring(mem_ring_itfs[0]),
        .uncacheable_mem_ring(mem_ring_itfs[1]),

        .ipi_injector(ipi_ring_injector[0]),
        .ipi_receiver(ipi_ring_stop_out[0]),

        .keyboard_interrupt(keyboard_interrupt),
        .keycode(keycode),

        .core_id(0),

        .reset(reset),
        .clk(clk)
    );

    // Can use generate loop on core1
    psp_single_core core1 (
        .vertical_mem_ring(mem_ring_itfs[2]),
        .uncacheable_mem_ring(mem_ring_itfs[3]),

        .ipi_injector(ipi_ring_injector[1]),
        .ipi_receiver(ipi_ring_stop_out[1]),

        .keyboard_interrupt(0),
        .keycode(0),

        .core_id(1),

        .reset(reset),
        .clk(clk)
    );

    // LLC
    mem_if #(.LINE_BYTES(CACHE_LINE_BYTES)) llc_mem_out(); // Goes to last level coupler
    mem_if #(.LINE_BYTES(4)) last_level_mem(); // Last level memory- talks right to RAM

    cache #(
        .NUM_WAYS(LLC_NUM_WAYS),
        .NUM_SETS(LLC_NUM_SETS),
        .LINE_BYTES(CACHE_LINE_BYTES)
    ) llc_slice0 (
        .upper(mem_ring_itfs[4]),
        .lower(llc_mem_out),

        .reset(reset),
        .clk(clk)
    );

    // always_comb begin
    //     if (mem_ring_itfs[2].read_en || mem_ring_itfs[2].write_en) begin
    //         $display("Xacting on LLC port");
    //     end
    // end

    // Check bounds for llc_slice0:
    assign mem_ring_bounds[4].in_bounds = (mem_ring_bounds[4].check_addr < MAIN_RAM_SIZE);

    // LLC <-> 32 Bit Physical RAM Interface
    long_to_short_coupler #(.LINE_BYTES(CACHE_LINE_BYTES)) last_level_coupler (
        .long_in_if(llc_mem_out),
        .short_out_if(last_level_mem),

        .reset(reset),
        .clk(clk)
    );

    // Physical RAM
    memory physical_ram (
        // Port A (READONLY)- Unused
        .addr_a(0),
        .data_o_a(),
        .read_en_a(0),
        .hit_a(),
        .done_a(),

        // Port B
        .addr_b(last_level_mem.addr),
        .data_i_b(last_level_mem.data_i),
        .data_o_b(last_level_mem.data_o),
        .data_en_b(last_level_mem.data_en),
        .write_en_b(last_level_mem.write_en),
        .read_en_b(last_level_mem.read_en),
        .hit_b(last_level_mem.hit),
        .done_b(last_level_mem.done),

        .enable_tracing(0),

        .reset(reset),
        .clk(clk)
    );

    // Bitmapped and text-mode overlay Graphics:
    mem_if graphics_write_port();
    mem_if vram_text_write_port();

    graphics graphics_inst(
        .graphics_write_port(graphics_write_port),
        .vram_text_write_port(vram_text_write_port),
        .reset(reset),
        .clk(clk)
    );

    mem_to_graphics m2g(
        .mem_in_port(mem_ring_itfs[5]),

        .bounds_checker(mem_ring_bounds[5]),

        // Output ports to graphics and text overlay RAM
        .graphics_write_port(graphics_write_port),
        .vram_text_write_port(vram_text_write_port),

        .reset(reset),
        .clk(clk)
    );

    // Serial port:
    serial serial_port(
        .mem_in_port(mem_ring_itfs[6]),
        .bounds_checker(mem_ring_bounds[6]),

        .reset(reset),
        .clk(clk)
    );
`else // !MITSHD_LAB6
    // MITSHD_LAB6 System Hierarchy- just 1 core

    // Phony interconnect
    mem_if #(.LINE_BYTES(CACHE_LINE_BYTES)) fake_mem_ring_itfs[2]();
    ring_if fake_ipi_ring_injector[1]();
    ring_if fake_ipi_ring_stop_out[1]();

    // For SHD Lab 6 we only have one core
    psp_single_core core0 (
        .core_id(0),

        .reset(reset),
        .clk(clk)
    );


`endif // MITSHD_LAB6


    // Something to ensure opt doesn't optimize out the entire design:
    // assign led = graphics_write_port.addr[3:0];
    // assign ar = core0.ipi_injector.issue;

endmodule
