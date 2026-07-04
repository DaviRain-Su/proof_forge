(module
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "signer_account_id" (func $signer_account_id (param i64)))
  (import "env" "attached_deposit" (func $attached_deposit (result i64)))
  (import "env" "sha256" (func $sha256 (param i64 i64 i64)))
  (import "env" "log_utf8" (func $log_utf8 (param i64 i64)))
  (import "env" "input" (func $input (param i64)))
  (import "env" "predecessor_account_id" (func $predecessor_account_id (param i64)))
  (import "env" "current_account_id" (func $current_account_id (param i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (import "env" "block_index" (func $block_index (result i64)))
  (global $hash_ptr (mut i32) (i32.const 30000))
  (global $evt_ptr (mut i32) (i32.const 42000))
  (global $arr_ptr (mut i32) (i32.const 60000))
  (func $__pf_read_u32 (param $kp i32) (param $kl i32) (result i32) (local $found i64) (local $r i32)
    i32.const 0
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
      i32.load
      local.set $r
    else
    end
    local.get $r
  )
  (func $__pf_write_u32 (param $kp i32) (param $kl i32) (param $v i32)
    i32.const 4096
    local.get $v
    i32.store
    local.get $kl
    i64.extend_i32_u
    local.get $kp
    i64.extend_i32_u
    i64.const 4
    i64.const 4096
    i64.const 0
    call $storage_write
    drop
  )
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
  (func $__pf_read_bool (param $kp i32) (param $kl i32) (result i32) (local $found i64) (local $r i32)
    i32.const 0
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
      i32.load8_u
      local.set $r
    else
    end
    local.get $r
  )
  (func $__pf_write_bool (param $kp i32) (param $kl i32) (param $v i32)
    i32.const 4096
    local.get $v
    i32.store8
    local.get $kl
    i64.extend_i32_u
    local.get $kp
    i64.extend_i32_u
    i64.const 1
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
  (func $__pf_return_u32 (param $v i32)
    i32.const 8192
    local.get $v
    i32.store
    i64.const 4
    i64.const 8192
    call $value_return
  )
  (func $__pf_return_bool (param $v i32)
    i32.const 8192
    local.get $v
    i32.store8
    i64.const 1
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
  (func $__pf_read_hash (param $kp i32) (param $kl i32) (result i32) (local $found i64) (local $p i32)
    call $__pf_hash_alloc
    local.set $p
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
      local.get $p
      i64.extend_i32_u
      call $read_register
    else
    end
    local.get $p
  )
  (func $__pf_write_hash (param $kp i32) (param $kl i32) (param $v i32)
    local.get $kl
    i64.extend_i32_u
    local.get $kp
    i64.extend_i32_u
    i64.const 32
    local.get $v
    i64.extend_i32_u
    i64.const 0
    call $storage_write
    drop
  )
  (func $__pf_ctx_user_id (result i64) (local $len i64)
    i64.const 0
    call $predecessor_account_id
    i64.const 0
    call $register_len
    local.set $len
    i64.const 0
    i64.const 41000
    call $read_register
    local.get $len
    i64.const 41000
    i64.const 1
    call $sha256
    i64.const 1
    i64.const 41000
    call $read_register
    i32.const 41000
    i64.load
  )
  (func $__pf_ctx_contract_id (result i64) (local $len i64)
    i64.const 0
    call $current_account_id
    i64.const 0
    call $register_len
    local.set $len
    i64.const 0
    i64.const 41000
    call $read_register
    local.get $len
    i64.const 41000
    i64.const 1
    call $sha256
    i64.const 1
    i64.const 41000
    call $read_register
    i32.const 41000
    i64.load
  )
  (func $__pf_ctx_signer_id (result i64) (local $len i64)
    i64.const 0
    call $signer_account_id
    i64.const 0
    call $register_len
    local.set $len
    i64.const 0
    i64.const 41000
    call $read_register
    local.get $len
    i64.const 41000
    i64.const 1
    call $sha256
    i64.const 1
    i64.const 41000
    call $read_register
    i32.const 41000
    i64.load
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
  (func $__pf_evt_start
    i32.const 42000
    global.set $evt_ptr
  )
  (func $__pf_evt_putc (param $c i32)
    global.get $evt_ptr
    local.get $c
    i32.store8
    global.get $evt_ptr
    i32.const 1
    i32.add
    global.set $evt_ptr
  )
  (func $__pf_evt_putstr (param $ptr i32) (param $len i32)
    global.get $evt_ptr
    local.get $ptr
    local.get $len
    call $__pf_memcpy
    global.get $evt_ptr
    local.get $len
    i32.add
    global.set $evt_ptr
  )
  (func $__pf_evt_putu64 (param $v i64) (local $p i32) (local $len i32)
    local.get $v
    call $__pf_fmt_u64
    local.set $p
    i32.const 8212
    local.get $p
    i32.sub
    local.set $len
    global.get $evt_ptr
    local.get $p
    local.get $len
    call $__pf_memcpy
    global.get $evt_ptr
    local.get $len
    i32.add
    global.set $evt_ptr
  )
  (func $__pf_evt_putbool (param $b i32)
    local.get $b
    i32.eqz
    if
      i32.const 12006
      i32.const 5
      call $__pf_evt_putstr
    else
      i32.const 12000
      i32.const 4
      call $__pf_evt_putstr
    end
  )
  (func $__pf_evt_log
    global.get $evt_ptr
    i32.const 42000
    i32.sub
    i64.extend_i32_u
    i64.const 42000
    call $log_utf8
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
  (func $initialize (export "initialize") (local $initial i64) (local $checkpoint i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $initial
    call $block_index
    local.set $checkpoint
    i32.const 0
    i32.const 7
    local.get $initial
    call $__pf_write_u64
    i32.const 8
    i32.const 8
    i64.const 0
    call $__pf_write_u64
    i32.const 17
    i32.const 4
    i64.const 0
    call $__pf_write_u64
    i32.const 22
    i32.const 10
    local.get $initial
    call $__pf_write_u64
    i32.const 33
    i32.const 15
    local.get $checkpoint
    call $__pf_write_u64
    i32.const 49
    i32.const 10
    i64.const 1
    call $__pf_write_u64
    call $__pf_evt_start
    i32.const 123
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 42800
    i32.const 5
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43000
    i32.const 16
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43017
    i32.const 7
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $initial
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43025
    i32.const 10
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $checkpoint
    call $__pf_evt_putu64
    i32.const 125
    call $__pf_evt_putc
    call $__pf_evt_log
  )
  (func $deposit (export "deposit") (local $amount i64) (local $current i64) (local $next i64) (local $ops i64) (local $next_ops i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $amount
    i32.const 0
    i32.const 7
    call $__pf_read_u64
    local.set $current
    local.get $current
    local.get $amount
    i64.add
    local.set $next
    i32.const 49
    i32.const 10
    call $__pf_read_u64
    local.set $ops
    local.get $ops
    i64.const 1
    i64.add
    local.set $next_ops
    i32.const 0
    i32.const 7
    local.get $next
    call $__pf_write_u64
    i32.const 22
    i32.const 10
    local.get $amount
    call $__pf_write_u64
    i32.const 49
    i32.const 10
    local.get $next_ops
    call $__pf_write_u64
    call $__pf_evt_start
    i32.const 123
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 42800
    i32.const 5
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43036
    i32.const 14
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43051
    i32.const 6
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $amount
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43058
    i32.const 7
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $next
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43066
    i32.const 10
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $next_ops
    call $__pf_evt_putu64
    i32.const 125
    call $__pf_evt_putc
    call $__pf_evt_log
  )
  (func $charge_fee (export "charge_fee") (local $gross i64) (local $fee_bps i64) (local $fee i64) (local $net i64) (local $current i64) (local $next i64) (local $current_fees i64) (local $next_fees i64) (local $ops i64) (local $next_ops i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $gross
    i32.const 44008
    i64.load
    local.set $fee_bps
    local.get $gross
    local.get $fee_bps
    i64.mul
    i64.const 10000
    i64.div_u
    local.set $fee
    local.get $gross
    local.get $fee
    i64.sub
    local.set $net
    i32.const 0
    i32.const 7
    call $__pf_read_u64
    local.set $current
    local.get $current
    local.get $net
    i64.add
    local.set $next
    i32.const 17
    i32.const 4
    call $__pf_read_u64
    local.set $current_fees
    local.get $current_fees
    local.get $fee
    i64.add
    local.set $next_fees
    i32.const 49
    i32.const 10
    call $__pf_read_u64
    local.set $ops
    local.get $ops
    i64.const 1
    i64.add
    local.set $next_ops
    i32.const 0
    i32.const 7
    local.get $next
    call $__pf_write_u64
    i32.const 17
    i32.const 4
    local.get $next_fees
    call $__pf_write_u64
    i32.const 22
    i32.const 10
    local.get $net
    call $__pf_write_u64
    i32.const 49
    i32.const 10
    local.get $next_ops
    call $__pf_write_u64
    call $__pf_evt_start
    i32.const 123
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 42800
    i32.const 5
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43077
    i32.const 12
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43090
    i32.const 5
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $gross
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43096
    i32.const 3
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $fee
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43100
    i32.const 3
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $net
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43058
    i32.const 7
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $next
    call $__pf_evt_putu64
    i32.const 125
    call $__pf_evt_putc
    call $__pf_evt_log
  )
  (func $release (export "release") (local $amount i64) (local $current i64) (local $next i64) (local $released_before i64) (local $released_next i64) (local $ops i64) (local $next_ops i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $amount
    i32.const 0
    i32.const 7
    call $__pf_read_u64
    local.set $current
    local.get $current
    local.get $amount
    i64.sub
    local.set $next
    i32.const 8
    i32.const 8
    call $__pf_read_u64
    local.set $released_before
    local.get $released_before
    local.get $amount
    i64.add
    local.set $released_next
    i32.const 49
    i32.const 10
    call $__pf_read_u64
    local.set $ops
    local.get $ops
    i64.const 1
    i64.add
    local.set $next_ops
    i32.const 0
    i32.const 7
    local.get $next
    call $__pf_write_u64
    i32.const 8
    i32.const 8
    local.get $released_next
    call $__pf_write_u64
    i32.const 22
    i32.const 10
    local.get $amount
    call $__pf_write_u64
    i32.const 49
    i32.const 10
    local.get $next_ops
    call $__pf_write_u64
    call $__pf_evt_start
    i32.const 123
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 42800
    i32.const 5
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43104
    i32.const 13
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43051
    i32.const 6
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $amount
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43058
    i32.const 7
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $next
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43118
    i32.const 8
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $released_next
    call $__pf_evt_putu64
    i32.const 125
    call $__pf_evt_putc
    call $__pf_evt_log
  )
  (func $snapshot (export "snapshot") (local $checkpoint i64) (local $balance_now i64) (local $released_now i64) (local $fees_now i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    call $block_index
    local.set $checkpoint
    i32.const 0
    i32.const 7
    call $__pf_read_u64
    local.set $balance_now
    i32.const 8
    i32.const 8
    call $__pf_read_u64
    local.set $released_now
    i32.const 17
    i32.const 4
    call $__pf_read_u64
    local.set $fees_now
    i32.const 33
    i32.const 15
    local.get $checkpoint
    call $__pf_write_u64
    call $__pf_evt_start
    i32.const 123
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 42800
    i32.const 5
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43127
    i32.const 13
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43058
    i32.const 7
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $balance_now
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43118
    i32.const 8
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $released_now
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43141
    i32.const 4
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $fees_now
    call $__pf_evt_putu64
    i32.const 44
    call $__pf_evt_putc
    i32.const 34
    call $__pf_evt_putc
    i32.const 43025
    i32.const 10
    call $__pf_evt_putstr
    i32.const 34
    call $__pf_evt_putc
    i32.const 58
    call $__pf_evt_putc
    local.get $checkpoint
    call $__pf_evt_putu64
    i32.const 125
    call $__pf_evt_putc
    call $__pf_evt_log
    local.get $balance_now
    call $__pf_return_u64
  )
  (func $get_balance (export "get_balance")
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 0
    i32.const 7
    call $__pf_read_u64
    call $__pf_return_u64
  )
  (func $get_net_value (export "get_net_value") (local $balance_now i64) (local $fees_now i64)
    i64.const 0
    call $input
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 0
    i32.const 7
    call $__pf_read_u64
    local.set $balance_now
    i32.const 17
    i32.const 4
    call $__pf_read_u64
    local.set $fees_now
    local.get $balance_now
    local.get $fees_now
    i64.sub
    call $__pf_return_u64
  )
  (memory (export "memory") 1)
  (data (i32.const 0) "balance")
  (data (i32.const 8) "released")
  (data (i32.const 17) "fees")
  (data (i32.const 22) "last_value")
  (data (i32.const 33) "last_checkpoint")
  (data (i32.const 49) "operations")
  (data (i32.const 12000) "true")
  (data (i32.const 12006) "false")
  (data (i32.const 42800) "event")
  (data (i32.const 43000) "VaultInitialized")
  (data (i32.const 43017) "initial")
  (data (i32.const 43025) "checkpoint")
  (data (i32.const 43036) "ValueDeposited")
  (data (i32.const 43051) "amount")
  (data (i32.const 43058) "balance")
  (data (i32.const 43066) "operations")
  (data (i32.const 43077) "ValueCharged")
  (data (i32.const 43090) "gross")
  (data (i32.const 43096) "fee")
  (data (i32.const 43100) "net")
  (data (i32.const 43104) "ValueReleased")
  (data (i32.const 43118) "released")
  (data (i32.const 43127) "ValueSnapshot")
  (data (i32.const 43141) "fees")
)
