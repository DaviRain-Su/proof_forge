/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# LR-1e: non-empty hostOpHandlers package (general rule under stress)

Uses the existing EVM CREATE/CREATE2 IR pattern (not a new product example) to
prove the general export path emits used hostOpHandlers and fail-closes when
the target cannot handle them.
-/
import ProofForge.Cli.ExportCore
import ProofForge.Contract.Source.Evm
import ProofForge.Contract.Spec
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Target.HostOps.Evm

namespace ProofForge.Tests.Canonical.CoreExportHostCall

open ProofForge.Cli.ExportCore
open ProofForge.IR
open ProofForge.Target

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

private def initCodeHex := "69602a60005260206000f3600052600a6016f3"

/-- Minimal IR that normalizes to EVM create/create2 HostOps. -/
private def createModule : Module := {
  name := "EvmCreateHostOp"
  state := #[]
  entrypoints := #[
    {
      name := "deploy"
      selector? := some "01020304"
      params := #[]
      «returns» := .address
      body := #[.return (ProofForge.Contract.Source.Evm.createDeploy
        (.literal (.u128 0)) initCodeHex)]
    },
    {
      name := "deploy2"
      selector? := some "05060708"
      params := #[]
      «returns» := .address
      body := #[.return (ProofForge.Contract.Source.Evm.create2Deploy
        (.literal (.u128 0)) (.literal (.hash4 0 0 0 7)) initCodeHex)]
    }
  ]
}

def main : IO UInt32 := do
  let spec := ProofForge.Contract.ContractSpec.fromIR createModule
  let outEvm := System.FilePath.mk "build/export/lr1e-create/evm"
  let code ← exportContractSpec "evm" outEvm spec "portable-ir-fixture" "EvmCreateHostOp"
  require (code == 0) s!"CREATE export on evm failed exit={code}"

  let plan ← IO.FS.readFile (outEvm / "capability-plan.v0.json")
  require (plan.contains "\"hostOpHandlers\"") "missing hostOpHandlers"
  require (plan.contains "create") "expected create host op in handlers"
  require (plan.contains "create2" || plan.contains "create_2" || plan.contains "create2")
    "expected create2-related host op"
  -- EVM catalog is non-empty and used handlers must be subset (non-empty here).
  require (plan.contains "targetHostOpCatalog") "missing target catalog"
  require (!plan.contains "\"hostOpHandlers\": []") "used handlers must be non-empty for CREATE"

  -- Fail closed on NEAR: CREATE HostOps are EVM-owned.
  let outNear := System.FilePath.mk "build/export/lr1e-create/wasm-near"
  let nearCode ← exportContractSpec "wasm-near" outNear spec "portable-ir-fixture" "EvmCreateHostOp"
  require (nearCode != 0) "CREATE must fail-closed on wasm-near"
  require (!(← (outNear / "core.v0.json").pathExists) || nearCode != 0)
    "NEAR CREATE should not produce a successful package"

  -- Solana likewise should refuse EVM-only host ops.
  let outSol := System.FilePath.mk "build/export/lr1e-create/solana-sbpf-asm"
  let solCode ← exportContractSpec "solana-sbpf-asm" outSol spec "portable-ir-fixture" "EvmCreateHostOp"
  require (solCode != 0) "CREATE must fail-closed on solana-sbpf-asm"

  IO.println "core-export-hostcall: ok (non-empty handlers on evm; refuse on near/solana)"
  pure 0

end ProofForge.Tests.Canonical.CoreExportHostCall

def main : IO UInt32 :=
  ProofForge.Tests.Canonical.CoreExportHostCall.main
