/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana Semantic Plan (SolanaModulePlan)

Phase 0 MVP of the Solana `*ModulePlan` artifact described in RFC 0014.

The plan captures every semantic decision that the sBPF assembly lowering
currently makes implicitly inside `LowerCtx` / `buildModuleInputSchema` /
`lowerEntrypoint`. For the Counter/scalar-state MVP it includes:

- module identity and target metadata
- serialized account-data state layout
- instruction account schema (signer/writable/owner)
- entrypoint dispatch table and instruction-data ABI
- declared CPI / syscall extensions (empty for Counter)

The plan is target-specific (it knows about Solana accounts, discriminators,
and instruction data) but it is still an abstract artifact: it does not
contain assembly instructions or register assignments. That makes it the
semantic boundary between `validate` and `lowerToAst`.

See `docs/solana-module-plan-design.md` for the full design.
-/

import ProofForge.IR.Contract
import ProofForge.Target.Plan
import ProofForge.Backend.Diagnostic
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.PortableCrosscall

namespace ProofForge.Backend.Solana.Plan

open ProofForge.IR
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.SbpfAsm
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Register
open ProofForge.Backend.Solana.Syscalls

-- ============================================================================
-- Plan types
-- ============================================================================

/-- One serialized state field inside account 0 data. -/
structure SolanaStateFieldPlan where
  id : String
  kind : String
  typeName : String
  byteSize : Nat
  absOff : Nat
  keyByteSize : Nat := 0
  valueByteSize : Nat := 0
  capacity : Nat := 0
  deriving Repr, Inhabited, BEq

/-- One account in the instruction account meta list. -/
structure SolanaAccountPlan where
  name : String
  index : Nat
  signer : Bool
  writable : Bool
  owner : String
  dataSize : Nat
  deriving Repr, Inhabited, BEq

/-- One scalar instruction parameter in the Solana instruction-data ABI. -/
structure SolanaInstructionParamPlan where
  name : String
  typeName : String
  offset : Nat
  byteSize : Nat
  deriving Repr, Inhabited, BEq

/-- Dispatch tag for an entrypoint. Internal entrypoints use a single-byte
index; external entrypoints use an 8-byte Anchor/solita discriminator. -/
structure SolanaEntrypointDiscriminatorPlan where
  tagKind : String -- "internal" | "external"
  bytes : Array Nat
  deriving Repr, Inhabited, BEq

/-- One callable entrypoint in the Solana program. -/
structure SolanaEntrypointPlan where
  name : String
  discriminator : SolanaEntrypointDiscriminatorPlan
  params : Array SolanaInstructionParamPlan
  returns : String
  hasReturn : Bool
  instructionDataMinLen : Nat
  deriving Repr, Inhabited, BEq

/-- Target-semantic value reference. IDs remain logical SSA identities; the
register/stack assignment is owned by `lowerFromPlan`. -/
structure SolanaValuePlan where
  id : Nat
  typeName : String
  deriving Repr, Inhabited, BEq

inductive SolanaArithmeticPlan where
  | add | sub | mul | div | mod | bitAnd | bitOr | bitXor | shiftLeft | shiftRight
  deriving Repr, Inhabited, BEq

inductive SolanaComparePlan where
  | eq | ne | lt | le | gt | ge
  deriving Repr, Inhabited, BEq

/-- Semantic operations accepted by the canonical sBPF backend. No assembly
nodes or Legacy IR declarations are stored here. -/
inductive SolanaOpPlan where
  | literal (result : SolanaValuePlan) (value : Nat)
  | boolLiteral (result : SolanaValuePlan) (value : Bool)
  | copy (result value : SolanaValuePlan)
  | loadState (result : SolanaValuePlan) (stateId : Nat) (absOff byteSize : Nat)
  | storeState (stateId : Nat) (absOff byteSize : Nat) (value : SolanaValuePlan)
  | loadMap (result : SolanaValuePlan) (stateId : Nat) (absOff capacity keyByteSize valueByteSize : Nat)
      (key : SolanaValuePlan)
  | storeMap (stateId : Nat) (absOff capacity keyByteSize valueByteSize : Nat)
      (key value : SolanaValuePlan)
  | loadArray (result : SolanaValuePlan) (stateId : Nat) (absOff capacity elementByteSize : Nat)
      (index : SolanaValuePlan)
  | storeArray (stateId : Nat) (absOff capacity elementByteSize : Nat)
      (index value : SolanaValuePlan)
  | arithmetic (result : SolanaValuePlan) (op : SolanaArithmeticPlan)
      (checked : Bool) (lhs rhs : SolanaValuePlan)
  | compare (result : SolanaValuePlan) (op : SolanaComparePlan)
      (lhs rhs : SolanaValuePlan)
  | context (result : SolanaValuePlan) (field : String)
  | log (eventId : Nat) (eventName : String) (args : Array SolanaValuePlan)
  | assert (condition : SolanaValuePlan) (errorCode : Nat)
  | portableCrosscall (result : SolanaValuePlan) (calleeAccountIndex : Nat)
      (method : SolanaValuePlan) (args : Array SolanaValuePlan)
  deriving Repr, Inhabited, BEq

inductive SolanaTerminatorPlan where
  | jump (target : Nat) (args : Array SolanaValuePlan)
  | branch (condition : SolanaValuePlan) (ifTrue ifFalse : Nat)
  | return (values : Array SolanaValuePlan)
  | revert (errorCode : Nat)
  deriving Repr, Inhabited, BEq

structure SolanaBlockPlan where
  id : Nat
  params : Array SolanaValuePlan
  ops : Array SolanaOpPlan
  terminator : SolanaTerminatorPlan
  deriving Repr, Inhabited, BEq

structure SolanaFunctionPlan where
  id : Nat
  name : String
  params : Array SolanaValuePlan
  returnType : String
  blocks : Array SolanaBlockPlan
  deriving Repr, Inhabited, BEq

/-- Declared extensions (CPI invokes, syscalls, memory ops, PDAs). Counter has
none. -/
structure SolanaExtensionPlan where
  cpis : Array String
  syscalls : Array String
  memoryOps : Array String
  pdas : Array String
  deriving Repr, Inhabited, BEq

def SolanaExtensionPlan.empty : SolanaExtensionPlan :=
  { cpis := #[], syscalls := #[], memoryOps := #[], pdas := #[] }

/-- The lowering-seed fields the assembly backend needs to reconstruct
`LowerCtx` and the account-validation prologue without re-deriving them from
the IR module. These are intentionally kept separate from the human-readable
plan fields above because they are large structural objects, but they are
part of the frozen plan so the lowering is a pure function of the plan. -/
structure SolanaLowerCtxSeed where
  stateFieldOffsets : Array (String × Nat)
  structs : Array StructDecl
  stateDecls : Array StateDecl
  inputLayout : InputLayout
  manifestAccounts : Array AccountEntry
  extensions : ProgramExtensions
  deriving Inhabited

/-- The semantic plan artifact for a Solana sBPF program. -/
structure SolanaModulePlan where
  targetId : String
  artifactKind : String
  irVersion : String
  moduleName : String
  programId? : Option String
  stateDataSize : Nat
  stateFields : Array SolanaStateFieldPlan
  accounts : Array SolanaAccountPlan
  entrypoints : Array SolanaEntrypointPlan
  functions : Array SolanaFunctionPlan := #[]
  extensions : SolanaExtensionPlan
  lowerCtxSeed : SolanaLowerCtxSeed
  deriving Inhabited

-- ============================================================================
-- Error type
-- ============================================================================

structure PlanError where
  message : String
  deriving Repr, Inhabited

def PlanError.render (err : PlanError) : String := err.message

/-! ## Shared diagnostic contract adapter (RFC 0014 Phase 3)

Trivial `LoweringError` instance: projects `PlanError` into the shared
`LoweringDiagnostic` shape, tagging `backend? := "solana-sbpf-asm"`. The class
default `render` delegates to `LoweringDiagnostic.render`, which outputs only
`message`, so this is byte-identical to `PlanError.render` above. Purely
additive metadata; no existing call site or golden diagnostic is affected. -/
instance : ProofForge.Backend.Diagnostic.LoweringError PlanError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "solana-sbpf-asm" }

-- ============================================================================
-- Building the plan from an IR module
-- ============================================================================

def valueTypeName (ty : ValueType) : String := ty.name

def stateKindName (kind : StateKind) : String :=
  match kind with
  | .scalar => "scalar"
  | .map _ _ => "map"
  | .array _ => "array"
  | .dynamicArray => "dynamicArray"

def buildStateFieldPlan (module : Module) (acctDataOff : Nat) : Array SolanaStateFieldPlan :=
  buildStateOffsetsAtBase module acctDataOff |>.map fun field =>
    match module.state.find? (fun s => s.id == field.id) with
    | none => { id := field.id, kind := "unknown", typeName := "unknown", byteSize := 0, absOff := field.absOff }
    | some decl =>
        { id := decl.id
          kind := stateKindName decl.kind
          typeName := valueTypeName decl.type
          byteSize := stateDeclSize decl
          absOff := field.absOff }

def buildAccountPlan (_module : Module) (_extensions : ProgramExtensions)
    (accounts : Array AccountEntry) (specs : Array (Nat × Bool)) : Array SolanaAccountPlan :=
  accounts.mapIdx fun idx account =>
    let (dataSize, _) := specs[idx]?.getD (0, false)
    { name := account.name
      index := account.index
      signer := account.signer
      writable := account.writable
      owner := account.owner
      dataSize := dataSize }

def scalarParamPlan? (_epName : String) (name : String) (ty : ValueType) (offset : Nat) :
    Except PlanError (Option (SolanaInstructionParamPlan × Nat)) :=
  match scalarParamSize? ty with
  | none => .ok none
  | some byteSize =>
    let typeName := valueTypeName ty
    .ok (some ({ name, typeName, offset, byteSize }, offset + byteSize))

def buildEntrypointParamPlans (ep : Entrypoint) :
    Except PlanError (Array SolanaInstructionParamPlan) := do
  let mut params := #[]
  let mut offset := entrypointDiscriminatorSize ep
  for (name, ty) in ep.params do
    match ← scalarParamPlan? ep.name name ty offset with
    | none =>
      -- Non-scalar parameters are not supported in Phase 1. We still record
      -- them with byteSize 0 so the plan reflects the unsupported shape.
      params := params.push { name, typeName := valueTypeName ty, offset, byteSize := 0 }
    | some (plan, nextOffset) =>
      params := params.push plan
      offset := nextOffset
  return params

def externalDiscriminatorPlan (ep : Entrypoint) (internalTag : Nat) :
    SolanaEntrypointDiscriminatorPlan :=
  match externalDiscriminatorBytes? ep with
  | none => { tagKind := "internal", bytes := #[internalTag] }
  | some bytes => { tagKind := "external", bytes }

def buildEntrypointPlan (ep : Entrypoint) (internalTag : Nat) : Except PlanError SolanaEntrypointPlan := do
  let params ← buildEntrypointParamPlans ep
  return {
    name := ep.name
    discriminator := externalDiscriminatorPlan ep internalTag
    params := params
    returns := valueTypeName ep.returns
    hasReturn := entrypointHasReturn ep
    instructionDataMinLen := instructionDataMinLen ep
  }

def buildExtensionPlan (extensions : ProgramExtensions) : SolanaExtensionPlan :=
  { cpis := extensions.cpis.map (fun c => c.name)
    syscalls := #[]
    memoryOps := extensions.memoryActions.map (fun m => m.op.id)
    pdas := extensions.pdas.map (fun p => p.name) }

/-- Build a `SolanaModulePlan` from an IR module and an optional capability plan.
This is the Tier B semantic boundary: all later lowering stages should be able
to reconstruct their contexts from this plan. -/
def buildSolanaModulePlan (module : Module) (capPlan? : Option ProofForge.Target.CapabilityPlan := none) :
    Except PlanError SolanaModulePlan := do
  let extensions := match capPlan? with | some p => ProgramExtensions.fromPlan p | none => {}
  let instructions := buildInstructionsWithExtensions module extensions
  let accounts :=
    match instructions[0]? with
    | some instruction => instruction.accounts
    | none => buildDefaultAccounts module
  let specs := accountInputSpecs module extensions accounts
  let inputLayout := computeInputLayoutWithReallocFlags specs
  let stateDataOff :=
    if module.state.isEmpty then 0
    else
      match stateAccountIndex? module accounts with
      | some idx =>
          match inputLayout.accounts[idx]? with
          | some layout => layout.dataStart
          | none => 0
      | none =>
          match inputLayout.accounts[0]? with
          | some layout => layout.dataStart
          | none => 0
  let stateFields := buildStateFieldPlan module stateDataOff
  let mut tag := 0
  let mut entrypointPlans := #[]
  for ep in module.entrypoints do
    entrypointPlans := entrypointPlans.push (← buildEntrypointPlan ep tag)
    tag := tag + 1
  let stateFieldOffsets := buildStateOffsetsAtBase module stateDataOff
                     |>.map (fun f => (f.id, f.absOff))
  let lowerCtxSeed := {
    stateFieldOffsets
    structs := module.structs
    stateDecls := module.state
    inputLayout
    manifestAccounts := accounts
    extensions
  }
  return {
    targetId := "solana-sbpf-asm"
    artifactKind := "solana-elf"
    irVersion := "portable-ir-v0"
    moduleName := module.name
    programId? := none
    stateDataSize := moduleDataSize module
    stateFields := stateFields
    accounts := buildAccountPlan module extensions accounts specs
    entrypoints := entrypointPlans
    extensions := buildExtensionPlan extensions
    lowerCtxSeed
  }

-- ============================================================================
-- Stable text rendering for golden testing
-- ============================================================================

def renderNat (n : Nat) : String := toString n
def renderBool (b : Bool) : String := if b then "true" else "false"

def indent (n : Nat) (s : String) : String :=
  String.ofList (List.replicate n ' ') ++ s

def joinLines (lines : List String) : String :=
  String.intercalate "\n" lines

def renderBytes (bytes : Array Nat) : String :=
  "[" ++ String.intercalate ", " (bytes.toList.map renderNat) ++ "]"

def renderStrings (ss : Array String) : String :=
  "[" ++ String.intercalate ", " (ss.toList.map (fun s => "\"" ++ s ++ "\"")) ++ "]"

def renderStateField (f : SolanaStateFieldPlan) : String :=
  s!"  {f.id}: kind={f.kind} type={f.typeName} byteSize={renderNat f.byteSize} absOff={renderNat f.absOff}"

def renderAccount (a : SolanaAccountPlan) : String :=
  s!"  {a.name}: index={renderNat a.index} signer={renderBool a.signer} writable={renderBool a.writable} owner=\"{a.owner}\" dataSize={renderNat a.dataSize}"

def renderParam (p : SolanaInstructionParamPlan) : String :=
  s!"    {p.name}: type={p.typeName} offset={renderNat p.offset} byteSize={renderNat p.byteSize}"

def renderDiscriminator (d : SolanaEntrypointDiscriminatorPlan) : String :=
  s!"  discriminator: kind={d.tagKind} bytes={renderBytes d.bytes}"

def renderEntrypoint (ep : SolanaEntrypointPlan) : String :=
  let header := s!"{ep.name}: returns={ep.returns} hasReturn={renderBool ep.hasReturn} instructionDataMinLen={renderNat ep.instructionDataMinLen}"
  let disc := renderDiscriminator ep.discriminator
  let params := if ep.params.isEmpty then #["  params: []"] else #["  params:"] ++ ep.params.map renderParam
  String.intercalate "\n" ([header, disc] ++ params.toList)

def renderExtensionPlan (ext : SolanaExtensionPlan) : String :=
  String.intercalate "\n" [
    s!"cpis: {renderStrings ext.cpis}",
    s!"syscalls: {renderStrings ext.syscalls}",
    s!"memoryOps: {renderStrings ext.memoryOps}",
    s!"pdas: {renderStrings ext.pdas}"
  ]

/-- Render the plan as a stable, diff-friendly text artifact. The format is
intentionally simple (not JSON) so that small plan changes produce readable
golden diffs. -/
def SolanaModulePlan.render (plan : SolanaModulePlan) : String :=
  let lines := #[
    s!"targetId: {plan.targetId}",
    s!"artifactKind: {plan.artifactKind}",
    s!"irVersion: {plan.irVersion}",
    s!"moduleName: {plan.moduleName}",
    s!"programId: {match plan.programId? with | some id => id | none => "(none)"}",
    s!"stateDataSize: {renderNat plan.stateDataSize}",
    "stateFields:",
    plan.stateFields.map renderStateField
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "accounts:",
    plan.accounts.map renderAccount
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n" ++ s) "",
    "entrypoints:",
    plan.entrypoints.map renderEntrypoint
      |>.foldl (fun acc s => acc ++ if acc.isEmpty then s else "\n\n" ++ s) "",
    "extensions:",
    renderExtensionPlan plan.extensions
  ]
  String.intercalate "\n" (lines.toList.filter (!·.isEmpty))

-- ============================================================================
-- Plan-driven lowering (Tier B contract)
-- ============================================================================

/-- Build a `LowerCtx` from the plan's lowering seed, without re-deriving state
offsets or account layout from the IR module. Delegates to
`SbpfAsm.LowerCtx.fromPlanSeed` (the `LowerCtx` owner) so the plan path and the
`SbpfAsm.lowerModuleCore` lowering entry share one reconstruction path and
cannot drift. The lowering-local mutable fields (`locals`, `nextLocalOffset`,
`scratchOffset`, `nextLabel`, `allocator`) are initialised to their entry
defaults inside `LowerCtx.fromPlanSeed`. -/
def LowerCtx.fromSeed (module : IR.Module) (seed : SolanaLowerCtxSeed) :
    Except SbpfAsm.LowerError SbpfAsm.LowerCtx := do
  let accountBindings :=
    SbpfAsm.buildCpiAccountBindings seed.manifestAccounts seed.inputLayout.accounts
  let stateDataOff ←
    match SbpfAsm.stateDataStartFromSchema module
        { accounts := seed.manifestAccounts, inputLayout := seed.inputLayout } with
    | .ok off => pure off
    | .error e => throw e
  let valueBindings := SbpfAsm.buildCpiValueBindings module stateDataOff
  let cpiIndices :=
    ProofForge.Backend.Solana.PortableCrosscall.selectPortableCpiAccountIndices
      seed.manifestAccounts
  pure <|
    SbpfAsm.LowerCtx.fromPlanSeed
      seed.stateFieldOffsets seed.structs seed.stateDecls seed.manifestAccounts.size
      accountBindings valueBindings #[] cpiIndices

/-- Lower a module using a pre-built `SolanaModulePlan`. This is the Tier B
contract entry point: the lowering is a pure function of the plan (plus the IR
module's statement bodies). The reconstructed `LowerCtx` is handed to the
shared `SbpfAsm.lowerModuleCoreWithSeed` body — the exact same body
`SbpfAsm.lowerModuleCore` uses (Step C made it the only path) — so the
plan-driven output is identical to the lowering entry's output. The
capability check is re-run here because it is a read-only validation gate, not
a lowering decision. -/
def lowerModuleFromPlan (module : IR.Module) (plan : SolanaModulePlan) :
    Except SbpfAsm.LowerError (Array AstNode) := do
  SbpfAsm.validateCapabilities module
  let seed := plan.lowerCtxSeed
  let ctx ← LowerCtx.fromSeed module seed
  let core ← SbpfAsm.lowerModuleCoreWithSeed module seed.manifestAccounts seed.inputLayout
    seed.extensions ctx
  -- Append PDA/CPI helpers with preflight (same honesty as lowerModuleWithPlan).
  let accountBindings :=
    SbpfAsm.buildCpiAccountBindings seed.manifestAccounts seed.inputLayout.accounts
  let stateDataOff ←
    match SbpfAsm.stateDataStartFromSchema module
        { accounts := seed.manifestAccounts, inputLayout := seed.inputLayout } with
    | .ok off => pure off
    | .error e => throw e
  let valueBindings := SbpfAsm.buildCpiValueBindings module stateDataOff
  let extNodes ←
    match Extension.lowerProgramExtensionsWithBindingsChecked
        accountBindings valueBindings seed.extensions with
    | .ok n => pure n
    | .error msg => throw { message := msg }
  pure (core ++ extNodes)

/-- Render a module to sBPF assembly text via the plan-driven path. Step C
made the plan-driven path the only lowering path, so this and
`SbpfAsm.renderModule` share the same `lowerModuleCoreWithSeed` body via
`LowerCtx.fromSeed` / `SbpfAsm.LowerCtx.fromPlanSeed`. -/
def renderModuleFromPlan (module : IR.Module) (plan : SolanaModulePlan) :
    Except SbpfAsm.LowerError String := do
  let nodes ← lowerModuleFromPlan module plan
  .ok (renderNodes nodes)

private def canonicalValueOffset (value : SolanaValuePlan) : Nat :=
  (value.id + 1) * 8

private def canonicalLoadValue (value : SolanaValuePlan) (reg : Reg) : AstNode :=
  .instruction { opcode := .ldxdw, dst := some reg, src := some Reg.r10, off := some (.num (canonicalValueOffset value)) }

private def canonicalStoreValue (value : SolanaValuePlan) (reg : Reg) : AstNode :=
  .instruction { opcode := .stxdw, dst := some Reg.r10, src := some reg, off := some (.num (canonicalValueOffset value)) }

private def canonicalArithmeticOpcode : SolanaArithmeticPlan -> Opcode
  | .add => .add64 | .sub => .sub64 | .mul => .mul64 | .div => .div64 | .mod => .mod64
  | .bitAnd => .and64 | .bitOr => .or64 | .bitXor => .xor64
  | .shiftLeft => .lsh64 | .shiftRight => .rsh64

private def canonicalCompareOpcode : SolanaComparePlan -> Opcode
  | .eq => .jeq | .ne => .jne | .lt => .jlt | .le => .jle | .gt => .jgt | .ge => .jge

private def canonicalBlockLabel (fnId blockId : Nat) : String := s!"sol_core_{fnId}_{blockId}"

private def lowerCanonicalOp (fnId blockId opIndex : Nat) : SolanaOpPlan -> Except SbpfAsm.LowerError (Array AstNode)
  | .literal result value => .ok #[
      .instruction { opcode := .mov64, dst := some .r2, imm := some (.num value) },
      canonicalStoreValue result .r2]
  | .boolLiteral result value => .ok #[
      .instruction { opcode := .mov64, dst := some .r2, imm := some (.num (if value then 1 else 0)) },
      canonicalStoreValue result .r2]
  | .copy result value => .ok #[canonicalLoadValue value .r2, canonicalStoreValue result .r2]
  | .portableCrosscall result calleeAccountIndex method args => do
      let site := s!"core_cpi_{fnId}_{blockId}_{opIndex}"
      let mut nodes : Array AstNode := #[
        .comment s!"portable peer handle -> peer/callee account index {calleeAccountIndex}",
        .instruction { opcode := .mov64, dst := some .r2, imm := some (.num calleeAccountIndex) }]
      nodes := nodes.push (.instruction {
        opcode := .stxdw
        dst := some .r10
        off := some (.num PortableCrosscall.portableTargetIndexSaveOffset)
        src := some .r2 })
      nodes := nodes.push (canonicalLoadValue method .r2)
      nodes := nodes ++ PortableCrosscall.storeIxDataWord 0
      for i in [:args.size] do
        nodes := nodes.push (canonicalLoadValue args[i]! .r2)
        nodes := nodes ++ PortableCrosscall.storeIxDataWord (i + 1)
      nodes := nodes ++ PortableCrosscall.invokeSignedC ((args.size + 1) * 8) #[] 0 #[]
        s!"{site}_return_none" s!"{site}_return_end"
      .ok (nodes.push (canonicalStoreValue result .r2))
  | .loadState result _ absOff byteSize => do
      unless byteSize == 8 do throw { message := s!"canonical Solana load width {byteSize} is unsupported" }
      .ok #[
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r1, off := some (.num absOff) },
        canonicalStoreValue result .r2]
  | .storeState _ absOff byteSize value => do
      unless byteSize == 8 do throw { message := s!"canonical Solana store width {byteSize} is unsupported" }
      .ok #[canonicalLoadValue value .r2,
        .instruction { opcode := .stxdw, dst := some .r1, src := some .r2, off := some (.num absOff) }]
  | .loadArray result _ absOff capacity elementByteSize index => do
      unless elementByteSize == 8 do
        throw { message := s!"canonical Solana array element width {elementByteSize} is unsupported" }
      let fail := s!"core_array_load_{fnId}_{blockId}_{opIndex}_bounds"
      let done := s!"core_array_load_{fnId}_{blockId}_{opIndex}_done"
      .ok #[
        canonicalLoadValue index .r2,
        .instruction { opcode := .jge, dst := some .r2, imm := some (.num capacity), off := some (.sym fail) },
        .instruction { opcode := .mul64, dst := some .r2, imm := some (.num elementByteSize) },
        .instruction { opcode := .mov64, dst := some .r3, src := some .r1 },
        .instruction { opcode := .add64, dst := some .r3, src := some .r2 },
        .instruction { opcode := .ldxdw, dst := some .r4, src := some .r3, off := some (.num absOff) },
        canonicalStoreValue result .r4,
        .instruction { opcode := .ja, off := some (.sym done) },
        .label fail,
        .instruction { opcode := .ja, off := some (.sym "assert_fail") },
        .label done]
  | .storeArray _ absOff capacity elementByteSize index value => do
      unless elementByteSize == 8 do
        throw { message := s!"canonical Solana array element width {elementByteSize} is unsupported" }
      let fail := s!"core_array_store_{fnId}_{blockId}_{opIndex}_bounds"
      let done := s!"core_array_store_{fnId}_{blockId}_{opIndex}_done"
      .ok #[
        canonicalLoadValue index .r2,
        .instruction { opcode := .jge, dst := some .r2, imm := some (.num capacity), off := some (.sym fail) },
        .instruction { opcode := .mul64, dst := some .r2, imm := some (.num elementByteSize) },
        .instruction { opcode := .mov64, dst := some .r3, src := some .r1 },
        .instruction { opcode := .add64, dst := some .r3, src := some .r2 },
        canonicalLoadValue value .r4,
        .instruction { opcode := .stxdw, dst := some .r3, src := some .r4, off := some (.num absOff) },
        .instruction { opcode := .ja, off := some (.sym done) },
        .label fail,
        .instruction { opcode := .ja, off := some (.sym "assert_fail") },
        .label done]
  | .loadMap result _ absOff capacity keyByteSize valueByteSize key => do
      unless keyByteSize == 8 && valueByteSize == 1 do
        throw { message := "canonical Solana Set map requires u64 keys and bool values" }
      let done := s!"core_map_load_{fnId}_{blockId}_{opIndex}_done"
      let mut nodes := #[
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num 0) },
        canonicalLoadValue key .r2]
      for index in [:capacity] do
        let entryOff := absOff + index * (1 + keyByteSize + valueByteSize)
        let next := s!"core_map_load_{fnId}_{blockId}_{opIndex}_{index}_next"
        nodes := nodes ++ #[
          .instruction { opcode := .ldxb, dst := some .r3, src := some .r1, off := some (.num entryOff) },
          .instruction { opcode := .jeq, dst := some .r3, imm := some (.num 0), off := some (.sym next) },
          .instruction { opcode := .ldxdw, dst := some .r3, src := some .r1, off := some (.num (entryOff + 1)) },
          .instruction { opcode := .jne, dst := some .r3, src := some .r2, off := some (.sym next) },
          .instruction { opcode := .ldxb, dst := some .r4, src := some .r1, off := some (.num (entryOff + 1 + keyByteSize)) },
          .instruction { opcode := .ja, off := some (.sym done) },
          .label next]
      nodes := nodes ++ #[.label done, canonicalStoreValue result .r4]
      return nodes
  | .storeMap _ absOff capacity keyByteSize valueByteSize key value => do
      unless keyByteSize == 8 && valueByteSize == 1 do
        throw { message := "canonical Solana Set map requires u64 keys and bool values" }
      let searchEmpty := s!"core_map_store_{fnId}_{blockId}_{opIndex}_empty"
      let done := s!"core_map_store_{fnId}_{blockId}_{opIndex}_done"
      let mut nodes := #[canonicalLoadValue key .r2, canonicalLoadValue value .r4]
      for index in [:capacity] do
        let entryOff := absOff + index * (1 + keyByteSize + valueByteSize)
        let next := s!"core_map_store_{fnId}_{blockId}_{opIndex}_{index}_next"
        nodes := nodes ++ #[
          .instruction { opcode := .ldxb, dst := some .r3, src := some .r1, off := some (.num entryOff) },
          .instruction { opcode := .jeq, dst := some .r3, imm := some (.num 0), off := some (.sym next) },
          .instruction { opcode := .ldxdw, dst := some .r3, src := some .r1, off := some (.num (entryOff + 1)) },
          .instruction { opcode := .jne, dst := some .r3, src := some .r2, off := some (.sym next) },
          .instruction { opcode := .stxb, dst := some .r1, src := some .r4, off := some (.num (entryOff + 1 + keyByteSize)) },
          .instruction { opcode := .ja, off := some (.sym done) },
          .label next]
      nodes := nodes.push (.instruction { opcode := .ja, off := some (.sym searchEmpty) })
      nodes := nodes.push (.label searchEmpty)
      for index in [:capacity] do
        let entryOff := absOff + index * (1 + keyByteSize + valueByteSize)
        let next := s!"core_map_empty_{fnId}_{blockId}_{opIndex}_{index}_next"
        nodes := nodes ++ #[
          .instruction { opcode := .ldxb, dst := some .r3, src := some .r1, off := some (.num entryOff) },
          .instruction { opcode := .jne, dst := some .r3, imm := some (.num 0), off := some (.sym next) },
          .instruction { opcode := .mov64, dst := some .r3, imm := some (.num 1) },
          .instruction { opcode := .stxb, dst := some .r1, src := some .r3, off := some (.num entryOff) },
          .instruction { opcode := .stxdw, dst := some .r1, src := some .r2, off := some (.num (entryOff + 1)) },
          .instruction { opcode := .stxb, dst := some .r1, src := some .r4, off := some (.num (entryOff + 1 + keyByteSize)) },
          .instruction { opcode := .ja, off := some (.sym done) },
          .label next]
      nodes := nodes ++ #[
        .instruction { opcode := .ja, off := some (.sym "error_map_capacity") }, .label done]
      return nodes
  | .arithmetic result op checked lhs rhs => do
      let base := #[canonicalLoadValue lhs .r2, canonicalLoadValue rhs .r3]
      let guard := if checked then
        match op with
        | .add | .mul => #[.instruction { opcode := .mov64, dst := some .r4, src := some .r2 }]
        | .sub => #[.instruction { opcode := .jlt, dst := some .r2, src := some .r3, off := some (.sym "error_arithmetic") }]
        | .div | .mod => #[.instruction { opcode := .jeq, dst := some .r3, imm := some (.num 0), off := some (.sym "error_arithmetic") }]
        | _ => #[]
      else #[]
      let calculation := #[.instruction { opcode := canonicalArithmeticOpcode op, dst := some .r2, src := some .r3 }]
      let post := if checked then match op with
        | .add => #[.instruction { opcode := .jlt, dst := some .r2, src := some .r4, off := some (.sym "error_arithmetic") }]
        | .mul =>
          let done := s!"core_mul_{fnId}_{blockId}_{opIndex}_done"
          #[.instruction { opcode := .jeq, dst := some .r3, imm := some (.num 0), off := some (.sym done) },
            .instruction { opcode := .mov64, dst := some .r5, src := some .r2 },
            .instruction { opcode := .div64, dst := some .r5, src := some .r3 },
            .instruction { opcode := .jne, dst := some .r5, src := some .r4, off := some (.sym "error_arithmetic") },
            .label done]
        | _ => #[]
      else #[]
      .ok (base ++ guard ++ calculation ++ post ++ #[canonicalStoreValue result .r2])
  | .compare result op lhs rhs =>
      let yes := s!"core_cmp_{fnId}_{blockId}_{opIndex}_yes"
      let done := s!"core_cmp_{fnId}_{blockId}_{opIndex}_done"
      .ok #[canonicalLoadValue lhs .r2, canonicalLoadValue rhs .r3,
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num 0) },
        .instruction { opcode := canonicalCompareOpcode op, dst := some .r2, src := some .r3, off := some (.sym yes) },
        .instruction { opcode := .ja, off := some (.sym done) },
        .label yes,
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num 1) },
        .label done,
        canonicalStoreValue result .r4]
  | .assert condition _ => .ok #[canonicalLoadValue condition .r2,
      .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "assert_fail") }]
  | .context result field => do
      if field.endsWith "sender" || field.endsWith "origin" then
        return #[
          .comment "solana.context.userId: account[0] pubkey u64-le word 0 handle",
          .instruction { opcode := .ldxdw, dst := some .r2, src := some .r1, off := some (.num 16) },
          canonicalStoreValue result .r2]
      unless field.endsWith "blockNumber" || field.endsWith "blockTimestamp" do
        throw { message := s!"canonical Solana context `{field}` has no target handler" }
      let bufferOff := 480
      let valueOff := if field.endsWith "blockTimestamp" then bufferOff - CLOCK_UNIX_TIMESTAMP_OFF else bufferOff
      .ok #[
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num 400), src := some .r1 },
        .instruction { opcode := .mov64, dst := some .r1, src := some .r10 },
        .instruction { opcode := .sub64, dst := some .r1, imm := some (.num bufferOff) },
        .instruction { opcode := .call, imm := some (.sym sol_get_clock_sysvar) },
        .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_syscall") },
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num valueOff) },
        canonicalStoreValue result .r2,
        .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num 400) }]
  | .log event eventName args => do
      let mut nodes := #[.comment s!"solana.event.emit {eventName} (event_id={event})"]
      for arg in args do
        nodes := nodes ++ #[canonicalLoadValue arg .r3,
          .instruction { opcode := .stxdw, dst := some .r10, off := some (.num 400), src := some .r1 },
          .instruction { opcode := .mov64, dst := some .r1, imm := some (.num event) },
          .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 0) },
          .instruction { opcode := .mov64, dst := some .r4, imm := some (.num 0) },
          .instruction { opcode := .mov64, dst := some .r5, imm := some (.num 0) },
          .instruction { opcode := .call, imm := some (.sym sol_log_64_) },
          .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num 400) }]
      return nodes

private def lowerCanonicalTerminator (fnId : Nat) : SolanaTerminatorPlan -> Array AstNode
  | .jump target _ => #[.instruction { opcode := .ja, off := some (.sym (canonicalBlockLabel fnId target)) }]
  | .branch condition ifTrue ifFalse => #[canonicalLoadValue condition .r2,
      .instruction { opcode := .jne, dst := some Reg.r2, imm := some (.num 0), off := some (.sym (canonicalBlockLabel fnId ifTrue)) },
      .instruction { opcode := .ja, off := some (.sym (canonicalBlockLabel fnId ifFalse)) }]
  | .return values => match values[0]? with
      | some value => #[canonicalLoadValue value .r2,
          .instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
          .instruction { opcode := .sub64, dst := some .r3, imm := some (.num 8) },
          .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 },
          .instruction { opcode := .mov64, dst := some .r1, src := some .r3 },
          .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 8) },
          .instruction { opcode := .call, imm := some (.sym "sol_set_return_data") },
          .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
          .instruction { opcode := .exit }]
      | none => #[.instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
          .instruction { opcode := .exit }]
  | .revert _ => #[.instruction { opcode := .ja, off := some (.sym "assert_fail") }]

private def lowerCanonicalParams (ep : SolanaEntrypointPlan) (fn : SolanaFunctionPlan) :
    Except SbpfAsm.LowerError (Array AstNode) := do
  unless ep.params.size == fn.params.size do
    throw { message := s!"canonical Solana parameter layout mismatch for `{fn.name}`" }
  let mut nodes := #[]
  for i in [:fn.params.size] do
    let param := ep.params[i]!
    let value := fn.params[i]!
    let opcode <- match param.byteSize with
      | 1 => pure Opcode.ldxb | 2 => pure .ldxh | 4 => pure .ldxw | 8 => pure .ldxdw
      | width => throw { message := s!"canonical Solana parameter width {width} is unsupported" }
    nodes := nodes ++ #[
      .instruction { opcode, dst := some .r2, src := some entryInstructionDataReg, off := some (.num param.offset) },
      canonicalStoreValue value .r2]
  return nodes

private def canonicalOpResults : SolanaOpPlan -> Array SolanaValuePlan
  | .literal result _ | .boolLiteral result _ | .copy result _ | .loadState result .. | .loadMap result .. |
    .loadArray result .. |
    .arithmetic result .. | .compare result .. | .context result _ |
    .portableCrosscall result .. => #[result]
  | _ => #[]

/-- Canonical lowering boundary: consumes only the complete target plan. -/
def lowerFromPlan (plan : SolanaModulePlan) : Except SbpfAsm.LowerError (Array AstNode) := do
  unless plan.targetId == "solana-sbpf-asm" do throw { message := "canonical Solana plan has wrong target" }
  unless plan.entrypoints.size == plan.functions.size do
    throw { message := "canonical Solana plan entrypoint/function count mismatch" }
  for fn in plan.functions do
    let declaredValues := fn.params ++ fn.blocks.flatMap (fun block =>
      block.params ++ block.ops.flatMap canonicalOpResults)
    if declaredValues.any (fun value => canonicalValueOffset value > 384) then
      throw { message := s!"canonical Solana function `{fn.name}` exceeds the 512-byte stack plan" }
  let mut nodes : Array AstNode := #[.sectionDecl .text, .globalDecl "entrypoint", .label "entrypoint"]
  let hasPortableCrosscall := plan.functions.any fun fn => fn.blocks.any fun block =>
    block.ops.any fun op => match op with | .portableCrosscall .. => true | _ => false
  nodes := nodes ++ SbpfAsm.lowerInstructionDataPointerSetup plan.accounts.size ++ #[
    .instruction { opcode := .ldxb, dst := some .r2, src := some entryInstructionDataReg, off := some (.num 0) }]
  for i in [:plan.functions.size] do
    let fn := plan.functions[i]!
    nodes := nodes.push (.instruction { opcode := .jeq, dst := some Reg.r2, imm := some (.num i), off := some (.sym (canonicalBlockLabel fn.id fn.blocks[0]!.id)) })
  nodes := nodes ++ #[.instruction { opcode := .mov64, dst := some .r0, imm := some (.num 9) },
    .instruction { opcode := .exit }]
  for fn in plan.functions do
    if fn.blocks.isEmpty then throw { message := s!"canonical Solana function `{fn.name}` has no body" }
    for block in fn.blocks do
      if block.id == fn.blocks[0]!.id then
        nodes := nodes.push (.label s!"sol_{fn.name}")
      nodes := nodes.push (.label (canonicalBlockLabel fn.id block.id))
      if block.id == fn.blocks[0]!.id then
        let ep <- match plan.entrypoints.find? (fun ep => ep.name == fn.name) with
          | some ep => pure ep
          | none => throw { message := s!"canonical Solana entrypoint `{fn.name}` is missing" }
        nodes := nodes ++ (<- lowerCanonicalParams ep fn)
      for i in [:block.ops.size] do
        nodes := nodes ++ (<- lowerCanonicalOp fn.id block.id i block.ops[i]!)
      nodes := nodes ++ lowerCanonicalTerminator fn.id block.terminator
  nodes := nodes ++ #[.label "assert_fail",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 2) }, .instruction { opcode := .exit },
    .label "error_syscall",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 10) }, .instruction { opcode := .exit },
    .label "error_arithmetic",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 13) }, .instruction { opcode := .exit },
    .label "error_map_capacity",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 14) }, .instruction { opcode := .exit }]
  if hasPortableCrosscall then
    nodes := nodes ++ #[.label "error_cpi",
      .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 8) },
      .instruction { opcode := .exit }]
  match BpfEncode.toBpfBin nodes with
  | .ok _ => pure nodes
  | .error e => throw { message := s!"canonical Solana verifier rejected plan: {e.render}" }

end ProofForge.Backend.Solana.Plan
