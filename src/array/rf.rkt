#lang rosette

(require "../param/veri.rkt")

(provide
  init-zero-rf rf-read write-rf! rf->bv rf->string
)


; FUNC: Initialize a 32-entry vector to represent the register file.
;       Each entry is initialized to 0 whose type is 32-bit bitvector.
(define (init-zero-rf)
  (make-vector 32 (bv 0 32))
)


; FUNC: Read the `pos`-th entry.
(define (rf-read rf pos)
  
  ; NOTE: Constrain the search space by assume `pos` is between 0-2
  (when param-limit-space (assume (bvzero? (extract 4 2 pos))))
  
  (vector-ref-bv rf pos)
)


; FUNC: Write to the `pos`-th entry with value `v`.
(define (write-rf! rf pos v)

  ; NOTE: Constrain the search space by assume `pos` is between 0-2
  (when param-limit-space (assume (bvzero? (extract 4 2 pos))))

  (when (not (bveq pos (bv 0 5))) (vector-set!-bv rf pos v))
)


; FUNC: Convert the 32-entry vector (each entry is a 32-bit bitvector) to a
;       single 31x32-bit bitvector (ignore the 0-th entry). This will be used to
;       compare the architectural state of spec and impl.
(define (rf->bv rf)
  (apply concat (vector->list (vector-take-right rf 31)))
)


; FUNC: Convert the (first 4 entry of) `rf` to string for a nice printing.
(define (rf->string rf)
  (define string (~a "["))
  (for ([i (in-range 4)])
    (define i-bv (integer->bitvector i (bitvector 5)))
    (define value (rf-read rf i-bv))
    (set! string (~a string (format "0x~x" (bitvector->natural value)) ", "))
  )
  (~a (string-trim string ", ") "]")
)

