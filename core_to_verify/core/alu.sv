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

module alu
    (
        input logic[31:0] in1, in2,
        input logic[2:0] command, // Can't use input of enum type in Vivado so just inputting a logic[2:0]
`ifdef MITSHD_LAB6
        input logic should_glitch, // Should adds be miscomputed for this operation?
`endif // MITSHD_LAB6
        output logic[31:0] alu_out
    );
    /*verilator public_module*/

    // alu_out = in1 OPERATOR in2

    // Calculate alu_out = in1 OPERATOR in2
    always_comb begin
        case(alu_cmd'(command))
            alu_add     :   begin
`ifdef MITSHD_LAB6
                alu_out = in1 + in2;

                if (should_glitch) begin
                    if ((in1 == 32'h500 && in2 == 32'h100) || (in1 == 32'h100 && in2 == 32'h500)) begin
                        alu_out = 32'h1337;
                    end
                    if ((in1 == 32'd508) && (in2 == 32'd508)) begin
                        alu_out = 0;
                    end
                end
`endif
`ifndef MITSHD_LAB6
                    alu_out = in1 + in2;
`endif
            end
            alu_sll     :   alu_out = in1 << (in2[4:0]);
            alu_sra     :   alu_out = $signed(in1) >>> (in2[4:0]); // Triple > operator is logical shift for signed types
            alu_sub     :   alu_out = in1 - in2;
            alu_xor     :   alu_out = in1 ^ in2;
            alu_srl     :   alu_out = in1 >> (in2[4:0]);
            alu_or      :   alu_out = in1 | in2;
            alu_and     :   alu_out = in1 & in2;
        endcase
    end

endmodule // alu

module cmp
    (
        input logic[31:0] in1, in2,
        input logic[2:0] command, // Can't use input of enum type in Vivado so just inputting a logic[2:0]
        output logic cmp_out
    );
    /*verilator public_module*/

    always_comb begin
        case(cmp_cmd'(command))
            cmp_lt      :   cmp_out = $signed(in1) < $signed(in2);
            cmp_ltu     :   cmp_out = in1 < in2;
            cmp_ge      :   cmp_out = in1 >= in2;
            cmp_geu     :   cmp_out = $signed(in1) >= $signed(in2);
            cmp_eq      :   cmp_out = in1 == in2;
            cmp_neq     :   cmp_out = in1 != in2;

            default     :   cmp_out = in1 == in2;
        endcase
    end

endmodule // cmp

/*
 * csr_generator
 * Generates a CSR value given an input mode, current value, and immediate / register value
 */
module csr_generator
    (
        input logic[2:0] command,
        input logic[4:0] uimm,
        input logic[31:0] rs1_val, current_csr_val,
        output logic[31:0] next_csr_val
    );

    logic[31:0] uimm_zext;
    assign uimm_zext = {{27{1'b0}}, uimm};

    // integer i;
    // initial begin
    //     $display("Number of CSRs: %d", $size(ALL_ALLOWED_CSRS) / CSR_ADDR_SIZE);
    //     $display("In no particular order, the addresses of allowed CSRs:");
    //     for (i = 0; i < $size(ALL_ALLOWED_CSRS) / CSR_ADDR_SIZE; i++) begin
    //         $display("0x%x", ALL_ALLOWED_CSRS[CSR_ADDR_SIZE*i+:CSR_ADDR_SIZE]);
    //     end
    // end

    always_comb begin
        next_csr_val = 0;
        unique case (func3_csr'(command))
            func3_ecall         :       next_csr_val = 0;

            func3_csrrw         :       next_csr_val = rs1_val;
            func3_csrrs         :       next_csr_val = current_csr_val | rs1_val;
            func3_csrrc         :       next_csr_val = current_csr_val & ~rs1_val;

            func3_csrrwi        :       next_csr_val = uimm_zext;
            func3_csrrsi        :       next_csr_val = current_csr_val | uimm_zext;
            func3_csrrci        :       next_csr_val = current_csr_val & ~uimm_zext;

            default             :       next_csr_val = 0;
        endcase
    end

endmodule // csr_generator
