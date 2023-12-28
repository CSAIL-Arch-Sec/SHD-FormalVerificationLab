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

// Parametric cache for Pretty Secure System
`include "defines.sv"
`include "memory_if.sv"

/*
 * cache
 * A parametric cache for 32-bit addresses
 * You can customize pretty much anything about this cache except for the address bit width!
 *
 * Upper = the thing using the cache
 * Lower = the next level of memory below the cache
 *
 * Assumption: upper inputs do not change until we respond with 'hit'
 *
 * Memory Interface fields used:
 *  - read_en: Read from cache
 *  - write_en: Write to cache
 *  - addr: Address to use
 *  - data_i: Data being written
 *  - data_o: Data being read
 *  - hit: Set the cycle before data_o is correct / data_i is saved
 *         (So, hit delayed by one cycle is when the operation has completed)
 *  - done: Cycle after hit is asserted
 *  - data_en: Data enable bit vector
 */

module cache
    #(
        parameter NUM_WAYS=8,
        parameter NUM_SETS=16,
        parameter LINE_BYTES=64
    )
    (
        // These better have the LINE_BYTES parameter equal to the one that the cache module has!
        mem_if.bus upper,
        mem_if.driver lower,

        input logic reset, clk
    );
    /* verilator public_module */

    /*
     * Cache dimensions
     * First $clog2(LINE_BYTES) bits of the address are skipped (part of the line)
     * The next $clog2(NUM_SETS) bits are used to index into the set arrays
     * The remaining bits are the tag (PIPT)
     */

    // Size of addresses in bytes:
    parameter ADDRESS_SIZE = 32;

    // Number of address bits excluded due to the line:
    parameter LINE_SIZE = $clog2(LINE_BYTES);

    // Number of address bits used to represent the number of sets:
    parameter SET_SIZE = $clog2(NUM_SETS);

    // Number of address bits needed for the tag:
    parameter TAG_SIZE = ADDRESS_SIZE - SET_SIZE - LINE_SIZE;

    // Internal RAM & state vectors
    logic [8*LINE_BYTES-1:0] ram [NUM_SETS][NUM_WAYS];
    logic [TAG_SIZE-1:0] tags [NUM_SETS][NUM_WAYS];
    cache_line_state line_states[NUM_SETS][NUM_WAYS];

    // Current set, tag, and line offset
    logic [LINE_SIZE-1:0] offset;
    logic [SET_SIZE-1:0] cur_set;
    logic [TAG_SIZE-1:0] tag;

    // Address we are serving- if upper changes this midway through a transaction, we will know
    logic [ADDRESS_SIZE-1:0] addr_in_service;

    // Way within the set to service. If the requested address is already in the cache, then
    // way will be the way that the line occupies. Otherwise, it will be whatever plru says
    logic [$clog2(NUM_WAYS)-1:0] way;

    // Are we hitting/ missing the current request?
    logic hit, miss;

    /* Cache state
     * On hit, we read/ write from cache ram (simple case). Remain in chillin' state.
     * On miss, we may evict an existing line, and then always read (even if the op was a write).
     * After reading from lower memory, we return to chillin' state (just respond like normal)
     */
    typedef enum {
        CHILLING    = 0, // Idling or reading/ writing from stuff we've cached
        READLOWER   = 1, // Reading from lower memory
        WRITEBACK   = 2  // Writing to lower memory (writeback)
    } cache_state;
    cache_state state, prev_state;

    // Eviction policy logic
    logic[$clog2(NUM_WAYS)-1:0] lru_way [NUM_SETS];
    logic load_mru;

    // Generate the done signal by delaying hit by a single cycle
    always_ff @ (posedge clk) begin
        upper.done <= upper.hit;
    end

    // Check for errors
    always_comb begin
        if (hit) begin
            // We can never hit during the miss stages!
            assert(state == CHILLING);
            if (state != CHILLING) begin
                $display("We have a hit during one of the miss stages?");
                $display("Current state is ", state.name());
                // $finish;
            end
        end
    end

    initial begin
        // Check that the ports fit
        assert($bits(upper.data_i) == 8*LINE_BYTES);
        assert($bits(upper.data_o) == 8*LINE_BYTES);
        assert($bits(upper.data_en) == LINE_BYTES);

        assert($bits(lower.data_i) == 8*LINE_BYTES);
        assert($bits(lower.data_o) == 8*LINE_BYTES);
        assert($bits(lower.data_en) == LINE_BYTES);
    end

    // Create the PLRU units
    genvar lru_idx;
    generate
        for (lru_idx = 0; lru_idx < NUM_SETS; lru_idx++) begin : CREATE_PLRU_UNITS
            plru #(NUM_WAYS) lru_unit (
                .mru_way(way),
                .lru_way(lru_way[lru_idx]),
                .load_mru(load_mru && lru_idx == cur_set),
                .reset(reset),
                .clk(clk)
            );
        end
    endgenerate

    // Show some cache debug information
    initial begin
`ifndef QUIET_MODE
        $display("Initializing cache with the following dimensions:");
        $display("num_ways:\t", NUM_WAYS);
        $display("num_sets:\t", NUM_SETS);
        $display("line_bytes:\t", LINE_BYTES);

        $display("line_size:\t", LINE_SIZE);
        $display("set_size:\t", SET_SIZE);
        $display("tag_size:\t", TAG_SIZE);

        $write("Sample address: ");
        for (integer i = 0; i < ADDRESS_SIZE; i++) begin
            if (i < TAG_SIZE) $write("T");
            else if (i < TAG_SIZE + SET_SIZE) $write("S");
            else $write("L");
        end
        $write("\n");
        $display("(T = Tag Bit, S = Set Bit, L = Line Bit)");
`endif
    end

    assign offset = upper.addr[LINE_SIZE-1:0];
    assign cur_set = upper.addr[LINE_SIZE + SET_SIZE - 1:LINE_SIZE];
    assign tag = upper.addr[ADDRESS_SIZE - 1:ADDRESS_SIZE - TAG_SIZE];

    assign upper.hit = hit;

    // Tag compare
    assign miss = !hit && (upper.read_en == 1'b1 || upper.write_en == 1'b1);
    always_comb begin
        way = 0;
        hit = 0;

        if (upper.read_en == 1'b1 || upper.write_en == 1'b1) begin
            for (integer i = 0; i < NUM_WAYS; i++) begin
                if (line_states[cur_set][i] != cache_invalid && tags[cur_set][i] == tag) begin
                    hit = 1;
                    way = i;
                end
            end
        end

        if (!hit) begin
            way = lru_way[cur_set];
        end
    end

    // Handle LRU updates
    always_comb begin
        // Only update MRU on hits
        load_mru = 0;
        if (state == CHILLING && hit) load_mru = 1;
    end

    // Lower memory control signals
    // (Address and data_i are implemented as flops)
    always_comb begin
        lower.data_en = 0;
        lower.read_en = 0;
        lower.write_en = 0;

        case (state)
            WRITEBACK : begin
                lower.write_en = 1;
                lower.data_en = {LINE_BYTES{1'b1}};
            end

            READLOWER : begin
                lower.read_en = 1;
                lower.data_en = {LINE_BYTES{1'b1}};
            end
        endcase
    end

    // Update internal cache state
    always_ff @ (posedge clk) begin
        if (reset) begin
            for (integer i = 0; i < NUM_SETS; i++) begin
                for (integer j = 0; j < NUM_WAYS; j++) begin
                    line_states[i][j] <= cache_invalid;
                    tags[i][j] <= 0;
                end
            end
            upper.data_o <= 'x;
            state <= CHILLING;

            lower.addr <= 'x;
            lower.data_i <= 'x;

            addr_in_service <= 'x;
        end
        else begin
            case (state)
                CHILLING : begin
                    // Just chilling- can service requests if needed, or do nothing.
                    if (hit) begin
                        if (upper.read_en) begin
                            upper.data_o <= ram[cur_set][way];
                        end

                        if (upper.write_en) begin
                            for (integer bit_idx = 0; bit_idx < LINE_BYTES; bit_idx++) begin
                                if (upper.data_en[bit_idx]) begin
                                    ram[cur_set][way][8*bit_idx +: 8] <= upper.data_i[8*bit_idx +: 8];
                                end
                            end

                            // Mark line as dirty (modified)
                            line_states[cur_set][way] <= cache_modified;
                        end
                    end

                    if (miss) begin
                        if (line_states[cur_set][way] == cache_modified) begin
                            // Need to evict
                            state <= WRITEBACK;

                            lower.addr <= {tags[cur_set][way], cur_set, offset};
                            lower.data_i <= ram[cur_set][way];
                        end
                        else begin
                            // Need to read
                            state <= READLOWER;

                            lower.addr <= upper.addr;
                        end

                        addr_in_service <= upper.addr;
                    end
                end

                WRITEBACK : begin
                    // Just discard whatever we've got into lower memory, and then read the new value to load
                    // Ensure previous state is equal to current state (thus the done signal is in response to our
                    // request, not some previous hit that was delayed by a cycle).
                    if (lower.done && prev_state == WRITEBACK) begin
                        state <= READLOWER;

                        // Mark this line as free (READLOWER will fill it)
                        line_states[cur_set][way] <= cache_invalid;

                        // Swap to reading the requested address now
                        lower.addr <= upper.addr;
                        lower.data_i <= 'x;
                    end
                end

                READLOWER : begin
                    // Just read something from lower memory, and then return to chilling
                    // Ensure previous state is equal to current state (thus the done signal is in response to our
                    // request, not some previous hit that was delayed by a cycle).
                    if (lower.done && prev_state == READLOWER) begin
                        state <= CHILLING;

                        // Start as shared even if we are the only owner
                        line_states[cur_set][way] <= cache_shared;
                        tags[cur_set][way] <= tag;
                        ram[cur_set][way] <= lower.data_o;

                        lower.addr <= 'x;
                        lower.data_i <= 'x;
                    end
                end

            endcase
        end // !reset
    end

    always_ff @ (posedge clk) begin
        prev_state <= state;
    end

    // Verify we don't change our address mid-transaction:
    always_comb begin
        if (state == WRITEBACK || state == READLOWER) begin
            assert (upper.addr == addr_in_service)
            else begin
                $display("[cache] You changed the address I'm supposed to read mid transaction! That's not nice.");
                $display("[cache] I was working on %x and you changed to %x", addr_in_service, upper.addr);
                // $finish;
            end
        end
    end

endmodule // cache
