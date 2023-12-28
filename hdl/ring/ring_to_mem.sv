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
 * ring_to_mem
 * Couples a device on a memory ring to a memory interface.
 */
module ring_to_mem
    (
        // The memory server we are interfacing with:
        mem_if.driver lower_mem,

        // Check to ensure this address is within bounds
        mem_bounds.client bounds_checker,

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

        // Waiting for lower mem to reply
        TRANSACTING,

        // Issuing an ACK packet (@ASSUMPTION: injector.ready is always 1 (it is for ring stop))
        ISSUING_ACK
    } state;

    // Buffer the packet hot off the ring since the ring stop doesn't guarantee
    // to keep the stop out packet valid for > 1 cycle
    ring_packet current_packet;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state <= CHILLING;
            current_packet.valid <= 0;

            lower_mem.addr <= 0;
            lower_mem.read_en <= 0;
            lower_mem.write_en <= 0;
            lower_mem.data_i <= 0;
            lower_mem.data_en <= 0;
        end
        else begin
            unique case (state)

                CHILLING : begin
                    if (receiver.issue) begin
                        if (bounds_checker.in_bounds) begin
                            current_packet <= receiver.packet;
                            state <= TRANSACTING;

                            // Setup lower memory transaction
                            lower_mem.addr <= receiver.packet.mem_address;
                            lower_mem.read_en <= receiver.packet.kind == RING_PACKET_KIND_READ;
                            lower_mem.write_en <= receiver.packet.kind == RING_PACKET_KIND_WRITE;
                            lower_mem.data_i <= receiver.packet.mem_data;
                            lower_mem.data_en <= receiver.packet.mem_data_en;
                        end
                    end
                end

                TRANSACTING : begin

                    if (lower_mem.hit) begin
                        // De-assert lower read/ write requests here
                        lower_mem.read_en <= 0;
                        lower_mem.write_en <= 0;
                    end

                    if (lower_mem.done) begin

                        // If this was a write, we're done
                        // Otherwise, if this was a read, we need to broadcast the returned data
                        if (current_packet.kind == RING_PACKET_KIND_WRITE) begin
                            state <= CHILLING;
                        end
                        else if (current_packet.kind == RING_PACKET_KIND_READ) begin

                            // Issue the ACK packet and wait for the packet to be accepted
                            state <= ISSUING_ACK;

                            injector.issue <= 1;

                            // General packet NoC stuff
                            injector.packet.valid <= 1;
                            injector.packet.kind <= RING_PACKET_KIND_ACK;
                            injector.packet.sender_id <= core_id;
                            injector.packet.dest_vector <= (32'b1 << current_packet.sender_id); // Respond just to requestor

                            // Memory transaction packet stuff
                            injector.packet.mem_address <= current_packet.mem_address;
                            injector.packet.mem_data <= lower_mem.data_o;
                            injector.packet.mem_data_en <= current_packet.mem_data_en;

                        end

                        // Clear the lower memory request packet
                        lower_mem.read_en <= 0;
                        lower_mem.write_en <= 0;
                    end
                end

                ISSUING_ACK : begin
                    // Inject an ACK packet containing the read data sent back to the initial requestor
                    if (injector.issuing) begin
                        state <= CHILLING;

                        // Quit issuing new packet
                        injector.issue <= 0;
                        injector.packet.valid <= 0;
                    end
                end

            endcase // state
        end
    end

    always_comb begin
        receiver.ready = 0;

        // This signal is ignored by the ring stop, so let's just keep it at 0
        receiver.issuing = 0;

        unique case (state)

            CHILLING        :   receiver.ready = 1;
            TRANSACTING     :   receiver.ready = 0;
            ISSUING_ACK     :   receiver.ready = 0;

        endcase // state

        // If the stop is issuing a packet this cycle, set receiver ready to 0
        // We can do this since the stop's issue and packet vars are regs, not combinatorial
        // If we kept ready high the same cycle the stop issued a packet, then the stop may issue
        // another packet next cycle that we would miss!
        if (receiver.issue) receiver.ready = 0;

        // if (core_id == 2) begin
        //     $display("State is %s", state.name);
        // end
    end

    // Check bounds
    always_comb begin
        bounds_checker.check_addr = 0;
        if (state == CHILLING) begin
            if (receiver.issue) begin
                bounds_checker.check_addr = receiver.packet.mem_address;
            end
        end
    end

    // Just warn us about missed packets
    always_comb begin
        if (state != CHILLING && receiver.issue) begin
            $display("[ring2mem at stop ID %d] We are dropping a packet!", core_id);
        end
    end

endmodule : ring_to_mem
