import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.IR.Contract
import ProofForge.IR.Examples.HashStorageProbe

open ProofForge.IR ProofForge.Backend.WasmHost.EmitWat

/-! Hash probe: literal, scalar storage roundtrip, hash (sha256) determinism,
    hash_two_to_one determinism. Observed via assertEq (trap on mismatch) +
    U64 return 1. -/

def hState : StateDecl := { id := "h", kind := .scalar, type := .hash }

def setHash : Entrypoint := {
  name := "setHash", returns := .unit,
  body := #[.effect (.storageScalarWrite "h" (.literal (.hash4 1 2 3 4)))] }

def checkStored : Entrypoint := {
  name := "checkStored", returns := .u64,
  body := #[
    .assertEq (.effect (.storageScalarRead "h")) (.literal (.hash4 1 2 3 4)) "stored hash mismatch",
    .return (.literal (.u64 1))
  ] }

def checkDeterminism : Entrypoint := {
  name := "checkDeterminism", returns := .u64,
  body := #[
    .assertEq (.hash (.literal (.hash4 1 2 3 4))) (.hash (.literal (.hash4 1 2 3 4))) "hash not deterministic",
    .return (.literal (.u64 1))
  ] }

def checkTwoToOne : Entrypoint := {
  name := "checkTwoToOne", returns := .u64,
  body := #[
    .assertEq (.hashTwoToOne (.literal (.hash4 1 2 3 4)) (.literal (.hash4 5 6 7 8)))
              (.hashTwoToOne (.literal (.hash4 1 2 3 4)) (.literal (.hash4 5 6 7 8)))
              "hash_two_to_one not deterministic",
    .return (.literal (.u64 1))
  ] }

def hashModule : Module := {
  name := "HashProbe", state := #[hState],
  entrypoints := #[setHash, checkStored, checkDeterminism, checkTwoToOne] }

def main : IO UInt32 := do
  let render (module : Module) (path : String) : IO UInt32 := do
    match renderModule module with
    | .ok wat =>
      IO.FS.createDirAll "build/wasm-near"
      IO.FS.writeFile path wat
      IO.println s!"wrote {path} ({wat.length} bytes)"
      pure 0
    | .error e =>
      IO.eprintln s!"EmitWat failed: {e.message}"
      pure 1
  let r1 ← render hashModule "build/wasm-near/emitwat-hash.wat"
  let r2 ← render ProofForge.IR.Examples.HashStorageProbe.module "build/wasm-near/emitwat-hash-storage.wat"
  if r1 == 0 && r2 == 0 then pure 0 else pure 1
