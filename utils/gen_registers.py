#!/usr/bin/env python3
# Pretty Secure System
# Joseph Ravichandran
# UIUC Senior Thesis Spring 2021
# MIT Secure Hardware Design Spring 2023
#
# MIT License
# Copyright (c) 2021-2023 Joseph Ravichandran
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Genereate the asm-offset function body contents for creating the assembly-c shared struct headers.

NUM_REGS=31

for i in range(NUM_REGS):
	reg_idx = i + 1
	print(f"EMIT_OFFSET(SAVED_REGS_X{reg_idx}, saved_regs_t, x{reg_idx});")

for i in range(NUM_REGS):
	reg_idx = i + 1
	print(f"sw x{reg_idx}, SAVED_REGS_X{reg_idx}(sp)")

for i in range(NUM_REGS):
	reg_idx = i + 1
	print(f"lw x{reg_idx}, SAVED_REGS_X{reg_idx}(sp)")

for i in range(NUM_REGS):
	reg_idx = i + 1
	print(f"la x{reg_idx}, 0x{reg_idx}{reg_idx}{reg_idx}{reg_idx}")

for i in range(NUM_REGS):
	reg_idx = i + 1
	print(f"printf(\"x{reg_idx}: 0x%X\\n\", saved_regs->x{reg_idx});")

for i in range(NUM_REGS):
	reg_idx = i + 1
	print(f"la x1, 0x{reg_idx}{reg_idx}{reg_idx}{reg_idx}")
	print(f"bne x1, x{reg_idx}, _exception_test_fail")

