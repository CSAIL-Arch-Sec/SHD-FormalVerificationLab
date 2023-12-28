# Secure Hardware Design Formal Verification Lab
Development repo for MIT SHD's Formal Verification Lab

This repository contains the source code for the MIT SHD Fuzzing Lab CPU (Pretty Secure Processor), created by Joseph Ravichandran.

# Codebase

`hdl` contains the SystemVerilog implementation of the CPU.
The intended top level is `hdl/psp.sv` for use on a Zynq FPGA and contains bindings to the RISC-V formal verification framework for dynamic device testing.
Or, you can use `hdl/psp_system.sv` as a top level if you want.

`hvl` contains a variety of test benches designed to test various functionality of the CPU.
Most of these test cases are a few years old and were only used for testing the early boostrapping of the core and are likely not functional anymore (deprecated in favor of the Verilator testbench).

`kernel` contains a sample C and assembly project as provided to students with the Fuzzing lab.
It is identical to `part2` of the Spring 2023 student distribution, except for a cosmetic change of the banner title.
Build the kernel with `cd kernel; make` and you will have a sample memory initialization file to run in the simulator.

`sim` contains the Verilator testbench and graphical interface simulator.

`utils` contains a variety of useful Python utilities and various scripts.

`csr_file.mem` is a sample CSR memory initialization file that creates a sample flag for Part 4 of the fuzzing lab and sets it to `MIT{example_flag_example_flag_ex}`, and zero initializes all other CSRs (save for the special six registers as defined below, which are always zero initialized).
You will need a CSR memory initialization file of some kind to run the simulator- use this one.

`debug.sh` is used for informing the `run.sh` script which GDB port to host the simulator GDB debug server at.

`gdb.sh` can be used for launching the simulator with GDB to debug the kernel.
It requires a kernel memory initialization file and kernel symbol file (eg. the ELF binary).

`run.sh` launches a given kernel on the simulator.
Run with `./run.sh kernel`.

`synth.ys` is a sample Yosys script from very early on in the CPU's development.

### CSR Issue
This version of the CPU (updated for Spring 2024) has been forked from the original implementation to resolve an issue caused by control and status registers (CSRs), due to the original implementation making use of a large SV array instead of individual registers (making it hard for Rosette to reason about data flow through the CSR register file).

This was solved by separating six key CSRs from the rest of the file- namely, `csr_mepc`, `csr_mie`, `csr_mtvec`, `csr_mpp`, `csr_mpie`, and `csr_utimer` have been broken out into distinct registers instead of being part of the table.

