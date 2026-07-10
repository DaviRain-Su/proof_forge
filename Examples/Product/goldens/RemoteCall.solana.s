  ; ProofForge generated sBPF — RemoteCall (Phase 1)
  ; Target: solana-sbpf-asm (D-026)

.equ INSTRUCTION_DATA_LEN, 51696
.equ INSTRUCTION_DATA, 51704
.equ MARKER_DATA, 96

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
  ; instruction_data.length >= 1
  ldxdw r3, [r10-4008]
  sub64 r3, 8
  ldxdw r2, [r3+0]
  jlt r2, 1, error_instruction_data
  ldxdw r3, [r10-4008]
  ldxb r2, [r3+0]
  jeq r2, 0, sol_initialize
  jeq r2, 1, sol_call_remote
  jeq r2, 2, sol_call_with_args
  mov64 r0, 1
  exit

sol_initialize:

  ; account.validation: generated account schema
  ; account.validation[0:marker]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:marker]: owner=program
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
  ; account.validation[1:payer]: signer=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+8]
  add64 r7, 1
  ldxb r2, [r7+0]
  jeq r2, 0, error_signer
  ; account.validation[1:payer]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+8]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[2:peer_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+16]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; account.validation[3:system_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+24]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; account.validation[4:callee_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+32]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  mov64 r2, 0
  stxdw [r1+96], r2
  mov64 r0, 0
  exit

sol_call_remote:

  ; account.validation: generated account schema
  ; account.validation[0:marker]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:marker]: owner=program
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
  ; account.validation[1:payer]: signer=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+8]
  add64 r7, 1
  ldxb r2, [r7+0]
  jeq r2, 0, error_signer
  ; account.validation[1:payer]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+8]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[2:peer_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+16]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; account.validation[3:system_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+24]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; account.validation[4:callee_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+32]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; portable peer handle → peer/callee account index 2 (PF-P2-03)
  mov64 r2, 2
  stxdw [r10-3280], r2
  ; portable address handle → u64 account index 1
  mov64 r2, 1
  ; portable crosscall → Solana CPI (method + args as ix data)
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
  jlt r0, 8, sol_lbl_0
  mov64 r3, r10
  sub64 r3, 3200
  ldxdw r2, [r3+0]
  ja sol_lbl_1
sol_lbl_0:
  mov64 r2, 0
sol_lbl_1:
  mov64 r3, r10
  sub64 r3, 8
  stxdw [r3+0], r2
  mov64 r1, r3
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit

sol_call_with_args:

  ; account.validation: generated account schema
  ; account.validation[0:marker]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+0]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[0:marker]: owner=program
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
  ; account.validation[1:payer]: signer=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+8]
  add64 r7, 1
  ldxb r2, [r7+0]
  jeq r2, 0, error_signer
  ; account.validation[1:payer]: writable=true
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+8]
  add64 r7, 2
  ldxb r2, [r7+0]
  jeq r2, 0, error_not_writable
  ; account.validation[2:peer_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+16]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; account.validation[3:system_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+24]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; account.validation[4:callee_program]: owner=executable
  mov64 r7, r10
  sub64 r7, 3488
  ldxdw r7, [r7+32]
  add64 r7, 3
  ldxb r2, [r7+0]
  jeq r2, 0, error_owner
  ; portable peer handle → peer/callee account index 2 (PF-P2-03)
  mov64 r2, 2
  stxdw [r10-3280], r2
  ; portable address handle → u64 account index 1
  mov64 r2, 1
  ; portable crosscall → Solana CPI (method + args as ix data)
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r8+0], r2
  mov64 r2, 42
  mov64 r8, r10
  sub64 r8, 1184
  stxdw [r8+8], r2
  mov64 r2, 7
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
  jlt r0, 8, sol_lbl_2
  mov64 r3, r10
  sub64 r3, 3200
  ldxdw r2, [r3+0]
  ja sol_lbl_3
sol_lbl_2:
  mov64 r2, 0
sol_lbl_3:
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

error_cpi:
  mov64 r0, 8
  exit
