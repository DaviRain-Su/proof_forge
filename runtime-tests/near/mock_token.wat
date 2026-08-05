;; Minimal NEP-141 mock token contract for engineering runtime tests.
;; ft_transfer ASSERTS exactly 1 yoctoNEAR attached deposit (NEP-141 core
;; requirement) and succeeds as a no-op ledger-wise (logs "ft_transfer ok").
;; Also exposes ft_balance_of / ft_total_supply (return 0) for completeness.
;; NOT a real NEP-141 ledger implementation — no balance bookkeeping; it is
;; the honest minimum that lets the sandbox execute the cross-contract
;; promise so the receipt (status + deposit assertion + log) is observable.
(module
  (import "env" "input" (func $input (param i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "log_utf8" (func $log_utf8 (param i64 i64)))
  (import "env" "attached_deposit" (func $attached_deposit (param i64)))
  (memory (export "memory") 1)

  ;; Scratch: input at offset 0, output at offset 1024, deposit u128 at 2048.
  (func (export "ft_transfer")
    (local $len i64)
    (call $input (i64.const 0))
    (local.set $len (call $register_len (i64.const 0)))
    (if (i64.gt_u (local.get $len) (i64.const 0))
      (then (call $read_register (i64.const 0) (i64.const 0))))
    ;; NEP-141 core: ft_transfer requires exactly 1 yoctoNEAR attached
    ;; deposit (u128 LE at 2048: lo must be 1, hi must be 0).
    (call $attached_deposit (i64.const 2048))
    (if (i64.ne (i64.load (i32.const 2048)) (i64.const 1))
      (then unreachable))
    (if (i64.ne (i64.load (i32.const 2056)) (i64.const 0))
      (then unreachable))
    ;; Log "ft_transfer ok" for observability
    (i32.store8 (i32.const 1024) (i32.const 102)) ;; f
    (i32.store8 (i32.const 1025) (i32.const 116)) ;; t
    (i32.store8 (i32.const 1026) (i32.const 95))  ;; _
    (i32.store8 (i32.const 1027) (i32.const 116)) ;; t
    (i32.store8 (i32.const 1028) (i32.const 114)) ;; r
    (i32.store8 (i32.const 1029) (i32.const 97))  ;; a
    (i32.store8 (i32.const 1030) (i32.const 110)) ;; n
    (i32.store8 (i32.const 1031) (i32.const 115)) ;; s
    (i32.store8 (i32.const 1032) (i32.const 102)) ;; f
    (i32.store8 (i32.const 1033) (i32.const 101)) ;; e
    (i32.store8 (i32.const 1034) (i32.const 114)) ;; r
    (i32.store8 (i32.const 1035) (i32.const 32))  ;;
    (i32.store8 (i32.const 1036) (i32.const 111)) ;; o
    (i32.store8 (i32.const 1037) (i32.const 107)) ;; k
    (call $log_utf8 (i64.const 14) (i64.const 1024))
  )

  ;; ft_balance_of — returns 0 (u128 LE = 16 zero bytes)
  (func (export "ft_balance_of")
    (call $value_return (i64.const 16) (i64.const 1024))
  )

  ;; ft_total_supply — returns 0
  (func (export "ft_total_supply")
    (call $value_return (i64.const 16) (i64.const 1024))
  )

  ;; ft_metadata — returns empty JSON (minimal)
  (func (export "ft_metadata")
    (call $value_return (i64.const 0) (i64.const 1024))
  )

  ;; storage_deposit — no-op (accept storage deposit)
  (func (export "storage_deposit")
    (call $value_return (i64.const 0) (i64.const 1024))
  )
)
