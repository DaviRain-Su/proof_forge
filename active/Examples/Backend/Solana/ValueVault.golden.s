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
  ldxb r2, [r9+0]
  jeq r2, 0, sol_core_0_0
  jeq r2, 1, sol_core_1_1
  jeq r2, 2, sol_core_2_2
  jeq r2, 3, sol_core_3_3
  jeq r2, 4, sol_core_4_4
  jeq r2, 5, sol_core_5_5
  jeq r2, 6, sol_core_6_6
  mov64 r0, 9
  exit
sol_initialize:
sol_core_0_0:
  ldxdw r2, [r9+1]
  stxdw [r10-8], r2
  stxdw [r10-400], r1
  mov64 r1, r10
  sub64 r1, 480
  call sol_get_clock_sysvar
  jne r0, 0, error_syscall
  ldxdw r2, [r10-480]
  stxdw [r10-16], r2
  ldxdw r1, [r10-400]
  ldxdw r2, [r10-8]
  stxdw [r1+96], r2
  mov64 r2, 0
  stxdw [r10-24], r2
  ldxdw r2, [r10-24]
  stxdw [r1+104], r2
  mov64 r2, 0
  stxdw [r10-32], r2
  ldxdw r2, [r10-32]
  stxdw [r1+112], r2
  ldxdw r2, [r10-8]
  stxdw [r1+120], r2
  ldxdw r2, [r10-16]
  stxdw [r1+128], r2
  mov64 r2, 1
  stxdw [r10-40], r2
  ldxdw r2, [r10-40]
  stxdw [r1+136], r2
  ; solana.event.emit VaultInitialized (event_id=0)
  ldxdw r3, [r10-8]
  stxdw [r10-400], r1
  mov64 r1, 0
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-16]
  stxdw [r10-400], r1
  mov64 r1, 0
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  mov64 r0, 0
  exit
sol_deposit:
sol_core_1_1:
  ldxdw r2, [r9+1]
  stxdw [r10-48], r2
  ldxdw r2, [r1+96]
  stxdw [r10-56], r2
  ldxdw r2, [r10-56]
  ldxdw r3, [r10-48]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-64], r2
  ldxdw r2, [r1+136]
  stxdw [r10-72], r2
  mov64 r2, 1
  stxdw [r10-80], r2
  ldxdw r2, [r10-72]
  ldxdw r3, [r10-80]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-88], r2
  ldxdw r2, [r10-64]
  stxdw [r1+96], r2
  ldxdw r2, [r10-48]
  stxdw [r1+120], r2
  ldxdw r2, [r10-88]
  stxdw [r1+136], r2
  ; solana.event.emit ValueDeposited (event_id=1)
  ldxdw r3, [r10-48]
  stxdw [r10-400], r1
  mov64 r1, 1
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-64]
  stxdw [r10-400], r1
  mov64 r1, 1
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-88]
  stxdw [r10-400], r1
  mov64 r1, 1
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  mov64 r0, 0
  exit
sol_charge_fee:
sol_core_2_2:
  ldxdw r2, [r9+1]
  stxdw [r10-96], r2
  ldxdw r2, [r9+9]
  stxdw [r10-104], r2
  ldxdw r2, [r10-96]
  ldxdw r3, [r10-104]
  mov64 r4, r2
  mul64 r2, r3
  jeq r3, 0, core_mul_2_2_0_done
  mov64 r5, r2
  div64 r5, r3
  jne r5, r4, error_arithmetic
core_mul_2_2_0_done:
  stxdw [r10-112], r2
  mov64 r2, 10000
  stxdw [r10-120], r2
  ldxdw r2, [r10-112]
  ldxdw r3, [r10-120]
  div64 r2, r3
  stxdw [r10-128], r2
  ldxdw r2, [r10-96]
  ldxdw r3, [r10-128]
  jlt r2, r3, error_arithmetic
  sub64 r2, r3
  stxdw [r10-136], r2
  ldxdw r2, [r1+96]
  stxdw [r10-144], r2
  ldxdw r2, [r10-144]
  ldxdw r3, [r10-136]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-152], r2
  ldxdw r2, [r1+112]
  stxdw [r10-160], r2
  ldxdw r2, [r10-160]
  ldxdw r3, [r10-128]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-168], r2
  ldxdw r2, [r1+136]
  stxdw [r10-176], r2
  mov64 r2, 1
  stxdw [r10-184], r2
  ldxdw r2, [r10-176]
  ldxdw r3, [r10-184]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-192], r2
  ldxdw r2, [r10-152]
  stxdw [r1+96], r2
  ldxdw r2, [r10-168]
  stxdw [r1+112], r2
  ldxdw r2, [r10-136]
  stxdw [r1+120], r2
  ldxdw r2, [r10-192]
  stxdw [r1+136], r2
  ; solana.event.emit ValueCharged (event_id=2)
  ldxdw r3, [r10-96]
  stxdw [r10-400], r1
  mov64 r1, 2
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-128]
  stxdw [r10-400], r1
  mov64 r1, 2
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-136]
  stxdw [r10-400], r1
  mov64 r1, 2
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-152]
  stxdw [r10-400], r1
  mov64 r1, 2
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  mov64 r0, 0
  exit
sol_release:
sol_core_3_3:
  ldxdw r2, [r9+1]
  stxdw [r10-200], r2
  ldxdw r2, [r1+96]
  stxdw [r10-208], r2
  ldxdw r2, [r10-208]
  ldxdw r3, [r10-200]
  jlt r2, r3, error_arithmetic
  sub64 r2, r3
  stxdw [r10-216], r2
  ldxdw r2, [r1+104]
  stxdw [r10-224], r2
  ldxdw r2, [r10-224]
  ldxdw r3, [r10-200]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-232], r2
  ldxdw r2, [r1+136]
  stxdw [r10-240], r2
  mov64 r2, 1
  stxdw [r10-248], r2
  ldxdw r2, [r10-240]
  ldxdw r3, [r10-248]
  mov64 r4, r2
  add64 r2, r3
  jlt r2, r4, error_arithmetic
  stxdw [r10-256], r2
  ldxdw r2, [r10-216]
  stxdw [r1+96], r2
  ldxdw r2, [r10-232]
  stxdw [r1+104], r2
  ldxdw r2, [r10-200]
  stxdw [r1+120], r2
  ldxdw r2, [r10-256]
  stxdw [r1+136], r2
  ; solana.event.emit ValueReleased (event_id=3)
  ldxdw r3, [r10-200]
  stxdw [r10-400], r1
  mov64 r1, 3
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-216]
  stxdw [r10-400], r1
  mov64 r1, 3
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-232]
  stxdw [r10-400], r1
  mov64 r1, 3
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  mov64 r0, 0
  exit
sol_snapshot:
sol_core_4_4:
  stxdw [r10-400], r1
  mov64 r1, r10
  sub64 r1, 480
  call sol_get_clock_sysvar
  jne r0, 0, error_syscall
  ldxdw r2, [r10-480]
  stxdw [r10-264], r2
  ldxdw r1, [r10-400]
  ldxdw r2, [r1+96]
  stxdw [r10-272], r2
  ldxdw r2, [r1+104]
  stxdw [r10-280], r2
  ldxdw r2, [r1+112]
  stxdw [r10-288], r2
  ldxdw r2, [r10-264]
  stxdw [r1+128], r2
  ; solana.event.emit ValueSnapshot (event_id=4)
  ldxdw r3, [r10-272]
  stxdw [r10-400], r1
  mov64 r1, 4
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-280]
  stxdw [r10-400], r1
  mov64 r1, 4
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-288]
  stxdw [r10-400], r1
  mov64 r1, 4
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r3, [r10-264]
  stxdw [r10-400], r1
  mov64 r1, 4
  mov64 r2, 0
  mov64 r4, 0
  mov64 r5, 0
  call sol_log_64_
  ldxdw r1, [r10-400]
  ldxdw r2, [r10-272]
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit
sol_get_balance:
sol_core_5_5:
  ldxdw r2, [r1+96]
  stxdw [r10-296], r2
  ldxdw r2, [r10-296]
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit
sol_get_net_value:
sol_core_6_6:
  ldxdw r2, [r1+96]
  stxdw [r10-304], r2
  ldxdw r2, [r1+112]
  stxdw [r10-312], r2
  ldxdw r2, [r10-304]
  ldxdw r3, [r10-312]
  jlt r2, r3, error_arithmetic
  sub64 r2, r3
  stxdw [r10-320], r2
  ldxdw r2, [r10-320]
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
