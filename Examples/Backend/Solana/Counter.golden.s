.text
.globl entrypoint
entrypoint:
  ; save instruction_data pointer from generated Solana input layout
  ; scan Solana input account pointers into current stack frame
  mov64 r3, r1
  add64 r3, 8
  mov64 r6, r10
  sub64 r6, 3488
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
  stxdw [r10-4008], r9
  ldxb r2, [r9+0]
  jeq r2, 0, sol_core_0_0
  jeq r2, 1, sol_core_1_1
  jeq r2, 2, sol_core_2_2
  mov64 r0, 9
  exit
sol_initialize:
sol_core_0_0:
  mov64 r2, 0
  stxdw [r10-8], r2
  ldxdw r2, [r10-8]
  stxdw [r1+96], r2
  mov64 r0, 0
  exit
sol_increment:
sol_core_1_1:
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
