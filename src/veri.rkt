#lang rosette

(require
  "impl.rkt" "spec.rkt"
  "array/imem.rkt" "array/dmem.rkt"
  "param/veri.rkt"
)


; FUNC: Simulate impl and spec, during which assumptions and assertions are
;       generated to assert that their architecture states match.
(define (simu imem dmem IS_CONCRETE)
  
  ; STEP1: Initialize the implementation and specification machines with the
  ;        provided instruction and data memory.
  (define impl (init-impl imem dmem))
  (define spec (init-spec imem dmem))
  (when IS_CONCRETE (printf (~a
    "[simu] INIT\n"
    "********* impl *********\n" (impl->string impl) "\n"
    "********* spec *********\n" (spec->string spec) "\n"
  )))


  ; STEP2: Simulate impl and spec in a "synchronized" (explained below) manner.
  (define commitID 0)
  (for ([i (in-range param-simuCycle)])
    
    ; STEP2.1: Here is what "synchronized" simulation means:
    ;          If one of impl or spec is falling behind (i.e., it did not
    ;          commit last cycle but the other committed), we stall the other
    ;          one from simulating the next cycle.
    (printf (~a "[simu] Cycle " (+ i 1) " Start... "))
    (cond
      [(and (not (impl-justCommit impl)) (not (spec-justCommit spec)))
        (step-impl! impl)
        (step-spec! spec)
      ]
      
      [(and      (impl-justCommit impl)  (not (spec-justCommit spec)))
        (step-spec! spec)
      ]
      
      [(and (not (impl-justCommit impl))      (spec-justCommit spec))
        (step-impl! impl)
      ]
      
      [(and      (impl-justCommit impl)       (spec-justCommit spec))
        (step-impl! impl)
        (step-spec! spec)
      ]
    )
    (printf (~a " ...End\n"))

    ; STEP2.2: When we simulate with concrete initial states, let's print out
    ;          the state of the impl and spec when both of them have just
    ;          committed an instruction in the last (unstalled) cycle.
    ; NOTE: What would happen if you print when IS_CONCRETE is false?
    (when IS_CONCRETE
      (when (and (impl-justCommit impl) (spec-justCommit spec))
        (set! commitID (+ commitID 1))
        (printf (~a "********* impl after " commitID "-th commit *********\n"
                    (impl->string impl) "\n"
                    "********* spec after " commitID "-th commit *********\n"
                    (spec->string spec) "\n"))
        (when (not (bveq (impl-archState impl) (spec-archState spec)))
          (printf (~a "********* Arch State Mismatch Found *********\n"))
          (exit)))
    )

    ; STEP2.3: We assert impl and spec should have same architectural state
    ;          when both have just committed an instruction in the last
    ;          (unstalled) cycle.
    (when (and (impl-justCommit impl) (spec-justCommit spec))
      (assert (bveq (impl-archState impl) (spec-archState spec))))
  )
)


; FUNC: The function does the verification.
(define (veri)
  ; STEP1: Initialize a symbolic instruction memory, or a concrete instruction
  ;        memory for debug.
  (define imem (cond
    [(equal? param-imem-type "concrete")
      (init-debug-imem)]
    [(equal? param-imem-type "sym")
      (init-sym-imem)]))
  

  ; STEP2: Initialize a data memory with all data initialized to zero.
  (define dmem (init-zero-dmem))


  ; STEP3: Simulate the impl and spec (i.e., `simu`) during which, assumptions
  ;        and assertions are collected by the `verify` function.
  ;        After the simulation, `verify` also send all assumptions and
  ;        assertions to a SMT solver, asking for solution (i.e., `sol`).
  ;        Solution is basically a counterexample satifying all the assumptions
  ;        but violating one of the assertions.
  (printf (~a
    "==================================\n"
    "==== Start Symbolic Execution ====\n"
    "==================================\n"))
  (define sol (verify (simu imem dmem #f)))
  (printf (~a "\n"))


  ; STEP4: In case we find a counterexample (we call it satisfiable), ...
  (when (sat? sol)

    ; STEP4.1: Based on the counterexample (i.e. `sol`) generated from the SMT
    ;          solver, print out the value of `imem`.
    ;          `(evaluate imem sol)` means `evaluate` a `sol` and get the
    ;          concrete value of `imem`.
    (printf (~a
      "==============================\n"
      "==== Counterexample Found ====\n"
      "==============================\n"
      (imem->string (evaluate imem sol))
      "\n"))

    ; STEP4.2: Simulate with the counterexample and print the debug trace.
    (set! imem (evaluate imem sol))
    (printf (~a
      "=============================================\n"
      "==== Start Simulating the Counterexample ====\n"
      "=============================================\n"))
    (simu imem dmem #t)
    (printf (~a "\n"))
  )


  ; STEP5: In case we do not find a counterexample, ...
  (when (not (sat? sol))
    (printf (~a
      "===========================\n"
      "==== No Counterexample ====\n"
      "===========================\n"
      "\n"))
  )
)


(define (testMe)
  (time (veri))
)
(module+ main (testMe))

