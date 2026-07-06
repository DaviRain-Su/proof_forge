  ; ProofForge generated sBPF — ValueVault (Phase 1)
  ; Target: solana-sbpf-asm (D-026)

.equ INSTRUCTION_DATA_LEN, 10392
.equ INSTRUCTION_DATA, 10400
.equ BALANCE_DATA, 96
.equ RELEASED_DATA, 104
.equ FEES_DATA, 112
.equ LAST_VALUE_DATA, 120
.equ LAST_CHECKPOINT_DATA, 128
.equ OPERATIONS_DATA, 136

.globl entrypoint

entrypoint:
  ; save instruction_data pointer from generated Solana input layout
  ; scan Solana input account pointers into current stack frame
  mov64 r3, r1
  add64 r3, 8
  mov64 r6, r10
  sub64 r6, 3328
  stxdw [r6+0], r3
  ldxdw r4, [r3+80]
  add64 r3, 88
  add64 r3, r4
  add64 r3, 10240
  add64 r3, 8
  mov64 r5, r3
  and64 r5, 7
  jeq r5, 0, entrypoint_account_scan_0_aligned
  mov64 r6, 8
  sub64 r6, r5
  add64 r3, r6
entrypoint_account_scan_0_aligned:
  mov64 r9, r3
  add64 r9, 8
  stxdw [r10-3584], r9
  ; instruction_data.length >= 1
  ldxdw r3, [r10-3584]
  sub64 r3, 8
  ldxdw r2, [r3+0]
  jlt r2, 1, error_instruction_data
  ldxdw r3, [r10-3584]
  ldxb r2, [r3+0]
  jeq r2, 0, sol_initialize
  jeq r2, 1, sol_deposit
  jeq r2, 2, sol_charge_fee
  jeq r2, 3, sol_release
  jeq r2, 4, sol_snapshot
  jeq r2, 5, sol_get_balance
  jeq r2, 6, sol_get_net_value
  mov64 r0, 1
  exit

sol_initialize:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ; instruction_data.length >= 9
  mov64 r3, r9
  mov64 r4, r3
  sub64 r4, 8
  ldxdw r2, [r4+0]
  jlt r2, 9, error_instruction_data
  ; entrypoint.param[initialize.initial]: U64 @ instruction_data+1
  mov64 r3, r9
  ldxdw r2, [r3+1]
  stxdw [r10-8], r2
  ; solana.sysvar.clock: sol_get_clock_sysvar -> Clock.slot
  stxdw [r10-24], r1
  mov64 r1, r10
  sub64 r1, 64
  call sol_get_clock_sysvar
  jne r0, 0, error_syscall
  ldxdw r2, [r10-64]
  ldxdw r1, [r10-24]
  stxdw [r10-16], r2
  ldxdw r2, [r10-8]
  stxdw [r1+96], r2
  mov64 r2, 0
  stxdw [r1+104], r2
  mov64 r2, 0
  stxdw [r1+112], r2
  ldxdw r2, [r10-8]
  stxdw [r1+120], r2
  ldxdw r2, [r10-16]
  stxdw [r1+128], r2
  mov64 r2, 1
  stxdw [r1+136], r2
  ; solana.event.emit VaultInitialized: sol_log_64_ scalar fields
  ldxdw r2, [r10-8]
  ; solana.event.field VaultInitialized.initial: tag=2316149127 index=0
  stxdw [r10-72], r1
  mov64 r3, r2
  mov64 r1, 2316149127
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-72]
  ldxdw r2, [r10-16]
  ; solana.event.field VaultInitialized.checkpoint: tag=2316149127 index=1
  stxdw [r10-80], r1
  mov64 r3, r2
  mov64 r1, 2316149127
  mov64 r2, 1
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-80]
  mov64 r0, 0
  exit

sol_deposit:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ; instruction_data.length >= 9
  mov64 r3, r9
  mov64 r4, r3
  sub64 r4, 8
  ldxdw r2, [r4+0]
  jlt r2, 9, error_instruction_data
  ; entrypoint.param[deposit.amount]: U64 @ instruction_data+1
  mov64 r3, r9
  ldxdw r2, [r3+1]
  stxdw [r10-8], r2
  ldxdw r2, [r1+96]
  stxdw [r10-16], r2
  ldxdw r2, [r10-16]
  stxdw [r10-32], r2
  ldxdw r2, [r10-8]
  ldxdw r3, [r10-32]
  add64 r2, r3
  stxdw [r10-24], r2
  ldxdw r2, [r1+136]
  stxdw [r10-32], r2
  ldxdw r2, [r10-32]
  stxdw [r10-48], r2
  mov64 r2, 1
  ldxdw r3, [r10-48]
  add64 r2, r3
  stxdw [r10-40], r2
  ldxdw r2, [r10-24]
  stxdw [r1+96], r2
  ldxdw r2, [r10-8]
  stxdw [r1+120], r2
  ldxdw r2, [r10-40]
  stxdw [r1+136], r2
  ; solana.event.emit ValueDeposited: sol_log_64_ scalar fields
  ldxdw r2, [r10-8]
  ; solana.event.field ValueDeposited.amount: tag=419180867 index=0
  stxdw [r10-56], r1
  mov64 r3, r2
  mov64 r1, 419180867
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-56]
  ldxdw r2, [r10-24]
  ; solana.event.field ValueDeposited.balance: tag=419180867 index=1
  stxdw [r10-64], r1
  mov64 r3, r2
  mov64 r1, 419180867
  mov64 r2, 1
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-64]
  ldxdw r2, [r10-40]
  ; solana.event.field ValueDeposited.operations: tag=419180867 index=2
  stxdw [r10-72], r1
  mov64 r3, r2
  mov64 r1, 419180867
  mov64 r2, 2
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-72]
  mov64 r0, 0
  exit

sol_charge_fee:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ; instruction_data.length >= 17
  mov64 r3, r9
  mov64 r4, r3
  sub64 r4, 8
  ldxdw r2, [r4+0]
  jlt r2, 17, error_instruction_data
  ; entrypoint.param[charge_fee.gross]: U64 @ instruction_data+1
  mov64 r3, r9
  ldxdw r2, [r3+1]
  stxdw [r10-8], r2
  ; entrypoint.param[charge_fee.fee_bps]: U64 @ instruction_data+9
  mov64 r3, r9
  ldxdw r2, [r3+9]
  stxdw [r10-16], r2
  ldxdw r2, [r10-8]
  stxdw [r10-32], r2
  ldxdw r2, [r10-16]
  ldxdw r3, [r10-32]
  mul64 r2, r3
  stxdw [r10-40], r2
  mov64 r2, 10000
  mov64 r3, r2
  ldxdw r2, [r10-40]
  div64 r2, r3
  stxdw [r10-24], r2
  ldxdw r2, [r10-8]
  stxdw [r10-48], r2
  ldxdw r2, [r10-24]
  mov64 r3, r2
  ldxdw r2, [r10-48]
  sub64 r2, r3
  stxdw [r10-32], r2
  ldxdw r2, [r1+96]
  stxdw [r10-40], r2
  ldxdw r2, [r10-40]
  stxdw [r10-56], r2
  ldxdw r2, [r10-32]
  ldxdw r3, [r10-56]
  add64 r2, r3
  stxdw [r10-48], r2
  ldxdw r2, [r1+112]
  stxdw [r10-56], r2
  ldxdw r2, [r10-56]
  stxdw [r10-72], r2
  ldxdw r2, [r10-24]
  ldxdw r3, [r10-72]
  add64 r2, r3
  stxdw [r10-64], r2
  ldxdw r2, [r1+136]
  stxdw [r10-72], r2
  ldxdw r2, [r10-72]
  stxdw [r10-88], r2
  mov64 r2, 1
  ldxdw r3, [r10-88]
  add64 r2, r3
  stxdw [r10-80], r2
  ldxdw r2, [r10-48]
  stxdw [r1+96], r2
  ldxdw r2, [r10-64]
  stxdw [r1+112], r2
  ldxdw r2, [r10-32]
  stxdw [r1+120], r2
  ldxdw r2, [r10-80]
  stxdw [r1+136], r2
  ; solana.event.emit ValueCharged: sol_log_64_ scalar fields
  ldxdw r2, [r10-8]
  ; solana.event.field ValueCharged.gross: tag=2567218288 index=0
  stxdw [r10-96], r1
  mov64 r3, r2
  mov64 r1, 2567218288
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-96]
  ldxdw r2, [r10-24]
  ; solana.event.field ValueCharged.fee: tag=2567218288 index=1
  stxdw [r10-104], r1
  mov64 r3, r2
  mov64 r1, 2567218288
  mov64 r2, 1
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-104]
  ldxdw r2, [r10-32]
  ; solana.event.field ValueCharged.net: tag=2567218288 index=2
  stxdw [r10-112], r1
  mov64 r3, r2
  mov64 r1, 2567218288
  mov64 r2, 2
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-112]
  ldxdw r2, [r10-48]
  ; solana.event.field ValueCharged.balance: tag=2567218288 index=3
  stxdw [r10-120], r1
  mov64 r3, r2
  mov64 r1, 2567218288
  mov64 r2, 3
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-120]
  mov64 r0, 0
  exit

sol_release:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ; instruction_data.length >= 9
  mov64 r3, r9
  mov64 r4, r3
  sub64 r4, 8
  ldxdw r2, [r4+0]
  jlt r2, 9, error_instruction_data
  ; entrypoint.param[release.amount]: U64 @ instruction_data+1
  mov64 r3, r9
  ldxdw r2, [r3+1]
  stxdw [r10-8], r2
  ldxdw r2, [r1+96]
  stxdw [r10-16], r2
  ldxdw r2, [r10-16]
  stxdw [r10-32], r2
  ldxdw r2, [r10-8]
  mov64 r3, r2
  ldxdw r2, [r10-32]
  sub64 r2, r3
  stxdw [r10-24], r2
  ldxdw r2, [r1+104]
  stxdw [r10-32], r2
  ldxdw r2, [r10-32]
  stxdw [r10-48], r2
  ldxdw r2, [r10-8]
  ldxdw r3, [r10-48]
  add64 r2, r3
  stxdw [r10-40], r2
  ldxdw r2, [r1+136]
  stxdw [r10-48], r2
  ldxdw r2, [r10-48]
  stxdw [r10-64], r2
  mov64 r2, 1
  ldxdw r3, [r10-64]
  add64 r2, r3
  stxdw [r10-56], r2
  ldxdw r2, [r10-24]
  stxdw [r1+96], r2
  ldxdw r2, [r10-40]
  stxdw [r1+104], r2
  ldxdw r2, [r10-8]
  stxdw [r1+120], r2
  ldxdw r2, [r10-56]
  stxdw [r1+136], r2
  ; solana.event.emit ValueReleased: sol_log_64_ scalar fields
  ldxdw r2, [r10-8]
  ; solana.event.field ValueReleased.amount: tag=3275777927 index=0
  stxdw [r10-72], r1
  mov64 r3, r2
  mov64 r1, 3275777927
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-72]
  ldxdw r2, [r10-24]
  ; solana.event.field ValueReleased.balance: tag=3275777927 index=1
  stxdw [r10-80], r1
  mov64 r3, r2
  mov64 r1, 3275777927
  mov64 r2, 1
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-80]
  ldxdw r2, [r10-40]
  ; solana.event.field ValueReleased.released: tag=3275777927 index=2
  stxdw [r10-88], r1
  mov64 r3, r2
  mov64 r1, 3275777927
  mov64 r2, 2
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-88]
  mov64 r0, 0
  exit

sol_snapshot:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ; solana.sysvar.clock: sol_get_clock_sysvar -> Clock.slot
  stxdw [r10-8], r1
  mov64 r1, r10
  sub64 r1, 48
  call sol_get_clock_sysvar
  jne r0, 0, error_syscall
  ldxdw r2, [r10-48]
  ldxdw r1, [r10-8]
  stxdw [r10-8], r2
  ldxdw r2, [r1+96]
  stxdw [r10-16], r2
  ldxdw r2, [r1+104]
  stxdw [r10-24], r2
  ldxdw r2, [r1+112]
  stxdw [r10-32], r2
  ldxdw r2, [r10-8]
  stxdw [r1+128], r2
  ; solana.event.emit ValueSnapshot: sol_log_64_ scalar fields
  ldxdw r2, [r10-16]
  ; solana.event.field ValueSnapshot.balance: tag=1266048818 index=0
  stxdw [r10-56], r1
  mov64 r3, r2
  mov64 r1, 1266048818
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-56]
  ldxdw r2, [r10-24]
  ; solana.event.field ValueSnapshot.released: tag=1266048818 index=1
  stxdw [r10-64], r1
  mov64 r3, r2
  mov64 r1, 1266048818
  mov64 r2, 1
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-64]
  ldxdw r2, [r10-32]
  ; solana.event.field ValueSnapshot.fees: tag=1266048818 index=2
  stxdw [r10-72], r1
  mov64 r3, r2
  mov64 r1, 1266048818
  mov64 r2, 2
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-72]
  ldxdw r2, [r10-8]
  ; solana.event.field ValueSnapshot.checkpoint: tag=1266048818 index=3
  stxdw [r10-80], r1
  mov64 r3, r2
  mov64 r1, 1266048818
  mov64 r2, 3
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-80]
  ldxdw r2, [r10-16]
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit

sol_get_balance:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ldxdw r2, [r1+96]
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit

sol_get_net_value:

  ; account.validation: generated account schema
  ; account.validation[0:balance]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:balance]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 40
  ldxdw r4, [r10-3600]
  ldxdw r5, [r7+0]
  ldxdw r6, [r4+0]
  jne r5, r6, error_owner
  ldxdw r5, [r7+8]
  ldxdw r6, [r4+8]
  jne r5, r6, error_owner
  ldxdw r5, [r7+16]
  ldxdw r6, [r4+16]
  jne r5, r6, error_owner
  ldxdw r5, [r7+24]
  ldxdw r6, [r4+24]
  jne r5, r6, error_owner
  ldxdw r2, [r1+96]
  stxdw [r10-8], r2
  ldxdw r2, [r1+112]
  stxdw [r10-16], r2
  ldxdw r2, [r10-8]
  stxdw [r10-32], r2
  ldxdw r2, [r10-16]
  mov64 r3, r2
  ldxdw r2, [r10-32]
  sub64 r2, r3
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit

assert_fail:
  mov64 r0, 2
  exit

assert_eq_fail:
  mov64 r0, 3
  exit

error_not_writable:
  mov64 r0, 4
  exit

error_signer:
  mov64 r0, 5
  exit

error_owner:
  mov64 r0, 6
  exit

error_instruction_data:
  mov64 r0, 9
  exit

error_pda_bump:
  mov64 r0, 11
  exit

error_array_bounds:
  mov64 r0, 12
  exit

error_syscall:
  mov64 r0, 10
  exit
