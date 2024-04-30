#lang rosette

(require rosette/solver/smt/z3 rosette/solver/smt/boolector)
(provide (all-defined-out))

; STEP1: We use boolector as the solver back-end.
;        We found it is faster than z3 in our use case.
(current-solver (boolector)) ; choose between: z3, boolector


; STEP2: Number of cycle to simulate.
; [Exercise 2-1/3-3]: Increase the number of cycle being simulated until you can
;                     find the bug.
(define param-simuCycle 5)


; STEP3: Initialize the instruction memory to either concrete value (for debug)
;        or symbolic value (for verification).
(define param-imem-type "sym") ; choose between: concrete, sym


; STEP4: Whether we want to limite the size of imem, dmem, and rf.
; NOTE: It can be hard to investigate a counterexample that might use the whole
;       memory space.
;       Thus, as a first verification attempt, we can limit the address space of
;       imem and dmem to be [0x0, 0x1f] (which can save 8 instructions) and
;       limit the number of register in rf to be [0, 3].
;       After you can find a bug when `param-limit-space` is true, turn it to
;       false and you should be able to find the same bug.
(define param-limit-space #f)

