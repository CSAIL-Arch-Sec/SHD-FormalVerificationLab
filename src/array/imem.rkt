#lang rosette

(require "../param/inst.rkt" "../param/veri.rkt")

(provide
  init-debug-imem init-sym-imem imem-read imem->string
)


; FUNC: Initilize a "data structure" storing some concrete instructions for
;       debugging. The "data structure" here is actually a function.
(define (init-debug-imem)
  ; NOTE: `lambda` keyword here defines a function without giving it a name,
  ;       which is very common in functional programming.
  ;       `x` is the argument of the function and the rest is the function body.
  (lambda (x) (cond
    [(bveq x (bv 0 30)) (concat (bv #xAAAA 20) (bv 1 5) op-lui)]
    [(bveq x (bv 1 30)) (concat (bv #xAAAA 20) (bv 2 5) op-lui)]
    [(bveq x (bv 2 30)) (concat (bv #xBBBB 20) (bv 2 5) op-lui)]

    ; [Exercise 1-3]: Test your new ADDI, SRLI, ADD, BEQ instructions.


    ; [Exercise 3-1]: Test the behavior of exception by adding an illegal
    ;                 instruction here.

    [else (concat (bv 0 20) (bv 0 5) op-lui)]
  ))
)


; FUNC: Initilize a symbolic instruction memory.
(define (init-sym-imem)
  ; NOTE: `define-symbolic*` keyword defines a symbolic function named
  ;       `sym-imem` which takes an argument with type `(bitvector 30)` and
  ;       returns a value with type `(bitvector 32)`.
  (define-symbolic* sym-imem (~> (bitvector 30) (bitvector 32)))
  sym-imem
)


; FUNC: Return the value stored at `addr` in `imem`.
(define (imem-read imem addr)
  
  ; NOTE: Constrain the search space by assume `addr` is between 0x0-0x1f.
  (when param-limit-space (assume (bvzero? (extract 31 5 addr))))
  
  (define addr-aligned (extract 31 2 addr))
  (imem addr-aligned)
)


; FUNC: Convert the (first 8 entry of) `imem` data structure to string for a
;       nice printing.
(define (imem->string imem)
  (define string (~a ""))
  (for ([i (in-range 8)])
    (define addr-bv (integer->bitvector i (bitvector 30)))
    (define inst (imem addr-bv))
    (set! string (~a string (format "0x~x: " (* i 4)) (inst->string inst) "\n"))
  )
  string
)

