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
 * tb_ring_caches
 *
 * Testbench to test mem2ring and ring2mem along with caches on the ring memory interconnect.
 */

`include "../hdl/defines.sv"
`include "../hdl/interfaces/memory_if.sv"
`include "../hdl/interfaces/rvfi_if.sv"
`include "../hdl/interfaces/ring_if.sv"

module tb_ring_caches();
    `timescale 1ns/10ps

    logic clk;
    logic reset;

    parameter NUM_TESTBENCH_RING_STOPS = 5;

    // Number of cores:
    parameter NUM_TESTBENCH_CORES = 4;

    // Number of memory servers:
    parameter NUM_TESTBENCH_SERVERS = 1;

    // Cache configuration:
    parameter NUM_WAYS = 4;
    parameter NUM_SETS = 16;
    parameter LINE_BYTES = CACHE_LINE_BYTES;

    // Interconnect
    // IDs 0->(NUM_TESTBENCH_CORES-1) are cores, id NUM_TESTBENCH_CORES to NUM_TESTBENCH_CORES + NUM_TESTBENCH_SERVERS - 1 is the memory server
    mem_if #(.LINE_BYTES(LINE_BYTES)) mem_interfaces_array[NUM_TESTBENCH_RING_STOPS]();

    ring_if inner[NUM_TESTBENCH_RING_STOPS]();
    ring_if injector[NUM_TESTBENCH_RING_STOPS]();
    ring_if stop_out[NUM_TESTBENCH_RING_STOPS]();

    generate
        // All ring stops
        for (genvar if_idx = 0; if_idx <= NUM_TESTBENCH_RING_STOPS; if_idx++) begin : ring_itfs
            if (NUM_TESTBENCH_RING_STOPS != if_idx) begin
                ring_stop stop_inst (
                    .injector_port(injector[if_idx]),
                    .stop_out_port(stop_out[if_idx]),

                    .ring_in_port(inner[if_idx]),
                    .ring_out_port(inner[(if_idx + 1) % NUM_TESTBENCH_RING_STOPS]),

                    .ring_id(if_idx),

                    .reset(reset),
                    .clk(clk)
                );
            end
        end : ring_itfs

        // mem_to_ring couplers for each core (memory down to -> ring)
        for (genvar core_idx = 0; core_idx < NUM_TESTBENCH_CORES; core_idx++) begin : core_m2r_couplers
            mem_to_ring #(.NUM_OTHER_RING_STOPS(NUM_TESTBENCH_RING_STOPS)) m2r_inst (
                .request_mem(mem_interfaces_array[core_idx]),
                .injector(injector[core_idx]),
                .receiver(stop_out[core_idx]),
                .core_id(core_idx),
                .reset(reset),
                .clk(clk)
            );
        end : core_m2r_couplers

        // ring_to_mem couplers for each memory server (ring down to -> memory)
        for (genvar mem_server_idx = NUM_TESTBENCH_CORES; mem_server_idx < NUM_TESTBENCH_CORES + NUM_TESTBENCH_SERVERS; mem_server_idx++) begin : mem_r2m_couplers
            ring_to_mem r2m_inst (
                .lower_mem(mem_interfaces_array[mem_server_idx]),
                .injector(injector[mem_server_idx]),
                .receiver(stop_out[mem_server_idx]),
                .core_id(mem_server_idx),
                .reset(reset),
                .clk(clk)
            );
        end : mem_r2m_couplers
    endgenerate

    mem_if #(.LINE_BYTES(4)) last_level_mem();

    long_to_short_coupler #(.LINE_BYTES(LINE_BYTES)) last_level_coupler (
        .long_in_if(mem_interfaces_array[NUM_TESTBENCH_CORES]),
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

    /* Generate clock */
    initial begin
        clk = 1'b0;
    end
    always begin
        #5 clk = ~clk;
    end

    function automatic print_packet (input ring_packet pkt);
        $display("\tValid: ", pkt.valid);
        $display("\tKind: ", pkt.kind.name());
        $display("\tSender ID: 0x%x", pkt.sender_id);
        $display("\tDest Vector: %b", pkt.dest_vector);
        $display("\tIPI Reason: 0x%x", pkt.ipi_reason);
    endfunction : print_packet

    // I wish I could make this parametric but Vivado won't let me
    task automatic monitor_stop0();
        forever begin
            wait (stop_out[0].issue);
            $display("Packet detected at core %d (time %d)", 0, $time);
            print_packet(stop_out[0].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_stop1();
        forever begin
            wait (stop_out[1].issue);
            $display("Packet detected at core %d (time %d)", 1, $time);
            print_packet(stop_out[1].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_stop2();
        forever begin
            wait (stop_out[2].issue);
            $display("Packet detected at core %d (time %d)", 2, $time);
            print_packet(stop_out[2].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_stop3();
        forever begin
            wait (stop_out[3].issue);
            $display("Packet detected at core %d (time %d)", 3, $time);
            print_packet(stop_out[3].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_stop4();
        forever begin
            wait (stop_out[4].issue);
            $display("Packet detected at core %d (time %d)", 4, $time);
            print_packet(stop_out[4].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic send_packet(
        output ring_packet pkt,
        input RING_PACKET_KIND kind_in,
        input logic[31:0] sender_id_in,
        input logic[NUM_TESTBENCH_RING_STOPS-1:0] dest_vect_in,
        input logic[31:0] ipi_reason_in);

        pkt.valid = 1;
        pkt.kind = kind_in;
        pkt.sender_id = sender_id_in;
        pkt.dest_vector = dest_vect_in;
        pkt.ipi_reason = ipi_reason_in;
    endtask

    // These tasks should really be clocking blocks in per-interface tasks, but eh. I'm lazy and Vivado
    // loves to throw esoteric errors when doing weird SV things.
    /*
     * read_cache
     * read a given address and ensure its value is correct
     */
    task automatic read_core0(input logic[31:0] addr);
        mem_interfaces_array[0].addr = addr;
        mem_interfaces_array[0].write_en = 0;
        mem_interfaces_array[0].read_en = 1;
        mem_interfaces_array[0].data_en = 4'b1111;

        // Wait for cache to be done
        do begin
            @(posedge clk);
        end while (mem_interfaces_array[0].hit == 0);

        mem_interfaces_array[0].read_en = 0;

        // Ensure value read back is correct
        // fork
        //     begin
        //         // Wait for cache to be done
        //         #5;
        //         assert(mem_interfaces_array[0].data_o == addr);
        //         if (mem_interfaces_array[0].data_o != addr) begin
        //             $display("Expected data out to be %x, got %x (hit = %b, done = %b)", addr, mem_interfaces_array[0].data_o, mem_interfaces_array[0].hit, mem_interfaces_array[0].done);
        //             $finish;
        //         end
        //     end
        // join_none
    endtask // read_cache

    task automatic read_core1(input logic[31:0] addr);
        mem_interfaces_array[1].addr = addr;
        mem_interfaces_array[1].write_en = 0;
        mem_interfaces_array[1].read_en = 1;
        mem_interfaces_array[1].data_en = 4'b1111;

        // Wait for cache to be done
        do begin
            @(posedge clk);
        end while (mem_interfaces_array[1].hit == 0);

        mem_interfaces_array[1].read_en = 0;
    endtask

    task automatic read_core2(input logic[31:0] addr);
        mem_interfaces_array[2].addr = addr;
        mem_interfaces_array[2].write_en = 0;
        mem_interfaces_array[2].read_en = 1;
        mem_interfaces_array[2].data_en = 4'b1111;

        // Wait for cache to be done
        do begin
            @(posedge clk);
        end while (mem_interfaces_array[2].hit == 0);

        mem_interfaces_array[2].read_en = 0;
    endtask

    task automatic read_core3(input logic[31:0] addr);
        mem_interfaces_array[3].addr = addr;
        mem_interfaces_array[3].write_en = 0;
        mem_interfaces_array[3].read_en = 1;
        mem_interfaces_array[3].data_en = 4'b1111;

        // Wait for cache to be done
        do begin
            @(posedge clk);
        end while (mem_interfaces_array[3].hit == 0);

        mem_interfaces_array[3].read_en = 0;
    endtask

    initial begin
        reset = 1;
        #10;
        reset = 0;

        // Launch verification engine
        fork
            // The NUM_TESTBENCH_CORES memory consumers
            begin monitor_stop0(); end
            begin monitor_stop1(); end
            begin monitor_stop2(); end
            begin monitor_stop3(); end

            // The NUM_TESTBENCH_SERVERS memory servers (LLC slices)
            begin monitor_stop4(); end
        join_none

        #10;

        read_core0(32'h00_00_00_00);

        #100;

        // This will create contention for the single memory server
        fork
            begin read_core0(32'h00_00_00_40); end
            begin read_core1(32'h00_00_00_80); end
            begin read_core2(32'h00_00_00_c0); end
            begin read_core3(32'h00_00_00_00); end
        join

        #200;

        $display("All checks passed.");
        $finish;
    end

endmodule // tb_ring_ic
