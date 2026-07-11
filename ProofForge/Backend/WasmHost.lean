/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Wasm-family host backend (`WasmHost`)

Portable IR → EmitWat → Wasm AST → WAT → `wat2wasm`, driven by
`HostBridge` (NEAR · Soroban · …).

**Not** the same as the registry target id `wasm-near` (one product chain).
This package is the Wasm-family backend tree:

| Submodule | Role |
|-----------|------|
| `WasmHost.EmitWat` | Shared IR→WAT for `HostBridge.near` / `.soroban` |
| `WasmHost.CosmWasm.*` | CosmWasm Counter-spike adapter (`HostBridge.cosmWasm`) |
| `WasmHost.NearHost` / `SorobanHost` / `CosmWasmHost` | Interpreter hosts |

Former top-level names: `Backend.WasmNear` (core), `Backend.CosmWasm` (adapter)
— both kept as deprecation re-exports.
-/
import ProofForge.Backend.WasmHost.Aggregate
import ProofForge.Backend.WasmHost.Assert
import ProofForge.Backend.WasmHost.ArrayHeap
import ProofForge.Backend.WasmHost.Capabilities
import ProofForge.Backend.WasmHost.Common
import ProofForge.Backend.WasmHost.Context
import ProofForge.Backend.WasmHost.CorePlan
import ProofForge.Backend.WasmHost.CoreLower
import ProofForge.Backend.WasmHost.Crosscall
import ProofForge.Backend.WasmHost.Diagnostics
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.Event
import ProofForge.Backend.WasmHost.ExprAnalysis
import ProofForge.Backend.WasmHost.Hash
import ProofForge.Backend.WasmHost.IR
import ProofForge.Backend.WasmHost.Imports
import ProofForge.Backend.WasmHost.Layout
import ProofForge.Backend.WasmHost.Locals
import ProofForge.Backend.WasmHost.LoweringEnv
import ProofForge.Backend.WasmHost.Map
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.ModuleAssembly
import ProofForge.Backend.WasmHost.Params
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Backend.WasmHost.Promise
import ProofForge.Backend.WasmHost.Refinement
import ProofForge.Backend.WasmHost.Return
import ProofForge.Backend.WasmHost.Scalar
import ProofForge.Backend.WasmHost.Statement
import ProofForge.Backend.WasmHost.Struct
import ProofForge.Backend.WasmHost.Types
import ProofForge.Backend.WasmHost.CosmWasm
import ProofForge.Backend.WasmHost.NearModulePlan.Core
