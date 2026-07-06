import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.IR.Contract

open ProofForge.IR ProofForge.Backend.WasmNear.EmitWat

/-! Context probe: predecessor/contract id determinism (sha256 of account id),
    block_height (checkpoint), block_timestamp, epoch_height, signer (origin),
    and attached deposit (`nativeValue`). -/

def callerStable : Entrypoint := {
  name := "callerStable", returns := .u64,
  body := #[
    .assertEq (.effect (.contextRead .userId)) (.effect (.contextRead .userId)) "caller unstable",
    .return (.literal (.u64 1)) ] }

def contractStable : Entrypoint := {
  name := "contractStable", returns := .u64,
  body := #[
    .assertEq (.effect (.contextRead .contractId)) (.effect (.contextRead .contractId)) "contract id unstable",
    .return (.literal (.u64 1)) ] }

def checkpoint : Entrypoint := {
  name := "checkpoint", returns := .u64,
  body := #[.return (.effect (.contextRead .checkpointId))] }

def blockTimestamp : Entrypoint := {
  name := "blockTimestamp", returns := .u64,
  body := #[.return (.effect (.contextRead .timestamp))] }

def epochHeight : Entrypoint := {
  name := "epochHeight", returns := .u64,
  body := #[.return (.effect (.contextRead .epochHeight))] }

def randomSeed : Entrypoint := {
  name := "randomSeed", returns := .hash,
  body := #[.return (.effect (.contextRead .randomSeed))] }

def signerStable : Entrypoint := {
  name := "signerStable", returns := .u64,
  body := #[
    .assertEq (.effect (.contextRead .origin)) (.effect (.contextRead .origin)) "signer unstable",
    .return (.effect (.contextRead .origin)) ] }

def depositProbe : Entrypoint := {
  name := "depositProbe", returns := .u64,
  body := #[.return .nativeValue] }

def contextModule : Module := {
  name := "ContextProbe", state := #[],
  entrypoints := #[callerStable, contractStable, checkpoint, blockTimestamp, epochHeight, randomSeed, signerStable] }

def depositModule : Module := {
  name := "DepositProbe", state := #[],
  entrypoints := #[depositProbe] }

def writeModule (path : String) (module : Module) : IO UInt32 := do
  match renderModule module with
  | .ok wat =>
    IO.FS.writeFile path wat
    IO.println s!"wrote {path} ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed for {module.name}: {e.message}"
    pure 1

def main : IO UInt32 := do
  IO.FS.createDirAll "build/wasm-near"
  let contextCode ← writeModule "build/wasm-near/emitwat-context.wat" contextModule
  if contextCode != 0 then
    pure contextCode
  else
    writeModule "build/wasm-near/emitwat-deposit.wat" depositModule
