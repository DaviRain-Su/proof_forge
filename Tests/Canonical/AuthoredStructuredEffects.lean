import ProofForge.Frontend.Authored
import ProofForge.Target.HostOps.Solana

namespace ProofForge.Tests.Canonical.AuthoredStructuredEffects

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Canonicalize
open ProofForge.IR.Core

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def contract : AuthoredContract := {
  name := "StructuredEffects"
  structs := #[]
  state := #[]
  events := #[]
  errors := #[{
    name := "Denied"
    message := "operation denied"
    params := #[.u64]
  }]
  entrypoints := #[
    {
      name := "digest"
      kind := .function
      mutability := .view
      params := #[{ name := "payload", type := .bytes }]
      retType := .hash
      body := #[.returnExpr (.hostCall
        ProofForge.Target.HostOps.Solana.sha256Sig.id
        #[.local "payload"] .hash)]
    },
    {
      name := "guard"
      kind := .function
      mutability := .call
      params := #[{ name := "code", type := .u64 }]
      retType := .unit
      body := #[
        .assertError
          (.compare .eq (.local "code") (.literal (.u64Lit 0)))
          "Denied" #[.local "code"],
        .returnUnit
      ]
    }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

def badHostResultContract : AuthoredContract := {
  contract with
  name := "BadHostResult"
  entrypoints := #[{
    name := "digest"
    kind := .function
    mutability := .view
    params := #[{ name := "payload", type := .bytes }]
    retType := .u64
    body := #[.returnExpr (.hostCall
      ProofForge.Target.HostOps.Solana.sha256Sig.id
      #[.local "payload"] .u64)]
  }]
}

def badErrorArgContract : AuthoredContract := {
  contract with
  name := "BadErrorArg"
  entrypoints := #[{
    name := "guard"
    kind := .function
    mutability := .call
    params := #[]
    retType := .unit
    body := #[
      .assertError (.literal (.boolLit false)) "Denied"
        #[.literal (.stringLit "wrong")],
      .returnUnit
    ]
  }]
}

def requireNormalizationFailure (candidate : AuthoredContract) (message : String) : IO Unit :=
  match normalizeAuthored candidate with
  | .ok _ => throw <| IO.userError message
  | .error _ => pure ()

def run : IO Unit := do
  let bundle ← match normalizeAuthored contract with
    | .ok bundle => pure bundle
    | .error error => throw <| IO.userError s!"normalization failed: {repr error}"
  let mod := bundle.contract.contract.module
  let digest ← match mod.functions.find? (·.id == ⟨0⟩) with
    | some function => pure function
    | none => throw <| IO.userError "missing digest function"
  let hostCall? := digest.blocks.flatMap (·.instructions) |>.find? fun instruction =>
    match instruction.op with
    | .hostCall _ => true
    | _ => false
  match hostCall? with
  | some instruction =>
      match instruction.results, instruction.op with
      | #[result], .hostCall call =>
          require (result.type == .hash)
            "HostOp expression defaulted away from its authored hash type"
          require (call.id == ProofForge.Target.HostOps.Solana.sha256Sig.id)
            "HostOp identity changed during canonicalization"
      | _, _ => throw <| IO.userError "malformed typed HostOp instruction"
  | none => throw <| IO.userError "missing typed HostOp instruction"

  let guard ← match mod.functions.find? (·.id == ⟨1⟩) with
    | some function => pure function
    | none => throw <| IO.userError "missing guard function"
  let assertion? := guard.blocks.flatMap (·.instructions) |>.find? fun instruction =>
    match instruction.op with
    | .assert _ _ => true
    | _ => false
  match assertion? with
  | some instruction =>
      match instruction.op with
      | .assert _ error =>
          require (error.id == ⟨0⟩) "structured assertion resolved the wrong error"
          require (error.args.size == 1 && error.args[0]!.type == .u64)
            "structured assertion lost its typed runtime argument"
      | _ => throw <| IO.userError "malformed structured assertion"
  | none => throw <| IO.userError "missing structured assertion"
  requireNormalizationFailure badHostResultContract
    "HostOp result-type mismatch was accepted"
  requireNormalizationFailure badErrorArgContract
    "structured error argument-type mismatch was accepted"
  IO.println "authored-structured-effects: ok"

end ProofForge.Tests.Canonical.AuthoredStructuredEffects

def main : IO Unit :=
  ProofForge.Tests.Canonical.AuthoredStructuredEffects.run
