; PF-P2-03: minimal Solana peer — always set_return_data(u64 LE 49).
; Used by RemoteCall CPI so call_with_args observes peer return 49 (42+7).

.globl entrypoint

entrypoint:
  mov64 r1, r10
  sub64 r1, 8
  lddw r2, 49
  stxdw [r1+0], r2
  mov64 r2, 8
  call sol_set_return_data
  mov64 r0, 0
  exit
