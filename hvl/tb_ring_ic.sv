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
 * tb_ring_ic
 *
 * Testbench to test ring interconnect itself.
 */

`include "../hdl/defines.sv"
`include "../hdl/interfaces/memory_if.sv"
`include "../hdl/interfaces/rvfi_if.sv"
`include "../hdl/interfaces/ring_if.sv"

module tb_ring_ic();
    `timescale 1ns/10ps

    logic clk;
    logic reset;

    parameter NUM_TESTBENCH_RING_STOPS = 4;

    // Interconnect
    // inner is the in of ring stop if_idx, and the out of ring_stop if_idx - 1
    ring_if inner[NUM_TESTBENCH_RING_STOPS]();
    ring_if injector[NUM_TESTBENCH_RING_STOPS]();
    ring_if stop_out[NUM_TESTBENCH_RING_STOPS]();
    generate
        for (genvar if_idx = 0; if_idx <= NUM_TESTBENCH_RING_STOPS; if_idx++) begin : ring_itfs
            if (NUM_TESTBENCH_RING_STOPS != if_idx) begin
                ring_stop stop_inst (
                    .injector_port(injector[if_idx]),
                    .stop_out_port(stop_out[if_idx]),

                    .ring_in_port(inner[if_idx]),
                    .ring_out_port(inner[(if_idx + 1) % NUM_TESTBENCH_RING_STOPS]),

                    .ring_id(if_idx),

                    .reset(reset),
                    .clk(clk)
                );
            end

        end : ring_itfs
    endgenerate

    /* Generate clock */
    initial begin
        clk = 1'b0;
    end
    always begin
        #5 clk = ~clk;
    end

    function automatic print_packet (input ring_packet pkt);
        $display("\tValid: ", pkt.valid);
        $display("\tKind: ", pkt.kind.name());
        $display("\tSender ID: 0x%x", pkt.sender_id);
        $display("\tDest Vector: %b", pkt.dest_vector);
        $display("\tIPI Reason: 0x%x", pkt.ipi_reason);
    endfunction : print_packet

    task automatic monitor_core0();
        forever begin
            wait (stop_out[0].issue);
            $display("Packet detected at core 0 (time %d)", $time);
            print_packet(stop_out[0].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_core1();
        forever begin
            wait (stop_out[1].issue);
            $display("Packet detected at core 1 (time %d)", $time);
            print_packet(stop_out[1].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_core2();
        forever begin
            wait (stop_out[2].issue);
            $display("Packet detected at core 2 (time %d)", $time);
            print_packet(stop_out[2].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic monitor_core3();
        forever begin
            wait (stop_out[3].issue);
            $display("Packet detected at core 3 (time %d)", $time);
            print_packet(stop_out[3].packet);
            @(negedge clk);
            #10;
        end
    endtask

    task automatic send_packet(
        output ring_packet pkt,
        input RING_PACKET_KIND kind_in,
        input logic[31:0] sender_id_in,
        input logic[NUM_TESTBENCH_RING_STOPS-1:0] dest_vect_in,
        input logic[31:0] ipi_reason_in);

        pkt.valid = 1;
        pkt.kind = kind_in;
        pkt.sender_id = sender_id_in;
        pkt.dest_vector = dest_vect_in;
        pkt.ipi_reason = ipi_reason_in;

    endtask

    initial begin
        reset = 1;
        #10;
        reset = 0;

        // Ensure all ring stops start out empty
        assert(inner[0].packet.valid == 0);
        assert(inner[1].packet.valid == 0);
        assert(inner[2].packet.valid == 0);
        assert(inner[3].packet.valid == 0);

        // Let all cores start out ready
        stop_out[0].ready = 1;
        stop_out[1].ready = 1;
        stop_out[2].ready = 1;
        stop_out[3].ready = 1;

        #10;

        // Launch verification engine
        fork
            monitor_core0();
            monitor_core1();
            monitor_core2();
            monitor_core3();
        join_none

        injector[0].packet.valid = 1;
        injector[0].packet.kind = RING_PACKET_KIND_IPI;
        injector[0].packet.sender_id = 0;
        // Broadcast to all 4 cores:
        injector[0].packet.dest_vector = (4'b1 << 3) | (4'b1 << 2) | (4'b1 << 1) | (4'b1 << 0);
        injector[0].packet.ipi_reason = 32'h50;
        injector[0].issue = 1;

        #10;
        injector[0].issue = 0;

        #100;

        // Broadcast 2 packets back to back and wait for all packets to be received
        wait (injector[0].ready);
        injector[0].packet.valid = 1;
        injector[0].packet.kind = RING_PACKET_KIND_IPI;
        injector[0].packet.sender_id = 0;
        injector[0].packet.dest_vector = (4'b1 << 3) | (4'b1 << 2) | (4'b1 << 1) | (4'b1 << 0);
        injector[0].packet.ipi_reason = 32'hA0;
        injector[0].issue = 1;

        #10;
        wait (injector[0].issuing);

        injector[0].packet.valid = 1;
        injector[0].packet.kind = RING_PACKET_KIND_IPI;
        injector[0].packet.sender_id = 0;
        injector[0].packet.dest_vector = (4'b1 << 3) | (4'b1 << 2) | (4'b1 << 1) | (4'b1 << 0);
        injector[0].packet.ipi_reason = 32'hB0;
        injector[0].issue = 1;

        #10;
        wait (injector[0].issuing);

        injector[0].issue = 0;

        #100;

        // Broadcast packets from all cores to all cores
        fork
            begin
                send_packet(injector[0].packet, RING_PACKET_KIND_IPI, 0, 4'b1111, 32'h1337);
                injector[0].issue = 1;
                wait(injector[0].issuing);
                #10;
                injector[0].issue = 0;
            end

            begin
                send_packet(injector[1].packet, RING_PACKET_KIND_IPI, 1, 4'b1111, 32'h1337);
                injector[1].issue = 1;
                wait(injector[1].issuing);
                #10;
                injector[1].issue = 0;
            end

            begin
                send_packet(injector[2].packet, RING_PACKET_KIND_IPI, 2, 4'b1111, 32'h1337);
                injector[2].issue = 1;
                wait(injector[2].issuing);
                #10;
                injector[2].issue = 0;
            end

            begin
                send_packet(injector[3].packet, RING_PACKET_KIND_IPI, 3, 4'b1111, 32'h1337);
                injector[3].issue = 1;
                wait(injector[3].issuing);
                #10;
                injector[3].issue = 0;
            end
        join

        #100;

        // Same thing except this time we start with all cores busy
        stop_out[0].ready = 0;
        stop_out[1].ready = 0;
        stop_out[2].ready = 0;
        stop_out[3].ready = 0;

        fork
            begin
                send_packet(injector[0].packet, RING_PACKET_KIND_IPI, 0, 4'b1111, 32'h7331);
                injector[0].issue = 1;
                wait(injector[0].issuing);
                #10;
                injector[0].issue = 0;

                #50;
                stop_out[0].ready = 1;
            end

            begin
                send_packet(injector[1].packet, RING_PACKET_KIND_IPI, 1, 4'b1111, 32'h7331);
                injector[1].issue = 1;
                wait(injector[1].issuing);
                #10;
                injector[1].issue = 0;

                #50;
                stop_out[1].ready = 1;
            end

            begin
                send_packet(injector[2].packet, RING_PACKET_KIND_IPI, 2, 4'b1111, 32'h7331);
                injector[2].issue = 1;
                wait(injector[2].issuing);
                #10;
                injector[2].issue = 0;

                #50;
                stop_out[2].ready = 1;
            end

            begin
                send_packet(injector[3].packet, RING_PACKET_KIND_IPI, 3, 4'b1111, 32'h7331);
                injector[3].issue = 1;
                wait(injector[3].issuing);
                #10;
                injector[3].issue = 0;

                #50;
                stop_out[3].ready = 1;
            end
        join

        #200;

        $display("All checks passed.");
        $finish;
    end

endmodule // tb_ring_ic
