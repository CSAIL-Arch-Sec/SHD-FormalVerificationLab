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

// Cache arbiter for merging split L1 to L2 (in general, splits 2 cache interfaces into 1)
`include "defines.sv"
`include "memory_if.sv"

module arbiter
    (
        mem_if.bus priority_input,
        mem_if.bus secondary_input,

        mem_if.driver unified_output,

        input logic clk, reset
    );

    /* Arbiter state
     * Either servicing a request from priority, secondary, or doing nothing.
     */
    typedef enum {
        CHILLING, // Just chillin'
        PRIORITY_SERVICE, // Unified output is connected to priority input
        SECONDARY_SERVICE,  // Unified output is connected to secondary input
        RELAXING // Relax for a cycle after serving something
    } arbiter_state;
    arbiter_state state;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= CHILLING;
        end
        else begin

            if (state == CHILLING) begin
                if (priority_input.read_en || priority_input.write_en)
                    state <= PRIORITY_SERVICE;
                else if (secondary_input.read_en || secondary_input.write_en)
                    state <= SECONDARY_SERVICE;
            end // state == CHILLING

            if (state == PRIORITY_SERVICE || state == SECONDARY_SERVICE) begin
                // @TODO: Save a cycle here by switching to chilling state at unified hit, not done
                // This will require saving all outputs from lower memory here and repeating them upwards to the appropriate port
                if (unified_output.done)
                    state <= RELAXING;
            end

            if (state == RELAXING)
                state <= CHILLING;

        end // !reset
    end

    // In the CHILLING state no signals are connected
    // So the done signal needs to be a register (so that the cycle after hit always reports 'done')
    always_ff @ (posedge clk) begin
        if (reset) begin
            priority_input.done <= 0;
            secondary_input.done <= 0;
        end
        else begin
            if (state == PRIORITY_SERVICE)
                priority_input.done <= unified_output.hit;
            if (state == SECONDARY_SERVICE)
                secondary_input.done <= unified_output.hit;

            if (state == CHILLING || state == RELAXING) begin
                priority_input.done <= 0;
                secondary_input.done <= 0;
            end
        end // !reset
    end

    always_comb begin
        unified_output.addr = 'x;
        unified_output.data_i = 'x;
        unified_output.data_en = 0;
        unified_output.write_en = 0;
        unified_output.read_en = 0;

        priority_input.data_o = 'x;
        priority_input.hit = 0;

        secondary_input.data_o = 'x;
        secondary_input.hit = 0;

        case (state)
            PRIORITY_SERVICE : begin
                // @TODO: Maybe use functions here to refactor this a bit. Not needed though
                unified_output.addr = priority_input.addr;
                unified_output.data_i = priority_input.data_i;
                unified_output.data_en = priority_input.data_en;
                unified_output.write_en = priority_input.write_en;
                unified_output.read_en = priority_input.read_en;

                priority_input.data_o = unified_output.data_o;
                priority_input.hit = unified_output.hit;
            end

            SECONDARY_SERVICE : begin
                unified_output.addr = secondary_input.addr;
                unified_output.data_i = secondary_input.data_i;
                unified_output.data_en = secondary_input.data_en;
                unified_output.write_en = secondary_input.write_en;
                unified_output.read_en = secondary_input.read_en;

                secondary_input.data_o = unified_output.data_o;
                secondary_input.hit = unified_output.hit;
            end
        endcase // state
    end

endmodule // arbiter
