; harness-only companion callee (issue #115 / ADR-0024 companion-v1 codecs)
; Fixed program id (test registration): 0x43 × 32
; Instruction: tag:u8 || delta:u64le
;   0x00 checked-add into 8-byte LE counter (account 0 writable)
;   0x01 attempt write then Custom(1)
;   0x02 checked-add and require account 1 is_signer (CPI authority)
;   0x03 same signer check, then write and return Custom(1)
;
; ABIv1 full marker only; original_data_len wire zeros; rent_epoch = u64::MAX.
; Virtual walk: after data use data_len+10240 then 8-align before rent_epoch.

.equ MAX_PERMITTED_DATA_INCREASE, 0x2800
.equ FULL_PREFIX, 0x58

.globl entrypoint

entrypoint:
  mov64 r6, r1

  ; Pinned runtime must clear caller return data before callee entry.
  ; Probe an 8-byte data buffer plus a 32-byte program-id buffer on stack.
  mov64 r1, r10
  sub64 r1, 72
  lddw r2, 8
  mov64 r3, r10
  sub64 r3, 32
  call sol_get_return_data
  jne r0, 0, err_stale_return

  ; num_accounts >= 1
  ldxdw r1, [r6 + 0]
  jlt r1, 1, err_shape
  mov64 r9, r1                       ; r9 = num_accounts

  ; Walk account 0 (counter)
  mov64 r7, r6
  add64 r7, 8                        ; r7 = marker0
  ldxb r1, [r7 + 0]
  jne r1, 0xff, err_shape
  ; original_data_len must be wire zeros
  ldxw r1, [r7 + 4]
  jne r1, 0, err_shape
  ; exact counter flags: non-signer, writable, non-executable
  ldxb r1, [r7 + 1]
  jne r1, 0, err_shape
  ldxb r1, [r7 + 2]
  jne r1, 1, err_shape
  ldxb r1, [r7 + 3]
  jne r1, 0, err_shape
  ; data_len must be 8
  ldxdw r1, [r7 + 80]
  jne r1, 8, err_shape
  ; counter owner is the frozen companion 0x43×32
  lddw r2, 0x4343434343434343
  ldxdw r1, [r7 + 40]
  jne r1, r2, err_shape
  ldxdw r1, [r7 + 48]
  jne r1, r2, err_shape
  ldxdw r1, [r7 + 56]
  jne r1, r2, err_shape
  ldxdw r1, [r7 + 64]
  jne r1, r2, err_shape

  ; virtual cursor after account 0 → r8 = rent0 addr
  mov64 r8, r7
  add64 r8, FULL_PREFIX              ; data start
  add64 r8, 8                        ; data_len
  add64 r8, MAX_PERMITTED_DATA_INCREASE
  ; align to 8 (data_len=8 already aligned)
  ldxdw r1, [r8 + 0]
  lddw r2, 0xffffffffffffffff
  jne r1, r2, err_shape
  add64 r8, 8                        ; r8 = after account 0

  ; Instruction data cursor depends on whether account 1 is present for tag 02.
  ; First load ix by walking remaining accounts based on num_accounts.
  mov64 r5, r8                       ; r5 = cursor after acc0
  jeq r9, 1, load_ix_one

  ; Account 1 present: walk it (authority for tag 02)
  ldxb r1, [r5 + 0]
  jne r1, 0xff, err_shape
  ldxw r1, [r5 + 4]
  jne r1, 0, err_shape
  ; exact PDA authority flags in callee: signer, readonly, non-executable
  ldxb r1, [r5 + 1]
  jne r1, 1, err_shape
  ldxb r1, [r5 + 2]
  jne r1, 0, err_shape
  ldxb r1, [r5 + 3]
  jne r1, 0, err_shape
  ldxdw r2, [r5 + 80]                ; data_len1
  jne r2, 0, err_shape
  ; PDA account owner is the current caller 0x42×32
  lddw r4, 0x4242424242424242
  ldxdw r1, [r5 + 40]
  jne r1, r4, err_shape
  ldxdw r1, [r5 + 48]
  jne r1, r4, err_shape
  ldxdw r1, [r5 + 56]
  jne r1, r4, err_shape
  ldxdw r1, [r5 + 64]
  jne r1, r4, err_shape
  mov64 r3, r5
  add64 r3, FULL_PREFIX
  add64 r3, r2
  add64 r3, MAX_PERMITTED_DATA_INCREASE
  ; align: (8 - (data_len % 8)) % 8  — data_start is 8-aligned so align(data_len)
  mov64 r1, r2
  and64 r1, 7
  jeq r1, 0, acc1_aligned
  lddw r4, 8
  sub64 r4, r1
  add64 r3, r4
acc1_aligned:
  ldxdw r1, [r3 + 0]
  lddw r2, 0xffffffffffffffff
  jne r1, r2, err_shape
  add64 r3, 8
  mov64 r5, r3                       ; cursor after acc1
  ja load_ix

load_ix_one:
load_ix:
  ; r5 = instruction_data_len addr
  ldxdw r1, [r5 + 0]
  jne r1, 9, err_shape               ; tag + u64le
  add64 r5, 8                        ; r5 = instruction data
  ldxb r1, [r5 + 0]                  ; tag
  ldxdw r2, [r5 + 1]                 ; delta

  jeq r1, 0, tag_add
  jeq r1, 1, tag_fail
  jeq r1, 2, tag_add_signer
  jeq r1, 3, tag_fail_signer
  ja err_shape

tag_add:
  jne r9, 1, err_shape
  ; checked add into counter data
  mov64 r3, r7
  add64 r3, FULL_PREFIX              ; data ptr
  ldxdw r1, [r3 + 0]
  lddw r4, 0xffffffffffffffff
  sub64 r4, r2
  jgt r1, r4, err_overflow
  add64 r1, r2
  stxdw [r3 + 0], r1
  ; Force a nonempty inner return value; the caller must clear it on success.
  lddw r1, 0x31763a72656e6e69      ; "inner:v1" little-endian
  stxdw [r10 - 72], r1
  mov64 r1, r10
  sub64 r1, 72
  lddw r2, 8
  call sol_set_return_data
  lddw r0, 0
  exit

tag_fail:
  jne r9, 1, err_shape
  ; attempt write then always fail Custom(1)
  mov64 r3, r7
  add64 r3, FULL_PREFIX
  ldxdw r1, [r3 + 0]
  lddw r4, 0xffffffffffffffff
  sub64 r4, r2
  jgt r1, r4, err_overflow
  add64 r1, r2
  stxdw [r3 + 0], r1
  ; Failure telemetry must remain observable because the caller propagates
  ; the nonzero CPI status without running its success-only clear.
  lddw r1, 0x2131763a6c696166      ; "fail:v1!" little-endian
  stxdw [r10 - 72], r1
  mov64 r1, r10
  sub64 r1, 72
  lddw r2, 8
  call sol_set_return_data
  lddw r0, 1
  exit

tag_add_signer:
  ; require exactly two CPI accounts and account1 is_signer
  jne r9, 2, err_shape
  ; account1 marker is at cursor after acc0 which we stored path... recompute
  mov64 r4, r7
  add64 r4, FULL_PREFIX
  add64 r4, 8
  add64 r4, MAX_PERMITTED_DATA_INCREASE
  add64 r4, 8                        ; after rent0 = marker1
  ldxb r1, [r4 + 1]                  ; is_signer
  jeq r1, 0, err_not_signer
  ; checked add
  mov64 r3, r7
  add64 r3, FULL_PREFIX
  ldxdw r1, [r3 + 0]
  lddw r5, 0xffffffffffffffff
  sub64 r5, r2
  jgt r1, r5, err_overflow
  add64 r1, r2
  stxdw [r3 + 0], r1
  lddw r1, 0x31763a72656e6e69      ; "inner:v1" little-endian
  stxdw [r10 - 72], r1
  mov64 r1, r10
  sub64 r1, 72
  lddw r2, 8
  call sol_set_return_data
  lddw r0, 0
  exit

tag_fail_signer:
  jne r9, 2, err_shape
  ; Recheck signer at use even though the structural parser checked flags.
  mov64 r4, r7
  add64 r4, FULL_PREFIX
  add64 r4, 8
  add64 r4, MAX_PERMITTED_DATA_INCREASE
  add64 r4, 8                        ; after rent0 = marker1
  ldxb r1, [r4 + 1]
  jeq r1, 0, err_not_signer
  mov64 r3, r7
  add64 r3, FULL_PREFIX
  ldxdw r1, [r3 + 0]
  lddw r5, 0xffffffffffffffff
  sub64 r5, r2
  jgt r1, r5, err_overflow
  add64 r1, r2
  stxdw [r3 + 0], r1
  lddw r1, 0x2131763a6c696166      ; "fail:v1!" little-endian
  stxdw [r10 - 72], r1
  mov64 r1, r10
  sub64 r1, 72
  lddw r2, 8
  call sol_set_return_data
  lddw r0, 1
  exit

err_not_signer:
  lddw r0, 1
  exit

err_overflow:
  lddw r0, 0x1001
  exit

err_stale_return:
  lddw r0, 0x1005
  exit

err_shape:
  lddw r0, 1
  exit
