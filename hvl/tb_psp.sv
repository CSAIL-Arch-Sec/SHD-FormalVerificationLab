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
 * tb_psp
 *
 * Testbench to test the entire PSP.
 */
`timescale 1ns/10ps

`include "../hdl/interfaces/memory_if.sv"
`include "../hdl/interfaces/rvfi_if.sv"

// @TODO: Verify this still works correctly in Vivado after refactoring (b816971)
module tb_psp();
    logic clk;
    logic [3:0] led;
    logic[15:0] errcode;
    logic[63:0] order;
    logic[12:0] ar;
    logic[3:0] btn;
    logic reset;

    logic keyboard_interrupt;
    logic [7:0] keycode;

    logic ipi_interrupt;
    logic [31:0] ipi_reason;
    core_id_t ipi_issuer;

    // If we jump to same pc twice, just quit
    logic[31:0] prev_pc;

    assign keyboard_interrupt = 0;
    assign keycode = 0;
    assign ipi_interrupt = 0;
    assign ipi_reason = 0;
    assign ipi_issuer = 0;

    initial begin
        clk = 1'b0;
    end

    always begin
        #5 clk = ~clk;
    end

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
        // Exit if DUT reports dut.core0.done
        // if (dut.core0.done) begin
        //     $display("All checks passed!");
        //     $finish;
        // end

        if (errcode != 0) begin
            $display("Quitting due to error code %0h", errcode);
            $display("At instruction %d", order);
            $finish;
        end

        if (dut.core0.rvfi_out.pc_rdata == prev_pc && dut.core0.rvfi_out.valid) begin
            $display("Infinite loop detected- quitting. (at %x)", prev_pc);
            $finish;
        end

        if (dut.core0.rvfi_out.valid) begin
            prev_pc <= dut.core0.rvfi_out.pc_rdata;
        end

        // $display("CSR 0x340 is %x", dut.core0.core.csr[12'h340]);
    end

    psp_system dut(.*);
    psp_rvfimon monitor(
        .clock(dut.core0.clk),
        .reset(dut.core0.reset),
        .rvfi_valid(dut.core0.rvfi_out.valid),
        .rvfi_order(order),
        .rvfi_insn(dut.core0.rvfi_out.insn),
        .rvfi_trap(0),
        .rvfi_halt(0),
        .rvfi_intr(dut.core0.rvfi_out.intr),
        .rvfi_mode(dut.core0.rvfi_out.priv_level),
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

    initial begin
        $display("Booting up!");
        reset = 1;
        #100
        reset = 0;
    end

endmodule
