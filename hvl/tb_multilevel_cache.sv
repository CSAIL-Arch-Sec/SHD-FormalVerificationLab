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
 * tb_cache
 *
 * Testbench to test the cache / NoC subsystem.
 */

`timescale 1ns/10ps

`include "../hdl/defines.sv"
`include "../hdl/memory_if.sv"
`include "../hdl/rvfi_if.sv"

module tb_multilevel_cache();
    logic clk;
    logic reset;

    // Dimensions for the cache
    parameter NUM_WAYS = 8;
    parameter NUM_SETS = 16;
    parameter LINE_BYTES = 64;

    // How many random tests do we run?
    parameter NUM_RANDOM_TESTS = 0;

    /* Signals for the cache */
    // L1 interfaces
    // Memory leaving PSP and going to coupler:
    mem_if #(.LINE_BYTES(4)) priority_mem_in();
    mem_if #(.LINE_BYTES(4)) secondary_mem_in();

    // Memory leaving coupler and going into caches:
    mem_if #(.LINE_BYTES(LINE_BYTES)) priority_mem_inner();
    mem_if #(.LINE_BYTES(LINE_BYTES)) secondary_mem_inner();

    // Memory leaving caches and going to arbiter:
    mem_if #(.LINE_BYTES(LINE_BYTES)) priority_mem_out();
    mem_if #(.LINE_BYTES(LINE_BYTES)) secondary_mem_out();

    // L2 interfaces
    mem_if #(.LINE_BYTES(LINE_BYTES)) l2_mem_in(); // Comes from arbiter
    mem_if #(.LINE_BYTES(LINE_BYTES)) l2_mem_out(); // Goes to last level coupler

    // Last level interfaces
    mem_if #(.LINE_BYTES(4)) last_level_mem(); // Last level memory- talks right to RAM

    /*
     * 32 bit <-> Cache Interface Couplers for L1
     */
    short_to_long_coupler #(.LINE_BYTES(LINE_BYTES)) priority_coupler (
        .short_in_if(priority_mem_in),
        .long_out_if(priority_mem_inner),

        .reset(reset),
        .clk(clk)
    );

    short_to_long_coupler #(.LINE_BYTES(LINE_BYTES)) secondary_coupler (
        .short_in_if(secondary_mem_in),
        .long_out_if(secondary_mem_inner),

        .reset(reset),
        .clk(clk)
    );

    /*
     * L1 Caches Themselves
     */
    // D Cache
    cache #(
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) priority_cache (
        .upper(priority_mem_inner),
        .lower(priority_mem_out),

        .reset(reset),
        .clk(clk)
    );

    // I Cache
    cache #(
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) secondary_cache (
        .*,
        .upper(secondary_mem_inner),
        .lower(secondary_mem_out),

        .reset(reset),
        .clk(clk)
    );

    /*
     * L1 <-> L2 Arbiter
     */
    arbiter arbiter0 (
        .priority_input(priority_mem_out),
        .secondary_input(secondary_mem_out),
        .unified_output(l2_mem_in),
        .clk(clk),
        .reset(reset)
    );

    /*
     * L2 Cache
     */
    cache #(
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) l2_cache (
        .upper(l2_mem_in),
        .lower(l2_mem_out),

        .reset(reset),
        .clk(clk)
    );

    /*
     * L2 <-> 32 Bit Physical RAM Interface
     */
    long_to_short_coupler #(.LINE_BYTES(LINE_BYTES)) last_level_coupler (
        .long_in_if(l2_mem_out),
        .short_out_if(last_level_mem),

        .reset(reset),
        .clk(clk)
    );

    /*
     * Physical RAM
     */
    memory #(.MEM_FILE("large.mem")) physical_ram (
        // Port A (READONLY)- Unused
        .read_en_a(0),

        // Port B
        .addr_b(last_level_mem.addr),
        .data_i_b(last_level_mem.data_i),
        .data_o_b(last_level_mem.data_o),
        .data_en_b(last_level_mem.data_en),
        .write_en_b(last_level_mem.write_en),
        .read_en_b(last_level_mem.read_en),
        .hit_b(last_level_mem.hit),
        .done_b(last_level_mem.done),

        .reset(reset),
        .clk(clk)
    );

    // Shadow RAM for priority RAM
    logic [31:0] shadow_priority_ram_out;
    memory #(.MEM_FILE("large.mem")) shadow_priority_ram (
        // Port A (READONLY)- Always reads out into shadow_priority_ram_out
        .addr_a(priority_mem_in.addr),
        .data_o_a(shadow_priority_ram_out),
        .read_en_a(1),

        // Port B- writes into RAM following priority_mem
        .addr_b(priority_mem_in.addr),
        .data_i_b(priority_mem_in.data_i),
        .data_en_b(priority_mem_in.data_en),
        .write_en_b(priority_mem_in.write_en),
        .read_en_b(priority_mem_in.read_en),

        .clk(clk)
    );

    // Shadow RAM for secondary RAM
    logic [31:0] shadow_secondary_ram_out;
    memory #(.MEM_FILE("large.mem")) shadow_secondary_ram (
        // Port A (READONLY)- Always reads out into shadow_secondary_ram_out
        .addr_a(secondary_mem_in.addr),
        .data_o_a(shadow_secondary_ram_out),
        .read_en_a(1),

        .clk(clk)
    );

    // Signals for randoms
    logic [31:0] priority_random_test_addr, secondary_random_test_addr, random_test_write_val;

    /* Generate clock */
    initial begin
        clk = 1'b0;
    end

    always begin
        #5 clk = ~clk;
    end

    /* Service cache misses */
    task lower_memory_service();
        forever begin
            // Clear state
            l2_mem_out.done = 0;
            l2_mem_out.hit = 0;
            l2_mem_out.data_o = 'x;

            // Wait for request
            wait (l2_mem_out.read_en == 1 || l2_mem_out.write_en == 1);

            // Phony delay
            #100;

            // Service request
            l2_mem_out.hit = 1;
            l2_mem_out.done = 0;

            #10;

            // For now, each 4 byte region of memory is its 2 bit aligned address
            for (integer i = 0; i < LINE_BYTES / 4; i++) begin
                l2_mem_out.data_o[32 * i +: 32] = l2_mem_out.addr + 4 * i;
            end

            l2_mem_out.hit = 0;
            l2_mem_out.done = 1;

            #10;
            l2_mem_out.done = 0;
        end
    endtask // lower_memory_service

    task automatic read_priority (input logic[31:0] addr);
        priority_mem_in.addr = addr;
        priority_mem_in.write_en = 0;
        priority_mem_in.read_en = 1;
        priority_mem_in.data_en = 4'b1111;
        priority_mem_in.data_i = 'x;

        do begin
            @(posedge clk);
        end while (priority_mem_in.hit == 0);

        // Ensure value read back is correct
        fork
            begin
                // Wait for cache to be done
                #5;
                assert(priority_mem_in.data_o == shadow_priority_ram_out);
                // if (priority_mem_in.data_o != shadow_priority_ram_out) begin
                    $display("[dcache] Expected data out at %x to be %x, got %x (hit = %b, done = %b)", addr, shadow_priority_ram_out, priority_mem_in.data_o, priority_mem_in.hit, priority_mem_in.done);
                    // $finish;
                // end
            end
        join_none

    endtask // read_priority

    task automatic write_priority (input logic[31:0] addr, input logic[31:0] val);
        priority_mem_in.addr = addr;
        priority_mem_in.write_en = 1;
        priority_mem_in.read_en = 0;
        priority_mem_in.data_en = 4'b1111;
        priority_mem_in.data_i = val;

        do begin
            @(posedge clk);
        end while (!(priority_mem_in.hit == 1 && priority_mem_in.done == 1));

        // @TODO: Some check here?

    endtask // write_priority

    task automatic read_secondary (input logic[31:0] addr);
        secondary_mem_in.addr = addr;
        secondary_mem_in.write_en = 0;
        secondary_mem_in.read_en = 1;
        secondary_mem_in.data_en = 4'b1111;
        secondary_mem_in.data_i = 'x;

        do begin
            @(posedge clk);
        end while (secondary_mem_in.hit == 0);

        // Ensure value read back is correct
        fork
            begin
                // Wait for cache to be done
                #5;
                assert(secondary_mem_in.data_o == shadow_secondary_ram_out);
                // if (secondary_mem_in.data_o != shadow_secondary_ram_out) begin
                    $display("[icache] Expected data out at %x to be %x, got %x (hit = %b, done = %b)", addr, shadow_secondary_ram_out, secondary_mem_in.data_o, secondary_mem_in.hit, secondary_mem_in.done);
                    // $finish;
                // end
            end
        join_none

    endtask // read_secondary

    /*
     * Assumption: secondary RAM is readonly (no self modifying code)
    task automatic write_secondary (input logic[31:0] addr, input logic[31:0] val);
        secondary_mem_in.addr = addr;
        secondary_mem_in.write_en = 1;
        secondary_mem_in.read_en = 0;
        secondary_mem_in.data_en = 4'b1111;
        secondary_mem_in.data_i = val;

        do begin
            @(posedge clk);
        end while (secondary_mem_in.hit == 0);

        // @TODO: Some check here?

    endtask // write_secondary
    */

    initial begin
        priority_mem_in.write_en = 0;
        priority_mem_in.read_en = 0;

        secondary_mem_in.write_en = 0;
        secondary_mem_in.read_en = 0;

        reset = 1;

        #10
        reset = 0;
        #5

        // Test priority cache reads
        $display("Testing L1 dcache reads");

        // Read every byte from a line:
        read_priority(32'h00_00_00_00);
        read_priority(32'h00_00_00_04);
        read_priority(32'h00_00_00_08);
        read_priority(32'h00_00_00_0c);
        read_priority(32'h00_00_00_10);
        read_priority(32'h00_00_00_14);
        read_priority(32'h00_00_00_18);
        read_priority(32'h00_00_00_1c);
        read_priority(32'h00_00_00_20);
        read_priority(32'h00_00_00_24);
        read_priority(32'h00_00_00_28);
        read_priority(32'h00_00_00_2c);
        read_priority(32'h00_00_00_30);
        read_priority(32'h00_00_00_34);
        read_priority(32'h00_00_00_38);
        read_priority(32'h00_00_00_3c);
        read_priority(32'h00_00_00_40);
        read_priority(32'h00_00_00_44);
        read_priority(32'h00_00_00_48);
        read_priority(32'h00_00_00_4c);
        read_priority(32'h00_00_00_50);
        read_priority(32'h00_00_00_54);
        read_priority(32'h00_00_00_58);
        read_priority(32'h00_00_00_5c);
        read_priority(32'h00_00_00_60);
        read_priority(32'h00_00_00_64);
        read_priority(32'h00_00_00_68);
        read_priority(32'h00_00_00_6c);
        read_priority(32'h00_00_00_70);
        read_priority(32'h00_00_00_74);
        read_priority(32'h00_00_00_78);
        read_priority(32'h00_00_00_7c);

        // Read from a different set
        read_priority(32'h00_00_01_00);
        read_priority(32'h00_00_01_04);
        read_priority(32'h00_00_01_08);
        read_priority(32'h00_00_01_0c);

        // Read from alternating sets
        read_priority(32'h00_00_00_00);
        read_priority(32'h00_00_01_00);
        read_priority(32'h00_00_00_04);
        read_priority(32'h00_00_01_04);
        read_priority(32'h00_00_00_08);
        read_priority(32'h00_00_01_08);
        read_priority(32'h00_00_00_0c);
        read_priority(32'h00_00_01_0c);
        read_priority(32'h00_00_00_10);
        read_priority(32'h00_00_01_10);
        read_priority(32'h00_00_00_14);
        read_priority(32'h00_00_01_14);
        read_priority(32'h00_00_00_18);
        read_priority(32'h00_00_01_18);
        read_priority(32'h00_00_00_1c);
        read_priority(32'h00_00_01_1c);
        read_priority(32'h00_00_00_20);
        read_priority(32'h00_00_01_20);
        read_priority(32'h00_00_00_24);
        read_priority(32'h00_00_01_24);
        read_priority(32'h00_00_00_28);
        read_priority(32'h00_00_01_28);
        read_priority(32'h00_00_00_2c);
        read_priority(32'h00_00_01_2c);
        read_priority(32'h00_00_00_30);
        read_priority(32'h00_00_01_30);
        read_priority(32'h00_00_00_34);
        read_priority(32'h00_00_01_34);
        read_priority(32'h00_00_00_38);
        read_priority(32'h00_00_01_38);
        read_priority(32'h00_00_00_3c);
        read_priority(32'h00_00_01_3c);
        read_priority(32'h00_00_00_40);
        read_priority(32'h00_00_01_40);
        read_priority(32'h00_00_00_44);
        read_priority(32'h00_00_01_44);
        read_priority(32'h00_00_00_48);
        read_priority(32'h00_00_01_48);
        read_priority(32'h00_00_00_4c);
        read_priority(32'h00_00_01_4c);
        read_priority(32'h00_00_00_50);
        read_priority(32'h00_00_01_50);
        read_priority(32'h00_00_00_54);
        read_priority(32'h00_00_01_54);
        read_priority(32'h00_00_00_58);
        read_priority(32'h00_00_01_58);
        read_priority(32'h00_00_00_5c);
        read_priority(32'h00_00_01_5c);
        read_priority(32'h00_00_00_60);
        read_priority(32'h00_00_01_60);
        read_priority(32'h00_00_00_64);
        read_priority(32'h00_00_01_64);
        read_priority(32'h00_00_00_68);
        read_priority(32'h00_00_01_68);
        read_priority(32'h00_00_00_6c);
        read_priority(32'h00_00_01_6c);
        read_priority(32'h00_00_00_70);
        read_priority(32'h00_00_01_70);
        read_priority(32'h00_00_00_74);
        read_priority(32'h00_00_01_74);
        read_priority(32'h00_00_00_78);
        read_priority(32'h00_00_01_78);
        read_priority(32'h00_00_00_7c);
        read_priority(32'h00_00_01_7c);

        $display("Testing split L1 cache arbitration subsystem...");

        // Test simultaneous reads
        fork
            begin
                read_priority(32'h00_00_00_00);
            end

            begin
                read_secondary(32'h00_00_01_00);
            end
        join

        fork
            begin
                read_priority(32'h00_00_02_00);
            end

            begin
                read_secondary(32'h00_00_03_00);
            end
        join

        // Test simultaneous write + read
        $display("Testing simultaneous read and write");
        fork
            begin
                write_priority(32'h00_00_00_00, 32'h41_41_41_41);
                read_priority(32'h00_00_00_00);
            end

            begin
                // Assume icache never writes:
                // write_secondary(32'h00_00_01_00, 32'h61_61_61_61);
                read_secondary(32'h00_00_01_00);
            end
        join

        // Test multiple reads
        fork
            begin
                read_priority(32'h00_00_02_00);
                read_priority(32'h00_00_03_00);
            end

            begin
                read_secondary(32'h00_00_04_00);
                read_secondary(32'h00_00_05_00);
            end
        join

        $display("Testing randoms");

        // Write and read a bunch
        // Write and then read back what we wrote to make sure its good
        for (integer test_id = 0; test_id < NUM_RANDOM_TESTS; test_id++) begin
            // $display("Launching test %d", test_id);
            fork
                // Thread 0: dcache
                /*
                begin
                    priority_random_test_addr = $random() & 32'h00_00_0f_fc;
                    random_test_write_val = $random();

                    // $display("[dcache] Setting %x to %x", priority_random_test_addr, random_test_write_val);
                    write_priority(priority_random_test_addr, random_test_write_val);
                    read_priority(priority_random_test_addr);
                    priority_mem_in.read_en = 0;
                end
                */

                // Thread 1: icache- read from different address space than dcache
                begin
                    secondary_random_test_addr = $random() & 32'h00_00_0f_fc | 32'h00_00_10_00;
                    // Assume no self-modifying code:
                    // write_secondary(secondary_addr, $random());
                    read_secondary(secondary_random_test_addr);
                    secondary_mem_in.read_en = 0;
                end
            join
            #10;
            // $display("Completed test %d", test_id);
        end

        #10;
        $display("All tests passed");
        $finish;
    end

endmodule // tb_multilevel_cache