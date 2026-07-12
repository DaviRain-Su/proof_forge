(module
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_remove" (func $storage_remove (param i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "promise_create" (func $promise_create (param i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
  (import "env" "promise_return" (func $promise_return (param i64)))
  (import "env" "input" (func $input (param i64)))
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
  (func $initialize (export "initialize") (local $pc i32) (local $v0 i64)
    i32.const 0
    local.set $pc
    loop
      local.get $pc
      i32.const 0
      i32.eq
      if
        i64.const 0
        local.set $v0
        i32.const 0
        i32.const 6
        local.get $v0
        call $__pf_write_u64
        return
      else
      end
      br 0
    end
  )
  (func $call_remote (export "call_remote") (local $pc i32) (local $v1 i64) (local $v2 i64) (local $v3 i64)
    i32.const 1
    local.set $pc
    loop
      local.get $pc
      i32.const 1
      i32.eq
      if
        i64.const 0
        local.set $v1
        i64.const 0
        local.set $v2
        i32.const 47000
        i32.const 91
        i32.store8
        i32.const 47001
        i32.const 93
        i32.store8
        i32.const 8192
        i64.const 0
        i64.store
        i32.const 8200
        i64.const 0
        i64.store
        i64.const 19
        i64.const 49000
        i64.const 11
        i64.const 49019
        i64.const 2
        i64.const 47000
        i64.const 8192
        i64.const 50000000000000
        call $promise_create
        local.set $v3
        local.get $v3
        call $promise_return
        return
      else
      end
      br 0
    end
  )
  (func $call_with_args (export "call_with_args") (local $pc i32) (local $v4 i64) (local $v5 i64) (local $v6 i64) (local $v7 i64) (local $v8 i64)
    i32.const 2
    local.set $pc
    loop
      local.get $pc
      i32.const 2
      i32.eq
      if
        i64.const 0
        local.set $v4
        i64.const 0
        local.set $v5
        i64.const 42
        local.set $v6
        i64.const 7
        local.set $v7
        i32.const 47000
        i32.const 91
        i32.store8
        i32.const 47001
        i32.const 52
        i32.store8
        i32.const 47002
        i32.const 50
        i32.store8
        i32.const 47003
        i32.const 44
        i32.store8
        i32.const 47004
        i32.const 55
        i32.store8
        i32.const 47005
        i32.const 93
        i32.store8
        i32.const 8192
        i64.const 0
        i64.store
        i32.const 8200
        i64.const 0
        i64.store
        i64.const 19
        i64.const 49000
        i64.const 11
        i64.const 49019
        i64.const 6
        i64.const 47000
        i64.const 8192
        i64.const 50000000000000
        call $promise_create
        local.set $v8
        local.get $v8
        call $promise_return
        return
      else
      end
      br 0
    end
  )
  (memory (export "memory") 1)
  (data (i32.const 0) "marker")
  (data (i32.const 12000) "true")
  (data (i32.const 12006) "false")
  (data (i32.const 12012) "0123456789abcdef")
  (data (i32.const 49000) "callee.example.near")
  (data (i32.const 49019) "remote_call")
)
