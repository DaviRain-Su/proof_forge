  ; ProofForge generated sBPF — Counter (Phase 1)
  ; Target: solana-sbpf-asm (D-026)

.equ INSTRUCTION_DATA_LEN, 10352
.equ INSTRUCTION_DATA, 10360
.equ COUNT_DATA, 96

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
  jeq r2, 1, sol_increment
  jeq r2, 2, sol_get
  mov64 r0, 1
  exit

sol_initialize:

  ; account.validation: generated account schema
  ; account.validation[0:count]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:count]: owner=program
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
  mov64 r2, 0
  stxdw [r1+96], r2
  mov64 r0, 0
  exit

sol_increment:

  ; account.validation: generated account schema
  ; account.validation[0:count]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:count]: owner=program
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
  ldxdw r2, [r10-8]
  stxdw [r10-24], r2
  mov64 r2, 1
  ldxdw r3, [r10-24]
  add64 r2, r3
  stxdw [r1+96], r2
  mov64 r0, 0
  exit

sol_get:

  ; account.validation: generated account schema
  ; account.validation[0:count]: writable=true
  mov64 r7, r10
  sub64 r7, 3328
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:count]: owner=program
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
