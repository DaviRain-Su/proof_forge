# B-CALL-SEM open sub-decision inventory (2026-08-16)

Owner-facing memo. `B-CALL-SEM` (backlog L249 area) stays **open**: resolver
support keys must not be read as "cross-platform call done". This note lists
the remaining product decisions so nobody re-derives them from chat. It does
not change any capability, spec, or formal status.

Already closed (honesty, not full alignment): Solana legacy profiles deleted
(#111); Solana sole `solana-sbpf-cpi-elf-v1` product sync active, async FC
(#125); shared N-CALL-RET value-position sync call (2026-08-04); SPEC text
split now tracked by ADR-0049 (proposed).

## Open sub-decisions

1. **EVM hashed-callee vs deployment address.** Static QN → keccak-derived
   20 bytes; empty-code `CALL` succeeds. Binding (mint authority, CREATE vs
   CREATE2 vs pre-placed, identity join to source/semantic hash) is parked on
   NetworkProfile/registry (`docs/plan/evm-call-addr-gap.md` §3; ADR-0029).
2. **EVM `schedule` spelling.** Same-tx synchronous fire-and-forget CALL with
   discarded outcome. Decide whether that may keep advertising
   `effect.asynchronous-workflow` or needs a distinct key/caveat.
3. **EVM result-bearing ABI residual.** UInt8–256 returndata open; Bool / Int
   / Bytes returndata still FC.
4. **Solana product sync residual.** Callee identity / outer account ABI
   (backlog L513 area). Async stays FC.
5. **Noir response-witness contract.** Both keys admitted as witness-binding
   relation only; result-bearing FC until a response-witness contract exists.
6. **NEAR sync scope.** Generic sync FC (Promise is async); sync key currently
   spells pf.assets deposit + `transferAsync` only. Resolver header now matches
   Phase C2 (2026-08-19 COMP-1-CALL-SEM-LAND). Inspect tag
   `near-promise+pfassets-sync-scope`.
7. **CosmWasm sync/async scope.** Generic sync FC; sync key = pf.assets bank
   only; async = same-tx SubMsg `reply_on=never` (not cross-tx);
   `contract_addr` static QN stub.
8. **TON**: sync declined (pure-async actor); async = raw out-message PARTIAL.
9. **ICP**: async advertised for inter-canister continuations while concrete
   Plan shapes may still FC; decide whether advertise-then-Plan-FC is the
   long-term spelling.
10. **Psy**: void sync PARTIAL (`InvokeExternalContractFunctionSync`, no
    deployment/response/runtime gate); async declined.
11. **Aleo / Soroban / OpenVM**: both keys declined (no static-callee Plan /
    4-key S0 / no call surface). Revisit only with their own ADRs.
12. **Quint**: sync = pf.assets vault model only; generic/async FC.
13. **Portable vs chain-native split.** ADR-0029 (proposed) is the portable
    branch candidate; accepting it does not close B-CALL-SEM.

## Decision order suggestion

(1) ADR-0049 accept (SPEC carrier honesty; blocks honest TST-SEM-002);
(2) EVM address binding + schedule spelling (items 1–2, biggest honesty
exposure on the strongest target); (3) per-target residuals as their leaves
next get touched. None of these are Goal-drain codable without an owner pick.
