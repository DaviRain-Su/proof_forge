;; Negative: missing interface_version_* marker export.
(module
  (type $t_i32_i32 (func (param i32) (result i32)))
  (import "env" "db_read" (func $db_read (type $t_i32_i32)))
  (memory (export "memory") 1)
  (func $allocate (export "allocate") (param i32) (result i32)
    local.get 0)
  (func $deallocate (export "deallocate") (param i32)
    nop)
  (func $instantiate (export "instantiate") (param i32 i32) (result i32)
    i32.const 0)
)
