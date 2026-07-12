(module
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_remove" (func $storage_remove (param i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "promise_create" (func $promise_create (param i64 i64 i64 i64 i64 i64 i64 i64) (result i64)))
  (import "env" "promise_return" (func $promise_return (param i64)))
  (import "env" "input" (func $input (param i64)))
  (global $crosscall_ptr (mut i32) (i32.const 47000))
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
  (func $__pf_memcpy (param $dst i32) (param $src i32) (param $n i32) (local $i i32)
    i32.const 0
    local.set $i
    block
      loop
        local.get $i
        local.get $n
        i32.ge_u
        br_if 1
        local.get $i
        local.get $dst
        i32.add
        local.get $i
        local.get $src
        i32.add
        i32.load8_u
        i32.store8
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br 0
      end
    end
  )
  (func $__pf_fmt_u64 (param $v i64) (result i32) (local $tmp i64) (local $p i32) (local $d i32)
    local.get $v
    local.set $tmp
    i32.const 8212
    local.set $p
    local.get $tmp
    i64.eqz
    if
      i32.const 8211
      i32.const 48
      i32.store8
      i32.const 8211
      local.set $p
    else
      block
        loop
          local.get $tmp
          i64.eqz
          br_if 1
          local.get $tmp
          i64.const 10
          i64.rem_u
          i32.wrap_i64
          local.set $d
          local.get $tmp
          i64.const 10
          i64.div_u
          local.set $tmp
          local.get $p
          i32.const 1
          i32.sub
          local.tee $p
          i32.const 48
          local.get $d
          i32.add
          i32.store8
          br 0
        end
      end
    end
    local.get $p
  )
  (func $__pf_crosscall_args_start
    i32.const 47000
    global.set $crosscall_ptr
  )
  (func $__pf_crosscall_args_putc (param $c i32)
    global.get $crosscall_ptr
    local.get $c
    i32.store8
    global.get $crosscall_ptr
    i32.const 1
    i32.add
    global.set $crosscall_ptr
  )
  (func $__pf_crosscall_args_putstr (param $ptr i32) (param $len i32)
    global.get $crosscall_ptr
    local.get $ptr
    local.get $len
    call $__pf_memcpy
    global.get $crosscall_ptr
    local.get $len
    i32.add
    global.set $crosscall_ptr
  )
  (func $__pf_crosscall_args_putu64 (param $v i64) (local $p i32) (local $len i32)
    local.get $v
    call $__pf_fmt_u64
    local.set $p
    i32.const 8212
    local.get $p
    i32.sub
    local.set $len
    global.get $crosscall_ptr
    local.get $p
    local.get $len
    call $__pf_memcpy
    global.get $crosscall_ptr
    local.get $len
    i32.add
    global.set $crosscall_ptr
  )
  (func $__pf_crosscall_args_putbool (param $b i32)
    local.get $b
    i32.eqz
    if
      i32.const 12006
      i32.const 5
      call $__pf_crosscall_args_putstr
    else
      i32.const 12000
      i32.const 4
      call $__pf_crosscall_args_putstr
    end
  )
  (func $__pf_crosscall_pool_ptr (param $idx i64) (result i64) (local $result i64)
    i64.const 0
    local.set $result
    local.get $idx
    i64.const 0
    i64.eq
    if
      i64.const 49000
      local.set $result
    else
    end
    local.get $idx
    i64.const 1
    i64.eq
    if
      i64.const 49020
      local.set $result
    else
    end
    local.get $result
  )
  (func $__pf_crosscall_pool_len (param $idx i64) (result i64) (local $result i64)
    i64.const 0
    local.set $result
    local.get $idx
    i64.const 0
    i64.eq
    if
      i64.const 19
      local.set $result
    else
    end
    local.get $idx
    i64.const 1
    i64.eq
    if
      i64.const 11
      local.set $result
    else
    end
    local.get $result
  )
  (func $__pf_u128_add (param $alo i64) (param $ahi i64) (param $blo i64) (param $bhi i64) (result i64 i64) (local $lo i64) (local $hi i64) (local $carry i64)
    local.get $alo
    local.get $blo
    i64.add
    local.set $lo
    local.get $lo
    local.get $alo
    i64.lt_u
    i64.extend_i32_u
    i64.const 1
    i64.and
    local.set $carry
    local.get $ahi
    local.get $bhi
    i64.add
    local.get $carry
    i64.add
    local.set $hi
    local.get $lo
    local.get $hi
  )
  (func $__pf_u128_sub (param $alo i64) (param $ahi i64) (param $blo i64) (param $bhi i64) (result i64 i64) (local $lo i64) (local $hi i64) (local $borrow i64)
    local.get $alo
    local.get $blo
    i64.sub
    local.set $lo
    local.get $alo
    local.get $blo
    i64.lt_u
    i64.extend_i32_u
    i64.const 1
    i64.and
    local.set $borrow
    local.get $ahi
    local.get $bhi
    i64.sub
    local.get $borrow
    i64.sub
    local.set $hi
    local.get $lo
    local.get $hi
  )
  (func $__pf_u128_mul (param $alo i64) (param $ahi i64) (param $blo i64) (param $bhi i64) (result i64 i64) (local $lo i64) (local $hi i64)
    local.get $alo
    local.get $blo
    i64.mul
    local.set $lo
    local.get $alo
    local.get $bhi
    i64.mul
    local.get $ahi
    local.get $blo
    i64.mul
    i64.add
    local.set $hi
    local.get $lo
    local.get $hi
  )
  (func $__pf_u128_eq (param $alo i64) (param $ahi i64) (param $blo i64) (param $bhi i64) (result i32) (local $hi_eq i32) (local $lo_eq i32)
    local.get $ahi
    local.get $bhi
    i64.eq
    local.set $hi_eq
    local.get $alo
    local.get $blo
    i64.eq
    local.set $lo_eq
    local.get $hi_eq
    local.get $lo_eq
    i32.and
  )
  (func $initialize (export "initialize")
    i32.const 0
    i32.const 6
    i64.const 0
    call $__pf_write_u64
  )
  (func $call_remote (export "call_remote")
    i64.const 19
    i32.const 49000
    i64.extend_i32_u
    i64.const 11
    i32.const 49020
    i64.extend_i32_u
    i64.const 0
    i32.const 48100
    i64.extend_i32_u
    i64.const 50000
    i64.const 50000000000000
    call $promise_create
    call $promise_return
  )
  (func $call_with_args (export "call_with_args")
    call $__pf_crosscall_args_start
    i32.const 91
    call $__pf_crosscall_args_putc
    i64.const 42
    call $__pf_crosscall_args_putu64
    i32.const 44
    call $__pf_crosscall_args_putc
    i64.const 7
    call $__pf_crosscall_args_putu64
    i32.const 93
    call $__pf_crosscall_args_putc
    i64.const 19
    i32.const 49000
    i64.extend_i32_u
    i64.const 11
    i32.const 49020
    i64.extend_i32_u
    global.get $crosscall_ptr
    i32.const 47000
    i32.sub
    i64.extend_i32_u
    i32.const 47000
    i64.extend_i32_u
    i64.const 50000
    i64.const 50000000000000
    call $promise_create
    call $promise_return
  )
  (memory (export "memory") 1)
  (data (i32.const 0) "marker")
  (data (i32.const 12000) "true")
  (data (i32.const 12006) "false")
  (data (i32.const 12012) "0123456789abcdef")
  (data (i32.const 49000) "callee.example.near")
  (data (i32.const 49020) "remote_call")
  (data (i32.const 48100) "[]")
)
