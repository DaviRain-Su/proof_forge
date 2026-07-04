import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Evm.Lower
import ProofForge.Backend.Evm.Metadata
import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Compiler.Yul.AST
import ProofForge.Compiler.Yul.Printer

namespace ProofForge.Backend.Evm.IR

open ProofForge.IR
open ProofForge.Target

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

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

def stateInfo? (module : Module) (stateId : String) : Option (Nat × StateDecl) :=
  go 0 0 module.state
where
  stateSlotSpan (state : StateDecl) : Nat :=
    match state.kind, state.type with
    | .scalar, .structType typeName =>
        match module.structs.find? (fun decl => decl.name == typeName) with
        | some decl => decl.fields.size
        | none => 1
    | .array length, .structType typeName =>
        match module.structs.find? (fun decl => decl.name == typeName) with
        | some decl => length * decl.fields.size
        | none => length
    | .array length, _ => length
    | .scalar, _ | .map _ _, _ => 1

  go (idx slot : Nat) (states : Array StateDecl) : Option (Nat × StateDecl) :=
    if h : idx < states.size then
      let state := states[idx]
      if state.id == stateId then
        some (slot, state)
      else
        go (idx + 1) (slot + stateSlotSpan state) states
    else
      none

def stateSlot? (module : Module) (stateId : String) : Option Nat :=
  match stateInfo? module stateId with
  | some (slot, _) => some slot
  | none => none

def slotExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.num slot

def yulFunctionName (moduleName entrypointName : String) : String :=
  s!"f_{moduleName}_{entrypointName}"

def mapSlotFunctionName : String := "__proof_forge_map_slot"
def mapPresenceSlotFunctionName : String := "__proof_forge_map_presence_slot"
def mapWriteFunctionName : String := "__proof_forge_map_write"
def mapSetReturnFunctionName : String := "__proof_forge_map_set_return"
def arraySlotFunctionName : String := "__proof_forge_array_slot"
def structArraySlotFunctionName : String := "__proof_forge_struct_array_slot"
def hashWordFunctionName : String := "__proof_forge_hash_word"
def hashPairFunctionName : String := "__proof_forge_hash_pair"
def crosscallReturnTypeSuffix : ValueType → Except LowerError String
  | .u64 => .ok ""
  | .u32 => .ok "_u32"
  | .bool => .ok "_bool"
  | .hash => .ok "_hash"
  | .address => .ok "_address"
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error { message := "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0" }

def crosscallFunctionName (arity : Nat) (returnType : ValueType) : Except LowerError String := do
  .ok s!"__proof_forge_crosscall_{arity}{← crosscallReturnTypeSuffix returnType}"

def crosscallValueFunctionName (arity : Nat) (returnType : ValueType) (plainTransfer : Bool := false) : Except LowerError String := do
  if plainTransfer then
    .ok s!"__proof_forge_native_transfer{← crosscallReturnTypeSuffix returnType}"
  else
    .ok s!"__proof_forge_crosscall_value_{arity}{← crosscallReturnTypeSuffix returnType}"

def crosscallStaticFunctionName (arity : Nat) (returnType : ValueType) : Except LowerError String := do
  .ok s!"__proof_forge_crosscall_static_{arity}{← crosscallReturnTypeSuffix returnType}"

def crosscallDelegateFunctionName (arity : Nat) (returnType : ValueType) : Except LowerError String := do
  .ok s!"__proof_forge_crosscall_delegate_{arity}{← crosscallReturnTypeSuffix returnType}"

def plainValueTransferMethodId? (methodId : ProofForge.IR.Expr) : Bool :=
  match methodId with
  | .literal (.u64 0) => true
  | _ => false

def plainValueTransferCall? (methodId : ProofForge.IR.Expr) (args : Array ProofForge.IR.Expr) : Bool :=
  plainValueTransferMethodId? methodId && args.isEmpty

def crosscallReturnWordTag : ValueType → Except LowerError String
  | .u64 => .ok "u64"
  | .u32 => .ok "u32"
  | .bool => .ok "bool"
  | .hash => .ok "hash"
  | .address => .ok "address"
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error { message := "crosscall aggregate return words must be U32, U64, Bool, or Hash in IR EVM v0" }

def crosscallReturnWordTagsSuffix (wordTypes : Array ValueType) : Except LowerError String := do
  let mut suffix := ""
  for wordType in wordTypes do
    suffix := suffix ++ "_" ++ (← crosscallReturnWordTag wordType)
  .ok suffix

def crosscallAggregateFunctionName (arity : Nat) (wordTypes : Array ValueType) : Except LowerError String := do
  .ok s!"__proof_forge_crosscall_{arity}_abi{← crosscallReturnWordTagsSuffix wordTypes}"

def crosscallValueAggregateFunctionName (arity : Nat) (wordTypes : Array ValueType) (plainTransfer : Bool := false) : Except LowerError String := do
  if plainTransfer then
    .error { message := "plain native transfer does not support aggregate crosscall returns in IR EVM v0" }
  else
    .ok s!"__proof_forge_crosscall_value_{arity}_abi{← crosscallReturnWordTagsSuffix wordTypes}"

def crosscallStaticAggregateFunctionName (arity : Nat) (wordTypes : Array ValueType) : Except LowerError String := do
  .ok s!"__proof_forge_crosscall_static_{arity}_abi{← crosscallReturnWordTagsSuffix wordTypes}"

def crosscallDelegateAggregateFunctionName (arity : Nat) (wordTypes : Array ValueType) : Except LowerError String := do
  .ok s!"__proof_forge_crosscall_delegate_{arity}_abi{← crosscallReturnWordTagsSuffix wordTypes}"

inductive CreateMode where
  | create
  | create2
  deriving BEq, Repr

def CreateMode.functionPrefix : CreateMode → String
  | .create => "__proof_forge_create_"
  | .create2 => "__proof_forge_create2_"

def CreateMode.opcode : CreateMode → String
  | .create => "create"
  | .create2 => "create2"

structure CreateHelperSpec where
  mode : CreateMode
  initCodeHex : String
  deriving BEq, Repr

def isHexChar (c : Char) : Bool :=
  ('0' <= c && c <= '9') ||
  ('a' <= c && c <= 'f') ||
  ('A' <= c && c <= 'F')

def stripHexPrefix (s : String) : String :=
  if s.startsWith "0x" || s.startsWith "0X" then
    (s.drop 2).toString
  else
    s

def normalizeInitCodeHex (context initCodeHex : String) : Except LowerError String := do
  let raw := stripHexPrefix initCodeHex
  if raw.isEmpty then
    .error { message := s!"{context} init code must be non-empty hex" }
  else if raw.length % 2 != 0 then
    .error { message := s!"{context} init code hex must have an even number of digits" }
  else if !(raw.all isHexChar) then
    .error { message := s!"{context} init code must contain only hex digits" }
  else
    .ok raw

def repeatString : Nat → String → String
  | 0, _ => ""
  | n+1, s => s ++ repeatString n s

def rightPadHex64 (chunk : String) : String :=
  chunk ++ repeatString (64 - chunk.length) "0"

partial def hexChunks64 (hex : String) : Array String :=
  if hex.isEmpty then
    #[]
  else
    let chunk := (hex.take 64).toString
    let rest := (hex.drop 64).toString
    #[chunk] ++ hexChunks64 rest

def createHelperFunctionName (mode : CreateMode) (initCodeHex : String) : Except LowerError String := do
  let hex ← normalizeInitCodeHex "contract creation" initCodeHex
  .ok s!"{mode.functionPrefix}{hex}"

def createCallValueParamName : String := "call_value"
def createSaltParamName : String := "salt"

def createHelperParams : CreateMode → Array Lean.Compiler.Yul.TypedName
  | .create => #[{ name := createCallValueParamName }]
  | .create2 => #[{ name := createCallValueParamName }, { name := createSaltParamName }]

def createInitCodeStoreStatements (initCodeHex : String) : Except LowerError (Array Lean.Compiler.Yul.Statement × Nat) := do
  let hex ← normalizeInitCodeHex "contract creation" initCodeHex
  let chunks := hexChunks64 hex
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:chunks.size] do
    let chunk := chunks[idx]
    statements := statements.push <| .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
      Lean.Compiler.Yul.Expr.num (idx * 32),
      Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex ("0x" ++ rightPadHex64 chunk))
    ])
  .ok (statements, hex.length / 2)

def createHelperFunction (spec : CreateHelperSpec) : Except LowerError Lean.Compiler.Yul.Statement := do
  let functionName ← createHelperFunctionName spec.mode spec.initCodeHex
  let (storeStatements, byteLength) ← createInitCodeStoreStatements spec.initCodeHex
  let createArgs :=
    match spec.mode with
    | .create =>
        #[
          Lean.Compiler.Yul.Expr.id createCallValueParamName,
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num byteLength
        ]
    | .create2 =>
        #[
          Lean.Compiler.Yul.Expr.id createCallValueParamName,
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num byteLength,
          Lean.Compiler.Yul.Expr.id createSaltParamName
        ]
  .ok <| .funcDef functionName
    (createHelperParams spec.mode)
    #[{ name := "result" }]
    {
      statements := storeStatements ++ #[
        .assignment #["result"] (Lean.Compiler.Yul.builtin spec.mode.opcode createArgs),
        .ifStmt
          (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "result"])
          { statements := #[.exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])] }
      ]
    }

def twoPow64 : Nat := 18446744073709551616
def maxU64 : Nat := twoPow64 - 1
def maxU32 : Nat := 4294967295

-- ASCII "PROOF_FORGE_MAP_PRESENCE" packed as one EVM word.
def mapPresenceDomain : Nat := 1969478005224772198022937154314036040895674356107534287685

def checkedHashLiteralLimb (name : String) (value : Nat) : Except LowerError Nat :=
  if value <= maxU64 then
    .ok value
  else
    .error { message := s!"Hash literal limb `{name}` exceeds U64 range" }

def packedHashLiteral (a b c d : Nat) : Except LowerError Nat := do
  let a ← checkedHashLiteralLimb "a" a
  let b ← checkedHashLiteralLimb "b" b
  let c ← checkedHashLiteralLimb "c" c
  let d ← checkedHashLiteralLimb "d" d
  .ok ((((a * twoPow64) + b) * twoPow64 + c) * twoPow64 + d)

def hashPackExpr
    (a b c d : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "or" #[
    Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 192, a],
    Lean.Compiler.Yul.builtin "or" #[
      Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 128, b],
      Lean.Compiler.Yul.builtin "or" #[
        Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 64, c],
        d
      ]
    ]
  ]

def validateEventName (name : String) : Except LowerError Unit := do
  if name.toUTF8.size == 0 then
    .error { message := "event name must be non-empty for IR EVM v0" }

def packedUtf8Words (value : String) : Array Nat × Nat :=
  ProofForge.Backend.Evm.ToYul.packedUtf8Words value

partial def eventSignatureFieldType (module : Module) (eventName fieldName : String) (type : ValueType) : Except LowerError String :=
  let erc20FieldType? : Option String :=
    if eventName == "Transfer" then
      if fieldName == "from" || fieldName == "to" then some "address"
      else if fieldName == "value" then some "uint256" else none
    else if eventName == "Approval" then
      if fieldName == "owner" || fieldName == "spender" then some "address"
      else if fieldName == "value" then some "uint256" else none
    else none
  match erc20FieldType? with
  | some abiType => .ok abiType
  | none =>
  match type with
  | .u32 => .ok "uint32"
  | .u64 => .ok "uint64"
  | .bool => .ok "bool"
  | .hash => .ok "bytes32"
  | .address => .ok "address"
  | .bytes => .ok "bytes"
  | .string => .ok "string"
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"event `{eventName}` field `{fieldName}` uses Array<{elementType.name},0>; event fixed arrays must have non-zero length" }
      match elementType with
      | .fixedArray _ _ => do
          let elementName ← eventSignatureFieldType module eventName fieldName elementType
          .ok (elementName ++ s!"[{length}]")
      | .structType typeName => do
          let some decl := module.structs.find? fun decl => decl.name == typeName
            | .error { message := s!"event `{eventName}` field `{fieldName}` uses unknown struct `{typeName}`" }
          if decl.fields.isEmpty then
            .error { message := s!"event `{eventName}` field `{fieldName}` uses empty struct `{typeName}`; event structs must have at least one field" }
          let mut parts := #[]
          for field in decl.fields do
            match field.type with
            | .u32 | .u64 | .bool | .hash | .address =>
                parts := parts.push (← eventSignatureFieldType module eventName s!"{fieldName}.{field.id}" field.type)
            | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
                .error {
                  message := s!"event `{eventName}` field `{fieldName}` struct `{typeName}` field `{field.id}` has unsupported EVM IR v0 event type `{field.type.name}`; event structs must be flat U32, U64, Bool, or Hash fields"
                }
          .ok ("(" ++ String.intercalate "," parts.toList ++ ")" ++ s!"[{length}]")
      | _ => do
          let elementName ← eventSignatureFieldType module eventName fieldName elementType
          .ok (elementName ++ s!"[{length}]")
  | .structType typeName => do
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error { message := s!"event `{eventName}` field `{fieldName}` uses unknown struct `{typeName}`" }
      if decl.fields.isEmpty then
        .error { message := s!"event `{eventName}` field `{fieldName}` uses empty struct `{typeName}`; event structs must have at least one field" }
      let mut parts := #[]
      for field in decl.fields do
        match field.type with
        | .u32 | .u64 | .bool | .hash | .address =>
            parts := parts.push (← eventSignatureFieldType module eventName s!"{fieldName}.{field.id}" field.type)
        | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
            .error {
              message := s!"event `{eventName}` field `{fieldName}` struct `{typeName}` field `{field.id}` has unsupported EVM IR v0 event type `{field.type.name}`; event structs must be flat U32, U64, Bool, or Hash fields"
            }
      .ok ("(" ++ String.intercalate "," parts.toList ++ ")")
  | .unit =>
      .error { message := s!"event `{eventName}` field `{fieldName}` has unsupported EVM IR v0 type `Unit`; event fields must be U32, U64, Bool, Hash, Address, flat structs, or fixed arrays" }

def ensureIndexedEventFieldType
    (module : Module)
    (eventName fieldName : String)
    (type : ValueType) : Except LowerError Unit := do
  discard <| eventSignatureFieldType module eventName fieldName type

def eventSignatureTopicStatements (signature : String) : Array Lean.Compiler.Yul.Statement :=
  ProofForge.Backend.Evm.ToYul.eventSignatureTopicStatements (ProofForge.Backend.Evm.Plan.EventPlan.mk "" signature #[])

def validateEventFieldName (eventName fieldName : String) : Except LowerError Unit :=
  if fieldName.isEmpty then
    .error { message := s!"event `{eventName}` field name must be non-empty" }
  else
    .ok ()

def validateDistinctEventFieldName (eventName : String) (seen : Array String) (fieldName : String) : Except LowerError (Array String) := do
  validateEventFieldName eventName fieldName
  if seen.contains fieldName then
    .error { message := s!"duplicate event `{eventName}` field name `{fieldName}`" }
  else
    .ok (seen.push fieldName)

def storagePathMapKeys? (path : Array StoragePathSegment) : Option (Array ProofForge.IR.Expr) :=
  if path.isEmpty then
    none
  else
    path.foldl (init := some #[]) fun acc segment =>
      match acc, segment with
      | some keys, .mapKey key => some (keys.push key)
      | _, _ => none

def validateIndexedEventFieldCount (eventName : String) (count : Nat) : Except LowerError Unit :=
  if count > 3 then
    .error { message := s!"event `{eventName}` has {count} indexed field(s); EVM IR v0 supports at most 3 indexed fields" }
  else
    .ok ()

def eventIndexedTopicName (index : Nat) : String :=
  ProofForge.Backend.Evm.ToYul.eventIndexedTopicName index

def eventLogBuiltinName (indexedFieldCount : Nat) : Except LowerError String :=
  ProofForge.Backend.Evm.ToYul.eventLogBuiltinName toYulError indexedFieldCount

def revertStmt : Lean.Compiler.Yul.Statement :=
  Lean.Compiler.Yul.Statement.exprStmt
    (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])

def eip1967ImplementationSlotExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")

def uupsProxyFallbackBody : Array Lean.Compiler.Yul.Statement := #[
  .varDecl #[{ name := "_impl" }] (some (Lean.Compiler.Yul.builtin "sload" #[eip1967ImplementationSlotExpr])),
  .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_impl"]) { statements := #[revertStmt] },
  .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "calldatasize" #[]
  ]),
  .varDecl #[{ name := "_ok" }] (some (Lean.Compiler.Yul.builtin "delegatecall" #[
    Lean.Compiler.Yul.builtin "gas" #[],
    Lean.Compiler.Yul.Expr.id "_impl",
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "calldatasize" #[],
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0
  ])),
  .exprStmt (Lean.Compiler.Yul.builtin "returndatacopy" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "returndatasize" #[]
  ]),
  .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_ok"]) {
    statements := #[
      .exprStmt (Lean.Compiler.Yul.builtin "revert" #[
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.builtin "returndatasize" #[]
      ])
    ]
  },
  .exprStmt (Lean.Compiler.Yul.builtin "return" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "returndatasize" #[]
  ])
]

def uupsProxyDefaultCase : Lean.Compiler.Yul.Case := {
  value := none
  body := { statements := uupsProxyFallbackBody }
}

/-- The 2^256 - 1 max word value, used for overflow checks. -/
def maxUint256 : Nat := 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

/-- Helper names for checked arithmetic (Solidity 0.8-style overflow/underflow revert).
    These are emitted once per module that uses them; see `checkedArithmeticHelperFunctions`. -/
def checkedAddName : String := "__pf_checked_add"
def checkedSubName : String := "__pf_checked_sub"
def checkedMulName : String := "__pf_checked_mul"

/-- Statement that reverts if `cond` is nonzero (truthy). -/
def revertIfStmt (cond : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Statement :=
  Lean.Compiler.Yul.Statement.ifStmt cond { statements := #[revertStmt] }

/-- Lower-level checked-add expression: `__pf_checked_add(a, b)` reverts on overflow. -/
def checkedAddExpr (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call checkedAddName #[lhs, rhs]

/-- Lower-level checked-sub expression: reverts on underflow. -/
def checkedSubExpr (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call checkedSubName #[lhs, rhs]

/-- Lower-level checked-mul expression: reverts on overflow. -/
def checkedMulExpr (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call checkedMulName #[lhs, rhs]

/-- Whether `op` is an arithmetic op that needs checked helpers. -/
def needsCheckedArithmetic (op : AssignOp) : Bool :=
  match op with
  | .add | .sub | .mul => true
  | _ => false

/-- The checked-arithmetic Yul function definitions emitted once per module.
    Mirrors Solidity 0.8 semantics: `add`/`mul` revert on U256 overflow, `sub`
    reverts on underflow. Bitwise/div/shift ops never overflow, so they keep
    using the raw EVM builtins. -/
def checkedArithmeticHelperFunctions : Array Lean.Compiler.Yul.Statement :=
  let tn (n : String) := { name := n : Lean.Compiler.Yul.TypedName }
  #[
    Lean.Compiler.Yul.Statement.funcDef checkedAddName #[tn "a", tn "b"] #[tn "r"]
      { statements := #[
        -- overflow iff a > maxUint256 - b  (i.e. a + b > max)
        revertIfStmt (Lean.Compiler.Yul.builtin "gt" #[
          Lean.Compiler.Yul.Expr.id "a",
          Lean.Compiler.Yul.builtin "sub" #[Lean.Compiler.Yul.Expr.num maxUint256, Lean.Compiler.Yul.Expr.id "b"]
        ]),
        Lean.Compiler.Yul.Statement.assignment #["r"]
          (Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "a", Lean.Compiler.Yul.Expr.id "b"])
      ] },
    Lean.Compiler.Yul.Statement.funcDef checkedSubName #[tn "a", tn "b"] #[tn "r"]
      { statements := #[
        -- underflow iff b > a
        revertIfStmt (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id "b", Lean.Compiler.Yul.Expr.id "a"]),
        Lean.Compiler.Yul.Statement.assignment #["r"]
          (Lean.Compiler.Yul.builtin "sub" #[Lean.Compiler.Yul.Expr.id "a", Lean.Compiler.Yul.Expr.id "b"])
      ] },
    Lean.Compiler.Yul.Statement.funcDef checkedMulName #[tn "a", tn "b"] #[tn "r"]
      { statements := #[
        -- 0 * b = 0 is safe and avoids div-by-zero in the overflow check below.
        Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "a"])
          { statements := #[
            Lean.Compiler.Yul.Statement.assignment #["r"] (Lean.Compiler.Yul.Expr.num 0),
            Lean.Compiler.Yul.Statement.leave
          ] },
        -- overflow iff a > max / b  (i.e. a * b > max)
        revertIfStmt (Lean.Compiler.Yul.builtin "gt" #[
          Lean.Compiler.Yul.Expr.id "a",
          Lean.Compiler.Yul.builtin "div" #[Lean.Compiler.Yul.Expr.num maxUint256, Lean.Compiler.Yul.Expr.id "b"]
        ]),
        Lean.Compiler.Yul.Statement.assignment #["r"]
          (Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "a", Lean.Compiler.Yul.Expr.id "b"])
      ] }
  ]

def nibbleToHex (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + (n - 10))

def byteToHex (b : UInt8) : String :=
  let n := b.toNat
  String.ofList [nibbleToHex (n / 16), nibbleToHex (n % 16)]

def stringToHex (s : String) : String :=
  s.toUTF8.toList.map byteToHex |>.foldl (· ++ ·) ""

def errorRefRevertStmts (ref : ProofForge.IR.ErrorRef) : Array Lean.Compiler.Yul.Statement :=
  let code := ref.userCode?.getD ""
  let codeLen := code.length
  let paddedLen := ((codeLen + 31) / 32) * 32
  let totalSize := 96 + paddedLen
  let headerStmts : Array Lean.Compiler.Yul.Statement := #[
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num ref.assertionId.toNat]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.num 64]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.num codeLen])
  ]
  let chunks := if codeLen > 0 then hexChunks64 (stringToHex code) else #[]
  let dataStmts := chunks.foldl (init := #[]) fun acc chunk =>
    let idx := acc.size
    acc.push <| .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
      Lean.Compiler.Yul.Expr.num (96 + idx * 32),
      Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex ("0x" ++ rightPadHex64 chunk))
    ])
  headerStmts ++ dataStmts ++ #[
    .exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num totalSize])
  ]

def lowerAssertStmt (condition : Lean.Compiler.Yul.Expr) (errorRef? : Option ProofForge.IR.ErrorRef) : Lean.Compiler.Yul.Statement :=
  let revertStatements := match errorRef? with
    | none => #[revertStmt]
    | some ref => errorRefRevertStmts ref
  ProofForge.Backend.Evm.ToYul.assertStatementFromCondition condition revertStatements

def calldataWordExpr (paramIndex : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num (4 + paramIndex * 32)]

-- Dynamic ABI type support: bytes and string use head-tail encoding.
-- The head contains an offset to the tail where (length, data) is stored.

def isDynamicAbiType : ValueType → Bool
  | .bytes | .string => true
  | .u32 | .u64 | .bool | .hash | .address | .unit | .fixedArray _ _ | .structType _ => false

-- Yul expression to load a word from calldata at a byte offset.
def calldataloadAt (offset : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[offset]

-- Names for dynamic parameter locals (length and memory pointer).
def dynamicParamLengthName (name : String) : String := s!"{name}__length"
def dynamicParamDataPtrName (name : String) : String := s!"{name}__data_ptr"
def arrayLocalElementName (name : String) (index : Nat) : String :=
  s!"__proof_forge_array_{name}_{index}"

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_array_struct_{name}_{index}_{fieldName}"

def natPathSuffix (path : Array Nat) : String :=
  Id.run do
    let mut suffix := ""
    for h : idx in [0:path.size] do
      let part := toString path[idx]
      suffix := if idx == 0 then part else s!"{suffix}_{part}"
    suffix

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  match path.toList with
  | [index] => arrayLocalElementName name index
  | _ => s!"__proof_forge_array_{name}_{natPathSuffix path}"

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  match path.toList with
  | [index] => arrayStructLocalFieldName name index fieldName
  | _ => s!"__proof_forge_array_struct_{name}_{natPathSuffix path}_{fieldName}"

def localArrayGetFunctionName (length : Nat) : String :=
  s!"__proof_forge_local_array_get_{length}"

def nestedLocalArrayGetFunctionName (lengths : Array Nat) : String :=
  s!"__proof_forge_local_array_get_nested_{natPathSuffix lengths}"

def localArrayGetValueParamName (index : Nat) : String :=
  s!"value_{index}"

def localArrayGetIndexParamName (index : Nat) : String :=
  s!"index_{index}"

def localArrayGetPathValueParamName (path : Array Nat) : String :=
  s!"value_{natPathSuffix path}"

partial def nestedLocalArrayLeafPaths (lengths : Array Nat) : Array (Array Nat) :=
  match lengths.toList with
  | [] => #[#[]]
  | length :: rest =>
      Id.run do
        let nested := nestedLocalArrayLeafPaths rest.toArray
        let mut paths : Array (Array Nat) := #[]
        for _h : idx in [0:length] do
          for path in nested do
            paths := paths.push (#[idx] ++ path)
        paths

def structLocalFieldName (name fieldName : String) : String :=
  s!"__proof_forge_struct_{name}_{fieldName}"

def abiReturnName (index : Nat) : String :=
  s!"__proof_forge_return_{index}"

def abiDispatchResultName (index : Nat) : String :=
  s!"_r{index}"

def ensureAbiWordType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error {
        message := s!"{context} has unsupported EVM IR v0 ABI word type `{type.name}`; ABI aggregate words support U32, U64, Bool, Hash, or Address"
      }

def ensureCrosscallWordType (context : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error {
        message := s!"{context} has unsupported EVM IR v0 crosscall word type `{type.name}`; crosscall scalar words support U32, U64, Bool, Hash, or Address"
      }

def isCrosscallWordType : ValueType → Bool
  | .u32 | .u64 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string => false

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
  | .bytes | .string =>
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
  | .bytes => .ok #[.bytes]
  | .string => .ok #[.string]
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
  | .bytes | .string =>
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
  | .bytes | .string =>
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
  | .u32 | .u64 | .bool | .hash | .address | .bytes | .string =>
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
  entrypoint.params.foldlM (init := #[]) fun acc param => do
    let (name, type) := param
    if isDynamicAbiType type then
      -- Dynamic params (bytes/string) are represented as two Yul locals:
      -- <name>__length (byte length) and <name>__data_ptr (memory pointer to data)
      .ok (acc ++ #[
        { name := dynamicParamLengthName name },
        { name := dynamicParamDataPtrName name }
      ])
    else
      let paramNames ← abiValueParamNames module s!"entrypoint `{entrypoint.name}` parameter `{name}`" name type
      .ok (acc ++ (paramNames.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName)))

-- Layout info for a single entrypoint parameter.
structure AbiParamLayout where
  name : String
  type : ValueType
  isDynamic : Bool
  headWordIndex : Nat  -- index of this param's first head word
  deriving Repr

def entrypointParamLayouts (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array AbiParamLayout) := do
  let mut layouts : Array AbiParamLayout := #[]
  let mut headIdx := 0
  for param in entrypoint.params do
    let (name, type) := param
    let isDyn := isDynamicAbiType type
    layouts := layouts.push { name, type, isDynamic := isDyn, headWordIndex := headIdx }
    headIdx := headIdx + (← abiParamHeadWordCount module s!"entrypoint `{entrypoint.name}` parameter `{name}`" type)
  .ok layouts

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

-- Generate call args for the entrypoint function.
-- Static params: calldataload from the head.
-- Dynamic params: pass __length and __data_ptr locals (set up by decode statements).
def entrypointCallArgsWithLayout (module : Module) (entrypoint : Entrypoint) (layouts : Array AbiParamLayout) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  let mut args : Array Lean.Compiler.Yul.Expr := #[]
  let mut staticWordIdx := 0
  for h : i in [0:layouts.size] do
    let layout := layouts[i]
    if layout.isDynamic then
      -- Pass the decoded length and data_ptr as function args
      args := args.push (Lean.Compiler.Yul.Expr.id (dynamicParamLengthName layout.name))
      args := args.push (Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName layout.name))
      staticWordIdx := staticWordIdx + 1
    else
      let wordTypes ← abiValueWordTypes module s!"entrypoint `{entrypoint.name}` parameter `{layout.name}`" layout.type
      for _ in [0:wordTypes.size] do
        args := args.push (calldataWordExpr staticWordIdx)
        staticWordIdx := staticWordIdx + 1
  .ok args

def entrypointCallArgs (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  let layouts ← entrypointParamLayouts module entrypoint
  entrypointCallArgsWithLayout module entrypoint layouts

-- Generate calldata size check and per-word validation for static params,
-- plus head-tail decode statements for dynamic params (bytes/string).
-- Returns (validationStmts, dynamicDecodeStmts) — both run before the call.
def abiParamValidationAndDecodeStmts
    (module : Module)
    (entrypoint : Entrypoint)
    (layouts : Array AbiParamLayout) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let headWordCount := layouts.foldl (init := 0) fun acc l =>
    if l.isDynamic then acc + 1 else
      Id.run <| match abiValueWordTypes module "" l.type with
      | .ok ws => acc + ws.size
      | _ => acc + 1  -- fallback, shouldn't happen
  let minSize := 4 + headWordCount * 32
  let mut statements : Array Lean.Compiler.Yul.Statement :=
    if headWordCount == 0 then
      #[]
    else
      #[
        Lean.Compiler.Yul.Statement.ifStmt
          (Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.builtin "calldatasize" #[], Lean.Compiler.Yul.Expr.num minSize])
          { statements := #[revertStmt] }
      ]
  -- Static param word validation
  let mut staticWordIdx := 0
  for h : i in [0:layouts.size] do
    let layout := layouts[i]
    if layout.isDynamic then
      -- Validate offset: the offset word in the head must point within calldata
      let offsetExpr := calldataWordExpr staticWordIdx
      let baseOffset := Lean.Compiler.Yul.Expr.num (4 + staticWordIdx * 32)
      -- The offset value + 4 (selector) + (staticWordIdx+1)*32 must be <= calldatasize
      let offsetPlusBase := Lean.Compiler.Yul.builtin "add" #[baseOffset, offsetExpr]
      statements := statements.push <|
        Lean.Compiler.Yul.Statement.ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[offsetPlusBase, Lean.Compiler.Yul.builtin "calldatasize" #[]])
          { statements := #[revertStmt] }
      staticWordIdx := staticWordIdx + 1
    else
      let wordTypes ← abiValueWordTypes module s!"entrypoint `{entrypoint.name}` parameter `{layout.name}`" layout.type
      for h : j in [0:wordTypes.size] do
        let word := calldataWordExpr staticWordIdx
        statements :=
          match wordTypes[j] with
          | .u32 =>
              statements.push <| Lean.Compiler.Yul.Statement.ifStmt
                (Lean.Compiler.Yul.builtin "gt" #[word, Lean.Compiler.Yul.Expr.num 4294967295])
                { statements := #[revertStmt] }
          | .bool =>
              statements.push <| Lean.Compiler.Yul.Statement.ifStmt
                (Lean.Compiler.Yul.builtin "gt" #[word, Lean.Compiler.Yul.Expr.num 1])
                { statements := #[revertStmt] }
          | .u64 | .hash | .address | .unit | .fixedArray _ _ | .structType _ | .bytes | .string => statements
        staticWordIdx := staticWordIdx + 1
  -- Dynamic param decode: read offset from head, load length and data from tail
  -- into memory. Use the free memory pointer (mload(0x40)) for allocation.
  for h : i in [0:layouts.size] do
    let layout := layouts[i]
    if layout.isDynamic then
      -- Read the offset from the head
      let offsetExpr := calldataWordExpr layout.headWordIndex
      -- Actual byte offset in calldata: 4 (selector) + headOffsetValue
      let dataOffset := Lean.Compiler.Yul.builtin "add" #[
        Lean.Compiler.Yul.Expr.num (4 + layout.headWordIndex * 32),
        offsetExpr
      ]
      -- Read length from calldata at the offset
      let lengthExpr := calldataloadAt dataOffset
      -- Allocate memory: length word + ceil(length/32) data words
      -- Use mload(0x40) as the memory pointer
      let memPtr := Lean.Compiler.Yul.Expr.id (s!"__pf_dyn_ptr_{layout.name}")
      let dataStart := Lean.Compiler.Yul.builtin "add" #[memPtr, Lean.Compiler.Yul.Expr.num 32]
      let wordCount := Lean.Compiler.Yul.builtin "div" #[
        Lean.Compiler.Yul.builtin "add" #[lengthExpr, Lean.Compiler.Yul.Expr.num 31],
        Lean.Compiler.Yul.Expr.num 32
      ]
      let memSize := Lean.Compiler.Yul.builtin "mul" #[wordCount, Lean.Compiler.Yul.Expr.num 32]
      let totalSize := Lean.Compiler.Yul.builtin "add" #[memSize, Lean.Compiler.Yul.Expr.num 32]
      -- Validate length: offset + 32 + ceil(length/32)*32 <= calldatasize
      let tailEnd := Lean.Compiler.Yul.builtin "add" #[
        dataOffset,
        Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.num 32, memSize]
      ]
      statements := statements ++ #[
        -- Validate the tail fits in calldata
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[tailEnd, Lean.Compiler.Yul.builtin "calldatasize" #[]])
          { statements := #[revertStmt] },
        -- Allocate memory
        .varDecl #[{ name := s!"__pf_dyn_ptr_{layout.name}" }]
          (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0x40])),
        -- Store length
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[memPtr, lengthExpr]),
        -- Copy data from calldata to memory
        .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
          dataStart,
          Lean.Compiler.Yul.builtin "add" #[dataOffset, Lean.Compiler.Yul.Expr.num 32],
          memSize
        ]),
        -- Update free memory pointer
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 0x40,
          Lean.Compiler.Yul.builtin "add" #[memPtr, totalSize]
        ]),
        -- Set the __length and __data_ptr locals
        .varDecl #[{ name := dynamicParamLengthName layout.name }] (some lengthExpr),
        .varDecl #[{ name := dynamicParamDataPtrName layout.name }] (some memPtr)
      ]
  .ok statements

-- Backward-compatible wrapper: only returns validation (no dynamic decode).
-- The full validation+decode is in abiParamValidationAndDecodeStmts.
def abiParamValidationStmts (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let layouts ← entrypointParamLayouts module entrypoint
  -- For backward compat, just run the size check + static word validation
  -- (no dynamic decode). This is used by callers that don't need decode.
  let headWordCount := layouts.foldl (init := 0) fun acc l =>
    if l.isDynamic then acc + 1 else
      Id.run <| match abiValueWordTypes module "" l.type with
      | .ok ws => acc + ws.size
      | _ => acc + 1
  let minSize := 4 + headWordCount * 32
  if headWordCount == 0 then
    .ok #[]
  else
    .ok #[
      Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.builtin "calldatasize" #[], Lean.Compiler.Yul.Expr.num minSize])
        { statements := #[revertStmt] }
    ]

def contextExpr : ContextField → Lean.Compiler.Yul.Expr
  | .userId => Lean.Compiler.Yul.builtin "caller" #[]
  | .contractId => Lean.Compiler.Yul.builtin "address" #[]
  | .checkpointId => Lean.Compiler.Yul.builtin "number" #[]
  | .timestamp => Lean.Compiler.Yul.builtin "timestamp" #[]
  | .chainId => Lean.Compiler.Yul.builtin "chainid" #[]
  | .gasPrice => Lean.Compiler.Yul.builtin "gasprice" #[]
  | .gasLeft => Lean.Compiler.Yul.builtin "gas" #[]
  | .baseFee => Lean.Compiler.Yul.builtin "basefee" #[]
  | .prevRandao => Lean.Compiler.Yul.builtin "prevrandao" #[]
  | .origin => Lean.Compiler.Yul.builtin "origin" #[]
  | .coinbase => Lean.Compiler.Yul.builtin "coinbase" #[]
  | .blockHash _ => Lean.Compiler.Yul.builtin "blockhash" #[]

def mapShapeName (keyType valueType : ValueType) (capacity : Nat) : String :=
  s!"Map<{keyType.name}, {valueType.name}, {capacity}>"

def isStorageWordType : ValueType → Bool
  | .u32 | .u64 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string => false

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

def requireStorageArrayState (module : Module) (stateId : String) : Except LowerError (Nat × Nat × ValueType) :=
  match stateInfo? module stateId with
  | none => .error { message := s!"unknown array state `{stateId}`" }
  | some (slot, state) =>
      match state.kind, state.type with
      | .array length, elementType =>
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
  if expected == actual then
    .ok ()
  else
    .error { message := s!"{context} expected `{expected.name}`, got `{actual.name}`" }

def ensureNumericType (context : String) (lhs rhs : ValueType) : Except LowerError ValueType :=
  match lhs, rhs with
  | .u32, .u32 => .ok .u32
  | .u64, .u64 => .ok .u64
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

def mapAssignFunctionName (op : AssignOp) : String :=
  s!"__proof_forge_map_assign_{assignOpBuiltinName op}"

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
  | .bool | .u32 | .u64 | .hash | .address => .ok ()
  | .unit => .error { message := s!"{context} does not support Unit equality" }
  | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error { message := s!"{context} does not support `{type.name}` equality in IR EVM v0" }

def ensureCastType (source target : ValueType) : Except LowerError Unit :=
  match source, target with
  | .u32, .u64 => .ok ()
  | .u64, .u32 => .ok ()
  | .u32, .bool => .ok ()
  | .bool, .u64 => .ok ()
  | .bool, .u32 => .ok ()
  | .u64, .bool => .ok ()
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

def mapStateTypes (module : Module) (stateId : String) : Except LowerError (ValueType × ValueType) := do
  let state ← stateDeclOf module stateId "map"
  match state.kind with
  | .map keyType _ => .ok (keyType, state.type)
  | .scalar => .error { message := s!"state `{stateId}` is scalar storage, not a map" }
  | .array _ => .error { message := s!"state `{stateId}` is array storage, not a map" }

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
  | .u32 | .u64 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
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
  | .u32 | .u64 | .bool | .hash | .address => .ok ()
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} `{name}` nested fixed-array leaf" typeName
  | .fixedArray elementType length => do
      if length == 0 then
        .error { message := s!"{context} `{name}` nested fixed array must have non-zero length in IR EVM v0" }
      else
        pure ()
      ensureLocalNestedFixedArrayValueType module context name elementType
  | .unit | .bytes | .string =>
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

mutual
  partial def inferExprType (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError ValueType
    | .literal (.u32 _) => .ok .u32
    | .literal (.u64 _) => .ok .u64
    | .literal (.bool _) => .ok .bool
    | .literal (.hash4 ..) => .ok .hash
    | .literal (.address _) => .ok .address
    | .local name =>
        match findLocal? env name with
        | some binding => .ok binding.type
        | none => .error { message := s!"unknown local `{name}`" }
    | .arrayLit elementType values => do
        for value in values do
          ensureType "array literal element" elementType (← inferExprType module env value)
        .ok (.fixedArray elementType values.size)
    | .arrayGet array index => do
        ensureArrayIndexType "fixed array index" (← inferExprType module env index)
        match ← inferExprType module env array with
        | .fixedArray elementType length => do
            match literalArrayIndex? index with
            | some indexValue =>
                ensureFixedArrayIndexInBounds "fixed array index" indexValue length
            | none => pure ()
            .ok elementType
        | other => .error { message := s!"fixed array indexing target expected `Array`, got `{other.name}`" }
    | .structLit typeName fields => do
        validateStructLiteralFields module typeName fields (inferExprType module env)
        .ok (.structType typeName)
    | .field base fieldName => do
        match ← inferExprType module env base with
        | .structType typeName => do
            let fieldType ← structFieldType module typeName fieldName
            ensureStructLocalFieldType typeName fieldName fieldType
            .ok fieldType
        | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
    | .add lhs rhs => do inferBinaryNumericType "addition" module env lhs rhs
    | .sub lhs rhs => do inferBinaryNumericType "subtraction" module env lhs rhs
    | .mul lhs rhs => do inferBinaryNumericType "multiplication" module env lhs rhs
    | .div lhs rhs => do inferBinaryNumericType "division" module env lhs rhs
    | .mod lhs rhs => do inferBinaryNumericType "modulo" module env lhs rhs
    | .pow lhs rhs => do inferBinaryNumericType "exponentiation" module env lhs rhs
    | .bitAnd lhs rhs => do inferBinaryNumericType "bitwise and" module env lhs rhs
    | .bitOr lhs rhs => do inferBinaryNumericType "bitwise or" module env lhs rhs
    | .bitXor lhs rhs => do inferBinaryNumericType "bitwise xor" module env lhs rhs
    | .shiftLeft lhs rhs => do inferBinaryNumericType "shift-left" module env lhs rhs
    | .shiftRight lhs rhs => do inferBinaryNumericType "shift-right" module env lhs rhs
    | .cast value targetType => do
        ensureCastType (← inferExprType module env value) targetType
        .ok targetType
    | .eq lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "equality right operand" lhsType rhsType
        ensureEqType "equality expression" lhsType
        .ok .bool
    | .ne lhs rhs => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "inequality right operand" lhsType rhsType
        ensureEqType "inequality expression" lhsType
        .ok .bool
    | .lt lhs rhs => do
        discard <| inferBinaryNumericType "less-than" module env lhs rhs
        .ok .bool
    | .le lhs rhs => do
        discard <| inferBinaryNumericType "less-or-equal" module env lhs rhs
        .ok .bool
    | .gt lhs rhs => do
        discard <| inferBinaryNumericType "greater-than" module env lhs rhs
        .ok .bool
    | .ge lhs rhs => do
        discard <| inferBinaryNumericType "greater-or-equal" module env lhs rhs
        .ok .bool
    | .boolAnd lhs rhs => do
        ensureType "boolean and left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean and right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolOr lhs rhs => do
        ensureType "boolean or left operand" .bool (← inferExprType module env lhs)
        ensureType "boolean or right operand" .bool (← inferExprType module env rhs)
        .ok .bool
    | .boolNot value => do
        ensureType "boolean not operand" .bool (← inferExprType module env value)
        .ok .bool
    | .hashValue a b c d => do
        ensureType "hash value part 0" .u64 (← inferExprType module env a)
        ensureType "hash value part 1" .u64 (← inferExprType module env b)
        ensureType "hash value part 2" .u64 (← inferExprType module env c)
        ensureType "hash value part 3" .u64 (← inferExprType module env d)
        .ok .hash
    | .hash preimage => do
        ensureType "hash preimage" .hash (← inferExprType module env preimage)
        .ok .hash
    | .hashTwoToOne lhs rhs => do
        ensureType "hash_two_to_one left operand" .hash (← inferExprType module env lhs)
        ensureType "hash_two_to_one right operand" .hash (← inferExprType module env rhs)
        .ok .hash
    | .nativeValue => .ok .u64
    | .crosscallInvoke target methodId args => do
        ensureType "crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "crosscall method id" .u64 (← inferExprType module env methodId)
        for arg in args do
          ensureType "crosscall argument" .u64 (← inferExprType module env arg)
        .ok .u64
    | .crosscallInvokeTyped target methodId args returnType => do
        ensureType "typed crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "typed crosscall method id" .u64 (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "typed crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "typed crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        ensureType "value crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "value crosscall method id" .u64 (← inferExprType module env methodId)
        ensureType "value crosscall call value" .u64 (← inferExprType module env callValue)
        discard <| crosscallReturnWordTypes module "value crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "value crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        ensureType "static crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "static crosscall method id" .u64 (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "static crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "static crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        ensureType "delegate crosscall target contract id" .u64 (← inferExprType module env target)
        ensureType "delegate crosscall method id" .u64 (← inferExprType module env methodId)
        discard <| crosscallReturnWordTypes module "delegate crosscall return" returnType
        for arg in args do
          discard <| crosscallArgWordTypes module "delegate crosscall argument" (← inferExprType module env arg)
        .ok returnType
    | .crosscallCreate callValue initCodeHex => do
        ensureType "contract creation call value" .u64 (← inferExprType module env callValue)
        discard <| normalizeInitCodeHex "contract creation" initCodeHex
        .ok .u64
    | .crosscallCreate2 callValue salt initCodeHex => do
        ensureType "contract creation call value" .u64 (← inferExprType module env callValue)
        ensureType "contract creation salt" .hash (← inferExprType module env salt)
        discard <| normalizeInitCodeHex "contract creation" initCodeHex
        .ok .u64
    | .effect effect => inferEffectExprType module env effect

  partial def inferBinaryNumericType
      (context : String)
      (module : Module)
      (env : TypeEnv)
      (lhs rhs : ProofForge.IR.Expr) : Except LowerError ValueType := do
    ensureNumericType context (← inferExprType module env lhs) (← inferExprType module env rhs)

  partial def inferStoragePathType
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (path : Array StoragePathSegment) : Except LowerError ValueType := do
    let state ← stateDeclOf module stateId "storage path"
    match state.kind, state.type, path.toList with
    | .map keyType _, _, _ => do
        let some keys := storagePathMapKeys? path
          | if path.isEmpty then
              .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
            else
              .error { message := "EVM IR v0 supports map storage paths only as one or more mapKey segments" }
        for key in keys do
          ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok state.type
    | .scalar, .structType _, [StoragePathSegment.field fieldName] => do
        let (_, field) ← requireStructStateField module stateId fieldName
        .ok field.type
    | .scalar, .structType _, [] =>
        .error { message := s!"storage path state `{stateId}` is struct storage; first segment must be a field" }
    | .scalar, .structType _, _ =>
        .error { message := "EVM IR v0 supports struct scalar storage paths only as a single field segment" }
    | .scalar, _, [] =>
        .ok state.type
    | .scalar, _, [StoragePathSegment.field fieldName] =>
        .error { message := s!"state `{stateId}` has unsupported EVM IR v0 struct storage type `{state.type.name}`; expected struct storage for field `{fieldName}`" }
    | .scalar, _, _ =>
        .error { message := "EVM IR v0 supports storage paths only for single-segment mapKey map access" }
    | .array _, .structType _, [StoragePathSegment.index index, StoragePathSegment.field fieldName] => do
        let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
        ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
        .ok field.type
    | .array _, .structType _, [StoragePathSegment.index _] =>
        .error { message := s!"storage path state `{stateId}` is struct array storage; a field segment must follow the index" }
    | .array _, _, [] =>
        .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
    | .array _, .structType _, _ =>
        .error { message := "EVM IR v0 supports struct-array storage paths only as index followed by field" }
    | .array _, _, [StoragePathSegment.index index] => do
        let (_, _, elementType) ← requireStorageArrayState module stateId
        ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .array _, _, _ =>
        .error { message := "EVM IR v0 supports only single-segment index storage paths for arrays" }

  partial def inferEffectExprType (module : Module) (env : TypeEnv) : Effect → Except LowerError ValueType
    | .storageScalarRead stateId =>
        scalarStateType module stateId
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key => do
        let (keyType, _) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok .bool
    | .storageMapGet stateId key => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        .ok valueType
    | .storageMapInsert stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
        .ok valueType
    | .storageMapSet stateId key value => do
        let (keyType, valueType) ← mapStateTypes module stateId
        ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
        ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
        .ok valueType
    | .storageArrayRead stateId index => do
        let (_, _, elementType) ← requireStorageArrayState module stateId
        ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
        .ok elementType
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName => do
        let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
        ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
        .ok field.type
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName => do
        let (_, field) ← requireStructStateField module stateId fieldName
        .ok field.type
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path =>
        inferStoragePathType module env stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead .origin => .ok .hash
    | .contextRead .coinbase => .ok .hash
    | .contextRead (.blockHash _) => .ok .hash
    | .contextRead _ =>
        .ok .u64
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }
end

partial def inferEventFieldExprType (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError ValueType
  | .literal (.u32 _) => .ok .u32
  | .literal (.u64 _) => .ok .u64
  | .literal (.bool _) => .ok .bool
  | .literal (.hash4 ..) => .ok .hash
  | .literal (.address _) => .ok .address
  | .local name =>
      match findLocal? env name with
      | some binding => .ok binding.type
      | none => .error { message := s!"unknown local `{name}`" }
  | .arrayLit elementType values => do
      for value in values do
        ensureType "event field array literal element" elementType (← inferEventFieldExprType module env value)
      .ok (.fixedArray elementType values.size)
  | .arrayGet array index => do
      ensureArrayIndexType "fixed array index" (← inferExprType module env index)
      match ← inferEventFieldExprType module env array with
      | .fixedArray elementType length => do
          match literalArrayIndex? index with
          | some indexValue =>
              ensureFixedArrayIndexInBounds "fixed array index" indexValue length
          | none => pure ()
          .ok elementType
      | other => .error { message := s!"fixed array indexing target expected `Array`, got `{other.name}`" }
  | .structLit typeName fields => do
      if fields.isEmpty then
        .error { message := s!"struct literal `{typeName}` must have at least one field" }
      let some decl := findStruct? module typeName
        | .error { message := s!"unknown struct `{typeName}`" }
      if decl.fields.size != fields.size then
        .error { message := s!"struct literal `{typeName}` expected {decl.fields.size} field(s), got {fields.size}" }
      for field in fields do
        let expected ← structFieldType module typeName field.fst
        let actual ← inferEventFieldExprType module env field.snd
        ensureType s!"struct literal `{typeName}` field `{field.fst}`" expected actual
      for expectedField in decl.fields do
        if !(fields.any fun field => field.fst == expectedField.id) then
          .error { message := s!"struct literal `{typeName}` is missing field `{expectedField.id}`" }
      .ok (.structType typeName)
  | .field base fieldName => do
      match ← inferEventFieldExprType module env base with
      | .structType typeName =>
          structFieldType module typeName fieldName
      | other => .error { message := s!"field `{fieldName}` requires struct value, got `{other.name}`" }
  | .effect effect =>
      inferEffectExprType module env effect
  | other =>
      inferExprType module env other

def eventSignature
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (fields : Array (String × ProofForge.IR.Expr)) : Except LowerError String := do
  validateEventName name
  let _ ← fields.foldlM (init := #[]) fun seen field =>
    validateDistinctEventFieldName name seen field.fst
  let mut typeNames := #[]
  for field in fields do
    let actual ← inferEventFieldExprType module env field.snd
    typeNames := typeNames.push (← eventSignatureFieldType module name field.fst actual)
  .ok (name ++ "(" ++ String.intercalate "," typeNames.toList ++ ")")

def validateEffectStmtTypes (module : Module) (env : TypeEnv) : Effect → Except LowerError Unit
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      ensureType s!"scalar state `{stateId}` write" (← scalarStateType module stateId) (← inferExprType module env value)
  | .storageScalarAssignOp stateId op value => do
      ensureAssignOpTypes op (← scalarStateType module stateId) (← inferExprType module env value)
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
      ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
  | .storageMapSet stateId key value => do
      let (keyType, valueType) ← mapStateTypes module stateId
      ensureType s!"map `{stateId}` key" keyType (← inferExprType module env key)
      ensureType s!"map `{stateId}` value" valueType (← inferExprType module env value)
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value => do
      let (_, _, elementType) ← requireStorageArrayState module stateId
      ensureArrayIndexType s!"array state `{stateId}` index" (← inferExprType module env index)
      ensureType s!"array state `{stateId}` write" elementType (← inferExprType module env value)
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      let (_, _, _, _, field) ← requireStructArrayStateField module stateId fieldName
      ensureArrayIndexType s!"struct array state `{stateId}` index" (← inferExprType module env index)
      ensureType s!"struct array state `{stateId}` field `{fieldName}` write" field.type (← inferExprType module env value)
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value => do
      let (_, field) ← requireStructStateField module stateId fieldName
      ensureType s!"struct state `{stateId}` field `{fieldName}` write" field.type (← inferExprType module env value)
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value => do
      ensureType s!"storage path `{stateId}` write" (← inferStoragePathType module env stateId path) (← inferExprType module env value)
  | .storagePathAssignOp stateId path op value => do
      ensureAssignOpTypes op (← inferStoragePathType module env stateId path) (← inferExprType module env value)
  | .contextRead _ =>
      .error { message := "context reads must be used as expressions" }
  | .eventEmit name fields => do
      discard <| eventSignature module env name fields
  | .eventEmitIndexed name indexedFields dataFields => do
      validateIndexedEventFieldCount name indexedFields.size
      for field in indexedFields do
        ensureIndexedEventFieldType module name field.fst (← inferEventFieldExprType module env field.snd)
      discard <| eventSignature module env name (indexedFields ++ dataFields)

def requireMutableLocal (env : TypeEnv) (context name : String) : Except LowerError LocalBinding := do
  let some binding := findLocal? env name
    | .error { message := s!"unknown local `{name}`" }
  if !binding.isMutable then
    .error { message := s!"{context} local `{name}` is not mutable" }
  .ok binding

partial def validateFixedArrayIndexPathTarget
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (type : ValueType)
    (path : Array ProofForge.IR.Expr) : Except LowerError ValueType := do
  match path.toList with
  | [] => .ok type
  | index :: rest =>
      match type with
      | .fixedArray elementType length => do
          ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
          match literalArrayIndex? index with
          | some indexValue => ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
          | none => pure ()
          validateFixedArrayIndexPathTarget module env context elementType rest.toArray
      | other =>
          .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

def validateLocalFixedArrayTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (index value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  match binding.type with
  | .fixedArray elementType length => do
      ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
      match literalArrayIndex? index with
      | some indexValue =>
          ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
      | none => pure ()
      ensureType s!"{context} value" elementType (← inferExprType module env value)
      match elementType with
      | .u32 | .u64 | .bool | .hash | .address => pure ()
      | .structType _ =>
          .error {
            message := s!"{context} local `{name}` returns struct values; IR EVM v0 requires field assignment such as array[index].field"
          }
      | .unit | .fixedArray _ _ | .bytes | .string =>
          .error {
            message := s!"{context} local `{name}` has unsupported EVM IR v0 element target type `{elementType.name}`; local fixed-array element targets must resolve to U32, U64, Bool, or Hash leaves"
          }
      .ok elementType
  | other =>
      .error { message := s!"{context} local `{name}` expected fixed-array target, got `{other.name}`" }

def validateLocalFixedArrayStaticPathTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (path : Array ProofForge.IR.Expr)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  let targetType ← validateFixedArrayIndexPathTarget module env context binding.type path
  ensureType s!"{context} value" targetType (← inferExprType module env value)
  match targetType with
  | .u32 | .u64 | .bool | .hash | .address => .ok targetType
  | .structType _ =>
      .error {
        message := s!"{context} local `{name}` returns struct values; IR EVM v0 requires field assignment such as array[index].field"
      }
  | .unit | .fixedArray _ _ | .bytes | .string =>
      .error {
        message := s!"{context} local `{name}` has unsupported EVM IR v0 element target type `{targetType.name}`; local fixed-array element targets must resolve to U32, U64, Bool, or Hash leaves"
      }

def validateLocalStructTarget
    (module : Module)
    (env : TypeEnv)
    (context name fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  match binding.type with
  | .structType typeName => do
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      ensureType s!"{context} value" fieldType (← inferExprType module env value)
      .ok fieldType
  | other =>
      .error { message := s!"{context} local `{name}` expected struct target, got `{other.name}`" }

def validateLocalStructArrayFieldTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (index : ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  discard <| requireMutableLocal env context name
  let (_, length, fieldType) ← requireLocalFixedStructArrayField module env context name fieldName
  ensureArrayIndexType s!"{context} fixed-array index" (← inferExprType module env index)
  match literalArrayIndex? index with
  | some indexValue =>
      ensureFixedArrayIndexInBounds s!"{context} fixed-array index" indexValue length
  | none => pure ()
  ensureType s!"{context} value" fieldType (← inferExprType module env value)
  .ok fieldType

def validateLocalFixedArrayPathFieldTarget
    (module : Module)
    (env : TypeEnv)
    (context name : String)
    (path : Array ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError ValueType := do
  let binding ← requireMutableLocal env context name
  let targetType ← validateFixedArrayIndexPathTarget module env context binding.type path
  match targetType with
  | .structType typeName => do
      discard <| ensureLocalFlatStructType module s!"{context} local `{name}` fixed-array leaf" typeName
      let fieldType ← structFieldType module typeName fieldName
      ensureStructLocalFieldType typeName fieldName fieldType
      ensureType s!"{context} value" fieldType (← inferExprType module env value)
      .ok fieldType
  | other =>
      .error {
        message := s!"{context} local `{name}` field target expected flat struct leaf, got `{other.name}`"
      }

def validateAssignTarget
    (module : Module)
    (env : TypeEnv)
    (target value : ProofForge.IR.Expr) : Except LowerError Unit := do
  let validateDefault : Except LowerError Unit := do
    match target with
    | .local name => do
        let binding ← requireMutableLocal env "assignment target" name
        match binding.type with
        | .fixedArray elementType _ => do
            match elementType with
            | .u32 | .u64 | .bool | .hash | .address => pure ()
            | .fixedArray _ _ =>
                ensureLocalNestedFixedArrayValueType module "assignment target" name elementType
            | .structType typeName =>
                discard <| ensureLocalFlatStructType module s!"assignment target `{name}` fixed-array element" typeName
            | .unit | .bytes | .string =>
                .error {
                  message := s!"assignment target `{name}` has unsupported EVM IR v0 fixed-array element type `{elementType.name}`; local fixed arrays support U32, U64, Bool, Hash, flat struct elements, or nested fixed arrays with scalar or flat struct leaves"
                }
            ensureType "assignment value" binding.type (← inferExprType module env value)
        | .structType typeName => do
            let some decl := findStruct? module typeName
              | .error { message := s!"unknown struct `{typeName}`" }
            for field in decl.fields do
              ensureStructLocalFieldType typeName field.id field.type
            ensureType "assignment value" binding.type (← inferExprType module env value)
        | _ =>
            ensureType "assignment value" binding.type (← inferExprType module env value)
    | .arrayGet (.local name) index => do
        discard <| validateLocalFixedArrayTarget module env "assignment target" name index value
    | .field (.arrayGet (.local name) index) fieldName => do
        discard <| validateLocalStructArrayFieldTarget module env "assignment target" name index fieldName value
    | .field (.local name) fieldName => do
        discard <| validateLocalStructTarget module env "assignment target" name fieldName value
    | _ =>
        .error { message := "assignment target must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  match collectLocalArrayFieldGetPath target with
  | some (name, path, fieldName) =>
      if path.size > 1 then
        discard <| validateLocalFixedArrayPathFieldTarget module env "assignment target" name path fieldName value
      else
        validateDefault
  | none =>
      match collectLocalArrayGetPath target with
      | some (name, path) =>
          if path.size > 1 then
            discard <| validateLocalFixedArrayStaticPathTarget module env "assignment target" name path value
          else
            validateDefault
      | none =>
          validateDefault

def validateAssignOpTarget
    (module : Module)
    (env : TypeEnv)
    (target : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Unit := do
  let validateDefault : Except LowerError Unit := do
    match target with
    | .local name => do
        let binding ← requireMutableLocal env "compound assignment target" name
        ensureAssignOpTypes op binding.type (← inferExprType module env value)
    | .arrayGet (.local name) index => do
        let targetType ← validateLocalFixedArrayTarget module env "compound assignment target" name index value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | .field (.arrayGet (.local name) index) fieldName => do
        let targetType ← validateLocalStructArrayFieldTarget module env "compound assignment target" name index fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | .field (.local name) fieldName => do
        let targetType ← validateLocalStructTarget module env "compound assignment target" name fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
    | _ =>
        .error { message := "compound assignment target must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  match collectLocalArrayFieldGetPath target with
  | some (name, path, fieldName) =>
      if path.size > 1 then
        let targetType ← validateLocalFixedArrayPathFieldTarget module env "compound assignment target" name path fieldName value
        ensureAssignOpTypes op targetType (← inferExprType module env value)
      else
        validateDefault
  | none =>
      match collectLocalArrayGetPath target with
      | some (name, path) =>
          if path.size > 1 then
            let targetType ← validateLocalFixedArrayStaticPathTarget module env "compound assignment target" name path value
            ensureAssignOpTypes op targetType (← inferExprType module env value)
          else
            validateDefault
      | none =>
          validateDefault

mutual
  partial def validateStatements (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) (statements : Array Statement) : Except LowerError TypeEnv :=
    statements.foldlM (init := env) fun env stmt =>
      validateStatementTypes module entrypoint env stmt

  partial def validateStatementTypes (module : Module) (entrypoint : Entrypoint) (env : TypeEnv) : Statement → Except LowerError TypeEnv
    | .letBind name type value => do
        ensureType s!"let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type false
    | .letMutBind name type value => do
        ensureType s!"mutable let binding `{name}`" type (← inferExprType module env value)
        addLocal env name type true
    | .assign target value => do
        validateAssignTarget module env target value
        .ok env
    | .assignOp target op value => do
        validateAssignOpTarget module env target op value
        .ok env
    | .effect effect => do
        validateEffectStmtTypes module env effect
        .ok env
    | .assert condition _ _ => do
        ensureType "assert condition" .bool (← inferExprType module env condition)
        .ok env
    | .assertEq lhs rhs _ _ => do
        let lhsType ← inferExprType module env lhs
        let rhsType ← inferExprType module env rhs
        ensureType "assert_eq right operand" lhsType rhsType
        ensureEqType "assert_eq" lhsType
        .ok env
    | .release _ =>
        .error { message := "release statements are not supported by IR EVM v0" }
    | .ifElse condition thenBody elseBody => do
        ensureType "if condition" .bool (← inferExprType module env condition)
        discard <| validateStatements module entrypoint env thenBody
        discard <| validateStatements module entrypoint env elseBody
        .ok env
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        discard <| validateStatements module entrypoint loopEnv body
        .ok env
    | .return value => do
        ensureType "return value" entrypoint.returns (← inferExprType module env value)
        .ok env
end

def entrypointTypeEnv (entrypoint : Entrypoint) : TypeEnv :=
  entrypoint.params.map fun param => {
    name := param.fst
    type := param.snd
    isMutable := false
  }

def validateEntrypointTypes (module : Module) (entrypoint : Entrypoint) : Except LowerError Unit := do
  discard <| validateStatements module entrypoint (entrypointTypeEnv entrypoint) entrypoint.body

mutual
  partial def lowerStorageSlotPlanExpr
      (module : Module)
      (env : TypeEnv)
      (plan : ProofForge.Backend.Evm.Plan.StorageSlotPlan) :
      Except LowerError Lean.Compiler.Yul.Expr :=
    ProofForge.Backend.Evm.ToYul.storageSlotExpr
      toYulError
      (fun expr => lowerExpr module env expr)
      plan

  partial def lowerScalarStorageSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.scalarSlotPlan module stateId
    lowerStorageSlotPlanExpr module env plan

  partial def lowerMapSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (key : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageMapState module stateId
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.mapValueSlotPlan module stateId #[key]
    lowerStorageSlotPlanExpr module env plan

  partial def lowerMapGetExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (key : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    .ok (Lean.Compiler.Yul.builtin "sload" #[← lowerMapSlotExpr module env stateId key])

  partial def lowerMapContainsExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (key : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageMapState module stateId
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.mapPresenceSlotPlan module stateId #[key]
    .ok (Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "sload" #[
          ← lowerStorageSlotPlanExpr module env plan
        ]
      ]
    ])

  partial def lowerMapScalarPlanExprOrFallback
      (module : Module)
      (env : TypeEnv)
      (expr : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let lowerEffect : ProofForge.Backend.Evm.Plan.EffectPlan → Except LowerError Lean.Compiler.Yul.Expr
      | .storageScalarRead stateId => do
          match ← scalarStateType module stateId with
          | .structType _ =>
              .error {
                message := s!"storage.scalar.read for struct state `{stateId}` must be consumed by a struct local binding, struct field access, or struct return in IR EVM v0"
              }
          | _ => pure ()
          let storageSlot ← lowerScalarStorageSlotExpr module env stateId
          .ok (Lean.Compiler.Yul.builtin "sload" #[storageSlot])
      | .contextRead (.blockHash blockNumber) => do
          .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerExpr module env blockNumber])
      | .contextRead field =>
          .ok (contextExpr field)
      | _ =>
          .error { message := "EVM map write plan-to-Yul scalar lowering does not support this effect plan yet" }
    match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) expr with
    | .ok plan =>
        match ProofForge.Backend.Evm.ToYul.exprPlanExpr
            toYulError
            (fun raw => lowerExpr module env raw)
            lowerEffect
            plan with
        | .ok lowered => .ok lowered
        | .error _ => lowerExpr module env expr
    | .error _ => lowerExpr module env expr

  partial def lowerMapSetReturnExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (key value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (slot, _, _) ← requireStorageMapState module stateId
    .ok (Lean.Compiler.Yul.call mapSetReturnFunctionName #[
      slotExpr slot,
      ← lowerMapScalarPlanExprOrFallback module env key,
      ← lowerMapScalarPlanExprOrFallback module env value
    ])

  partial def lowerMapPathValueSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (keys : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageMapState module stateId
    if keys.isEmpty then
      .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.mapValueSlotPlan module stateId keys
    lowerStorageSlotPlanExpr module env plan

  partial def lowerMapPathPresenceSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (keys : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageMapState module stateId
    if keys.isEmpty then
      .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.mapPresenceSlotPlan module stateId keys
    lowerStorageSlotPlanExpr module env plan

  partial def lowerMapPathReadExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (keys : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    .ok (Lean.Compiler.Yul.builtin "sload" #[← lowerMapPathValueSlotExpr module env stateId keys])

  partial def lowerArraySlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStorageArrayState module stateId
    let plan ← lowerPlan <| ProofForge.Backend.Evm.Plan.arraySlotPlan module stateId index
    lowerStorageSlotPlanExpr module env plan

  partial def lowerArrayReadExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    .ok (Lean.Compiler.Yul.builtin "sload" #[← lowerArraySlotExpr module env stateId index])

  partial def lowerStructFieldSlotExpr
      (module : Module)
      (stateId fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (slot, _) ← requireStructStateField module stateId fieldName
    .ok (slotExpr slot)

  partial def lowerStructFieldReadExpr
      (module : Module)
      (stateId fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    .ok (Lean.Compiler.Yul.builtin "sload" #[← lowerStructFieldSlotExpr module stateId fieldName])

  partial def lowerStructArrayFieldSlotExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (index : ProofForge.IR.Expr)
      (fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    discard <| requireStructArrayStateField module stateId fieldName
    let plan ← lowerPlan <|
      ProofForge.Backend.Evm.Plan.structArrayFieldSlotPlan module stateId index fieldName
    lowerStorageSlotPlanExpr module env plan

  partial def lowerStructArrayFieldReadExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (index : ProofForge.IR.Expr)
      (fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    .ok (Lean.Compiler.Yul.builtin "sload" #[← lowerStructArrayFieldSlotExpr module env stateId index fieldName])

  partial def lowerStoragePathReadExpr
      (module : Module)
      (env : TypeEnv)
      (stateId : String)
      (path : Array StoragePathSegment) : Except LowerError Lean.Compiler.Yul.Expr :=
    match path.toList with
    | [StoragePathSegment.mapKey key] => lowerMapGetExpr module env stateId key
    | [StoragePathSegment.index index] => lowerArrayReadExpr module env stateId index
    | [StoragePathSegment.field fieldName] => lowerStructFieldReadExpr module stateId fieldName
    | [StoragePathSegment.index index, StoragePathSegment.field fieldName] =>
        lowerStructArrayFieldReadExpr module env stateId index fieldName
    | [] => do
        let state ← stateDeclOf module stateId "storage path"
        match state.kind with
        | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
        | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
        | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.read" }
    | _ => do
        match storagePathMapKeys? path with
        | some keys => lowerMapPathReadExpr module env stateId keys
        | none =>
            .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

  partial def validateFixedArrayIndexExprPath
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (type : ValueType)
      (path : Array ProofForge.IR.Expr) : Except LowerError (Array Nat × ValueType) := do
    match path.toList with
    | [] => .ok (#[], type)
    | index :: rest =>
        match type with
        | .fixedArray elementType length => do
            ensureArrayIndexType context (← inferExprType module env index)
            match literalArrayIndex? index with
            | some indexValue => ensureFixedArrayIndexInBounds context indexValue length
            | none => pure ()
            let (nestedLengths, leafType) ← validateFixedArrayIndexExprPath module env context elementType rest.toArray
            .ok (#[length] ++ nestedLengths, leafType)
        | other =>
            .error { message := s!"{context} target expected `Array`, got `{other.name}`" }

  partial def lowerDynamicNestedLocalFixedArrayGetExpr
      (module : Module)
      (env : TypeEnv)
      (name : String)
      (binding : LocalBinding)
      (path : Array ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (lengths, leafType) ← validateFixedArrayIndexExprPath module env "fixed array index" binding.type path
    match leafType with
    | .u32 | .u64 | .bool | .hash | .address => pure ()
    | .structType _ =>
        .error {
          message := s!"fixed array indexing local `{name}` returns struct values; IR EVM v0 requires field access such as array[index].field"
        }
    | .unit | .fixedArray _ _ | .bytes | .string =>
        .error {
          message := s!"fixed array indexing local `{name}` has unsupported EVM IR v0 element type `{leafType.name}`"
        }
    let leafPaths := nestedLocalArrayLeafPaths lengths
    let mut args : Array Lean.Compiler.Yul.Expr := #[]
    for index in path do
      args := args.push (← lowerExpr module env index)
    for leafPath in leafPaths do
      args := args.push (Lean.Compiler.Yul.Expr.id (arrayLocalPathName name leafPath))
    .ok (Lean.Compiler.Yul.call (nestedLocalArrayGetFunctionName lengths) args)

  partial def lowerLocalFixedArrayGetExpr
      (module : Module)
      (env : TypeEnv)
      (array index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
    let fullExpr := ProofForge.IR.Expr.arrayGet array index
    match collectLocalArrayGetPath fullExpr with
    | some (name, path) =>
        if path.size > 1 && arrayIndexPathHasDynamic path then
          let some binding := findLocal? env name
            | .error { message := s!"unknown local `{name}`" }
          lowerDynamicNestedLocalFixedArrayGetExpr module env name binding path
        else
          match collectStaticLocalArrayGetPath fullExpr with
          | some (name, path) => do
              let some binding := findLocal? env name
                | .error { message := s!"unknown local `{name}`" }
              let elementType ← fixedArrayPathType "fixed array index" binding.type path
              match elementType with
              | .u32 | .u64 | .bool | .hash | .address =>
                  .ok (Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path))
              | .structType _ =>
                  .error {
                    message := s!"fixed array indexing local `{name}` returns struct values; IR EVM v0 requires field access such as array[index].field"
                  }
              | .unit | .fixedArray _ _ | .bytes | .string =>
                  .error {
                    message := s!"fixed array indexing local `{name}` has unsupported EVM IR v0 element type `{elementType.name}`"
                  }
          | none =>
              lowerLocalFixedArrayGetExprFallback module env array index
    | none =>
        lowerLocalFixedArrayGetExprFallback module env array index

  partial def lowerLocalFixedArrayGetExprFallback
      (module : Module)
      (env : TypeEnv)
      (array index : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr :=
    match array with
    | .local name => do
        let (elementType, length) ← requireLocalFixedArray "fixed array indexing" env name
        match elementType with
        | .structType _ =>
            .error {
              message := s!"fixed array indexing local `{name}` returns struct values; IR EVM v0 requires field access such as array[index].field"
            }
        | .unit | .fixedArray _ _ | .bytes | .string =>
            .error {
              message := s!"fixed array indexing local `{name}` has unsupported EVM IR v0 element type `{elementType.name}`"
            }
        | .u32 | .u64 | .bool | .hash | .address => pure ()
        match literalArrayIndex? index with
        | some indexValue => do
            ensureFixedArrayIndexInBounds "fixed array index" indexValue length
            .ok (Lean.Compiler.Yul.Expr.id (arrayLocalElementName name indexValue))
        | none => do
            let mut values : Array Lean.Compiler.Yul.Expr := #[]
            for h : idx in [0:length] do
              values := values.push (Lean.Compiler.Yul.Expr.id (arrayLocalElementName name idx))
            .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName length) (#[← lowerExpr module env index] ++ values))
    | .arrayLit _ values =>
        match literalArrayIndex? index with
        | some indexValue =>
            if h : indexValue < values.size then
              lowerExpr module env values[indexValue]
            else
              .error { message := s!"fixed array literal index {indexValue} is out of bounds for length {values.size}" }
        | none => do
            let mut loweredValues : Array Lean.Compiler.Yul.Expr := #[]
            for h : idx in [0:values.size] do
              loweredValues := loweredValues.push (← lowerExpr module env values[idx])
            .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName values.size) (#[← lowerExpr module env index] ++ loweredValues))
    | _ =>
        .error {
          message := "fixed array indexing in IR EVM v0 supports local fixed-array values or array literals only"
        }

  partial def lowerNestedLocalStructFieldGetExpr
      (module : Module)
      (env : TypeEnv)
      (name : String)
      (binding : LocalBinding)
      (path : Array ProofForge.IR.Expr)
      (fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr := do
    let (lengths, leafType) ← validateFixedArrayIndexExprPath module env "struct field fixed-array index" binding.type path
    match leafType with
    | .structType typeName => do
        discard <| ensureLocalFlatStructType module s!"struct field access local `{name}` fixed-array leaf" typeName
        let fieldType ← structFieldType module typeName fieldName
        ensureStructLocalFieldType typeName fieldName fieldType
    | other =>
        .error {
          message := s!"struct field access local `{name}` fixed-array leaf expected flat struct, got `{other.name}`"
        }
    if arrayIndexPathHasDynamic path then do
      let leafPaths := nestedLocalArrayLeafPaths lengths
      let mut args : Array Lean.Compiler.Yul.Expr := #[]
      for index in path do
        args := args.push (← lowerExpr module env index)
      for leafPath in leafPaths do
        args := args.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalPathFieldName name leafPath fieldName))
      .ok (Lean.Compiler.Yul.call (nestedLocalArrayGetFunctionName lengths) args)
    else do
      let mut staticPath : Array Nat := #[]
      for index in path do
        staticPath := staticPath.push (← requireStaticArrayIndex "struct field fixed-array index" index)
      .ok (Lean.Compiler.Yul.Expr.id (arrayStructLocalPathFieldName name staticPath fieldName))

  partial def lowerLocalStructFieldExpr
      (module : Module)
      (env : TypeEnv)
      (base : ProofForge.IR.Expr)
      (fieldName : String) : Except LowerError Lean.Compiler.Yul.Expr :=
    match base with
    | .local name =>
        .ok (Lean.Compiler.Yul.Expr.id (structLocalFieldName name fieldName))
    | .effect (.storageScalarRead stateId) =>
        lowerStructFieldReadExpr module stateId fieldName
    | .arrayGet (.local name) index => do
        let (_, length, _) ← requireLocalFixedStructArrayField module env "struct field access" name fieldName
        match literalArrayIndex? index with
        | some indexValue => do
            ensureFixedArrayIndexInBounds "struct field fixed-array index" indexValue length
            .ok (Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName name indexValue fieldName))
        | none => do
            let mut values : Array Lean.Compiler.Yul.Expr := #[]
            for _h : idx in [0:length] do
              values := values.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName name idx fieldName))
            .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName length) (#[← lowerExpr module env index] ++ values))
    | .structLit _ fields => do
        let some field := fields.find? fun field => field.fst == fieldName
          | .error { message := s!"struct literal has no field `{fieldName}`" }
        lowerExpr module env field.snd
    | _ =>
        match collectLocalArrayGetPath base with
        | some (name, path) =>
            if path.size > 1 then do
              let some binding := findLocal? env name
                | .error { message := s!"unknown local `{name}`" }
              lowerNestedLocalStructFieldGetExpr module env name binding path fieldName
            else
              .error {
                message := "struct field access in IR EVM v0 supports local struct values, local struct-array values, nested local fixed-array struct leaves, or struct literals only"
              }
        | none =>
            .error {
              message := "struct field access in IR EVM v0 supports local struct values, local struct-array values, nested local fixed-array struct leaves, or struct literals only"
            }

  partial def lowerLocalAbiWordsAt
      (module : Module)
      (context name : String)
      (path : Array Nat) : ValueType → Except LowerError (Array Lean.Compiler.Yul.Expr)
    | .u32 | .u64 | .bool | .hash | .address =>
        if path.isEmpty then
          .ok #[Lean.Compiler.Yul.Expr.id name]
        else
          .ok #[Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path)]
    | .unit =>
        .error { message := s!"{context} uses Unit; IR EVM v0 ABI values must use U32, U64, Bool, Hash, Address, Bytes, String, fixed arrays, or structs" }
    | .bytes | .string =>
        -- Dynamic locals: return the data_ptr (memory pointer to length+data)
        if path.isEmpty then
          .ok #[Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName name)]
        else
          .error { message := s!"{context} dynamic type cannot be nested in fixed arrays" }
    | .fixedArray elementType length => do
        discard <| abiValueWordTypes module context (.fixedArray elementType length)
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for _h : idx in [0:length] do
          words := words ++ (← lowerLocalAbiWordsAt module context name (path.push idx) elementType)
        .ok words
    | .structType typeName => do
        discard <| abiValueWordTypes module context (.structType typeName)
        let some decl := findStruct? module typeName
          | .error { message := s!"{context} uses unknown struct `{typeName}`" }
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for fieldDecl in decl.fields do
          ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
          let fieldName :=
            if path.isEmpty then
              structLocalFieldName name fieldDecl.id
            else
              arrayStructLocalPathFieldName name path fieldDecl.id
          words := words.push (Lean.Compiler.Yul.Expr.id fieldName)
        .ok words

  partial def lowerLocalAbiWords
      (module : Module)
      (env : TypeEnv)
      (context name : String)
      (expectedType : ValueType) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    let some binding := findLocal? env name
      | .error { message := s!"unknown local `{name}`" }
    ensureType context expectedType binding.type
    lowerLocalAbiWordsAt module context name #[] expectedType

  partial def lowerLocalCrosscallWordsAt
      (module : Module)
      (context name : String)
      (path : Array Nat) : ValueType → Except LowerError (Array Lean.Compiler.Yul.Expr)
    | .u32 | .u64 | .bool | .hash | .address =>
        if path.isEmpty then
          .ok #[Lean.Compiler.Yul.Expr.id name]
        else
          .ok #[Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path)]
    | .unit | .bytes | .string =>
        .error { message := s!"{context} uses Unit; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, fixed arrays, or structs" }
    | .fixedArray elementType length => do
        discard <| crosscallValueWordTypes module context (.fixedArray elementType length)
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for _h : idx in [0:length] do
          words := words ++ (← lowerLocalCrosscallWordsAt module context name (path.push idx) elementType)
        .ok words
    | .structType typeName => do
        discard <| crosscallValueWordTypes module context (.structType typeName)
        let some decl := findStruct? module typeName
          | .error { message := s!"{context} uses unknown struct `{typeName}`" }
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for fieldDecl in decl.fields do
          ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
          let fieldName :=
            if path.isEmpty then
              structLocalFieldName name fieldDecl.id
            else
              arrayStructLocalPathFieldName name path fieldDecl.id
          words := words.push (Lean.Compiler.Yul.Expr.id fieldName)
        .ok words

  partial def lowerLocalCrosscallWords
      (module : Module)
      (env : TypeEnv)
      (context name : String)
      (expectedType : ValueType) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    let some binding := findLocal? env name
      | .error { message := s!"unknown local `{name}`" }
    ensureType context expectedType binding.type
    lowerLocalCrosscallWordsAt module context name #[] expectedType

  partial def lowerCrosscallStructArgWords
      (module : Module)
      (env : TypeEnv)
      (context typeName : String)
      (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    discard <| crosscallArgWordTypes module context (.structType typeName)
    let some decl := findStruct? module typeName
      | .error { message := s!"{context} uses unknown struct `{typeName}`" }
    match value with
    | .local name => do
        let some binding := findLocal? env name
          | .error { message := s!"unknown local `{name}`" }
        ensureType context (.structType typeName) binding.type
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for fieldDecl in decl.fields do
          ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
          words := words.push (Lean.Compiler.Yul.Expr.id (structLocalFieldName name fieldDecl.id))
        .ok words
    | .structLit literalTypeName fields => do
        if literalTypeName != typeName then
          .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for fieldDecl in decl.fields do
          ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
          let some field := fields.find? fun field => field.fst == fieldDecl.id
            | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
          words := words.push (← lowerExpr module env field.snd)
        .ok words
    | .effect (.storageScalarRead stateId) => do
        let fields ← lowerStructStorageReadFields module context typeName stateId
        .ok (fields.map fun field => field.snd)
    | _ =>
        .error {
          message := s!"{context} struct values in IR EVM v0 support local struct values, struct literals, or storage scalar struct reads only"
        }

  partial def lowerCrosscallStructArrayArgWords
      (module : Module)
      (env : TypeEnv)
      (context typeName : String)
      (length : Nat)
      (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    discard <| crosscallArgWordTypes module context (.fixedArray (.structType typeName) length)
    let some decl := findStruct? module typeName
      | .error { message := s!"{context} uses unknown struct `{typeName}`" }
    match value with
    | .local name => do
        let (sourceElementType, sourceLength) ← requireLocalFixedArray context env name
        ensureType s!"{context} fixed-array element type" (.structType typeName) sourceElementType
        if sourceLength != length then
          .error { message := s!"{context} fixed-array expected length {length}, got {sourceLength}" }
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for _h : idx in [0:length] do
          for fieldDecl in decl.fields do
            ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
            words := words.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName name idx fieldDecl.id))
        .ok words
    | .arrayLit literalElementType values => do
        ensureType s!"{context} fixed-array element type" (.structType typeName) literalElementType
        if values.size != length then
          .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
        let mut words : Array Lean.Compiler.Yul.Expr := #[]
        for h : idx in [0:values.size] do
          match values[idx] with
          | .structLit literalTypeName fields => do
              if literalTypeName != typeName then
                .error { message := s!"{context} fixed-array element {idx} expected struct `{typeName}`, got `{literalTypeName}`" }
              for fieldDecl in decl.fields do
                ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
                let some field := fields.find? fun field => field.fst == fieldDecl.id
                  | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
                words := words.push (← lowerExpr module env field.snd)
          | other =>
              let actualType ← inferExprType module env other
              .error {
                message := s!"{context} fixed-array element {idx} expected struct literal `{typeName}`, got `{actualType.name}`"
              }
        .ok words
    | _ =>
        .error {
          message := s!"{context} fixed-array struct values in IR EVM v0 support local fixed-array values or array literals only"
        }

  partial def lowerCrosscallFixedArrayArgWords
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (elementType : ValueType)
      (length : Nat)
      (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    discard <| crosscallArgWordTypes module context (.fixedArray elementType length)
    match elementType with
    | .structType typeName =>
        lowerCrosscallStructArrayArgWords module env context typeName length value
    | .fixedArray nestedElementType nestedLength =>
        match value with
        | .local name =>
            lowerLocalCrosscallWords module env context name (.fixedArray elementType length)
        | .arrayLit literalElementType values => do
            ensureType s!"{context} fixed-array element type" elementType literalElementType
            if values.size != length then
              .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
            let mut words : Array Lean.Compiler.Yul.Expr := #[]
            for h : idx in [0:values.size] do
              words := words ++ (← lowerCrosscallFixedArrayArgWords module env context nestedElementType nestedLength values[idx])
            .ok words
        | _ =>
            .error {
              message := s!"{context} nested fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
            }
    | _ => do
        match value with
        | .local name => do
            lowerLocalCrosscallWords module env context name (.fixedArray elementType length)
        | .arrayLit literalElementType values => do
            ensureType s!"{context} fixed-array element type" elementType literalElementType
            if values.size != length then
              .error { message := s!"{context} fixed-array expected length {length}, got {values.size}" }
            let mut words : Array Lean.Compiler.Yul.Expr := #[]
            for h : idx in [0:values.size] do
              words := words.push (← lowerExpr module env values[idx])
            .ok words
        | _ =>
            .error {
              message := s!"{context} fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
            }

  partial def lowerCrosscallArgWords
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (arg : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    let type ← inferExprType module env arg
    discard <| crosscallArgWordTypes module context type
    match type with
    | .u32 | .u64 | .bool | .hash | .address =>
        .ok #[← lowerExpr module env arg]
    | .fixedArray elementType length =>
        lowerCrosscallFixedArrayArgWords module env context elementType length arg
    | .structType typeName =>
        lowerCrosscallStructArgWords module env context typeName arg
    | .unit | .bytes | .string =>
        .error { message := s!"{context} uses Unit; IR EVM v0 crosscall arguments must use U32, U64, Bool, Hash, fixed arrays, or structs" }

  partial def lowerCrosscallArgWordsMany
      (module : Module)
      (env : TypeEnv)
      (context : String)
      (args : Array ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
    let mut words : Array Lean.Compiler.Yul.Expr := #[]
    for arg in args do
      words := words ++ (← lowerCrosscallArgWords module env context arg)
    .ok words

  partial def lowerExpr (module : Module) (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError Lean.Compiler.Yul.Expr
    | .literal (.u32 value) => .ok (Lean.Compiler.Yul.Expr.num value)
    | .literal (.u64 value) => .ok (Lean.Compiler.Yul.Expr.num value)
    | .literal (.bool value) => .ok (if value then Lean.Compiler.Yul.Expr.num 1 else Lean.Compiler.Yul.Expr.num 0)
    | .literal (.hash4 a b c d) => do
        .ok (Lean.Compiler.Yul.Expr.num (← packedHashLiteral a b c d))
    | .literal (.address value) => .ok (Lean.Compiler.Yul.Expr.num value)
    | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
    | .arrayLit _ _ =>
        .error { message := "fixed array literals must be consumed by a fixed array local binding or literal index in IR EVM v0" }
    | .arrayGet array index =>
        lowerLocalFixedArrayGetExpr module env array index
    | .structLit _ _ =>
        .error { message := "struct literals must be consumed by a struct local binding or field access in IR EVM v0" }
    | .field base fieldName =>
        lowerLocalStructFieldExpr module env base fieldName
    | .add lhs rhs => do
        .ok (checkedAddExpr (← lowerExpr module env lhs) (← lowerExpr module env rhs))
    | .sub lhs rhs => do
        .ok (checkedSubExpr (← lowerExpr module env lhs) (← lowerExpr module env rhs))
    | .mul lhs rhs => do
        .ok (checkedMulExpr (← lowerExpr module env lhs) (← lowerExpr module env rhs))
    | .div lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "div" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .mod lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "mod" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .pow lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "exp" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .bitAnd lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "and" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .bitOr lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "or" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .bitXor lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "xor" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .shiftLeft lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "shl" #[← lowerExpr module env rhs, ← lowerExpr module env lhs])
    | .shiftRight lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "shr" #[← lowerExpr module env rhs, ← lowerExpr module env lhs])
    | .cast value _ => do
        lowerExpr module env value
    | .eq lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "eq" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .ne lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "eq" #[← lowerExpr module env lhs, ← lowerExpr module env rhs]])
    | .lt lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "lt" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .le lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "gt" #[← lowerExpr module env lhs, ← lowerExpr module env rhs]])
    | .gt lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "gt" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .ge lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "lt" #[← lowerExpr module env lhs, ← lowerExpr module env rhs]])
    | .boolAnd lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "and" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .boolOr lhs rhs => do
        .ok (Lean.Compiler.Yul.builtin "or" #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .boolNot value => do
        .ok (Lean.Compiler.Yul.builtin "iszero" #[← lowerExpr module env value])
    | .hashValue a b c d => do
        .ok (hashPackExpr (← lowerExpr module env a) (← lowerExpr module env b) (← lowerExpr module env c) (← lowerExpr module env d))
    | .hash preimage => do
        .ok (Lean.Compiler.Yul.call hashWordFunctionName #[← lowerExpr module env preimage])
    | .hashTwoToOne lhs rhs => do
        .ok (Lean.Compiler.Yul.call hashPairFunctionName #[← lowerExpr module env lhs, ← lowerExpr module env rhs])
    | .nativeValue =>
        .ok (Lean.Compiler.Yul.builtin "callvalue" #[])
    | .crosscallInvoke target methodId args => do
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        for arg in args do
          callArgs := callArgs.push (← lowerExpr module env arg)
        .ok (Lean.Compiler.Yul.call (← crosscallFunctionName args.size .u64) callArgs)
    | .crosscallInvokeTyped target methodId args returnType => do
        if !isCrosscallWordType returnType then
          .error { message := s!"typed aggregate crosscall return `{returnType.name}` must be consumed by aggregate return lowering in IR EVM v0" }
        let argWords ← lowerCrosscallArgWordsMany module env "typed crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        callArgs := callArgs ++ argWords
        .ok (Lean.Compiler.Yul.call (← crosscallFunctionName argWords.size returnType) callArgs)
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        if !isCrosscallWordType returnType then
          .error { message := s!"value aggregate crosscall return `{returnType.name}` must be consumed by aggregate return lowering in IR EVM v0" }
        if plainValueTransferCall? methodId args then
          .ok (Lean.Compiler.Yul.call (← crosscallValueFunctionName 0 returnType true) #[
            ← lowerExpr module env target,
            ← lowerExpr module env callValue
          ])
        else
          let argWords ← lowerCrosscallArgWordsMany module env "value crosscall argument" args
          let mut callArgs := #[
            ← lowerExpr module env target,
            ← lowerExpr module env methodId,
            ← lowerExpr module env callValue
          ]
          callArgs := callArgs ++ argWords
          .ok (Lean.Compiler.Yul.call (← crosscallValueFunctionName argWords.size returnType) callArgs)
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        if !isCrosscallWordType returnType then
          .error { message := s!"static aggregate crosscall return `{returnType.name}` must be consumed by aggregate return lowering in IR EVM v0" }
        let argWords ← lowerCrosscallArgWordsMany module env "static crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        callArgs := callArgs ++ argWords
        .ok (Lean.Compiler.Yul.call (← crosscallStaticFunctionName argWords.size returnType) callArgs)
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        if !isCrosscallWordType returnType then
          .error { message := s!"delegate aggregate crosscall return `{returnType.name}` must be consumed by aggregate return lowering in IR EVM v0" }
        let argWords ← lowerCrosscallArgWordsMany module env "delegate crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        callArgs := callArgs ++ argWords
        .ok (Lean.Compiler.Yul.call (← crosscallDelegateFunctionName argWords.size returnType) callArgs)
    | .crosscallCreate callValue initCodeHex => do
        .ok (Lean.Compiler.Yul.call (← createHelperFunctionName .create initCodeHex) #[
          ← lowerExpr module env callValue
        ])
    | .crosscallCreate2 callValue salt initCodeHex => do
        .ok (Lean.Compiler.Yul.call (← createHelperFunctionName .create2 initCodeHex) #[
          ← lowerExpr module env callValue,
          ← lowerExpr module env salt
        ])
    | .effect effect => lowerEffectExpr module env effect

  partial def lowerEffectExpr (module : Module) (env : TypeEnv) : Effect → Except LowerError Lean.Compiler.Yul.Expr
    | .storageScalarRead stateId => do
        match ← scalarStateType module stateId with
        | .structType _ =>
            .error {
              message := s!"storage.scalar.read for struct state `{stateId}` must be consumed by a struct local binding, struct field access, or struct return in IR EVM v0"
            }
        | _ => pure ()
        let storageSlot ← lowerScalarStorageSlotExpr module env stateId
        .ok (Lean.Compiler.Yul.builtin "sload" #[storageSlot])
    | .storageScalarWrite _ _ =>
        .error { message := "storage.scalar.write is a statement effect, not an expression" }
    | .storageScalarAssignOp _ _ _ =>
        .error { message := "storage.scalar.assign_op is a statement effect, not an expression" }
    | .storageMapContains stateId key =>
        lowerMapContainsExpr module env stateId key
    | .storageMapGet stateId key =>
        lowerMapGetExpr module env stateId key
    | .storageMapInsert stateId key value =>
        lowerMapSetReturnExpr module env stateId key value
    | .storageMapSet stateId key value =>
        lowerMapSetReturnExpr module env stateId key value
    | .storageArrayRead stateId index =>
        lowerArrayReadExpr module env stateId index
    | .storageArrayWrite _ _ _ =>
        .error { message := "storage.array.write is a statement effect, not an expression" }
    | .storageArrayStructFieldRead stateId index fieldName =>
        lowerStructArrayFieldReadExpr module env stateId index fieldName
    | .storageArrayStructFieldWrite _ _ _ _ =>
        .error { message := "storage.array.struct.field.write is a statement effect, not an expression" }
    | .storageStructFieldRead stateId fieldName =>
        lowerStructFieldReadExpr module stateId fieldName
    | .storageStructFieldWrite _ _ _ =>
        .error { message := "storage.struct.field.write is a statement effect, not an expression" }
    | .storagePathRead stateId path =>
        lowerStoragePathReadExpr module env stateId path
    | .storagePathWrite _ _ _ =>
        .error { message := "storage.path.write is a statement effect, not an expression" }
    | .storagePathAssignOp _ _ _ _ =>
        .error { message := "storage.path.assign_op is a statement effect, not an expression" }
    | .contextRead (.blockHash blockNumber) => do
        .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerExpr module env blockNumber])
    | .contextRead field =>
        .ok (contextExpr field)
    | .eventEmit _ _ =>
        .error { message := "event.emit is a statement effect, not an expression" }
    | .eventEmitIndexed _ _ _ =>
        .error { message := "event.emit.indexed is a statement effect, not an expression" }
end

partial def exprSupportsPlanScalarYul : ProofForge.IR.Expr → Bool
  | .literal _ => true
  | .local _ => true
  | .add lhs rhs
  | .sub lhs rhs
  | .mul lhs rhs
  | .div lhs rhs
  | .mod lhs rhs
  | .pow lhs rhs
  | .bitAnd lhs rhs
  | .bitOr lhs rhs
  | .bitXor lhs rhs
  | .shiftLeft lhs rhs
  | .shiftRight lhs rhs
  | .eq lhs rhs
  | .ne lhs rhs
  | .lt lhs rhs
  | .le lhs rhs
  | .gt lhs rhs
  | .ge lhs rhs
  | .boolAnd lhs rhs
  | .boolOr lhs rhs
  | .hashTwoToOne lhs rhs =>
      exprSupportsPlanScalarYul lhs && exprSupportsPlanScalarYul rhs
  | .cast value _ => exprSupportsPlanScalarYul value
  | .boolNot value
  | .hash value => exprSupportsPlanScalarYul value
  | .hashValue a b c d =>
      exprSupportsPlanScalarYul a &&
      exprSupportsPlanScalarYul b &&
      exprSupportsPlanScalarYul c &&
      exprSupportsPlanScalarYul d
  | .nativeValue => true
  | .effect (.storageScalarRead _) => true
  | .effect (.contextRead _) => true
  | .arrayLit _ _
  | .arrayGet _ _
  | .structLit _ _
  | .field _ _
  | .crosscallInvoke _ _ _
  | .crosscallInvokeTyped _ _ _ _
  | .crosscallInvokeValueTyped _ _ _ _ _
  | .crosscallInvokeStaticTyped _ _ _ _
  | .crosscallInvokeDelegateTyped _ _ _ _
  | .crosscallCreate _ _
  | .crosscallCreate2 _ _ _
  | .effect _ => false

partial def lowerPlanEffectExpr
    (module : Module)
    (env : TypeEnv) :
    ProofForge.Backend.Evm.Plan.EffectPlan → Except LowerError Lean.Compiler.Yul.Expr
  | .storageScalarRead stateId => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          .error {
            message := s!"storage.scalar.read for struct state `{stateId}` must be consumed by a struct local binding, struct field access, or struct return in IR EVM v0"
          }
      | _ => pure ()
      let storageSlot ← lowerScalarStorageSlotExpr module env stateId
      .ok (Lean.Compiler.Yul.builtin "sload" #[storageSlot])
  | .contextRead (.blockHash blockNumber) => do
      .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerExpr module env blockNumber])
  | .contextRead field =>
      .ok (ProofForge.Backend.Evm.ToYul.contextExpr field)
  | _ =>
      .error { message := "EVM ExprPlan-to-Yul scalar lowering does not support this effect plan yet" }

partial def lowerExprPlanExpr
    (module : Module)
    (env : TypeEnv)
    (plan : ProofForge.Backend.Evm.Plan.ExprPlan) :
    Except LowerError Lean.Compiler.Yul.Expr :=
  ProofForge.Backend.Evm.ToYul.exprPlanExpr
    toYulError
    (fun expr => lowerExpr module env expr)
    (lowerPlanEffectExpr module env)
    plan

partial def lowerExprViaPlan
    (module : Module)
    (env : TypeEnv)
    (expr : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr := do
  let plan ←
    match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) expr with
    | .ok plan => .ok plan
    | .error err => .error { message := err.message }
  lowerExprPlanExpr module env plan

partial def lowerScalarPlanExprOrFallback
    (module : Module)
    (env : TypeEnv)
    (expr : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Expr :=
  if exprSupportsPlanScalarYul expr then
    lowerExprViaPlan module env expr
  else
    lowerExpr module env expr

partial def lowerScalarBindingStmtPlanOrFallback
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (type : ValueType)
    (isMutable : Bool)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  if exprSupportsPlanScalarYul value then
    let valuePlan ←
      match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) value with
      | .ok plan => .ok plan
      | .error err => .error { message := err.message }
    let stmtPlan :=
      if isMutable then
        ProofForge.Backend.Evm.Plan.StmtPlan.letMutBind name type valuePlan
      else
        ProofForge.Backend.Evm.Plan.StmtPlan.letBind name type valuePlan
    ProofForge.Backend.Evm.ToYul.scalarBindingStmtPlanStatements
      toYulError
      (fun expr => lowerExpr module env expr)
      (lowerPlanEffectExpr module env)
      stmtPlan
  else
    .ok #[
      .varDecl
        #[({ name := name } : Lean.Compiler.Yul.TypedName)]
        (some (← lowerExpr module env value))
    ]

partial def lowerScalarAssertStmtPlanOrFallback
    (module : Module)
    (env : TypeEnv) :
    ProofForge.IR.Statement → Except LowerError (Array Lean.Compiler.Yul.Statement)
  | .assert condition message errorRef? => do
      if exprSupportsPlanScalarYul condition then
        let conditionPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) condition with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (fun
            | none => #[revertStmt]
            | some ref => errorRefRevertStmts ref)
          (.assert conditionPlan message errorRef?)
      else
        .ok #[lowerAssertStmt (← lowerScalarPlanExprOrFallback module env condition) errorRef?]
  | .assertEq lhs rhs message errorRef? => do
      if exprSupportsPlanScalarYul lhs && exprSupportsPlanScalarYul rhs then
        let lhsPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) lhs with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        let rhsPlan ←
          match ProofForge.Backend.Evm.Lower.buildExprPlan module (toValidateTypeEnv env) rhs with
          | .ok plan => .ok plan
          | .error err => .error { message := err.message }
        ProofForge.Backend.Evm.ToYul.scalarAssertStmtPlanStatements
          toYulError
          (fun expr => lowerExpr module env expr)
          (lowerPlanEffectExpr module env)
          (fun
            | none => #[revertStmt]
            | some ref => errorRefRevertStmts ref)
          (.assertEq lhsPlan rhsPlan message errorRef?)
      else
        let condition := Lean.Compiler.Yul.builtin "eq" #[
          ← lowerScalarPlanExprOrFallback module env lhs,
          ← lowerScalarPlanExprOrFallback module env rhs
        ]
        .ok #[lowerAssertStmt condition errorRef?]
  | _ =>
      .error { message := "EVM StmtPlan-to-Yul scalar assertion lowering expected assert/assertEq" }

partial def lowerEventStructDataWords
    (module : Module)
    (env : TypeEnv)
    (eventName fieldName typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  discard <| eventSignatureFieldType module eventName fieldName (.structType typeName)
  let some decl := module.structs.find? fun decl => decl.name == typeName
    | .error { message := s!"event `{eventName}` field `{fieldName}` uses unknown struct `{typeName}`" }
  match value with
  | .local name => do
      let some binding := findLocal? env name
        | .error { message := s!"unknown local `{name}`" }
      ensureType s!"event `{eventName}` data field `{fieldName}`" (.structType typeName) binding.type
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for field in decl.fields do
        ensureStructLocalFieldType typeName field.id field.type
        words := words.push (Lean.Compiler.Yul.Expr.id (structLocalFieldName name field.id))
      .ok words
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"event `{eventName}` data field `{fieldName}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        words := words.push (← lowerScalarPlanExprOrFallback module env field.snd)
      .ok words
  | .effect (.storageScalarRead stateId) => do
      let fields ← lowerStructStorageReadFields module s!"event `{eventName}` data field `{fieldName}`" typeName stateId
      .ok (fields.map fun field => field.snd)
  | _ =>
      .error {
        message := s!"event `{eventName}` data field `{fieldName}` struct values in IR EVM v0 support local struct values, struct literals, or storage scalar struct reads only"
      }

partial def lowerEventFixedArrayDataWords
    (module : Module)
    (env : TypeEnv)
    (eventName fieldName : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  discard <| eventSignatureFieldType module eventName fieldName (.fixedArray elementType length)
  match elementType with
  | .fixedArray nestedElementType nestedLength => do
      match value with
      | .local name =>
          lowerLocalAbiWords
            module
            env
            s!"event `{eventName}` data field `{fieldName}`"
            name
            (.fixedArray elementType length)
      | .arrayLit literalElementType values => do
          ensureType s!"event `{eventName}` data field `{fieldName}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"event `{eventName}` data field `{fieldName}` expected fixed-array length {length}, got {values.size}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            words := words ++
              (← lowerEventFixedArrayDataWords module env eventName fieldName nestedElementType nestedLength values[idx])
          .ok words
      | _ =>
          .error {
            message := s!"event `{eventName}` data field `{fieldName}` nested fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
          }
  | .structType typeName => do
      let some decl := module.structs.find? fun decl => decl.name == typeName
        | .error { message := s!"event `{eventName}` field `{fieldName}` uses unknown struct `{typeName}`" }
      match value with
      | .local name => do
          let (sourceElementType, sourceLength) ← requireLocalFixedArray s!"event `{eventName}` data field `{fieldName}`" env name
          ensureType s!"event `{eventName}` data field `{fieldName}` fixed-array element type" elementType sourceElementType
          if sourceLength != length then
            .error {
              message := s!"event `{eventName}` data field `{fieldName}` expected fixed-array length {length}, got {sourceLength}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for _h : idx in [0:length] do
            for fieldDecl in decl.fields do
              ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
              words := words.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName name idx fieldDecl.id))
          .ok words
      | .arrayLit literalElementType values => do
          ensureType s!"event `{eventName}` data field `{fieldName}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"event `{eventName}` data field `{fieldName}` expected fixed-array length {length}, got {values.size}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            match values[idx] with
            | .structLit literalTypeName fields => do
                if literalTypeName != typeName then
                  .error { message := s!"event `{eventName}` data field `{fieldName}` fixed-array element {idx} expected struct `{typeName}`, got `{literalTypeName}`" }
                for fieldDecl in decl.fields do
                  ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
                  let some field := fields.find? fun field => field.fst == fieldDecl.id
                    | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
                  words := words.push (← lowerScalarPlanExprOrFallback module env field.snd)
            | other =>
                let actualType ← inferExprType module env other
                .error {
                  message := s!"event `{eventName}` data field `{fieldName}` fixed-array element {idx} expected struct literal `{typeName}`, got `{actualType.name}`"
                }
          .ok words
      | _ =>
          .error {
            message := s!"event `{eventName}` data field `{fieldName}` fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
          }
  | .u32 | .u64 | .bool | .hash | .address => do
      match value with
      | .local name => do
          let (sourceElementType, sourceLength) ← requireLocalFixedArray s!"event `{eventName}` data field `{fieldName}`" env name
          ensureType s!"event `{eventName}` data field `{fieldName}` fixed-array element type" elementType sourceElementType
          if sourceLength != length then
            .error {
              message := s!"event `{eventName}` data field `{fieldName}` expected fixed-array length {length}, got {sourceLength}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for _h : idx in [0:length] do
            words := words.push (Lean.Compiler.Yul.Expr.id (arrayLocalElementName name idx))
          .ok words
      | .arrayLit literalElementType values => do
          ensureType s!"event `{eventName}` data field `{fieldName}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"event `{eventName}` data field `{fieldName}` expected fixed-array length {length}, got {values.size}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            words := words.push (← lowerScalarPlanExprOrFallback module env values[idx])
          .ok words
      | _ =>
          .error {
            message := s!"event `{eventName}` data field `{fieldName}` fixed-array values in IR EVM v0 support local fixed-array values or array literals only"
          }
  | .unit | .bytes | .string =>
      .error {
        message := s!"event `{eventName}` data field `{fieldName}` has unsupported EVM IR v0 fixed-array element type `{elementType.name}`"
      }

partial def lowerEventDataWords
    (module : Module)
    (env : TypeEnv)
    (eventName fieldName : String)
    (type : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  match type with
  | .u32 | .u64 | .bool | .hash | .address =>
      .ok #[← lowerScalarPlanExprOrFallback module env value]
  | .fixedArray elementType length =>
      lowerEventFixedArrayDataWords module env eventName fieldName elementType length value
  | .structType typeName =>
      lowerEventStructDataWords module env eventName fieldName typeName value
  | .unit | .bytes | .string =>
      .error {
        message := s!"event `{eventName}` data field `{fieldName}` has unsupported EVM IR v0 type `Unit`; event data fields must be U32, U64, Bool, Hash, flat structs, or fixed arrays"
      }

def eventDataStoreStatements (words : Array Lean.Compiler.Yul.Expr) : Array Lean.Compiler.Yul.Statement :=
  ProofForge.Backend.Evm.ToYul.eventDataStoreStatements words

partial def lowerIndexedEventTopicStatements
    (module : Module)
    (env : TypeEnv)
    (eventName fieldName : String)
    (index : Nat)
    (fieldPlan : ProofForge.Backend.Evm.Plan.EventFieldPlan)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let topicName := eventIndexedTopicName index
  let type := fieldPlan.type
  match type with
  | .u32 | .u64 | .bool | .hash | .address =>
      .ok #[.varDecl #[{ name := topicName }] (some (← lowerScalarPlanExprOrFallback module env value))]
  | .fixedArray _ _ | .structType _ => do
      let words ← lowerEventDataWords module env eventName fieldName type value
      .ok <| eventDataStoreStatements words |>.push
        (.varDecl #[{ name := topicName }]
          (some (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num (words.size * 32)])))
  | .unit | .bytes | .string =>
      .error {
        message := s!"event `{eventName}` indexed field `{fieldName}` has unsupported EVM IR v0 type `{type.name}`; indexed event fields must be U32, U64, Bool, Hash, Address, flat structs, or fixed arrays"
      }

def lowerEventEmitCoreStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × ProofForge.IR.Expr)) : Except LowerError Lean.Compiler.Yul.Statement := do
  let eventPlan ←
    match ProofForge.Backend.Evm.Lower.eventPlanForFields
        module
        (toValidateTypeEnv env)
        name
        indexedFields
        dataFields with
    | .ok eventPlan => .ok eventPlan
    | .error err => .error { message := err.message }
  let indexedFieldPlans := eventPlan.indexedFields
  let dataFieldPlans := eventPlan.dataFields
  let mut statements := ProofForge.Backend.Evm.ToYul.eventSignatureTopicStatements eventPlan
  for h : idx in [0:indexedFields.size] do
    let field := indexedFields[idx]
    let some fieldPlan := indexedFieldPlans[idx]?
      | .error { message := s!"event `{name}` missing indexed field plan at index {idx}" }
    statements := statements ++ (← lowerIndexedEventTopicStatements module env name field.fst idx fieldPlan field.snd)
  let mut dataWords : Array Lean.Compiler.Yul.Expr := #[]
  for h : idx in [0:dataFields.size] do
    let field := dataFields[idx]
    let some fieldPlan := dataFieldPlans[idx]?
      | .error { message := s!"event `{name}` missing data field plan at index {idx}" }
    dataWords := dataWords ++ (← lowerEventDataWords module env name field.fst fieldPlan.type field.snd)
  statements := statements ++ ProofForge.Backend.Evm.ToYul.eventDataStoreStatements dataWords
  statements := statements.push (← ProofForge.Backend.Evm.ToYul.eventLogStatement toYulError eventPlan dataWords.size)
  .ok (.block { statements := statements })

def lowerEventEmitStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (fields : Array (String × ProofForge.IR.Expr)) : Except LowerError Lean.Compiler.Yul.Statement :=
  lowerEventEmitCoreStmt module env name #[] fields

def lowerEventEmitIndexedStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (indexedFields dataFields : Array (String × ProofForge.IR.Expr)) : Except LowerError Lean.Compiler.Yul.Statement :=
  lowerEventEmitCoreStmt module env name indexedFields dataFields

def lowerMapWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (key value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let (slot, _, _) ← requireStorageMapState module stateId
  .ok (.exprStmt (Lean.Compiler.Yul.call mapWriteFunctionName #[
    slotExpr slot,
    ← lowerMapScalarPlanExprOrFallback module env key,
    ← lowerMapScalarPlanExprOrFallback module env value
  ]))

def lowerMapPathWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (keys : Array ProofForge.IR.Expr)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  .ok (.block { statements := #[
    .varDecl #[{ name := "_slot" }] (some (← lowerMapPathValueSlotExpr module env stateId keys)),
    .varDecl #[{ name := "_presence_slot" }] (some (← lowerMapPathPresenceSlotExpr module env stateId keys)),
    .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
      Lean.Compiler.Yul.Expr.id "_slot",
      ← lowerScalarPlanExprOrFallback module env value
    ]),
    .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
      Lean.Compiler.Yul.Expr.id "_presence_slot",
      Lean.Compiler.Yul.Expr.num 1
    ])
  ]})

def lowerArrayWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (index value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  .ok (.exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
    ← lowerArraySlotExpr module env stateId index,
    ← lowerScalarPlanExprOrFallback module env value
  ]))

def lowerStructFieldWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let (slot, _) ← requireStructStateField module stateId fieldName
  .ok (.exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
    slotExpr slot,
    ← lowerScalarPlanExprOrFallback module env value
  ]))

def storageStructAssignTempName (stateId fieldName : String) : String :=
  s!"__proof_forge_assign_storage_struct_{stateId}_{fieldName}"

def lowerStorageStructWriteSourceExprs
    (module : Module)
    (env : TypeEnv)
    (stateId typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array (Nat × String × Lean.Compiler.Yul.Expr)) := do
  let some decl := findStruct? module typeName
    | .error { message := s!"storage scalar struct write `{stateId}` uses unknown struct `{typeName}`" }
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"storage scalar struct write `{stateId}` source type" (.structType typeName) binding.type
      let mut values : Array (Nat × String × Lean.Compiler.Yul.Expr) := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        values := values.push (idx, fieldDecl.id, Lean.Compiler.Yul.Expr.id (structLocalFieldName sourceName fieldDecl.id))
      .ok values
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"storage scalar struct write `{stateId}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut values : Array (Nat × String × Lean.Compiler.Yul.Expr) := #[]
      for h : idx in [0:decl.fields.size] do
        let fieldDecl := decl.fields[idx]
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        values := values.push (idx, fieldDecl.id, ← lowerScalarPlanExprOrFallback module env field.snd)
      .ok values
  | .effect (.storageScalarRead sourceStateId) => do
      let fields ← lowerStructStorageReadFields module s!"storage scalar struct write `{stateId}` source type" typeName sourceStateId
      let mut values : Array (Nat × String × Lean.Compiler.Yul.Expr) := #[]
      for h : idx in [0:fields.size] do
        let field := fields[idx]
        values := values.push (idx, field.fst, field.snd)
      .ok values
  | _ =>
      .error {
        message := s!"storage scalar struct write `{stateId}` supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0"
      }

def lowerStorageStructWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let (slot, typeName, _) ← requireStructState module stateId
  let sourceExprs ← lowerStorageStructWriteSourceExprs module env stateId typeName value
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for source in sourceExprs do
    let (_, fieldName, expr) := source
    statements := statements.push <|
      .varDecl #[{ name := storageStructAssignTempName stateId fieldName }] (some expr)
  for source in sourceExprs do
    let (idx, fieldName, _) := source
    statements := statements.push <|
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
        slotExpr (slot + idx),
        Lean.Compiler.Yul.Expr.id (storageStructAssignTempName stateId fieldName)
      ])
  .ok (.block { statements := statements })

partial def lowerStructArrayFieldWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (index : ProofForge.IR.Expr)
    (fieldName : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  .ok (.exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
    ← lowerStructArrayFieldSlotExpr module env stateId index fieldName,
    ← lowerScalarPlanExprOrFallback module env value
  ]))

def lowerStoragePathWriteStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (path : Array StoragePathSegment)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement :=
  match path.toList with
  | [StoragePathSegment.mapKey key] => lowerMapWriteStmt module env stateId key value
  | [StoragePathSegment.index index] => lowerArrayWriteStmt module env stateId index value
  | [StoragePathSegment.field fieldName] => lowerStructFieldWriteStmt module env stateId fieldName value
  | [StoragePathSegment.index index, StoragePathSegment.field fieldName] =>
      lowerStructArrayFieldWriteStmt module env stateId index fieldName value
  | [] => do
      let state ← stateDeclOf module stateId "storage path"
      match state.kind with
      | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
      | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.write" }
  | _ => do
      match storagePathMapKeys? path with
      | some keys => lowerMapPathWriteStmt module env stateId keys value
      | none =>
          .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

def lowerStoragePathAssignOpStmt
    (module : Module)
    (env : TypeEnv)
    (stateId : String)
    (path : Array StoragePathSegment)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement :=
  match path.toList with
  | [StoragePathSegment.mapKey key] => do
      let (slot, _, _) ← requireStorageMapState module stateId
      .ok (.exprStmt (Lean.Compiler.Yul.call (mapAssignFunctionName op) #[
        slotExpr slot,
        ← lowerMapScalarPlanExprOrFallback module env key,
        ← lowerMapScalarPlanExprOrFallback module env value
      ]))
  | [StoragePathSegment.index index] => do
      let storageSlot ← lowerArraySlotExpr module env stateId index
      .ok (.block { statements := #[
        .varDecl #[{ name := "_slot" }] (some storageSlot),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.Expr.id "_slot",
          lowerAssignOpExpr op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (← lowerScalarPlanExprOrFallback module env value)
        ])
      ]})
  | [StoragePathSegment.field fieldName] => do
      let storageSlot ← lowerStructFieldSlotExpr module stateId fieldName
      .ok (.block { statements := #[
        .varDecl #[{ name := "_slot" }] (some storageSlot),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.Expr.id "_slot",
          lowerAssignOpExpr op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (← lowerScalarPlanExprOrFallback module env value)
        ])
      ]})
  | [StoragePathSegment.index index, StoragePathSegment.field fieldName] => do
      let storageSlot ← lowerStructArrayFieldSlotExpr module env stateId index fieldName
      .ok (.block { statements := #[
        .varDecl #[{ name := "_slot" }] (some storageSlot),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.Expr.id "_slot",
          lowerAssignOpExpr op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (← lowerScalarPlanExprOrFallback module env value)
        ])
      ]})
  | [] => do
      let state ← stateDeclOf module stateId "storage path"
      match state.kind with
      | .map _ _ => .error { message := s!"storage path state `{stateId}` is map storage; first segment must be a map key" }
      | .array _ => .error { message := s!"storage path state `{stateId}` is array storage; first segment must be an index" }
      | .scalar => .error { message := "scalar storage paths are not supported by IR EVM v0; use storage.scalar.assign_op" }
  | _ => do
      match storagePathMapKeys? path with
      | some keys => do
          let storageSlot ← lowerMapPathValueSlotExpr module env stateId keys
          let presenceSlot ← lowerMapPathPresenceSlotExpr module env stateId keys
          .ok (.block { statements := #[
            .varDecl #[{ name := "_slot" }] (some storageSlot),
            .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
            .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
              Lean.Compiler.Yul.Expr.id "_slot",
              lowerAssignOpExpr op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (← lowerScalarPlanExprOrFallback module env value)
            ]),
            .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
              Lean.Compiler.Yul.Expr.id "_presence_slot",
              Lean.Compiler.Yul.Expr.num 1
            ])
          ]})
      | none =>
          .error { message := "EVM IR v0 supports storage paths as one or more mapKey segments, index, field, or index followed by field" }

def lowerEffectStmt (module : Module) (env : TypeEnv) : Effect → Except LowerError Lean.Compiler.Yul.Statement
  | .storageScalarRead _ =>
      .error { message := "storage.scalar.read must be used as an expression" }
  | .storageScalarWrite stateId value => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          lowerStorageStructWriteStmt module env stateId value
      | _ => do
          let storageSlot ← lowerScalarStorageSlotExpr module env stateId
          .ok (.exprStmt (Lean.Compiler.Yul.builtin "sstore" #[storageSlot, ← lowerScalarPlanExprOrFallback module env value]))
  | .storageScalarAssignOp stateId op value => do
      match ← scalarStateType module stateId with
      | .structType _ =>
          .error { message := s!"storage.scalar.assign_op does not support struct state `{stateId}` in IR EVM v0" }
      | _ => pure ()
      let storageSlot ← lowerScalarStorageSlotExpr module env stateId
      .ok (.exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
        storageSlot,
        lowerAssignOpExpr op (Lean.Compiler.Yul.builtin "sload" #[storageSlot]) (← lowerScalarPlanExprOrFallback module env value)
      ]))
  | .storageMapContains _ _ =>
      .error { message := "storage.map.contains must be used as an expression" }
  | .storageMapGet _ _ =>
      .error { message := "storage.map.get must be used as an expression" }
  | .storageMapInsert stateId key value =>
      lowerMapWriteStmt module env stateId key value
  | .storageMapSet stateId key value =>
      lowerMapWriteStmt module env stateId key value
  | .storageArrayRead _ _ =>
      .error { message := "storage.array.read must be used as an expression" }
  | .storageArrayWrite stateId index value =>
      lowerArrayWriteStmt module env stateId index value
  | .storageArrayStructFieldRead _ _ _ =>
      .error { message := "storage.array.struct.field.read must be used as an expression" }
  | .storageArrayStructFieldWrite stateId index fieldName value =>
      lowerStructArrayFieldWriteStmt module env stateId index fieldName value
  | .storageStructFieldRead _ _ =>
      .error { message := "storage.struct.field.read must be used as an expression" }
  | .storageStructFieldWrite stateId fieldName value =>
      lowerStructFieldWriteStmt module env stateId fieldName value
  | .storagePathRead _ _ =>
      .error { message := "storage.path.read must be used as an expression" }
  | .storagePathWrite stateId path value =>
      lowerStoragePathWriteStmt module env stateId path value
  | .storagePathAssignOp stateId path op value =>
      lowerStoragePathAssignOpStmt module env stateId path op value
  | .contextRead _ =>
      .error { message := "context reads must be used as expressions" }
  | .eventEmit name fields =>
      lowerEventEmitStmt module env name fields
  | .eventEmitIndexed name indexedFields dataFields =>
      lowerEventEmitIndexedStmt module env name indexedFields dataFields

def ensureLocalScalarType (context name : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 | .bool | .hash | .address => .ok ()
  | .unit => .error { message := s!"{context} `{name}` has unsupported EVM IR v0 type `Unit`" }
  | .fixedArray _ _ | .structType _ | .bytes | .string => .error { message := s!"{context} `{name}` has unsupported EVM IR v0 type `{type.name}`" }

def ensureLocalFixedArrayElementType (context name : String) (type : ValueType) : Except LowerError Unit :=
  match type with
  | .u32 | .u64 | .bool | .hash | .address => .ok ()
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error {
        message := s!"{context} `{name}` has unsupported EVM IR v0 fixed-array element type `{type.name}`; local fixed arrays support U32, U64, Bool, or Hash elements"
      }

def lowerStructValueFieldExprs
    (module : Module)
    (env : TypeEnv)
    (context typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array (String × Lean.Compiler.Yul.Expr)) := do
  let decl ← ensureLocalFlatStructType module context typeName
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType context (.structType typeName) binding.type
      let mut values : Array (String × Lean.Compiler.Yul.Expr) := #[]
      for fieldDecl in decl.fields do
        values := values.push (fieldDecl.id, Lean.Compiler.Yul.Expr.id (structLocalFieldName sourceName fieldDecl.id))
      .ok values
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"{context} expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut values : Array (String × Lean.Compiler.Yul.Expr) := #[]
      for fieldDecl in decl.fields do
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        values := values.push (fieldDecl.id, ← lowerExpr module env field.snd)
      .ok values
  | .effect (.storageScalarRead stateId) =>
      lowerStructStorageReadFields module context typeName stateId
  | _ =>
      .error {
        message := s!"{context} supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0"
      }

structure NestedFixedArraySourceExpr where
  path : Array Nat
  fieldName? : Option String
  expr : Lean.Compiler.Yul.Expr

def nestedFixedArrayTargetName (name : String) (source : NestedFixedArraySourceExpr) : String :=
  match source.fieldName? with
  | none => arrayLocalPathName name source.path
  | some fieldName => arrayStructLocalPathFieldName name source.path fieldName

partial def lowerNestedFixedArrayLetBindings
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (path : Array Nat)
    (type : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match type with
  | .u32 | .u64 | .bool | .hash | .address =>
      .ok #[Lean.Compiler.Yul.Statement.varDecl
        #[{ name := arrayLocalPathName name path }]
        (some (← lowerExpr module env value))]
  | .fixedArray elementType length => do
      ensureLocalNestedFixedArrayValueType module "let binding" name elementType
      match value with
      | .arrayLit literalElementType values => do
          ensureType s!"let binding `{name}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"let binding `{name}` expected fixed array length {length}, got {values.size}"
            }
          let mut statements : Array Lean.Compiler.Yul.Statement := #[]
          for h : index in [0:values.size] do
            statements := statements ++
              (← lowerNestedFixedArrayLetBindings module env name (path.push index) elementType values[index])
          .ok statements
      | _ =>
          .error {
            message := s!"let binding `{name}` fixed array must be initialized from an array literal in IR EVM v0"
          }
  | .structType typeName => do
      let fields ← lowerStructValueFieldExprs module env s!"let binding `{name}` nested fixed-array leaf" typeName value
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for field in fields do
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.varDecl
            #[{ name := arrayStructLocalPathFieldName name path field.fst }]
            (some field.snd)
      .ok statements
  | .unit | .bytes | .string =>
      .error {
        message := s!"let binding `{name}` has unsupported EVM IR v0 nested fixed-array leaf type `Unit`; nested local fixed arrays support U32, U64, Bool, Hash, or flat struct leaves"
      }

def lowerStructArrayLetBinding
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let decl ← ensureLocalFlatStructType module s!"let binding `{name}` fixed-array element" typeName
  match value with
  | .arrayLit literalElementType values => do
      ensureType s!"let binding `{name}` fixed-array element type" (.structType typeName) literalElementType
      if values.size != length then
        .error {
          message := s!"let binding `{name}` expected fixed array length {length}, got {values.size}"
        }
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for h : index in [0:values.size] do
        match values[index] with
        | .structLit literalTypeName fields => do
            if literalTypeName != typeName then
              .error { message := s!"let binding `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
            for fieldDecl in decl.fields do
              let some field := fields.find? fun field => field.fst == fieldDecl.id
                | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
              statements := statements.push <|
                Lean.Compiler.Yul.Statement.varDecl
                  #[{ name := arrayStructLocalFieldName name index fieldDecl.id }]
                  (some (← lowerExpr module env field.snd))
        | other =>
            let actualType ← inferExprType module env other
            .error {
              message := s!"let binding `{name}` fixed-array element {index} expected struct literal `{typeName}`, got `{actualType.name}`"
            }
      .ok statements
  | _ =>
      .error {
        message := s!"let binding `{name}` fixed array of structs must be initialized from an array literal in IR EVM v0"
      }

def lowerFixedArrayLetBinding
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  if length == 0 then
    .error { message := s!"let binding `{name}` fixed array must have non-zero length in IR EVM v0" }
  match elementType with
  | .structType typeName =>
      lowerStructArrayLetBinding module env name typeName length value
  | .fixedArray _ _ => do
      ensureLocalNestedFixedArrayValueType module "let binding" name elementType
      lowerNestedFixedArrayLetBindings module env name #[] (.fixedArray elementType length) value
  | _ => do
      ensureLocalFixedArrayElementType "let binding" name elementType
      match value with
      | .arrayLit literalElementType values => do
          ensureType s!"let binding `{name}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"let binding `{name}` expected fixed array length {length}, got {values.size}"
            }
          let mut statements : Array Lean.Compiler.Yul.Statement := #[]
          for h : index in [0:values.size] do
            statements := statements.push <|
              Lean.Compiler.Yul.Statement.varDecl
                #[{ name := arrayLocalElementName name index }]
                (some (← lowerExpr module env values[index]))
          .ok statements
      | _ =>
          .error {
            message := s!"let binding `{name}` fixed array must be initialized from an array literal in IR EVM v0"
          }

def lowerStructLetBinding
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  match value with
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"let binding `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.varDecl
            #[{ name := structLocalFieldName name fieldDecl.id }]
            (some (← lowerExpr module env field.snd))
      .ok statements
  | .effect (.storageScalarRead stateId) => do
      let fields ← lowerStructStorageReadFields module s!"let binding `{name}` struct type" typeName stateId
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for field in fields do
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.varDecl
            #[{ name := structLocalFieldName name field.fst }]
            (some field.snd)
      .ok statements
  | _ =>
      .error {
        message := s!"let binding `{name}` struct must be initialized from a struct literal or storage scalar struct read in IR EVM v0"
      }

def lowerAssignTargetName (context : String) : ProofForge.IR.Expr → Except LowerError String
  | .local name =>
      .ok name
  | .arrayGet (.local name) index => do
      let indexValue ← requireStaticArrayIndex s!"{context} fixed-array index" index
      .ok (arrayLocalElementName name indexValue)
  | .field (.arrayGet (.local name) index) fieldName => do
      let indexValue ← requireStaticArrayIndex s!"{context} fixed-array index" index
      .ok (arrayStructLocalFieldName name indexValue fieldName)
  | .field (.local name) fieldName =>
      .ok (structLocalFieldName name fieldName)
  | .field base fieldName =>
      match collectStaticLocalArrayGetPath base with
      | some (name, path) =>
          .ok (arrayStructLocalPathFieldName name path fieldName)
      | none =>
          .error { message := s!"{context} must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }
  | target =>
      match collectStaticLocalArrayGetPath target with
      | some (name, path) =>
          .ok (arrayLocalPathName name path)
      | none =>
          .error { message := s!"{context} must be a mutable local, mutable local fixed-array element, mutable local struct field, or mutable local struct-array field in IR EVM v0" }

def aggregateAssignArrayTempName (name : String) (index : Nat) : String :=
  s!"__proof_forge_assign_array_{name}_{index}"

def aggregateAssignArrayPathTempName (name : String) (path : Array Nat) : String :=
  s!"__proof_forge_assign_array_{name}_{natPathSuffix path}"

def aggregateAssignStructTempName (name fieldName : String) : String :=
  s!"__proof_forge_assign_struct_{name}_{fieldName}"

def aggregateAssignStructArrayTempName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_assign_array_struct_{name}_{index}_{fieldName}"

def aggregateAssignNestedFixedArrayTempName (name : String) (source : NestedFixedArraySourceExpr) : String :=
  match source.fieldName? with
  | none => aggregateAssignArrayPathTempName name source.path
  | some fieldName => s!"__proof_forge_assign_array_struct_{name}_{natPathSuffix source.path}_{fieldName}"

def lowerFixedArrayAssignmentSourceExprs
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  match value with
  | .local sourceName => do
      let (sourceElementType, sourceLength) ← requireLocalFixedArray "assignment value" env sourceName
      ensureType s!"assignment target `{name}` fixed-array element type" elementType sourceElementType
      if sourceLength != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {sourceLength}" }
      let mut values : Array Lean.Compiler.Yul.Expr := #[]
      for _h : idx in [0:length] do
        values := values.push (Lean.Compiler.Yul.Expr.id (arrayLocalElementName sourceName idx))
      .ok values
  | .arrayLit literalElementType literalValues => do
      ensureType s!"assignment target `{name}` fixed-array element type" elementType literalElementType
      if literalValues.size != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {literalValues.size}" }
      let mut values : Array Lean.Compiler.Yul.Expr := #[]
      for h : idx in [0:literalValues.size] do
        values := values.push (← lowerExpr module env literalValues[idx])
      .ok values
  | _ =>
      .error { message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0" }

partial def lowerNestedFixedArrayLocalSourceExprs
    (module : Module)
    (sourceName : String)
    (path : Array Nat) : ValueType → Except LowerError (Array NestedFixedArraySourceExpr)
  | .u32 | .u64 | .bool | .hash | .address =>
      .ok #[{ path := path, fieldName? := none, expr := Lean.Compiler.Yul.Expr.id (arrayLocalPathName sourceName path) }]
  | .structType typeName => do
      let decl ← ensureLocalFlatStructType module s!"assignment value `{sourceName}` nested fixed-array leaf" typeName
      let mut values : Array NestedFixedArraySourceExpr := #[]
      for fieldDecl in decl.fields do
        values := values.push {
          path := path,
          fieldName? := some fieldDecl.id,
          expr := Lean.Compiler.Yul.Expr.id (arrayStructLocalPathFieldName sourceName path fieldDecl.id)
        }
      .ok values
  | .fixedArray elementType length => do
      ensureLocalNestedFixedArrayValueType module "assignment value" sourceName elementType
      let mut values : Array NestedFixedArraySourceExpr := #[]
      for _h : idx in [0:length] do
        values := values ++ (← lowerNestedFixedArrayLocalSourceExprs module sourceName (path.push idx) elementType)
      .ok values
  | .unit | .bytes | .string =>
      .error {
        message := s!"assignment value `{sourceName}` has unsupported EVM IR v0 nested fixed-array leaf type `Unit`; nested local fixed arrays support U32, U64, Bool, Hash, or flat struct leaves"
      }

partial def lowerNestedFixedArrayLiteralSourceExprs
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (path : Array Nat)
    (expectedType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array NestedFixedArraySourceExpr) := do
  match expectedType with
  | .u32 | .u64 | .bool | .hash | .address =>
      .ok #[{ path := path, fieldName? := none, expr := ← lowerExpr module env value }]
  | .structType typeName => do
      let fields ← lowerStructValueFieldExprs module env s!"assignment target `{name}` nested fixed-array leaf" typeName value
      let mut values : Array NestedFixedArraySourceExpr := #[]
      for field in fields do
        values := values.push { path := path, fieldName? := some field.fst, expr := field.snd }
      .ok values
  | .fixedArray elementType length => do
      ensureLocalNestedFixedArrayValueType module "assignment target" name elementType
      match value with
      | .arrayLit literalElementType values => do
          ensureType s!"assignment target `{name}` fixed-array element type" elementType literalElementType
          if values.size != length then
            .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {values.size}" }
          let mut lowered : Array NestedFixedArraySourceExpr := #[]
          for h : idx in [0:values.size] do
            lowered := lowered ++
              (← lowerNestedFixedArrayLiteralSourceExprs module env name (path.push idx) elementType values[idx])
          .ok lowered
      | _ =>
          .error { message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0" }
  | .unit | .bytes | .string =>
      .error {
        message := s!"assignment target `{name}` has unsupported EVM IR v0 nested fixed-array leaf type `{expectedType.name}`; nested local fixed arrays support U32, U64, Bool, Hash, or flat struct leaves"
      }

def lowerNestedFixedArrayAssignmentSourceExprs
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (expectedType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array NestedFixedArraySourceExpr) := do
  ensureLocalNestedFixedArrayValueType module "assignment target" name expectedType
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"assignment target `{name}` fixed-array type" expectedType binding.type
      lowerNestedFixedArrayLocalSourceExprs module sourceName #[] expectedType
  | .arrayLit _ _ =>
      lowerNestedFixedArrayLiteralSourceExprs module env name #[] expectedType value
  | _ =>
      .error { message := s!"assignment target `{name}` fixed-array whole assignment supports local fixed-array values or array literals in IR EVM v0" }

def lowerStructArrayAssignmentSourceExprs
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array (Nat × String × Lean.Compiler.Yul.Expr)) := do
  let decl ← ensureLocalFlatStructType module s!"assignment target `{name}` fixed-array element" typeName
  match value with
  | .local sourceName => do
      let (sourceElementType, sourceLength) ← requireLocalFixedArray "assignment value" env sourceName
      ensureType s!"assignment target `{name}` fixed-array element type" (.structType typeName) sourceElementType
      if sourceLength != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {sourceLength}" }
      let mut values : Array (Nat × String × Lean.Compiler.Yul.Expr) := #[]
      for _h : idx in [0:length] do
        for fieldDecl in decl.fields do
          values := values.push (idx, fieldDecl.id, Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName sourceName idx fieldDecl.id))
      .ok values
  | .arrayLit literalElementType literalValues => do
      ensureType s!"assignment target `{name}` fixed-array element type" (.structType typeName) literalElementType
      if literalValues.size != length then
        .error { message := s!"assignment target `{name}` expected fixed array length {length}, got {literalValues.size}" }
      let mut values : Array (Nat × String × Lean.Compiler.Yul.Expr) := #[]
      for h : idx in [0:literalValues.size] do
        match literalValues[idx] with
        | .structLit literalTypeName fields => do
            if literalTypeName != typeName then
              .error { message := s!"assignment target `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
            for fieldDecl in decl.fields do
              let some field := fields.find? fun field => field.fst == fieldDecl.id
                | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
              values := values.push (idx, fieldDecl.id, ← lowerExpr module env field.snd)
        | other =>
            let actualType ← inferExprType module env other
            .error {
              message := s!"assignment target `{name}` fixed-array element {idx} expected struct literal `{typeName}`, got `{actualType.name}`"
            }
      .ok values
  | _ =>
      .error { message := s!"assignment target `{name}` struct-array whole assignment supports local fixed-array values or array literals in IR EVM v0" }

def lowerWholeStructArrayAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let sourceExprs ← lowerStructArrayAssignmentSourceExprs module env name typeName length value
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for source in sourceExprs do
    let (idx, fieldName, expr) := source
    statements := statements.push <|
      .varDecl #[{ name := aggregateAssignStructArrayTempName name idx fieldName }] (some expr)
  for source in sourceExprs do
    let (idx, fieldName, _) := source
    statements := statements.push <|
      .assignment #[arrayStructLocalFieldName name idx fieldName] (Lean.Compiler.Yul.Expr.id (aggregateAssignStructArrayTempName name idx fieldName))
  .ok (.block { statements := statements })

def lowerWholeFixedArrayAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  match elementType with
  | .structType typeName =>
      lowerWholeStructArrayAssignStmt module env name typeName length value
  | .fixedArray _ _ => do
      let expectedType := ValueType.fixedArray elementType length
      let sourceExprs ← lowerNestedFixedArrayAssignmentSourceExprs module env name expectedType value
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for source in sourceExprs do
        statements := statements.push <|
          .varDecl #[{ name := aggregateAssignNestedFixedArrayTempName name source }] (some source.expr)
      for source in sourceExprs do
        statements := statements.push <|
          .assignment #[nestedFixedArrayTargetName name source] (Lean.Compiler.Yul.Expr.id (aggregateAssignNestedFixedArrayTempName name source))
      .ok (.block { statements := statements })
  | _ => do
      let sourceExprs ← lowerFixedArrayAssignmentSourceExprs module env name elementType length value
      if sourceExprs.size != length then
        .error { message := s!"assignment target `{name}` lowering produced {sourceExprs.size} element(s), expected {length}" }
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for h : idx in [0:sourceExprs.size] do
        statements := statements.push <|
          .varDecl #[{ name := aggregateAssignArrayTempName name idx }] (some sourceExprs[idx])
      for _h : idx in [0:length] do
        statements := statements.push <|
          .assignment #[arrayLocalElementName name idx] (Lean.Compiler.Yul.Expr.id (aggregateAssignArrayTempName name idx))
      .ok (.block { statements := statements })

def lowerStructAssignmentSourceExprs
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array (String × Lean.Compiler.Yul.Expr)) := do
  let some decl := findStruct? module typeName
    | .error { message := s!"unknown struct `{typeName}`" }
  match value with
  | .local sourceName => do
      let some binding := findLocal? env sourceName
        | .error { message := s!"unknown local `{sourceName}`" }
      ensureType s!"assignment target `{name}` struct type" (.structType typeName) binding.type
      let mut values : Array (String × Lean.Compiler.Yul.Expr) := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        values := values.push (fieldDecl.id, Lean.Compiler.Yul.Expr.id (structLocalFieldName sourceName fieldDecl.id))
      .ok values
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"assignment target `{name}` expected struct `{typeName}`, got `{literalTypeName}`" }
      let mut values : Array (String × Lean.Compiler.Yul.Expr) := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        values := values.push (fieldDecl.id, ← lowerExpr module env field.snd)
      .ok values
  | .effect (.storageScalarRead stateId) =>
      lowerStructStorageReadFields module s!"assignment target `{name}` struct type" typeName stateId
  | _ =>
      .error { message := s!"assignment target `{name}` struct whole assignment supports local struct values, struct literals, or storage scalar struct reads in IR EVM v0" }

def lowerWholeStructAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let sourceExprs ← lowerStructAssignmentSourceExprs module env name typeName value
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for field in sourceExprs do
    statements := statements.push <|
      .varDecl #[{ name := aggregateAssignStructTempName name field.fst }] (some field.snd)
  for field in sourceExprs do
    statements := statements.push <|
      .assignment #[structLocalFieldName name field.fst] (Lean.Compiler.Yul.Expr.id (aggregateAssignStructTempName name field.fst))
  .ok (.block { statements := statements })

def lowerWholeLocalAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (binding : LocalBinding)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement :=
  match binding.type with
  | .fixedArray elementType length =>
      lowerWholeFixedArrayAssignStmt module env name elementType length value
  | .structType typeName =>
      lowerWholeStructAssignStmt module env name typeName value
  | _ =>
      .error { message := s!"assignment target local `{name}` is not an aggregate value" }

def dynamicArrayIndexLocalName : String := "__proof_forge_array_index"
def dynamicArrayValueLocalName : String := "__proof_forge_array_value"

def dynamicArrayIndexPathLocalName (depth : Nat) : String :=
  s!"__proof_forge_array_index_{depth}"

def dynamicLocalFixedArraySwitchCases
    (length : Nat)
    (bodyForIndex : Nat → Array Lean.Compiler.Yul.Statement) : Array Lean.Compiler.Yul.Case :=
  Id.run do
    let mut cases : Array Lean.Compiler.Yul.Case := #[]
    for _h : idx in [0:length] do
      cases := cases.push {
        value := some (Lean.Compiler.Yul.Literal.natLit idx)
        body := { statements := bodyForIndex idx }
      }
    cases.push {
      value := none
      body := { statements := #[revertStmt] }
    }

def lowerDynamicLocalFixedArrayAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (length : Nat)
    (index value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let valueExpr ← lowerExpr module env value
  let indexExpr ← lowerExpr module env index
  let cases := dynamicLocalFixedArraySwitchCases length fun idx =>
    #[.assignment #[arrayLocalElementName name idx] (Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName)]
  .ok (.block {
    statements := #[
      .varDecl #[{ name := dynamicArrayIndexLocalName }] (some indexExpr),
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr),
      .switchStmt (Lean.Compiler.Yul.Expr.id dynamicArrayIndexLocalName) cases
    ]
  })

partial def lowerDynamicLocalFixedArrayPathAssignBody
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (type : ValueType)
    (pathPrefix : Array Nat)
    (path : Array ProofForge.IR.Expr)
    (op? : Option AssignOp) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match path.toList with
  | [] =>
      let targetName := arrayLocalPathName name pathPrefix
      let valueExpr := Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName
      let rhs :=
        match op? with
        | some op => lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) valueExpr
        | none => valueExpr
      .ok #[.assignment #[targetName] rhs]
  | index :: rest =>
      match type with
      | .fixedArray elementType length =>
          match literalArrayIndex? index with
          | some indexValue => do
              ensureFixedArrayIndexInBounds "assignment target fixed-array index" indexValue length
              lowerDynamicLocalFixedArrayPathAssignBody module env name elementType (pathPrefix.push indexValue) rest.toArray op?
          | none => do
              let indexName := dynamicArrayIndexPathLocalName pathPrefix.size
              let indexExpr ← lowerExpr module env index
              let mut cases : Array Lean.Compiler.Yul.Case := #[]
              for _h : idx in [0:length] do
                cases := cases.push {
                  value := some (Lean.Compiler.Yul.Literal.natLit idx)
                  body := {
                    statements := ← lowerDynamicLocalFixedArrayPathAssignBody module env name elementType (pathPrefix.push idx) rest.toArray op?
                  }
                }
              cases := cases.push {
                value := none
                body := { statements := #[revertStmt] }
              }
              .ok #[
                .block {
                  statements := #[
                    .varDecl #[{ name := indexName }] (some indexExpr),
                    .switchStmt (Lean.Compiler.Yul.Expr.id indexName) cases
                  ]
                }
              ]
      | other =>
          .error { message := s!"assignment target fixed-array path expected `Array`, got `{other.name}`" }

def lowerDynamicLocalFixedArrayPathAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (binding : LocalBinding)
    (path : Array ProofForge.IR.Expr)
    (op? : Option AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let valueExpr ← lowerExpr module env value
  let body ← lowerDynamicLocalFixedArrayPathAssignBody module env name binding.type #[] path op?
  .ok (.block {
    statements := #[
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr)
    ] ++ body
  })

partial def lowerDynamicLocalFixedArrayPathFieldAssignBody
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (type : ValueType)
    (pathPrefix : Array Nat)
    (path : Array ProofForge.IR.Expr)
    (fieldName : String)
    (op? : Option AssignOp) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match path.toList with
  | [] =>
      match type with
      | .structType typeName => do
          discard <| ensureLocalFlatStructType module s!"assignment target local `{name}` fixed-array leaf" typeName
          let fieldType ← structFieldType module typeName fieldName
          ensureStructLocalFieldType typeName fieldName fieldType
          let targetName := arrayStructLocalPathFieldName name pathPrefix fieldName
          let valueExpr := Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName
          let rhs :=
            match op? with
            | some op => lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) valueExpr
            | none => valueExpr
          .ok #[.assignment #[targetName] rhs]
      | other =>
          .error { message := s!"assignment target fixed-array path field expected flat struct leaf, got `{other.name}`" }
  | index :: rest =>
      match type with
      | .fixedArray elementType length =>
          match literalArrayIndex? index with
          | some indexValue => do
              ensureFixedArrayIndexInBounds "assignment target fixed-array index" indexValue length
              lowerDynamicLocalFixedArrayPathFieldAssignBody module env name elementType (pathPrefix.push indexValue) rest.toArray fieldName op?
          | none => do
              let indexName := dynamicArrayIndexPathLocalName pathPrefix.size
              let indexExpr ← lowerExpr module env index
              let mut cases : Array Lean.Compiler.Yul.Case := #[]
              for _h : idx in [0:length] do
                cases := cases.push {
                  value := some (Lean.Compiler.Yul.Literal.natLit idx)
                  body := {
                    statements := ← lowerDynamicLocalFixedArrayPathFieldAssignBody module env name elementType (pathPrefix.push idx) rest.toArray fieldName op?
                  }
                }
              cases := cases.push {
                value := none
                body := { statements := #[revertStmt] }
              }
              .ok #[
                .block {
                  statements := #[
                    .varDecl #[{ name := indexName }] (some indexExpr),
                    .switchStmt (Lean.Compiler.Yul.Expr.id indexName) cases
                  ]
                }
              ]
      | other =>
          .error { message := s!"assignment target fixed-array path expected `Array`, got `{other.name}`" }

def lowerDynamicLocalFixedArrayPathFieldAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (binding : LocalBinding)
    (path : Array ProofForge.IR.Expr)
    (fieldName : String)
    (op? : Option AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let valueExpr ← lowerExpr module env value
  let body ← lowerDynamicLocalFixedArrayPathFieldAssignBody module env name binding.type #[] path fieldName op?
  .ok (.block {
    statements := #[
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr)
    ] ++ body
  })

def lowerDynamicLocalFixedArrayAssignOpStmt
    (module : Module)
    (env : TypeEnv)
    (name : String)
    (length : Nat)
    (index : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let valueExpr ← lowerExpr module env value
  let indexExpr ← lowerExpr module env index
  let cases := dynamicLocalFixedArraySwitchCases length fun idx =>
    let elementName := arrayLocalElementName name idx
    #[.assignment #[elementName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id elementName) (Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName))]
  .ok (.block {
    statements := #[
      .varDecl #[{ name := dynamicArrayIndexLocalName }] (some indexExpr),
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr),
      .switchStmt (Lean.Compiler.Yul.Expr.id dynamicArrayIndexLocalName) cases
    ]
  })

def lowerDynamicLocalStructArrayFieldAssignStmt
    (module : Module)
    (env : TypeEnv)
    (name fieldName : String)
    (length : Nat)
    (index value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let valueExpr ← lowerExpr module env value
  let indexExpr ← lowerExpr module env index
  let cases := dynamicLocalFixedArraySwitchCases length fun idx =>
    #[.assignment #[arrayStructLocalFieldName name idx fieldName] (Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName)]
  .ok (.block {
    statements := #[
      .varDecl #[{ name := dynamicArrayIndexLocalName }] (some indexExpr),
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr),
      .switchStmt (Lean.Compiler.Yul.Expr.id dynamicArrayIndexLocalName) cases
    ]
  })

def lowerDynamicLocalStructArrayFieldAssignOpStmt
    (module : Module)
    (env : TypeEnv)
    (name fieldName : String)
    (length : Nat)
    (index : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError Lean.Compiler.Yul.Statement := do
  let valueExpr ← lowerExpr module env value
  let indexExpr ← lowerExpr module env index
  let cases := dynamicLocalFixedArraySwitchCases length fun idx =>
    let fieldLocalName := arrayStructLocalFieldName name idx fieldName
    #[.assignment #[fieldLocalName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id fieldLocalName) (Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName))]
  .ok (.block {
    statements := #[
      .varDecl #[{ name := dynamicArrayIndexLocalName }] (some indexExpr),
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr),
      .switchStmt (Lean.Compiler.Yul.Expr.id dynamicArrayIndexLocalName) cases
    ]
  })

def lowerAssignStmt
    (module : Module)
    (env : TypeEnv)
    (target value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match target with
  | .local name => do
      let some binding := findLocal? env name
        | .error { message := s!"unknown local `{name}`" }
      match binding.type with
      | .fixedArray _ _ | .structType _ =>
          .ok #[← lowerWholeLocalAssignStmt module env name binding value]
      | _ =>
          let targetName ← lowerAssignTargetName "assignment target" target
          .ok #[.assignment #[targetName] (← lowerScalarPlanExprOrFallback module env value)]
  | .arrayGet (.local name) index =>
      match literalArrayIndex? index with
      | some _ => do
          let targetName ← lowerAssignTargetName "assignment target" target
          .ok #[.assignment #[targetName] (← lowerScalarPlanExprOrFallback module env value)]
      | none => do
          let (_, length) ← requireLocalFixedArray "assignment target" env name
          .ok #[← lowerDynamicLocalFixedArrayAssignStmt module env name length index value]
  | .field (.arrayGet (.local name) index) fieldName =>
      match literalArrayIndex? index with
      | some _ => do
          let targetName ← lowerAssignTargetName "assignment target" target
          .ok #[.assignment #[targetName] (← lowerScalarPlanExprOrFallback module env value)]
      | none => do
          let (_, length, _) ← requireLocalFixedStructArrayField module env "assignment target" name fieldName
          .ok #[← lowerDynamicLocalStructArrayFieldAssignStmt module env name fieldName length index value]
  | _ => do
      match collectLocalArrayFieldGetPath target with
      | some (name, path, fieldName) =>
          if path.size > 1 && arrayIndexPathHasDynamic path then
            let binding ← requireMutableLocal env "assignment target" name
            .ok #[← lowerDynamicLocalFixedArrayPathFieldAssignStmt module env name binding path fieldName none value]
          else
            let targetName ← lowerAssignTargetName "assignment target" target
            .ok #[.assignment #[targetName] (← lowerScalarPlanExprOrFallback module env value)]
      | none =>
          match collectLocalArrayGetPath target with
          | some (name, path) =>
              if path.size > 1 && arrayIndexPathHasDynamic path then
                let binding ← requireMutableLocal env "assignment target" name
                .ok #[← lowerDynamicLocalFixedArrayPathAssignStmt module env name binding path none value]
              else
                let targetName ← lowerAssignTargetName "assignment target" target
                .ok #[.assignment #[targetName] (← lowerScalarPlanExprOrFallback module env value)]
          | none =>
              let targetName ← lowerAssignTargetName "assignment target" target
              .ok #[.assignment #[targetName] (← lowerScalarPlanExprOrFallback module env value)]

def lowerAssignOpStmt
    (module : Module)
    (env : TypeEnv)
    (target : ProofForge.IR.Expr)
    (op : AssignOp)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  match target with
  | .arrayGet (.local name) index =>
      match literalArrayIndex? index with
      | some _ => do
          let targetName ← lowerAssignTargetName "compound assignment target" target
          .ok #[.assignment #[targetName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) (← lowerScalarPlanExprOrFallback module env value))]
      | none => do
          let (_, length) ← requireLocalFixedArray "compound assignment target" env name
          .ok #[← lowerDynamicLocalFixedArrayAssignOpStmt module env name length index op value]
  | .field (.arrayGet (.local name) index) fieldName =>
      match literalArrayIndex? index with
      | some _ => do
          let targetName ← lowerAssignTargetName "compound assignment target" target
          .ok #[.assignment #[targetName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) (← lowerScalarPlanExprOrFallback module env value))]
      | none => do
          let (_, length, _) ← requireLocalFixedStructArrayField module env "compound assignment target" name fieldName
          .ok #[← lowerDynamicLocalStructArrayFieldAssignOpStmt module env name fieldName length index op value]
  | _ => do
      match collectLocalArrayFieldGetPath target with
      | some (name, path, fieldName) =>
          if path.size > 1 && arrayIndexPathHasDynamic path then
            let binding ← requireMutableLocal env "compound assignment target" name
            .ok #[← lowerDynamicLocalFixedArrayPathFieldAssignStmt module env name binding path fieldName (some op) value]
          else
            let targetName ← lowerAssignTargetName "compound assignment target" target
            .ok #[.assignment #[targetName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) (← lowerScalarPlanExprOrFallback module env value))]
      | none =>
          match collectLocalArrayGetPath target with
          | some (name, path) =>
              if path.size > 1 && arrayIndexPathHasDynamic path then
                let binding ← requireMutableLocal env "compound assignment target" name
                .ok #[← lowerDynamicLocalFixedArrayPathAssignStmt module env name binding path (some op) value]
              else
                let targetName ← lowerAssignTargetName "compound assignment target" target
                .ok #[.assignment #[targetName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) (← lowerScalarPlanExprOrFallback module env value))]
          | none =>
              let targetName ← lowerAssignTargetName "compound assignment target" target
              .ok #[.assignment #[targetName] (lowerAssignOpExpr op (Lean.Compiler.Yul.Expr.id targetName) (← lowerScalarPlanExprOrFallback module env value))]

mutual
  partial def statementAlwaysReturns : Statement → Bool
    | .return _ => true
    | .ifElse _ thenBody elseBody =>
        statementsAlwaysReturn thenBody && statementsAlwaysReturn elseBody
    | .boundedFor _ start stopExclusive body =>
        start < stopExclusive && statementsAlwaysReturn body
    | _ => false

  partial def statementsAlwaysReturn (statements : Array Statement) : Bool :=
    statements.any statementAlwaysReturns
end

def abiReturnNames (module : Module) (entrypointName : String) : ValueType → Except LowerError (Array String)
  | .unit => .ok #[]
  | .u32 | .u64 | .bool | .hash | .address | .bytes | .string => .ok #["result"]
  | .fixedArray elementType length => do
      let words ← abiValueWordTypes module s!"entrypoint `{entrypointName}` return value" (.fixedArray elementType length)
      let mut names : Array String := #[]
      for _h : idx in [0:words.size] do
        names := names.push (abiReturnName idx)
      .ok names
  | .structType typeName => do
      let words ← abiValueWordTypes module s!"entrypoint `{entrypointName}` return value" (.structType typeName)
      let mut names : Array String := #[]
      for _h : idx in [0:words.size] do
        names := names.push (abiReturnName idx)
      .ok names

def abiReturnTypedNames (module : Module) (entrypoint : Entrypoint) : Except LowerError (Array Lean.Compiler.Yul.TypedName) := do
  let names ← abiReturnNames module entrypoint.name entrypoint.returns
  .ok (names.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName))

def lowerStructArrayReturnWords
    (module : Module)
    (env : TypeEnv)
    (entrypointName typeName : String)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  discard <| abiValueWordTypes module s!"entrypoint `{entrypointName}` return value" (.fixedArray (.structType typeName) length)
  let some decl := findStruct? module typeName
    | .error { message := s!"entrypoint `{entrypointName}` return value uses unknown struct `{typeName}`" }
  match value with
  | .local name => do
      let (elementType, sourceLength) ← requireLocalFixedArray "entrypoint return value" env name
      ensureType s!"entrypoint `{entrypointName}` fixed-array return element type" (.structType typeName) elementType
      if sourceLength != length then
        .error {
          message := s!"entrypoint `{entrypointName}` fixed-array return expected length {length}, got {sourceLength}"
        }
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for _h : idx in [0:length] do
        for fieldDecl in decl.fields do
          ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
          words := words.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName name idx fieldDecl.id))
      .ok words
  | .arrayLit literalElementType values => do
      ensureType s!"entrypoint `{entrypointName}` fixed-array return element type" (.structType typeName) literalElementType
      if values.size != length then
        .error {
          message := s!"entrypoint `{entrypointName}` fixed-array return expected length {length}, got {values.size}"
        }
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for h : idx in [0:values.size] do
        match values[idx] with
        | .structLit literalTypeName fields => do
            if literalTypeName != typeName then
              .error { message := s!"entrypoint `{entrypointName}` fixed-array return expected struct `{typeName}`, got `{literalTypeName}`" }
            for fieldDecl in decl.fields do
              ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
              let some field := fields.find? fun field => field.fst == fieldDecl.id
                | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
              words := words.push (← lowerExpr module env field.snd)
        | other =>
            let actualType ← inferExprType module env other
            .error {
              message := s!"entrypoint `{entrypointName}` fixed-array return element {idx} expected struct literal `{typeName}`, got `{actualType.name}`"
            }
      .ok words
  | _ =>
      .error {
        message := s!"entrypoint `{entrypointName}` fixed-array returns in IR EVM v0 support local fixed-array values or array literals only"
      }

def lowerFixedArrayReturnWords
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (elementType : ValueType)
    (length : Nat)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  discard <| abiValueWordTypes module s!"entrypoint `{entrypointName}` return value" (.fixedArray elementType length)
  match elementType with
  | .structType typeName =>
      lowerStructArrayReturnWords module env entrypointName typeName length value
  | .fixedArray nestedElementType nestedLength =>
      match value with
      | .local name =>
          lowerLocalAbiWords module env s!"entrypoint `{entrypointName}` return value" name (.fixedArray elementType length)
      | .arrayLit literalElementType values => do
          ensureType s!"entrypoint `{entrypointName}` fixed-array return element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"entrypoint `{entrypointName}` fixed-array return expected length {length}, got {values.size}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            words := words ++ (← lowerFixedArrayReturnWords module env entrypointName nestedElementType nestedLength values[idx])
          .ok words
      | _ =>
          .error {
            message := s!"entrypoint `{entrypointName}` nested fixed-array returns in IR EVM v0 support local fixed-array values or array literals only"
          }
  | _ => do
      match value with
      | .local name => do
          lowerLocalAbiWords module env s!"entrypoint `{entrypointName}` return value" name (.fixedArray elementType length)
      | .arrayLit literalElementType values => do
          ensureType s!"entrypoint `{entrypointName}` fixed-array return element type" elementType literalElementType
          if values.size != length then
            .error {
              message := s!"entrypoint `{entrypointName}` fixed-array return expected length {length}, got {values.size}"
            }
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            words := words.push (← lowerExpr module env values[idx])
          .ok words
      | _ =>
          .error {
            message := s!"entrypoint `{entrypointName}` fixed-array returns in IR EVM v0 support local fixed-array values or array literals only"
          }

def lowerStructReturnWords
    (module : Module)
    (env : TypeEnv)
    (entrypointName typeName : String)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) := do
  discard <| abiValueWordTypes module s!"entrypoint `{entrypointName}` return value" (.structType typeName)
  let some decl := findStruct? module typeName
    | .error { message := s!"entrypoint `{entrypointName}` return value uses unknown struct `{typeName}`" }
  match value with
  | .local name => do
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        words := words.push (Lean.Compiler.Yul.Expr.id (structLocalFieldName name fieldDecl.id))
      .ok words
  | .structLit literalTypeName fields => do
      if literalTypeName != typeName then
        .error { message := s!"entrypoint `{entrypointName}` struct return expected `{typeName}`, got `{literalTypeName}`" }
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for fieldDecl in decl.fields do
        ensureStructLocalFieldType typeName fieldDecl.id fieldDecl.type
        let some field := fields.find? fun field => field.fst == fieldDecl.id
          | .error { message := s!"struct literal `{typeName}` is missing field `{fieldDecl.id}`" }
        words := words.push (← lowerExpr module env field.snd)
      .ok words
  | .effect (.storageScalarRead stateId) => do
      let fields ← lowerStructStorageReadFields module s!"entrypoint `{entrypointName}` struct return type" typeName stateId
      .ok (fields.map fun field => field.snd)
  | _ =>
      .error {
        message := s!"entrypoint `{entrypointName}` struct returns in IR EVM v0 support local struct values, struct literals, or storage scalar struct reads only"
      }

def lowerReturnWords
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Expr) :=
  match returnType with
  | .unit =>
      .error { message := s!"entrypoint `{entrypointName}` has Unit return type and cannot return a value" }
  | .bytes | .string =>
      -- Dynamic return: the function returns a memory pointer.
      -- For a .local name, return the __data_ptr local.
      match value with
      | .local name =>
          .ok #[Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName name)]
      | _ =>
          .error { message := s!"entrypoint `{entrypointName}` bytes/string returns in IR EVM v0 support local references only" }
  | .u32 | .u64 | .bool | .hash | .address => do
      .ok #[← lowerScalarPlanExprOrFallback module env value]
  | .fixedArray elementType length =>
      lowerFixedArrayReturnWords module env entrypointName elementType length value
  | .structType typeName =>
      lowerStructReturnWords module env entrypointName typeName value

def lowerAggregateCrosscallReturnAssignment?
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Option (Array Lean.Compiler.Yul.Statement)) := do
  if isCrosscallWordType returnType then
    .ok none
  else
    match value with
    | .crosscallInvokeTyped target methodId args callReturnType => do
        ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type" returnType callReturnType
        let names ← abiReturnNames module entrypointName returnType
        let wordTypes ← crosscallReturnWordTypes module s!"entrypoint `{entrypointName}` return value" returnType
        let argWords ← lowerCrosscallArgWordsMany module env "typed crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        callArgs := callArgs ++ argWords
        .ok (some #[
          .assignment names (Lean.Compiler.Yul.call (← crosscallAggregateFunctionName argWords.size wordTypes) callArgs)
        ])
    | .crosscallInvokeValueTyped target methodId callValue args callReturnType => do
        ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type" returnType callReturnType
        let names ← abiReturnNames module entrypointName returnType
        let wordTypes ← crosscallReturnWordTypes module s!"entrypoint `{entrypointName}` return value" returnType
        let argWords ← lowerCrosscallArgWordsMany module env "value crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId,
          ← lowerExpr module env callValue
        ]
        callArgs := callArgs ++ argWords
        .ok (some #[
          .assignment names (Lean.Compiler.Yul.call (← crosscallValueAggregateFunctionName argWords.size wordTypes) callArgs)
        ])
    | .crosscallInvokeStaticTyped target methodId args callReturnType => do
        ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type" returnType callReturnType
        let names ← abiReturnNames module entrypointName returnType
        let wordTypes ← crosscallReturnWordTypes module s!"entrypoint `{entrypointName}` return value" returnType
        let argWords ← lowerCrosscallArgWordsMany module env "static crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        callArgs := callArgs ++ argWords
        .ok (some #[
          .assignment names (Lean.Compiler.Yul.call (← crosscallStaticAggregateFunctionName argWords.size wordTypes) callArgs)
        ])
    | .crosscallInvokeDelegateTyped target methodId args callReturnType => do
        ensureType s!"entrypoint `{entrypointName}` aggregate crosscall return type" returnType callReturnType
        let names ← abiReturnNames module entrypointName returnType
        let wordTypes ← crosscallReturnWordTypes module s!"entrypoint `{entrypointName}` return value" returnType
        let argWords ← lowerCrosscallArgWordsMany module env "delegate crosscall argument" args
        let mut callArgs := #[
          ← lowerExpr module env target,
          ← lowerExpr module env methodId
        ]
        callArgs := callArgs ++ argWords
        .ok (some #[
          .assignment names (Lean.Compiler.Yul.call (← crosscallDelegateAggregateFunctionName argWords.size wordTypes) callArgs)
        ])
    | _ => .ok none

def lowerReturnAssignments
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let aggregateAssignment? ← lowerAggregateCrosscallReturnAssignment? module env entrypointName returnType value
  match aggregateAssignment? with
  | some statements => .ok statements
  | none => do
      let names ← abiReturnNames module entrypointName returnType
      let words ← lowerReturnWords module env entrypointName returnType value
      if names.size != words.size then
        .error { message := s!"entrypoint `{entrypointName}` return lowering produced {words.size} word(s), expected {names.size}" }
      let mut statements : Array Lean.Compiler.Yul.Statement := #[]
      for h : idx in [0:names.size] do
        let some word := words[idx]?
          | .error { message := s!"entrypoint `{entrypointName}` return lowering is missing word {idx}" }
        statements := statements.push (.assignment #[names[idx]] word)
      .ok statements

def lowerReturnStmt
    (module : Module)
    (env : TypeEnv)
    (entrypointName : String)
    (returnType : ValueType)
    (value : ProofForge.IR.Expr)
    (leaveAfterReturn : Bool) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let statements ← lowerReturnAssignments module env entrypointName returnType value
  if leaveAfterReturn then
    .ok (statements.push .leave)
  else
    .ok statements

mutual
  partial def lowerStatements
      (module : Module)
      (entrypointName : String)
      (returnType : ValueType)
      (env : TypeEnv)
      (leaveAfterReturn : Bool)
      (statements : Array Statement) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
    do
      let mut statementsAcc : Array Lean.Compiler.Yul.Statement := #[]
      let mut currentEnv := env
      for h : idx in [0:statements.size] do
        let stmtLeaveAfterReturn := leaveAfterReturn || decide (idx + 1 < statements.size)
        let (lowered, nextEnv) ← lowerStatement module entrypointName returnType currentEnv stmtLeaveAfterReturn statements[idx]
        statementsAcc := statementsAcc ++ lowered
        currentEnv := nextEnv
      .ok statementsAcc

  partial def lowerStatement
      (module : Module)
      (entrypointName : String)
      (returnType : ValueType)
      (env : TypeEnv)
      (leaveAfterReturn : Bool) : ProofForge.IR.Statement → Except LowerError (Array Lean.Compiler.Yul.Statement × TypeEnv)
    | .letBind name (.fixedArray elementType length) value => do
        let lowered ← lowerFixedArrayLetBinding module env name elementType length value
        let nextEnv ← addLocal env name (.fixedArray elementType length) false
        .ok (lowered, nextEnv)
    | .letBind name (.structType typeName) value => do
        let lowered ← lowerStructLetBinding module env name typeName value
        let nextEnv ← addLocal env name (.structType typeName) false
        .ok (lowered, nextEnv)
    | .letBind name type value => do
        ensureLocalScalarType "let binding" name type
        let nextEnv ← addLocal env name type false
        .ok (← lowerScalarBindingStmtPlanOrFallback module env name type false value, nextEnv)
    | .letMutBind name (.fixedArray elementType length) value => do
        let lowered ← lowerFixedArrayLetBinding module env name elementType length value
        let nextEnv ← addLocal env name (.fixedArray elementType length) true
        .ok (lowered, nextEnv)
    | .letMutBind name (.structType typeName) value => do
        let lowered ← lowerStructLetBinding module env name typeName value
        let nextEnv ← addLocal env name (.structType typeName) true
        .ok (lowered, nextEnv)
    | .letMutBind name type value => do
        ensureLocalScalarType "mutable let binding" name type
        let nextEnv ← addLocal env name type true
        .ok (← lowerScalarBindingStmtPlanOrFallback module env name type true value, nextEnv)
    | .assign target value => do
        .ok (← lowerAssignStmt module env target value, env)
    | .assignOp target op value => do
        .ok (← lowerAssignOpStmt module env target op value, env)
    | .effect effect => do
        .ok (#[← lowerEffectStmt module env effect], env)
    | .assert condition message errorRef? => do
        .ok (← lowerScalarAssertStmtPlanOrFallback module env (.assert condition message errorRef?), env)
    | .assertEq lhs rhs message errorRef? => do
        .ok (← lowerScalarAssertStmtPlanOrFallback module env (.assertEq lhs rhs message errorRef?), env)
    | .release _ =>
        .error { message := "release statements are not supported by IR EVM v0" }
    | .ifElse condition thenBody elseBody => do
        let thenStatements ← lowerStatements module entrypointName returnType env true thenBody
        let elseStatements ← lowerStatements module entrypointName returnType env true elseBody
        .ok (#[.switchStmt (← lowerScalarPlanExprOrFallback module env condition) #[
          {
            value := some (Lean.Compiler.Yul.Literal.natLit 0)
            body := { statements := elseStatements }
          },
          {
            value := none
            body := { statements := thenStatements }
          }
        ]], env)
    | .boundedFor indexName start stopExclusive body => do
        if stopExclusive <= start then
          .error { message := s!"bounded loop `{indexName}` must have stop greater than start" }
        let loopEnv ← addLocal env indexName .u32 false
        let bodyStatements ← lowerStatements module entrypointName returnType loopEnv true body
        let loopCondition ← lowerScalarPlanExprOrFallback module loopEnv (.lt (.local indexName) (.literal (.u32 stopExclusive)))
        .ok (#[.forLoop
          { statements := #[
            .varDecl #[{ name := indexName }] (some (Lean.Compiler.Yul.Expr.num start))
          ] }
          loopCondition
          { statements := #[
            .assignment #[indexName] (Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id indexName, Lean.Compiler.Yul.Expr.num 1])
          ] }
          { statements := bodyStatements }], env)
    | .return value => do
        .ok (← lowerReturnStmt module env entrypointName returnType value leaveAfterReturn, env)
end

def lowerEntrypoint (module : Module) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Yul.Statement := do
  let params ← lowerEntrypointParams module entrypoint
  match entrypoint.returns with
  | .unit => pure ()
  | _ =>
      if statementsAlwaysReturn entrypoint.body then
        pure ()
      else
        .error { message := s!"entrypoint `{entrypoint.name}` returns `{entrypoint.returns.name}` but does not return on every control-flow path" }
  validateEntrypointTypes module entrypoint
  let body ← lowerStatements module entrypoint.name entrypoint.returns (entrypointTypeEnv entrypoint) false entrypoint.body
  let returns ← abiReturnTypedNames module entrypoint
  .ok (.funcDef (yulFunctionName module.name entrypoint.name) params returns { statements := body })

def entrypointCallExpr (module : Module) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Yul.Expr := do
  let layouts ← entrypointParamLayouts module entrypoint
  let args ← entrypointCallArgsWithLayout module entrypoint layouts
  .ok (Lean.Compiler.Yul.call (yulFunctionName module.name entrypoint.name) args)

def dispatchResultNames (wordCount : Nat) : Array String :=
  if wordCount == 1 then
    #["_r"]
  else
    Id.run do
      let mut names : Array String := #[]
      for _h : idx in [0:wordCount] do
        names := names.push (abiDispatchResultName idx)
      names

def dispatchReturnStatements
    (module : Module)
    (entrypoint : Entrypoint)
    (callExpr : Lean.Compiler.Yul.Expr) : Except LowerError (Array Lean.Compiler.Yul.Statement) := do
  let layouts ← entrypointParamLayouts module entrypoint
  let validationStmts ← abiParamValidationAndDecodeStmts module entrypoint layouts
  match entrypoint.returns with
  | .unit =>
      .ok (validationStmts ++ #[
        Lean.Compiler.Yul.Statement.exprStmt callExpr,
        Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
      ])
  | .bytes | .string =>
      -- Dynamic return: the function returns a memory pointer.
      -- Encode as head-tail: head = offset (32 bytes), tail = (length, data).
      .ok (validationStmts ++ #[
        -- Call the function, get the memory pointer result
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_r" }] (some callExpr),
        -- Read length from memory at _r
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_ret_len" }]
          (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.id "_r"])),
        -- Compute word count for data: ceil(len / 32)
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_ret_word_count" }]
          (some (Lean.Compiler.Yul.builtin "div" #[
            Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_ret_len", Lean.Compiler.Yul.Expr.num 31],
            Lean.Compiler.Yul.Expr.num 32
          ])),
        -- Store offset in head (offset = 32, since head is 1 word)
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 32]),
        -- Store length in tail
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "_ret_len"]),
        -- Copy data from memory (_r + 32) to output (offset 64) using a loop
        -- (avoids mcopy due to solc optimizer argument-order bug)
        Lean.Compiler.Yul.Statement.forLoop
          { statements := #[Lean.Compiler.Yul.Statement.varDecl #[{ name := "_i" }] (some (Lean.Compiler.Yul.Expr.num 0))] }
          (Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.id "_ret_word_count"])
          { statements := #[Lean.Compiler.Yul.Statement.assignment #["_i"] (Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 1])] }
          { statements := #[
            Lean.Compiler.Yul.Statement.exprStmt
              (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 32]],
                Lean.Compiler.Yul.builtin "mload" #[
                  Lean.Compiler.Yul.builtin "add" #[
                    Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_r", Lean.Compiler.Yul.Expr.num 32],
                    Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 32]
                  ]
                ]
              ])
          ] },
        -- Return: head (32) + tail (32 + data words)
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "return" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.builtin "add" #[
              Lean.Compiler.Yul.Expr.num 64,
              Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_ret_word_count", Lean.Compiler.Yul.Expr.num 32]
            ]
          ])
      ])
  | _ => do
      let wordTypes ← abiValueWordTypes module s!"entrypoint `{entrypoint.name}` return value" entrypoint.returns
      let resultNames := dispatchResultNames wordTypes.size
      let mut statements : Array Lean.Compiler.Yul.Statement :=
        validationStmts ++ #[
          Lean.Compiler.Yul.Statement.varDecl
            (resultNames.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName))
            (some callExpr)
        ]
      for h : idx in [0:resultNames.size] do
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.exprStmt
            (Lean.Compiler.Yul.builtin "mstore" #[
              Lean.Compiler.Yul.Expr.num (idx * 32),
              Lean.Compiler.Yul.Expr.id resultNames[idx]
            ])
      statements := statements.push <|
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num (wordTypes.size * 32)])
      .ok statements

def dispatchCase (module : Module) (entrypoint : Entrypoint) : Except LowerError Lean.Compiler.Yul.Case := do
  let some selector := entrypoint.selector?
    | .error { message := s!"entrypoint `{entrypoint.name}` has no EVM selector metadata" }
  let callExpr ← entrypointCallExpr module entrypoint
  let bodyStmts ← dispatchReturnStatements module entrypoint callExpr
  .ok {
    value := some (Lean.Compiler.Yul.Literal.hex ("0x" ++ selector))
    body := { statements := bodyStmts }
  }

def dispatchBlock (module : Module) : Except LowerError Lean.Compiler.Yul.Statement := do
  let selectorExpr := Lean.Compiler.Yul.builtin "shr" #[
    Lean.Compiler.Yul.Expr.num 224,
    Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num 0]
  ]
  let cases ← module.entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (acc.push (← dispatchCase module entrypoint))
  let defaultCase : Lean.Compiler.Yul.Case :=
    match module.evmProxyPattern? with
    | some "uups" => uupsProxyDefaultCase
    | _ => {
        value := none
        body := { statements := #[revertStmt] }
      }
  -- Initialize the free memory pointer (0x80 = 128) before the switch
  -- when any entrypoint has dynamic ABI parameters (bytes/string).
  -- In raw Yul, 0x40 is NOT initialized (unlike Solidity), so dynamic
  -- ABI decoding (which uses mload(64) for allocation) needs a valid FMP.
  let hasDynamicParams := module.entrypoints.any fun entrypoint =>
    entrypoint.params.any fun param => isDynamicAbiType param.snd
  let switchStmt := .switchStmt selectorExpr (cases.push defaultCase)
  if hasDynamicParams then
    .ok (.block { statements := #[
      Lean.Compiler.Yul.Statement.exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.num 128]),
      switchStmt
    ] })
  else
    .ok switchStmt

def hashHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef hashWordFunctionName
    #[{ name := "value" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "value"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 32])
      ]
    },
  .funcDef hashPairFunctionName
    #[{ name := "left" }, { name := "right" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "left"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "right"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])
      ]
    }
]

def mapBaseHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef mapSlotFunctionName
    #[{ name := "slot" }, { name := "key" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "key"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "slot"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])
      ]
    },
  .funcDef mapPresenceSlotFunctionName
    #[{ name := "slot" }, { name := "key" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "slot"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.num mapPresenceDomain]),
        .varDecl #[{ name := "_presence_slot" }]
          (some (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "key"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "_presence_slot"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])
      ]
    },
  .funcDef mapWriteFunctionName
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (Lean.Compiler.Yul.call mapSlotFunctionName #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[Lean.Compiler.Yul.Expr.id "_slot", Lean.Compiler.Yul.Expr.id "value"]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.call mapPresenceSlotFunctionName #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    },
  .funcDef mapSetReturnFunctionName
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[{ name := "old" }]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (Lean.Compiler.Yul.call mapSlotFunctionName #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .assignment #["old"] (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[Lean.Compiler.Yul.Expr.id "_slot", Lean.Compiler.Yul.Expr.id "value"]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.call mapPresenceSlotFunctionName #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    }
]

def mapAssignHelperFunction (op : AssignOp) : Lean.Compiler.Yul.Statement :=
  .funcDef (mapAssignFunctionName op)
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (Lean.Compiler.Yul.call mapSlotFunctionName #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.Expr.id "_slot",
          lowerAssignOpExpr op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (Lean.Compiler.Yul.Expr.id "value")
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.call mapPresenceSlotFunctionName #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    }

def mapHelperFunctions (assignOps : Array AssignOp) : Array Lean.Compiler.Yul.Statement :=
  mapBaseHelperFunctions ++ assignOps.map mapAssignHelperFunction

def arrayHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef arraySlotFunctionName
    #[{ name := "slot" }, { name := "length" }, { name := "index" }]
    #[{ name := "result" }]
    {
      statements := #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.id "length"]])
          { statements := #[revertStmt] },
        .assignment #["result"] (Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "index"])
      ]
    }
]

def localArrayGetFunctionParams (length : Nat) : Array Lean.Compiler.Yul.TypedName :=
  Id.run do
    let mut params : Array Lean.Compiler.Yul.TypedName := #[{ name := "index" }]
    for _h : idx in [0:length] do
      params := params.push { name := localArrayGetValueParamName idx }
    params

def localArrayGetSwitchCases (length : Nat) : Array Lean.Compiler.Yul.Case :=
  Id.run do
    let mut cases : Array Lean.Compiler.Yul.Case := #[]
    for _h : idx in [0:length] do
      cases := cases.push {
        value := some (Lean.Compiler.Yul.Literal.natLit idx)
        body := {
          statements := #[
            .assignment #["result"] (Lean.Compiler.Yul.Expr.id (localArrayGetValueParamName idx))
          ]
        }
      }
    cases.push {
      value := none
      body := { statements := #[revertStmt] }
    }

def localArrayGetHelperFunction (length : Nat) : Lean.Compiler.Yul.Statement :=
  .funcDef (localArrayGetFunctionName length)
    (localArrayGetFunctionParams length)
    #[{ name := "result" }]
    {
      statements := #[
        .switchStmt (Lean.Compiler.Yul.Expr.id "index") (localArrayGetSwitchCases length)
      ]
    }

def localArrayGetHelperFunctions (lengths : Array Nat) : Array Lean.Compiler.Yul.Statement :=
  lengths.map localArrayGetHelperFunction

def nestedLocalArrayGetFunctionParams (lengths : Array Nat) : Array Lean.Compiler.Yul.TypedName :=
  Id.run do
    let mut params : Array Lean.Compiler.Yul.TypedName := #[]
    for _h : idx in [0:lengths.size] do
      params := params.push { name := localArrayGetIndexParamName idx }
    for path in nestedLocalArrayLeafPaths lengths do
      params := params.push { name := localArrayGetPathValueParamName path }
    params

partial def nestedLocalArrayGetSwitchStatements
    (lengths : Array Nat)
    (depth : Nat)
    (path : Array Nat) : Array Lean.Compiler.Yul.Statement :=
  match lengths.toList with
  | [] =>
      #[.assignment #["result"] (Lean.Compiler.Yul.Expr.id (localArrayGetPathValueParamName path))]
  | length :: rest =>
      let cases := Id.run do
        let mut cases : Array Lean.Compiler.Yul.Case := #[]
        for _h : idx in [0:length] do
          cases := cases.push {
            value := some (Lean.Compiler.Yul.Literal.natLit idx)
            body := {
              statements := nestedLocalArrayGetSwitchStatements rest.toArray (depth + 1) (path.push idx)
            }
          }
        cases.push {
          value := none
          body := { statements := #[revertStmt] }
        }
      #[.switchStmt (Lean.Compiler.Yul.Expr.id (localArrayGetIndexParamName depth)) cases]

def nestedLocalArrayGetHelperFunction (lengths : Array Nat) : Lean.Compiler.Yul.Statement :=
  .funcDef (nestedLocalArrayGetFunctionName lengths)
    (nestedLocalArrayGetFunctionParams lengths)
    #[{ name := "result" }]
    { statements := nestedLocalArrayGetSwitchStatements lengths 0 #[] }

def arrayNatEq (lhs rhs : Array Nat) : Bool :=
  lhs == rhs

def pushNatArrayIfMissing (acc : Array (Array Nat)) (value : Array Nat) : Array (Array Nat) :=
  if acc.any fun existing => arrayNatEq existing value then acc else acc.push value

def mergeNatArraySets (lhs rhs : Array (Array Nat)) : Array (Array Nat) :=
  rhs.foldl pushNatArrayIfMissing lhs

def nestedLocalArrayGetHelperFunctions (lengths : Array (Array Nat)) : Array Lean.Compiler.Yul.Statement :=
  lengths.map nestedLocalArrayGetHelperFunction

def structArrayHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef structArraySlotFunctionName
    #[
      { name := "slot" },
      { name := "length" },
      { name := "field_count" },
      { name := "field_offset" },
      { name := "index" }
    ]
    #[{ name := "result" }]
    {
      statements := #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.id "length"]])
          { statements := #[revertStmt] },
        .assignment #["result"] (Lean.Compiler.Yul.builtin "add" #[
          Lean.Compiler.Yul.builtin "add" #[
            Lean.Compiler.Yul.Expr.id "slot",
            Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.id "field_count"]
          ],
          Lean.Compiler.Yul.Expr.id "field_offset"
        ])
      ]
    }
]

def crosscallArgName (idx : Nat) : String :=
  s!"arg{idx}"

def crosscallCallValueName : String := "call_value"

def crosscallCalldataSize (arity : Nat) : Nat :=
  4 + arity * 32

inductive CrosscallMode where
  | call
  | callValue
  | staticcall
  | delegatecall
  deriving BEq, Repr

def CrosscallMode.forwardsValue : CrosscallMode → Bool
  | .callValue => true
  | .call | .staticcall | .delegatecall => false

def crosscallFunctionParams (arity : Nat) (mode : CrosscallMode) (plainTransfer : Bool := false) : Array Lean.Compiler.Yul.TypedName :=
  if plainTransfer then
    #[
      ({ name := "target" } : Lean.Compiler.Yul.TypedName),
      ({ name := crosscallCallValueName } : Lean.Compiler.Yul.TypedName)
    ]
  else
    let base := #[
      ({ name := "target" } : Lean.Compiler.Yul.TypedName),
      ({ name := "selector" } : Lean.Compiler.Yul.TypedName)
    ]
    let base :=
      if mode.forwardsValue then
        base.push ({ name := crosscallCallValueName } : Lean.Compiler.Yul.TypedName)
      else
        base
    go 0 base
  where
    go (idx : Nat) (acc : Array Lean.Compiler.Yul.TypedName) : Array Lean.Compiler.Yul.TypedName :=
      if h : idx < arity then
        go (idx + 1) (acc.push ({ name := crosscallArgName idx } : Lean.Compiler.Yul.TypedName))
      else
        acc

def crosscallArgStoreStatements (arity : Nat) : Array Lean.Compiler.Yul.Statement :=
  go 0 #[]
where
  go (idx : Nat) (acc : Array Lean.Compiler.Yul.Statement) : Array Lean.Compiler.Yul.Statement :=
    if h : idx < arity then
      let store := Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num (4 + idx * 32),
          Lean.Compiler.Yul.Expr.id (crosscallArgName idx)
        ])
      go (idx + 1) (acc.push store)
    else
      acc

structure CrosscallHelperSpec where
  arity : Nat
  returnType : ValueType
  mode : CrosscallMode := .call
  plainTransfer : Bool := false
  deriving BEq, Repr

def crosscallReturnGuardStatementsForName (resultName : String) (returnType : ValueType) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  match returnType with
  | .u32 =>
      .ok #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id resultName, Lean.Compiler.Yul.Expr.num maxU32])
          { statements := #[revertStmt] }
      ]
  | .bool =>
      .ok #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id resultName, Lean.Compiler.Yul.Expr.num 1])
          { statements := #[revertStmt] }
      ]
  | .u64 | .hash | .address => .ok #[]
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error { message := "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0" }

def crosscallReturnGuardStatements (returnType : ValueType) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  match returnType with
  | .u32 => crosscallReturnGuardStatementsForName "result" .u32
  | .bool => crosscallReturnGuardStatementsForName "result" .bool
  | .u64 | .hash | .address => .ok #[]
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string =>
      .error { message := "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0" }

def crosscallHelperReturnNames (wordCount : Nat) : Array Lean.Compiler.Yul.TypedName :=
  if wordCount == 1 then
    #[{ name := "result" }]
  else
    Id.run do
      let mut names : Array Lean.Compiler.Yul.TypedName := #[]
      for _h : idx in [0:wordCount] do
        names := names.push ({ name := s!"result{idx}" } : Lean.Compiler.Yul.TypedName)
      names

def crosscallHelperReturnNameStrings (wordCount : Nat) : Array String :=
  (crosscallHelperReturnNames wordCount).map fun name => name.name

def crosscallHelperFunction (module : Module) (spec : CrosscallHelperSpec) : Except LowerError Lean.Compiler.Yul.Statement := do
  let wordTypes ← crosscallReturnWordTypes module "typed crosscall return" spec.returnType
  let functionName ←
    match spec.mode, isCrosscallWordType spec.returnType with
    | .call, true => crosscallFunctionName spec.arity spec.returnType
    | .call, false => crosscallAggregateFunctionName spec.arity wordTypes
    | .callValue, true => crosscallValueFunctionName spec.arity spec.returnType spec.plainTransfer
    | .callValue, false => crosscallValueAggregateFunctionName spec.arity wordTypes spec.plainTransfer
    | .staticcall, true => crosscallStaticFunctionName spec.arity spec.returnType
    | .staticcall, false => crosscallStaticAggregateFunctionName spec.arity wordTypes
    | .delegatecall, true => crosscallDelegateFunctionName spec.arity spec.returnType
    | .delegatecall, false => crosscallDelegateAggregateFunctionName spec.arity wordTypes
  if spec.plainTransfer then
    if wordTypes.size != 1 then
      .error { message := "plain native transfer expects a single-word return type in IR EVM v0" }
    else
      let returnName := (crosscallHelperReturnNameStrings 1)[0]!
      .ok <| .funcDef functionName
        (crosscallFunctionParams spec.arity spec.mode true)
        (crosscallHelperReturnNames 1)
        {
          statements := #[
            .varDecl #[{ name := "_success" }] (some <|
              Lean.Compiler.Yul.builtin "call" #[
                Lean.Compiler.Yul.builtin "gas" #[],
                Lean.Compiler.Yul.Expr.id "target",
                Lean.Compiler.Yul.Expr.id crosscallCallValueName,
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num 0
              ]),
            .ifStmt
              (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_success"])
              { statements := #[revertStmt] },
            .assignment #[returnName] (Lean.Compiler.Yul.Expr.num 0)
          ]
        }
  else
  let outputSize := wordTypes.size * 32
  let callValue :=
    if spec.mode.forwardsValue then
      Lean.Compiler.Yul.Expr.id crosscallCallValueName
    else
      Lean.Compiler.Yul.Expr.num 0
  let callExpr :=
    match spec.mode with
    | .call | .callValue =>
        Lean.Compiler.Yul.builtin "call" #[
          Lean.Compiler.Yul.builtin "gas" #[],
          Lean.Compiler.Yul.Expr.id "target",
          callValue,
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num outputSize
        ]
    | .staticcall =>
        Lean.Compiler.Yul.builtin "staticcall" #[
          Lean.Compiler.Yul.builtin "gas" #[],
          Lean.Compiler.Yul.Expr.id "target",
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num outputSize
        ]
    | .delegatecall =>
        Lean.Compiler.Yul.builtin "delegatecall" #[
          Lean.Compiler.Yul.builtin "gas" #[],
          Lean.Compiler.Yul.Expr.id "target",
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num outputSize
        ]
  let returnNameStrings := crosscallHelperReturnNameStrings wordTypes.size
  let mut copyAssignments : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:wordTypes.size] do
    copyAssignments := copyAssignments.push <|
      .assignment #[returnNameStrings[idx]!]
        (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num (idx * 32)])
  let mut guardStatements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:wordTypes.size] do
    guardStatements := guardStatements ++ (← crosscallReturnGuardStatementsForName returnNameStrings[idx]! wordTypes[idx])
  .ok <| .funcDef functionName
    (crosscallFunctionParams spec.arity spec.mode spec.plainTransfer)
    (crosscallHelperReturnNames wordTypes.size)
    {
      statements :=
        #[
          .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.builtin "shl" #[
              Lean.Compiler.Yul.Expr.num 224,
              Lean.Compiler.Yul.Expr.id "selector"
            ]
          ])
        ] ++
        crosscallArgStoreStatements spec.arity ++
        #[
          .varDecl #[{ name := "_success" }] (some callExpr),
          .ifStmt
            (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_success"])
            { statements := #[revertStmt] },
          .ifStmt
            (Lean.Compiler.Yul.builtin "lt" #[
              Lean.Compiler.Yul.builtin "returndatasize" #[],
              Lean.Compiler.Yul.Expr.num outputSize
            ])
            { statements := #[revertStmt] },
          .exprStmt (Lean.Compiler.Yul.builtin "returndatacopy" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.Expr.num outputSize
          ])
        ] ++
        copyAssignments ++
        guardStatements
    }

def pushNatIfMissing (acc : Array Nat) (value : Nat) : Array Nat :=
  if acc.contains value then acc else acc.push value

def mergeNatSets (lhs rhs : Array Nat) : Array Nat :=
  rhs.foldl pushNatIfMissing lhs

def pushCrosscallHelperSpecIfMissing (acc : Array CrosscallHelperSpec) (value : CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCrosscallHelperSpecs (lhs rhs : Array CrosscallHelperSpec) : Array CrosscallHelperSpec :=
  rhs.foldl pushCrosscallHelperSpecIfMissing lhs

def crosscallArgWordCountForExpr
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (arg : ProofForge.IR.Expr) : Except LowerError Nat := do
  let type ← inferExprType module env arg
  let words ← crosscallArgWordTypes module context type
  .ok words.size

def crosscallArgWordCountForArgs
    (module : Module)
    (env : TypeEnv)
    (context : String)
    (args : Array ProofForge.IR.Expr) : Except LowerError Nat := do
  let mut count := 0
  for arg in args do
    count := count + (← crosscallArgWordCountForExpr module env context arg)
  .ok count

mutual
  partial def crosscallHelperSpecsExpr
      (module : Module)
      (env : TypeEnv) : ProofForge.IR.Expr → Except LowerError (Array CrosscallHelperSpec)
    | .literal _ => .ok #[]
    | .local _ => .ok #[]
    | .arrayLit _ values =>
        values.foldlM (init := #[]) fun acc value => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsExpr module env value))
    | .arrayGet array index => do
        let arraySpecs ← crosscallHelperSpecsExpr module env array
        let indexSpecs ← crosscallHelperSpecsExpr module env index
        .ok (mergeCrosscallHelperSpecs arraySpecs indexSpecs)
    | .structLit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsExpr module env field.snd))
    | .field base _ =>
        crosscallHelperSpecsExpr module env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs => do
        let lhsSpecs ← crosscallHelperSpecsExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs)
    | .cast value _ | .boolNot value | .hash value =>
        crosscallHelperSpecsExpr module env value
    | .hashValue a b c d => do
        let ab := mergeCrosscallHelperSpecs (← crosscallHelperSpecsExpr module env a) (← crosscallHelperSpecsExpr module env b)
        let cd := mergeCrosscallHelperSpecs (← crosscallHelperSpecsExpr module env c) (← crosscallHelperSpecsExpr module env d)
        .ok (mergeCrosscallHelperSpecs ab cd)
    | .nativeValue => .ok #[]
    | .crosscallInvoke target methodId args => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsExpr module env target)
          (← crosscallHelperSpecsExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsExpr module env arg)
        .ok (pushCrosscallHelperSpecIfMissing nested { arity := args.size, returnType := .u64, mode := .call })
    | .crosscallInvokeTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsExpr module env target)
          (← crosscallHelperSpecsExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "typed crosscall argument" args
        .ok (pushCrosscallHelperSpecIfMissing nested { arity := argWordCount, returnType := returnType, mode := .call })
    | .crosscallInvokeValueTyped target methodId callValue args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsExpr module env target)
          (← crosscallHelperSpecsExpr module env methodId)
        nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsExpr module env callValue)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "value crosscall argument" args
        let plainTransfer := plainValueTransferCall? methodId args && isCrosscallWordType returnType
        .ok (pushCrosscallHelperSpecIfMissing nested {
          arity := argWordCount
          returnType := returnType
          mode := .callValue
          plainTransfer := plainTransfer
        })
    | .crosscallInvokeStaticTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsExpr module env target)
          (← crosscallHelperSpecsExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "static crosscall argument" args
        .ok (pushCrosscallHelperSpecIfMissing nested { arity := argWordCount, returnType := returnType, mode := .staticcall })
    | .crosscallInvokeDelegateTyped target methodId args returnType => do
        let mut nested := mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsExpr module env target)
          (← crosscallHelperSpecsExpr module env methodId)
        for arg in args do
          nested := mergeCrosscallHelperSpecs nested (← crosscallHelperSpecsExpr module env arg)
        let argWordCount ← crosscallArgWordCountForArgs module env "delegate crosscall argument" args
        .ok (pushCrosscallHelperSpecIfMissing nested { arity := argWordCount, returnType := returnType, mode := .delegatecall })
    | .crosscallCreate callValue _ =>
        crosscallHelperSpecsExpr module env callValue
    | .crosscallCreate2 callValue salt _ => do
        .ok (mergeCrosscallHelperSpecs
          (← crosscallHelperSpecsExpr module env callValue)
          (← crosscallHelperSpecsExpr module env salt))
    | .effect effect =>
        crosscallHelperSpecsEffect module env effect

  partial def crosscallHelperSpecsEffect
      (module : Module)
      (env : TypeEnv) : Effect → Except LowerError (Array CrosscallHelperSpec)
    | .storageScalarRead _ => .ok #[]
    | .storageScalarWrite _ value =>
        crosscallHelperSpecsExpr module env value
    | .storageScalarAssignOp _ _ value =>
        crosscallHelperSpecsExpr module env value
    | .storageMapContains _ key =>
        crosscallHelperSpecsExpr module env key
    | .storageMapGet _ key =>
        crosscallHelperSpecsExpr module env key
    | .storageMapInsert _ key value | .storageMapSet _ key value => do
        let keySpecs ← crosscallHelperSpecsExpr module env key
        let valueSpecs ← crosscallHelperSpecsExpr module env value
        .ok (mergeCrosscallHelperSpecs keySpecs valueSpecs)
    | .storageArrayRead _ index =>
        crosscallHelperSpecsExpr module env index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value => do
        let indexSpecs ← crosscallHelperSpecsExpr module env index
        let valueSpecs ← crosscallHelperSpecsExpr module env value
        .ok (mergeCrosscallHelperSpecs indexSpecs valueSpecs)
    | .storageArrayStructFieldRead _ index _ =>
        crosscallHelperSpecsExpr module env index
    | .storageStructFieldRead _ _ => .ok #[]
    | .storageStructFieldWrite _ _ value =>
        crosscallHelperSpecsExpr module env value
    | .storagePathRead _ path =>
        path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsStoragePathSegment module env segment))
    | .storagePathWrite _ path value => do
        let pathSpecs ← path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsStoragePathSegment module env segment))
        .ok (mergeCrosscallHelperSpecs pathSpecs (← crosscallHelperSpecsExpr module env value))
    | .storagePathAssignOp _ path _ value => do
        let pathSpecs ← path.foldlM (init := #[]) fun acc segment => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsStoragePathSegment module env segment))
        .ok (mergeCrosscallHelperSpecs pathSpecs (← crosscallHelperSpecsExpr module env value))
    | .contextRead _ => .ok #[]
    | .eventEmit _ fields =>
        fields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsExpr module env field.snd))
    | .eventEmitIndexed _ indexedFields dataFields => do
        let indexedSpecs ← indexedFields.foldlM (init := #[]) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsExpr module env field.snd))
        dataFields.foldlM (init := indexedSpecs) fun acc field => do
          .ok (mergeCrosscallHelperSpecs acc (← crosscallHelperSpecsExpr module env field.snd))

  partial def crosscallHelperSpecsStoragePathSegment
      (module : Module)
      (env : TypeEnv) : StoragePathSegment → Except LowerError (Array CrosscallHelperSpec)
    | .field _ => .ok #[]
    | .index index => crosscallHelperSpecsExpr module env index
    | .mapKey key => crosscallHelperSpecsExpr module env key

  partial def crosscallHelperSpecsStatement
      (module : Module)
      (env : TypeEnv) : Statement → Except LowerError (Array CrosscallHelperSpec × TypeEnv)
    | .letBind name type value => do
        let specs ← crosscallHelperSpecsExpr module env value
        let nextEnv ← addLocal env name type false
        .ok (specs, nextEnv)
    | .letMutBind name type value => do
        let specs ← crosscallHelperSpecsExpr module env value
        let nextEnv ← addLocal env name type true
        .ok (specs, nextEnv)
    | .assign target value => do
        let targetSpecs ← crosscallHelperSpecsExpr module env target
        let valueSpecs ← crosscallHelperSpecsExpr module env value
        .ok (mergeCrosscallHelperSpecs targetSpecs valueSpecs, env)
    | .assignOp target _ value => do
        let targetSpecs ← crosscallHelperSpecsExpr module env target
        let valueSpecs ← crosscallHelperSpecsExpr module env value
        .ok (mergeCrosscallHelperSpecs targetSpecs valueSpecs, env)
    | .effect effect => do
        .ok (← crosscallHelperSpecsEffect module env effect, env)
    | .assert condition _ _ => do
        .ok (← crosscallHelperSpecsExpr module env condition, env)
    | .assertEq lhs rhs _ _ => do
        let lhsSpecs ← crosscallHelperSpecsExpr module env lhs
        let rhsSpecs ← crosscallHelperSpecsExpr module env rhs
        .ok (mergeCrosscallHelperSpecs lhsSpecs rhsSpecs, env)
    | .release _ =>
        .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let (thenSpecs, _) ← crosscallHelperSpecsStatements module env thenBody
        let (elseSpecs, _) ← crosscallHelperSpecsStatements module env elseBody
        let bodySpecs := mergeCrosscallHelperSpecs thenSpecs elseSpecs
        let conditionSpecs ← crosscallHelperSpecsExpr module env condition
        .ok (mergeCrosscallHelperSpecs conditionSpecs bodySpecs, env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodySpecs, _) ← crosscallHelperSpecsStatements module loopEnv body
        .ok (bodySpecs, env)
    | .return value => do
        .ok (← crosscallHelperSpecsExpr module env value, env)

  partial def crosscallHelperSpecsStatements
      (module : Module)
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array CrosscallHelperSpec × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (specs, currentEnv) := acc
      let (stmtSpecs, nextEnv) ← crosscallHelperSpecsStatement module currentEnv stmt
      .ok (mergeCrosscallHelperSpecs specs stmtSpecs, nextEnv)
end

def moduleCrosscallHelperSpecs (module : Module) : Except LowerError (Array CrosscallHelperSpec) := do
  let mut specs : Array CrosscallHelperSpec := #[]
  for entrypoint in module.entrypoints do
    let (entrypointSpecs, _) ← crosscallHelperSpecsStatements module (entrypointTypeEnv entrypoint) entrypoint.body
    specs := mergeCrosscallHelperSpecs specs entrypointSpecs
  .ok specs

def crosscallHelperFunctions (module : Module) (specs : Array CrosscallHelperSpec) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  specs.mapM (crosscallHelperFunction module)

def pushCreateHelperSpecIfMissing (acc : Array CreateHelperSpec) (value : CreateHelperSpec) : Array CreateHelperSpec :=
  if acc.any (fun existing => existing == value) then acc else acc.push value

def mergeCreateHelperSpecs (lhs rhs : Array CreateHelperSpec) : Array CreateHelperSpec :=
  rhs.foldl pushCreateHelperSpecIfMissing lhs

mutual
  partial def createHelperSpecsExpr : ProofForge.IR.Expr → Array CreateHelperSpec
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr value)
    | .arrayGet array index =>
        mergeCreateHelperSpecs (createHelperSpecsExpr array) (createHelperSpecsExpr index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr field.snd)
    | .field base _ =>
        createHelperSpecsExpr base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeCreateHelperSpecs (createHelperSpecsExpr lhs) (createHelperSpecsExpr rhs)
    | .cast value _ | .boolNot value | .hash value =>
        createHelperSpecsExpr value
    | .hashValue a b c d =>
        mergeCreateHelperSpecs
          (mergeCreateHelperSpecs (createHelperSpecsExpr a) (createHelperSpecsExpr b))
          (mergeCreateHelperSpecs (createHelperSpecsExpr c) (createHelperSpecsExpr d))
    | .nativeValue => #[]
    | .crosscallInvoke target methodId args =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr arg)
    | .crosscallInvokeTyped target methodId args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr methodId)
        let nested := mergeCreateHelperSpecs nested (createHelperSpecsExpr callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr arg)
    | .crosscallInvokeStaticTyped target methodId args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr arg)
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr arg)
    | .crosscallCreate callValue initCodeHex =>
        pushCreateHelperSpecIfMissing (createHelperSpecsExpr callValue) { mode := .create, initCodeHex }
    | .crosscallCreate2 callValue salt initCodeHex =>
        let nested := mergeCreateHelperSpecs (createHelperSpecsExpr callValue) (createHelperSpecsExpr salt)
        pushCreateHelperSpecIfMissing nested { mode := .create2, initCodeHex }
    | .effect effect =>
        createHelperSpecsEffect effect

  partial def createHelperSpecsEffect : Effect → Array CreateHelperSpec
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        createHelperSpecsExpr value
    | .storageMapContains _ key | .storageMapGet _ key =>
        createHelperSpecsExpr key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        mergeCreateHelperSpecs (createHelperSpecsExpr key) (createHelperSpecsExpr value)
    | .storageArrayRead _ index =>
        createHelperSpecsExpr index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value =>
        mergeCreateHelperSpecs (createHelperSpecsExpr index) (createHelperSpecsExpr value)
    | .storageArrayStructFieldRead _ index _ =>
        createHelperSpecsExpr index
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ value =>
        createHelperSpecsExpr value
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsStoragePathSegment segment)
    | .storagePathWrite _ path value =>
        let pathSpecs := path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsStoragePathSegment segment)
        mergeCreateHelperSpecs pathSpecs (createHelperSpecsExpr value)
    | .storagePathAssignOp _ path _ value =>
        let pathSpecs := path.foldl (init := #[]) fun acc segment =>
          mergeCreateHelperSpecs acc (createHelperSpecsStoragePathSegment segment)
        mergeCreateHelperSpecs pathSpecs (createHelperSpecsExpr value)
    | .contextRead _ => #[]
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedSpecs := indexedFields.foldl (init := #[]) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr field.snd)
        dataFields.foldl (init := indexedSpecs) fun acc field =>
          mergeCreateHelperSpecs acc (createHelperSpecsExpr field.snd)

  partial def createHelperSpecsStoragePathSegment : StoragePathSegment → Array CreateHelperSpec
    | .field _ => #[]
    | .index index => createHelperSpecsExpr index
    | .mapKey key => createHelperSpecsExpr key

  partial def createHelperSpecsStatement : Statement → Array CreateHelperSpec
    | .letBind _ _ value | .letMutBind _ _ value =>
        createHelperSpecsExpr value
    | .assign target value =>
        mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr value)
    | .assignOp target _ value =>
        mergeCreateHelperSpecs (createHelperSpecsExpr target) (createHelperSpecsExpr value)
    | .effect effect =>
        createHelperSpecsEffect effect
    | .assert condition _ _ =>
        createHelperSpecsExpr condition
    | .assertEq lhs rhs _ _ =>
        mergeCreateHelperSpecs (createHelperSpecsExpr lhs) (createHelperSpecsExpr rhs)
    | .release _ =>
        #[]
    | .ifElse condition thenBody elseBody =>
        mergeCreateHelperSpecs
          (createHelperSpecsExpr condition)
          (mergeCreateHelperSpecs (createHelperSpecsStatements thenBody) (createHelperSpecsStatements elseBody))
    | .boundedFor _ _ _ body =>
        createHelperSpecsStatements body
    | .return value =>
        createHelperSpecsExpr value

  partial def createHelperSpecsStatements (statements : Array Statement) : Array CreateHelperSpec :=
    statements.foldl (init := #[]) fun acc stmt =>
      mergeCreateHelperSpecs acc (createHelperSpecsStatement stmt)
end

def moduleCreateHelperSpecs (module : Module) : Array CreateHelperSpec :=
  module.entrypoints.foldl (init := #[]) fun acc entrypoint =>
    mergeCreateHelperSpecs acc (createHelperSpecsStatements entrypoint.body)

def createHelperFunctions (specs : Array CreateHelperSpec) : Except LowerError (Array Lean.Compiler.Yul.Statement) :=
  specs.mapM createHelperFunction

def localArrayGetLengthsForDynamicExprTarget
    (env : TypeEnv)
    (array index : ProofForge.IR.Expr) : Array Nat :=
  match literalArrayIndex? index with
  | some _ => #[]
  | none =>
      match array with
      | .local name =>
          match findLocal? env name with
          | some { type := .fixedArray _ length, .. } => #[length]
          | _ => #[]
      | .arrayLit _ values => #[values.size]
      | _ => #[]

def nestedLocalArrayGetShapesForDynamicExprTarget
    (env : TypeEnv)
    (array index : ProofForge.IR.Expr) : Array (Array Nat) :=
  let fullExpr := ProofForge.IR.Expr.arrayGet array index
  match collectLocalArrayGetPath fullExpr with
  | some (name, path) =>
      if path.size > 1 && arrayIndexPathHasDynamic path then
        match findLocal? env name with
        | some binding =>
            match fixedArrayPathShape "fixed array index" binding.type path with
            | .ok (lengths, leafType) =>
                match leafType with
                | .u32 | .u64 | .bool | .hash | .address | .structType _ => #[lengths]
                | .unit | .fixedArray _ _ | .bytes | .string => #[]
            | .error _ => #[]
        | none => #[]
      else
        #[]
  | none => #[]

mutual
  partial def localArrayGetLengthsExpr (env : TypeEnv) : ProofForge.IR.Expr → Array Nat
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value => mergeNatSets acc (localArrayGetLengthsExpr env value)
    | .arrayGet array index =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env array) (localArrayGetLengthsExpr env index)
        mergeNatSets nested (localArrayGetLengthsForDynamicExprTarget env array index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field => mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
    | .field base _ =>
        localArrayGetLengthsExpr env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs)
    | .cast value _ | .boolNot value | .hash value =>
        localArrayGetLengthsExpr env value
    | .hashValue a b c d =>
        mergeNatSets (mergeNatSets (localArrayGetLengthsExpr env a) (localArrayGetLengthsExpr env b))
          (mergeNatSets (localArrayGetLengthsExpr env c) (localArrayGetLengthsExpr env d))
    | .nativeValue => #[]
    | .crosscallInvoke target methodId args =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallInvokeTyped target methodId args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        let nested := mergeNatSets nested (localArrayGetLengthsExpr env callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallInvokeStaticTyped target methodId args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeNatSets (localArrayGetLengthsExpr env target) (localArrayGetLengthsExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatSets acc (localArrayGetLengthsExpr env arg)
    | .crosscallCreate callValue _ =>
        localArrayGetLengthsExpr env callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeNatSets (localArrayGetLengthsExpr env callValue) (localArrayGetLengthsExpr env salt)
    | .effect effect =>
        localArrayGetLengthsEffect env effect

  partial def localArrayGetLengthsEffect (env : TypeEnv) : Effect → Array Nat
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        localArrayGetLengthsExpr env value
    | .storageMapContains _ key | .storageMapGet _ key =>
        localArrayGetLengthsExpr env key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        mergeNatSets (localArrayGetLengthsExpr env key) (localArrayGetLengthsExpr env value)
    | .storageArrayRead _ index | .storageArrayStructFieldRead _ index _ =>
        localArrayGetLengthsExpr env index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value =>
        mergeNatSets (localArrayGetLengthsExpr env index) (localArrayGetLengthsExpr env value)
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ value =>
        localArrayGetLengthsExpr env value
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment => mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
    | .storagePathWrite _ path value =>
        let pathLengths := path.foldl (init := #[]) fun acc segment =>
          mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
        mergeNatSets pathLengths (localArrayGetLengthsExpr env value)
    | .storagePathAssignOp _ path _ value =>
        let pathLengths := path.foldl (init := #[]) fun acc segment =>
          mergeNatSets acc (localArrayGetLengthsStoragePathSegment env segment)
        mergeNatSets pathLengths (localArrayGetLengthsExpr env value)
    | .contextRead _ => #[]
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field => mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedLengths := indexedFields.foldl (init := #[]) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)
        dataFields.foldl (init := indexedLengths) fun acc field =>
          mergeNatSets acc (localArrayGetLengthsExpr env field.snd)

  partial def localArrayGetLengthsStoragePathSegment (env : TypeEnv) : StoragePathSegment → Array Nat
    | .field _ => #[]
    | .index index => localArrayGetLengthsExpr env index
    | .mapKey key => localArrayGetLengthsExpr env key

  partial def localArrayGetLengthsAssignTarget (env : TypeEnv) : ProofForge.IR.Expr → Array Nat
    | .arrayGet (.local _) index =>
        localArrayGetLengthsExpr env index
    | .field (.local _) _ =>
        #[]
    | target =>
        localArrayGetLengthsExpr env target

  partial def localArrayGetLengthsStatement
      (module : Module)
      (env : TypeEnv) : Statement → Except LowerError (Array Nat × TypeEnv)
    | .letBind name type value => do
        let nextEnv ← addLocal env name type false
        .ok (localArrayGetLengthsExpr env value, nextEnv)
    | .letMutBind name type value => do
        let nextEnv ← addLocal env name type true
        .ok (localArrayGetLengthsExpr env value, nextEnv)
    | .assign target value =>
        .ok (mergeNatSets (localArrayGetLengthsAssignTarget env target) (localArrayGetLengthsExpr env value), env)
    | .assignOp target _ value =>
        .ok (mergeNatSets (localArrayGetLengthsAssignTarget env target) (localArrayGetLengthsExpr env value), env)
    | .effect effect =>
        .ok (localArrayGetLengthsEffect env effect, env)
    | .assert condition _ _ =>
        .ok (localArrayGetLengthsExpr env condition, env)
    | .assertEq lhs rhs _ _ =>
        .ok (mergeNatSets (localArrayGetLengthsExpr env lhs) (localArrayGetLengthsExpr env rhs), env)
    | .release _ =>
        .ok (#[], env)
    | .ifElse condition thenBody elseBody => do
        let (thenLengths, _) ← localArrayGetLengthsStatements module env thenBody
        let (elseLengths, _) ← localArrayGetLengthsStatements module env elseBody
        let bodyLengths := mergeNatSets thenLengths elseLengths
        .ok (mergeNatSets (localArrayGetLengthsExpr env condition) bodyLengths, env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyLengths, _) ← localArrayGetLengthsStatements module loopEnv body
        .ok (bodyLengths, env)
    | .return value =>
        .ok (localArrayGetLengthsExpr env value, env)

  partial def localArrayGetLengthsStatements
      (module : Module)
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array Nat × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (lengths, currentEnv) := acc
      let (stmtLengths, nextEnv) ← localArrayGetLengthsStatement module currentEnv stmt
      .ok (mergeNatSets lengths stmtLengths, nextEnv)
end

def moduleLocalArrayGetLengths (module : Module) : Except LowerError (Array Nat) := do
  let mut lengths : Array Nat := #[]
  for entrypoint in module.entrypoints do
    let (entrypointLengths, _) ← localArrayGetLengthsStatements module (entrypointTypeEnv entrypoint) entrypoint.body
    lengths := mergeNatSets lengths entrypointLengths
  .ok lengths

mutual
  partial def nestedLocalArrayGetShapesExpr (env : TypeEnv) : ProofForge.IR.Expr → Array (Array Nat)
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit _ values =>
        values.foldl (init := #[]) fun acc value => mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env value)
    | .arrayGet array index =>
        let nested := mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
        mergeNatArraySets nested (nestedLocalArrayGetShapesForDynamicExprTarget env array index)
    | .structLit _ fields =>
        fields.foldl (init := #[]) fun acc field => mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
    | .field base _ =>
        nestedLocalArrayGetShapesExpr env base
    | .add lhs rhs | .sub lhs rhs | .mul lhs rhs | .div lhs rhs | .mod lhs rhs
    | .pow lhs rhs | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftLeft lhs rhs | .shiftRight lhs rhs | .eq lhs rhs | .ne lhs rhs
    | .lt lhs rhs | .le lhs rhs | .gt lhs rhs | .ge lhs rhs
    | .boolAnd lhs rhs | .boolOr lhs rhs | .hashTwoToOne lhs rhs =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs)
    | .cast value _ | .boolNot value | .hash value =>
        nestedLocalArrayGetShapesExpr env value
    | .hashValue a b c d =>
        mergeNatArraySets (mergeNatArraySets (nestedLocalArrayGetShapesExpr env a) (nestedLocalArrayGetShapesExpr env b))
          (mergeNatArraySets (nestedLocalArrayGetShapesExpr env c) (nestedLocalArrayGetShapesExpr env d))
    | .nativeValue => #[]
    | .crosscallInvoke target methodId args
    | .crosscallInvokeTyped target methodId args _
    | .crosscallInvokeStaticTyped target methodId args _
    | .crosscallInvokeDelegateTyped target methodId args _ =>
        let nested := mergeNatArraySets (nestedLocalArrayGetShapesExpr env target) (nestedLocalArrayGetShapesExpr env methodId)
        args.foldl (init := nested) fun acc arg =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)
    | .crosscallInvokeValueTyped target methodId callValue args _ =>
        let nested := mergeNatArraySets (nestedLocalArrayGetShapesExpr env target) (nestedLocalArrayGetShapesExpr env methodId)
        let nested := mergeNatArraySets nested (nestedLocalArrayGetShapesExpr env callValue)
        args.foldl (init := nested) fun acc arg =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env arg)
    | .crosscallCreate callValue _ =>
        nestedLocalArrayGetShapesExpr env callValue
    | .crosscallCreate2 callValue salt _ =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env callValue) (nestedLocalArrayGetShapesExpr env salt)
    | .effect effect =>
        nestedLocalArrayGetShapesEffect env effect

  partial def nestedLocalArrayGetShapesEffect (env : TypeEnv) : Effect → Array (Array Nat)
    | .storageScalarRead _ => #[]
    | .storageScalarWrite _ value | .storageScalarAssignOp _ _ value =>
        nestedLocalArrayGetShapesExpr env value
    | .storageMapContains _ key | .storageMapGet _ key =>
        nestedLocalArrayGetShapesExpr env key
    | .storageMapInsert _ key value | .storageMapSet _ key value =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env key) (nestedLocalArrayGetShapesExpr env value)
    | .storageArrayRead _ index =>
        nestedLocalArrayGetShapesExpr env index
    | .storageArrayWrite _ index value | .storageArrayStructFieldWrite _ index _ value =>
        mergeNatArraySets (nestedLocalArrayGetShapesExpr env index) (nestedLocalArrayGetShapesExpr env value)
    | .storageArrayStructFieldRead _ index _ =>
        nestedLocalArrayGetShapesExpr env index
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ value =>
        nestedLocalArrayGetShapesExpr env value
    | .storagePathRead _ path =>
        path.foldl (init := #[]) fun acc segment => mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
    | .storagePathWrite _ path value =>
        let pathShapes := path.foldl (init := #[]) fun acc segment =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
        mergeNatArraySets pathShapes (nestedLocalArrayGetShapesExpr env value)
    | .storagePathAssignOp _ path _ value =>
        let pathShapes := path.foldl (init := #[]) fun acc segment =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesStoragePathSegment env segment)
        mergeNatArraySets pathShapes (nestedLocalArrayGetShapesExpr env value)
    | .contextRead _ => #[]
    | .eventEmit _ fields =>
        fields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexedShapes := indexedFields.foldl (init := #[]) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)
        dataFields.foldl (init := indexedShapes) fun acc field =>
          mergeNatArraySets acc (nestedLocalArrayGetShapesExpr env field.snd)

  partial def nestedLocalArrayGetShapesStoragePathSegment (env : TypeEnv) : StoragePathSegment → Array (Array Nat)
    | .field _ => #[]
    | .index index => nestedLocalArrayGetShapesExpr env index
    | .mapKey key => nestedLocalArrayGetShapesExpr env key

  partial def nestedLocalArrayGetShapesAssignTarget (env : TypeEnv) : ProofForge.IR.Expr → Array (Array Nat)
    | .arrayGet array index =>
        let nested := mergeNatArraySets (nestedLocalArrayGetShapesExpr env array) (nestedLocalArrayGetShapesExpr env index)
        mergeNatArraySets nested (nestedLocalArrayGetShapesForDynamicExprTarget env array index)
    | .field target _ =>
        nestedLocalArrayGetShapesExpr env target
    | _ => #[]

  partial def nestedLocalArrayGetShapesStatement
      (module : Module)
      (env : TypeEnv) : Statement → Except LowerError (Array (Array Nat) × TypeEnv)
    | .letBind name type value => do
        let nextEnv ← addLocal env name type false
        .ok (nestedLocalArrayGetShapesExpr env value, nextEnv)
    | .letMutBind name type value => do
        let nextEnv ← addLocal env name type true
        .ok (nestedLocalArrayGetShapesExpr env value, nextEnv)
    | .assign target value =>
        .ok (mergeNatArraySets (nestedLocalArrayGetShapesAssignTarget env target) (nestedLocalArrayGetShapesExpr env value), env)
    | .assignOp target _ value =>
        .ok (mergeNatArraySets (nestedLocalArrayGetShapesAssignTarget env target) (nestedLocalArrayGetShapesExpr env value), env)
    | .effect effect =>
        .ok (nestedLocalArrayGetShapesEffect env effect, env)
    | .assert condition _ _ =>
        .ok (nestedLocalArrayGetShapesExpr env condition, env)
    | .assertEq lhs rhs _ _ =>
        .ok (mergeNatArraySets (nestedLocalArrayGetShapesExpr env lhs) (nestedLocalArrayGetShapesExpr env rhs), env)
    | .ifElse condition thenBody elseBody => do
        let (thenShapes, _) ← nestedLocalArrayGetShapesStatements module env thenBody
        let (elseShapes, _) ← nestedLocalArrayGetShapesStatements module env elseBody
        .ok (mergeNatArraySets (nestedLocalArrayGetShapesExpr env condition) (mergeNatArraySets thenShapes elseShapes), env)
    | .boundedFor indexName _ _ body => do
        let loopEnv ← addLocal env indexName .u32 false
        let (bodyShapes, _) ← nestedLocalArrayGetShapesStatements module loopEnv body
        .ok (bodyShapes, env)
    | .release _ =>
        .ok (#[], env)
    | .return value =>
        .ok (nestedLocalArrayGetShapesExpr env value, env)

  partial def nestedLocalArrayGetShapesStatements
      (module : Module)
      (env : TypeEnv)
      (statements : Array Statement) : Except LowerError (Array (Array Nat) × TypeEnv) :=
    statements.foldlM (init := (#[], env)) fun acc stmt => do
      let (shapes, currentEnv) := acc
      let (stmtShapes, nextEnv) ← nestedLocalArrayGetShapesStatement module currentEnv stmt
      .ok (mergeNatArraySets shapes stmtShapes, nextEnv)
end

def moduleNestedLocalArrayGetShapes (module : Module) : Except LowerError (Array (Array Nat)) := do
  let mut shapes : Array (Array Nat) := #[]
  for entrypoint in module.entrypoints do
    let (entrypointShapes, _) ← nestedLocalArrayGetShapesStatements module (entrypointTypeEnv entrypoint) entrypoint.body
    shapes := mergeNatArraySets shapes entrypointShapes
  .ok shapes

def validateDistinctStructName (seen : Array String) (name : String) : Except LowerError (Array String) :=
  if name.isEmpty then
    .error { message := "struct name must be non-empty for IR EVM v0" }
  else if seen.contains name then
    .error { message := s!"duplicate struct `{name}`" }
  else
    .ok (seen.push name)

def validateDistinctStructFieldName (structName : String) (seen : Array String) (fieldName : String) : Except LowerError (Array String) :=
  if fieldName.isEmpty then
    .error { message := s!"struct `{structName}` field name must be non-empty" }
  else if seen.contains fieldName then
    .error { message := s!"duplicate field `{fieldName}` in struct `{structName}`" }
  else
    .ok (seen.push fieldName)

def validateStructs (module : Module) : Except LowerError Unit := do
  let _ ← module.structs.foldlM (init := #[]) fun seen decl =>
    validateDistinctStructName seen decl.name
  for decl in module.structs do
    if decl.fields.isEmpty then
      .error { message := s!"struct `{decl.name}` must declare at least one field" }
    let _ ← decl.fields.foldlM (init := #[]) fun seen field =>
      validateDistinctStructFieldName decl.name seen field.id
    for field in decl.fields do
      ensureStructLocalFieldType decl.name field.id field.type

def validateStorageStructState (context typeName : String) (module : Module) : Except LowerError Unit := do
  let some decl := findStruct? module typeName
    | .error { message := s!"{context} uses unknown struct `{typeName}`" }
  if decl.fields.isEmpty then
    .error { message := s!"{context} uses empty struct `{typeName}`; EVM IR v0 storage structs must have at least one field" }
  for field in decl.fields do
    ensureStructLocalFieldType decl.name field.id field.type

def validateState (module : Module) : Except LowerError Unit := do
  for state in module.state do
    match state.kind, state.type with
    | .scalar, .u32 => pure ()
    | .scalar, .u64 => pure ()
    | .scalar, .bool => pure ()
    | .scalar, .hash => pure ()
    | .scalar, .structType typeName =>
        validateStorageStructState s!"state `{state.id}`" typeName module
    | .scalar, other =>
        .error { message := s!"state `{state.id}` has unsupported EVM IR v0 type `{other.name}`" }
    | .map keyType capacity, valueType =>
        if isStorageWordType keyType && isStorageWordType valueType then
          pure ()
        else
          .error {
            message := s!"map state `{state.id}` has unsupported EVM IR v0 type `{mapShapeName keyType valueType capacity}`; storage maps support key/value word types U32, U64, Bool, or Hash"
          }
    | .array 0, _ =>
        .error { message := s!"array state `{state.id}` must have non-zero length" }
    | .array _, .u32 => pure ()
    | .array _, .u64 => pure ()
    | .array _, .bool => pure ()
    | .array _, .hash => pure ()
    | .array _, .structType typeName =>
        validateStorageStructState s!"array state `{state.id}`" typeName module
    | .array _, other =>
        .error { message := s!"array state `{state.id}` has unsupported EVM IR v0 element type `{other.name}`; storage arrays support U32, U64, Bool, Hash, or flat struct arrays" }

def validateCapabilities (module : Module) : Except LowerError Unit :=
  match resolveModule Target.evm module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

def plannedMapHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .mapSlot then
    mapHelperFunctions plan.mapAssignOps
  else
    #[]

def plannedArrayHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .arraySlot then arrayHelperFunctions else #[]

def plannedStructArrayHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .structArraySlot then structArrayHelperFunctions else #[]

def plannedHashHelperFunctions (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Array Lean.Compiler.Yul.Statement :=
  if plan.hasHelper .hashWord || plan.hasHelper .hashPair then hashHelperFunctions else #[]

/-! Detect whether a module uses any `.add`/`.sub`/`.mul` `Expr` or compound
    assignment op that would route to the checked-arithmetic helpers. Used to
    avoid emitting the helpers when a module only uses div/mod/bitwise/shift. -/
mutual
  partial def effectUsesCheckedArithmetic : Effect → Bool
    | .storageScalarWrite _ v => exprUsesCheckedArithmetic v
    | .storageScalarAssignOp _ op v => needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageMapInsert _ _ v => exprUsesCheckedArithmetic v
    | .storageMapSet _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayWrite _ _ v => exprUsesCheckedArithmetic v
    | .storageArrayStructFieldWrite _ _ _ v => exprUsesCheckedArithmetic v
    | .storageStructFieldWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathWrite _ _ v => exprUsesCheckedArithmetic v
    | .storagePathAssignOp _ _ op v => needsCheckedArithmetic op || exprUsesCheckedArithmetic v
    | .storageScalarRead _ | .storageMapContains _ _ | .storageMapGet _ _
    | .storageArrayRead _ _ | .storageArrayStructFieldRead _ _ _
    | .storageStructFieldRead _ _ | .storagePathRead _ _
    | .contextRead _ | .eventEmit _ _ | .eventEmitIndexed _ _ _ => false

  partial def exprUsesCheckedArithmetic : Expr → Bool
    | .add _ _ | .sub _ _ | .mul _ _ => true
    | .literal _ | .local _ | .nativeValue => false
    | .arrayLit _ xs => xs.any exprUsesCheckedArithmetic
    | .arrayGet a i => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic i
    | .structLit _ fs => fs.any (fun (_, v) => exprUsesCheckedArithmetic v)
    | .field b _ => exprUsesCheckedArithmetic b
    | .div l r | .mod l r | .pow l r
    | .bitAnd l r | .bitOr l r | .bitXor l r
    | .shiftLeft l r | .shiftRight l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .cast v _ => exprUsesCheckedArithmetic v
    | .eq l r | .ne l r | .lt l r | .le l r | .gt l r | .ge l r
    | .boolAnd l r | .boolOr l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .boolNot v => exprUsesCheckedArithmetic v
    | .hashValue a b c d => exprUsesCheckedArithmetic a || exprUsesCheckedArithmetic b
        || exprUsesCheckedArithmetic c || exprUsesCheckedArithmetic d
    | .hash p => exprUsesCheckedArithmetic p
    | .hashTwoToOne l r => exprUsesCheckedArithmetic l || exprUsesCheckedArithmetic r
    | .crosscallInvoke t m args | .crosscallInvokeTyped t m args _
    | .crosscallInvokeValueTyped t m _ args _
    | .crosscallInvokeStaticTyped t m args _ | .crosscallInvokeDelegateTyped t m args _ =>
        exprUsesCheckedArithmetic t || exprUsesCheckedArithmetic m || args.any exprUsesCheckedArithmetic
    | .crosscallCreate v _ => exprUsesCheckedArithmetic v
    | .crosscallCreate2 v s _ => exprUsesCheckedArithmetic v || exprUsesCheckedArithmetic s
    | .effect e => effectUsesCheckedArithmetic e

  partial def stmtUsesCheckedArithmetic : Statement → Bool
    | .letBind _ _ v | .letMutBind _ _ v | .assign _ v | .assignOp _ _ v | .return v =>
        exprUsesCheckedArithmetic v
    | .assert _ _ _ | .assertEq _ _ _ _ | .release _ => false
    | .effect e => effectUsesCheckedArithmetic e
    | .ifElse c thenBody elseBody =>
        exprUsesCheckedArithmetic c || thenBody.any stmtUsesCheckedArithmetic
          || elseBody.any stmtUsesCheckedArithmetic
    | .boundedFor _ _ _ body => body.any stmtUsesCheckedArithmetic
end

def moduleUsesCheckedArithmetic (module : Module) : Bool :=
  module.entrypoints.any (fun ep => ep.body.any stmtUsesCheckedArithmetic)

def plannedCheckedArithmeticHelperFunctions (module : Module) :
    Array Lean.Compiler.Yul.Statement :=
  if moduleUsesCheckedArithmetic module then checkedArithmeticHelperFunctions else #[]

def lowerModuleWithPlan
    (module : Module)
    (plan : ProofForge.Backend.Evm.Plan.ModulePlan) :
    Except LowerError Lean.Compiler.Yul.Object := do
  validateStructs module
  validateState module
  let functions ← module.entrypoints.foldlM (init := #[]) fun acc entrypoint => do
    .ok (acc.push (← lowerEntrypoint module entrypoint))
  let dispatch ← dispatchBlock module
  let helpers := plannedMapHelperFunctions plan
  let helpers := helpers ++ plannedArrayHelperFunctions plan
  let helpers := helpers ++ plannedStructArrayHelperFunctions plan
  let helpers := helpers ++ plannedHashHelperFunctions plan
  let helpers := helpers ++ plannedCheckedArithmeticHelperFunctions module
  let crosscallSpecs ← moduleCrosscallHelperSpecs module
  let helpers := helpers ++ (← crosscallHelperFunctions module crosscallSpecs)
  let createSpecs := moduleCreateHelperSpecs module
  let helpers := helpers ++ (← createHelperFunctions createSpecs)
  let localArrayGetLengths ← moduleLocalArrayGetLengths module
  let helpers := helpers ++ localArrayGetHelperFunctions localArrayGetLengths
  let nestedLocalArrayGetShapes ← moduleNestedLocalArrayGetShapes module
  let helpers := helpers ++ nestedLocalArrayGetHelperFunctions nestedLocalArrayGetShapes
  .ok {
    name := module.name
    code := { statements := #[dispatch] ++ functions ++ helpers }
  }

/-- Build the full EVM semantic plan for `module` before lowering to Yul.

The plan is constructed by `Lower.buildFullModulePlan`, which populates
`EntrypointPlan` nodes (selector, ABI params, return shape), `EventPlan` nodes
(signature, field layout), and `MetadataPlan`. Helper specs (crosscall, create,
local-array-get, nested-local-array-get) and the checked-arithmetic flag are
discovered from the IR and recorded on the plan so `ToYul` and metadata passes
can consume them without re-discovering facts from rendered Yul. -/

def toPlanCrosscallMode (mode : CrosscallMode) : ProofForge.Backend.Evm.Plan.CrosscallMode :=
  match mode with
  | .call => .call
  | .callValue => .callValue
  | .staticcall => .staticcall
  | .delegatecall => .delegatecall

def toPlanCrosscallSpec (spec : CrosscallHelperSpec) : ProofForge.Backend.Evm.Plan.CrosscallHelperSpec :=
  { arity := spec.arity, returnType := spec.returnType, mode := toPlanCrosscallMode spec.mode }

def toPlanCreateMode (mode : CreateMode) : ProofForge.Backend.Evm.Plan.CreateMode :=
  match mode with
  | .create => .create
  | .create2 => .create2

def toPlanCreateSpec (spec : CreateHelperSpec) : ProofForge.Backend.Evm.Plan.CreateHelperSpec :=
  { mode := toPlanCreateMode spec.mode, initCodeHex := spec.initCodeHex }

def buildSemanticPlan (module : Module) : Except LowerError ProofForge.Backend.Evm.Plan.ModulePlan := do
  let plan ←
    match ProofForge.Backend.Evm.Lower.buildFullModulePlan module with
    | .ok p => .ok p
    | .error err => .error { message := err.message }
  let crosscallSpecs ← moduleCrosscallHelperSpecs module
  let createSpecs := moduleCreateHelperSpecs module
  let localArrayGetLengths ← moduleLocalArrayGetLengths module
  let nestedLocalArrayGetShapes ← moduleNestedLocalArrayGetShapes module
  let usesCheckedArithmetic := moduleUsesCheckedArithmetic module
  .ok { plan with
    crosscalls := crosscallSpecs.map toPlanCrosscallSpec
    creates := createSpecs.map toPlanCreateSpec
    localArrayGetLengths := localArrayGetLengths
    nestedLocalArrayGetShapes := nestedLocalArrayGetShapes
    usesCheckedArithmetic := usesCheckedArithmetic
  }

/-- Build the semantic plan best-effort, catching plan-construction errors so
    diagnostic smokes that intentionally feed unsupported shapes still render
    the expected diagnostic message rather than aborting at plan time. -/

def buildSemanticPlanBestEffort (module : Module) : ProofForge.Backend.Evm.Plan.ModulePlan :=
  match buildSemanticPlan module with
  | .ok plan => plan
  | .error _ =>
    match ProofForge.Backend.Evm.Plan.buildModulePlan module with
    | .ok plan => plan
    | .error _ => {
      name := module.name
      targetPlan := { targetId := Target.evm.id, calls := #[] }
      storage := ProofForge.Backend.Evm.Plan.storageLayout module
      helpers := #[]
      mapAssignOps := #[]
      entrypoints := #[]
      events := #[]
      crosscalls := #[]
      creates := #[]
      localArrayGetLengths := #[]
      nestedLocalArrayGetShapes := #[]
      usesCheckedArithmetic := false
      metadata := {
        moduleName := module.name
        entrypoints := #[]
        events := #[]
        capabilities := #[]
      }
    }

def lowerModule (module : Module) : Except LowerError Lean.Compiler.Yul.Object := do
  let fullPlan := buildSemanticPlanBestEffort module
  lowerModuleWithPlan module fullPlan

def renderModule (module : Module) : Except LowerError String := do
  .ok (Lean.Compiler.Yul.Printer.render (← lowerModule module))

/-- Render the EVM semantic plan for inspection without producing Yul. -/

def renderSemanticPlan (module : Module) : Except LowerError String := do
  let plan ← buildSemanticPlan module
  let mut parts : Array String := #[]
  parts := parts.push s!"module: {plan.name}"
  parts := parts.push s!"target: {plan.targetPlan.targetId}"
  let capIds := plan.capabilities.map (·.id)
  parts := parts.push s!"capabilities: {String.intercalate ", " capIds.toList}"
  parts := parts.push "storage:"
  for state in plan.storage.states do
    parts := parts.push s!"  {state.id}: slot {state.slot}, span {state.span}"
  parts := parts.push "entrypoints:"
  for ep in plan.entrypoints do
    parts := parts.push s!"  {ep.name}: selector 0x{ep.selector}, {ep.params.size} param(s), returns {ep.returns.returnType.name}"
  parts := parts.push "events:"
  for ev in plan.events do
    parts := parts.push s!"  {ev.name}: {ev.signature}, {ev.fields.size} field(s)"
  parts := parts.push s!"crosscalls: {plan.crosscalls.size}"
  parts := parts.push s!"creates: {plan.creates.size}"
  parts := parts.push s!"localArrayGetLengths: {plan.localArrayGetLengths}"
  parts := parts.push s!"usesCheckedArithmetic: {plan.usesCheckedArithmetic}"
  let helperNames := plan.helpers.map ProofForge.Backend.Evm.Plan.Helper.name
  parts := parts.push s!"helpers: {String.intercalate ", " helperNames.toList}"
  .ok (String.intercalate "\n" parts.toList)

/-- Build artifact metadata from the semantic plan (RFC 0004 Metadata pass). -/

def buildPlanArtifactMetadata (module : Module) : Except LowerError ProofForge.Backend.Evm.Metadata.ArtifactMetadata := do
  let plan ← buildSemanticPlan module
  .ok (ProofForge.Backend.Evm.Metadata.buildArtifactMetadata plan)

/-- Build deploy metadata from the semantic plan (RFC 0004 Metadata pass). -/

def buildPlanDeployMetadata (module : Module) : Except LowerError ProofForge.Backend.Evm.Metadata.DeployMetadata := do
  let plan ← buildSemanticPlan module
  .ok (ProofForge.Backend.Evm.Metadata.buildDeployMetadata plan)

end ProofForge.Backend.Evm.IR
