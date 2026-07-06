(module
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "input" (func $input (param i64)))
  (func $__pf_read_u64 (param $kp i32) (param $kl i32) (result i64) (local $found i64) (local $r i64)
    i64.const 0
    local.set $r
    local.get $kl
    i64.extend_i32_u
    local.get $kp
    i64.extend_i32_u
    i64.const 0
    call $storage_read
    local.set $found
    local.get $found
    i64.const 0
    i64.ne
    if
      i64.const 0
      i64.const 4096
      call $read_register
      i32.const 4096
      i64.load
      local.set $r
    else
    end
    local.get $r
  )
  (func $__pf_write_u64 (param $kp i32) (param $kl i32) (param $v i64)
    i32.const 4096
    local.get $v
    i64.store
    local.get $kl
    i64.extend_i32_u
    local.get $kp
    i64.extend_i32_u
    i64.const 8
    i64.const 4096
    i64.const 0
    call $storage_write
    drop
  )
  (func $__pf_return_u64 (param $v i64)
    i32.const 8192
    local.get $v
    i64.store
    i64.const 8
    i64.const 8192
    call $value_return
  )
  (func $initialize (export "initialize")
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 0
    i32.const 5
    i64.const 0
    call $__pf_write_u64
  )
  (func $increment (export "increment") (local $n i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 0
    i32.const 5
    call $__pf_read_u64
    local.set $n
    i32.const 0
    i32.const 5
    local.get $n
    i64.const 1
    i64.add
    call $__pf_write_u64
  )
  (func $get (export "get")
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 0
    i32.const 5
    call $__pf_read_u64
    call $__pf_return_u64
  )
  (memory (export "memory") 1)
  (data (i32.const 0) "count")
  (data (i32.const 12000) "true")
  (data (i32.const 12006) "false")
  (data (i32.const 12012) "0123456789abcdef")
)
