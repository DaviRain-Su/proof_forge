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

namespace ProofForge.Backend.Solana.Plan

open ProofForge.IR
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.SbpfAsm
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Register

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
  accounts : Array SolanaAccountPlan
  discriminator : SolanaEntrypointDiscriminatorPlan
  params : Array SolanaInstructionParamPlan
  returns : String
  hasReturn : Bool
  instructionDataMinLen : Nat
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
  entrypointSchemas : Array EntrypointInputSchema
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

def buildEntrypointPlan (module : Module) (extensions : ProgramExtensions)
    (ep : Entrypoint) (internalTag : Nat) : Except PlanError SolanaEntrypointPlan := do
  let params ← buildEntrypointParamPlans ep
  let accounts := buildInstructionAccounts module extensions ep.name
  let specs := accountInputSpecs module extensions accounts
  return {
    name := ep.name
    accounts := buildAccountPlan module extensions accounts specs
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
  let accounts := buildModuleAccounts module extensions
  let specs := accountInputSpecs module extensions accounts
  let inputLayout := computeInputLayoutWithReallocFlags specs
  let entrypointSchemas := buildEntrypointInputSchemas module extensions
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
    entrypointPlans := entrypointPlans.push (← buildEntrypointPlan module extensions ep tag)
    tag := tag + 1
  let stateFieldOffsets := buildStateOffsetsAtBase module stateDataOff
                     |>.map (fun f => (f.id, f.absOff))
  let lowerCtxSeed := {
    stateFieldOffsets
    structs := module.structs
    stateDecls := module.state
    inputLayout
    manifestAccounts := accounts
    entrypointSchemas
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
  let accountLines :=
    if ep.accounts.isEmpty then #["  accounts: []"]
    else #["  accounts:"] ++ ep.accounts.map (fun account => "  " ++ renderAccount account)
  let disc := renderDiscriminator ep.discriminator
  let params := if ep.params.isEmpty then #["  params: []"] else #["  params:"] ++ ep.params.map renderParam
  String.intercalate "\n" ([header] ++ accountLines.toList ++ [disc] ++ params.toList)

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
    seed.entrypointSchemas seed.extensions ctx
  -- Append PDA/CPI helpers with preflight (same honesty as lowerModuleWithPlan).
  let accountBindings :=
    SbpfAsm.buildCpiAccountBindings seed.manifestAccounts seed.inputLayout.accounts
  let stateDataOff ←
    match SbpfAsm.stateDataStartFromSchema module
        { accounts := seed.manifestAccounts, inputLayout := seed.inputLayout } with
    | .ok off => pure off
    | .error e => throw e
  let valueBindings := SbpfAsm.buildCpiValueBindings module stateDataOff
  let entrypointBindings ← SbpfAsm.buildEntrypointExtensionBindings module seed.entrypointSchemas
  let extNodes ←
    match Extension.lowerProgramExtensionsWithEntrypointBindingsChecked
        accountBindings valueBindings entrypointBindings seed.extensions with
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

end ProofForge.Backend.Solana.Plan
