import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Diagnostic
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.Lower
import ProofForge.Backend.SharedValidate
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Compiler.Yul.AST
import ProofForge.Compiler.Yul.Printer

/-! # EVM IR validation common helpers

Shared error, ABI, local-environment, storage, struct, and aggregate helper logic
used by the legacy EVM IR validation and lowering modules.
-/

namespace ProofForge.Backend.Evm.IR

open ProofForge.Backend.Evm.Plan
open ProofForge.Backend.Evm.Validate (needsCheckedArithmetic exprUsesCheckedArithmetic)
open ProofForge.IR
open ProofForge.Target
open ProofForge.Backend.Evm.Validate
open ProofForge.Backend.Evm.ToYul
open ProofForge.Backend.Evm.Lower
open ProofForge.Backend.Evm.Plan

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

instance : ProofForge.Backend.Diagnostic.LoweringError LowerError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "evm" }

def diagnosticError (err : Diagnostic) : LowerError := {
  message := err.render
}

def planError (err : ProofForge.Backend.Evm.Plan.PlanError) : LowerError := {
  message := err.render
}

def toYulError (message : String) : LowerError := {
  message
}

def lowerPlan
    {α : Type}
    (result : Except ProofForge.Backend.Evm.Plan.PlanError α) : Except LowerError α :=
  match result with
  | .ok value => .ok value
  | .error err => .error (planError err)

def lowerValidate
    {α : Type}
    (result : Except ProofForge.Backend.Evm.Validate.LowerError α) : Except LowerError α :=
  match result with
  | .ok value => .ok value
  | .error err => .error { message := err.message }

def stateInfo? (module : Module) (stateId : String) : Option (Nat × StateDecl) :=
  ProofForge.Backend.Evm.Plan.stateInfo? module stateId

def stateSlot? (module : Module) (stateId : String) : Option Nat :=
  match stateInfo? module stateId with
  | some (slot, _) => some slot
  | none => none

def slotExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.num slot

def yulFunctionName (moduleName entrypointName : String) : String :=
  ProofForge.Backend.Evm.ToYul.entrypointFunctionName moduleName entrypointName

def ensureIndexedEventFieldType
    (module : Module)
    (eventName fieldName : String)
    (type : ValueType) : Except LowerError Unit := do
  discard <| lowerValidate <| ProofForge.Backend.Evm.Validate.eventSignatureFieldType module eventName fieldName type

def storagePathMapKeys? (path : Array StoragePathSegment) : Option (Array ProofForge.IR.Expr) :=
  if path.isEmpty then
    none
  else
    path.foldl (init := some #[]) fun acc segment =>
      match acc, segment with
      | some keys, .mapKey key => some (keys.push key)
      | _, _ => none

def revertStmt : Lean.Compiler.Yul.Statement :=
  ProofForge.Backend.Evm.ToYul.revertStatement

def eip1967ImplementationSlotExpr : Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.eip1967ImplementationSlotExpr

def uupsProxyFallbackBody : Array Lean.Compiler.Yul.Statement :=
  ProofForge.Backend.Evm.ToYul.uupsProxyFallbackBody

def uupsProxyDefaultCase : Lean.Compiler.Yul.Case :=
  ProofForge.Backend.Evm.ToYul.dispatchDefaultCase .uupsProxy

/-- Lower-level checked-add expression: `__pf_checked_add(a, b)` reverts on overflow. -/
def checkedAddExpr (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.checkedArithExpr .add lhs rhs

/-- Lower-level checked-sub expression: reverts on underflow. -/
def checkedSubExpr (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.checkedArithExpr .sub lhs rhs

/-- Lower-level checked-mul expression: reverts on overflow. -/
def checkedMulExpr (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.checkedArithExpr .mul lhs rhs

def nibbleToHex (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + (n - 10))

def byteToHex (b : UInt8) : String :=
  let n := b.toNat
  String.ofList [nibbleToHex (n / 16), nibbleToHex (n % 16)]

def stringToHex (s : String) : String :=
  s.toUTF8.toList.map byteToHex |>.foldl (· ++ ·) ""

/-- Parse 8 hex digits (no `0x`) into a Nat selector value, or none. -/
def parseSoliditySelectorHex (hex : String) : Option Nat :=
  if hex.length != 8 then none
  else
    let rec go (i : Nat) (acc : Nat) : Option Nat :=
      if i ≥ hex.length then some acc
      else
        let c := hex.data[i]!
        let d? :=
          if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
          else if 'a' ≤ c ∧ c ≤ 'f' then some (10 + c.toNat - 'a'.toNat)
          else if 'A' ≤ c ∧ c ≤ 'F' then some (10 + c.toNat - 'A'.toNat)
          else none
        match d? with
        | none => none
        | some d => go (i + 1) (acc * 16 + d)
    go 0 0

/-- Solidity custom-error revert: 4-byte selector + optional ABI static words (E1.1).
    Layout: `mstore(0, shl(224, selector)); mstore(4, w0); mstore(36, w1); …; revert(0, 4+32*n)`. -/
def solidityCustomErrorRevertStmts (selector : Nat) (argWords : Array Nat := #[]) :
    Array Lean.Compiler.Yul.Statement :=
  let selectorWord :=
    Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num 224,
      Lean.Compiler.Yul.Expr.num selector
    ]
  let header : Array Lean.Compiler.Yul.Statement := #[
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, selectorWord])
  ]
  let argStmts :=
    argWords.foldl (init := (#[] : Array Lean.Compiler.Yul.Statement)) fun acc word =>
      let offset := 4 + acc.size * 32
      acc.push <| .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num offset,
        Lean.Compiler.Yul.Expr.num word
      ])
  let totalSize := 4 + argWords.size * 32
  header ++ argStmts ++ #[
    .exprStmt (Lean.Compiler.Yul.builtin "revert" #[
      Lean.Compiler.Yul.Expr.num 0,
      Lean.Compiler.Yul.Expr.num totalSize
    ])
  ]

/-- Solidity custom-error revert with runtime expression arguments.
    Each `Expr` is lowered via `lowerExpr` to a Yul value and stored at the
    corresponding ABI word offset. The selector is still compile-time. -/
def solidityCustomErrorRevertStmtsRuntime
    {ε : Type} (_mkError : String → ε)
    (lowerExpr : ProofForge.IR.Expr → Except ε Lean.Compiler.Yul.Expr)
    (selector : Nat) (argExprs : Array ProofForge.IR.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  let selectorWord :=
    Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num 224,
      Lean.Compiler.Yul.Expr.num selector
    ]
  let header : Array Lean.Compiler.Yul.Statement := #[
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, selectorWord])
  ]
  let mut argStmts : Array Lean.Compiler.Yul.Statement := #[]
  for expr in argExprs do
    let offset := 4 + argStmts.size * 32
    let yulExpr ← lowerExpr expr
    argStmts := argStmts.push <|
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num offset,
        yulExpr
      ])
  let totalSize := 4 + argExprs.size * 32
  .ok (header ++ argStmts ++ #[
    .exprStmt (Lean.Compiler.Yul.builtin "revert" #[
      Lean.Compiler.Yul.Expr.num 0,
      Lean.Compiler.Yul.Expr.num totalSize
    ])
  ])

def errorRefRevertStmts (ref : ProofForge.IR.ErrorRef) : Array Lean.Compiler.Yul.Statement :=
  match ref.soliditySelector? with
  | some hex =>
      match parseSoliditySelectorHex hex with
      | some sel => solidityCustomErrorRevertStmts sel ref.solidityArgWords
      | none =>
          -- The public lowering paths reject this in validateSolidityErrorRef.
          -- Keep the legacy defensive branch reverting with the PF envelope if
          -- an internal caller invokes this helper without validation.
          let code := ref.userCode?.getD ""
          let codeLen := code.length
          let paddedLen := ((codeLen + 31) / 32) * 32
          let totalSize := 96 + paddedLen
          #[
            .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num ref.assertionId.toNat]),
            .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.num 64]),
            .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.num codeLen]),
            .exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num totalSize])
          ]
  | none =>
      let code := ref.userCode?.getD ""
      let codeLen := code.length
      let paddedLen := ((codeLen + 31) / 32) * 32
      let totalSize := 96 + paddedLen
      let headerStmts : Array Lean.Compiler.Yul.Statement := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num ref.assertionId.toNat]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.num 64]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.num codeLen])
      ]
      let chunks := if codeLen > 0 then ProofForge.Backend.Evm.ToYul.hexChunks64 (stringToHex code) else #[]
      let dataStmts := chunks.foldl (init := #[]) fun acc chunk =>
        let idx := acc.size
        acc.push <| .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num (96 + idx * 32),
          Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex ("0x" ++ ProofForge.Backend.Evm.ToYul.rightPadHex64 chunk))
        ])
      headerStmts ++ dataStmts ++ #[
        .exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num totalSize])
      ]

/-- Runtime-expression version of `errorRefRevertStmts`. When
    `ref.solidityArgExprs` is non-empty, each expression is lowered via
    `lowerExpr` to a Yul value. Falls back to `errorRefRevertStmts` (compile-time
    path) when `solidityArgExprs` is empty. -/
def errorRefRevertStmtsRuntime
    {ε : Type} (mkError : String → ε)
    (lowerExpr : ProofForge.IR.Expr → Except ε Lean.Compiler.Yul.Expr)
    (ref : ProofForge.IR.ErrorRef) :
    Except ε (Array Lean.Compiler.Yul.Statement) :=
  if ref.solidityArgExprs.isEmpty then
    .ok (errorRefRevertStmts ref)
  else
    match ref.soliditySelector? with
    | some hex =>
        match parseSoliditySelectorHex hex with
        | some sel => solidityCustomErrorRevertStmtsRuntime mkError lowerExpr sel ref.solidityArgExprs
        | none =>
            .error (mkError
              s!"errorRefRevertStmtsRuntime: invalid selector `{hex}` for runtime error args")
    | none =>
        .error (mkError
          "errorRefRevertStmtsRuntime: runtime error args require a Solidity selector")

def calldataWordExpr (paramIndex : Nat) : Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.calldataWordExpr paramIndex

-- Dynamic ABI type support: bytes and string use head-tail encoding.
-- The head contains an offset to the tail where (length, data) is stored.

def isDynamicAbiType : ValueType → Bool
  | type => ProofForge.Backend.Evm.Plan.abiTypeIsDynamic type

-- Yul expression to load a word from calldata at a byte offset.
def calldataloadAt (offset : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.calldataloadAt offset

-- Names for dynamic parameter locals (length and memory pointer).
def dynamicParamLengthName (name : String) : String :=
  ProofForge.Backend.Evm.ToYul.dynamicParamLengthName name

def dynamicParamDataPtrName (name : String) : String :=
  ProofForge.Backend.Evm.ToYul.dynamicParamDataPtrName name
def arrayLocalElementName (name : String) (index : Nat) : String :=
  ProofForge.Backend.Evm.ToYul.arrayLocalElementName name index

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.ToYul.arrayStructLocalFieldName name index fieldName

def natPathSuffix (path : Array Nat) : String :=
  ProofForge.Backend.Evm.ToYul.natPathSuffix path

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  ProofForge.Backend.Evm.ToYul.arrayLocalPathName name path

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.ToYul.arrayStructLocalPathFieldName name path fieldName

def localArrayGetFunctionName (length : Nat) : String :=
  ProofForge.Backend.Evm.ToYul.localArrayGetFunctionName length

def nestedLocalArrayGetFunctionName (lengths : Array Nat) : String :=
  ProofForge.Backend.Evm.ToYul.nestedLocalArrayGetFunctionName lengths

partial def nestedLocalArrayLeafPaths (lengths : Array Nat) : Array (Array Nat) :=
  ProofForge.Backend.Evm.ToYul.nestedLocalArrayLeafPaths lengths

def structLocalFieldName (name fieldName : String) : String :=
  ProofForge.Backend.Evm.ToYul.structLocalFieldName name fieldName

def abiReturnName (index : Nat) : String :=
  ProofForge.Backend.Evm.Plan.abiReturnName index

def ensureAbiWordType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} has unsupported EVM IR v0 ABI word type `{type.name}`; ABI aggregate words support U32, U64, Bool, Hash, or Address"
      }

def ensureCrosscallWordType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} has unsupported EVM IR v0 crosscall word type `{type.name}`; crosscall scalar words support U32, U64, Bool, Hash, or Address"
      }

def isCrosscallWordType : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def abiStructWordTypes (module : Module) (context typeName : String) : Except LowerError (Array ValueType) := do
  let some decl := module.structs.find? fun decl => decl.name == typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; IR EVM v0 ABI structs must have at least one field" }
  let mut words : Array ValueType := #[]
  for field in decl.fields do
    ensureAbiWordType s!"{context} struct `{typeName}` field `{field.id}`" field.type
    words := words.push field.type
  .ok words

def crosscallStructWordTypes (module : Module) (context typeName : String) : Except LowerError (Array ValueType) := do
  let some decl := module.structs.find? fun decl => decl.name == typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; IR EVM v0 crosscall structs must have at least one field" }
  let mut words : Array ValueType := #[]
  for field in decl.fields do
    ensureCrosscallWordType s!"{context} struct `{typeName}` field `{field.id}`" field.type
    words := words.push field.type
  .ok words

partial def abiNestedFixedArrayWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .u8 => .ok #[.u8]
  | .u128 => .ok #[.u128]
  | .bytes | .string | .array _ =>
      .error { message := s!"{context} uses a dynamic type; IR EVM v0 ABI nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 ABI nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length" }
      let elementWords ← abiNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      abiStructWordTypes module context typeName

partial def abiValueWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .u8 => .ok #[.u8]
  | .u128 => .ok #[.u128]
  | .bytes => .ok #[.bytes]
  | .string => .ok #[.string]
  | .array _ =>
      .error { message := s!"{context} uses a dynamic array; IR EVM v0 ABI values do not yet support dynamic arrays" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 ABI values must use U32, U64, Bool, Hash, Address, Bytes, String, fixed arrays, or structs" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length" }
      let elementWords ←
        match elementType with
        | .fixedArray _ _ =>
            abiNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
        | .structType _ =>
            abiValueWordTypes module s!"{context} fixed-array element" elementType
        | _ => do
            ensureAbiWordType s!"{context} fixed-array element" elementType
            .ok #[elementType]
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      abiStructWordTypes module context typeName

-- Number of static head words a parameter occupies.
-- Static types: 1 word. Dynamic types: 1 word (the offset).
-- Fixed arrays and structs: their flattened word count (all must be static in v0).
def abiParamHeadWordCount (module : Module) (context : String) (type : ValueType) : Except LowerError Nat := do
  if isDynamicAbiType type then
    .ok 1
  else
    let words ← abiValueWordTypes module context type
    .ok words.size

partial def crosscallNestedFixedArrayWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .u8 => .ok #[.u8]
  | .u128 => .ok #[.u128]
  | .bytes | .string | .array _ =>
      .error { message := s!"{context} uses a dynamic type; IR EVM v0 crosscall nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 crosscall nested fixed arrays must have U32, U64, Bool, Hash, Address, or flat struct leaves" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 crosscall fixed arrays must have non-zero length" }
      let elementWords ← crosscallNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      crosscallStructWordTypes module context typeName

partial def crosscallValueWordTypes (module : Module) (context : String) : ValueType → Except LowerError (Array ValueType)
  | .u32 => .ok #[.u32]
  | .u64 => .ok #[.u64]
  | .bool => .ok #[.bool]
  | .hash => .ok #[.hash]
  | .address => .ok #[.address]
  | .u8 => .ok #[.u8]
  | .u128 => .ok #[.u128]
  | .bytes | .string | .array _ =>
      .error { message := s!"{context} uses a dynamic type; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, Address, fixed arrays, or structs" }
  | .unit =>
      .error { message := s!"{context} uses Unit; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, Address, fixed arrays, or structs" }
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} uses Array<{elementType.name},0>; IR EVM v0 crosscall fixed arrays must have non-zero length" }
      let elementWords ←
        match elementType with
        | .fixedArray _ _ =>
            crosscallNestedFixedArrayWordTypes module s!"{context} fixed-array element" elementType
        | .structType _ =>
            crosscallValueWordTypes module s!"{context} fixed-array element" elementType
        | _ => do
            ensureCrosscallWordType s!"{context} fixed-array element" elementType
            .ok #[elementType]
      let mut words : Array ValueType := #[]
      for _h : _idx in [0:length] do
        words := words ++ elementWords
      .ok words
  | .structType typeName =>
      crosscallStructWordTypes module context typeName

def crosscallReturnWordTypes (module : Module) (context : String) (returnType : ValueType) : Except LowerError (Array ValueType) := do
  if isCrosscallWordType returnType then
    .ok #[returnType]
  else
    crosscallValueWordTypes module context returnType

def crosscallArgWordTypes (module : Module) (context : String) (type : ValueType) : Except LowerError (Array ValueType) :=
  crosscallValueWordTypes module context type

partial def abiValueParamNamesAt
    (module : Module)
    (context name : String)
    (path : Array Nat) : ValueType → Except LowerError (Array String)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .bytes | .string | .array _ =>
      if path.isEmpty then
        .ok #[name]
      else
        .ok #[arrayLocalPathName name path]
  | .unit => do
      discard <| abiValueWordTypes module context .unit
      .ok #[]
  | .fixedArray elementType length => do
      discard <| abiValueWordTypes module context (.fixedArray elementType length)
      let mut names : Array String := #[]
      for _h : index in [0:length] do
        names := names ++ (← abiValueParamNamesAt module context name (path.push index) elementType)
      .ok names
  | .structType typeName => do
      discard <| abiValueWordTypes module context (.structType typeName)
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error { message := s!"{context} uses unknown struct `{typeName}`" }
      .ok (decl.fields.map fun field =>
        if path.isEmpty then
          structLocalFieldName name field.id
        else
          arrayStructLocalPathFieldName name path field.id)

def abiValueParamNames
    (module : Module)
    (context name : String)
    (type : ValueType) : Except LowerError (Array String) :=
  abiValueParamNamesAt module context name #[] type

def lowerEntrypointParams (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.TypedName) :=
  match ProofForge.Backend.Evm.Lower.entrypointParamPlans module entrypoint with
  | .ok params => .ok (ProofForge.Backend.Evm.ToYul.entrypointParamTypedNames params)
  | .error err => .error { message := err.message }
-- Static-only word types for entrypoint params (excludes dynamic types).
-- Used for calldata size validation.
def entrypointStaticParamWordTypes (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array ValueType) := do
  let mut words : Array ValueType := #[]
  for param in entrypoint.params do
    if isDynamicAbiType param.snd then
      -- Dynamic params contribute one head word (the offset)
      words := words.push param.snd
    else
      words := words ++ (← abiValueWordTypes module s!"entrypoint `{entrypoint.name}` parameter `{param.fst}`" param.snd)
  .ok words

def entrypointParamPlansForModule
    (module : Module)
    (entrypoint : Entrypoint) :
    Except LowerError (Array ProofForge.Backend.Evm.Plan.AbiParamPlan) := do
  match ProofForge.Backend.Evm.Lower.entrypointParamPlans module entrypoint with
  | .ok params => .ok params
  | .error err => .error { message := err.message }

def entrypointCallArgsWithPlan
    (params : Array ProofForge.Backend.Evm.Plan.AbiParamPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Expr) :=
  .ok (ProofForge.Backend.Evm.ToYul.entrypointCallArgs params)

def entrypointCallArgs (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  let params ← entrypointParamPlansForModule module entrypoint
  entrypointCallArgsWithPlan params

-- Generate calldata size check and per-word validation for static params,
-- plus head-tail decode statements for dynamic params (bytes/string).
-- Returns (validationStmts, dynamicDecodeStmts) — both run before the call.
def abiParamValidationAndDecodeStmts
    (params : Array ProofForge.Backend.Evm.Plan.AbiParamPlan) :
    Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  .ok (ProofForge.Backend.Evm.ToYul.abiParamValidationAndDecodeStatements params)

-- Backward-compatible wrapper: only returns validation (no dynamic decode).
-- The full validation+decode is in abiParamValidationAndDecodeStmts.
def abiParamValidationStmts (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let params ← entrypointParamPlansForModule module entrypoint
  .ok (ProofForge.Backend.Evm.ToYul.abiParamsMinSizeValidationStatements params)



def mapShapeName (keyType valueType : ValueType) (capacity : Nat) : String :=
  s!"Map<{keyType.name}, {valueType.name}, {capacity}>"

def isStorageWordType : ValueType → Bool
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def requireStorageMapState (module : Module) (stateId : String) : Except LowerError (Nat × ValueType × ValueType) :=
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown map state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .map keyType capacity, valueType =>
          if isStorageWordType keyType && isStorageWordType valueType then
            .ok (slot, keyType, valueType)
          else
            .error {
              message := s!"map state `{stateId}` has unsupported EVM IR v0 type `{mapShapeName keyType valueType capacity}`; storage maps support key/value word types U32, U64, Bool, or Hash"
            }
      | .scalar, _ => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
      | .array _, _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
      | .dynamicArray, _ => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

def requireStorageArrayState (module : Module) (stateId : String) : Except LowerError (Nat × Nat × ValueType) :=
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown array state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .array length, elementType => do
          if length == 0 then
            .error { message := s!"array state `{stateId}` must have non-zero length" }
          else if isStorageWordType elementType then
            .ok (slot, length, elementType)
          else
            match elementType with
            | .structType _ =>
                .error { message := s!"array state `{stateId}` is struct storage; use storage.array.struct.field.read/write" }
            | other =>
                .error { message := s!"array state `{stateId}` has unsupported EVM IR v0 element type `{other.name}`; storage arrays support U32, U64, Bool, Hash, or flat struct arrays" }
      | .scalar, _ => .error { message := s!"state `{stateId}` is scalar storage, not an array" }
      | .map _ _, _ => .error { message := s!"state `{stateId}` is map storage, not an array" }
      | .dynamicArray, _ => .error { message := s!"state `{stateId}` is dynamic array storage; IR EVM v0 does not yet support dynamic array storage" }

structure LocalBinding where
  name : String
  type : ValueType
  isMutable : Bool
  deriving Repr

abbrev TypeEnv := Array LocalBinding

def toValidateLocalBinding (binding : LocalBinding) :
    ProofForge.Backend.Evm.Validate.LocalBinding := {
  name := binding.name
  type := binding.type
  isMutable := binding.isMutable
}

def toValidateTypeEnv (env : TypeEnv) :
    ProofForge.Backend.Evm.Validate.TypeEnv :=
  env.map toValidateLocalBinding

def findLocal? (env : TypeEnv) (name : String) : Option LocalBinding :=
  env.find? fun binding => binding.name == name

def addLocal (env : TypeEnv) (name : String) (type : ValueType) (isMutable : Bool) : Except LowerError TypeEnv :=
  if (findLocal? env name).isSome then
    .error { message := s!"duplicate local `{name}`" }
  else
    .ok (env.push { name, type, isMutable })

def ensureType (context : String) (expected actual : ValueType) : Except LowerError Unit :=
  match ProofForge.Backend.SharedValidate.ensureType context expected actual with
  | .ok _ => .ok ()
  | .error diag => .error { message := diag.message }

/-- Portable contract / method handles: `U64` words or portable identity `Address`. -/
def ensureCrosscallHandleType (context : String) (actual : ValueType) : Except LowerError Unit :=
  match actual with
  | .u64 | .address => .ok ()
  | _ =>
      .error {
        message :=
          s!"{context} expected `U64` or `Address` (portable handle), got `{actual.name}`"
      }

def ensureNumericType (context : String) (lhs rhs : ValueType) : Except LowerError ValueType :=
  match lhs, rhs with
  | .u8, .u8 => .ok .u8
  | .u32, .u32 => .ok .u32
  | .u64, .u64 => .ok .u64
  | .u128, .u128 => .ok .u128
  | _, _ => .error { message := s!"{context} expects matching numeric operands, got `{lhs.name}` and `{rhs.name}`" }

def ensureArrayIndexType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 => .ok ()
  | _ => .error { message := s!"{context} expected U32 or U64 index, got `{type.name}`" }

def literalArrayIndex? : ProofForge.IR.Expr → Option Nat
  | .literal (.u32 value) => some value
  | .literal (.u64 value) => some value
  | _ => none

def requireStaticArrayIndex (context : String) (index : ProofForge.IR.Expr) : Except LowerError Nat :=
  match literalArrayIndex? index with
  | some value => .ok value
  | none =>
      .error {
        message := s!"{context} in IR EVM v0 requires a U32/U64 literal index for local fixed-array values"
      }

def requireLocalFixedArray
    (context : String)
    (env : TypeEnv)
    (name : String) : Except LowerError (ValueType × Nat) :=
  match findLocal? env name with
  | none => .error { message := s!"unknown local `{name}`" }
  | some binding =>
      match binding.type with
      | .fixedArray elementType length => .ok (elementType, length)
      | other => .error { message := s!"{context} local `{name}` expected fixed-array value, got `{other.name}`" }

def ensureFixedArrayIndexInBounds (context : String) (index length : Nat) : Except LowerError Unit :=
  if index < length then
    .ok ()
  else
    .error { message := s!"{context} {index} is out of bounds for length {length}" }

partial def collectStaticLocalArrayGetPath : ProofForge.IR.Expr → Option (String × Array Nat)
  | .arrayGet (.local name) index =>
      match literalArrayIndex? index with
      | some indexValue => some (name, #[indexValue])
      | none => none
  | .arrayGet array index =>
      match collectStaticLocalArrayGetPath array, literalArrayIndex? index with
      | some (name, path), some indexValue => some (name, path.push indexValue)
      | _, _ => none
  | _ => none

partial def collectLocalArrayGetPath : ProofForge.IR.Expr → Option (String × Array ProofForge.IR.Expr)
  | .arrayGet (.local name) index => some (name, #[index])
  | .arrayGet array index =>
      match collectLocalArrayGetPath array with
      | some (name, path) => some (name, path.push index)
      | none => none
  | _ => none

partial def collectLocalArrayFieldGetPath : ProofForge.IR.Expr → Option (String × Array ProofForge.IR.Expr × String)
  | .field base fieldName =>
      match collectLocalArrayGetPath base with
      | some (name, path) => some (name, path, fieldName)
      | none => none
  | _ => none

def arrayIndexPathHasDynamic (path : Array ProofForge.IR.Expr) : Bool :=
  path.any fun index => (literalArrayIndex? index).isNone

partial def fixedArrayPathType
    (context : String)
    (type : ValueType)
    (path : Array Nat) : Except LowerError ValueType :=
  match path.toList with
  | [] => .ok type
  | index :: rest =>
      match type with
      | .fixedArray elementType length => do
          ensureFixedArrayIndexInBounds context index length
          fixedArrayPathType context elementType rest.toArray
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

partial def fixedArrayPathShape
    (context : String)
    (type : ValueType)
    (path : Array ProofForge.IR.Expr) : Except LowerError (Array Nat × ValueType) := do
  match path.toList with
  | [] => .ok (#[], type)
  | _ :: rest =>
      match type with
      | .fixedArray elementType length => do
          let (nested, leafType) ← fixedArrayPathShape context elementType rest.toArray
          .ok (#[length] ++ nested, leafType)
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

def assignOpDiagnosticName : AssignOp → String
  | .add => "addition"
  | .sub => "subtraction"
  | .mul => "multiplication"
  | .div => "division"
  | .mod => "modulo"
  | .bitAnd => "bitwise and"
  | .bitOr => "bitwise or"
  | .bitXor => "bitwise xor"
  | .shiftLeft => "shift-left"
  | .shiftRight => "shift-right"

def assignOpBuiltinName : AssignOp → String
  | .add => "add"
  | .sub => "sub"
  | .mul => "mul"
  | .div => "div"
  | .mod => "mod"
  | .bitAnd => "and"
  | .bitOr => "or"
  | .bitXor => "xor"
  | .shiftLeft => "shl"
  | .shiftRight => "shr"

def ensureAssignOpTypes (op : AssignOp) (targetType valueType : ValueType) : Except LowerError Unit := do
  discard <| ensureNumericType s!"compound assignment {assignOpDiagnosticName op}" targetType valueType

def lowerAssignOpExpr
    (op : AssignOp)
    (target value : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  match op with
  | .shiftLeft | .shiftRight =>
      Lean.Compiler.Yul.builtin (assignOpBuiltinName op) #[value, target]
  | .add => checkedAddExpr target value
  | .sub => checkedSubExpr target value
  | .mul => checkedMulExpr target value
  | _ =>
      Lean.Compiler.Yul.builtin (assignOpBuiltinName op) #[target, value]

def ensureEqType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .bool | .u8 | .u32 | .u64 | .u128 | .hash | .address => .ok ()
  | .unit => .error { message := s!"{context} does not support Unit equality" }
  | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error { message := s!"{context} does not support `{type.name}` equality in IR EVM v0" }

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u8, .u8 | .u8, .u32 | .u8, .u64 | .u8, .u128 | .u8, .bool => .ok ()
  | .u32, .u8 | .u32, .u32 | .u32, .u64 | .u32, .u128 | .u32, .bool => .ok ()
  | .u64, .u8 | .u64, .u32 | .u64, .u64 | .u64, .u128 | .u64, .bool
  | .u64, .address => .ok ()
  | .u128, .u8 | .u128, .u32 | .u128, .u64 | .u128, .u128 => .ok ()
  | .bool, .u8 | .bool, .u32 | .bool, .u64 | .bool, .u128 | .bool, .bool => .ok ()
  | .address, .address | .address, .u64 | .hash, .address | .address, .hash | .hash, .hash => .ok ()
  | _, _ =>
      .error { message := s!"cast from `{source.name}` to `{target.name}` is not supported by IR EVM v0" }

def stateDeclOf (module : Module) (stateId kind : String) : Except LowerError StateDecl :=
  match stateInfo? module stateId with
  | some (_, state) => .ok state
  | none => .error { message := s!"unknown {kind} state `{stateId}`" }

def scalarStateType (module : Module) (stateId : String) : Except LowerError ValueType := do
  let state ← stateDeclOf module stateId "scalar"
  match state.kind with
  | .scalar => .ok state.type
  | .map _ _ => .error { message := s!"state `{stateId}` is a map, not scalar storage" }
  | .array _ => .error { message := s!"state `{stateId}` is an array, not scalar storage" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not scalar storage" }

def scalarStatePacking (module : Module) (stateId : String) : Except LowerError (Nat × Nat) := do
  if stateId == "$eip1967.implementation" then
    .ok (0, 32)
  else
    match ProofForge.Backend.Evm.Plan.storageLayout module |>.find? stateId with
    | some plan => .ok (plan.byteOffset, plan.byteWidth)
    | none => .error { message := s!"unknown EVM state '{stateId}'" }

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }
  | .dynamicArray => .error { message := s!"state `{stateId}` is dynamic array storage, not a map" }

def findStruct? (module : Module) (name : String) : Option StructDecl :=
  module.structs.find? fun decl => decl.name == name

def findStructField? (decl : StructDecl) (fieldName : String) : Option StructField :=
  decl.fields.find? fun field => field.id == fieldName

def findStructFieldWithOffset? (decl : StructDecl) (fieldName : String) : Option (Nat × StructField) :=
  Id.run do
    let mut found : Option (Nat × StructField) := none
    for h : idx in [0:decl.fields.size] do
      if found.isNone then
        let field := decl.fields[idx]
        if field.id == fieldName then
          found := some (idx, field)
    found

def ensureStructLocalFieldType (structName fieldName : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error {
        message := s!"field `{fieldName}` in struct `{structName}` has unsupported EVM IR v0 local struct field type `{type.name}`; local structs support U32, U64, Bool, or Hash fields"
      }

def ensureLocalFlatStructType (module : Module) (context typeName : String) : Except LowerError StructDecl := do
  let some decl := findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; local fixed arrays of structs require at least one field" }
  for field in decl.fields do
    ensureStructLocalFieldType typeName field.id field.type
  .ok decl

partial def ensureLocalNestedFixedArrayValueType
    (module : Module)
    (context name : String) : ValueType → Except LowerError Unit
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address => .ok ()
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} `{name}` nested fixed-array leaf" typeName
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} `{name}` nested fixed array must have non-zero length in IR EVM v0" }
      else
        pure ()
      ensureLocalNestedFixedArrayValueType module context name elementType
  | .unit | .bytes | .string | .array _ =>
      .error {
        message := s!"{context} `{name}` has unsupported EVM IR v0 nested fixed-array leaf type; nested local fixed arrays support U32, U64, Bool, Hash, Address, or flat struct leaves"
      }

def structFieldType (module : Module) (typeName fieldName : String) : Except LowerError ValueType := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  let some field := findStructField? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  .ok field.type

def requireLocalFixedStructArrayField
    (module : Module)
    (env : TypeEnv)
    (context name fieldName : String) : Except LowerError (String × Nat × ValueType) := do
  let (elementType, length) ← requireLocalFixedArray context env name
  match elementType with
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} local `{name}` element" typeName
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      .ok (typeName, length, fieldType)
  | other =>
      .error { message := s!"{context} local `{name}` expected fixed-array struct element, got `{other.name}`" }

def requireStructState
    (module : Module)
    (stateId : String) : Except LowerError (Nat × String × StructDecl) := do
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown struct state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .scalar, .structType typeName => do
          let some decl := findStruct? module typeName
            | .error { message := s!"state `{stateId}` uses unknown struct `{typeName}`" }
          if decl.fields.isEmpty then
            .error { message := s!"state `{stateId}` uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
          for field in decl.fields do
            ensureStructLocalFieldType typeName field.id field.type
          .ok (slot, typeName, decl)
      | .scalar, other =>
          .error { message := s!"state `{stateId}` has unsupported EVM IR v0 struct storage type `{other.name}`; expected struct storage" }
      | .array _, _ =>
          .error { message := s!"state `{stateId}` is array storage, not scalar struct storage" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not scalar struct storage" }
      | .dynamicArray, _ =>
          .error { message := s!"state `{stateId}` is dynamic array storage, not scalar struct storage" }

def requireStructStateField
    (module : Module)
    (stateId fieldName : String) : Except LowerError (Nat × StructField) := do
  let (slot, typeName, decl) ← requireStructState module stateId
  let some (offset, field) := findStructFieldWithOffset? decl fieldName
    | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
  ensureStructLocalFieldType typeName field.id field.type
  .ok (slot + offset, field)

def requireStructArrayStateField
    (module : Module)
    (stateId fieldName : String) : Except LowerError (Nat × Nat × Nat × Nat × StructField) := do
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown struct array state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .array length, .structType typeName => do
          if length == 0 then
            .error { message := s!"array state `{stateId}` must have non-zero length" }
          let some decl := findStruct? module typeName
            | .error { message := s!"array state `{stateId}` uses unknown struct `{typeName}`" }
          let some (offset, field) := findStructFieldWithOffset? decl fieldName
            | .error { message := s!"struct `{typeName}` has no field `{fieldName}`" }
          ensureStructLocalFieldType typeName field.id field.type
          .ok (slot, length, decl.fields.size, offset, field)
      | .array _, other =>
          .error { message := s!"array state `{stateId}` has unsupported EVM IR v0 struct element type `{other.name}`; expected struct storage array" }
      | .scalar, _ =>
          .error { message := s!"state `{stateId}` is scalar storage, not a struct array" }
      | .map _ _, _ =>
          .error { message := s!"state `{stateId}` is map storage, not a struct array" }
      | .dynamicArray, _ =>
          .error { message := s!"state `{stateId}` is dynamic array storage, not a struct array" }

def lowerStructStorageReadFields
    (module : Module)
    (context typeName stateId : String) : Except LowerError (Array (String × Lean.Compiler.Yul.Expr)) := do
  let (slot, stateTypeName, decl) ← requireStructState module stateId
  ensureType context (.structType typeName) (.structType stateTypeName)
  let mut fields : Array (String × Lean.Compiler.Yul.Expr) := #[]
  for h : idx in [0:decl.fields.size] do
    let field := decl.fields[idx]
    ensureStructLocalFieldType typeName field.id field.type
    fields := fields.push (field.id, Lean.Compiler.Yul.builtin "sload" #[slotExpr (slot + idx)])
  .ok fields

def validateStructLiteralFields
    (module : Module)
    (typeName : String)
    (fields : Array (String × ProofForge.IR.Expr))
    (infer : ProofForge.IR.Expr → Except LowerError ValueType) : Except LowerError Unit := do
  if fields.isEmpty then
    .error { message := s!"struct literal `{typeName}` must have at least one field" }
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  if decl.fields.size != fields.size then
    .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
  for field in fields do
    let expected ← structFieldType module typeName field.fst
    ensureStructLocalFieldType typeName field.fst expected
    let actual ← infer field.snd
    ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
  for expectedField in decl.fields do
    if !(fields.any fun field => field.fst == expectedField.id) then
      .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }


end ProofForge.Backend.Evm.IR
