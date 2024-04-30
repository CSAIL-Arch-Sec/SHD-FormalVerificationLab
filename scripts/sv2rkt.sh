#!/bin/bash

# STEP1: Clean up old files
rm generated_src/core_to_verify.v \
   generated_src/core_to_verify.smt2 \
   generated_src/core_to_verify.rkt


# STEP2: Generate verilog file from system verilog
sv2v -I=core_to_verify -I=core_to_verify/interfaces -I=core_to_verify/core \
     -y=core_to_verify/core -w=generated_src/core_to_verify.v \
     core_to_verify/core_to_verify.sv


# STEP3: Generate SMT2 file from verilog
yosys -s scripts/yosys_command.ys
rm generated_src/core_to_verify.v


# STEP4: Generate Rosette file from SMT2
echo "#lang yosys" > generated_src/core_to_verify.rkt
cat generated_src/core_to_verify.smt2 >> generated_src/core_to_verify.rkt
rm generated_src/core_to_verify.smt2

