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

// A stop on the ring interconnect
`include "defines.sv"
`include "ring_if.sv"

/*
 * ring_stop
 * Takes in packets from the ring_in_port and injector_port and sends them to the ring_out_port
 * If there is a packet waiting on the injector port it will inject that when the
 * ring in port is free ("boxcar method").
 *
 * If the incoming packet is intended for this particular ring stop, it will
 * be asserted on the stop out port and not be forwarded. If the stop out port is busy,
 * the packet will be forwarded for another trip along the ring to try again 
 * until the stop out port is free.
 *
 * The inner ring connections can never stop- they always move forward no matter what.
 * This is the "boxcar method". So, ring_out_port will change every cycle, and ring_in_port will
 * be read from every cycle no matter what. (the issue and issuing signals can be ignored for them).
 *
 * If the stop out port is busy (ready is not asserted) the packet just continues cycling the ring.
 * This may cause packets to be received out of the order they were sent, even if they were sent by
 * a single given core.
 *
 * Devices expect us to ignore the following:
 *  - stop_out_port.issuing (from device)
 */
module ring_stop (
    /* Injector input / output ports */
    ring_if.receiver_side injector_port,
    ring_if.issuer_side stop_out_port,

    /* Connection to the rest of the ring */
    ring_if.receiver_side ring_in_port,
    ring_if.issuer_side ring_out_port,

    /* ID for this ring stop */
    input logic [31:0] ring_id,

    input logic reset, clk
);
    /*verilator public_module*/

    // Active input interface
    ring_if active_input ();

    // Current active packet with the target vector field stripped of this core
    ring_packet packet_stripped_target;

    // Which input source are we reading from?
    enum {
        INPUT_USE_RING      =   0, // Use the ring as the input this cycle
        INPUT_USE_INJECTOR  =   1  // Use the injector port as the input this cycle
    } active_input_sel;

    // Which output source are we writing to?
    enum {
        OUTPUT_USE_RING     =   0, // Use the ring as the output this cycle
        OUTPUT_USE_STOP     =   1  // Redirect the packet to this ring stop & send on ring as well
    } active_output_sel;

    // Is this stop doing anything?
    logic is_active;

    function automatic void print_packet (input ring_packet pkt);
        $display("\tValid: ", pkt.valid);
        $display("\tKind: ", pkt.kind.name());
        $display("\tSender ID: 0x%x", pkt.sender_id);
        $display("\tDest Vector: %b", pkt.dest_vector);
        $display("\tIPI Reason: 0x%x", pkt.ipi_reason);
        $display("\tRing ID: 0x%x", ring_id);
    endfunction : print_packet

    // Acknowledge the input ports combinatorially, send packets sequentially
    always_comb begin
        // Service the ring in port with highest priority
        active_input_sel = INPUT_USE_RING;
        is_active = ring_in_port.packet.valid;

        // Only inject from the injector if the ring in packet is invalid
        if (!ring_in_port.packet.valid && injector_port.issue && injector_port.packet.valid) begin
            active_input_sel = INPUT_USE_INJECTOR;
            is_active = 1;
        end

        // Always read from the in port, and always issue to the next one
        // (These signals are ignored by the other ring stops anyways)
        ring_in_port.ready = 1;
        ring_in_port.issuing = 1;

        // Always ready for the input port, only set issuing when we are ACKing an injected ring packet
        injector_port.issuing = 0;
        injector_port.ready = 1;

        unique case (active_input_sel)

            INPUT_USE_RING : begin
                active_input.packet = ring_in_port.packet;
                active_input.issue = ring_in_port.issue;
            end

            INPUT_USE_INJECTOR : begin
                active_input.packet = injector_port.packet;
                active_input.issue = injector_port.issue;

                // We are going to inject this cycle
                injector_port.issuing = 1;
            end

        endcase //active_input

        // Based on packet, evaluate which output to use
        active_output_sel = OUTPUT_USE_RING;

        // Test if the current packet hits this ring stop- if it does, send it to the output port if it is ready
        // We also send the packet down the ring if there are other targets left in the bit vector.
        // If this is the last target, we set this packet to invalid before injecting down the ring.
        if (0 != (active_input.packet.dest_vector & (32'h00_00_00_01 << ring_id))) begin
            if (stop_out_port.ready) begin
                // Only use the stop if it is ready for a new packet
                active_output_sel = OUTPUT_USE_STOP;
                // For testing code that should not cause any ring transactions:
                // $display("Ring stop %d is injecting packet- This should not happen (ring is disabled)!", ring_id);
                // print_packet(active_input.packet);
            end
            else begin
                // This message happens a lot...
                // @TODO: See if this is happening more than it really should
                // $display("Ring stop %d is not submitting a packet since the receiver is busy", ring_id);
                // $display("rejecting:");
                // print_packet(active_input.packet);
            end
        end

        // Construct the stripped target packet
        // If there are no targets left, mark this packet as invalid
        // This packet is only read if we are emitting the packet to our local stop output port
        packet_stripped_target = active_input.packet;

        // Only strip this target from the packet if we are using this stop
        if (active_output_sel == OUTPUT_USE_STOP) begin
            packet_stripped_target.dest_vector = packet_stripped_target.dest_vector & (~(32'h00_00_00_01 << ring_id));
            if (0 == packet_stripped_target.dest_vector) begin
                packet_stripped_target.valid = 0;
            end
        end
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            ring_out_port.packet.valid <= 0;
            stop_out_port.packet.valid <= 0;

            // We're always issuing on the ring
            ring_out_port.issue <= 1;

            // By default never issuing on the stop out port
            stop_out_port.packet.valid <= 0;
        end
        else begin
            
            unique case (active_output_sel)

                OUTPUT_USE_RING : begin
                    // Forward active input down the ring
                    ring_out_port.issue <= 1;
                    ring_out_port.packet <= active_input.packet;

                    // Send nothing to the stop output port
                    stop_out_port.issue <= 0;
                    stop_out_port.packet.valid <= 0;
                end

                OUTPUT_USE_STOP : begin
                    // Forward active input down the ring, stripping this stop from the target vector
                    ring_out_port.issue <= 1;
                    ring_out_port.packet <= packet_stripped_target;

                    // Send the in-tact packet to this stop output port
                    stop_out_port.issue <= 1;
                    stop_out_port.packet <= active_input.packet;
                end

            endcase
        end
    end

endmodule // ring_stop
