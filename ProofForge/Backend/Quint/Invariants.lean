import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model

namespace ProofForge.Backend.Quint.Invariants

open ProofForge.IR
open ProofForge.Backend.Quint

/-- Return true if the IR value type is an unsigned integer scalar. -/
def isUnsignedInt (t : ValueType) : Bool :=
  match t with
  | .u8 | .u32 | .u64 | .u128 => true
  | _ => false

/-- Auto-derive non-negativity invariants for every unsigned scalar state variable. -/
def deriveAuto (state : Array StateDecl) : Array Val :=
  state.filterMap (fun s =>
    if isUnsignedInt s.type then
      some {
        name := s!"{s.id}NonNegative",
        body := .binOp .ge (.local s.id) (.literalInt 0)
      }
    else
      none)

/-- Manual invariants for known fixtures (ValueVault v1).
    In Phase 3 v1 these are hard-coded in Lean; later they move to
    scenario config or contract_source annotations. -/
def deriveManual (module : ProofForge.IR.Module) : Array Val :=
  if module.name == "ValueVault" then
    let hasBalance := module.state.any (fun s => s.id == "balance")
    let hasReleased := module.state.any (fun s => s.id == "released")
    let hasFees := module.state.any (fun s => s.id == "fees")
    if hasBalance && hasReleased && hasFees then
      #[{
        name := "conservation",
        body := .binOp .le
          (.binOp .add (.binOp .add (.local "balance") (.local "released")) (.local "fees"))
          (.local "MAX_UINT")
      }]
    else
      #[]
  else
    #[]

/-- Derive all invariants for a module. -/
def derive (module : ProofForge.IR.Module) : Array Val :=
  deriveAuto module.state ++ deriveManual module

end ProofForge.Backend.Quint.Invariants
