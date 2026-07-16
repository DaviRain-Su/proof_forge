import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Contract.Spec
import ProofForge.Contract.Spec.Json
import ProofForge.Contract.Client
import ProofForge.IR.Examples.ErrorRefProbe

open ProofForge.Backend.WasmHost.EmitWat

def main : IO UInt32 := do
  match renderModule ProofForge.IR.Examples.ErrorRefProbe.module with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-error-ref.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-error-ref.wat ({wat.length} bytes)"
    let spec := ProofForge.Contract.ContractSpec.fromIR ProofForge.IR.Examples.ErrorRefProbe.module
    IO.FS.writeFile "build/wasm-near/emitwat-error-ref.contract-spec.json" (ProofForge.Contract.Spec.Json.render spec ++ "\n")
    IO.println "wrote build/wasm-near/emitwat-error-ref.contract-spec.json"
    IO.FS.writeFile "build/wasm-near/proof-forge-near.ts" (ProofForge.Contract.Client.renderNearWrapper spec ++ "\n")
    IO.println "wrote build/wasm-near/proof-forge-near.ts"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
