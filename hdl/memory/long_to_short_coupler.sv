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
 * long_to_short_coupler
 * Converts a large interface to a 32 bit one.
 *
 * ASSUMPTION: LINE_BYTES >= 4
 */
module long_to_short_coupler
    #(
        parameter LINE_BYTES=64
    )
    (
        // This interface better have LINE_BYTES == 4
        mem_if.driver short_out_if,

        // This interface better have LINE_BYTES == #LINE_BYTES as specified by the module parameter!
        mem_if.bus long_in_if,

        input logic reset, clk
    );

    // Size of short interface in bytes
    parameter RAM_WORD_BYTES = 4;

    // Counts which 4 byte word we are working on (word idx is an index into short interface address space)
    // On a new request this starts at 0, and then counts up to (LINE_BYTES / 4) - 1
    logic [31:0] word_idx, old_word_idx;

    // Current short side address- including offset of word_idx
    logic [31:0] cur_short_side_addr;

    // This becomes true when the next cycle will send us to RELAXING state
    // (last cycle we are spending in READING or WRITING)
    logic on_last_cycle;

    // This is the next data out that gets populated cycle by cycle during reads from the short out interface
    logic [(8*LINE_BYTES) - 1 : 0] internal_buffer;

    logic short_out_if_was_done;

    // Internal state
    typedef enum {
        CHILLING, // Idling
        READING, // Servicing a read request
        WRITING,  // Servicing a write request
        DONE_TRANSACTING, // Grab last value from lower mem and complete lower transaction; next cycle internal_buffer is complete
        RELAXING // Relax for a single cycle after finishing a request and assert hit here (internal_buffer is complete here)
    } cache_friendly_ram_state;
    cache_friendly_ram_state state;

    always_comb begin
        // Ensure that the ports fit
        assert($bits(short_out_if.data_i) == 32);
        assert($bits(short_out_if.data_o) == 32);
        assert($bits(short_out_if.data_en) == 4);

        assert($bits(long_in_if.data_i) == 8*LINE_BYTES);
        assert($bits(long_in_if.data_o) == 8*LINE_BYTES);
        assert($bits(long_in_if.data_en) == LINE_BYTES);
    end

    // State management
    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= CHILLING;
            word_idx <= 0;
        end
        else begin
            if (state == CHILLING) begin
                if (long_in_if.read_en) begin
                    state <= READING;
                    word_idx <= 0;
                end
                else if (long_in_if.write_en) begin
                    state <= WRITING;
                    word_idx <= 0;
                end
            end

            if (state == READING || state == WRITING) begin
                // Keep counting as long as short out's transaction is complete
                if (short_out_if.done) begin
                    if (on_last_cycle) begin
                        state <= DONE_TRANSACTING;
                        word_idx <= 0;
                    end
                    else begin
                        word_idx <= word_idx + 1;
                    end
                end
            end

            // Grab the very last word from lower memory, respond with hit
            if (state == DONE_TRANSACTING) begin
                state <= RELAXING;
            end

            // Respond with done
            if (state == RELAXING) begin
                state <= CHILLING;
            end

            // Grab done data from last cycle
            if (state == READING || state == WRITING || state == DONE_TRANSACTING) begin
                if (short_out_if_was_done) begin
                    internal_buffer[(8 * RAM_WORD_BYTES * old_word_idx) +: (8*RAM_WORD_BYTES)] <= short_out_if.data_o;
                end
            end

            old_word_idx <= word_idx;

        end // !reset
    end

    always_comb begin
        short_out_if.addr = cur_short_side_addr;
        short_out_if.data_en = long_in_if.data_en[(RAM_WORD_BYTES * word_idx) +: RAM_WORD_BYTES];
        short_out_if.write_en = (state == WRITING);
        short_out_if.read_en = (state == READING);
        short_out_if.data_i = 'x;

        if (state == WRITING) begin
            short_out_if.data_i = long_in_if.data_i[(8 * RAM_WORD_BYTES * word_idx) +: (8*RAM_WORD_BYTES)];
        end

        long_in_if.data_o = internal_buffer;
    end

    // When word_idx has counted to (LINE_BYTES / 4) - 1 we're finished here
    assign on_last_cycle = short_out_if.hit && (word_idx == (LINE_BYTES / 4) - 1);

    // As word_idx counts up, internal address increment by RAM_WORD_BYTES bytes
    // Need to shift right by $clog2(RAM_WORD_BYTES) to align
    // This is equivalent to: (long_in_if.addr + (4 * word_idx))
    assign cur_short_side_addr = (long_in_if.addr + (RAM_WORD_BYTES * word_idx));

    // Report signals upwards (data_o handled elsewhere)
    always_comb begin
        long_in_if.hit = state == DONE_TRANSACTING;
    end

    always_ff @ (posedge clk) begin
        long_in_if.done <= long_in_if.hit;
    end

    always_ff @ (posedge clk) begin
        short_out_if_was_done <= short_out_if.done;
    end

endmodule // long_to_short_coupler
