/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# CosmWasm host adapter (under WasmHost family)

Counter-spike EmitWat + IR for registry target `wasm-cosmwasm`.
Lives under `WasmHost` so the Wasm family has one package tree; host
differences remain `HostBridge.cosmWasm` + this adapter (message ABI /
exports), not a sibling of Evm/Solana.
-/
import ProofForge.Backend.WasmHost.CosmWasm.EmitWat
import ProofForge.Backend.WasmHost.CosmWasm.IR
