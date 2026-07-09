import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo Road 2 slice 1: record declaration + creation.

Aleo's ZK value proposition is private **records** (UTXO-like state with an
`owner: address`). Neither Psy nor the portable IR model records, so an
opt-in `StructDecl.isRecord` flag (mirroring `deriveStorage`) marks a struct
to lower as a Leo `record`. This smoke covers the first Road 2 slice:

- a `record Token { owner: address, amount: u64 }` declaration;
- a pure `fn mint(amount) -> Token` that CREATES a record from `self.caller`
  (verified against ProvableHQ/leo migration/transitions_to_fn).

Record CONSUME/transfer (the UTXO spend side) needs private input-record
parameters, which the portable IR does not express yet — that is a later slice. -/

namespace ProofForge.Tests.AleoLeoRecordLoweringSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

def tokenRecord : StructDecl :=
  { name := "Token"
    fields := #[{ id := "owner", type := .address }, { id := "amount", type := .u64 }]
    isRecord := true }

/-- `fn mint(amount: u64) -> Token { return Token { owner: self.caller, amount: amount }; }` -/
def mint : Entrypoint :=
  { name := "mint"
    params := #[("amount", .u64)]
    returns := .structType "Token"
    body := #[ .return (.structLit "Token"
        #[("owner", .effect (.contextRead .userId)), ("amount", .local "amount")]) ] }

def tokenModule : Module :=
  { name := "Tok", structs := #[tokenRecord], state := #[], entrypoints := #[mint] }

def recordLowersOk : Bool :=
  match renderModule tokenModule with
  | .ok _ => true
  | .error _ => false

theorem record_lowers_ok : recordLowersOk = true := by native_decide

/-- The lowered Leo source declares a record and mints it from `self.caller`. -/
def recordLeoHasMarkers : Bool :=
  match renderModule tokenModule with
  | .ok s =>
      s.contains "program tok.aleo" &&
      s.contains "record Token {" &&
      s.contains "owner: address" &&
      s.contains "amount: u64" &&
      s.contains "fn mint(amount: u64) -> Token" &&
      s.contains "Token { owner: self.caller, amount: amount }"
  | .error _ => false

theorem record_leo_has_markers : recordLeoHasMarkers = true := by native_decide

example : True := by
  have _ := @record_lowers_ok
  have _ := @record_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoRecordLoweringSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-record-lowering-smoke: record decl + mint checked"
  return 0
