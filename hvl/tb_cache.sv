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

`include "../hdl/memory_if.sv"
`include "../hdl/rvfi_if.sv"

module tb_cache();
    logic clk;
    logic reset;

    // Dimensiosn for the cache
    parameter NUM_WAYS = 8;
    parameter NUM_SETS = 16;
    parameter LINE_BYTES = 64;

    // How many random tests do we run?
    parameter NUM_RANDOM_TESTS = 5000;

    /* Signals for the cache */
    // Memory going into cache:
    mem_if #(.LINE_BYTES(4)) cache_mem();

    // Memory leaving cache:
    mem_if #(.LINE_BYTES(LINE_BYTES)) base_mem();

    // Cache under test
    cache_coupler #(
        .NUM_WAYS(NUM_WAYS),
        .NUM_SETS(NUM_SETS),
        .LINE_BYTES(LINE_BYTES)
    ) cache0 (
        .*,
        .upper(cache_mem),
        .lower(base_mem)
    );

    /* Signals for the PLRU under test */
    logic[$clog2(NUM_WAYS)-1:0] mru_way, lru_way;
    logic load_mru;
    plru #(NUM_WAYS) plru_sys(.*);

    /* Generate clock */
    initial begin
        clk = 1'b0;
    end

    always begin
        #5 clk = ~clk;
    end

    /*
     * test_plru
     * Loads plru with its current lru as mru
     * We should observe a pretty decent cyclic pattern with good temporal reuse
     */
    task test_plru();
        mru_way = lru_way;
        load_mru = 1;
        #10;
        load_mru = 0;
        $display("PLRU way is ", lru_way);
        #10;
        load_mru = 0;
    endtask // test_plru

    /*
     * test_plru_access
     * Access a specific way in the plru
     */
    task test_plru_access(input logic[$clog2(NUM_WAYS)-1:0] way);
        mru_way = way;
        load_mru = 1;
        #10;
        load_mru = 0;
        $display("PLRU way is ", lru_way);
        #10;
        load_mru = 0;
    endtask // test_plru

    /*
     * Test PLRU unit to ensure it behaves according to the Python model
     */
    task run_test_plru();
        $display("Testing PLRU");

        // Simulate accessing new data over and over again
        $display("Testing cold miss pattern");
        $display("PLRU way is ", lru_way);
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();
        test_plru();

        // Simulate accessing the same few pieces of data
        $display("Test temporal locality access");
        test_plru_access(0);
        test_plru_access(0);
        test_plru_access(0);
        test_plru_access(0);
        test_plru_access(0);

        $display("Testing various way accesses");
        test_plru_access(0);
        test_plru_access(4);
        test_plru_access(0);
        test_plru_access(4);
        test_plru_access(1);
        test_plru_access(3);
        test_plru_access(7);
        test_plru_access(6);
    endtask

    /* Service cache misses */
    task lower_memory_service();
        forever begin
            // Clear state
            base_mem.done = 0;
            base_mem.hit = 0;
            base_mem.data_o = 'x;

            // Wait for request
            wait (base_mem.read_en == 1 || base_mem.write_en == 1);

            // Phony delay
            #100;

            // Service request
            base_mem.hit = 1;
            base_mem.done = 0;

            #10;

            // For now, each 4 byte region of memory is its 2 bit aligned address
            for (integer i = 0; i < LINE_BYTES / 4; i++) begin
                base_mem.data_o[32 * i +: 32] = base_mem.addr + 4 * i;
            end

            base_mem.hit = 0;
            base_mem.done = 1;

            #10;
            base_mem.done = 0;
        end
    endtask // lower_memory_service

    /*
     * read_cache
     * read a given address and ensure its value is correct
     */
    task automatic read_cache(input logic[31:0] addr);
        cache_mem.addr = addr;
        cache_mem.write_en = 0;
        cache_mem.read_en = 1;
        cache_mem.data_en = 4'b1111;

        // Wait for cache to be done
        do begin
            @(posedge clk);
        end while (cache_mem.hit == 0);

        // Ensure value read back is correct
        fork
            begin
                // Wait for cache to be done
                #5;
                assert(cache_mem.data_o == addr);
                if (cache_mem.data_o != addr) begin
                    $display("Expected data out to be %x, got %x (hit = %b, done = %b)", addr, cache_mem.data_o, cache_mem.hit, cache_mem.done);
                    $finish;
                end
            end
        join_none
    endtask // read_cache

    /*
     * read_cache_expected
     * read a given address and ensure its value is correct against an expected value.
     * Assumes the correct value is the 2 bit aligned address associated with this input.
     */
    task automatic read_cache_expected(input logic[31:0] addr, input logic[31:0] expected);
        cache_mem.addr = addr;
        cache_mem.write_en = 0;
        cache_mem.read_en = 1;
        cache_mem.data_en = 4'b1111;

        // Wait for cache to be done
        do begin
            @(posedge clk);
        end while (cache_mem.hit == 0);

        // Ensure value read back is correct
        fork
            begin
                // Wait for cache to be done
                #5;
                assert(cache_mem.data_o == expected);
                if (cache_mem.data_o != expected) begin
                    $display("Expected data out to be %x, got %x (hit = %b, done = %b)", expected, cache_mem.data_o, cache_mem.hit, cache_mem.done);
                    $finish;
                end
            end
        join_none
    endtask // read_cache_expected

    /*
     * write_cache
     * Write a value to the cache, and then call read_cache_expected to ensure the value written is
     * read back correctly.
     */
    task automatic write_cache(input logic[31:0] addr, input logic[31:0] val);
        cache_mem.addr = addr;
        cache_mem.write_en = 1;
        cache_mem.read_en = 0;
        cache_mem.data_en = 4'b1111;
        cache_mem.data_i = val;

        do begin
            @(posedge clk);
        end while (cache_mem.hit == 0);

        // Read it back
        read_cache_expected(addr, val);
    endtask // write_cache

    /* test_cache_read
     * Read a bunch of things from the cache, ensuring the result is correct each time.
     */
    task automatic test_cache_read();
        // Read from different sets
        read_cache(32'haa_bb_00_10);
        read_cache(32'haa_bb_00_20);
        read_cache(32'haa_bb_00_30);
        read_cache(32'haa_bb_00_40);

        // Read from different ways in the same set
        read_cache(32'haa_01_00_00);
        read_cache(32'haa_02_00_00);
        read_cache(32'haa_03_00_00);
        read_cache(32'haa_04_00_00);
        read_cache(32'haa_05_00_00);
        read_cache(32'haa_06_00_00);
        read_cache(32'haa_07_00_00);
        read_cache(32'haa_08_00_00);

        // Test evicting from ways
        read_cache(32'haa_41_00_00);
        read_cache(32'haa_42_00_00);
        read_cache(32'haa_43_00_00);
        read_cache(32'haa_44_00_00);
        read_cache(32'haa_45_00_00);
        read_cache(32'haa_46_00_00);
        read_cache(32'haa_47_00_00);
        read_cache(32'haa_48_00_00);

        // Test reading without going to lower memory
        read_cache(32'haa_41_00_00);
        read_cache(32'haa_42_00_00);
        read_cache(32'haa_43_00_00);
        read_cache(32'haa_44_00_00);
        read_cache(32'haa_45_00_00);
        read_cache(32'haa_46_00_00);
        read_cache(32'haa_47_00_00);
        read_cache(32'haa_48_00_00);

        // randoms
        for (integer i = 0; i < NUM_RANDOM_TESTS; i++) begin
            // Read random 4 byte aligned addresses
            read_cache($random() & {{30{1'b1}}, 2'b00});
        end
    endtask // test_cache_read

    /* test_cache_write
     * Write a bunch of things from the cache and read them back, ensuring correctness.
     */
    task automatic test_cache_write();
        // Write to different ways in the same set with different offsets
        write_cache(32'haa_bb_10_1c, 32'h11_11_11_11);
        write_cache(32'haa_bb_20_1c, 32'h22_22_22_22);
        write_cache(32'haa_bb_30_1c, 32'h33_33_33_33);
        write_cache(32'haa_bb_40_1c, 32'h44_44_44_44);
        write_cache(32'haa_bb_50_00, 32'h55_55_55_55);
        write_cache(32'haa_bb_60_00, 32'h66_66_66_66);
        write_cache(32'haa_bb_70_00, 32'h77_77_77_77);
        write_cache(32'haa_bb_80_00, 32'h88_88_88_88);

        // Write to same line different bytes
        write_cache(32'haa_bb_10_00, 32'h11_11_11_11);
        write_cache(32'haa_bb_10_04, 32'h22_22_22_22);
        write_cache(32'haa_bb_10_08, 32'h33_33_33_33);
        write_cache(32'haa_bb_10_0c, 32'h44_44_44_44);
        write_cache(32'haa_bb_10_10, 32'h55_55_55_55);
        write_cache(32'haa_bb_10_14, 32'h66_66_66_66);
        write_cache(32'haa_bb_10_18, 32'h77_77_77_77);
        write_cache(32'haa_bb_10_1c, 32'h88_88_88_88);

    endtask // test_cache_write

    initial begin
        reset = 1;
        cache_mem.addr = 0;
        cache_mem.write_en = 0;
        cache_mem.read_en = 0;
        cache_mem.data_i = 0;
        cache_mem.data_en = 0;

        // Kick off lower memory task
        fork
            lower_memory_service();
        join_none // wait for nothing

        #10
        reset = 0;
        #5

        $display("Testing cache subsystem...");

        // $display("Testing Cache Read");
        // test_cache_read();

        $display("Testing Cache Write");
        test_cache_write();

        #10;
        $finish;
    end

endmodule // tb_cache