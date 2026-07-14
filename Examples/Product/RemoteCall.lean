/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable cross-contract intent shared across primary targets.

Authors declare a logical peer once, then call through the bound `RemoteRef`:

  remote callee "peer.callee" "remote_call";
  return remoteCallRef callee #[];

Host account strings are deploy-time: `--peer peer.callee=alice.testnet` or
`--peers-demo`.

  --target evm · solana-sbpf-asm · wasm-near · wasm-stellar-soroban

See `just portable-remote-call-multi-target` / `just crosscall-materialize`.
-/
import ProofForge.Contract.Source.Legacy

namespace Examples.Product.RemoteCall

open ProofForge.Contract.Source.Legacy

contract_source RemoteCall do
  remote callee "peer.callee" "remote_call";

  state marker : .u64

  entry «initialize» do
    marker := u64 0;

  entry call_remote returns(.u64) do
    return ProofForge.Contract.Source.Legacy.remoteCallRef callee #[];

  entry call_with_args returns(.u64) do
    return ProofForge.Contract.Source.Legacy.remoteCallRef callee #[u64 42, u64 7];

end Examples.Product.RemoteCall
