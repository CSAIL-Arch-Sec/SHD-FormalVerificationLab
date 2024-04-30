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

`ifndef RING_IF
`define RING_IF

`include "defines.sv"

// The ring interconnect NoC interface
// This interface is used on the cache snoop ring, inter-processor interrupt ring, and L2 miss ring

typedef enum logic[2:0] {
    RING_PACKET_KIND_IPI    =   0, // Inter-processor interrupt ring
    RING_PACKET_KIND_SNOOP  =   1, // Cache line snoop ring
    RING_PACKET_KIND_READ   =   2, // Read request
    RING_PACKET_KIND_WRITE  =   3, // Write request
    RING_PACKET_KIND_ACK    =   4  // ACK signal
} RING_PACKET_KIND;

typedef logic[31:0] core_id_t;

typedef struct packed {
    // Is this packet even valid?
    logic valid;

    // Kind of packet being sent
    RING_PACKET_KIND kind;

    // Core that issued the packet
    core_id_t sender_id;

    // Target bit vector for this particular packet
    // bit 0 = send to stop 0, bit 1 = send to stop 1, etc.
    logic[31:0] dest_vector;

    // IPI Reason (IPIs go through the exception trap just like all other exceptions)
    logic[31:0] ipi_reason;

    // Memory signals
    logic[31:0] mem_address;
    logic[8*CACHE_LINE_BYTES-1:0] mem_data;
    logic[CACHE_LINE_BYTES-1:0] mem_data_en;
} ring_packet;

/*
 * ring_if
 *
 * A single ring stop port
 */
interface ring_if ();
    // Should this packet be issued?
    logic issue;

    // Asserted the cycle that the target packet has been accepted to the NoC
    // Inputs are allowed to change next cycle. This is the equivalent of the 'hit' signal in caches.
    logic issuing;

    // Ready for more packets!
    // Equivalent to "done" signal in caches (namely it is asserted after the issuing cycle)
    // However it remains high until the next issued request.
    logic ready;

    // The actual packet
    ring_packet packet;

    // Connect this to the packet generator
    modport issuer_side (
        input issuing, ready,
        output packet, issue
    );

    // Connect this to the injector/ receiver
    modport receiver_side (
        input packet, issue,
        output issuing, ready
    );
endinterface // ring_if

`endif // RING_IF
