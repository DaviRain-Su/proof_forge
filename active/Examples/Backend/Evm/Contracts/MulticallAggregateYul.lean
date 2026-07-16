/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Multicall3 Call[] → full Yul object (Wave δ follow-on)

Compile-time aggregate packing: `AbiEncode.Plan` → `ToYul.AbiEncode` → Yul
`object` with `main` that mstores Call[] calldata and CALLs Multicall3.

This is the real Call[] materialize path (not scalar `remoteCall` smoke).
Portable IR still uses handle wiring for dynamic peers; fixed Call[] batches
are planned here and emitted as assembly.

```bash
just multicall-abi-yul
```
-/
import ProofForge.Backend.Evm.AbiEncode
import ProofForge.Backend.Evm.ToYul.AbiEncode
import ProofForge.Protocols.Evm.Multicall
import ProofForge.Protocols.Evm.IERC20

namespace Examples.Backend.Evm.Contracts.MulticallAggregateYul

open ProofForge.Backend.Evm.AbiEncode
open ProofForge.Backend.Evm.ToYul.AbiEncode
open ProofForge.Protocols.Evm.Multicall

/-- Demo Multicall3 address word (fixture). -/
def multicallTarget : Nat := 0xcA11bde05977b3631167028862bE2a173976CA11

/-- Inner IERC20 transfer calldata (selector only, empty args for size smoke). -/
def innerTransferData : Array Nat :=
  callDataFromSelectorArgs ProofForge.Protocols.Evm.IERC20.selectorTransfer #[]

/-- One batch: single Call to token 0xab with transfer selector bytes. -/
def demoCalls : Array Call :=
  #[mkCall 0xab innerTransferData]

/-- ABI plan for the batch. -/
def demoPlan : Plan :=
  encodeAggregate demoCalls

/-- Full Yul object source. -/
def yulSource : String :=
  renderAggregateObjectYul "MulticallAggregate" multicallTarget 0 demoCalls

/-- Expected in-size: 4 + plan.size. -/
def expectedInSize : Nat :=
  callInSize demoPlan

end Examples.Backend.Evm.Contracts.MulticallAggregateYul
