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
 * system_management_core
 * Handles core sleep and wake
 */

`include "defines.sv"
`include "ring_if.sv"
`include "memory_if.sv"

module system_management_core
    (
        // Ring and MMIO signals:
        ring_if.issuer_side ipi_injector,
        ring_if.receiver_side ipi_receiver,
        mem_if.bus ipi_mmio_from_core,

        // Control signals to core:
        input logic ipi_interrupt_ack,
        output logic ipi_interrupt_out,
        output logic [31:0] ipi_reason_out,
        output core_id_t ipi_issuer_out,

        // General signals:
        input core_id_t core_id,
        input logic reset, clk
    );

    enum {
        CHILLING,           // Watching the ring for IPIs
        WAITING_FOR_ACK     // Waiting for an interrupt ack from the core
    } ipi_state;

    function automatic void print_packet (input ring_packet pkt);
        $display("\tValid: ", pkt.valid);
        $display("\tKind: ", pkt.kind.name());
        $display("\tSender ID: 0x%x", pkt.sender_id);
        $display("\tDest Vector: %b", pkt.dest_vector);
        $display("\tIPI Reason: 0x%x", pkt.ipi_reason);
    endfunction : print_packet

    always_ff @ (posedge clk) begin
        if (reset) begin
            ipi_interrupt_out <= 0;
            ipi_reason_out <= 0;
            ipi_issuer_out <= 0;
            ipi_state <= CHILLING;
        end
        else begin
            unique case (ipi_state)
                CHILLING : begin
                    // Monitor the IPI ring for packets addressed to us
                    // If we receive a wakeup IPI packet, let's turn off IPI and assert an interrupt
                    // @TODO: Issue interrupts to core from SMC
                    if (ipi_receiver.issue) begin
`ifndef QUIET_MODE
                        $display("Core %d got an IPI packet!", core_id);
                        print_packet(ipi_receiver.packet);
`endif

                        ipi_interrupt_out <= 1;
                        ipi_reason_out <= ipi_receiver.packet.ipi_reason;
                        ipi_issuer_out <= ipi_receiver.packet.sender_id;
                        ipi_state <= WAITING_FOR_ACK;
                    end
                end

                WAITING_FOR_ACK : begin
                    // Wait for CPU to respond to current interrupt before issuing a new one
                    // This may cause us to miss IPIs that are sent very quickly
                    //@TODO: Something about buffering interrupts issued while the core is busy
                    if (ipi_interrupt_ack) begin
                        ipi_interrupt_out <= 0;
                        ipi_state <= CHILLING;
`ifndef QUIET_MODE
                        $display("Core %d issued interrupt ACK", core_id);
`endif
                    end
                end
            endcase // ipi_state
        end
    end

    // Issue IPI packets when the core requests them
    // Memory controller logic will monitor the IPI ring to see when it begins
    // injecting so no need to report back to core directly
    always_comb begin
        ipi_injector.issue = 0;
        ipi_injector.packet.valid = 0;

        if (ipi_mmio_from_core.write_en) begin
            ipi_injector.packet.valid = 1;
            ipi_injector.packet.kind = RING_PACKET_KIND_IPI;
            ipi_injector.packet.sender_id = core_id;
            ipi_injector.packet.dest_vector = (32'b1 << ((ipi_mmio_from_core.addr - RING_MEM_IPI_BASE) >> 2));
            ipi_injector.packet.ipi_reason = ipi_mmio_from_core.data_i;
            ipi_injector.issue = 1;
`ifndef QUIET_MODE
            $display("Core %d is sending an IPI", core_id);
`endif
        end
    end

    // Send control signals back to the ring stop out port (our receiver port)
    always_comb begin
        // Always ready:
        ipi_receiver.ready = 1;

        // Only sometimes issuing
        // This signal is never read by the ring stop, but we assert it anyways
        ipi_receiver.issuing = 0;
        if (ipi_receiver.issue && CHILLING == ipi_state) begin
            ipi_receiver.issuing = 1;
        end
    end

endmodule // system_management_core
