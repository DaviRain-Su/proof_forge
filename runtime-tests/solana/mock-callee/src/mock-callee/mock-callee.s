; ProofForge BL-27 mock CPI callee (zero AccountMeta).
;
; Input layout for n_accounts=0 (ABIv1 aligned):
;   [0x00] u64 num_accounts = 0
;   [0x08] u64 instruction_data_len
;   [0x10] instruction_data...
;   [0x10+len] program_id (32B)
;
; Instruction data = 8B product method disc + N×UInt64 LE args.
; Methods (arity 1, domain proof-forge-solana-v1:):
;   get(u64)    → return_data = (k+1) as u64 LE
;   record(u64) → sol_log_data key=0x5EC0 + value x (proves CPI executed)
;   unknown     → program_error 0x2001

.equ NUM_ACCOUNTS, 0x00
.equ IX_DATA_LEN, 0x08
.equ IX_DATA, 0x10

; Product discriminators as LE u64 immediates (see scripts / common helper).
.equ DISC_GET_LE, 0xb0d87cb78b1ec3d7
.equ DISC_RECORD_LE, 0xb4197762b60a5622
.equ ERR_UNKNOWN, 0x2001
.equ RECORD_KEY, 0x5ec0

.globl entrypoint
entrypoint:
  mov64 r6, r1
  ; require at least 8B disc
  ldxdw r1, [r6 + IX_DATA_LEN]
  jlt r1, 8, err_unknown
  ldxdw r2, [r6 + IX_DATA]
  lddw r3, DISC_GET_LE
  jeq r2, r3, do_get
  lddw r3, DISC_RECORD_LE
  jeq r2, r3, do_record
  ja err_unknown

do_get:
  ; need disc + 1 arg = 16B
  ldxdw r1, [r6 + IX_DATA_LEN]
  jlt r1, 16, err_unknown
  ldxdw r1, [r6 + IX_DATA + 8]
  add64 r1, 1
  stxdw [r10 - 8], r1
  mov64 r1, r10
  add64 r1, -8
  lddw r2, 8
  call sol_set_return_data
  lddw r0, 0
  exit

do_record:
  ldxdw r1, [r6 + IX_DATA_LEN]
  jlt r1, 16, err_unknown
  ; Layout for sol_log_data: keySlot, data[1], 4 descriptor u64s
  ; temps at r10-8, r10-16, ... (high address = lower temp index convention
  ; matches product emit: pack data then descriptors)
  ldxdw r1, [r6 + IX_DATA + 8]
  stxdw [r10 - 16], r1          ; data word
  lddw r1, RECORD_KEY
  stxdw [r10 - 8], r1           ; key word
  ; descriptors: keyPtr, keyLen, dataPtr, dataLen at r10-24..r10-48
  mov64 r1, r10
  add64 r1, -8
  stxdw [r10 - 24], r1          ; keyPtr
  lddw r1, 8
  stxdw [r10 - 32], r1          ; keyLen
  mov64 r1, r10
  add64 r1, -16
  stxdw [r10 - 40], r1          ; dataPtr
  lddw r1, 8
  stxdw [r10 - 48], r1          ; dataLen
  mov64 r1, r10
  add64 r1, -24
  lddw r2, 2
  call sol_log_data
  lddw r0, 0
  exit

err_unknown:
  lddw r0, ERR_UNKNOWN
  exit
