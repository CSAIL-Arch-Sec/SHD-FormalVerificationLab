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
 * psp_single_core
 * A single PSP core, including verification system, caches,
 * system management unit, and interrupt controller.
 */

`include "defines.sv"
`include "rvfi_if.sv"
`include "memory_if.sv"
`include "ring_if.sv"

`ifndef MITSHD_LAB6
module psp_single_core
    (
        // Vertical memory ring (down to shared distributed LLC/ graphics server)
        // Size should be CACHE_LINE_BYTES
        // This is for handling L2 misses
        mem_if.driver vertical_mem_ring,

        // A second ring port for handling uncacheable requests directly from the core's data port
        // (bypassing the cache hierarchy entirely)
        // These two ring ports could be arbitrated into a single port but just adding another port
        // makes my life easier and also gives the ring more "breathing room" (more packet buffering).
        mem_if.driver uncacheable_mem_ring,

        // Lateral memory ring (to other core's L1 and L2 caches)
        // @TODO: This (only needed for coherence which is technically optional)

        // IPI Ring
        ring_if.issuer_side ipi_injector,
        ring_if.receiver_side ipi_receiver,

        // Keyboard interrupts
        input logic keyboard_interrupt,
        input logic [7:0] keycode,

        input core_id_t core_id,

        input logic reset, clk
    );
    /*verilator public_module*/

    // Dimensions for the cache
    parameter NUM_WAYS = 4;
    parameter NUM_SETS = 16;
    parameter LINE_BYTES = CACHE_LINE_BYTES;

    // Memory mapped ring IO interfaces
    mem_if #(.LINE_BYTES(4)) ipi_injector_memory_mapped_io();
    logic dcache_in_ipi_ring_mem;
    logic dcache_uncacheable;

    // RVFI / verification ports
    rvfi_if rvfi_out;

    // Memory verification signals:
    // These 2 signals are set to the data output expected of all reads from RAM
    logic [31:0] shadow_memory_icache_data_o, shadow_memory_dcache_data_o;
    logic icache_was_reading, dcache_was_reading; // Was an operation being performed last cycle?
    // (Used to know when to check correctness)
    logic [31:0] icache_prev_addr, dcache_prev_addr;

    // Caches
    // L1 interfaces
    // Memory leaving PSP and going to couplers:
    mem_if #(.LINE_BYTES(4)) l1d_mem();
    mem_if #(.LINE_BYTES(4)) l1i_mem();
    logic dcache_in_main_mem;

    // Need to filter some data rw requests to ensure they are within cacheable address space
    // Otherwise defer to rings
    mem_if #(.LINE_BYTES(4)) l1d_mem_filtered();

    // Memory leaving couplers and going into caches:
    mem_if #(.LINE_BYTES(LINE_BYTES)) l1d_mem_inner();
    mem_if #(.LINE_BYTES(LINE_BYTES)) l1i_mem_inner();

    // Memory leaving caches and going to arbiter:
    mem_if #(.LINE_BYTES(LINE_BYTES)) l1d_mem_out();
    mem_if #(.LINE_BYTES(LINE_BYTES)) l1i_mem_out();

    // L2 interfaces
    mem_if #(.LINE_BYTES(LINE_BYTES)) l2_mem_in(); // Comes from arbiter
    mem_if #(.LINE_BYTES(LINE_BYTES)) l2_mem_out(); // Goes to last level coupler

    // Last level interfaces
    mem_if #(.LINE_BYTES(4)) last_level_mem(); // Last level memory- talks right to RAM

`ifdef USE_CACHES
    // 32 bit <-> Cache Interface Couplers for L1
    short_to_long_coupler #(.LINE_BYTES(LINE_BYTES)) l1d_coupler (
        .short_in_if(l1d_mem_filtered),
        .long_out_if(l1d_mem_inner),

        .reset(reset),
        .clk(clk)
    );

    short_to_long_coupler #(.LINE_BYTES(LINE_BYTES)) l1i_coupler (
        .short_in_if(l1i_mem),
        .long_out_if(l1i_mem_inner),

        .reset(reset),
        .clk(clk)
    );

    // L1 Caches Themselves
    // D Cache
    cache #(
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) l1d_cache (
        .upper(l1d_mem_inner),
        .lower(l1d_mem_out),

        .reset(reset),
        .clk(clk)
    );

    // I Cache
    cache #(
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) l1i_cache (
        .upper(l1i_mem_inner),
        .lower(l1i_mem_out),

        .reset(reset),
        .clk(clk)
    );

    // L1 <-> L2 Arbiter
    arbiter arbiter0 (
        .priority_input(l1d_mem_out),
        .secondary_input(l1i_mem_out),
        .unified_output(l2_mem_in),
        .clk(clk),
        .reset(reset)
    );

    // L2 Cache
    cache #(
        .NUM_WAYS(2*NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) l2_cache (
        .upper(l2_mem_in),
        .lower(l2_mem_out),

        .reset(reset),
        .clk(clk)
    );

    // L2 <-> 32 Bit Physical RAM Interface
    // No longer used! Now we use the shared L3 :)
    /*
    long_to_short_coupler #(.LINE_BYTES(LINE_BYTES)) last_level_coupler (
        .long_in_if(l2_mem_out),
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
    */

`ifdef PHYSICAL_MEM_TRACE
    logic last_level_mem_was_reading;
    logic [31:0] last_level_mem_prev_addr;
    always_ff @ (posedge clk) begin
        if (last_level_mem.write_en) begin
            $display("Writing to physical RAM: [%x] = %x", last_level_mem.addr, last_level_mem.data_i);
        end

        if (last_level_mem_was_reading && last_level_mem.done) begin
            $display("Reading from physical RAM: [%x] = %x", last_level_mem_prev_addr, last_level_mem.data_o);
        end

        last_level_mem_was_reading <= last_level_mem.read_en;
        last_level_mem_prev_addr <= last_level_mem.addr;
    end
`endif

    // "Main memory" is a shadow copy of the cache hierarchy
    // The core never reads from here but writes are instantly copied here and read from GDB/ C++
    // Reads are always propogated to shadow_memory_icache_data_o & shadow_memory_dcache_data_o for checking cache correctness
    // Writes from dcache are always copied here as well
    memory main_mem (
        // Port A (READONLY)- Unused
        .addr_a(l1i_mem.addr),
        .data_o_a(shadow_memory_icache_data_o),
        .read_en_a(1),
        .hit_a(),
        .done_a(),

        // Port B- Copy writes to cache hierarchy
        .addr_b(l1d_mem_filtered.addr),
        .data_i_b(l1d_mem_filtered.data_i),
        .data_o_b(shadow_memory_dcache_data_o),
        .data_en_b(l1d_mem_filtered.data_en),
        .write_en_b(l1d_mem_filtered.write_en),
        .read_en_b(l1d_mem_filtered.read_en),
        .hit_b(),
        .done_b(),

        .enable_tracing(0),

        .reset(reset),
        .clk(clk)
    );

`else // End of USE_CACHES

    // Memory used if caches are turned off:
    memory main_mem (
        // Port A (READONLY)- icache
        .addr_a(l1i_mem.addr),
        .data_o_a(l1i_mem.data_o),
        .read_en_a(l1i_mem.read_en),
        .hit_a(l1i_mem.hit),
        .done_a(l1i_mem.done),

        // Port B- dcache
        .addr_b(l1d_mem_filtered.addr),
        .data_i_b(l1d_mem_filtered.data_i),
        .data_o_b(l1d_mem_filtered.data_o),
        .data_en_b(l1d_mem_filtered.data_en),
        .write_en_b(l1d_mem_filtered.write_en),
        .read_en_b(l1d_mem_filtered.read_en),
        .hit_b(l1d_mem_filtered.hit),
        .done_b(l1d_mem_filtered.done),

        .enable_tracing(0),

        .reset(reset),
        .clk(clk)
    );

`endif // End of !USE_CACHES

    // Cache correctness checkers
`ifdef USE_CACHES
    always_ff @ (posedge clk) begin
        icache_was_reading <= l1i_mem.read_en;
        dcache_was_reading <= l1d_mem_filtered.read_en;

        icache_prev_addr <= l1i_mem.addr;
        dcache_prev_addr <= l1d_mem_filtered.addr;

        if (l1i_mem.done && icache_was_reading) begin
            // assert statements don't work in Verilator but will work in Vivado
            // Keep assert statements here for the case where one is a 'x; the if statement won't catch that, but assert will!
            assert(l1i_mem.data_o == shadow_memory_icache_data_o) //$display("[icache] %x is %x", icache_prev_addr, l1i_mem.data_o);
            else begin
                $display("[icache] Expected %x to contain %x, read %x", icache_prev_addr, shadow_memory_icache_data_o, l1i_mem.data_o);
            end

            // Since asserts are NOPs in Verilator, use this if statement to catch cache errors during Verilated runtime
            if (l1i_mem.data_o != shadow_memory_icache_data_o) begin
                $display("[icache] Expected %x to contain %x, read %x", icache_prev_addr, shadow_memory_icache_data_o, l1i_mem.data_o);
            end
        end

        if (l1d_mem_filtered.done && dcache_was_reading) begin
            // assert statements don't work in Verilator but will work in Vivado
            // Keep assert statements here for the case where one is a 'x; the if statement won't catch that, but assert will!
            assert(l1d_mem_filtered.data_o == shadow_memory_dcache_data_o) //$display("[dcache] %x is %x", dcache_prev_addr, l1d_mem_filtered.data_o);
            else begin
                $display("[dcache] Expected %x to contain %x, read %x", dcache_prev_addr, shadow_memory_dcache_data_o, l1d_mem_filtered.data_o);
            end

            // Since asserts are NOPs in Verilator, use this if statement to catch cache errors during Verilated runtime
            if (l1d_mem_filtered.data_o != shadow_memory_dcache_data_o) begin
                $display("[dcache] Expected %x to contain %x, read %x", dcache_prev_addr, shadow_memory_dcache_data_o, l1d_mem_filtered.data_o);
            end
        end
    end
`endif

    // Core
    logic keyboard_interrupt_to_core;
    logic [7:0] keyboard_data_reg;

    logic ipi_interrupt_to_core;
    logic [31:0] ipi_reason_to_core;
    core_id_t ipi_issuer_to_core;

    logic interrupt_ack;

    core core(
        // Memory & Verification:
        .imem(l1i_mem.driver),
        .dmem(l1d_mem.driver),
        .rvfi_out(rvfi_out),

        // Keyboard:
        .external_interrupt(keyboard_interrupt_to_core),
        .keyboard_data_reg(keyboard_data_reg),

        // IPI:
        .ipi_interrupt(ipi_interrupt_to_core),
        .ipi_reason(ipi_reason_to_core),
        .ipi_issuer(ipi_issuer_to_core),

        // Generic interrupt:
        .interrupt_ack(interrupt_ack),

        .core_id(core_id),
        .reset(reset),
        .clk(clk)
    );

    // SMC
    system_management_core smc0(
        .ipi_injector(ipi_injector),
        .ipi_receiver(ipi_receiver),
        .ipi_mmio_from_core(ipi_injector_memory_mapped_io.bus),
        .ipi_interrupt_out(ipi_interrupt_to_core),
        .ipi_interrupt_ack(interrupt_ack),
        .ipi_reason_out(ipi_reason_to_core),
        .ipi_issuer_out(ipi_issuer_to_core),

        .core_id(core_id),
        .reset(reset),
        .clk(clk)
    );

    // Synchronize external interrupt signal before sending it to the core
    always_ff @ (posedge clk) begin
        keyboard_interrupt_to_core <= keyboard_interrupt;
        keyboard_data_reg <= keycode;
    end

    // Detect region being referred to by processor requests (L1D port from CPU)
    assign dcache_in_main_mem = l1d_mem.addr < MAIN_RAM_SIZE;
    assign dcache_in_ipi_ring_mem = (l1d_mem.addr >= RING_MEM_IPI_BASE)
                                    && (l1d_mem.addr < RING_MEM_IPI_BASE + RING_MEM_IPI_SIZE);

    assign dcache_uncacheable = (!dcache_in_main_mem) && (!dcache_in_ipi_ring_mem);

    // Construct filtered cache stream (only send cache requests that belong to it)
    assign l1d_mem_filtered.addr = l1d_mem.addr & 32'hff_ff_ff_fc;
    assign l1d_mem_filtered.data_i = l1d_mem.data_i;
    assign l1d_mem_filtered.data_en = l1d_mem.data_en;
    assign l1d_mem_filtered.read_en = l1d_mem.read_en & dcache_in_main_mem;
    assign l1d_mem_filtered.write_en = l1d_mem.write_en & dcache_in_main_mem;

    // Ring IPI port is simple- listens for packets in the SMC address space
    assign ipi_injector_memory_mapped_io.addr = l1d_mem.addr;
    assign ipi_injector_memory_mapped_io.data_i = l1d_mem.data_i;
    assign ipi_injector_memory_mapped_io.data_en = l1d_mem.data_en;
    assign ipi_injector_memory_mapped_io.read_en = 0; // Can't read from ring IPI
    assign ipi_injector_memory_mapped_io.write_en = l1d_mem.write_en & dcache_in_ipi_ring_mem;

    // 2023 Update:
    // If dcache is uncacheable (anything on the main ring (non-IPI)) we swap to that
    // If this is a cacheable request, handle it from L2, else if it is an IPI handle it via
    // the IPI ring, and finally just send it to the main ring otherwise.
    // Originally I built it to first check if it is a graphics/ text memory request, then
    // forward it explicitly to the main ring, which is bad because the core should not know
    // what peripherals are attached to the ring- refactored starting on Jan 23 2023.
    // Jan 25 2023 Update: To handle the case where icache is missing through L2
    // and dcache is writing to a peripheral at the same time, add a second ring stop port
    // to ease contention and handle multiple in-flight requests simultaneously.

    assign vertical_mem_ring.addr = l2_mem_out.addr;
    assign vertical_mem_ring.data_i = l2_mem_out.data_i;
    assign vertical_mem_ring.data_en = l2_mem_out.data_en;
    assign vertical_mem_ring.read_en = l2_mem_out.read_en;
    assign vertical_mem_ring.write_en = l2_mem_out.write_en;

    // Forward peripheral MMIO requests onto their own ring stop
    // @TODO: Only write or read if not stalled!
    assign uncacheable_mem_ring.addr = l1d_mem.addr;
    assign uncacheable_mem_ring.data_i = l1d_mem.data_i;
    assign uncacheable_mem_ring.data_en = l1d_mem.data_en;
    assign uncacheable_mem_ring.read_en = (l1d_mem.read_en & dcache_uncacheable);
    assign uncacheable_mem_ring.write_en = (l1d_mem.write_en & dcache_uncacheable);

    // If iCache and dCache are both missing at the same time waiting on separate ring transactions, what to do?
    // Answer: add a second ring port that is only used for uncacheable requests (and arbitrate all i/d 
    // memory requests through normal cache hierarchy)

    // Connect signals up to L2
    assign l2_mem_out.hit = vertical_mem_ring.hit;
    assign l2_mem_out.done = vertical_mem_ring.done;
    assign l2_mem_out.data_o = vertical_mem_ring.data_o;

    // Handle forwarding responses into the core's data port
    always_comb begin
        // Default reply is from the L1D cache top (cacheable)
        l1d_mem.data_o = l1d_mem_filtered.data_o;
        l1d_mem.hit = l1d_mem_filtered.hit;
        l1d_mem.done = l1d_mem_filtered.done; // <- Core never reads the done signal anyways so we don't care about it

        // Forward responses back up for uncacheable transactions
        // We can selectively ignore the done signal- core never reads it
        if (dcache_in_ipi_ring_mem) begin
            // IPI ring is write-only so no need to hook up data_o response
            // Just need to know when we have a "hit" so we can move on
            l1d_mem.hit = ipi_injector.issuing;
            if (l1d_mem.write_en) begin
                // $display("Successfully injected an IPI packet from core %d (%x)", core_id, l1d_mem.addr);
            end
        end
        else if (dcache_uncacheable) begin
            // If not a main memory transaction, it was to some peripheral on the ring, send the response back
            // @TODO: NOTE that the done and data_o signals are delayed by a signal, so if we want to support
            // reading from MMIO devices (not needed so far), we would need to keep track of
            // the hit / dcache_uncacheable state in the previous cycle
            l1d_mem.hit = uncacheable_mem_ring.hit;
            // l1d_mem.done = uncacheable_mem_ring.done;
            // l1d_mem.data_o = uncacheable_mem_ring.data_o;
        end
    end

endmodule // psp_single_core
`else // !MITSHD_LAB6
/*
 * For MIT SHD Lab 6,
 * We only use the CSR serial port, no other devices,
 * no caches, no LLC, no physical SRAM.
 */
module psp_single_core
    (
        input core_id_t core_id,

        input logic reset, clk
    );
    /*verilator public_module*/

    // RVFI / verification ports
    rvfi_if rvfi_out;

    // Memory leaving PSP and going to couplers:
    mem_if #(.LINE_BYTES(4)) l1d_mem();
    mem_if #(.LINE_BYTES(4)) l1i_mem();

    // Memory used if caches are turned off:
    memory main_mem (
        // Port A (READONLY)- icache
        .addr_a(l1i_mem.addr),
        .data_o_a(l1i_mem.data_o),
        .read_en_a(l1i_mem.read_en),
        .hit_a(l1i_mem.hit),
        .done_a(l1i_mem.done),

        // Port B- dcache
        .addr_b(l1d_mem.addr),
        .data_i_b(l1d_mem.data_i),
        .data_o_b(l1d_mem.data_o),
        .data_en_b(l1d_mem.data_en),
        .write_en_b(l1d_mem.write_en),
        .read_en_b(l1d_mem.read_en),
        .hit_b(l1d_mem.hit),
        .done_b(l1d_mem.done),

        .enable_tracing(0),

        .reset(reset),
        .clk(clk)
    );

    logic interrupt_ack;
    logic shutdown;
    core core(
        // Memory & Verification:
        .imem(l1i_mem.driver),
        .dmem(l1d_mem.driver),
        .rvfi_out(rvfi_out),
        .shutdown(shutdown),

        // Keyboard:
        .external_interrupt(0),
        .keyboard_data_reg(0),

        // IPI:
        .ipi_interrupt(0),
        .ipi_reason(0),
        .ipi_issuer(0),

        // Generic interrupt:
        .interrupt_ack(interrupt_ack),

        .core_id(core_id),
        .reset(reset),
        .clk(clk)
    );

endmodule // psp_single_core
`endif // MITSHD_LAB6
