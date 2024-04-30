#lang rosette

(require "../param/inst.rkt" "../param/veri.rkt")

(provide
  init-zero-csr csr-read write-csr! csr-hasPrivilege csr->bv csr->string
)


; STRUCT: Store 3 supported CSRs.
(struct csr (mtvec mepc mpp) #:mutable #:transparent)


; FUNC: Initialize an instance of `csr` data structure with 0s and return it.
(define (init-zero-csr)
  (csr (bv 0 32) (bv 0 32) (bv 0 32))
)


; FUNC: Return the CSR indexed by `pos`. For unsupported CSRs, return 0.
(define (csr-read csr pos)
  (cond
    [(bveq pos imm-CSR-mtvec) (csr-mtvec csr)]
    [(bveq pos imm-CSR-mepc ) (csr-mepc  csr)]
    [(bveq pos imm-CSR-mpp  ) (csr-mpp   csr)]
    [else (bv 0 32)]
  )
)


; FUNC: Write to the CSR indexed by `pos` with value `v`. For unsupported CSRs,
;       do nothing.
(define (write-csr! csr pos v)
  (cond
    [(bveq pos imm-CSR-mtvec) (set-csr-mtvec! csr v)]
    [(bveq pos imm-CSR-mepc ) (set-csr-mepc!  csr v)]
    [(bveq pos imm-CSR-mpp  ) (set-csr-mpp!   csr v)]
    [else (void)]
  )
)


; FUNC: Return whether `privilege` have the permission to access the CSR indexed
;       by `pos`. For unsupported CSRs, return #t.
(define (csr-hasPrivilege csr pos privilege)
  (cond
    [(bveq pos imm-CSR-mtvec) (bveq privilege privilege-machine)]
    [(bveq pos imm-CSR-mepc ) (bveq privilege privilege-machine)]
    [(bveq pos imm-CSR-mpp  ) (bveq privilege privilege-machine)]
    [else #t]
  )
)


; FUNC: Convert the 3 32-bit bitvectors to a single 3x32-bit bitvector. This
;       will be used to compare the architectural state of spec and impl.
(define (csr->bv csr)
  (concat (csr-mtvec csr) (csr-mepc csr) (csr-mpp csr))
)


; FUNC: Convert the 3 CSRs to string for a nice printing.
(define (csr->string csr)
  (~a (format "[mtvec: 0x~x, mepc: 0x~x, mpp: 0x~x]"
              (bitvector->natural (csr-mtvec csr))
              (bitvector->natural (csr-mepc  csr))
              (bitvector->natural (csr-mpp   csr))))
)

