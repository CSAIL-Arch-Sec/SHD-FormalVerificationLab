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

`ifndef PSP_CSR_HEADER
`define PSP_CSR_HEADER

/*
 * A map of all PSP CSR registers
 *
 * Much of this is in compliance with the Risc V ISA
 * See the Risc V Specification Volume II for more info
 */

// How long are CSR addresses?
parameter int CSR_ADDR_SIZE = 12;

// Various parameters related to opcodes

// i_imm values for ecall & ebreak:
parameter CSR_IMM_ECALL = 12'b0;
parameter CSR_IMM_EBREAK = 12'b1;

// i_imm values for *ret
parameter CSR_IMM_URET = 12'b0000000_00010;
parameter CSR_IMM_SRET = 12'b0001000_00010;
parameter CSR_IMM_MRET = 12'b0011000_00010;

// i_imm value for WFI
parameter CSR_IMM_WFI  = 12'b0001000_00101;

/*
 * User level CSRs
 */
// User Trap Setup
// parameter   ustatus     =       12'h000;
// parameter   uie         =       12'h004;
// parameter   utvec       =       12'h005;

// // User Trap Handling
// parameter   uscratch    =       12'h040;
// parameter   uepc        =       12'h041;
// parameter   ucause      =       12'h042;

// NON-STANDARD
// utimer is a timer that contains the number of cycles accessible from usermode
parameter utimer        =       12'h037;

/*
 * Machine level CSRs
 */

// Hart (hardware thread) ID
parameter   mhartid     =       12'hf14;

// Status configuration register
parameter   mstatus     =       12'h300;
parameter   mstatush    =       12'h310;

// NON-STANDARD
// Interrupt enable
// For PSP only the lowest bit of mie means anything- when it is 0, interrupts
// are completely disabled, otherwise they are enabled.
// Also mpie is a separate CSR rather than being a field in mstatus
parameter   mie         =       12'h304;
parameter   mpie        =       12'h398;

// Machine trap vector table (pc is loaded with this CSR at exception/ interrupt)
parameter   mtvec       =       12'h305;

// Machine scratch register
parameter   mscratch    =       12'h340;

// Exception PC (saved PC)
parameter   mepc        =       12'h341;

// Exception cause
parameter   mcause      =       12'h342;

// Exception value
parameter   mtval       =       12'h343;

// Interrupt pending
parameter   mip         =       12'h344;

// NON-STANDARD
// Instead of putting mpp (previous priv level) in status I'm just putting it in its own CSR
// Sue me
parameter mpp           =       12'h399;

// NON-STANDARD
// IPI Issuing core hart ID
parameter mipi_issuer   =       12'h397;

// NON-STANDARD
// Emulated per-core serial port using CSRs
parameter csr_serial_flags = 12'h200;
parameter csr_serial_io_in = 12'h201;
parameter csr_serial_io_out = 12'h202;

/*
 * Interrupt causes
 * These are loaded into mcause and tell the handler why it happened
 */

// This happens if user tries to do a CSR* instruction
parameter EXCEPTION_CAUSE_ILLEGAL_ACCESS = 32'h1;

// While this is the RISC-V ISA Privileged Spec value for this kind of exception flavor,
// this is very non-standard as only some illegal instructions are treated as invalid by us.
// For example, the unimp instruction is NOT illegal as it has a valid opcode but invalid operands,
// for now we only check opcodes.
parameter EXCEPTION_CAUSE_INVALID_INSTRUCTION = 32'h2;

// External interrupt at machine level
parameter EXCEPTION_CAUSE_EXTERNAL = {1'b1, 31'd11};

// NON STANDARD to Risc-V ISA
// IPI Interrupt issued via IPI ring
parameter EXCEPTION_CAUSE_IPI = {1'b1, 31'd12};

// Ecall from various levels
parameter EXCEPTION_CAUSE_ECALL_U = 32'd8;
parameter EXCEPTION_CAUSE_ECALL_S = 32'd9;
parameter EXCEPTION_CAUSE_ECALL_M = 32'd11;

// Privilege levels
parameter PSP_PRIV_USER     =   2'b00;
parameter PSP_PRIV_MACHINE  =   2'b11;

`endif // CSR_H
