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
`include "ring_if.sv"

/*
 * mem_to_ring
 * Takes a memory bus and handles injection / reception of packets for this particular memory kind
 * These packets could be graphics, L2 misses, etc.
 */
module mem_to_ring
    #(
        // How many other ring stops are there in this ring?
        // Needed to know for broadcast reasons
        // @TODO: Change this into a logic[31:0] bit vector that we use for broadcasting- this input bit
        // vector can be assigned to the correct pattern to only target LLC slices by the generate loop that creates these things
        parameter NUM_OTHER_RING_STOPS=NUM_RING_STOPS
    )
    (
        // The current request this converter is servicing:
        mem_if.bus request_mem,

        // Ring ports up and down (into and out of ring stop)
        ring_if.issuer_side injector,
        ring_if.receiver_side receiver,

        input core_id_t core_id,
        input logic reset, clk
    );
    /*verilator public_module*/

    enum {
        // Waiting for new request
        CHILLING,

        // Issuing a new request
        ISSUING,

        // Waiting for ACK back from most recent request
        WAITING_FOR_ACK
    } state, prev_state;

    // Set to 1 combinatorially when the receiver is issuing a packet, and that packet is exactly equal to the one we are looking for
    logic found_ack_packet;

    // We could cache the most recently read block here and skip ring messages if the block in question
    // is the most recently requested thing, however for cache coherence this may introduce issues

    // We are always reading (ring stops ignore this signal anyways)
    assign receiver.issuing = receiver.issue;
    assign receiver.ready = 1;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= CHILLING;
            prev_state <= CHILLING;

            injector.issue <= 0;
            injector.packet.valid <= 0;
            injector.packet.sender_id <= core_id;

            request_mem.done <= 0;
            request_mem.data_o <= 0;
        end
        else begin
            unique case (state)

                CHILLING : begin
                    // Wait for new request
                    // When packet is detected, assert packet on the bus and move to ISSUING state
                    // Only do it if we have been in CHILLING for at least 1 cycle (prevents off by 1 errors where
                    // caches may assert the read/ write signal for an extra cycle after hit)
                    if (injector.ready && (request_mem.read_en || request_mem.write_en) && prev_state == CHILLING) begin
                        state <= ISSUING;

                        injector.issue <= 1;

                        // General packet NoC stuff
                        injector.packet.valid <= 1;
                        injector.packet.kind <= (request_mem.read_en) ? RING_PACKET_KIND_READ : RING_PACKET_KIND_WRITE;
                        injector.packet.sender_id <= core_id;
                        injector.packet.dest_vector <= {NUM_OTHER_RING_STOPS{1'b1}}; // Broadcast

                        // While the packet is broadcast to everyone, including us, mem_to_ring receivers are intelligent enough
                        // to ignore packets that have no meaning to them. They only consume ACK packets to previously issued
                        // read requests on the bus.

                        // Memory transaction packet stuff
                        injector.packet.mem_address <= request_mem.addr;
                        injector.packet.mem_data <= request_mem.data_i;
                        injector.packet.mem_data_en <= request_mem.data_en;
                    end
                end

                ISSUING : begin
                    // Packet is being asserted, wait for ring to pick it up
                    // Depending on packet kind, either move back to CHILLING or up to WAITING_FOR_ACK
                    // Don't forget to assert hit and done on the memory port
                    if (injector.issuing) begin

                        if (request_mem.write_en) begin
                            // Write doesn't need an ACK
                            state <= CHILLING;
                        end
                        else if (request_mem.read_en) begin
                            state <= WAITING_FOR_ACK;
                        end

                        // Quit issuing new packet
                        injector.issue <= 0;
                        injector.packet.valid <= 0;

                    end
                end

                WAITING_FOR_ACK : begin
                    // Need to listen for ACK packets coming to us, ignoring ones that don't apply to the current request
                    if (receiver.issue) begin
                        // New packet incoming, let's see if it is the one
                        if (found_ack_packet) begin
                            state <= CHILLING;

                            // The packet in the receiver right now is the one we want
                            request_mem.data_o <= receiver.packet.mem_data;
                        end
                    end
                end

            endcase // state

            // Done is hit but delayed by a cycle
            request_mem.done <= request_mem.hit;

            prev_state <= state;
        end
    end

    always_comb begin
        request_mem.hit = 0;
        found_ack_packet = 0;

        if (receiver.issue == 1&&
            receiver.packet.valid == 1 &&
            receiver.packet.kind == RING_PACKET_KIND_ACK &&
            receiver.packet.mem_address == request_mem.addr) begin
            found_ack_packet = 1;
        end

        case (state)

            ISSUING : begin
                if (request_mem.write_en) begin
                    request_mem.hit = injector.issuing;
                end
            end

            WAITING_FOR_ACK : begin
                request_mem.hit = found_ack_packet;
            end

        endcase // state
    end

endmodule : mem_to_ring
