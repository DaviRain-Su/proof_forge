import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Contract.Examples.ValueVault

open ProofForge.Backend.WasmHost.EmitWat

/-! EmitWat smoke: lower the portable ValueVault contract module to WAT for the
    deterministic offline host and unified testkit. -/

def main : IO UInt32 := do
  match renderModule ProofForge.Contract.Examples.ValueVault.module with
  | .ok wat =>
    IO.FS.createDirAll "build/wasm-near"
    IO.FS.writeFile "build/wasm-near/emitwat-value-vault.wat" wat
    IO.println s!"wrote build/wasm-near/emitwat-value-vault.wat ({wat.length} bytes)"
    pure 0
  | .error e =>
    IO.eprintln s!"EmitWat failed: {e.message}"
    pure 1
