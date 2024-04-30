#lang rosette

(require
  "array/rf.rkt" "array/csr.rkt" "array/imem.rkt" "array/dmem.rkt"
  "param/inst.rkt" "param/veri.rkt"
)

(provide init-spec step-spec! spec-archState spec-justCommit spec->string)


; STRUCT: Store all archiecture states defined in the ISA specification.
(struct spec (
  pc rf csr privilege imem dmem justCommit justCommitPC)
  #:mutable #:transparent
)


; FUNC: Initialize an instance of `spec` data structure and return it.
(define (init-spec imem dmem)
  (spec
    (bv 0 32)
    (init-zero-rf)
    (init-zero-csr)
    privilege-machine
    imem
    dmem
    #f
    (bv 0 32)
  )
)


; FUNC: Simulate the specification by 1 cycle.
(define (step-spec! spec)

  ; STEP: Short names for some data stored in the data structure `spec`.
  (define pc   (spec-pc   spec))
  (define rf   (spec-rf   spec))
  (define imem (spec-imem spec))


  ; STEP: Fetch the instruction.
  (define inst (imem-read imem pc))


  ; STEP: Decode some fields from the instruction.
  (define rd    (inst-rd    inst))
  (define imm-U (inst-imm-U inst))


  ; STEP: Execute the instruction.
  (cond
    ; LUI
    [(isLUI inst)
      ; STEP.1: Write the immediate number to the register file's `rd` entry.
      (write-rf! rf rd imm-U)

      ; STEP.2: Mark that an instruction is committed by this cycle of
      ;         simulation. The `veri.rkt` will use this information.
      (set-spec-justCommit!   spec #t)
      (set-spec-justCommitPC! spec pc)

      ; STEP.3: Increment PC.
      (set-spec-pc! spec (bvadd pc (bv 4 32)))
    ]

    ; [Exercise 1-3]: Support ADDI, SRLI, ADD, BEQ instructions.

    ; [Exercise 3-4]: Support all the 10 legal instructions.

    ; Illegal Instructions (or unimplemented instructions)
    [else
      ; [Exercise 3-1]: Illegal Instructions should trigger exceptions.
      (assume #f)
    ]
  )
)


; FUNC: Extract the architectural state of the specification that will be
;       compared with the implementation. All information are encoded into a
;       long bitvector.
(define (spec-archState spec)
  (concat
    (spec-pc spec)
    (rf->bv (spec-rf spec))
    ; [Exercise 3-4]: More state (e.g., CSRs, Privilege Level) could be,
    ;                 included, but you do not have to if you could find the
    ;                 backdoor otherwise. Remember to change the
    ;                 `impl-archState` function accordingly.
  )
)


; FUNC: Convert the `spec` data structure to string for a nice printing.
(define (spec->string spec)
  (define pc           (spec-pc           spec))
  (define rf           (spec-rf           spec))
  (define csr          (spec-csr          spec))
  (define privilege    (spec-privilege    spec))
  (define dmem         (spec-dmem         spec))
  (define justCommit   (spec-justCommit   spec))
  (define justCommitPC (spec-justCommitPC spec))


  (~a
    "pc: " (format "0x~x" (bitvector->natural pc)) "  "
    "rf: " (rf->string rf) "\n"
    "csr: " (csr->string csr) "  "
    "privilege: " (bitvector->natural privilege) "\n"
    "dmem: " (dmem->string dmem) "\n"
    "just_commit: " justCommit "  "
    (if justCommit
      (format "just_committed_pc: 0x~x\n" (bitvector->natural justCommitPC))
      "\n")
  )
)


; FUNC: A test function for the code in this file.
(define (testMe)

  ; STEP: Initialize an instance of `spec` with a concret debug instruction
  ;       memory `imem` and a all-zero data memory `dmem`.
  (define imem (init-debug-imem))
  (define dmem (init-zero-dmem))
  (define spec (init-spec imem dmem))
  

  ; STEP: Print out the initial state of `imem` and `spec`.
  (printf (~a
    "[simu] INIT\n"
    "********* imem *********\n" (imem->string imem) "\n"
    "********* spec *********\n" (spec->string spec) "\n"
  ))


  ; STEP: Simulate the `spec` for 5 cycle.
  (for ([i (in-range 5)])
    (printf (~a "[simu] Cycle " (+ i 1) " Start... "))
    (step-spec! spec)
    (printf (~a " ...End\n"))

    (printf (~a "********* spec *********\n" (spec->string spec) "\n"))
  )
)
(module+ main (testMe))
