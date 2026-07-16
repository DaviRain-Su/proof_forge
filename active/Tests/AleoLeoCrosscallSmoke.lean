import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo named-callee cross-program call (RFC 0015 Decision 4).

`crosscallNamed(programId, method, args, returnType)` addresses a callee by
compile-time program/method identifiers — the app-chain counterpart to the
runtime-address `crosscallInvoke`. Aleo lowers it to a static qualified call
`programId::method(args)` plus an `import programId;` declaration (verified
against ProvableHQ/leo data_types/external_consumer:
`import external_program.aleo; … external_program.aleo::S2`). -/

namespace ProofForge.Tests.AleoLeoCrosscallSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

/-- `import credits.aleo;
--   program caller.aleo { … fn call_mint(amount: u64) -> u64 {
--       return credits.aleo::mint(amount); } … }` -/
def callMint : Entrypoint :=
  { name := "call_mint"
    params := #[("amount", .u64)]
    returns := .u64
    body := #[ .return (.crosscallNamed "credits.aleo" "mint" #[.local "amount"] .u64) ] }

def crosscallModule : Module :=
  { name := "Caller", state := #[], entrypoints := #[callMint] }

def crosscallLowersOk : Bool :=
  match renderModule crosscallModule with
  | .ok _ => true
  | .error _ => false

theorem crosscall_lowers_ok : crosscallLowersOk = true := by native_decide

/-- The lowered Leo emits the import and the qualified cross-program call. -/
def crosscallLeoHasMarkers : Bool :=
  match renderModule crosscallModule with
  | .ok s =>
      s.contains "import credits.aleo;" &&
      s.contains "program caller.aleo" &&
      s.contains "fn call_mint(amount: u64) -> u64" &&
      s.contains "return credits.aleo::mint(amount);"
  | .error _ => false

theorem crosscall_leo_has_markers : crosscallLeoHasMarkers = true := by native_decide

example : True := by
  have _ := @crosscall_lowers_ok
  have _ := @crosscall_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoCrosscallSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-crosscall-smoke: crosscallNamed -> static qualified call + import checked"
  return 0
