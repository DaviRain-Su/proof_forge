;; Hand-written minimal NEAR counter — no Lean runtime, no WASI, no near-sdk.
;; Proves a WAT-only contract can deploy to near-sandbox and pass the counter
;; scenario (init -> get==0 -> increment -> get==1). Stores the count as a
;; single ASCII digit byte under key "count"; returns it via value_return so
;; near-api-js JSON.parse("0")=0 / JSON.parse("1")=1.
(module
  (import "env" "storage_read"  (func $storage_read  (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return"  (func $value_return  (param i64 i64)))
  (import "env" "log_utf8"      (func $log_utf8      (param i64 i64)))
  (memory (export "memory") 1)
  (data (i32.const 0) "count")          ;; storage key at offset 0 (len 5)
  ;; value byte lives at offset 32

  (func $load_digit (result i32)        ;; current ASCII digit at mem[32], default '0'
    (local $found i64)
    (local.set $found (call $storage_read (i64.const 5) (i64.const 0) (i64.const 0)))
    (if (i64.eqz (local.get $found))
      (then (i32.store8 (i32.const 32) (i32.const 48)))
      (else (call $read_register (i64.const 0) (i64.const 32))))
    (i32.load8_u (i32.const 32))
  )

  (func (export "init")
    (i32.store8 (i32.const 32) (i32.const 48))   ;; '0'
    (drop (call $storage_write (i64.const 5) (i64.const 0) (i64.const 1) (i64.const 32) (i64.const 0)))
  )

  (func (export "get")
    (local $found i64)
    (local.set $found (call $storage_read (i64.const 5) (i64.const 0) (i64.const 0)))
    (if (i64.eqz (local.get $found))
      (then (i32.store8 (i32.const 32) (i32.const 48)))
      (else (call $read_register (i64.const 0) (i64.const 32))))
    (call $value_return (i64.const 1) (i64.const 32))
  )

  (func (export "increment")
    (i32.store8 (i32.const 32)
      (i32.add (call $load_digit) (i32.const 1)))
    (drop (call $storage_write (i64.const 5) (i64.const 0) (i64.const 1) (i64.const 32) (i64.const 0)))
  )
)
