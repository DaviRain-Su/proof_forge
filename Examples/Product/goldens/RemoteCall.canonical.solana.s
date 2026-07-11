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
  mov64 r6, r10
  sub64 r6, 3488
  stxdw [r6+8], r3
  ldxdw r4, [r3+80]
  add64 r3, 88
  add64 r3, r4
  add64 r3, 10240
  add64 r3, 8
  mov64 r5, r3
  and64 r5, 7
  jeq r5, 0, entrypoint_account_scan_1_aligned
  mov64 r6, 8
  sub64 r6, r5
  add64 r3, r6
entrypoint_account_scan_1_aligned:
  mov64 r6, r10
  sub64 r6, 3488
  stxdw [r6+16], r3
  ldxdw r4, [r3+80]
  add64 r3, 88
  add64 r3, r4
  add64 r3, 10240
  add64 r3, 8
  mov64 r5, r3
  and64 r5, 7
  jeq r5, 0, entrypoint_account_scan_2_aligned
  mov64 r6, 8
  sub64 r6, r5
  add64 r3, r6
entrypoint_account_scan_2_aligned:
  mov64 r6, r10
  sub64 r6, 3488
  stxdw [r6+24], r3
  ldxdw r4, [r3+80]
  add64 r3, 88
  add64 r3, r4
  add64 r3, 10240
  add64 r3, 8
  mov64 r5, r3
  and64 r5, 7
  jeq r5, 0, entrypoint_account_scan_3_aligned
  mov64 r6, 8
  sub64 r6, r5
  add64 r3, r6
entrypoint_account_scan_3_aligned:
  mov64 r6, r10
  sub64 r6, 3488
  stxdw [r6+32], r3
  ldxdw r4, [r3+80]
  add64 r3, 88
  add64 r3, r4
  add64 r3, 10240
  add64 r3, 8
  mov64 r5, r3
  and64 r5, 7
  jeq r5, 0, entrypoint_account_scan_4_aligned
  mov64 r6, 8
  sub64 r6, r5
  add64 r3, r6
entrypoint_account_scan_4_aligned:
  mov64 r9, r3
  add64 r9, 8
  stxdw [r10-4008], r9
  ldxb r2, [r9+0]
  jeq r2, 0, sol_core_0_0
  jeq r2, 1, sol_core_1_1
  jeq r2, 2, sol_core_2_2
  mov64 r0, 9
  exit
sol_core_0_0:
  mov64 r2, 0
  stxdw [r10-8], r2
  ldxdw r2, [r10-8]
  stxdw [r1+96], r2
  mov64 r0, 0
  exit
sol_core_1_1:
  mov64 r2, 0
  stxdw [r10-16], r2
  mov64 r2, 1
  stxdw [r10-24], r2
  ; portable peer handle -> peer/callee account index 4
  mov64 r2, 4
  stxdw [r10-3280], r2
  ldxdw r2, [r10-24]
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r8+0], r2
  ; portable crosscall → sol_invoke_signed_c (data_len=8, accounts=0/64, empty AccountMeta pack (pure peer method+args), signers=0)
  stxdw [r10-4000], r1
  ; portable CPI: program_id ← input account[target].key (32 bytes)
  mov64 r6, r10
  sub64 r6, 3488
  ldxdw r2, [r10-3280]
  mul64 r2, 8
  add64 r6, r2
  ldxdw r7, [r6+0]
  add64 r7, 8
  mov64 r8, r10
  sub64 r8, 1152
  ldxdw r3, [r7+0]
  stxdw [r8+0], r3
  ldxdw r3, [r7+8]
  stxdw [r8+8], r3
  ldxdw r3, [r7+16]
  stxdw [r8+16], r3
  ldxdw r3, [r7+24]
  stxdw [r8+24], r3
  ; portable CPI: empty AccountMeta pack (pure peer method+args); infos@stack-2048
  ; portable CPI: SolInstruction (program_id, 0 metas, ix data)
  mov64 r5, r10
  sub64 r5, 64
  mov64 r8, r10
  sub64 r8, 1152
  stxdw [r5+0], r8
  mov64 r7, r10
  sub64 r7, 128
  stxdw [r5+8], r7
  mov64 r3, 0
  stxdw [r5+16], r3
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r5+24], r8
  mov64 r3, 8
  stxdw [r5+32], r3
  mov64 r1, r10
  sub64 r1, 64
  mov64 r2, r10
  sub64 r2, 2048
  mov64 r3, 0
  mov64 r4, 0
  mov64 r5, 0
  ; r1=instruction_ptr r2=infos_ptr r3=0 r4=0 r5=0 (empty AccountMeta pack (pure peer method+args))
  call sol_invoke_signed_c
  jne r0, 0, error_cpi
  ldxdw r1, [r10-4000]
  ; portable CPI: decode first u64 of sol_get_return_data → r2
  mov64 r1, r10
  sub64 r1, 3200
  mov64 r2, 8
  mov64 r3, r10
  sub64 r3, 3240
  stdw [r3+0], 0
  stdw [r3+8], 0
  stdw [r3+16], 0
  stdw [r3+24], 0
  ; r1=data_ptr r2=max_len=8 r3=program_id_ptr (non-overlapping)
  call sol_get_return_data
  jlt r0, 8, core_cpi_1_1_2_return_none
  mov64 r3, r10
  sub64 r3, 3200
  ldxdw r2, [r3+0]
  ja core_cpi_1_1_2_return_end
core_cpi_1_1_2_return_none:
  mov64 r2, 0
core_cpi_1_1_2_return_end:
  stxdw [r10-32], r2
  ldxdw r2, [r10-32]
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit
sol_core_2_2:
  mov64 r2, 0
  stxdw [r10-40], r2
  mov64 r2, 1
  stxdw [r10-48], r2
  mov64 r2, 42
  stxdw [r10-56], r2
  mov64 r2, 7
  stxdw [r10-64], r2
  ; portable peer handle -> peer/callee account index 4
  mov64 r2, 4
  stxdw [r10-3280], r2
  ldxdw r2, [r10-48]
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r8+0], r2
  ldxdw r2, [r10-56]
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r8+8], r2
  ldxdw r2, [r10-64]
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r8+16], r2
  ; portable crosscall → sol_invoke_signed_c (data_len=24, accounts=0/64, empty AccountMeta pack (pure peer method+args), signers=0)
  stxdw [r10-4000], r1
  ; portable CPI: program_id ← input account[target].key (32 bytes)
  mov64 r6, r10
  sub64 r6, 3488
  ldxdw r2, [r10-3280]
  mul64 r2, 8
  add64 r6, r2
  ldxdw r7, [r6+0]
  add64 r7, 8
  mov64 r8, r10
  sub64 r8, 1152
  ldxdw r3, [r7+0]
  stxdw [r8+0], r3
  ldxdw r3, [r7+8]
  stxdw [r8+8], r3
  ldxdw r3, [r7+16]
  stxdw [r8+16], r3
  ldxdw r3, [r7+24]
  stxdw [r8+24], r3
  ; portable CPI: empty AccountMeta pack (pure peer method+args); infos@stack-2048
  ; portable CPI: SolInstruction (program_id, 0 metas, ix data)
  mov64 r5, r10
  sub64 r5, 64
  mov64 r8, r10
  sub64 r8, 1152
  stxdw [r5+0], r8
  mov64 r7, r10
  sub64 r7, 128
  stxdw [r5+8], r7
  mov64 r3, 0
  stxdw [r5+16], r3
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r5+24], r8
  mov64 r3, 24
  stxdw [r5+32], r3
  mov64 r1, r10
  sub64 r1, 64
  mov64 r2, r10
  sub64 r2, 2048
  mov64 r3, 0
  mov64 r4, 0
  mov64 r5, 0
  ; r1=instruction_ptr r2=infos_ptr r3=0 r4=0 r5=0 (empty AccountMeta pack (pure peer method+args))
  call sol_invoke_signed_c
  jne r0, 0, error_cpi
  ldxdw r1, [r10-4000]
  ; portable CPI: decode first u64 of sol_get_return_data → r2
  mov64 r1, r10
  sub64 r1, 3200
  mov64 r2, 8
  mov64 r3, r10
  sub64 r3, 3240
  stdw [r3+0], 0
  stdw [r3+8], 0
  stdw [r3+16], 0
  stdw [r3+24], 0
  ; r1=data_ptr r2=max_len=8 r3=program_id_ptr (non-overlapping)
  call sol_get_return_data
  jlt r0, 8, core_cpi_2_2_4_return_none
  mov64 r3, r10
  sub64 r3, 3200
  ldxdw r2, [r3+0]
  ja core_cpi_2_2_4_return_end
core_cpi_2_2_4_return_none:
  mov64 r2, 0
core_cpi_2_2_4_return_end:
  stxdw [r10-72], r2
  ldxdw r2, [r10-72]
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
error_cpi:
  mov64 r0, 8
  exit
