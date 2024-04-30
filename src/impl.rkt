#lang rosette

(require
  "../generated_src/core_to_verify.rkt"
  "array/imem.rkt" "array/dmem.rkt"
  "param/inst.rkt" "param/veri.rkt"
)

(provide init-impl step-impl! impl-archState impl-justCommit impl->string)


; STRUCT: The memory in the implementation takes 1 cycle to finish a read/write.
;         In cycle 0, it saves the inputs to the memory into input registers
;         (i.e., this `memInputReg` struct).
;         In cycle 1, using the request information in the input registers, it
;         writes to the memory array or reply the read data.
(struct memInputReg (
  imem_addr imem_read_en
  dmem_addr dmem_read_en dmem_write_en dmem_data_en dmem_data_i)
  #:mutable #:transparent
)


; FUNC: Initialize an instance of `memInputReg` data structure with 0s and
;       return it.
(define (init-reset-memInputReg)
  (memInputReg
    (bv 0 32) #f
    (bv 0 32) #f #f (bv 0 4) (bv 0 32)
  )
)


; STRUCT: Store all archiecture and micro-architecture states defined in the
;         implementation.
(struct impl (core imem dmem memInputReg)
  #:mutable #:transparent
)


; FUNC: Initialize an instance of `impl` data structure with 0s, reset it, and
;       return it.
(define (init-impl imem dmem)

  ; STEP: Initialize a new core whose states are all zeros.
  (define core (new-zeroed-core_to_verify_s))

  ; STEP: To reset the core, we pull up the the reset signal and step core
  ;       state to next cycle. "step" just means simulate by 1 cycle.
  (set! core (step (with-input core (input* 'reset #t))))

  ; STEP: Reset the memory input registers.
  (define memInputReg (init-reset-memInputReg))

  ; STEP: Return the full reset state.
  (impl core imem dmem memInputReg)
)


; FUNC: Simulate the implementation by 1 cycle.
(define (step-impl! impl)

  ; STEP: Short names for some data stored in the data structure `impl`.
  (define core        (impl-core        impl))
  (define imem        (impl-imem        impl))
  (define dmem        (impl-dmem        impl))
  (define memInputReg (impl-memInputReg impl))

  (define imem_addr     (memInputReg-imem_addr     memInputReg))
  (define imem_read_en  (memInputReg-imem_read_en  memInputReg))
  (define dmem_addr     (memInputReg-dmem_addr     memInputReg))
  (define dmem_read_en  (memInputReg-dmem_read_en  memInputReg))
  (define dmem_write_en (memInputReg-dmem_write_en memInputReg))
  (define dmem_data_en  (memInputReg-dmem_data_en  memInputReg))
  (define dmem_data_i   (memInputReg-dmem_data_i   memInputReg))


  ; STEP: Using the read request in the input buffer, read from memory
  (define imem_data_o (if imem_read_en (imem-read imem imem_addr)
                                       (bv 0 32)))
  (define dmem_data_o (if dmem_read_en (dmem-read dmem dmem_addr)
                                       (bv 0 32)))

  ; STEP: Using the write request in the input buffer, write to memory
  (when dmem_write_en
    (set-impl-dmem! impl (dmem-write dmem dmem_addr dmem_data_en dmem_data_i)))

  ; STEP: Using the output from the core, update the input buffer of the memory
  (define core-output (get-output core))
  (set-memInputReg-imem_addr!     memInputReg
                                  (output-imem_addr core-output))
  (set-memInputReg-imem_read_en!  memInputReg
                                  (output-imem_read_en core-output))
  (set-memInputReg-dmem_addr!     memInputReg
                                  (output-dmem_addr core-output))
  (set-memInputReg-dmem_read_en!  memInputReg
                                  (output-dmem_read_en core-output))
  (set-memInputReg-dmem_write_en! memInputReg
                                  (output-dmem_write_en core-output))
  (set-memInputReg-dmem_data_en!  memInputReg
                                  (output-dmem_data_en core-output))
  (set-memInputReg-dmem_data_i!   memInputReg
                                  (output-dmem_data_i core-output))

  ; STEP: Step the core state to next cycle.
  (set-impl-core! impl
    (step (with-input core (input* 'reset #f
                                   'imem_data_o imem_data_o
                                   'dmem_data_o dmem_data_o))))
)


; FUNC: Extract the architectural state of the implementation that will be
;       compared with the specification. All information are encoded into a
;       long bitvector.
(define (impl-archState impl)
  (define core (impl-core impl))
  (define core-output (get-output core))
  (define nextpc_to_commit (output-nextpc_to_commit core-output))
  (define csr_mtvec        (output-csr_mtvec        core-output))
  (define csr_mepc         (output-csr_mepc         core-output))
  (define csr_mpp          (output-csr_mpp          core-output))
  (define privilege        (output-privilege        core-output))

  (concat
    nextpc_to_commit
    (core_to_verify_s-core_inst.regs|[1]| core)
    (core_to_verify_s-core_inst.regs|[2]| core)
    (core_to_verify_s-core_inst.regs|[3]| core)
    (core_to_verify_s-core_inst.regs|[4]| core)
    (core_to_verify_s-core_inst.regs|[5]| core)
    (core_to_verify_s-core_inst.regs|[6]| core)
    (core_to_verify_s-core_inst.regs|[7]| core)
    (core_to_verify_s-core_inst.regs|[8]| core)
    (core_to_verify_s-core_inst.regs|[9]| core)
    (core_to_verify_s-core_inst.regs|[10]| core)
    (core_to_verify_s-core_inst.regs|[11]| core)
    (core_to_verify_s-core_inst.regs|[12]| core)
    (core_to_verify_s-core_inst.regs|[13]| core)
    (core_to_verify_s-core_inst.regs|[14]| core)
    (core_to_verify_s-core_inst.regs|[15]| core)
    (core_to_verify_s-core_inst.regs|[16]| core)
    (core_to_verify_s-core_inst.regs|[17]| core)
    (core_to_verify_s-core_inst.regs|[18]| core)
    (core_to_verify_s-core_inst.regs|[19]| core)
    (core_to_verify_s-core_inst.regs|[20]| core)
    (core_to_verify_s-core_inst.regs|[21]| core)
    (core_to_verify_s-core_inst.regs|[22]| core)
    (core_to_verify_s-core_inst.regs|[23]| core)
    (core_to_verify_s-core_inst.regs|[24]| core)
    (core_to_verify_s-core_inst.regs|[25]| core)
    (core_to_verify_s-core_inst.regs|[26]| core)
    (core_to_verify_s-core_inst.regs|[27]| core)
    (core_to_verify_s-core_inst.regs|[28]| core)
    (core_to_verify_s-core_inst.regs|[29]| core)
    (core_to_verify_s-core_inst.regs|[30]| core)
    (core_to_verify_s-core_inst.regs|[31]| core)

    ; [Exercise 3-4]: Selectively uncomment following 4 lines according to your
    ;                 `spec-archState` fucntion.
    ; csr_mtvec  ; 32-bit bitvector
    ; csr_mepc   ; 32-bit bitvector
    ; csr_mpp    ; 32-bit bitvector
    ; privilege  ; 2-bit bitvector
  )
)


; FUNC: Return the justCommit signal in the tiny_cpu. It means whether it just
;       committed an instruction in the last simulated cycle.
(define (impl-justCommit impl)
  (define core (impl-core impl))
  (define core-output (get-output core))
  (define just_commit (output-just_commit core-output))

  just_commit
)


; FUNC: Convert the `impl` data structure to string for a nice printing.
(define (impl->string impl)
  (define core (impl-core impl))
  (define dmem (impl-dmem impl))

  (define core-output (get-output core))
  (define just_commit         (output-just_commit         core-output))
  (define just_committed_pc   (output-just_committed_pc   core-output))
  (define just_committed_inst (output-just_committed_inst core-output))
  (define nextpc_to_commit    (output-nextpc_to_commit    core-output))
  (define csr_mtvec           (output-csr_mtvec           core-output))
  (define csr_mepc            (output-csr_mepc            core-output))
  (define csr_mpp             (output-csr_mpp             core-output))
  (define privilege           (output-privilege           core-output))


  (~a
    (format "pc: 0x~x  "
            (bitvector->natural nextpc_to_commit))
    (format "rf: [0x0, 0x~x, 0x~x, 0x~x]\n"
            (bitvector->natural (core_to_verify_s-core_inst.regs|[1]| core))
            (bitvector->natural (core_to_verify_s-core_inst.regs|[2]| core))
            (bitvector->natural (core_to_verify_s-core_inst.regs|[3]| core)))
    
    (format "csr: [mtvec: 0x~x, mepc: 0x~x, mpp: 0x~x]  "
            (bitvector->natural csr_mtvec)
            (bitvector->natural csr_mepc)
            (bitvector->natural csr_mpp))
    "privilege: " (bitvector->natural privilege)
    "\n"
    
    (format "dmem: [0x~x, 0x~x, 0x~x, 0x~x, 0x~x, 0x~x, 0x~x, 0x~x]\n"
            (bitvector->natural (dmem-read dmem (bv  0 32)))
            (bitvector->natural (dmem-read dmem (bv  4 32)))
            (bitvector->natural (dmem-read dmem (bv  8 32)))
            (bitvector->natural (dmem-read dmem (bv 12 32)))
            (bitvector->natural (dmem-read dmem (bv 16 32)))
            (bitvector->natural (dmem-read dmem (bv 20 32)))
            (bitvector->natural (dmem-read dmem (bv 24 32)))
            (bitvector->natural (dmem-read dmem (bv 28 32))))
    
    "just_commit: " just_commit "  "
    (if just_commit
      (~a
        (format "just_committed_pc: 0x~x\n"
                (bitvector->natural just_committed_pc))
        "just_committed_inst: "
        (inst->string just_committed_inst)
        "\n"
      )
      "\n")
  )
)


; FUNC: A test function for the code in this file.
(define (testMe)

  ; STEP: Initialize an instance of `impl` with a concret debug instruction
  ;       memory `imem` and a all-zero data memory `dmem`.
  (define imem (init-debug-imem))
  (define dmem (init-zero-dmem))
  (define impl (init-impl imem dmem))
  

  ; STEP: Print out the initial state of `imem` and `impl`.
  (printf (~a
    "[simu] INIT\n"
    "********* imem *********\n" (imem->string imem) "\n"
    "********* impl *********\n" (impl->string impl) "\n"
  ))


  ; STEP: Simulate the `spec` for 10 cycle.
  (for ([i (in-range 10)])
    (printf (~a "[simu] Cycle " (+ i 1) " Start... "))
    (step-impl! impl)
    (printf (~a " ...End\n"))

    (printf (~a "********* impl *********\n" (impl->string impl) "\n"))
  )
)
(module+ main (testMe))

