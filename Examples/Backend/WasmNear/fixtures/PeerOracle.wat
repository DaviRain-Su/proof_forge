(module
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (func $remote_call (export "remote_call")
    ;; write u64 49 LE at memory 0
    i32.const 0
    i64.const 49
    i64.store
    i64.const 8
    i32.const 0
    i64.extend_i32_u
    call $value_return
  )
  (memory (export "memory") 1)
)
