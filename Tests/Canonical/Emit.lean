import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec
import ProofForge.Cli.Evm
import ProofForge.Cli.EvmArtifacts
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Plan
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.NearModulePlan
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Compiler.Wasm.Printer

/-! # Internal Canonical Emit Test Harness

Parses `--pipeline legacy|canonical --target <id> --fixture counter|value-vault --out <dir>`
arguments and writes test artifacts under the specified output directory.

This is an internal test tool — not exposed through the public CLI.
-/

open ProofForge.Compiler
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Resolve the fixture module to a `ContractSpec`. -/
def fixtureSpec (name : String) : IO ContractSpec :=
  match name with
  | "counter" => pure <| ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  | "value-vault" => pure <| ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module
  | other => throw <| IO.userError s!"unknown fixture: {other}"

/-- Parse `--pipeline`, `--target`, `--fixture`, `--out` from argv. -/
structure EmitArgs where
  pipeline : String
  target : String
  fixture : String
  outDir : String

def parseArgs (args : List String) : IO EmitArgs := do
  let mut pipeline := "legacy"
  let mut target := "evm"
  let mut fixture := "counter"
  let mut outDir := "build/canonical"
  let mut i := 0
  let arr := args.toArray
  while i < arr.size do
    match arr[i]! with
    | "--pipeline" => pipeline := arr[i+1]?.getD "legacy"; i := i + 2
    | "--target" => target := arr[i+1]?.getD "evm"; i := i + 2
    | "--fixture" => fixture := arr[i+1]?.getD "counter"; i := i + 2
    | "--out" => outDir := arr[i+1]?.getD "build/canonical"; i := i + 2
    | _ => i := i + 1
  pure { pipeline, target, fixture, outDir }

def main (args : List String) : IO UInt32 := do
  let parsed ← parseArgs args
  let mode := match parsed.pipeline with
    | "canonical" => CompilerPipeline.canonical
    | _ => CompilerPipeline.legacy
  let spec ← fixtureSpec parsed.fixture
  let dir := System.FilePath.mk parsed.outDir
  IO.FS.createDirAll dir
  if parsed.target == "evm" then
    let yul ← match mode with
      | .legacy =>
          match ProofForge.Cli.Evm.renderYul spec.module with
          | .ok yul => pure yul
          | .error error => throw <| IO.userError s!"legacy EVM emit failed: {error.message}"
      | .canonical =>
          match ProofForge.Cli.renderCanonicalSpecEvmYul spec with
          | .ok yul => pure yul
          | .error message => throw <| IO.userError message
    IO.FS.writeFile (dir / "contract.yul") (yul ++ "\n")
  if parsed.target == "solana-sbpf-asm" then
    let asm <- match mode with
      | .legacy =>
          match ProofForge.Backend.Solana.SbpfAsm.renderModule spec.module with
          | .ok asm => pure asm
          | .error e => throw <| IO.userError s!"legacy Solana emit failed: {e.message}"
      | .canonical => do
          let bundle <- match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
            | .ok bundle => pure bundle
            | .error e => throw <| IO.userError s!"canonical Solana adapt failed: {repr e}"
          let capPlan : ProofForge.Target.CapabilityPlan := {
            targetId := "solana-sbpf-asm", calls := bundle.contract.contract.requirements, metadata := #[]
          }
          let plan <- match ProofForge.Backend.Solana.Plan.Core.buildFromCore bundle.contract capPlan with
            | .ok plan => pure plan
            | .error e => throw <| IO.userError s!"canonical Solana plan failed: {e.message}"
          let nodes <- match ProofForge.Backend.Solana.Plan.lowerFromPlan plan with
            | .ok nodes => pure nodes
            | .error e => throw <| IO.userError s!"canonical Solana lowering failed: {e.message}"
          pure (ProofForge.Backend.Solana.Asm.renderNodes nodes)
    IO.FS.writeFile (dir / "contract.s") (asm ++ "\n")
  if parsed.target == "wasm-near" then
    let wat <- match mode with
      | .legacy =>
          match ProofForge.Backend.WasmHost.EmitWat.renderCheckedModule spec.module with
          | .ok wat => pure wat
          | .error e => throw <| IO.userError s!"legacy NEAR emit failed: {e.message}"
      | .canonical => do
          let bundle <- match ProofForge.Frontend.Authored.Normalize.normalizeContractSpec spec with
            | .ok bundle => pure bundle
            | .error e => throw <| IO.userError s!"canonical NEAR adapt failed: {repr e}"
          let capPlan : ProofForge.Target.CapabilityPlan := {
            targetId := "wasm-near", calls := bundle.contract.contract.requirements, metadata := #[]
          }
          let plan <- match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore bundle.contract capPlan with
            | .ok plan => pure plan
            | .error e => throw <| IO.userError s!"canonical NEAR plan failed: {e.message}"
          let wasm <- match ProofForge.Backend.WasmHost.NearModulePlan.lowerFromPlan plan with
            | .ok wasm => pure wasm
            | .error e => throw <| IO.userError s!"canonical NEAR lowering failed: {e.message}"
          pure (ProofForge.Compiler.Wasm.Printer.render wasm)
    IO.FS.writeFile (dir / "contract.wat") (wat ++ "\n")
  match ← compileForTest mode parsed.target spec with
  | .error diag => do
    IO.eprintln s!"compile failed: {repr diag}"
    return 1
  | .ok bundle => do
    let manifestPath := dir / "manifest.json"
    let manifest := "{\"target\":\"" ++ bundle.targetId ++ "\",\"fixture\":\"" ++ parsed.fixture ++ "\",\"pipeline\":\"" ++ parsed.pipeline ++ "\",\"outputs\":" ++ toString bundle.outputs.size ++ "}"
    IO.FS.writeFile manifestPath manifest
    IO.println s!"emit: ok (pipeline={parsed.pipeline} target={parsed.target} fixture={parsed.fixture} out={parsed.outDir})"
    return 0
