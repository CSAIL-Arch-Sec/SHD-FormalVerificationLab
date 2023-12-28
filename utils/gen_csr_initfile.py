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

# Genereate the CSR initialization file

# Defined CSRs (keep this in sync with csr.sv)
CSR_MHARTID     = 0xf14
CSR_MSTATUS     = 0x300
CSR_MSTATUSH    = 0x310
CSR_MIE         = 0x304
CSR_MTVEC       = 0x305
CSR_MSCRATCH    = 0x340
CSR_MEPC        = 0x341
CSR_MCAUSE      = 0x342
CSR_MTVAL       = 0x343
CSR_MIP         = 0x344
CSR_MPP         = 0x399
CSR_MPIE        = 0x398
CSR_MIPI_ISSUER = 0x397


# Special MIT SHD Lab 6 Flag CSRS
MIT_SHD_FLAG_CSR_START=0xFC0
MIT_SHD_FLAG_CSR_END=0xFF0

# MITSHD_FLAG=b"MIT{this_is_the_last_flag_of_shd}"
MITSHD_FLAG=b"MIT{th3_r34l_f1n4l_fl4g_0f_shd!!}"
MITSHD_FLAG_BYTES=[MITSHD_FLAG[i:i+4] for i in range(0, len(MITSHD_FLAG), 4)]

NUM_CSRS=4096

# Put 4 chars per CSR:
# for i in range(NUM_CSRS):
# 	if i < MIT_SHD_FLAG_CSR_START or i >= MIT_SHD_FLAG_CSR_END:
# 		# Not in the flags range, zero init
# 		print("00000000")
# 	else:
# 		# Could be a flag register, but depends on the length of the flag
# 		flag_idx = i-MIT_SHD_FLAG_CSR_START
# 		if flag_idx < len(MITSHD_FLAG_BYTES):
# 			print(f"FLAG ({i}): {MITSHD_FLAG_BYTES[flag_idx]}")
# 			print(f"{MITSHD_FLAG_BYTES[flag_idx].hex().rjust(8,'0')}")
# 		else:
# 			print("00000000")

# Simpler: put 1 char per CSR:
#### PRINT csr_file.mem ####
for i in range(NUM_CSRS):
	if i < MIT_SHD_FLAG_CSR_START or i >= MIT_SHD_FLAG_CSR_END:
		# Not in the flags range, zero init
		print("00000000")
	else:
		# Could be a flag register, but depends on the length of the flag
		flag_idx = i-MIT_SHD_FLAG_CSR_START
		if flag_idx < len(MITSHD_FLAG):
			# print(f"FLAG ({i}): {chr(MITSHD_FLAG[flag_idx])}")
			print(f"{hex(MITSHD_FLAG[flag_idx])[2:].rjust(8,'0')}")
		else:
			print("00000000")

# #### PRINT dump_flag ####
# for i in range(len(MITSHD_FLAG)):
# 	print(f"csrr a0, {hex(i+MIT_SHD_FLAG_CSR_START)}")
# 	print(f"jal print_char")
