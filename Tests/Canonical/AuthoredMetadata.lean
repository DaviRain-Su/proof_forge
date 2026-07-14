import ProofForge.Frontend.Authored

namespace ProofForge.Tests.Canonical.AuthoredMetadata

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def contract : AuthoredContract := {
  name := "AuthoredMetadata"
  structs := #[{
    name := "Profile"
    fields := #[{ name := "quota", type := .u64, isPublic := false }]
    deriveStorage := true
    isPublic := false
  }]
  state := #[{ name := "profile", kind := .record "Profile" }]
  events := #[]
  errors := #[]
  entrypoints := #[{
    name := "noop"
    kind := .function
    mutability := .view
    params := #[]
    retType := .unit
    body := #[.returnUnit]
  }]
  constructorParams := #[]
  constructorBindings := #[]
  quintInvariants := #[{ name := "bounded", body := "quota <= MAX_UINT" }]
  quintLiveness := #[{ name := "progress", body := "eventually(quota > 0)" }]
  leanInvariants := #[{ name := "nonNegative", body := "Example.nonNegative" }]
}

def unsupportedOwnership : AuthoredContract := {
  contract with
  name := "UnsupportedOwnership"
  structs := #[{
    name := "Profile"
    fields := #[{ name := "quota", type := .u64, ownership := .reference }]
  }]
}

def run : IO Unit := do
  let bundle ← match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"normalization failed: {repr error}"
  let coreStruct ← match bundle.contract.contract.module.structs[0]? with
    | some declaration => pure declaration
    | none => throw <| IO.userError "missing Core struct"
  require (coreStruct.semantics == .value &&
      coreStruct.fields[0]!.ownership == FieldOwnership.value)
    "Authored struct semantics changed during Core normalization"
  let layout ← match bundle.contract.contract.materialization.typeLayouts[0]? with
    | some layout => pure layout
    | none => throw <| IO.userError "missing type layout metadata"
  require (!layout.isPublic && layout.deriveStorage && !layout.fields[0]!.isPublic)
    "struct visibility or storage metadata was defaulted away"
  let verification := bundle.evidence.verification
  require (verification.quintInvariants.map (·.name) == #["bounded"] &&
      verification.quintLiveness.map (·.name) == #["progress"] &&
      verification.leanInvariants.map (·.name) == #["nonNegative"])
    "verification annotations were not preserved as canonical evidence"
  match normalizeAuthored unsupportedOwnership with
  | .ok _ => throw <| IO.userError "reference ownership was silently treated as a value field"
  | .error _ => pure ()
  IO.println "authored-metadata: ok"

end ProofForge.Tests.Canonical.AuthoredMetadata

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredMetadata.run
