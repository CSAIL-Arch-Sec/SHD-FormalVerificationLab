#lang rosette

(provide (all-defined-out))


; PART: Helper function to extract certain fields from instrucions, according
;       to the ISA Specification.
(define (inst-op    inst) (extract  6  0 inst))
(define (inst-func3 inst) (extract 14 12 inst))
(define (inst-func7 inst) (extract 31 25 inst))
(define (inst-rs1   inst) (extract 19 15 inst))
(define (inst-rs2   inst) (extract 24 20 inst))
(define (inst-rd    inst) (extract 11  7 inst))

(define (inst-imm-I inst) (sign-extend
                            (extract 31 20 inst)
                            (bitvector 32)))
(define (inst-imm-S inst) (sign-extend
                            (concat (extract 31 25 inst) (extract 11 7 inst))
                            (bitvector 32)))
(define (inst-imm-B inst) (sign-extend
                            (concat (extract 31 31 inst) (extract  7 7 inst)
                                    (extract 30 25 inst) (extract 11 8 inst)
                                    (bv 0 1))
                            (bitvector 32)))
(define (inst-imm-U inst) (concat (extract 31 12 inst) (bv 0 12)))
(define (inst-imm-J inst) (sign-extend
                            (concat (extract 31 31 inst) (extract 19 12 inst)
                                    (extract 20 20 inst) (extract 30 21 inst)
                                    (bv 0 1))
                            (bitvector 32)))

(define (inst-imm-CSR inst) (extract 31 20 inst))




; PART: Some constant numbers, according to the ISA definition.
;       Not all of them will be used in this lab.
(define op-lui   (bv #b0110111 7))
(define op-auipc (bv #b0010111 7))
(define op-jal   (bv #b1101111 7))
(define op-jalr  (bv #b1100111 7))
(define op-br    (bv #b1100011 7))
(define op-load  (bv #b0000011 7))
(define op-store (bv #b0100011 7))
(define op-imm   (bv #b0010011 7))
(define op-reg   (bv #b0110011 7))
(define op-sys   (bv #b1110011 7))
(define op-scall (bv #b1010011 7))
(define op-sret  (bv #b1010110 7))

(define func3-add  (bv #b000 3))
(define func3-sll  (bv #b001 3))
(define func3-slt  (bv #b010 3))
(define func3-sltu (bv #b011 3))
(define func3-xor  (bv #b100 3))
(define func3-srl  (bv #b101 3))
(define func3-or   (bv #b110 3))
(define func3-and  (bv #b111 3))

(define func3-eq  (bv #b000 3))
(define func3-neq (bv #b001 3))
(define func3-lt  (bv #b100 3))
(define func3-ge  (bv #b101 3))
(define func3-ltu (bv #b110 3))
(define func3-geu (bv #b111 3))

(define func3-byte  (bv #b000 3))
(define func3-half  (bv #b001 3))
(define func3-word  (bv #b010 3))
(define func3-ubyte (bv #b100 3))
(define func3-uhalf (bv #b101 3))

(define func3-ecall  (bv #b000 3))
(define func3-csrrw  (bv #b001 3))
(define func3-csrrs  (bv #b010 3))
(define func3-csrrc  (bv #b011 3))
(define func3-csrrwi (bv #b101 3))
(define func3-csrrsi (bv #b110 3))
(define func3-csrrci (bv #b111 3))


(define func7-0 (bv #b0000000 7))
(define func7-1 (bv #b0100000 7))

(define imm-CSR-mtvec (bv #x305 12))
(define imm-CSR-mepc  (bv #x341 12))
(define imm-CSR-mpp   (bv #x399 12))
(define imm-CSR-ecall (bv #b000000000000 12))
(define imm-CSR-mret  (bv #b001100000010 12))

(define func3-unused (bv #b000 3))
(define rs1-unused   (bv #b00000 5))
(define rd-unused    (bv #b00000 5))

(define privilege-user    (bv 0 2))
(define privilege-machine (bv 3 2))




; PART: Functions to decode instructions
(define (isLUI   inst) (bveq (inst-op inst) op-lui))

(define (isBEQ  inst) (and
  (bveq (inst-op inst) op-br) (bveq (inst-func3 inst) func3-eq)))

(define (isLW  inst) (and
  (bveq (inst-op inst) op-load)  (bveq (inst-func3 inst) func3-word)))
(define (isSW  inst) (and
  (bveq (inst-op inst) op-store) (bveq (inst-func3 inst) func3-word)))

(define (isADDI  inst) (and
  (bveq (inst-op    inst) op-imm) (bveq (inst-func3 inst) func3-add)))
(define (isSRLI  inst) (and
  (bveq (inst-op    inst) op-imm) (bveq (inst-func3 inst) func3-srl)
  (bveq (inst-func7 inst) func7-0)))

(define (isADD  inst) (and
  (bveq (inst-op    inst) op-reg) (bveq (inst-func3 inst) func3-add)
  (bveq (inst-func7 inst) func7-0)))

(define (isECALL inst) (and
  (bveq (inst-op      inst) op-sys) (bveq (inst-func3 inst) func3-ecall)
  (bveq (inst-imm-CSR inst) imm-CSR-ecall)
  (bveq (inst-rs1     inst) rs1-unused)
  (bveq (inst-rd      inst) rd-unused)))
(define (isCSRRW inst) (and
  (bveq (inst-op      inst) op-sys) (bveq (inst-func3 inst) func3-csrrw)))
(define (isMRET  inst) (and
  (bveq (inst-op      inst) op-sys) (bveq (inst-func3 inst) func3-ecall)
  (bveq (inst-imm-CSR inst) imm-CSR-mret)
  (bveq (inst-rs1     inst) rs1-unused)
  (bveq (inst-rd      inst) rd-unused)))




; PART: Print instructions in a nice way.
(define (inst->string inst)

  (define op    (bitvector->natural (inst-op    inst)))
  (define func3 (bitvector->natural (inst-func3 inst)))
  (define func7 (bitvector->natural (inst-func7 inst)))
  (define rs1   (bitvector->natural (inst-rs1   inst)))
  (define rs2   (bitvector->natural (inst-rs2   inst)))
  (define rd    (bitvector->natural (inst-rd    inst)))

  (define imm-I   (bitvector->natural (inst-imm-I   inst)))
  (define imm-S   (bitvector->natural (inst-imm-S   inst)))
  (define imm-B   (bitvector->natural (inst-imm-B   inst)))
  (define imm-U   (bitvector->natural (inst-imm-U   inst)))
  (define imm-J   (bitvector->natural (inst-imm-J   inst)))
  (define imm-CSR (bitvector->natural (inst-imm-CSR inst)))

  (cond
    ; LUI
    [(isLUI inst)
      (format "LUI  rf[~a] <- 0x~x" rd imm-U)]
    
    ; BEQ
    [(isBEQ inst)
      (format "BEQ  if (rf[~a] == rf[~a]) pc <- pc + 0x~x" rs1 rs2 imm-B)]
    
    ; LW
    [(isLW inst)
      (format "LW   rf[~a] <- dmem[rf[~a] + 0x~x]" rd rs1 imm-I)]
    
    ; SW
    [(isSW inst)
      (format "SW   dmem[rf[~a] + 0x~x] <- rf[~a]" rs1 imm-S rs2)]
    
    ; ADDI
    [(isADDI inst)
      (format "ADDI rf[~a] <- rf[~a] + 0x~x" rd rs1 imm-I)]
    
    ; SRLI
    [(isSRLI inst)
      (format "SRLI rf[~a] <- rf[~a] >> 0x~x" rd rs1 imm-I)]
    
    ; ADD
    [(isADD inst)
      (format "ADD  rf[~a] <- rf[~a] + rf[~a]" rd rs1 rs2)]
    
    ; ECALL
    [(isECALL inst)
      (format "ECALL")]
    
    ; CSRRW
    [(isCSRRW inst)
      (format "CSRRW rf[~a] <- csr[0x~x]; csr[0x~x] <- rf[~a]" 
              rd imm-CSR imm-CSR rs1)]
    
    ; MRET
    [(isMRET inst)
      (format "MRET")]
    
    [else
      (format "UNDEFINED (inst: 0x~x, func7: ~b, rs2: ~b, rs1: ~b, func3: ~b, rd: ~b, op: ~b)"
              (bitvector->natural inst) func7 rs2 rs1 func3 rd op)
    ]
  )

)

