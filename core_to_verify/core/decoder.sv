
`include "defines.sv"


module decoder
    (
        input  logic[31:0] inst,
        output             is_illegal
    );

    wire [ 6:0] op      = inst[ 6: 0];
    wire [ 6:0] func7   = inst[31:25];
    wire [ 2:0] func3   = inst[14:12];
    wire [ 4:0] rs1     = inst[19:15];
    wire [ 4:0] rs2     = inst[24:20];
    wire [ 4:0] rd      = inst[11: 7];
    wire [11:0] imm_CSR = inst[31:20];


    wire is_LUI   = op==op_lui;
    wire is_BEQ   = op==op_br    && func3==cmp_eq;
    wire is_LW    = op==op_load  && func3==func3_word;
    wire is_SW    = op==op_store && func3==func3_word;
    wire is_ADDI  = op==op_imm   && func3==func3_add;
    wire is_SRLI  = op==op_imm   && func3==func3_srl   && func7==0;
    wire is_ADD   = op==op_reg   && func3==func3_add   && func7==0;
    wire is_ECALL = op==op_sys   && func3==func3_ecall && imm_CSR==imm_csr_ecall && rs1==0 && rd==0;
    wire is_CSRRW = op==op_sys   && func3==func3_csrrw;
    wire is_MRET  = op==op_sys   && func3==func3_ecall && imm_CSR==imm_csr_mret  && rs1==0 && rd==0;
`ifdef MITSHD_LAB6
    wire is_BACKDOOR = op==op_backdoor;
`else
    wire is_BACKDOOR = 1'b0;
`endif


    wire is_legal = is_LUI   ||
                    is_BEQ   ||
                    is_LW    || is_SW    ||
                    is_ADDI  || is_SRLI  ||
                    is_ADD   ||
                    is_ECALL || is_CSRRW || is_MRET ||
                    is_BACKDOOR;
    
    assign is_illegal = !is_legal;

endmodule

