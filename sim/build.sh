#!/bin/bash
# Verilate the design into obj_dir
verilator --cc -I../hdl -I../hdl/core -I../hdl/memory -I../hdl/interfaces -I../hdl/ring ../hdl/psp.sv --public-flat-rw -Wno-UNOPTFLAT -Wno-UNOPT -Wno-CASEINCOMPLETE -Wno-WIDTH --exe $(find . -maxdepth 1 -name "*.cpp") --build -j -LDFLAGS "-g -lpthread" -CFLAGS "-g"
