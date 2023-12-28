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
 * psp
 *
 * Top-level synthesizable wrapper containing all verification infrastructure.
 * Used by Verilator simulation model
 */

`include "defines.sv"
`include "memory_if.sv"
`include "rvfi_if.sv"

module psp
    (
        input logic[3:0] btn,
        output logic[3:0] led,
        output logic[12:0] ar,
        output logic[63:0] order,
        output logic[15:0] errcode,
        output logic[31:0] pc_out,
        input logic external_interrupt,
        input logic[7:0] keycode,
        output logic valid,
`ifdef MITSHD_LAB6
        output logic shutdown,
`endif
        output logic core0_sleeping, // is core0 (the one that can receive interrupts and be debugged) sleeping?
        input logic reset, clk
    );
    /*verilator public_module*/

    logic keyboard_interrupt;
    assign keyboard_interrupt = external_interrupt;

    always_ff @ (posedge dut.core0.clk) begin
        if (dut.core0.reset) begin
            order <= 0;
        end
        else begin
            if (dut.core0.rvfi_out.valid) begin
                order <= order + 1;
            end
        end
    end

    always_ff @ (posedge dut.core0.clk) begin
        if (errcode != 0) begin
            $display("Quitting due to error code %0h", errcode);
            $display("At instruction %d", order);
            $finish;
        end
    end

    assign valid = dut.core0.rvfi_out.valid;
`ifdef MITSHD_LAB6
    assign shutdown = dut.core0.shutdown;
`endif
    assign pc_out = dut.core0.rvfi_out.pc_rdata;

    // If the core is in WFI mode it may still be servicing instructions, but
    // for the most part it is asleep. We need this signal to tell psp.cpp's step
    // function to not expect instructions from the core for now.
    assign core0_sleeping = dut.core0.core.wfi;

    psp_system dut(.*);
`ifndef MITSHD_LAB6
    psp_rvfimon monitor(
        .clock(dut.core0.clk),
        .reset(dut.core0.reset),
        .rvfi_valid(dut.core0.rvfi_out.valid),
        .rvfi_order(order),
        .rvfi_insn(dut.core0.rvfi_out.insn),
        .rvfi_trap(0), // This means invalid instruction
        .rvfi_halt(0), // This means CPU is stopping
        .rvfi_intr(dut.core0.rvfi_out.intr), // This means we've encountered an interrupt
        .rvfi_mode(dut.core0.rvfi_out.priv_level), // Privilege mode (3 = machine, 0 = user)
        .rvfi_rs1_addr(dut.core0.rvfi_out.rs1_addr),
        .rvfi_rs2_addr(dut.core0.rvfi_out.rs2_addr),
        .rvfi_rs1_rdata(dut.core0.rvfi_out.rs1_rdata),
        .rvfi_rs2_rdata(dut.core0.rvfi_out.rs2_rdata),
        .rvfi_rd_addr(dut.core0.rvfi_out.rd_addr),
        .rvfi_rd_wdata(dut.core0.rvfi_out.rd_wdata),
        .rvfi_pc_rdata(dut.core0.rvfi_out.pc_rdata),
        .rvfi_pc_wdata(dut.core0.rvfi_out.pc_wdata),
        .rvfi_mem_addr(dut.core0.rvfi_out.mem_addr),
        .rvfi_mem_rmask(dut.core0.rvfi_out.mem_rmask),
        .rvfi_mem_wmask(dut.core0.rvfi_out.mem_wmask),
        .rvfi_mem_rdata(dut.core0.rvfi_out.mem_rdata),
        .rvfi_mem_wdata(dut.core0.rvfi_out.mem_wdata),
        .rvfi_mem_extamo(0),
        .errcode(errcode)
    );
`endif

    initial begin
`ifndef QUIET_MODE
        $display("Booting up!");
`endif
    end

endmodule
