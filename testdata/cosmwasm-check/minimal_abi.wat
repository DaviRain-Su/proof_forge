;; Minimal CosmWasm-shaped Wasm fixture (positive).
;; Required: single unbounded memory, allocate/deallocate, interface_version_8.
;; Optional entry points + env.db_* imports exercise the static import allowlist.
(module
  (type $t_i32_i32 (func (param i32) (result i32)))
  (import "env" "db_read" (func $db_read (type $t_i32_i32)))
  (import "env" "db_write" (func $db_write (param i32 i32) (result i32)))
  (import "env" "db_remove" (func $db_remove (type $t_i32_i32)))
  (memory (export "memory") 1)
  (func $allocate (export "allocate") (param i32) (result i32)
    local.get 0)
  (func $deallocate (export "deallocate") (param i32)
    nop)
  (func $interface_version_8 (export "interface_version_8")
    nop)
  (func $instantiate (export "instantiate") (param i32 i32) (result i32)
    i32.const 0)
  (func $execute (export "execute") (param i32 i32) (result i32)
    i32.const 0)
  (func $query (export "query") (param i32 i32) (result i32)
    i32.const 0)
)
