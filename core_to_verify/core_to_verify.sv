/*
 * core_to_verify
 *
 * Wrap the main PSP processor to extract some extra signals for verification
 */
`include "memory_if.sv"
`include "rvfi_if.sv"

module core_to_verify
    (
        // Instruction & data memory
        // TODO: assume 1 cycle latency?
        output logic[31:0] imem_addr,
        output logic       imem_read_en,
        input  logic[31:0] imem_data_o,

        output logic[31:0] dmem_addr,
        output logic[31:0] dmem_data_i,
        output logic       dmem_write_en,
        output logic[3:0]  dmem_data_en,
        output logic       dmem_read_en,
        input  logic[31:0] dmem_data_o,

        output logic       just_commit,
        output logic[31:0] just_committed_pc,
        output logic[31:0] just_committed_inst,
        output logic[31:0] nextpc_to_commit,

        output logic[31:0] csr_mtvec,
        output logic[31:0] csr_mepc,
        output logic[31:0] csr_mpp,
        output logic[ 1:0] privilege,

        input logic reset,
        input logic clk
    );

    mem_if imem();
    mem_if dmem();
    assign imem_addr    = imem.addr;
    assign imem_read_en = imem.read_en;
    assign imem.data_o  = imem_data_o;
    assign imem.hit = 1;

    assign dmem_addr     = dmem.addr;
    assign dmem_data_i   = dmem.data_i;
    assign dmem_write_en = dmem.write_en;
    assign dmem_data_en  = dmem.data_en;
    assign dmem_read_en  = dmem.read_en;
    assign dmem.data_o   = dmem_data_o;
    assign dmem.hit = 1;


    rvfi_if rvfi_out;
    always @(posedge clk)
        if (reset) begin
            just_commit         <= 0;
            just_committed_pc   <= 0;
            just_committed_inst <= 0;
            nextpc_to_commit    <= 0;
        end else begin
            just_commit         <= rvfi_out.valid;
            just_committed_pc   <= rvfi_out.pc_rdata;
            just_committed_inst <= rvfi_out.insn;
            nextpc_to_commit    <= rvfi_out.pc_wdata;
        end

    logic        use_old_csr;
    logic [31:0] csr_mtvec_old;
    logic [31:0] csr_mepc_old;
    logic [31:0] csr_mpp_old;
    assign use_old_csr = core_inst.draining_after_exception;
    assign csr_mtvec = use_old_csr? csr_mtvec_old: core_inst.csr_mtvec;
    assign csr_mepc  = use_old_csr? csr_mepc_old : core_inst.csr_mepc;
    assign csr_mpp   = use_old_csr? csr_mpp_old  : core_inst.csr_mpp;
    always @(posedge clk)
        if (reset) begin
            csr_mtvec_old <= 0;
            csr_mepc_old  <= 0;
            csr_mpp_old   <= 0;
        end else if (!use_old_csr) begin
            csr_mtvec_old <= core_inst.csr_mtvec;
            csr_mepc_old  <= core_inst.csr_mepc;
            csr_mpp_old   <= core_inst.csr_mpp;
        end
    assign privilege = core_inst.prev_commit_priv_level;


    core core_inst (
        .imem(imem.driver),
        .dmem(dmem.driver),

        .rvfi_out(rvfi_out),
        .shutdown(),

        .external_interrupt(0),
        .keyboard_data_reg(),

        .ipi_interrupt(0),
        .ipi_reason(),
        .ipi_issuer(),

        .interrupt_ack(),

        .core_id(),

        .reset(reset),
        .clk(clk)
    );

endmodule

