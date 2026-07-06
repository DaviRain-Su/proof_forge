import ProofForge.IR.Contract
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.InvExpr
import ProofForge.Backend.Quint.Scenario

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
    match s.kind with
    | .scalar =>
        if isUnsignedInt s.type then
          some {
            name := s!"{s.id}NonNegative",
            body := .binOp .ge (.local s.id) (.literalInt 0)
          }
        else
          none
    | _ => none)

def isValidQuintIdentifier (s : String) : Bool :=
  let chars := s.toList
  match chars with
  | [] => false
  | c :: rest =>
      (c.isAlpha || c == '_') && rest.all (fun c => c.isAlphanum || c == '_')

def reservedQuintNames : Array String :=
  reservedNames.toArray ++ #[
    "match", "let", "in", "rec", "enum",
    "init", "next", "temporal", "assume", "assert",
    "Set", "Map", "List", "Int", "Bool", "String",
    "MAX_UINT", "USERS"
  ]

def reservedNamesForModule (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Array String :=
  let stateNames := module.state.map (fun s => s.id)
  let actionNames := module.entrypoints.map (fun ep => sanitizeName ep.name)
  let pureDefNames := scenario.quintPureDefs.map (fun d => d.name)
  stateNames ++ actionNames ++ pureDefNames ++ reservedQuintNames ++ #["initialize", "step"]

def deriveManual (_module : ProofForge.IR.Module) (scenario : Scenario.Config) (reservedNames : Array String) : Except String (Array Val) := do
  let mut vals := #[]
  let mut seen : Array String := reservedNames
  for (name, exprStr) in scenario.invariants do
    if seen.contains name then
      .error s!"duplicate invariant name `{name}` (auto-derived or already defined in scenario)"
    if !isValidQuintIdentifier name then
      .error s!"invariant name `{name}` is not a valid Quint identifier"
    match InvExpr.parse exprStr with
    | .error e =>
        .error s!"invariant `{name}`: {e.message}"
    | .ok body =>
        seen := seen.push name
        vals := vals.push { name := name, body := body }
  .ok vals

def scenarioInvariantEntries (scenario : Scenario.Config) : Array (String × String) :=
  scenario.contractInvariants ++ scenario.invariants

/-- Derive all invariants for a module. -/
def derive (module : ProofForge.IR.Module) (scenario : Scenario.Config) : Except String (Array Val) := do
  let auto := deriveAuto module.state
  let reserved := reservedNamesForModule module scenario ++ auto.map (fun v => v.name)
  let manualScenario := { scenario with invariants := scenarioInvariantEntries scenario }
  let manual ← deriveManual module manualScenario reserved
  .ok (auto ++ manual)

end ProofForge.Backend.Quint.Invariants
