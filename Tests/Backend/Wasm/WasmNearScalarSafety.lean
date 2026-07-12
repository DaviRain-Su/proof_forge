import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.NearAbiPlan

namespace ProofForge.Tests.WasmNearScalarSafety

open ProofForge.IR
open ProofForge.Backend.WasmHost.EmitWat
open ProofForge.Backend.WasmHost.Layout
open ProofForge.Backend.WasmHost.Memory
open ProofForge.Backend.WasmHost.ModuleAssembly
open ProofForge.Backend.WasmHost.NearAbiPlan
open ProofForge.Backend.WasmHost.Scalar

def partialWrite : Entrypoint := {
  name := "write_a"
  body := #[.effect (.storageScalarWrite "a" (.literal (.u64 7)))]
}

def twoScalarModule : Module := {
  name := "TwoScalarSafety"
  state := #[
    { id := "a", kind := .scalar, type := .u64 },
    { id := "b", kind := .scalar, type := .u64 }
  ]
  entrypoints := #[partialWrite]
}

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def testNamedCrosscallScan : IO Unit := do
  let packed := (stateLayoutPacked twoScalarModule).1
  let named := Expr.crosscallNamed "credits.aleo" "mint"
    #[.effect (.storageScalarRead "b")] .u64
  require (exprReadsPackedScalar packed named)
    "crosscallNamed arguments must participate in packed-state read analysis"

def testPackedKeyLengthMatchesDataSegment : IO Unit := do
  require (PACK_KEY_LEN == "__pf_s".length)
    "packed scalar storage-key length must match its emitted data segment"

def testPartialWriteUsesConservativeLoad : IO Unit := do
  let (packed, packSize) := stateLayoutPacked twoScalarModule
  let base := loweringCtxForModule twoScalarModule .near
  let plans ← match buildModulePlans twoScalarModule with
    | .ok plans => pure plans
    | .error msg => throw <| IO.userError msg
  let ctx := { base with packScalars := true, scalars := packed, packSize := packSize,
                         entrypointAbis := plans }
  let fn ←
    match lowerEntrypoint ctx partialWrite with
    | .ok fn => pure fn
    | .error err => throw <| IO.userError err.message
  require (fn.body.insns.any fun
      | .call name => name == packBeginName
      | _ => false)
    "a partial packed write must load the existing blob before patching it"
  require (!fn.body.insns.any fun
      | .call name => name == packBeginFreshName
      | _ => false)
    "a partial packed write must never zero the existing blob"

def testImplicitPackingDisabled : IO Unit := do
  require (!moduleScalarsPackable twoScalarModule)
    "multi-scalar modules must retain the stable per-key layout unless packing is explicitly versioned"
  let wat ←
    match renderModule twoScalarModule with
    | .ok wat => pure wat
    | .error err => throw <| IO.userError err.message
  require (!wat.contains "__pf_s")
    "unversioned modules must not switch existing state to the packed __pf_s key"

def main : IO UInt32 := do
  testNamedCrosscallScan
  testPackedKeyLengthMatchesDataSegment
  testPartialWriteUsesConservativeLoad
  testImplicitPackingDisabled
  IO.println "wasm-near-scalar-safety: ok"
  pure 0

end ProofForge.Tests.WasmNearScalarSafety

def main : IO UInt32 := ProofForge.Tests.WasmNearScalarSafety.main
