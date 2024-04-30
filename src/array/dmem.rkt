#lang rosette

(require "../param/inst.rkt" "../param/veri.rkt")

(provide
  init-zero-dmem init-sym-dmem dmem-read dmem-write dmem->string
)


; FUNC: Initilize a "data structure" storing some concrete data values for
;       debugging. The "data structure" here is actually a function.
(define (init-zero-dmem)
  (lambda (x) (bv 0 32))
)


; FUNC: Initilize a symbolic data memory.
(define (init-sym-dmem)
  (define-symbolic* sym-dmem (~> (bitvector 30) (bitvector 32)))
  sym-dmem
)


; FUNC: Return the value stored at `addr` in `dmem`.
(define (dmem-read dmem addr)
  
  ; NOTE: Constrain the search space by assume `addr` is between 0x0-0x1f
  (when param-limit-space (assume (bvzero? (extract 31 5 addr))))
  
  (define addr-aligned (extract 31 2 addr))
  (dmem addr-aligned)
)


; FUNC: Write the value `data` to `addr` in `dmem`. The enable bits `en`
;       determine which byte will be stored.
; NOTE: It can be un-intuitive for people new to functional programming that,
;       for a function than should update the value of some data structure,
;       such as the `dmem-write` should write to a memory entry, instead of
;       updating the value in that memory array, we return a new memory
;       structure with the updated value. This means, the caller of `dmem-write`
;       should not use the input arguement `dmem` anymore, but should start to
;       use the return value of `dmem-write`.
(define (dmem-write dmem addr en data)
  
  ; NOTE: Constrain the search space by assume `addr` is between 0x0-0x1f
  (when param-limit-space (assume (bvzero? (extract 31 5 addr))))

  (define addr-aligned (extract 31 2 addr))
  (define data-old (dmem addr-aligned))
  (define data-new (concat
    (if (bveq (bv 1 1) (extract 3 3 en)) (extract 31 24 data)
                                         (extract 31 24 data-old))
    (if (bveq (bv 1 1) (extract 2 2 en)) (extract 23 16 data)
                                         (extract 23 16 data-old))
    (if (bveq (bv 1 1) (extract 1 1 en)) (extract 15 8 data)
                                         (extract 15 8 data-old))
    (if (bveq (bv 1 1) (extract 0 0 en)) (extract 7 0 data)
                                         (extract 7 0 data-old))
  ))

  ; NOTE: Again, be careful that this function returns a new function. You
  ;       should use this return value to update the old function that was used
  ;       to represent dmem.
  (lambda (x) (if (bveq x addr-aligned) data-new (dmem x)))
)


; FUNC: Convert the (first 8 entry of) `dmem` data structure to string for a
;       nice printing.
(define (dmem->string dmem)
  (define string (~a "["))
  (for ([i (in-range 8)])
    (define addr-bv (integer->bitvector i (bitvector 30)))
    (define value (dmem addr-bv))
    (set! string (~a string (format "0x~x" (bitvector->natural value)) ", "))
  )
  (~a (string-trim string ", ") "]")
)

