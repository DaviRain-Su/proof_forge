(module
  (import "env" "storage_read" (func $storage_read (param i64 i64 i64) (result i64)))
  (import "env" "storage_write" (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
  (import "env" "storage_remove" (func $storage_remove (param i64 i64 i64) (result i64)))
  (import "env" "read_register" (func $read_register (param i64 i64)))
  (import "env" "value_return" (func $value_return (param i64 i64)))
  (import "env" "input" (func $input (param i64)))
  (import "env" "log_utf8" (func $log_utf8 (param i64 i64)))
  (import "env" "block_index" (func $block_index (result i64)))
  (import "env" "register_len" (func $register_len (param i64) (result i64)))
  (global $evt_ptr (mut i32) (i32.const 42000))
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
  (func $__pf_evt_putu64 (param $v i64) (local $tmp i64) (local $p i32) (local $d i32) (local $len i32)
    local.get $v
    local.set $tmp
    local.get $tmp
    i64.eqz
    if
      global.get $evt_ptr
      i32.const 48
      i32.store8
      global.get $evt_ptr
      i32.const 1
      i32.add
      global.set $evt_ptr
    else
      i32.const 8212
      local.set $p
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
    end
  )
  (func $__pf_evt_putu128 (param $lo i64) (param $hi i64) (local $p i32) (local $len i32)
    local.get $lo
    local.get $hi
    call $__pf_fmt_u128
    local.set $p
    i32.const 8232
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
  (func $__pf_u128_divmod10 (param $alo i64) (param $ahi i64) (result i64) (local $rem i64) (local $cur i64) (local $ql0 i64) (local $ql1 i64) (local $ql2 i64) (local $ql3 i64)
    i64.const 0
    local.set $rem
    local.get $rem
    i64.const 32
    i64.shl
    local.get $ahi
    i64.const 32
    i64.shr_u
    i64.or
    local.tee $cur
    i64.const 10
    i64.div_u
    local.set $ql3
    local.get $cur
    i64.const 10
    i64.rem_u
    local.set $rem
    local.get $rem
    i64.const 32
    i64.shl
    local.get $ahi
    i64.const 4294967295
    i64.and
    i64.or
    local.tee $cur
    i64.const 10
    i64.div_u
    local.set $ql2
    local.get $cur
    i64.const 10
    i64.rem_u
    local.set $rem
    local.get $rem
    i64.const 32
    i64.shl
    local.get $alo
    i64.const 32
    i64.shr_u
    i64.or
    local.tee $cur
    i64.const 10
    i64.div_u
    local.set $ql1
    local.get $cur
    i64.const 10
    i64.rem_u
    local.set $rem
    local.get $rem
    i64.const 32
    i64.shl
    local.get $alo
    i64.const 4294967295
    i64.and
    i64.or
    local.tee $cur
    i64.const 10
    i64.div_u
    local.set $ql0
    local.get $cur
    i64.const 10
    i64.rem_u
    local.set $rem
    i32.const 56000
    local.get $ql0
    local.get $ql1
    i64.const 32
    i64.shl
    i64.or
    i64.store
    i32.const 56008
    local.get $ql2
    local.get $ql3
    i64.const 32
    i64.shl
    i64.or
    i64.store
    local.get $rem
  )
  (func $__pf_fmt_u128 (param $alo i64) (param $ahi i64) (result i32) (local $ql i64) (local $qh i64) (local $rem i64) (local $p i32)
    local.get $alo
    local.set $ql
    local.get $ahi
    local.set $qh
    i32.const 8232
    local.set $p
    local.get $ql
    i64.eqz
    local.get $qh
    i64.eqz
    i32.and
    if
      i32.const 8231
      i32.const 48
      i32.store8
      i32.const 8231
      local.set $p
    else
      block
        loop
          local.get $ql
          i64.eqz
          local.get $qh
          i64.eqz
          i32.and
          br_if 1
          local.get $ql
          local.get $qh
          call $__pf_u128_divmod10
          local.set $rem
          i32.const 56000
          i64.load
          local.set $ql
          i32.const 56008
          i64.load
          local.set $qh
          local.get $p
          i32.const 1
          i32.sub
          local.tee $p
          i32.const 48
          local.get $rem
          i32.wrap_i64
          i32.add
          i32.store8
          br 0
        end
      end
    end
    local.get $p
  )
  (func $__pf_evt_log
    global.get $evt_ptr
    i32.const 42000
    i32.sub
    i64.extend_i32_u
    i64.const 42000
    call $log_utf8
  )
  (func $initialize (export "initialize") (local $pc i32) (local $v0 i64) (local $v1 i64) (local $v2 i64) (local $v3 i64) (local $v4 i64)
    i64.const 0
    call $input
    i64.const 0
    call $register_len
    i64.const 8
    i64.ne
    if
      unreachable
    else
    end
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $v0
    i32.const 0
    local.set $pc
    loop
      local.get $pc
      i32.const 0
      i32.eq
      if
        call $block_index
        local.set $v1
        i32.const 0
        i32.const 7
        local.get $v0
        call $__pf_write_u64
        i64.const 0
        local.set $v2
        i32.const 8
        i32.const 8
        local.get $v2
        call $__pf_write_u64
        i64.const 0
        local.set $v3
        i32.const 17
        i32.const 4
        local.get $v3
        call $__pf_write_u64
        i32.const 22
        i32.const 10
        local.get $v0
        call $__pf_write_u64
        i32.const 33
        i32.const 15
        local.get $v1
        call $__pf_write_u64
        i64.const 1
        local.set $v4
        i32.const 49
        i32.const 10
        local.get $v4
        call $__pf_write_u64
        call $__pf_evt_start
        i32.const 43000
        i32.const 27
        call $__pf_evt_putstr
        i32.const 43027
        i32.const 11
        call $__pf_evt_putstr
        local.get $v0
        call $__pf_evt_putu64
        i32.const 43038
        i32.const 14
        call $__pf_evt_putstr
        local.get $v1
        call $__pf_evt_putu64
        i32.const 42815
        i32.const 1
        call $__pf_evt_putstr
        call $__pf_evt_log
        return
      else
      end
      br 0
    end
  )
  (func $deposit (export "deposit") (local $pc i32) (local $v5 i64) (local $v6 i64) (local $v7 i64) (local $v8 i64) (local $v9 i64) (local $v10 i64)
    i64.const 0
    call $input
    i64.const 0
    call $register_len
    i64.const 8
    i64.ne
    if
      unreachable
    else
    end
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $v5
    i32.const 1
    local.set $pc
    loop
      local.get $pc
      i32.const 1
      i32.eq
      if
        i32.const 0
        i32.const 7
        call $__pf_read_u64
        local.set $v6
        local.get $v6
        local.get $v5
        i64.add
        local.set $v7
        local.get $v7
        local.get $v6
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 49
        i32.const 10
        call $__pf_read_u64
        local.set $v8
        i64.const 1
        local.set $v9
        local.get $v8
        local.get $v9
        i64.add
        local.set $v10
        local.get $v10
        local.get $v8
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 0
        i32.const 7
        local.get $v7
        call $__pf_write_u64
        i32.const 22
        i32.const 10
        local.get $v5
        call $__pf_write_u64
        i32.const 49
        i32.const 10
        local.get $v10
        call $__pf_write_u64
        call $__pf_evt_start
        i32.const 43052
        i32.const 25
        call $__pf_evt_putstr
        i32.const 43077
        i32.const 10
        call $__pf_evt_putstr
        local.get $v5
        call $__pf_evt_putu64
        i32.const 43087
        i32.const 11
        call $__pf_evt_putstr
        local.get $v7
        call $__pf_evt_putu64
        i32.const 43098
        i32.const 14
        call $__pf_evt_putstr
        local.get $v10
        call $__pf_evt_putu64
        i32.const 42815
        i32.const 1
        call $__pf_evt_putstr
        call $__pf_evt_log
        return
      else
      end
      br 0
    end
  )
  (func $charge_fee (export "charge_fee") (local $pc i32) (local $v11 i64) (local $v12 i64) (local $v13 i64) (local $v14 i64) (local $v15 i64) (local $v16 i64) (local $v17 i64) (local $v18 i64) (local $v19 i64) (local $v20 i64) (local $v21 i64) (local $v22 i64) (local $v23 i64)
    i64.const 0
    call $input
    i64.const 0
    call $register_len
    i64.const 16
    i64.ne
    if
      unreachable
    else
    end
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $v11
    i32.const 44008
    i64.load
    local.set $v12
    i32.const 2
    local.set $pc
    loop
      local.get $pc
      i32.const 2
      i32.eq
      if
        local.get $v11
        local.get $v12
        i64.mul
        local.set $v13
        local.get $v12
        i64.eqz
        if
        else
          local.get $v13
          local.get $v12
          i64.div_u
          local.get $v11
          i64.ne
          if
            unreachable
          else
          end
        end
        i64.const 10000
        local.set $v14
        local.get $v13
        local.get $v14
        i64.div_u
        local.set $v15
        local.get $v11
        local.get $v15
        i64.lt_u
        if
          unreachable
        else
        end
        local.get $v11
        local.get $v15
        i64.sub
        local.set $v16
        i32.const 0
        i32.const 7
        call $__pf_read_u64
        local.set $v17
        local.get $v17
        local.get $v16
        i64.add
        local.set $v18
        local.get $v18
        local.get $v17
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 17
        i32.const 4
        call $__pf_read_u64
        local.set $v19
        local.get $v19
        local.get $v15
        i64.add
        local.set $v20
        local.get $v20
        local.get $v19
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 49
        i32.const 10
        call $__pf_read_u64
        local.set $v21
        i64.const 1
        local.set $v22
        local.get $v21
        local.get $v22
        i64.add
        local.set $v23
        local.get $v23
        local.get $v21
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 0
        i32.const 7
        local.get $v18
        call $__pf_write_u64
        i32.const 17
        i32.const 4
        local.get $v20
        call $__pf_write_u64
        i32.const 22
        i32.const 10
        local.get $v16
        call $__pf_write_u64
        i32.const 49
        i32.const 10
        local.get $v23
        call $__pf_write_u64
        call $__pf_evt_start
        i32.const 43112
        i32.const 23
        call $__pf_evt_putstr
        i32.const 43135
        i32.const 9
        call $__pf_evt_putstr
        local.get $v11
        call $__pf_evt_putu64
        i32.const 43144
        i32.const 7
        call $__pf_evt_putstr
        local.get $v15
        call $__pf_evt_putu64
        i32.const 43151
        i32.const 7
        call $__pf_evt_putstr
        local.get $v16
        call $__pf_evt_putu64
        i32.const 43087
        i32.const 11
        call $__pf_evt_putstr
        local.get $v18
        call $__pf_evt_putu64
        i32.const 42815
        i32.const 1
        call $__pf_evt_putstr
        call $__pf_evt_log
        return
      else
      end
      br 0
    end
  )
  (func $release (export "release") (local $pc i32) (local $v24 i64) (local $v25 i64) (local $v26 i64) (local $v27 i64) (local $v28 i64) (local $v29 i64) (local $v30 i64) (local $v31 i64)
    i64.const 0
    call $input
    i64.const 0
    call $register_len
    i64.const 8
    i64.ne
    if
      unreachable
    else
    end
    i64.const 0
    i64.const 44000
    call $read_register
    i32.const 44000
    i64.load
    local.set $v24
    i32.const 3
    local.set $pc
    loop
      local.get $pc
      i32.const 3
      i32.eq
      if
        i32.const 0
        i32.const 7
        call $__pf_read_u64
        local.set $v25
        local.get $v25
        local.get $v24
        i64.lt_u
        if
          unreachable
        else
        end
        local.get $v25
        local.get $v24
        i64.sub
        local.set $v26
        i32.const 8
        i32.const 8
        call $__pf_read_u64
        local.set $v27
        local.get $v27
        local.get $v24
        i64.add
        local.set $v28
        local.get $v28
        local.get $v27
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 49
        i32.const 10
        call $__pf_read_u64
        local.set $v29
        i64.const 1
        local.set $v30
        local.get $v29
        local.get $v30
        i64.add
        local.set $v31
        local.get $v31
        local.get $v29
        i64.lt_u
        if
          unreachable
        else
        end
        i32.const 0
        i32.const 7
        local.get $v26
        call $__pf_write_u64
        i32.const 8
        i32.const 8
        local.get $v28
        call $__pf_write_u64
        i32.const 22
        i32.const 10
        local.get $v24
        call $__pf_write_u64
        i32.const 49
        i32.const 10
        local.get $v31
        call $__pf_write_u64
        call $__pf_evt_start
        i32.const 43158
        i32.const 24
        call $__pf_evt_putstr
        i32.const 43077
        i32.const 10
        call $__pf_evt_putstr
        local.get $v24
        call $__pf_evt_putu64
        i32.const 43087
        i32.const 11
        call $__pf_evt_putstr
        local.get $v26
        call $__pf_evt_putu64
        i32.const 43182
        i32.const 12
        call $__pf_evt_putstr
        local.get $v28
        call $__pf_evt_putu64
        i32.const 42815
        i32.const 1
        call $__pf_evt_putstr
        call $__pf_evt_log
        return
      else
      end
      br 0
    end
  )
  (func $snapshot (export "snapshot") (local $pc i32) (local $v32 i64) (local $v33 i64) (local $v34 i64) (local $v35 i64)
    i32.const 4
    local.set $pc
    loop
      local.get $pc
      i32.const 4
      i32.eq
      if
        call $block_index
        local.set $v32
        i32.const 0
        i32.const 7
        call $__pf_read_u64
        local.set $v33
        i32.const 8
        i32.const 8
        call $__pf_read_u64
        local.set $v34
        i32.const 17
        i32.const 4
        call $__pf_read_u64
        local.set $v35
        i32.const 33
        i32.const 15
        local.get $v32
        call $__pf_write_u64
        call $__pf_evt_start
        i32.const 43194
        i32.const 24
        call $__pf_evt_putstr
        i32.const 43087
        i32.const 11
        call $__pf_evt_putstr
        local.get $v33
        call $__pf_evt_putu64
        i32.const 43182
        i32.const 12
        call $__pf_evt_putstr
        local.get $v34
        call $__pf_evt_putu64
        i32.const 43218
        i32.const 8
        call $__pf_evt_putstr
        local.get $v35
        call $__pf_evt_putu64
        i32.const 43038
        i32.const 14
        call $__pf_evt_putstr
        local.get $v32
        call $__pf_evt_putu64
        i32.const 42815
        i32.const 1
        call $__pf_evt_putstr
        call $__pf_evt_log
        local.get $v33
        call $__pf_return_u64
        return
      else
      end
      br 0
    end
  )
  (func $get_balance (export "get_balance") (local $pc i32) (local $v36 i64)
    i32.const 5
    local.set $pc
    loop
      local.get $pc
      i32.const 5
      i32.eq
      if
        i32.const 0
        i32.const 7
        call $__pf_read_u64
        local.set $v36
        local.get $v36
        call $__pf_return_u64
        return
      else
      end
      br 0
    end
  )
  (func $get_net_value (export "get_net_value") (local $pc i32) (local $v37 i64) (local $v38 i64) (local $v39 i64)
    i32.const 6
    local.set $pc
    loop
      local.get $pc
      i32.const 6
      i32.eq
      if
        i32.const 0
        i32.const 7
        call $__pf_read_u64
        local.set $v37
        i32.const 17
        i32.const 4
        call $__pf_read_u64
        local.set $v38
        local.get $v37
        local.get $v38
        i64.lt_u
        if
          unreachable
        else
        end
        local.get $v37
        local.get $v38
        i64.sub
        local.set $v39
        local.get $v39
        call $__pf_return_u64
        return
      else
      end
      br 0
    end
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
  (data (i32.const 12012) "0123456789abcdef")
  (data (i32.const 42800) "{\"event\":\"\",\"\":}")
  (data (i32.const 43000) "{\"event\":\"VaultInitialized\"")
  (data (i32.const 43027) ",\"initial\":")
  (data (i32.const 43038) ",\"checkpoint\":")
  (data (i32.const 43052) "{\"event\":\"ValueDeposited\"")
  (data (i32.const 43077) ",\"amount\":")
  (data (i32.const 43087) ",\"balance\":")
  (data (i32.const 43098) ",\"operations\":")
  (data (i32.const 43112) "{\"event\":\"ValueCharged\"")
  (data (i32.const 43135) ",\"gross\":")
  (data (i32.const 43144) ",\"fee\":")
  (data (i32.const 43151) ",\"net\":")
  (data (i32.const 43158) "{\"event\":\"ValueReleased\"")
  (data (i32.const 43182) ",\"released\":")
  (data (i32.const 43194) "{\"event\":\"ValueSnapshot\"")
  (data (i32.const 43218) ",\"fees\":")
)
