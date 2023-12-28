TARGET:=(obj_dir/Vpsp)

$(TARGET): $(shell find . -maxdepth 1 -name "*.cpp" -or -name "*.c" -or -name "*.cc" -or -name "*.hpp" -or -name "*.h" -or -name "*.hh") $(shell find ../hdl -name "*.sv")
	@./build.sh

.PHONY: clean
clean:
	@./clean.sh
