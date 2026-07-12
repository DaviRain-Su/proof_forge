/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Assembly Backend

Architecture: IR.Module → `Array AstNode` → sBPF assembly text (`.s`)

The AST/printer lives in `ProofForge.Backend.Solana.Asm`, account layout in
`StateLayout`, manifest generation in `Manifest`, syscalls in `Syscalls`, and
register bookkeeping in `Register`. This file owns the IR → AST lowering.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Register
import ProofForge.Backend.Solana.Syscalls
import ProofForge.Backend.Solana.PortableCrosscall
import ProofForge.Backend.Solana.SbpfAsm.Common
import ProofForge.Backend.Solana.SbpfAsm.Expr
import ProofForge.Backend.Solana.SbpfAsm.Stmt

namespace ProofForge.Backend.Solana.SbpfAsm

open ProofForge.Backend.Solana.StateLayout

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Register
open ProofForge.Backend.Solana.Syscalls

-- ============================================================================
-- Entrypoint lowering
-- ============================================================================

def entrypointHasReturn (ep : IR.Entrypoint) : Bool :=
  ep.body.any fun stmt => match stmt with | .return _ => true | _ => false

def moduleNeedsSyscallError (module : IR.Module) : Bool :=
  module.capabilities.any (fun capability =>
    capability == .envBlock || capability == .callerSender || capability == .cryptoHash)

def lowerProgramOwnerValidation (layout : AccountInputLayout) : Array AstNode :=
  loadCurrentProgramIdPtr .r4 .r2 ++ #[
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num 3600), src := some .r4 }
  ] ++
  inputAccountFieldPtr .r7 layout layout.ownerOff ++
  #[
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r10, off := some (.num 3600) },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 0) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 0) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 8) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 8) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 16) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 16) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 24) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 24) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") }
  ]

def lowerPubkeyPtrEqualityCheck (actual expected : Reg) : Array AstNode := #[
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 0) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 0) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 8) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 8) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 16) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 16) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 24) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 24) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") }
]

def lowerExecutableOwnerValidation (layout : AccountInputLayout) : Array AstNode :=
  inputAccountFieldPtr .r7 layout layout.executableOff ++ #[
    .instruction { opcode := .ldxb, dst := some .r2, src := some .r7, off := some (.num 0) },
    .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "error_owner") }
  ]

def lowerNamedOwnerValidation (layout ownerLayout : AccountInputLayout) : Array AstNode :=
  inputAccountFieldPtr .r7 layout layout.ownerOff ++
  inputAccountFieldPtr .r4 ownerLayout ownerLayout.keyOff ++
  lowerPubkeyPtrEqualityCheck .r7 .r4

def accountLayoutByName? : List AccountEntry -> List AccountInputLayout -> String ->
    Option AccountInputLayout
  | [], _, _ => none
  | _, [], _ => none
  | account :: accounts, layout :: layouts, name =>
      if account.name == name then
        some layout
      else
        accountLayoutByName? accounts layouts name

def lowerOwnerValidationFor (allAccounts : Array AccountEntry)
    (allLayouts : Array AccountInputLayout) (account : AccountEntry)
    (layout : AccountInputLayout) : Except LowerError (Array AstNode) := do
  if account.owner == "any" || account.owner.isEmpty then
    .ok #[]
  else if account.owner == "program" then
    .ok <| #[.comment s!"account.validation[{account.index}:{account.name}]: owner=program"] ++
      lowerProgramOwnerValidation layout
  else if account.owner == "executable" then
    .ok <| #[.comment s!"account.validation[{account.index}:{account.name}]: owner=executable"] ++
      lowerExecutableOwnerValidation layout
  else
    match accountLayoutByName? allAccounts.toList allLayouts.toList account.owner with
    | some ownerLayout =>
        .ok <| #[.comment s!"account.validation[{account.index}:{account.name}]: owner={account.owner}"] ++
          lowerNamedOwnerValidation layout ownerLayout
    | none =>
        .error {
          message := s!"unknown Solana owner account `{account.owner}` for account `{account.name}`"
        }

def lowerAccountValidationFor (account : AccountEntry)
    (layout : AccountInputLayout) (allAccounts : Array AccountEntry)
    (allLayouts : Array AccountInputLayout) : Except LowerError (Array AstNode) := do
  let signerCheck :=
    if account.signer then
      #[
        .comment s!"account.validation[{account.index}:{account.name}]: signer=true"
      ] ++ inputAccountFieldPtr .r7 layout layout.signerOff ++ #[
        .instruction { opcode := .ldxb, dst := some .r2, src := some .r7, off := some (.num 0) },
        .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "error_signer") }
      ]
    else
      #[]
  let writableCheck :=
    if account.writable then
      #[
        .comment s!"account.validation[{account.index}:{account.name}]: writable=true"
      ] ++ inputAccountFieldPtr .r7 layout layout.writableOff ++ #[
        .instruction { opcode := .ldxb, dst := some .r2, src := some .r7, off := some (.num 0) },
        .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "error_not_writable") }
      ]
    else
      #[]
  let ownerCheck ← lowerOwnerValidationFor allAccounts allLayouts account layout
  .ok <| signerCheck ++ writableCheck ++ ownerCheck

/-- Account-validation prologue for the generated fixed account schema. The
owner check uses the runtime instruction-data pointer saved from entrypoint
register `r9`, so it stays correct under account-data direct mapping. -/
def lowerAccountValidation (allAccounts : Array AccountEntry)
    (allLayouts : Array AccountInputLayout) :
    List AccountEntry -> List AccountInputLayout -> Except LowerError (Array AstNode)
  | [], _ => .ok #[]
  | _, [] => .ok #[]
  | account :: accounts, layout :: layouts => do
      let head ← lowerAccountValidationFor account layout allAccounts allLayouts
      let tail ← lowerAccountValidation allAccounts allLayouts accounts layouts
      .ok <| head ++ tail

def lowerAccountValidations (accounts : Array AccountEntry)
    (layouts : Array AccountInputLayout) : Except LowerError (Array AstNode) := do
  let validation ← lowerAccountValidation accounts layouts accounts.toList layouts.toList
  .ok <| #[
    .comment "account.validation: generated account schema"
  ] ++ validation

def lowerInstructionDataLengthCheck (requiredLen : Nat) : Array AstNode :=
  if requiredLen <= 1 then
    #[]
  else
    #[
      .comment s!"instruction_data.length >= {requiredLen}"
    ] ++ loadSavedInstructionDataPtr .r3 ++ #[
      .instruction { opcode := .mov64, dst := some .r4, src := some .r3 },
      .instruction { opcode := .sub64, dst := some .r4, imm := some (.num 8) },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r4, off := some (.num 0) },
      .instruction { opcode := .jlt, dst := some .r2, imm := some (.num requiredLen), off := some (.sym "error_instruction_data") }
    ]

def lowerExternalDiscriminatorDispatch (ep : IR.Entrypoint) : Array AstNode :=
  match externalDiscriminatorBytes? ep with
  | none => #[]
  | some bytes =>
      let nextLabel := s!"dispatch_external_next_{ep.name}"
      let byteChecks :=
        bytes.mapIdx (fun idx byte =>
          #[
            .instruction { opcode := .ldxb, dst := some .r4, src := some .r3, off := some (.num idx) },
            .instruction { opcode := .jne, dst := some .r4, imm := some (.num byte), off := some (.sym nextLabel) }
          ])
          |>.foldl (fun acc nodes => acc ++ nodes) #[]
      #[
        .comment s!"external discriminator dispatch {ep.name}: {bytes.size} bytes",
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num entryInstructionDataSaveOffset) },
        .instruction { opcode := .sub64, dst := some .r3, imm := some (.num 8) },
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) },
        .instruction { opcode := .jlt, dst := some .r2, imm := some (.num bytes.size), off := some (.sym nextLabel) },
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num entryInstructionDataSaveOffset) }
      ] ++ byteChecks ++ #[
        .instruction { opcode := .ja, off := some (.sym s!"sol_{ep.name}") },
        .label nextLabel
      ]

def lowerEntrypointParamDecoding (ctx : LowerCtx) (ep : IR.Entrypoint) :
    Except LowerError (LowerCtx × Array AstNode) := do
  let mut ctx := ctx
  let mut nodes := #[]
  let mut payloadOff := entrypointDiscriminatorSize ep
  for param in ep.params do
    let (name, ty) := param
    let some byteSize := scalarParamSize? ty
      | .error { message := s!"unsupported Solana entrypoint parameter type for `{name}`: {ty.name}" }
    let localOff := ctx.nextLocalOffset
    ctx := ctx.addLocal name ty
    if isRawBytesParam ty then
      -- L1.3: fixed raw-byte params stay addressable via instruction-data
      -- bindings for CPI (memo); also mirror bytes into the local frame.
      let copy :=
        (List.range byteSize).foldl
          (fun acc idx =>
            acc ++ #[
              .instruction {
                opcode := .ldxb, dst := some .r2, src := some .r3,
                off := some (.num (payloadOff + idx))
              },
              .instruction {
                opcode := .stxb, dst := some .r10, off := some (.num (localOff + idx)),
                src := some .r2
              }
            ])
          #[]
      nodes := nodes ++ #[
        .comment s!"entrypoint.param[{ep.name}.{name}]: raw-bytes {ty.name} @ instruction_data+{payloadOff} (len={byteSize})"
      ] ++ loadSavedInstructionDataPtr .r3 ++ copy
    else
      let some opcode := scalarParamLoadOpcode? ty
        | .error { message := s!"unsupported Solana entrypoint parameter load for `{name}`: {ty.name}" }
      nodes := nodes ++ #[
        .comment s!"entrypoint.param[{ep.name}.{name}]: {ty.name} @ instruction_data+{payloadOff}"
      ] ++ loadSavedInstructionDataPtr .r3 ++ #[
        .instruction { opcode := opcode, dst := some .r2, src := some .r3, off := some (.num payloadOff) },
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num localOff), src := some .r2 }
      ]
    payloadOff := payloadOff + byteSize
  .ok (ctx, nodes)

partial def lowerEntrypoint (ctx : LowerCtx)
    (accounts : Array AccountEntry) (accountLayouts : Array AccountInputLayout)
    (extensions : ProgramExtensions) (ep : IR.Entrypoint) :
    Except LowerError (LowerCtx × Array AstNode) := do
  let mut nodes := #[
    .label s!"sol_{ep.name}",
    .blankLine
  ]
  -- Per-entrypoint PDA signer seeds for portable peer CPI (invoke_signed).
  let mut ctx := {
    ctx with
    portableSignerSeeds := portableSignerSeedsFromExtensions extensions ep.name
  }
  nodes := nodes ++ #[
    .comment s!"account.graph: exact runtime count = {accounts.size}",
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r1, off := some (.num 0) },
    .instruction { opcode := .jne, dst := some .r2, imm := some (.num accounts.size), off := some (.sym "error_account_count") }
  ]
  let accountValidationNodes ← lowerAccountValidations accounts accountLayouts
  nodes := nodes ++ accountValidationNodes
  nodes := nodes ++ lowerInstructionDataLengthCheck (instructionDataMinLen ep)
  let (ctxAfterParams, paramNodes) ← lowerEntrypointParamDecoding ctx ep
  ctx := ctxAfterParams
  nodes := nodes ++ paramNodes
  nodes := nodes ++ lowerEntrypointActions extensions ep.name
  for stmt in ep.body do
    let (sn, ctx') ← lowerStmt ctx stmt
    nodes := nodes ++ sn
    ctx := ctx'
  if !entrypointHasReturn ep then
    nodes := nodes ++ #[
      .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
      .instruction { opcode := .exit }
    ]
  .ok (ctx, nodes)

-- ============================================================================
-- Module → AST nodes
-- ============================================================================

structure ModuleInputSchema where
  accounts : Array AccountEntry
  inputLayout : InputLayout
  deriving Inhabited

structure EntrypointInputSchema where
  name : String
  accounts : Array AccountEntry
  inputLayout : InputLayout
  deriving Inhabited

def buildModuleInputSchema (module : IR.Module) (extensions : ProgramExtensions) :
    ModuleInputSchema :=
  let accounts := buildModuleAccounts module extensions
  let inputLayout := computeInputLayoutWithReallocFlags (accountInputSpecs module extensions accounts)
  { accounts, inputLayout }

def buildEntrypointInputSchemas (module : IR.Module) (extensions : ProgramExtensions) :
    Array EntrypointInputSchema :=
  buildInstructionsWithExtensions module extensions |>.map fun instruction =>
    let specs := accountInputSpecs module extensions instruction.accounts
    {
      name := instruction.name
      accounts := instruction.accounts
      inputLayout := computeInputLayoutWithReallocFlags specs
    }

def buildCpiAccountBindings (accounts : Array AccountEntry)
    (layouts : Array AccountInputLayout) : Array CpiAccountBinding := Id.run do
  let mut bindings := #[]
  let mut idx := 0
  for account in accounts do
    match layouts[idx]? with
    | some layout =>
        bindings := bindings.push { name := account.name, layout }
    | none =>
        pure ()
    idx := idx + 1
  return bindings

def buildStateCpiValueBindings (module : IR.Module) (stateDataOff : Nat) : Array CpiValueBinding :=
  buildStateOffsetsAtBase module stateDataOff |>.map fun field => {
    name := field.id
    absOff := field.absOff
    byteSize := 8
    sourceKind := "state"
  }

def buildEntrypointParamCpiValueBindings (module : IR.Module) :
    Array CpiValueBinding := Id.run do
  let mut bindings := #[]
  let mut ambiguous : Array String := #[]
  for ep in module.entrypoints do
    let mut payloadOff := entrypointDiscriminatorSize ep
    for param in ep.params do
      let (name, ty) := param
      match scalarParamSize? ty with
      | some byteSize =>
          let binding := {
            name := name
            absOff := payloadOff
            byteSize := byteSize
            sourceKind := "instruction param"
            relativeToInstructionData := true
          }
          if ambiguous.any (fun existing => existing == name) then
            pure ()
          else
            match bindings.find? (fun existing => existing.name == name) with
            | none => bindings := bindings.push binding
            | some existing =>
                if existing.absOff == binding.absOff then
                  pure ()
                else
                  bindings := bindings.filter (fun item => item.name != name)
                  ambiguous := ambiguous.push name
          payloadOff := payloadOff + byteSize
      | none =>
          pure ()
  return bindings

def buildCpiValueBindings (module : IR.Module) (stateDataOff : Nat) :
    Array CpiValueBinding :=
  buildStateCpiValueBindings module stateDataOff ++
  buildEntrypointParamCpiValueBindings module

def lastAccountLayout? (layouts : Array AccountInputLayout) : Option AccountInputLayout :=
  layouts[layouts.size - 1]?

def lowerInstructionDataPointerSetup (accountCount : Nat) : Array AstNode :=
  #[
    .comment "save instruction_data pointer from generated Solana input layout"
  ] ++ lowerAccountPtrTableSetup "entrypoint" accountCount ++ #[
    .instruction { opcode := .mov64, dst := some entryInstructionDataReg, src := some .r3 },
    .instruction { opcode := .add64, dst := some entryInstructionDataReg, imm := some (.num U64_SIZE) },
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num entryInstructionDataSaveOffset), src := some entryInstructionDataReg }
  ]

/-- Resolve portable state account dataStart when `authority` may occupy index 0. -/
def stateDataStartFromSchema (module : IR.Module) (schema : ModuleInputSchema) :
    Except LowerError Nat :=
  if module.state.isEmpty then
    .ok 0
  else
    match stateAccountIndex? module schema.accounts with
    | none =>
        .error {
          message :=
            s!"Solana account schema missing state account `{defaultStateAccountName module}`"
        }
    | some idx =>
        match schema.inputLayout.accounts[idx]? with
        | some accountLayout => .ok accountLayout.dataStart
        | none =>
            .error { message := "Solana input layout missing state account slot" }

def buildEntrypointExtensionBindings (module : IR.Module)
    (schemas : Array EntrypointInputSchema) :
    Except LowerError (Array EntrypointBindings) := do
  let mut bindings := #[]
  for schema in schemas do
    let stateDataOff ← stateDataStartFromSchema module {
      accounts := schema.accounts
      inputLayout := schema.inputLayout
    }
    bindings := bindings.push {
      entrypoint := schema.name
      accountBindings := buildCpiAccountBindings schema.accounts schema.inputLayout.accounts
      valueBindings := buildCpiValueBindings module stateDataOff
    }
  pure bindings

/-- Core lowering body once the account schema, input layout, and lowering
context have been derived. Exposed so the plan-driven path
(`ProofForge.Backend.Solana.Plan.lowerModuleFromPlan`) can reuse the exact same
body without re-deriving the schema from the IR module. -/
partial def lowerModuleCoreWithSeed (module : IR.Module)
    (accounts : Array AccountEntry) (inputLayout : InputLayout)
    (entrypointSchemas : Array EntrypointInputSchema)
    (extensions : ProgramExtensions) (ctx : LowerCtx) :
    Except LowerError (Array AstNode) := do
  let mut nodes := #[
    .comment s!"ProofForge generated sBPF — {module.name} (Phase 1)",
    .comment "Target: solana-sbpf-asm (D-026)",
    .blankLine,
    .equDecl "INSTRUCTION_DATA_LEN" inputLayout.instructionDataLenOff,
    .equDecl "INSTRUCTION_DATA" inputLayout.instructionDataOff
  ]
  for (stateId, absOff) in ctx.stateFieldOffsets do
    nodes := nodes.push (.equDecl (stateId.toUpper ++ "_DATA") absOff)

  nodes := nodes ++ #[
    .blankLine,
    .globalDecl "entrypoint",
    .blankLine,
    .label "entrypoint"
  ] ++ lowerInstructionDataPointerSetup accounts.size ++ #[
    .comment "instruction_data.length >= 1",
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num entryInstructionDataSaveOffset) },
    .instruction { opcode := .sub64, dst := some .r3, imm := some (.num 8) },
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) },
    .instruction { opcode := .jlt, dst := some .r2, imm := some (.num 1), off := some (.sym "error_instruction_data") },
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num entryInstructionDataSaveOffset) },
    .instruction { opcode := .ldxb, dst := some .r2, src := some .r3, off := some (.num 0) }
  ]
  let hasExternalDiscriminators :=
    module.entrypoints.any (fun ep => (externalDiscriminatorBytes? ep).isSome)
  if hasExternalDiscriminators then
    for ep in module.entrypoints do
      nodes := nodes ++ lowerExternalDiscriminatorDispatch ep
    nodes := nodes ++ loadSavedInstructionDataPtr .r3 ++ #[
      .instruction { opcode := .ldxb, dst := some .r2, src := some .r3, off := some (.num 0) }
    ]
  let mut idx := 0
  for ep in module.entrypoints do
    if (externalDiscriminatorBytes? ep).isNone then
      nodes := nodes.push (.instruction {
        opcode := .jeq, dst := some .r2, imm := some (.num idx), off := some (.sym s!"sol_{ep.name}")
      })
    idx := idx + 1
  nodes := nodes ++ #[
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 1) },
    .instruction { opcode := .exit }
  ]

  let mut ctx := ctx
  for ep in module.entrypoints do
    nodes := nodes.push .blankLine
    let epSchema ←
      match entrypointSchemas.find? (fun schema => schema.name == ep.name) with
      | some schema => pure schema
      | none => throw { message := s!"Solana input schema missing entrypoint `{ep.name}`" }
    let stateDataOff ← stateDataStartFromSchema module {
      accounts := epSchema.accounts
      inputLayout := epSchema.inputLayout
    }
    let stateFieldOffsets := buildStateOffsetsAtBase module stateDataOff
      |>.map (fun field => (field.id, field.absOff))
    let accountBindings := buildCpiAccountBindings epSchema.accounts epSchema.inputLayout.accounts
    let valueBindings := buildCpiValueBindings module stateDataOff
    let cpiIndices :=
      ProofForge.Backend.Solana.PortableCrosscall.selectPortableCpiAccountIndices epSchema.accounts
    let epCtx := {
      LowerCtx.fromPlanSeed stateFieldOffsets module.structs module.state epSchema.accounts.size
        accountBindings valueBindings #[] cpiIndices with
      nextLabel := ctx.nextLabel
    }
    let (ctx', block) ←
      lowerEntrypoint epCtx epSchema.accounts epSchema.inputLayout.accounts extensions ep
    ctx := { ctx with nextLabel := ctx'.nextLabel }
    nodes := nodes ++ block

  nodes := nodes ++ #[
    .blankLine,
    .label "assert_fail",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 2) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "assert_eq_fail",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 3) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_not_writable",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 4) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_signer",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 5) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_owner",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 6) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_instruction_data",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 9) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_duplicate_account",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 13) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_account_count",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 14) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_pda_bump",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 11) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_array_bounds",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 12) },
    .instruction { opcode := .exit },
    .blankLine,
    -- Portable crosscall materialization and Source.Solana CPI share this trap.
    .label "error_cpi",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 8) },
    .instruction { opcode := .exit }
  ]
  if moduleNeedsSyscallError module then
    nodes := nodes ++ #[
      .blankLine,
      .label "error_syscall",
      .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 10) },
      .instruction { opcode := .exit }
    ]
  .ok nodes

partial def lowerModuleCore (module : IR.Module) (extensions : ProgramExtensions) :
    Except LowerError (Array AstNode) := do
  validateCapabilities module
  let schema := buildModuleInputSchema module extensions
  let entrypointSchemas := buildEntrypointInputSchemas module extensions
  let stateDataOff ← stateDataStartFromSchema module schema
  let accountBindings := buildCpiAccountBindings schema.accounts schema.inputLayout.accounts
  let valueBindings := buildCpiValueBindings module stateDataOff
  let cpiIndices :=
    ProofForge.Backend.Solana.PortableCrosscall.selectPortableCpiAccountIndices
      schema.accounts
  let ctx :=
    buildLowerCtx module stateDataOff schema.accounts.size accountBindings valueBindings
      cpiIndices
  if schema.accounts.size > MAX_PORTABLE_CPI_ACCOUNTS then
    .error {
      message :=
        s!"Solana account schema has {schema.accounts.size} accounts; " ++
        s!"portable CPI packing supports at most {MAX_PORTABLE_CPI_ACCOUNTS} " ++
        s!"(= MAX_TX_ACCOUNT_LOCKS; infos on heap, metas on stack)"
    }
  else
    lowerModuleCoreWithSeed module schema.accounts schema.inputLayout entrypointSchemas extensions ctx

partial def lowerModule (module : IR.Module) : Except LowerError (Array AstNode) :=
  lowerModuleCore module {}

-- ============================================================================
-- Module rendering (IR → AST → text pipeline)
-- ============================================================================

def renderModule (module : IR.Module) : Except LowerError String := do
  let nodes ← lowerModule module
  .ok (Asm.renderNodes nodes)

def lowerModuleWithPlan (module : IR.Module) (plan : ProofForge.Target.CapabilityPlan) :
    Except LowerError (Array AstNode) := do
  let extensions := ProgramExtensions.fromPlan plan
  let schema := buildModuleInputSchema module extensions
  let accountBindings := buildCpiAccountBindings schema.accounts schema.inputLayout.accounts
  let stateDataOff ← stateDataStartFromSchema module schema
  let valueBindings := buildCpiValueBindings module stateDataOff
  let entrypointBindings ← buildEntrypointExtensionBindings module
    (buildEntrypointInputSchemas module extensions)
  let nodes ← lowerModuleCore module extensions
  -- Preflight: reject unresolved PDA/CPI seed bindings (no silent zero seeds).
  let extNodes ←
    match ProofForge.Backend.Solana.Extension.lowerProgramExtensionsWithEntrypointBindingsChecked
        accountBindings valueBindings entrypointBindings extensions with
    | .ok n => pure n
    | .error msg => throw { message := msg }
  .ok (nodes ++ extNodes)

def renderModuleWithPlan (module : IR.Module) (plan : ProofForge.Target.CapabilityPlan) :
    Except LowerError String := do
  let nodes ← lowerModuleWithPlan module plan
  .ok (Asm.renderNodes nodes)

-- ============================================================================
-- Phase 0: canned entrypoint
-- ============================================================================

def renderCannedEntrypoint : Except LowerError String :=
  .ok (String.intercalate "\n" #[
    "; ProofForge generated sBPF entrypoint (Phase 0 spike)",
    "; Target: solana-sbpf-asm (D-026)",
    "; This canned entrypoint returns success (r0 = 0) without parsing accounts.",
    "",
    ".globl entrypoint",
    "",
    "entrypoint:",
    "  mov64 r0, 0",
    "  exit",
    ""
  ].toList)

end ProofForge.Backend.Solana.SbpfAsm
