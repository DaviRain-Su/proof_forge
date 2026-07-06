(module
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "sha256" (func $sha256 (param i64 i64 i64)))
  (import "env" "input" (func $input (param i64)))
  (global $hash_ptr (mut i32) (i32.const 30000))
  (global $arr_ptr (mut i32) (i32.const 60000))
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
  (func $__pf_pow_u32 (param $base i32) (param $exp i32) (result i32) (local $r i32)
    i32.const 1
    local.set $r
    block
      loop
        local.get $exp
        i32.const 0
        i32.eq
        br_if 1
        local.get $exp
        i32.const 1
        i32.and
        i32.const 0
        i32.ne
        if
          local.get $r
          local.get $base
          i32.mul
          local.set $r
        else
        end
        local.get $base
        local.get $base
        i32.mul
        local.set $base
        local.get $exp
        i32.const 1
        i32.shr_u
        local.set $exp
        br 0
      end
    end
    local.get $r
  )
  (func $__pf_pow_u64 (param $base i64) (param $exp i64) (result i64) (local $r i64)
    i64.const 1
    local.set $r
    block
      loop
        local.get $exp
        i64.const 0
        i64.eq
        br_if 1
        local.get $exp
        i64.const 1
        i64.and
        i64.const 0
        i64.ne
        if
          local.get $r
          local.get $base
          i64.mul
          local.set $r
        else
        end
        local.get $base
        local.get $base
        i64.mul
        local.set $base
        local.get $exp
        i64.const 1
        i64.shr_u
        local.set $exp
        br 0
      end
    end
    local.get $r
  )
  (func $__pf_hash_alloc (result i32)
    global.get $hash_ptr
    global.get $hash_ptr
    i32.const 32
    i32.add
    global.set $hash_ptr
  )
  (func $__pf_hash_make (param $a i64) (param $b i64) (param $c i64) (param $d i64) (result i32) (local $p i32)
    call $__pf_hash_alloc
    local.set $p
    local.get $p
    local.get $a
    i64.store
    local.get $p
    local.get $b
    i64.store offset=8
    local.get $p
    local.get $c
    i64.store offset=16
    local.get $p
    local.get $d
    i64.store offset=24
    local.get $p
  )
  (func $__pf_hash (param $preimage i32) (result i32) (local $p i32)
    i64.const 32
    local.get $preimage
    i64.extend_i32_u
    i64.const 0
    call $sha256
    call $__pf_hash_alloc
    local.set $p
    i64.const 0
    local.get $p
    i64.extend_i32_u
    call $read_register
    local.get $p
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
  (func $__pf_hash_two_to_one (param $l i32) (param $r i32) (result i32) (local $p i32)
    i32.const 40000
    local.get $l
    i32.const 32
    call $__pf_memcpy
    i32.const 40032
    local.get $r
    i32.const 32
    call $__pf_memcpy
    i64.const 64
    i64.const 40000
    i64.const 0
    call $sha256
    call $__pf_hash_alloc
    local.set $p
    i64.const 0
    local.get $p
    i64.extend_i32_u
    call $read_register
    local.get $p
  )
  (func $__pf_hash_eq (param $a i32) (param $b i32) (result i32)
    local.get $a
    i64.load
    local.get $b
    i64.load
    i64.eq
    local.get $a
    i64.load offset=8
    local.get $b
    i64.load offset=8
    i64.eq
    i32.and
    local.get $a
    i64.load offset=16
    local.get $b
    i64.load offset=16
    i64.eq
    i32.and
    local.get $a
    i64.load offset=24
    local.get $b
    i64.load offset=24
    i64.eq
    i32.and
  )
  (func $__pf_arr_alloc (param $n i64) (result i32)
    global.get $arr_ptr
    global.get $arr_ptr
    local.get $n
    i32.wrap_i64
    i32.add
    global.set $arr_ptr
  )
  (func $__pf_arr_dealloc (param $p i32) (param $n i64))
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
  (data (i32.const 42800) "event")
)
