(module
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_remove" (func $storage_remove (param i64 i64) (result i64)))
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
        i32.const 5
        local.get $v0
        call $__pf_write_u64
        return
      else
      end
      br 0
    end
  )
  (func $increment (export "increment") (local $pc i32) (local $v1 i64) (local $v2 i64) (local $v3 i64)
    i32.const 1
    local.set $pc
    loop
      local.get $pc
      i32.const 1
      i32.eq
      if
        i32.const 0
        i32.const 5
        call $__pf_read_u64
        local.set $v1
        i64.const 1
        local.set $v2
        local.get $v1
        local.get $v2
        i64.add
        local.set $v3
        local.get $v3
        local.get $v1
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 0
        i32.const 5
        local.get $v3
        call $__pf_write_u64
        return
      else
      end
      br 0
    end
  )
  (func $get (export "get") (local $pc i32) (local $v4 i64)
    i32.const 2
    local.set $pc
    loop
      local.get $pc
      i32.const 2
      i32.eq
      if
        i32.const 0
        i32.const 5
        call $__pf_read_u64
        local.set $v4
        local.get $v4
        call $__pf_return_u64
        return
      else
      end
      br 0
    end
  )
  (memory (export "memory") 1)
  (data (i32.const 0) "count")
  (data (i32.const 12000) "true")
  (data (i32.const 12006) "false")
  (data (i32.const 12012) "0123456789abcdef")
)
