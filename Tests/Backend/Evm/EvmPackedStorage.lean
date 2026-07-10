import ProofForge.Backend.Evm.ConstructorInit
import ProofForge.Backend.Evm.IR
import ProofForge.Compiler.Yul.Printer
import ProofForge.IR.Examples.EvmPackedStorageProbe

namespace ProofForge.Tests.EvmPackedStorage

open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.ToYul
open Lean.Compiler.Yul

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def renderExpr (expr : Expr) : String :=
  Printer.printExpr expr

def renderStatement (stmt : Statement) : String :=
  Printer.printStatement 0 stmt

def requirePackedWrite
    (statements : Array Statement)
    (expectedShift expectedMask : Nat)
    (expectedValue : String)
    (message : String) : IO Unit := do
  require (statements.size == 1) s!"{message}: expected one sstore"
  let rendered := renderStatement statements[0]!
  require
    (rendered.contains s!"not(shl({expectedShift}, {expectedMask}))")
    s!"{message}: field-clear mask must use the low-order byte offset, got: {rendered}"
  require
    (rendered.contains s!"shl({expectedShift}, and({expectedValue}, {expectedMask}))")
    s!"{message}: packed value must be masked before shifting, got: {rendered}"

def testLowOrderReadAndMaskedWrite : IO Unit := do
  let readExpr := scalarStoragePackedReadExpr (.num 7) 1 1
  require
    (renderExpr readExpr == "and(shr(8, sload(7)), 255)")
    s!"packed reads must use Solidity low-order offsets, got: {renderExpr readExpr}"
  requirePackedWrite
    (scalarStorageWriteStatements (.num 7) (.id "value") 1 1)
    8
    255
    "value"
    "packed scalar write"

def testCheckedAssignOpRejectsNarrowOverflow : IO Unit := do
  let statements := scalarStorageAssignOpStatements true .add (.num 7) (.num 1) 1 1
  require (statements.size == 1) "checked packed assign_op must remain one scoped statement"
  let rendered := renderStatement statements[0]!
  require
    (rendered.contains "let __pf_packed_value := __pf_checked_width(__pf_checked_add(")
    s!"checked packed assign_op must evaluate its value exactly once in local scope, got: {rendered}"
  require
    (rendered.contains "__pf_checked_width(and(shr(8, sload(7)), 255), 255)")
    s!"checked packed assign_op must validate its packed operand width, got: {rendered}"
  require
    (rendered.contains "if gt(__pf_packed_value, 255)")
    s!"checked packed assign_op must reject values above the field mask, got: {rendered}"
  require
    (rendered.contains "revert(0, 0)")
    s!"checked packed assign_op width guard must fail closed, got: {rendered}"
  require
    (rendered.contains "shl(8, and(__pf_packed_value, 255))")
    s!"checked packed assign_op must mask the guarded local before shifting, got: {rendered}"

def testWrappingAssignOpTruncatesToFieldWidth : IO Unit := do
  let statements := scalarStorageAssignOpStatements false .add (.num 7) (.num 1) 1 1
  requirePackedWrite
    statements
    8
    255
    "and(add(and(shr(8, sload(7)), 255), 1), 255)"
    "wrapping packed assign_op"

def requirePackedWidthGuard
    (statements : Array Statement)
    (expectedValue expectedMask message : String) : IO Unit := do
  require (statements.size == 1) s!"{message}: expected one scoped statement"
  let rendered := renderStatement statements[0]!
  require
    (rendered.contains s!"let __pf_packed_value := {expectedValue}")
    s!"{message}: write value must be evaluated once, got: {rendered}"
  require
    (rendered.contains s!"if gt(__pf_packed_value, {expectedMask})")
    s!"{message}: checked write must guard destination width, got: {rendered}"

def testDirectWriteSemanticsAreExplicit : IO Unit := do
  let checkedTarget : ScalarStorageTargetPlan := {
    slot := .scalarSlot 7
    byteOffset := 1
    byteWidth := 1
    writeSemantics := .checked
  }
  let wrappingTarget : ScalarStorageTargetPlan := {
    checkedTarget with writeSemantics := .wrapping
  }
  let lowerExpr : ProofForge.IR.Expr → Except String Expr :=
    fun _ => .error "raw expression lowering is not expected"
  let lowerEffect : EffectPlan → Except String Expr :=
    fun _ => .error "nested effect lowering is not expected"
  let checkedLiteral ←
    match scalarStorageTargetEffectPlanStatements
        id lowerExpr lowerEffect
        (.storageScalarWriteTarget checkedTarget (.literalWord 256)) with
    | .ok statements => pure statements
    | .error err => throw <| IO.userError err
  requirePackedWidthGuard checkedLiteral "256" "255" "checked packed literal write"
  let checkedLocal ←
    match scalarStorageTargetEffectPlanStatements
        id lowerExpr lowerEffect
        (.storageScalarWriteTarget checkedTarget (.local "value")) with
    | .ok statements => pure statements
    | .error err => throw <| IO.userError err
  requirePackedWidthGuard checkedLocal "value" "255" "checked packed local write"
  let wrappingLiteral ←
    match scalarStorageTargetEffectPlanStatements
        id lowerExpr lowerEffect
        (.storageScalarWriteTarget wrappingTarget (.literalWord 256)) with
    | .ok statements => pure statements
    | .error err => throw <| IO.userError err
  let wrappingRendered := renderStatement wrappingLiteral[0]!
  require
    (!wrappingRendered.contains "if gt(")
    s!"wrapping packed write must not inject a checked guard, got: {wrappingRendered}"
  require
    (wrappingRendered.contains "shl(8, and(256, 255))")
    s!"wrapping packed write must deliberately truncate, got: {wrappingRendered}"

def testLowerCarriesDirectWriteSemantics : IO Unit := do
  let module := ProofForge.IR.Examples.EvmPackedStorageProbe.module
  let requireMode
      (effect : ProofForge.IR.Effect)
      (env : ProofForge.Backend.Evm.Validate.TypeEnv)
      (expected : ScalarStorageWriteSemantics)
      (label : String) : IO Unit := do
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module env effect with
    | .ok (.storageScalarWriteTarget target _) =>
        require (target.writeSemantics == expected)
          s!"{label}: wrong planned write semantics"
    | .ok _ => throw <| IO.userError s!"{label}: expected planned scalar target"
    | .error err => throw <| IO.userError s!"{label}: {err.message}"
  requireMode
    (.storageScalarWrite "counter" (.literal (.u8 1)))
    #[]
    .checked
    "checked literal"
  requireMode
    (.storageScalarWrite "counter" (.local "candidate"))
    #[{ name := "candidate", type := .u8, isMutable := false }]
    .checked
    "checked local"
  requireMode
    (.storageScalarWrite "counter"
      (.add (.literal (.u8 255)) (.literal (.u8 1)) false))
    #[]
    .wrapping
    "explicit wrapping expression"
  match ProofForge.Backend.Evm.Lower.buildEffectPlan module #[]
      (.storageScalarWrite "counter"
        (.add (.literal (.u8 255)) (.literal (.u8 1)) false)) with
  | .ok (.storageScalarWriteTarget _
      (.checkedArith .add _ _ false (some byteWidth))) =>
      require (byteWidth == 1)
        s!"u8 arithmetic plan must retain byte width 1, got {byteWidth}"
  | .ok _ => throw <| IO.userError "u8 arithmetic plan must carry result width metadata"
  | .error err => throw <| IO.userError err.message

def testNarrowArithmeticIsAppliedPerNode : IO Unit := do
  let module := ProofForge.IR.Examples.EvmPackedStorageProbe.module
  let renderWrite (value : ProofForge.IR.Expr) (label : String) : IO String := do
    let effectPlan ←
      match ProofForge.Backend.Evm.Lower.buildEffectPlan module #[]
          (.storageScalarWrite "counter" value) with
      | .ok plan@(.storageScalarWriteTarget ..) => pure plan
      | .ok _ => throw <| IO.userError s!"{label}: expected planned scalar target"
      | .error err => throw <| IO.userError s!"{label}: {err.message}"
    let statements ←
      match scalarStorageTargetEffectPlanStatements
          id
          (fun _ => .error "raw expression lowering is not expected")
          (fun _ => .error "nested effect lowering is not expected")
          effectPlan with
      | .ok statements => pure statements
      | .error err => throw <| IO.userError s!"{label}: {err}"
    pure <| String.intercalate "\n" (statements.toList.map renderStatement)
  let nestedChecked :=
    .sub
      (.add (.literal (.u8 255)) (.literal (.u8 1)) true)
      (.literal (.u8 1))
      true
  let nestedCheckedRendered ← renderWrite nestedChecked "nested checked expression"
  require
    (nestedCheckedRendered.contains "__pf_checked_width")
    s!"nested checked arithmetic must enforce the width at each node, got: {nestedCheckedRendered}"
  let mixedRendered ← renderWrite
    (.sub
      (.add (.literal (.u8 255)) (.literal (.u8 1)) true)
      (.literal (.u8 256))
      false)
    "mixed checked/wrapping expression"
  require
    (mixedRendered.contains "__pf_checked_width")
    s!"mixed arithmetic must retain the inner checked width guard, got: {mixedRendered}"
  require
    (mixedRendered.contains "and(sub(")
    s!"mixed arithmetic must mask the outer wrapping result, got: {mixedRendered}"
  let castPlan ←
    match ProofForge.Backend.Evm.Lower.buildEffectPlan module #[]
        (.storageScalarWrite "counter"
          (.cast
            (.add (.literal (.u64 1)) (.literal (.u64 2)) true)
            .u8)) with
    | .ok (.storageScalarWriteTarget _ plan) => pure plan
    | .ok _ => throw <| IO.userError "cast storage write must retain its planned target"
    | .error err => throw <| IO.userError err.message
  match castPlan with
  | .cast (.checkedArith .add _ _ _ (some byteWidth)) .u8 =>
      require (byteWidth == 8)
        s!"arithmetic below a narrowing cast must retain U64 width 8, got {byteWidth}"
  | _ =>
      throw <| IO.userError
        "arithmetic below a narrowing cast must carry its own result width"
  let ordinaryPlan ←
    match ProofForge.Backend.Evm.Lower.buildExprPlan module #[]
        (.add (.literal (.u8 1)) (.literal (.u8 2)) true) with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err.message
  let ordinaryExpr ←
    match exprPlanExpr
        id
        (fun _ => .error "raw expression lowering is not expected")
        (fun _ => .error "nested effect lowering is not expected")
        ordinaryPlan with
    | .ok expr => pure expr
    | .error err => throw <| IO.userError err
  require
    (renderExpr ordinaryExpr == "__pf_checked_add(1, 2)")
    s!"ordinary non-storage arithmetic must retain word semantics, got: {renderExpr ordinaryExpr}"
  let missingWidthTarget : ScalarStorageTargetPlan := {
    slot := .scalarSlot 0
    byteOffset := 0
    byteWidth := 1
    writeSemantics := .checked
  }
  match scalarStorageTargetEffectPlanStatements
      id
      (fun _ => .error "raw expression lowering is not expected")
      (fun _ => .error "nested effect lowering is not expected")
      (.storageScalarWriteTarget missingWidthTarget
        (.checkedArith .add (.literalWord 1) (.literalWord 2) true none)) with
  | .error err =>
      require
        (err == "EVM narrow scalar storage arithmetic plan is missing result byte width metadata")
        s!"missing width metadata must fail with a stable diagnostic, got: {err}"
  | .ok _ =>
      throw <| IO.userError "narrow storage arithmetic without width metadata must fail closed"

def requireAbiUpperBoundGuard
    (type : ProofForge.IR.ValueType)
    (expectedLimit label : String) : IO Unit := do
  let some statement := abiWordValidationStatement? (.id "value") type
    | throw <| IO.userError s!"{label}: missing ABI upper-bound guard"
  let rendered := renderStatement statement
  require
    (rendered.contains s!"gt(value, {expectedLimit})")
    s!"{label}: wrong ABI upper-bound guard, got: {rendered}"

def testNarrowAbiWordGuards : IO Unit := do
  requireAbiUpperBoundGuard .u8 "255" "u8"
  requireAbiUpperBoundGuard .u32 "4294967295" "u32"
  requireAbiUpperBoundGuard .u64 "18446744073709551615" "u64"
  requireAbiUpperBoundGuard .u128 "340282366920938463463374607431768211455" "u128"
  requireAbiUpperBoundGuard .address
    "1461501637330902918203684832716283019655932542975"
    "address"
  requireAbiUpperBoundGuard .bool "1" "bool"

def testAbiWordOverridesDriveCanonicalGuards : IO Unit := do
  let entrypoint : ProofForge.IR.Entrypoint := {
    name := "abi_overrides"
    params := #[
      ("recipient", .u64),
      ("interface_id", .u64),
      ("plain", .u64)
    ]
    paramAbiWords := #[some "address", some "bytes4", none]
    body := #[]
  }
  let module : ProofForge.IR.Module := {
    name := "AbiOverrideProbe"
    state := #[]
    entrypoints := #[entrypoint]
  }
  let plans ← match ProofForge.Backend.Evm.Lower.entrypointParamPlans module entrypoint with
    | .ok plans => pure plans
    | .error err => throw <| IO.userError err.message
  require (plans.size == 3) "ABI override probe must lower all parameters"
  require (plans[0]!.abiWord? == some "address")
    "address ABI override must survive the EVM plan boundary"
  require (plans[1]!.abiWord? == some "bytes4")
    "bytes4 ABI override must survive the EVM plan boundary"
  require (plans[2]!.abiWord?.isNone)
    "plain U64 parameter must remain override-free"
  let rendered := String.intercalate "\n"
    ((abiParamHeadValidationStatements plans).toList.map renderStatement)
  require
    (rendered.contains "gt(calldataload(4), 1461501637330902918203684832716283019655932542975)")
    s!"address override must use the 160-bit canonical guard, got: {rendered}"
  require
    (rendered.contains
      "and(calldataload(36), 26959946667150639794667015087019630673637144422540572481103610249215)")
    s!"bytes4 override must reject non-zero right padding, got: {rendered}"
  require
    (rendered.contains "gt(calldataload(68), 18446744073709551615)")
    s!"plain U64 parameters must retain their 64-bit guard, got: {rendered}"

def testConstructorUsesLowOrderPacking : IO Unit := do
  let state : StorageStatePlan := {
    id := "counter"
    slot := 3
    span := 0
    kind := .scalar
    type := .u8
    byteOffset := 1
    byteWidth := 1
  }
  let rendered := ProofForge.Backend.Evm.ConstructorInit.storePackedU64 state "value"
  require
    (rendered.contains "not(shl(8, 255))")
    s!"constructor packed clear mask must use the low-order byte offset, got: {rendered}"
  require
    (rendered.contains "shl(8, and(value, 255))")
    s!"constructor packed value must use the low-order byte offset, got: {rendered}"

def testWrappingFixtureMasksBeforeNeighborBits : IO Unit := do
  let module := ProofForge.IR.Examples.EvmPackedStorageProbe.module
  require
    (module.entrypoints.any (fun entrypoint => entrypoint.name == "packed_assign_op_wraps"))
    "packed storage fixture must expose the wrapping-width regression entrypoint"
  require
    (module.entrypoints.any
      (fun entrypoint => entrypoint.name == "packed_nested_checked_overflow_reverts"))
    "packed storage fixture must expose the nested checked regression entrypoint"
  require
    (module.entrypoints.any
      (fun entrypoint => entrypoint.name == "packed_mixed_overflow_reverts"))
    "packed storage fixture must expose the mixed-mode regression entrypoint"
  require
    (module.entrypoints.any
      (fun entrypoint => entrypoint.name == "packed_nested_wrapping_preserves_neighbors"))
    "packed storage fixture must expose the nested wrapping regression entrypoint"
  require
    (module.entrypoints.any
      (fun entrypoint => entrypoint.name == "packed_checked_mul_zero_rhs_succeeds"))
    "packed storage fixture must expose the checked multiply-zero regression entrypoint"
  let yul ←
    match ProofForge.Backend.Evm.IR.renderModule module with
    | .ok yul => pure yul
    | .error err => throw <| IO.userError s!"packed storage fixture render failed: {err.render}"
  require
    (yul.contains "and(add(255, 1), 255)")
    "wrapping packed expression fixture must truncate before shifting into its shared slot"
  require
    (yul.contains "and(sub(and(add(255, 1), 255), 1), 255)")
    "nested wrapping fixture must mask every U8 arithmetic node"
  require
    (yul.contains "f_EvmPackedStorageProbe_packed_assign_op_overflow_reverts")
    "packed storage fixture must expose the checked-width overflow regression entrypoint"
  require
    (yul.contains "f_EvmPackedStorageProbe_packed_checked_write_overflow_reverts")
    "packed storage fixture must expose the checked direct-write overflow regression entrypoint"
  require
    (yul.contains "f_EvmPackedStorageProbe_packed_checked_literal_write_overflow_reverts")
    "packed storage fixture must expose the checked literal-write regression entrypoint"
  require
    (yul.contains "f_EvmPackedStorageProbe_packed_checked_local_write_overflow_reverts")
    "packed storage fixture must expose the checked local-write regression entrypoint"
  require
    (yul.contains "f_EvmPackedStorageProbe_packed_checked_write_param")
    "packed storage fixture must expose the narrow calldata regression entrypoint"
  require
    (yul.contains "if gt(__pf_packed_value, 255)")
    "checked packed assign_op fixture must reject values above the field mask"
  require
    ((yul.splitOn "if gt(__pf_packed_value, 255)").length >= 3)
    "checked packed direct writes and assign_op must each guard the destination field width"
  require
    (yul.contains "let __pf_packed_value := __pf_checked_width(__pf_checked_add(")
    "checked packed direct writes must evaluate the checked expression once before the width guard"
  require
    (yul.contains "function __pf_checked_width(value, maxValue) -> result")
    "packed checked arithmetic must emit its shared width helper"
  require
    (yul.contains "let __pf_packed_value := 256")
    "checked packed literal writes must guard values without arithmetic"
  require
    (yul.contains "let __pf_packed_value := candidate")
    "checked packed local writes must guard values without arithmetic"
  require
    (yul.contains "if gt(calldataload(4), 255)")
    "u8 entrypoint calldata must reject non-canonical words"

def main : IO UInt32 := do
  testLowOrderReadAndMaskedWrite
  testCheckedAssignOpRejectsNarrowOverflow
  testWrappingAssignOpTruncatesToFieldWidth
  testDirectWriteSemanticsAreExplicit
  testLowerCarriesDirectWriteSemantics
  testNarrowArithmeticIsAppliedPerNode
  testNarrowAbiWordGuards
  testAbiWordOverridesDriveCanonicalGuards
  testConstructorUsesLowOrderPacking
  testWrappingFixtureMasksBeforeNeighborBits
  IO.println "evm-packed-storage: ok"
  return 0

end ProofForge.Tests.EvmPackedStorage

def main : IO UInt32 :=
  ProofForge.Tests.EvmPackedStorage.main
