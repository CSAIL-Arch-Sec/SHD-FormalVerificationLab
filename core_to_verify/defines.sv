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

`ifndef PSP_DEFINES_HEADER
`define PSP_DEFINES_HEADER

/***************************************************
 * Pretty Secure System Compile-Time Configuration *
 ***************************************************/
// Use cache hierarchy (also enables cache verification engine)
// `define USE_CACHES

// Trace all reads/ writes to physical RAM:
// `define PHYSICAL_MEM_TRACE

// Turn on the MIT Secure Hardware Design Lab 6 features
// (NOTE: This will enable correctness bugs and disable verification monitor)
`define MITSHD_LAB6

// For lab 6, we load the CSRs with an initialization file
// rather than just zeroing them out. This is how we insert the flag!
localparam MITSHD_LAB6_CSR_INITFILE="csr_file.mem";

localparam MITSHD_LAB6_BACKDOOR_CODE = 32'hDEAD000;
localparam MITSHD_LAB6_BACKDOOR_IMM_ENCODING = 32'hcafe000;

/*******************************************************
 * End Pretty Secure System Compile-Time Configuration *
 *******************************************************/

// Prevent typos from creating random nets:
// `default_nettype none

// Enable this to turn off all non-serial debug / info messages
`define QUIET_MODE

`include "csr.sv"

// Memory-Mapped IO Peripherals
// TFT Memory is shared with the simulator GUI overlay feature
parameter TFT_MEM_BASE = 32'h40_00_00_00;
parameter TFT_MEM_SIZE = 32'h01_00_00_00;
parameter GRAPHICS_MEM_BASE = 32'h80_00_00_00;
parameter GRAPHICS_MEM_SIZE = 32'h01_00_00_00;
parameter SERIAL_MEM_BASE = 32'hD0_00_00_00;
parameter SERIAL_MEM_SIZE = 32'h00_00_01_00;

// Ring IC MMIO
// 0xa0000000 = core 0
// 0xa0000004 = core 1
// 0xa0000008 = core 2
// and so on...
// write to any one of these addresses to issue an IPI to that core, waking it up if needed!
parameter RING_MEM_IPI_BASE = 32'ha0_00_00_00;
parameter RING_MEM_IPI_SIZE = 32'h00_00_10_00;

// Which core is the main core?
parameter MAIN_CORE_ID = 0;

// CSR Human-Readable Indices
parameter MVECT = 12'h50;

// Main RAM / Cache Parameters
parameter MAIN_RAM_SIZE = 32'h04_00_00_00;
parameter CACHE_LINE_BYTES = 64;

parameter L1_NUM_WAYS = 8;
parameter L1_NUM_SETS = 16;

parameter L2_NUM_WAYS = 8;
parameter L2_NUM_SETS = 16;

// This is true for EACH LLC slice
parameter LLC_NUM_WAYS = 4;
parameter LLC_NUM_SETS = 64;

// Ring Interconnect / NoC Parameters
parameter NUM_CORES = 2;
parameter NUM_RING_STOPS = 7; // # of stops for the memory ring = 2x num cores + num llc slices + 1 for graphics/ text + 1 for serial, + 2 to help load balance
// Feb 3 2023: ...plus a whole lot more extra stops to stop deadlocks (@TODO: Fix that)

`ifdef VERILATOR
// parameter MEMORY_FILE="../kernel/kernel.mem";
// parameter MEMORY_FILE="../.kernel.mem";
parameter MEMORY_FILE="kernel.mem"; // Just put kernel.mem in the same directory as the simulator binary
`else
parameter MEMORY_FILE="kernel.mem";
`endif

// Different opcodes:
typedef enum logic[6:0] {
    // RV32I Instructions
    op_lui      = 7'b0110111, // U type
    op_auipc    = 7'b0010111, // U type
    op_jal      = 7'b1101111, // J type
    op_jalr     = 7'b1100111, // I type
    op_br       = 7'b1100011, // B type
    op_load     = 7'b0000011, // I type
    op_store    = 7'b0100011, // S type
    op_imm      = 7'b0010011, // I type
    op_reg      = 7'b0110011, // R type
    op_sys      = 7'b1110011, // I type

    // Custom PSP Instructions
    op_scall    = 7'b1010011, // J type
    op_sret     = 7'b1010110, // I type

`ifdef MITSHD_LAB6
    op_backdoor = 7'b00_010_11, // custom-0 instruction type (see ISA Vol 1 Chapter 24)
    op_shutdown = 7'b01_010_11, // custom-1, run this to shut the CPU down
`endif // MITSHD_LAB6

    op_illegal  = 7'b0000000 // Catch-all for an illegal instruction
} rv_opcode /*verilator public*/;

// Different func3 values for ALU operations
typedef enum logic[2:0] {
    func3_add   = 3'b000, // If func7[5] is 1 this becomes sub
    func3_sll   = 3'b001,
    func3_slt   = 3'b010,
    func3_sltu  = 3'b011,
    func3_xor   = 3'b100,
    func3_srl   = 3'b101, // If func7[5] is 1 this becomes sra
    func3_or    = 3'b110,
    func3_and   = 3'b111
} func3_alu /*verilator public*/;

// Different func3 values for load / store ops
typedef enum logic[2:0] {
    func3_byte  = 3'b000,
    func3_half  = 3'b001,
    func3_word  = 3'b010,

    // Only load uses unsigned
    func3_ubyte = 3'b100,
    func3_uhalf = 3'b101
} func3_mem /*verilator public*/;

// Different func3 values for CSR* instructions
typedef enum logic[2:0] {
    func3_ecall     = 3'b000, // ecall/ ebreak/ wfi
    func3_csrrw     = 3'b001, // Read CSR into RD, Write RS1 into CSR
    func3_csrrs     = 3'b010, // Read CSR into RD, Bit Set RS1 into CSR
    func3_csrrc     = 3'b011, // Read CSR into RD, Bit Clear RS1 into CSR
    func3_csrrwi    = 3'b101, // Read CSR into RD, Write zext(rs1_idx as uimm) into CSR
    func3_csrrsi    = 3'b110, // Read CSR into RD, Bit Set zext(rs1_idx as uimm) into CSR
    func3_csrrci    = 3'b111  // Read CSR into RD, Bit Clear zext(rs1_idx as uimm) into CSR
} func3_csr /*verilator public*/;

// CSR
typedef enum logic[11:0] {
    imm_csr_mtvec = 12'h305,
    imm_csr_mepc  = 12'h341,
    imm_csr_mpp   = 12'h399,
    imm_csr_ecall = 12'b000000000000,
    imm_csr_mret  = 12'b001100000010
} imm_csr /*verilator public*/;

// ALU commands
// The compare commands run on the compare unit instead of ALU
// ALU has dedicated add and sub modes- could combine into 1 adder, but
// would need extra hardware in decode stage to negate rs2, which is the same
// cost as just adding a sub function to the ALU
typedef enum logic[2:0] {
    alu_add     = 3'b000,
    alu_sll     = 3'b001,
    alu_sra     = 3'b010,
    alu_sub     = 3'b011,
    alu_xor     = 3'b100,
    alu_srl     = 3'b101,
    alu_or      = 3'b110,
    alu_and     = 3'b111
} alu_cmd /*verilator public*/;

// Comparison commands
// Used by conditional branch instructions and SLT / SLTU (register and imm modes)
typedef enum logic[2:0] {
    // ==
    cmp_eq      = 3'b000,
    cmp_neq     = 3'b001,

    // <
    cmp_lt      = 3'b100,
    cmp_ltu     = 3'b110,

    // >=
    cmp_ge      = 3'b101,
    cmp_geu     = 3'b111
} cmp_cmd /*verilator public*/;

// What gets written back to a register?
typedef enum logic[2:0] {
    wb_alu, // Write back alu value
    wb_cmp, // Write back cmp value
    wb_mem, // Write back memory data read
    wb_ret, // Write back return address, used by JAL/ JALR
    wb_imm, // Write back immediate value only, only used by LUI
    wb_csr  // Write back zext(CSR value)
} wb_cmd /*verilator public*/;

// Cache coherence states
typedef enum logic[1:0] {
    cache_invalid    = 0,     // Invalid line
    cache_modified   = 1,     // Modified line
    cache_shared     = 2      // Shared line (unmodified, read only)
} cache_line_state;

typedef struct packed {
    // Is this word valid?
    logic valid;

    // Raw memory from fetch:
    logic[31:0] instruction;
    logic[31:0] pc; // Address of this instruction

    /*
     * Decode-created signals
     */
    rv_opcode opcode;
    logic[4:0] rs1_idx, rs2_idx, rd_idx;
    logic[31:0] rs1_val, rs2_val, rd_val;
    logic[31:0] csr_read_val;
    logic load_rd;

    // What to load the new CSR with?
    // This is calculated in execute and then performed in writeback
    // Since system ops block new instructions from entering the pipeline,
    // This is 100% atomic with respect to the core as a whole.
    logic[31:0] csr_val;
    logic load_csr;

    // Push/ pop secure stack?
    logic secure_push, secure_pop;

    logic[6:0] func7;
    logic[2:0] func3;

    // Fully sign extended immediate values per instruction type
    logic[31:0] i_imm, s_imm, b_imm, u_imm, j_imm;
    logic[31:0] imm; // <- Which ever kind of instruction it is, this is the correct imm

    alu_cmd alu_command;

    // alu_mux1: 0 = rs1, 1 = PC
    logic alu_mux1;

    // alu_mux2: 0 = rs2, 1 = imm
    logic alu_mux2;

    cmp_cmd cmp_command;

    // cmp_mux: 0 = rs2, 1 = imm
    logic cmp_mux;

    logic[3:0] mem_mask;

    wb_cmd wb_command;

    /*
     * Execute-created signals
     */
    logic[31:0] alu_out;
    logic cmp_out;

    /*
     * Memory-created signals
     */

    // Primarily used for rvfi purposes:
    logic[3:0] dmem_mask;
    logic dmem_write_en;
    logic[31:0] dmem_wdata;

    /*
     * Exception/ Interrupt signals
     */
    logic intr; // For RVFI, this is set high when an exception / interrupt happens

    /*
     * Privileged architecture signals
     * An instruction that changes its privilege level does so in execute.
     * commit_priv_level is set to the new privilege level and is readable starting in the memory stage.
     */
    logic[1:0] decode_priv_level; // The privilege level our instruction was decoded at
    logic[1:0] commit_priv_level; // The privilege level our instruction committed with

    // RVFI stuff
    logic[31:0] pc_next; // PC written by this instruction (usually PC + 4)

`ifdef MITSHD_LAB6
    logic alu_should_glitch; // Should the ALU miscompute if the operands are wrong?
                             // This signal is used to make sure the ALU computes things
                             // like jump targets always correctly while allowing the
                             // `add` instruction to fail.
    logic should_shutdown;   // When this hits writeback, we shut down the simulator
`endif // MITSHD_LAB6
} controlword /*verilator public*/;

`endif // DEFINES
