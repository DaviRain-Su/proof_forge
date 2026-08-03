; harness-only multi-account CPI caller (issue #115)
; Fixed program id (test registration): 0x42 × 32
;
; Outer roles (pairwise distinct):
;   unsigned: counter, companion-program
;   signed:   counter, authorityPda, seedAuthority, companion-program
;
; Top-level instruction ABI (frozen in harness/manifest.json):
;   opcode:u8 || delta:u64le                  (len 9)  — opcodes 0/1/0x10/0x11
;   opcode:u8 || delta:u64le || seedTag:u64le || bump:u8  (len 18) — opcodes 2/3
;
; Opcodes:
;   0x00 invoke success     → companion tag 0x00, metas [counter w]
;   0x01 invoke fail        → companion tag 0x01, metas [counter w]
;   0x02 invoke_signed      → companion tag 0x02, metas [counter w, authorityPda signer-readonly]
;   0x03 invoke_signed fail → companion tag 0x03, same metas; callee writes then fails
;                            signer group: current-program-tagged-v1 (4 seeds)
;   0x10 forge writable     → CPI meta is_writable=1 while using outer flags as-is
;                            (test supplies outer counter readonly → PrivilegeEscalation)
;   0x11 forge signer       → CPI meta is_signer=1 on counter (outer non-signer → escalation)
;
; Parses Loader V3 ABIv1 with direct-mapping virtual walk (no contiguous pitch).
; Validates full marker 0xff, original_data_len==0, rent_epoch==u64::MAX,
; SIMD-0449 trailing marker pointer table. Scratch structs live on the stack.

.equ MAX_PERMITTED_DATA_INCREASE, 0x2800
.equ FULL_PREFIX, 0x58
.equ INFO_SIZE, 56
.equ META_SIZE, 16
.equ INSTRUCTION_SIZE, 40
.equ SEED_ENTRY_SIZE, 16
.equ SEEDS_GROUP_SIZE, 16

; Stack layout (negative offsets from r10). Keep 8-aligned.
; Role table: up to 16 roles × 8 u64 = 1024 bytes at [r10-1024 .. r10)
;   per role i at base = r10 - 1024 + i*64:
;     +0  marker_vm
;     +8  key_vm
;     +16 owner_vm
;     +24 lamports_vm
;     +32 data_vm
;     +40 data_len (value)
;     +48 rent_epoch (value)
;     +56 flags: signer | (writable<<8) | (executable<<16)
.equ ROLE_BASE, 1024
.equ ROLE_STRIDE, 64
.equ ROLE_MARKER, 0
.equ ROLE_KEY, 8
.equ ROLE_OWNER, 16
.equ ROLE_LAMPORTS, 24
.equ ROLE_DATA, 32
.equ ROLE_DATA_LEN, 40
.equ ROLE_RENT, 48
.equ ROLE_FLAGS, 56

; Below role table (further negative):
;   [r10-1032] num_roles
;   [r10-1040] opcode
;   [r10-1048] delta
;   [r10-1056] seed_tag
;   [r10-1064] bump (u64 lane)
;   [r10-1072] program_id_vm (current)
;   [r10-1080] ix_data_vm
;   [r10-1088] companion_key_vm  (role last key)
;   [r10-1096] signed companion tag
; Working CPI region starts at r10-1600; stale-return bytes at r10-1608.

.equ SLOT_NUM_ROLES, 1032
.equ SLOT_OPCODE, 1040
.equ SLOT_DELTA, 1048
.equ SLOT_SEED_TAG, 1056
.equ SLOT_BUMP, 1064
.equ SLOT_PROGRAM_ID, 1072
.equ SLOT_IX_DATA, 1080
.equ SLOT_COMPANION_KEY, 1088
.equ SLOT_CPI_TAG, 1096

; CPI scratch from r10-1600 upward toward role table
.equ CPI_BASE, 1600
.equ STALE_SLOT, 1608

.globl entrypoint

entrypoint:
  mov64 r6, r1                       ; input base

  ; ---------- parse num_accounts ----------
  ldxdw r1, [r6 + 0]
  jgt r1, 16, err_shape
  stxdw [r10 - SLOT_NUM_ROLES], r1
  mov64 r9, r1                       ; r9 = num roles to parse
  mov64 r8, r6
  add64 r8, 8                        ; r8 = virtual cursor (marker of role 0)
  lddw r7, 0                         ; r7 = role index
  jeq r9, 0, parse_roles_done

parse_role:
  ; bounds: need at least full prefix readable conceptually
  ldxb r1, [r8 + 0]
  jne r1, 0xff, err_shape
  ldxw r1, [r8 + 4]
  jne r1, 0, err_shape               ; original_data_len wire == 0

  ; compute role slot address → r2
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  mov64 r3, r7
  lsh64 r3, 6
  add64 r2, r3

  stxdw [r2 + ROLE_MARKER], r8
  mov64 r1, r8
  add64 r1, 8
  stxdw [r2 + ROLE_KEY], r1
  mov64 r1, r8
  add64 r1, 40
  stxdw [r2 + ROLE_OWNER], r1
  mov64 r1, r8
  add64 r1, 72
  stxdw [r2 + ROLE_LAMPORTS], r1
  mov64 r1, r8
  add64 r1, FULL_PREFIX
  stxdw [r2 + ROLE_DATA], r1

  ldxdw r1, [r8 + 80]
  stxdw [r2 + ROLE_DATA_LEN], r1
  mov64 r4, r1                       ; r4 = data_len

  ldxb r1, [r8 + 1]
  jgt r1, 1, err_shape
  ldxb r3, [r8 + 2]
  jgt r3, 1, err_shape
  lsh64 r3, 8
  or64 r1, r3
  ldxb r3, [r8 + 3]
  jgt r3, 1, err_shape
  lsh64 r3, 16
  or64 r1, r3
  stxdw [r2 + ROLE_FLAGS], r1

  ; virtual skip: data + 10240 + align8(data_len)
  mov64 r5, r8
  add64 r5, FULL_PREFIX
  add64 r5, r4
  add64 r5, MAX_PERMITTED_DATA_INCREASE
  mov64 r1, r4
  and64 r1, 7
  jeq r1, 0, role_aligned
  lddw r3, 8
  sub64 r3, r1
  add64 r5, r3
role_aligned:
  ldxdw r1, [r5 + 0]
  lddw r3, 0xffffffffffffffff
  jne r1, r3, err_shape
  stxdw [r2 + ROLE_RENT], r1
  add64 r5, 8
  mov64 r8, r5                       ; next marker / ix_len

  add64 r7, 1
  mov64 r1, r7
  ldxdw r3, [r10 - SLOT_NUM_ROLES]
  jlt r1, r3, parse_role

parse_roles_done:
  ; ---------- instruction data + program id ----------
  ldxdw r1, [r8 + 0]                 ; ix_data_len
  mov64 r2, r8
  add64 r2, 8                        ; ix_data_vm
  stxdw [r10 - SLOT_IX_DATA], r2
  jlt r1, 9, err_shape

  ldxb r3, [r2 + 0]
  stxdw [r10 - SLOT_OPCODE], r3
  ldxdw r3, [r2 + 1]
  stxdw [r10 - SLOT_DELTA], r3

  ldxdw r3, [r10 - SLOT_OPCODE]
  jeq r3, 2, expect_signed_ix
  jeq r3, 3, expect_signed_ix
  jne r1, 9, err_shape
  ja after_ix_decode

expect_signed_ix:
  jne r1, 18, err_shape
  ldxdw r3, [r2 + 9]
  stxdw [r10 - SLOT_SEED_TAG], r3
  ldxb r3, [r2 + 17]
  jeq r3, 0, err_shape              ; canonical profile search excludes bump 0
  stxdw [r10 - SLOT_BUMP], r3

after_ix_decode:
  mov64 r5, r2
  add64 r5, r1                       ; program_id_vm
  stxdw [r10 - SLOT_PROGRAM_ID], r5
  add64 r5, 32                       ; after program id

  ; Check every ABI padding byte is zero while advancing to 8 alignment.
  mov64 r1, r5
  and64 r1, 7
  jeq r1, 0, ptr_table
  lddw r3, 8
  sub64 r3, r1
check_zero_pad:
  ldxb r1, [r5 + 0]
  jne r1, 0, err_shape
  add64 r5, 1
  sub64 r3, 1
  jne r3, 0, check_zero_pad

ptr_table:
  ; SIMD-0449: u64 marker_vm for each role
  lddw r7, 0
  ldxdw r3, [r10 - SLOT_NUM_ROLES]
  jeq r3, 0, pointer_table_done
check_ptr:
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  mov64 r3, r7
  lsh64 r3, 6
  add64 r2, r3
  ldxdw r1, [r2 + ROLE_MARKER]
  ldxdw r3, [r5 + 0]
  jne r1, r3, err_shape
  add64 r5, 8
  add64 r7, 1
  ldxdw r3, [r10 - SLOT_NUM_ROLES]
  jlt r7, r3, check_ptr

pointer_table_done:
  ; CPI operations require at least one business account plus program role.
  ldxdw r1, [r10 - SLOT_NUM_ROLES]
  jlt r1, 2, err_shape
  ; companion program is last role; save its key
  sub64 r1, 1
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  lsh64 r1, 6
  add64 r2, r1
  ldxdw r1, [r2 + ROLE_KEY]
  stxdw [r10 - SLOT_COMPANION_KEY], r1
  ; Frozen companion-v1 package: exact 0x43×32 key, readonly,
  ; non-signer, executable. No QName hash or dynamic program address.
  lddw r3, 0x4343434343434343
  ldxdw r1, [r1 + 0]
  jne r1, r3, err_shape
  ldxdw r1, [r2 + ROLE_KEY]
  ldxdw r1, [r1 + 8]
  jne r1, r3, err_shape
  ldxdw r1, [r2 + ROLE_KEY]
  ldxdw r1, [r1 + 16]
  jne r1, r3, err_shape
  ldxdw r1, [r2 + ROLE_KEY]
  ldxdw r1, [r1 + 24]
  jne r1, r3, err_shape
  ldxdw r1, [r2 + ROLE_FLAGS]
  jne r1, 0x10000, err_shape

  ; ---------- opcode dispatch ----------
  ldxdw r1, [r10 - SLOT_OPCODE]
  jeq r1, 0, do_invoke_success
  jeq r1, 1, do_invoke_fail
  jeq r1, 2, do_invoke_signed_success
  jeq r1, 3, do_invoke_signed_fail
  jeq r1, 0x10, do_forge_writable
  jeq r1, 0x11, do_forge_signer
  ja err_shape

; ===== unsigned invoke paths (2 roles, 1 meta) =====
do_invoke_success:
  lddw r1, 0                         ; companion tag
  lddw r2, 0                         ; forge_writable=0
  lddw r3, 0                         ; forge_signer=0
  ja invoke_unsigned

do_invoke_fail:
  lddw r1, 1
  lddw r2, 0
  lddw r3, 0
  ja invoke_unsigned

do_forge_writable:
  lddw r1, 0
  lddw r2, 1
  lddw r3, 0
  ja invoke_unsigned

do_forge_signer:
  lddw r1, 0
  lddw r2, 0
  lddw r3, 1
  ja invoke_unsigned

; r1=companion_tag, r2=forge_w, r3=forge_s
invoke_unsigned:
  ; require exactly 2 roles
  ldxdw r4, [r10 - SLOT_NUM_ROLES]
  jne r4, 2, err_shape
  ; Normal/forge-signer paths require exact counter outer flags
  ; non-signer+writable+non-executable. The forge-writable probe alone
  ; intentionally admits exact readonly flags so the runtime can reject the
  ; attempted inner escalation.
  mov64 r4, r10
  lddw r5, ROLE_BASE
  sub64 r4, r5
  ldxdw r5, [r4 + ROLE_FLAGS]
  jeq r2, 1, unsigned_expect_readonly
  jne r5, 0x100, err_shape
  ja unsigned_flags_ok
unsigned_expect_readonly:
  jne r5, 0, err_shape
unsigned_flags_ok:

  ; --- layout CPI scratch ---
  ; [r10-CPI_BASE]     instruction data 16B
  ; +16                SolAccountMeta[1] 16B
  ; +32                SolInstruction 40B
  ; +72                SolAccountInfo[2] 112B
  mov64 r9, r10
  lddw r4, CPI_BASE
  sub64 r9, r4                       ; r9 = cpi base

  ; instruction data: zero 16B scratch first, then write tag || delta.
  ; Writing an 8-byte zero at +8 after delta would corrupt delta byte 7.
  lddw r4, 0
  stxdw [r9 + 0], r4
  stxdw [r9 + 8], r4
  stxb [r9 + 0], r1
  ldxdw r4, [r10 - SLOT_DELTA]
  stxdw [r9 + 1], r4

  ; meta[0] = counter (role 0)
  mov64 r5, r9
  add64 r5, 16                       ; metas
  mov64 r7, r10
  lddw r4, ROLE_BASE
  sub64 r7, r4                       ; role0 base
  ldxdw r4, [r7 + ROLE_KEY]
  stxdw [r5 + 0], r4
  ; is_writable
  jeq r2, 0, meta_w_from_outer
  lddw r4, 1
  ja meta_w_set
meta_w_from_outer:
  ldxdw r4, [r7 + ROLE_FLAGS]
  rsh64 r4, 8
  and64 r4, 0xff
meta_w_set:
  stxb [r5 + 8], r4
  ; is_signer
  jeq r3, 0, meta_s_from_outer
  lddw r4, 1
  ja meta_s_set
meta_s_from_outer:
  ldxdw r4, [r7 + ROLE_FLAGS]
  and64 r4, 0xff
meta_s_set:
  stxb [r5 + 9], r4
  ; zero pad meta
  lddw r4, 0
  stxb [r5 + 10], r4
  stxb [r5 + 11], r4
  stxb [r5 + 12], r4
  stxb [r5 + 13], r4
  stxb [r5 + 14], r4
  stxb [r5 + 15], r4

  ; SolInstruction
  mov64 r8, r9
  add64 r8, 32
  ldxdw r4, [r10 - SLOT_COMPANION_KEY]
  stxdw [r8 + 0], r4                 ; program_id
  stxdw [r8 + 8], r5                 ; accounts
  lddw r4, 1
  stxdw [r8 + 16], r4                ; accounts_len
  stxdw [r8 + 24], r9                ; data
  lddw r4, 9
  stxdw [r8 + 32], r4                ; data_len

  ; SolAccountInfo[2] dense role order
  mov64 r5, r9
  add64 r5, 72
  lddw r7, 0
fill_info_u:
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  mov64 r3, r7
  lsh64 r3, 6
  add64 r2, r3
  ; key
  ldxdw r4, [r2 + ROLE_KEY]
  stxdw [r5 + 0], r4
  ldxdw r4, [r2 + ROLE_LAMPORTS]
  stxdw [r5 + 8], r4
  ldxdw r4, [r2 + ROLE_DATA_LEN]
  stxdw [r5 + 16], r4
  ldxdw r4, [r2 + ROLE_DATA]
  stxdw [r5 + 24], r4
  ldxdw r4, [r2 + ROLE_OWNER]
  stxdw [r5 + 32], r4
  ldxdw r4, [r2 + ROLE_RENT]
  stxdw [r5 + 40], r4
  ldxdw r4, [r2 + ROLE_FLAGS]
  stxb [r5 + 48], r4                 ; signer
  rsh64 r4, 8
  stxb [r5 + 49], r4                 ; writable
  rsh64 r4, 8
  stxb [r5 + 50], r4                 ; executable
  lddw r4, 0
  stxb [r5 + 51], r4
  stxb [r5 + 52], r4
  stxb [r5 + 53], r4
  stxb [r5 + 54], r4
  stxb [r5 + 55], r4
  add64 r5, INFO_SIZE
  add64 r7, 1
  jlt r7, 2, fill_info_u

  ; Seed stale caller return data. The runtime must clear it before callee
  ; entry; the companion probes that boundary. Success later clears the
  ; companion's forced nonempty return value.
  lddw r1, 0x31763a656c617473      ; "stale:v1" little-endian
  stxdw [r10 - STALE_SLOT], r1
  mov64 r1, r10
  sub64 r1, STALE_SLOT
  lddw r2, 8
  call sol_set_return_data

  ; invoke_signed_c with 0 signer groups
  mov64 r1, r8
  mov64 r2, r9
  add64 r2, 72
  lddw r3, 2
  lddw r4, 0
  lddw r5, 0
  call sol_invoke_signed_c
  jne r0, 0, cpi_failed

  ; clear return data (zero length)
  lddw r1, 0
  lddw r2, 0
  call sol_set_return_data
  lddw r0, 0
  exit

; ===== signed invoke (4 roles, 2 metas, 1 signer group / 4 seeds) =====
do_invoke_signed_success:
  lddw r1, 2
  stxdw [r10 - SLOT_CPI_TAG], r1
  ja invoke_signed_common

do_invoke_signed_fail:
  lddw r1, 3
  stxdw [r10 - SLOT_CPI_TAG], r1

invoke_signed_common:
  ldxdw r4, [r10 - SLOT_NUM_ROLES]
  jne r4, 4, err_shape

  ; Exact joined outer privileges for the signed harness contract:
  ; counter writable, authority PDA readonly/non-signer, seed authority
  ; readonly/business-signer. Program role was checked above.
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  ldxdw r1, [r2 + ROLE_FLAGS]
  jne r1, 0x100, err_shape
  add64 r2, ROLE_STRIDE
  ldxdw r1, [r2 + ROLE_FLAGS]
  jne r1, 0, err_shape
  add64 r2, ROLE_STRIDE
  ldxdw r1, [r2 + ROLE_FLAGS]
  jne r1, 1, err_shape

  ; CPI layout at r9:
  ; +0    ix data 16B
  ; +16   seed0 bytes 24B ("proof-forge:pda:v1" = 18, pad)
  ; +40   seed2 seedTag u64
  ; +48   seed3 bump u8 (+pad to 8)
  ; +56   SolSignerSeed[4] 64B
  ; +120  SolSignerSeeds[1] 16B
  ; +136  SolAccountMeta[2] 32B
  ; +168  SolInstruction 40B
  ; +208  SolAccountInfo[4] 224B
  mov64 r9, r10
  lddw r4, CPI_BASE
  sub64 r9, r4

  ; companion ix data tag=2 (success) or 3 (write then fail).
  ; Zero the full scratch slot before the unaligned 8-byte delta write.
  lddw r1, 0
  stxdw [r9 + 0], r1
  stxdw [r9 + 8], r1
  ldxdw r1, [r10 - SLOT_CPI_TAG]
  stxb [r9 + 0], r1
  ldxdw r1, [r10 - SLOT_DELTA]
  stxdw [r9 + 1], r1

  ; seed0 = "proof-forge:pda:v1" (18 bytes)
  ; hex 70 72 6f 6f 66 2d 66 6f 72 67 65 3a 70 64 61 3a 76 31
  ; bytewise for clarity / correctness
  lddw r1, 0x70
  stxb [r9 + 16], r1
  lddw r1, 0x72
  stxb [r9 + 17], r1
  lddw r1, 0x6f
  stxb [r9 + 18], r1
  lddw r1, 0x6f
  stxb [r9 + 19], r1
  lddw r1, 0x66
  stxb [r9 + 20], r1
  lddw r1, 0x2d
  stxb [r9 + 21], r1
  lddw r1, 0x66
  stxb [r9 + 22], r1
  lddw r1, 0x6f
  stxb [r9 + 23], r1
  lddw r1, 0x72
  stxb [r9 + 24], r1
  lddw r1, 0x67
  stxb [r9 + 25], r1
  lddw r1, 0x65
  stxb [r9 + 26], r1
  lddw r1, 0x3a
  stxb [r9 + 27], r1
  lddw r1, 0x70
  stxb [r9 + 28], r1
  lddw r1, 0x64
  stxb [r9 + 29], r1
  lddw r1, 0x61
  stxb [r9 + 30], r1
  lddw r1, 0x3a
  stxb [r9 + 31], r1
  lddw r1, 0x76
  stxb [r9 + 32], r1
  lddw r1, 0x31
  stxb [r9 + 33], r1

  ; seed2 = seedTag u64le
  ldxdw r1, [r10 - SLOT_SEED_TAG]
  stxdw [r9 + 40], r1
  ; seed3 = bump
  ldxdw r1, [r10 - SLOT_BUMP]
  stxb [r9 + 48], r1

  ; SolSignerSeed[4]
  mov64 r5, r9
  add64 r5, 56
  ; seed0
  mov64 r1, r9
  add64 r1, 16
  stxdw [r5 + 0], r1
  lddw r1, 18
  stxdw [r5 + 8], r1
  ; seed1 = seedAuthority key (role 2)
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  lddw r3, 128                       ; role 2 * 64
  add64 r2, r3
  ldxdw r1, [r2 + ROLE_KEY]
  stxdw [r5 + 16], r1
  lddw r1, 32
  stxdw [r5 + 24], r1
  ; seed2
  mov64 r1, r9
  add64 r1, 40
  stxdw [r5 + 32], r1
  lddw r1, 8
  stxdw [r5 + 40], r1
  ; seed3
  mov64 r1, r9
  add64 r1, 48
  stxdw [r5 + 48], r1
  lddw r1, 1
  stxdw [r5 + 56], r1

  ; Independently derive the canonical PDA and bump from the first 3 seeds.
  ; Output address lives at +440 (32B), output bump at +472 (1B).
  mov64 r1, r5                       ; SolSignerSeed[0..3)
  lddw r2, 3
  ldxdw r3, [r10 - SLOT_PROGRAM_ID]
  mov64 r4, r9
  add64 r4, 440
  mov64 r5, r9
  add64 r5, 472
  call sol_try_find_program_address
  jne r0, 0, err_shape
  ; supplied bump must equal the pinned runtime's canonical 255..1 result
  ldxb r1, [r9 + 472]
  ldxdw r2, [r10 - SLOT_BUMP]
  jne r1, r2, err_shape
  ; passed authorityPda role key must equal the canonical address
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  add64 r2, ROLE_STRIDE
  ldxdw r2, [r2 + ROLE_KEY]
  lddw r3, 0
canonical_key_word:
  mov64 r4, r9
  add64 r4, 440
  add64 r4, r3
  ldxdw r1, [r4 + 0]
  mov64 r5, r2
  add64 r5, r3
  ldxdw r5, [r5 + 0]
  jne r1, r5, err_shape
  add64 r3, 8
  jlt r3, 32, canonical_key_word

  ; SolSignerSeeds[1]
  mov64 r5, r9
  add64 r5, 56
  mov64 r4, r9
  add64 r4, 120
  stxdw [r4 + 0], r5
  lddw r1, 4
  stxdw [r4 + 8], r1

  ; metas: counter writable, authorityPda signer-readonly
  mov64 r5, r9
  add64 r5, 136
  ; meta0 counter role0
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  ldxdw r1, [r2 + ROLE_KEY]
  stxdw [r5 + 0], r1
  lddw r1, 1
  stxb [r5 + 8], r1                  ; writable
  lddw r1, 0
  stxb [r5 + 9], r1                  ; signer false (outer)
  stxb [r5 + 10], r1
  stxb [r5 + 11], r1
  stxb [r5 + 12], r1
  stxb [r5 + 13], r1
  stxb [r5 + 14], r1
  stxb [r5 + 15], r1
  ; meta1 authorityPda role1 — PDA signer, readonly
  add64 r5, 16
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  lddw r3, 64
  add64 r2, r3
  ldxdw r1, [r2 + ROLE_KEY]
  stxdw [r5 + 0], r1
  lddw r1, 0
  stxb [r5 + 8], r1                  ; readonly
  lddw r1, 1
  stxb [r5 + 9], r1                  ; signer via seeds
  lddw r1, 0
  stxb [r5 + 10], r1
  stxb [r5 + 11], r1
  stxb [r5 + 12], r1
  stxb [r5 + 13], r1
  stxb [r5 + 14], r1
  stxb [r5 + 15], r1

  ; SolInstruction
  mov64 r8, r9
  add64 r8, 168
  ldxdw r1, [r10 - SLOT_COMPANION_KEY]
  stxdw [r8 + 0], r1
  mov64 r1, r9
  add64 r1, 136
  stxdw [r8 + 8], r1
  lddw r1, 2
  stxdw [r8 + 16], r1
  stxdw [r8 + 24], r9
  lddw r1, 9
  stxdw [r8 + 32], r1

  ; SolAccountInfo[4]
  mov64 r5, r9
  add64 r5, 208
  lddw r7, 0
fill_info_s:
  mov64 r2, r10
  lddw r3, ROLE_BASE
  sub64 r2, r3
  mov64 r3, r7
  lsh64 r3, 6
  add64 r2, r3
  ldxdw r4, [r2 + ROLE_KEY]
  stxdw [r5 + 0], r4
  ldxdw r4, [r2 + ROLE_LAMPORTS]
  stxdw [r5 + 8], r4
  ldxdw r4, [r2 + ROLE_DATA_LEN]
  stxdw [r5 + 16], r4
  ldxdw r4, [r2 + ROLE_DATA]
  stxdw [r5 + 24], r4
  ldxdw r4, [r2 + ROLE_OWNER]
  stxdw [r5 + 32], r4
  ldxdw r4, [r2 + ROLE_RENT]
  stxdw [r5 + 40], r4
  ldxdw r4, [r2 + ROLE_FLAGS]
  stxb [r5 + 48], r4
  rsh64 r4, 8
  stxb [r5 + 49], r4
  rsh64 r4, 8
  stxb [r5 + 50], r4
  lddw r4, 0
  stxb [r5 + 51], r4
  stxb [r5 + 52], r4
  stxb [r5 + 53], r4
  stxb [r5 + 54], r4
  stxb [r5 + 55], r4
  add64 r5, INFO_SIZE
  add64 r7, 1
  jlt r7, 4, fill_info_s

  ; Same stale-return probe as unsigned invocation.
  lddw r1, 0x31763a656c617473      ; "stale:v1" little-endian
  stxdw [r10 - STALE_SLOT], r1
  mov64 r1, r10
  sub64 r1, STALE_SLOT
  lddw r2, 8
  call sol_set_return_data

  mov64 r1, r8
  mov64 r2, r9
  add64 r2, 208
  lddw r3, 4
  mov64 r4, r9
  add64 r4, 120                      ; signer groups
  lddw r5, 1
  call sol_invoke_signed_c
  jne r0, 0, cpi_failed

  lddw r1, 0
  lddw r2, 0
  call sol_set_return_data
  lddw r0, 0
  exit

cpi_failed:
  ; propagate syscall status; do not clear return data / continue
  exit

err_shape:
  lddw r0, 1
  exit
