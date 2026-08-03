;; Negative: memory maximum is set.
;; CosmWasm requires exactly one memory with unset maximum (host sets it).
;; Note: float opcodes are NOT rejected by cosmwasm-check 3.0.9 static checks
;; (verified 2026-08-03); this fixture is the third hard negative instead.
(module
  (import "env" "db_read" (func $db_read (param i32) (result i32)))
  (memory (export "memory") 1 1)
  (func $allocate (export "allocate") (param i32) (result i32)
    local.get 0)
  (func $deallocate (export "deallocate") (param i32)
    nop)
  (func $interface_version_8 (export "interface_version_8")
    nop)
  (func $instantiate (export "instantiate") (param i32 i32) (result i32)
    i32.const 0)
)
