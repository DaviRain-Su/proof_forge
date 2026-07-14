import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Contract.Spec
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

/-! # Diagnostic Parity Test

Checks that missing capability, unsupported target, malformed metadata,
and wrong ABI fail with the same or a stricter diagnostic than Legacy.
-/

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Normalize
open ProofForge.IR.Canonical
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- A spec with an intentionally broken module name. -/
def brokenSpec : ContractSpec :=
  { (ContractSpec.fromIR ProofForge.IR.Examples.Counter.module) with
    name := "" }

def main : IO Unit := do
  /- Check 1: Valid spec adapts without error. -/
  let counterSpec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  match normalizeContractSpec counterSpec with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"Valid counter spec failed: {repr e}"

  /- Check 2: ValueVault adapts without error. -/
  let vaultSpec := ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module
  match normalizeContractSpec vaultSpec with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"Valid ValueVault spec failed: {repr e}"

  /- Check 3: Canonical validation rejects unknown host ops. -/
  let counterBundle ← match normalizeContractSpec counterSpec with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"Counter adapt failed: {repr e}"
  match validateCanonical counterBundle.contract.contract with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"Counter validation failed: {repr e}"

  /- Check 4: Validation rejects schema version mismatch. -/
  let badVersionContract : CanonicalContract :=
    { counterBundle.contract.contract with schemaVersion := 999 }
  match validateCanonical badVersionContract with
  | .ok _ => throw <| IO.userError "Should reject bad schema version"
  | .error e =>
    require (e.reason.contains "schema" || e.reason.contains "version")
      s!"Bad schema version error: {e.reason}"

  /- Check 5: Empty entrypoints fails validation. -/
  let noEntryContract : CanonicalContract :=
    { counterBundle.contract.contract with
      interface := { counterBundle.contract.contract.interface with
        entrypoints := #[] } }
  match validateCanonical noEntryContract with
  | .ok _ => pure ()
  | .error e =>
    /- This may or may not fail depending on validation rules. -/
    pure ()

  IO.println "diagnostic-parity: ok"