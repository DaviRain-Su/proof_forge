# Agent Note: Same capability layer is catalog disposition, not opcode parity

Status: implemented

## Problem

After twelve materializers exist, the tempting next sentence is “put every
target on the same level”: one Wasm host plan, one crypto lowering, or a
thirteenth TargetId so the set looks complete.

That collapses state-class hosts, circuit witnesses, and source-only
recipes into a fake portable bytecode.

## Decision

[`docs/plan/capability-layer-parity.md`](../../../../docs/plan/capability-layer-parity.md)
is the standing definition: one catalog row, per-target named admit or
named fail-closed. Tasks live in
[`docs/plan/capability-layer-tasks.md`](../../../../docs/plan/capability-layer-tasks.md).

Do not add cairo / risc0 / sp1 / Move / Bitcoin in this wave. Do not
open CosmWasm sha256 or ICP blockHeight (no host). Do not treat Soroban
axis labels as Wasm/auth/TTL. Circuit class stays fail-closed on
chain-anchored keys.

## Alternatives considered

- **One `GenericWasmHostPlan` for NEAR/CW/Soroban/ICP** — rejected:
  RPT-025 / family docs: shared encoder, never shared Plan.
- **Open every ContextRead key everywhere** — rejected: TON has no honest
  height; ICP has no height API; Solana unixTime is a product question
  (stake-weighted Clock), not a missing syscall.
- **Add a thirteenth target so the layer looks fuller** — rejected: empty
  Goal + RPT-028 say deepen honesty, not grow registry.
- **Count named FC as unfinished parity** — rejected: named FC *is* the
  layer. Unfinished means an honest host exists and is still unbound.

## Consequences

Engineering next is CAP-1a (ICP time) and the Wave-1 decisions, not a new
TargetId and not formal D2-07. Merkle / Bytes / SOR-1 remain the
sibling rejected/implemented notes.
