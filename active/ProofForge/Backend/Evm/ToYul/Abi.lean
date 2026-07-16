import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Backend.Evm.ToYul.Local
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def calldataloadAt (offset : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[offset]

def dynamicParamLengthName (name : String) : String :=
  ProofForge.Backend.Evm.Plan.dynamicParamLengthName name

def dynamicParamDataPtrName (name : String) : String :=
  ProofForge.Backend.Evm.Plan.dynamicParamDataPtrName name

partial def localAbiWordsAt
    {ε : Type}
    (mkError : String → ε)
    (structFieldIds : String → Except ε (Array String))
    (context name : String)
    (path : Array Nat) : ValueType → Except ε (Array Lean.Compiler.Yul.Expr)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      if path.isEmpty then
        .ok #[Lean.Compiler.Yul.Expr.id name]
      else
        .ok #[Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path)]
  | .unit =>
      .error (mkError s!"{context} uses Unit; IR EVM v0 ABI values must use U32, U64, Bool, Hash, Address, Bytes, String, fixed arrays, or structs")
  | .bytes | .string | .array _ =>
      if path.isEmpty then
        .ok #[Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName name)]
      else
        .error (mkError s!"{context} dynamic type cannot be nested in fixed arrays")
  | .fixedArray elementType length => do
      if length == 0 then
        .error (mkError s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length")
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for _h : idx in [0:length] do
        words := words ++ (← localAbiWordsAt mkError structFieldIds context name (path.push idx) elementType)
      .ok words
  | .structType typeName => do
      let fieldIds ← structFieldIds typeName
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for fieldId in fieldIds do
        let fieldName :=
          if path.isEmpty then
            structLocalFieldName name fieldId
          else
            arrayStructLocalPathFieldName name path fieldId
        words := words.push (Lean.Compiler.Yul.Expr.id fieldName)
      .ok words

def localAbiWords
    {ε : Type}
    (mkError : String → ε)
    (structFieldIds : String → Except ε (Array String))
    (context name : String)
    (type : ValueType) : Except ε (Array Lean.Compiler.Yul.Expr) :=
  localAbiWordsAt mkError structFieldIds context name #[] type

def storageAbiWords
    {ε : Type}
    (mkError : String → ε)
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context stateId : String)
    (type : ValueType) : Except ε (Array Lean.Compiler.Yul.Expr) := do
  match type with
  | .structType typeName =>
      storageStructWords context typeName stateId
  | .fixedArray elementType length =>
      storageArrayWords context stateId elementType length
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .unit
  | .bytes | .string | .array _ =>
      .error (mkError s!"{context} storage-backed ABI word expansion supports struct scalar storage or fixed storage arrays only, got `{type.name}`")

partial def abiValueWordsFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context : String)
    (type : ValueType)
    (value : AbiValuePlan) :
    Except ε (Array Lean.Compiler.Yul.Expr) := do
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      match value with
      | .expr plan => .ok #[← lowerPlanExpr plan]
      | _ => .error (mkError s!"{context} scalar ABI value requires an expression plan")
  | .fixedArray elementType length =>
      match value with
      | .local name plannedType =>
          if plannedType == type then
            localAbiWords mkError (fun typeName => do
              let fields ← structFields typeName
              .ok (fields.map fun field => field.fst)) context name type
          else
            .error (mkError s!"{context} local ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .storage stateId plannedType =>
          if plannedType == type then
            storageAbiWords mkError storageStructWords storageArrayWords context stateId type
          else
            .error (mkError s!"{context} storage ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .arrayLit literalElementType values => do
          if literalElementType != elementType then
            .error (mkError s!"{context} fixed-array literal element type mismatch: expected `{elementType.name}`, got `{literalElementType.name}`")
          if values.size != length then
            .error (mkError s!"{context} fixed-array expected length {length}, got {values.size}")
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            words := words ++
              (← abiValueWordsFromPlan
                mkError
                lowerPlanExpr
                structFields
                storageStructWords
                storageArrayWords
                s!"{context} fixed-array element {idx}"
                elementType
                values[idx])
          .ok words
      | _ =>
          .error (mkError s!"{context} aggregate field requires an ABI word expansion plan")
  | .structType typeName =>
      match value with
      | .local name plannedType =>
          if plannedType == type then
            localAbiWords mkError (fun typeName => do
              let fields ← structFields typeName
              .ok (fields.map fun field => field.fst)) context name type
          else
            .error (mkError s!"{context} local ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .storage stateId plannedType =>
          if plannedType == type then
            storageAbiWords mkError storageStructWords storageArrayWords context stateId type
          else
            .error (mkError s!"{context} storage ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .structLit literalTypeName fields => do
          if literalTypeName != typeName then
            .error (mkError s!"{context} expected struct `{typeName}`, got `{literalTypeName}`")
          let fieldDecls ← structFields typeName
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for fieldDecl in fieldDecls do
            let some field := fields.find? fun field => field.fst == fieldDecl.fst
              | .error (mkError s!"{context} struct literal `{typeName}` is missing field `{fieldDecl.fst}`")
            words := words ++
              (← abiValueWordsFromPlan
                mkError
                lowerPlanExpr
                structFields
                storageStructWords
                storageArrayWords
                s!"{context} struct field `{fieldDecl.fst}`"
                fieldDecl.snd
                field.snd)
          .ok words
      | _ =>
          .error (mkError s!"{context} aggregate field requires an ABI word expansion plan")
  | .unit | .bytes | .string | .array _ =>
      .error (mkError s!"{context} has unsupported ABI word type `{type.name}`")

def returnValueWordPlanWords
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context : String)
    (plan : ReturnValueWordPlan) : Except ε (Array Lean.Compiler.Yul.Expr) :=
  abiValueWordsFromPlan
    mkError
    lowerPlanExpr
    structFields
    storageStructWords
    storageArrayWords
    context
    plan.returns.returnType
    plan.source

def returnValueWordAssignments
    {ε : Type}
    (mkError : String → ε)
    (context : String)
    (returns : ReturnPlan)
    (words : Array Lean.Compiler.Yul.Expr) : Except ε (Array Lean.Compiler.Yul.Statement) := do
  if returns.localNames.size != words.size then
    .error (mkError s!"{context} return lowering produced {words.size} word(s), expected {returns.localNames.size}")
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:returns.localNames.size] do
    let some word := words[idx]?
      | .error (mkError s!"{context} return lowering is missing word {idx}")
    statements := statements.push (.assignment #[returns.localNames[idx]] word)
  .ok statements

def returnValueWordPlanAssignments
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context : String)
    (plan : ReturnValueWordPlan) : Except ε (Array Lean.Compiler.Yul.Statement) := do
  let words ← returnValueWordPlanWords
    mkError
    lowerPlanExpr
    structFields
    storageStructWords
    storageArrayWords
    context
    plan
  returnValueWordAssignments mkError context plan.returns words

def abiParamsHeadWordCount (params : Array AbiParamPlan) : Nat :=
  params.foldl (fun acc param => acc + param.headWordCount) 0

def abiParamsMinSizeValidationStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  let headWordCount := abiParamsHeadWordCount params
  let minSize := 4 + headWordCount * 32
  if headWordCount == 0 then
    #[]
  else
    #[
      Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "lt" #[
          Lean.Compiler.Yul.builtin "calldatasize" #[],
          Lean.Compiler.Yul.Expr.num minSize
        ])
        { statements := #[revertStatement] }
    ]

def abiWordValidationStatement?
    (word : Lean.Compiler.Yul.Expr)
    (type : ValueType)
    (abiWord? : Option String := none) : Option Lean.Compiler.Yul.Statement :=
  let upperBoundGuard (limit : Nat) :=
    some <| Lean.Compiler.Yul.Statement.ifStmt
      (Lean.Compiler.Yul.builtin "gt" #[word, Lean.Compiler.Yul.Expr.num limit])
      { statements := #[revertStatement] }
  match abiWord? with
  | some "address" =>
      upperBoundGuard 1461501637330902918203684832716283019655932542975
  | some "bytes4" =>
      some <| Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "and" #[
          word,
          Lean.Compiler.Yul.Expr.num
            26959946667150639794667015087019630673637144422540572481103610249215
        ])
        { statements := #[revertStatement] }
  | some "bytes32" | some "uint256" => none
  | some "uint8" => upperBoundGuard 255
  | some "uint32" => upperBoundGuard 4294967295
  | some "uint64" => upperBoundGuard 18446744073709551615
  | some "uint128" => upperBoundGuard 340282366920938463463374607431768211455
  | some "bool" => upperBoundGuard 1
  | some _ | none =>
      match type with
      | .u8 => upperBoundGuard 255
      | .u32 => upperBoundGuard 4294967295
      | .u64 => upperBoundGuard 18446744073709551615
      | .u128 => upperBoundGuard 340282366920938463463374607431768211455
      | .bool => upperBoundGuard 1
      | .address => upperBoundGuard 1461501637330902918203684832716283019655932542975
      | .hash | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
          none

def abiParamHeadValidationStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for h : i in [0:params.size] do
      let param := params[i]
      if param.isDynamic then
        let offsetExpr := calldataWordExpr param.headWordIndex
        let baseOffset := Lean.Compiler.Yul.Expr.num (4 + param.headWordIndex * 32)
        let offsetPlusBase := Lean.Compiler.Yul.builtin "add" #[baseOffset, offsetExpr]
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.ifStmt
            (Lean.Compiler.Yul.builtin "gt" #[
              offsetPlusBase,
              Lean.Compiler.Yul.builtin "calldatasize" #[]
            ])
            { statements := #[revertStatement] }
      else
        for h : j in [0:param.wordTypes.size] do
          let wordIndex := param.headWordIndex + j
          match abiWordValidationStatement? (calldataWordExpr wordIndex) param.wordTypes[j]
              (if j == 0 then param.abiWord? else none) with
          | some statement => statements := statements.push statement
          | none => pure ()
    statements

def dynamicBytesStringParamDecodeStatements (param : AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  let offsetExpr := calldataWordExpr param.headWordIndex
  let dataOffset := Lean.Compiler.Yul.builtin "add" #[
    Lean.Compiler.Yul.Expr.num (4 + param.headWordIndex * 32),
    offsetExpr
  ]
  let lengthExpr := calldataloadAt dataOffset
  let memPtrName := s!"__pf_dyn_ptr_{param.name}"
  let memPtr := Lean.Compiler.Yul.Expr.id memPtrName
  let dataStart := Lean.Compiler.Yul.builtin "add" #[memPtr, Lean.Compiler.Yul.Expr.num 32]
  let wordCount := Lean.Compiler.Yul.builtin "div" #[
    Lean.Compiler.Yul.builtin "add" #[lengthExpr, Lean.Compiler.Yul.Expr.num 31],
    Lean.Compiler.Yul.Expr.num 32
  ]
  let memSize := Lean.Compiler.Yul.builtin "mul" #[wordCount, Lean.Compiler.Yul.Expr.num 32]
  let totalSize := Lean.Compiler.Yul.builtin "add" #[memSize, Lean.Compiler.Yul.Expr.num 32]
  let tailEnd := Lean.Compiler.Yul.builtin "add" #[
    dataOffset,
    Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.num 32, memSize]
  ]
  #[
    .ifStmt
      (Lean.Compiler.Yul.builtin "gt" #[tailEnd, Lean.Compiler.Yul.builtin "calldatasize" #[]])
      { statements := #[revertStatement] },
    .varDecl #[{ name := memPtrName }]
      (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0x40])),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[memPtr, lengthExpr]),
    .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
      dataStart,
      Lean.Compiler.Yul.builtin "add" #[dataOffset, Lean.Compiler.Yul.Expr.num 32],
      memSize
    ]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
      Lean.Compiler.Yul.Expr.num 0x40,
      Lean.Compiler.Yul.builtin "add" #[memPtr, totalSize]
    ]),
    .varDecl #[{ name := dynamicParamLengthName param.name }] (some lengthExpr),
    .varDecl #[{ name := dynamicParamDataPtrName param.name }] (some memPtr)
  ]

def dynamicArrayParamDecodeStatements (param : AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  match param.type with
  | .array _ =>
    let offsetExpr := calldataWordExpr param.headWordIndex
    let dataOffset := Lean.Compiler.Yul.builtin "add" #[
      Lean.Compiler.Yul.Expr.num (4 + param.headWordIndex * 32),
      offsetExpr
    ]
    let lengthExpr := calldataloadAt dataOffset
    let memPtrName := s!"__pf_dyn_ptr_{param.name}"
    let memPtr := Lean.Compiler.Yul.Expr.id memPtrName
    let memSize := Lean.Compiler.Yul.builtin "mul" #[lengthExpr, Lean.Compiler.Yul.Expr.num 32]
    let totalSize := Lean.Compiler.Yul.builtin "add" #[memSize, Lean.Compiler.Yul.Expr.num 32]
    let tailEnd := Lean.Compiler.Yul.builtin "add" #[
      dataOffset,
      Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.num 32, memSize]
    ]
    #[
      .ifStmt
        (Lean.Compiler.Yul.builtin "gt" #[tailEnd, Lean.Compiler.Yul.builtin "calldatasize" #[]])
        { statements := #[revertStatement] },
      .varDecl #[{ name := memPtrName }]
        (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0x40])),
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[memPtr, lengthExpr]),
      .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
        Lean.Compiler.Yul.builtin "add" #[memPtr, Lean.Compiler.Yul.Expr.num 32],
        Lean.Compiler.Yul.builtin "add" #[dataOffset, Lean.Compiler.Yul.Expr.num 32],
        memSize
      ]),
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num 0x40,
        Lean.Compiler.Yul.builtin "add" #[memPtr, totalSize]
      ]),
      .varDecl #[{ name := dynamicParamLengthName param.name }] (some lengthExpr),
      .varDecl #[{ name := dynamicParamDataPtrName param.name }] (some memPtr)
    ]
  | _ => #[]

def dynamicAbiParamDecodeStatements (param : AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  if param.isDynamic then
    match param.type with
    | .array _ => dynamicArrayParamDecodeStatements param
    | _ => dynamicBytesStringParamDecodeStatements param
  else
    #[]

def abiParamDecodeStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  params.foldl (fun acc param => acc ++ dynamicAbiParamDecodeStatements param) #[]

def abiParamValidationAndDecodeStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  abiParamsMinSizeValidationStatements params ++
    abiParamHeadValidationStatements params ++
    abiParamDecodeStatements params

def entrypointCallArgs (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Expr :=
  Id.run do
    let mut args : Array Lean.Compiler.Yul.Expr := #[]
    for h : i in [0:params.size] do
      let param := params[i]
      if param.isDynamic then
        args := args.push (Lean.Compiler.Yul.Expr.id (dynamicParamLengthName param.name))
        args := args.push (Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName param.name))
      else
        for h : j in [0:param.wordTypes.size] do
          args := args.push (calldataWordExpr (param.headWordIndex + j))
    args

def entrypointParamTypedNames (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.TypedName :=
  params.foldl
    (fun acc param =>
      acc ++ param.localNames.map (fun name => ({ name := name } : Lean.Compiler.Yul.TypedName)))
    #[]

def returnTypedNames (returns : ReturnPlan) : Array Lean.Compiler.Yul.TypedName :=
  returns.localNames.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName)

end ProofForge.Backend.Evm.ToYul
