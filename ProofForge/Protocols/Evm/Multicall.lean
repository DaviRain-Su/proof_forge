/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Layer B — EVM Multicall3 external client

CALL wrappers for a deployed Multicall3, backed by **`Evm.AbiEncode`** for
`Call[]` / `Call3[]` argument layouts (not hand-rolled offsets).

Selectors (canonical Multicall3):
- `aggregate((address,bytes)[])` → `0x252dba42`
- `tryAggregate(bool,(address,bytes)[])` → `0xbce38bd7`
- `aggregate3((address,bool,bytes)[])` → `0x82ad56cb`

## Surfaces

1. **Layout planning** (static Call arrays):
   `encodeAggregate` / `encodeAggregate3` → `AbiEncode.Plan`
2. **Yul emit** (Wave δ): `renderAggregateCallYul` / `renderAggregate3CallYul`
3. **Portable scalar remote**: `aggregate` still uses `remoteCall` with scalar
   words for multi-target handle wiring / smoke.

ABI-packed helpers remain EVM plan/Yul APIs. They are not encoded as portable
IR expressions; free-form runtime `bytes` / nested dynamic ABI remains a
target-specific future extension.
-/
import ProofForge.Contract.Source.Internal
import ProofForge.Backend.Evm.AbiEncode
import ProofForge.Backend.Evm.ToYul.AbiEncode

namespace ProofForge.Protocols.Evm.Multicall

open ProofForge.Contract.Source.Internal
open ProofForge.Backend.Evm.AbiEncode

def catalogId : String := "protocols.evm.multicall"

def selectorAggregate : Nat := 0x252dba42
def selectorTryAggregate : Nat := 0xbce38bd7
def selectorAggregate3 : Nat := 0x82ad56cb

structure Multicall where
  target : ProofForge.IR.Expr
  deriving Repr

def declareMulticall (peerId : String) : ModuleM Multicall := do
  let tIdx ← ProofForge.Contract.Builder.ensureCrosscallString peerId
  pure { target := peerHandle tIdx }

/-- Build inner call data = selector ‖ static arg words. -/
def innerCallData (selector : Nat) (argWords : Array Nat := #[]) : Array Nat :=
  callDataFromSelectorArgs selector argWords

/-- One Multicall `Call`. -/
def mkCall (target : Nat) (data : Array Nat) : Call :=
  { target := target, data := data }

/-- One Multicall3 `Call3`. -/
def mkCall3 (target : Nat) (allowFailure : Bool) (data : Array Nat) : Call3 :=
  { target := target, allowFailure := allowFailure, data := data }

/-- ABI plan for `aggregate` args (uses JsonEncode-analogue `AbiEncode`). -/
def encodeAggregate (calls : Array Call) : Plan :=
  encodeAggregateArgs calls

/-- ABI plan for `aggregate3` args. -/
def encodeAggregate3 (calls : Array Call3) : Plan :=
  encodeAggregate3Args calls

/-- Portable scalar CALL (handle wiring / smoke). Prefer `encodeAggregate` +
`renderAggregateCallYul` for real Call[] calldata. -/
def aggregate (m : Multicall) (args : Array ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall m.target (u64 selectorAggregate) args

def tryAggregate (m : Multicall) (args : Array ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall m.target (u64 selectorTryAggregate) args

def aggregate3 (m : Multicall) (args : Array ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  remoteCall m.target (u64 selectorAggregate3) args

/-- Wave δ: Plan → Yul CALL packing for `aggregate(Call[])`.
`multicallTarget` is the Multicall3 address word; `outSize` is return buffer
bytes (0 if ignored). Uses free-memory-style base `0x80`. -/
def renderAggregateCallYul (multicallTarget outSize : Nat) (calls : Array Call) : String :=
  ProofForge.Backend.Evm.ToYul.AbiEncode.renderAggregateCallYul
    ProofForge.Backend.Evm.ToYul.AbiEncode.defaultMemBase multicallTarget outSize calls

/-- Wave δ: Plan → Yul CALL packing for `aggregate3(Call3[])`. -/
def renderAggregate3CallYul (multicallTarget outSize : Nat) (calls : Array Call3) : String :=
  ProofForge.Backend.Evm.ToYul.AbiEncode.renderAggregate3CallYul
    ProofForge.Backend.Evm.ToYul.AbiEncode.defaultMemBase multicallTarget outSize calls

end ProofForge.Protocols.Evm.Multicall
