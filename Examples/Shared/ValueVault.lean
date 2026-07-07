/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical portable ValueVault shared across primary targets.

Compile the same module to EVM, Solana sBPF, and NEAR/Wasm by changing only
`--target`:

  lake env proof-forge build --target evm --root . \
    -o build/portable-value-vault/ValueVault.bin \
    --yul-output build/portable-value-vault/ValueVault.yul \
    --artifact-output build/portable-value-vault/ValueVault.proof-forge-artifact.json \
    Examples/Shared/ValueVault.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/portable-value-vault/ValueVault.s \
    --artifact-output build/portable-value-vault/ValueVault.solana-artifact.json \
    Examples/Shared/ValueVault.lean

  lake env proof-forge build --target wasm-near --root . \
    -o build/portable-value-vault/near \
    --artifact-output build/portable-value-vault/ValueVault.near-artifact.json \
    Examples/Shared/ValueVault.lean

See `scripts/portable/value-vault-smoke.sh` for a checked end-to-end demo.

`ProofForge/Contract/Examples/ValueVault.lean` is a compatibility alias for
this source so tests and formal gates keep one canonical authoring surface.
-/
import ProofForge.Contract.Source

namespace Examples.Shared.ValueVault

open ProofForge.Contract.Source

contract_source ValueVault do
  state balance : .u64
  state released : .u64
  state fees : .u64
  state last_value : .u64
  state last_checkpoint : .u64
  state operations : .u64

  quint_invariant totalCoversReleased := "balance + released + fees >= released"
  quint_invariant totalCoversFees := "balance + released + fees >= fees"

  event VaultInitialized
  event ValueDeposited
  event ValueCharged
  event ValueReleased
  event ValueSnapshot

  entry «initialize» (initial : .u64) do
    let checkpoint : .u64 := checkpointId;
    balance := initial;
    released := u64 0;
    fees := u64 0;
    last_value := initial;
    last_checkpoint := checkpoint;
    operations := u64 1;
    emit VaultInitialized #[
      field initial,
      field checkpoint
    ];

  entry deposit (amount : .u64) do
    let current : .u64 := balance;
    let next : .u64 := current +! amount;
    let ops : .u64 := operations;
    let next_ops : .u64 := ops +! u64 1;
    balance := next;
    last_value := amount;
    operations := next_ops;
    emit ValueDeposited #[
      field amount,
      fieldAs balance next,
      fieldAs operations next_ops
    ];

  entry charge_fee (gross : .u64, fee_bps : .u64) do
    let fee : .u64 := (gross *! fee_bps) /! u64 10000;
    let net : .u64 := gross -! fee;
    let current : .u64 := balance;
    let next : .u64 := current +! net;
    let current_fees : .u64 := fees;
    let next_fees : .u64 := current_fees +! fee;
    let ops : .u64 := operations;
    let next_ops : .u64 := ops +! u64 1;
    balance := next;
    fees := next_fees;
    last_value := net;
    operations := next_ops;
    emit ValueCharged #[
      field gross,
      field fee,
      field net,
      fieldAs balance next
    ];

  entry release (amount : .u64) do
    let current : .u64 := balance;
    let next : .u64 := current -! amount;
    let released_before : .u64 := released;
    let released_next : .u64 := released_before +! amount;
    let ops : .u64 := operations;
    let next_ops : .u64 := ops +! u64 1;
    balance := next;
    released := released_next;
    last_value := amount;
    operations := next_ops;
    emit ValueReleased #[
      field amount,
      fieldAs balance next,
      fieldAs released released_next
    ];

  query snapshot returns(.u64) do
    let checkpoint : .u64 := checkpointId;
    let balance_now : .u64 := balance;
    let released_now : .u64 := released;
    let fees_now : .u64 := fees;
    last_checkpoint := checkpoint;
    emit ValueSnapshot #[
      fieldAs balance balance_now,
      fieldAs released released_now,
      fieldAs fees fees_now,
      field checkpoint
    ];
    return balance_now;

  query get_balance returns(.u64) do
    return balance;

  query get_net_value returns(.u64) do
    let balance_now : .u64 := balance;
    let fees_now : .u64 := fees;
    return balance_now -! fees_now;

end Examples.Shared.ValueVault
