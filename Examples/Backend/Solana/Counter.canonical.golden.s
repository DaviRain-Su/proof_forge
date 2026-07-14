.text
.globl entrypoint
entrypoint:
  ; save instruction_data pointer from generated Solana input layout
  ; scan runtime Solana input account pointers into current stack frame
  ldxdw r2, [r1+0]
  jgt r2, 1, error_account_count
  mov64 r3, r1
  add64 r3, 8
  mov64 r7, 0
entrypoint_account_scan_loop:
  jge r7, r2, entrypoint_account_scan_done
  ldxb r4, [r3+0]
  jeq r4, 255, entrypoint_account_scan_unique
  jge r4, r7, error_duplicate_account
  lsh64 r4, 3
  mov64 r6, r10
  sub64 r6, 3488
  add64 r6, r4
  ldxdw r4, [r6+0]
  mov64 r5, r7
  lsh64 r5, 3
  mov64 r6, r10
  sub64 r6, 3488
  add64 r6, r5
  stxdw [r6+0], r4
  add64 r3, 8
  ja entrypoint_account_scan_next
entrypoint_account_scan_unique:
  mov64 r5, r7
  lsh64 r5, 3
  mov64 r6, r10
  sub64 r6, 3488
  add64 r6, r5
  stxdw [r6+0], r3
  ldxdw r4, [r3+80]
  add64 r3, 88
  add64 r3, r4
  add64 r3, 10240
  add64 r3, 8
  mov64 r5, r3
  and64 r5, 7
  jeq r5, 0, entrypoint_account_scan_aligned
  mov64 r6, 8
  sub64 r6, r5
  add64 r3, r6
entrypoint_account_scan_aligned:
entrypoint_account_scan_next:
  add64 r7, 1
  ja entrypoint_account_scan_loop
entrypoint_account_scan_done:
  mov64 r9, r3
  add64 r9, 8
  stxdw [r10-4008], r9
  ; instruction_data.length >= 1
  mov64 r3, r9
  mov64 r4, r3
  sub64 r4, 8
  ldxdw r2, [r4+0]
  jlt r2, 1, error_instruction_data
  ldxb r2, [r9+0]
  jeq r2, 0, sol_core_0_0
  jeq r2, 1, sol_core_1_1
  jeq r2, 2, sol_core_2_2
  mov64 r0, 9
  exit
sol_initialize:
sol_core_0_0:
  ; account.graph: exact runtime count = 1
  ldxdw r2, [r1+0]
  jne r2, 1, error_account_count
  ; account.validation: generated account schema
  ; account.validation[0:program_state]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:program_state]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3488
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
  stxdw [r10-8], r2
  ldxdw r2, [r10-8]
  stxdw [r1+96], r2
  mov64 r0, 0
  exit
sol_increment:
sol_core_1_1:
  ; account.graph: exact runtime count = 1
  ldxdw r2, [r1+0]
  jne r2, 1, error_account_count
  ; account.validation: generated account schema
  ; account.validation[0:program_state]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:program_state]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3488
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
  stxdw [r10-16], r2
  mov64 r2, 1
  stxdw [r10-24], r2
  ldxdw r2, [r10-16]
  ldxdw r3, [r10-24]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-32], r2
  ldxdw r2, [r10-32]
  stxdw [r1+96], r2
  mov64 r0, 0
  exit
sol_get:
sol_core_2_2:
  ; account.graph: exact runtime count = 1
  ldxdw r2, [r1+0]
  jne r2, 1, error_account_count
  ; account.validation: generated account schema
  ; account.validation[0:program_state]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:program_state]: owner=program
  mov64 r4, r9
  mov64 r2, r4
  sub64 r2, 8
  ldxdw r2, [r2+0]
  add64 r4, r2
  stxdw [r10-3600], r4
  mov64 r7, r10
  sub64 r7, 3488
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
  stxdw [r10-40], r2
  ldxdw r2, [r10-40]
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
error_syscall:
  mov64 r0, 10
  exit
error_arithmetic:
  mov64 r0, 13
  exit
error_map_capacity:
  mov64 r0, 14
  exit
error_duplicate_account:
  mov64 r0, 13
  exit
error_account_count:
  mov64 r0, 14
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
