/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# HostEnv triad probe (U1.6)

Portable product example that only reads **triad-safe** HostEnv fields:

* `timestamp` → HostEnv.blockTime (EVM · Solana Clock.unix_timestamp · NEAR)
* `checkpointId` → HostEnv.blockHeight
* `contractId` → HostEnv.selfAddress (Solana program_id digest after U1.2)
* `caller` → HostEnv.caller

Authors write business intent only; `--target` materializes each host.
Approximate / chain-only env (Solana randomness, epoch, gasLeft, chainId, …)
still honest-reject and must not appear on the Shared product path.
-/
import ProofForge.Contract.Source

namespace Examples.Product.HostEnvProbe

open ProofForge.Contract.Source

contract_source HostEnvProbe do
  state lastTime : .u64
  state lastHeight : .u64
  state lastSelf : .u64
  state lastCaller : .u64

  entry «initialize» do
    lastTime := u64 0;
    lastHeight := u64 0;
    lastSelf := u64 0;
    lastCaller := u64 0;

  -- Snapshot triad HostEnv into storage (portable materialize).
  entry snapshot do
    lastTime := timestamp;
    lastHeight := checkpointId;
    lastSelf := contractId;
    lastCaller := caller;

  query getTime returns(.u64) do
    return lastTime;

  query getHeight returns(.u64) do
    return lastHeight;

  query getSelf returns(.u64) do
    return lastSelf;

  query getCaller returns(.u64) do
    return lastCaller;

end Examples.Product.HostEnvProbe
