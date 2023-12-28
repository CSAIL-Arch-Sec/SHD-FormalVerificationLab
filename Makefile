all: sim/obj_dir/Vpsp

sim/obj_dir/Vpsp: $(shell find sim -maxdepth 1 -name "*.cpp" -or -name "*.h" -or -name "*.c" -or -name "*.cc") $(shell find hdl -name "*.sv")
	@echo "SYN Vpsp"
	@cd sim ; make

.PHONY: clean
clean:
	@cd sim; make clean
