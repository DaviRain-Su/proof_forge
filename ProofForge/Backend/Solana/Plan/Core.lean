import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Backend.Solana.Plan
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Extension
import ProofForge.Target.Plan

/-! # Build Existing Solana Plan from Canonical Core

This module maps a `CheckedCanonicalContract` to the existing Solana
`SolanaModulePlan`. It reuses `SolanaModulePlan`, `SolanaStateFieldPlan`,
`SolanaEntrypointPlan`, and related types directly — no parallel plan types.

The Core builder must not consume `IR.Expr`, `IR.Effect`, `IR.Statement`, or
`IR.Module`. All input is typed Core ANF/CFG.
-/

namespace ProofForge.Backend.Solana.Plan.Core

open ProofForge.IR.Core
open ProofForge.IR.Canonical
open ProofForge.Target
open ProofForge.Backend.Solana.Plan
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Manifest

/-- Map a Core type to a Solana type name string. -/
def coreTypeToSolanaName : CoreType → String
  | .unit => "unit"
  | .bool => "bool"
  | .u8 => "u8"
  | .u32 => "u32"
  | .u64 => "u64"
  | .u128 => "u128"
  | .address => "address"
  | .bytes => "bytes"
  | .string => "string"
  | .hash => "hash"
  | .fixedArray _ _ => "array"
  | .array _ => "dynamicArray"
  | .memoryRef _ => "memoryRef"
  | .structType _ => "struct"

/-- Compute the byte size of a Core state shape in Solana account data.
Scalar = 8, map = capacity × 16, fixedArray = len × 8, dynamicArray = 0. -/
def coreScalarByteSize : CoreType -> Except PlanError Nat
  | .bool | .u8 => .ok 1
  | .u32 => .ok 4
  | .u64 => .ok 8
  | .u128 => .ok 16
  | .address | .hash => .ok 32
  | ty => .error { message := s!"unsupported Solana scalar type `{repr ty}`" }

def coreStateByteSize : StateShape → Except PlanError Nat
  | .scalar ty => coreScalarByteSize ty
  | .map key value (some cap) => do
      let keySize <- coreScalarByteSize key
      let valueSize <- coreScalarByteSize value
      return (1 + keySize + valueSize) * cap
  | .map _ _ none => .error { message := "Solana map state requires a finite capacity" }
  | .fixedArray elem len => do
      let elemSize <- coreScalarByteSize elem
      return elemSize * len
  | .dynamicArray _ => .error { message := "dynamic Solana state requires an explicit allocator layout" }
  | .record _ => .error { message := "Solana record state layout is not materialized" }

/-- Map a Core state kind to the Solana plan kind string. -/
def coreStateKindName : StateShape → String
  | .scalar _ => "scalar"
  | .map _ _ _ => "map"
  | .fixedArray _ _ => "array"
  | .dynamicArray _ => "dynamicArray"
  | .record _ => "struct"

/-- Compute total account data size from Core state declarations. -/
def coreModuleDataSize (m : ProofForge.IR.Core.Module) : Except PlanError Nat := do
  m.state.foldlM (fun acc decl => return acc + (<- coreStateByteSize decl.shape)) 0

/-- Build state field plans from Core state declarations.
Assigns sequential byte offsets in declaration order. -/
def coreStateFields (m : ProofForge.IR.Core.Module) (acctDataOff : Nat) : Except PlanError (Array SolanaStateFieldPlan) := do
  let mut fields := #[]
  let mut offset := 0
  for decl in m.state do
    let size <- coreStateByteSize decl.shape
    let keyByteSize ← match decl.shape with
      | .map key _ _ => coreScalarByteSize key
      | _ => pure 0
    let valueByteSize ← match decl.shape with
      | .map _ value _ => coreScalarByteSize value
      | .fixedArray element _ => coreScalarByteSize element
      | _ => pure 0
    let capacity := match decl.shape with
      | .map _ _ capacity => capacity.getD 0
      | .fixedArray _ length => length
      | _ => 0
    fields := fields.push {
      id := toString decl.id.value
      kind := coreStateKindName decl.shape
      typeName := match decl.shape with
        | .scalar ty => coreTypeToSolanaName ty
        | .map _ vty _ => coreTypeToSolanaName vty
        | .fixedArray elem _ => coreTypeToSolanaName elem
        | .dynamicArray elem => coreTypeToSolanaName elem
        | .record _ => "struct"
      byteSize := size
      absOff := acctDataOff + offset
      keyByteSize
      valueByteSize
      capacity
    }
    offset := offset + size
  return fields

/-- Build a default account plan for a Solana program.
Phase 1: single account (account 0) holding all state. -/
def coreDefaultAccounts (dataSize : Nat) : Array SolanaAccountPlan :=
  #[{ name := "program_state", index := 0, signer := false, writable := true,
      owner := "BPFLoaderUpgradeable", dataSize }]

/-- Build an empty extensions plan. -/
def coreEmptyExtensions : SolanaExtensionPlan := SolanaExtensionPlan.empty

/-- Build an empty lower context seed. The canonical builder does not
store Legacy `StructDecl`, `StateDecl`, or `Module`. The lowering for
canonical plans must reconstruct its context from the plan fields only. -/
def coreLowerCtxSeed (stateFields : Array SolanaStateFieldPlan) : SolanaLowerCtxSeed := {
  stateFieldOffsets := stateFields.map (fun f => (f.id, f.absOff))
  structs := #[]
  stateDecls := #[]
  inputLayout := { accounts := #[], instructionDataLenOff := 0, instructionDataOff := 0 }
  manifestAccounts := #[]
  extensions := {}
}

/-- Build a Solana entrypoint plan from a Core InterfaceEntrypoint.
Maps Core entrypoint params to Solana instruction-data params. -/
def coreEntrypointToPlan (ep : InterfaceEntrypoint) (tag : Nat) :
    Except PlanError SolanaEntrypointPlan := do
  /- Build instruction-data param plans. Offset starts at 1 (byte 0 = tag). -/
  let mut params := #[]
  let mut offset := 1
  for p in ep.params do
    let byteSize <- coreScalarByteSize p.type
    params := params.push {
      name := p.name
      typeName := coreTypeToSolanaName p.type
      offset
      byteSize
    }
    offset := offset + byteSize
  let discriminator <- match ep.selector? with
    | some sel =>
      if sel.length == 16 then
        match parseHexBytePairs (stripHexPrefix sel).toList with
        | some bytes => pure { tagKind := "external", bytes }
        | none => throw { message := s!"entrypoint {ep.name} has malformed external discriminator `{sel}`" }
      else
        pure { tagKind := "internal", bytes := #[tag] }
    | none => pure { tagKind := "internal", bytes := #[tag] }
  let hasReturn := match ep.retType with | .unit => false | _ => true
  return {
    name := ep.name
    discriminator
    params
    returns := coreTypeToSolanaName ep.retType
    hasReturn
    instructionDataMinLen := offset
  }

private def valuePlan (v : ValueRef) : SolanaValuePlan :=
  { id := v.id.value, typeName := coreTypeToSolanaName v.type }

private def resultPlan (instr : Instruction) : Except PlanError SolanaValuePlan :=
  match instr.results with
  | #[result] => .ok { id := result.id.value, typeName := coreTypeToSolanaName result.type }
  | _ => .error { message := "Solana value-producing operation requires exactly one result" }

private def stateField (fields : Array SolanaStateFieldPlan) (id : StateId) : Except PlanError SolanaStateFieldPlan :=
  match fields.find? (fun field => field.id == toString id.value) with
  | some field => .ok field
  | none => .error { message := s!"unknown Solana state {id.value}" }

private def arithmeticPlan : ArithmeticOp -> SolanaArithmeticPlan
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .mod => .mod
  | .and => .bitAnd | .or => .bitOr | .xor => .bitXor | .shl => .shiftLeft | .shr => .shiftRight

private def comparePlan : CompareOp -> SolanaComparePlan
  | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge

private def lowerInstructionPlan (fields : Array SolanaStateFieldPlan) (instr : Instruction) : Except PlanError SolanaOpPlan := do
  match instr.op with
  | .pure (.literal (.boolLit value)) => return .boolLiteral (<- resultPlan instr) value
  | .pure (.literal (.u8Lit value)) | .pure (.literal (.u32Lit value)) |
    .pure (.literal (.u64Lit value)) | .pure (.literal (.u128Lit value)) =>
      return .literal (<- resultPlan instr) value
  | .pure (.arithmetic op mode lhs rhs) =>
      return .arithmetic (<- resultPlan instr) (arithmeticPlan op) (mode == .checked)
        (valuePlan lhs) (valuePlan rhs)
  | .pure (.compare op lhs rhs) =>
      return .compare (<- resultPlan instr) (comparePlan op) (valuePlan lhs) (valuePlan rhs)
  | .storageLoad ref =>
      let field <- stateField fields ref.root
      match ref.path with
      | #[] => return .loadState (<- resultPlan instr) ref.root.value field.absOff field.byteSize
      | #[.mapKey key] => return .loadMap (<- resultPlan instr) ref.root.value field.absOff field.capacity field.keyByteSize field.valueByteSize (valuePlan key)
      | #[.index index] => return .loadArray (<- resultPlan instr) ref.root.value field.absOff field.capacity field.valueByteSize (valuePlan index)
      | _ => throw { message := "Solana canonical storage supports one mapKey or index segment" }
  | .storageStore ref value =>
      let field <- stateField fields ref.root
      match ref.path with
      | #[] => return .storeState ref.root.value field.absOff field.byteSize (valuePlan value)
      | #[.mapKey key] => return .storeMap ref.root.value field.absOff field.capacity field.keyByteSize field.valueByteSize (valuePlan key) (valuePlan value)
      | #[.index index] => return .storeArray ref.root.value field.absOff field.capacity field.valueByteSize (valuePlan index) (valuePlan value)
      | _ => throw { message := "Solana canonical storage supports one mapKey or index segment" }
  | .contextRead field => return .context (<- resultPlan instr) (reprStr field)
  | .emit event args => return .log event.value (args.map valuePlan)
  | .assert condition error => return .assert (valuePlan condition) error.id.value
  | op => throw { message := s!"unsupported canonical Solana operation `{repr op}`" }

private def lowerTerminatorPlan : Terminator -> SolanaTerminatorPlan
  | .jump target args _ => .jump target.value (args.map valuePlan)
  | .branch condition onTrue onFalse => .branch (valuePlan condition) onTrue.value onFalse.value
  | .return values => .return (values.map valuePlan)
  | .revert error => .revert error.id.value

private def lowerFunctionPlan (fields : Array SolanaStateFieldPlan)
    (iface : InterfaceContract) (fn : Function) : Except PlanError SolanaFunctionPlan := do
  let ep <- match iface.entrypoints.find? (fun ep => ep.functionId == fn.id) with
    | some ep => pure ep
    | none => throw { message := s!"missing Solana interface entrypoint for function {fn.id.value}" }
  let blocks <- fn.blocks.mapM fun block => do
    let ops <- block.instructions.mapM (lowerInstructionPlan fields)
    return {
      id := block.id.value
      params := block.params.map (fun p => { id := p.id.value, typeName := coreTypeToSolanaName p.type })
      ops
      terminator := lowerTerminatorPlan block.terminator
    }
  return {
    id := fn.id.value, name := ep.name
    params := fn.params.map (fun p => { id := p.id.value, typeName := coreTypeToSolanaName p.type })
    returnType := coreTypeToSolanaName fn.retType
    blocks
  }

/-- Build a Solana ModulePlan from a checked canonical contract.
This reuses the existing SolanaModulePlan structure — no parallel plan types.
The lowerCtxSeed is populated with resolved plan fields, not Legacy IR types. -/
def buildFromCore (checked : CheckedCanonicalContract)
    (capPlan : CapabilityPlan) :
    Except PlanError SolanaModulePlan := do
  if capPlan.targetId != "solana-sbpf-asm" then
    .error { message := s!"Solana buildFromCore requires target `solana-sbpf-asm`, got `{capPlan.targetId}`" }
  for requirement in checked.contract.requirements do
    unless capPlan.calls.any (fun call => call.capability == requirement.capability) do
      throw { message := s!"Solana capability plan is missing `{requirement.capability.id}`" }
  let m := checked.contract.module
  let iface := checked.contract.interface
  /- Compute account data size and layout. -/
  let dataSize <- coreModuleDataSize m
  let (acctDataOff, _) := computeSingleAccountLayout dataSize
  /- Build state field plans from Core state declarations. -/
  let stateFields <- coreStateFields m acctDataOff
  /- Build entrypoint plans from interface. -/
  let mut entrypoints := #[]
  let mut tag := 0
  for ep in iface.entrypoints do
    let epPlan ← coreEntrypointToPlan ep tag
    entrypoints := entrypoints.push epPlan
    tag := tag + 1
  /- Build accounts and extensions. -/
  let accounts := coreDefaultAccounts dataSize
  let extensions := coreEmptyExtensions
  /- Build lower context seed from resolved plan fields. -/
  let seed := coreLowerCtxSeed stateFields
  let functions <- m.functions.mapM (lowerFunctionPlan stateFields iface)
  .ok {
    targetId := "solana-sbpf-asm"
    artifactKind := "solana-elf"
    irVersion := "canonical-core-v1"
    moduleName := iface.contractName
    programId? := none
    stateDataSize := dataSize
    stateFields
    accounts
    entrypoints
    functions
    extensions
    lowerCtxSeed := seed
  }

end ProofForge.Backend.Solana.Plan.Core
