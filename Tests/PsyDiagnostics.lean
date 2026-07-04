import ProofForge.Backend.Psy.IR
import ProofForge.IR.Contract

namespace ProofForge.Tests.PsyDiagnostics

open ProofForge.IR

def markerState : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def countState : StateDecl := {
  id := "count"
  kind := .scalar
  type := .u64
}

def pointStructNoStorage : StructDecl := {
  name := "Point"
  fields := #[
    { id := "x", type := .u64 }
  ]
}

def pairStruct : StructDecl := {
  name := "Pair"
  fields := #[
    { id := "left", type := .u64 },
    { id := "right", type := .u64 }
  ]
}

def unitEntrypoint (name : String) (body : Array Statement := #[]) : Entrypoint := {
  name := name
  returns := .unit
  body := body
}

def invalidModuleIdentifierModule : Module := {
  name := "Bad-Module"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad"]
}

def emptyStateModule : Module := {
  name := "BadEmptyState"
  state := #[]
  entrypoints := #[unitEntrypoint "bad"]
}

def duplicateStateModule : Module := {
  name := "BadDuplicateState"
  state := #[countState, countState]
  entrypoints := #[unitEntrypoint "bad"]
}

def duplicateEntrypointModule : Module := {
  name := "BadDuplicateEntrypoint"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad", unitEntrypoint "bad"]
}

def reservedLocalIdentifierModule : Module := {
  name := "BadReservedLocal"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "let" .u64 (.literal (.u64 1))
  ]]
}

def unitParamModule : Module := {
  name := "BadUnitParam"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    params := #[("x", .unit)]
    returns := .unit
    body := #[]
  }]
}

def zeroArrayParamModule : Module := {
  name := "BadZeroArrayParam"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    params := #[("xs", .fixedArray .u64 0)]
    returns := .unit
    body := #[]
  }]
}

def unknownReturnStructModule : Module := {
  name := "BadUnknownReturnStruct"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .structType "Missing"
    body := #[]
  }]
}

def selectorEntrypointModule : Module := {
  name := "BadEntrypointSelector"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    selector? := some "0xdeadbeef"
    returns := .unit
    body := #[]
  }]
}

def unsupportedMapModule : Module := {
  name := "BadMapShape"
  state := #[{
    id := "bad_map"
    kind := .map .u64 16
    type := .u64
  }]
  entrypoints := #[unitEntrypoint "bad"]
}

def unsupportedUnitArrayStateModule : Module := {
  name := "BadUnitArrayState"
  state := #[{
    id := "units"
    kind := .array 8
    type := .unit
  }]
  entrypoints := #[unitEntrypoint "bad"]
}

def balancesMapState : StateDecl := {
  id := "balances"
  kind := .map .hash 16
  type := .hash
}

def nonStorageStructStateModule : Module := {
  name := "BadStructState"
  structs := #[pointStructNoStorage]
  state := #[{
    id := "current"
    kind := .scalar
    type := .structType "Point"
  }]
  entrypoints := #[unitEntrypoint "bad"]
}

def emptyStructModule : Module := {
  name := "BadEmptyStruct"
  structs := #[{
    name := "Empty"
    fields := #[]
  }]
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad"]
}

def invalidLoopModule : Module := {
  name := "BadLoop"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .boundedFor "_i" 0 0 #[]
  ]]
}

def storageWriteExprModule : Module := {
  name := "BadStorageWriteExpr"
  state := #[countState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.effect (.storageScalarWrite "count" (.literal (.u64 1))))
    ]
  }]
}

def storageScalarAssignExprModule : Module := {
  name := "BadStorageScalarAssignExpr"
  state := #[countState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.effect (.storageScalarAssignOp "count" .add (.literal (.u64 1))))
    ]
  }]
}

def storageReadStmtModule : Module := {
  name := "BadStorageReadStmt"
  state := #[countState]
  entrypoints := #[unitEntrypoint "bad" #[
    .effect (.storageScalarRead "count")
  ]]
}

def invalidAssignTargetModule : Module := {
  name := "BadAssignTarget"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .assign
      (.add (.literal (.u64 1)) (.literal (.u64 2)))
      (.literal (.u64 3))
  ]]
}

def profileStorageStruct : StructDecl := {
  name := "Profile"
  deriveStorage := true
  fields := #[
    { id := "age", type := .u64 }
  ]
}

def personStorageStructNoRef : StructDecl := {
  name := "Person"
  deriveStorage := true
  fields := #[
    { id := "profile", type := .structType "Profile" }
  ]
}

def personStorageStructWithRef : StructDecl := {
  name := "Person"
  deriveStorage := true
  fields := #[
    { id := "profile", type := .structType "Profile", isRef := true }
  ]
}

def personStorageState : StateDecl := {
  id := "person"
  kind := .scalar
  type := .structType "Person"
}

def storagePathAssignExprModule : Module := {
  name := "BadStoragePathAssignExpr"
  structs := #[profileStorageStruct, personStorageStructWithRef]
  state := #[personStorageState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.effect (.storagePathAssignOp "person" #[.field "profile", .field "age"] .add (.literal (.u64 1))))
    ]
  }]
}

def emptyStoragePathModule : Module := {
  name := "BadEmptyStoragePath"
  structs := #[profileStorageStruct, personStorageStructWithRef]
  state := #[personStorageState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.effect (.storagePathRead "person" #[]))
    ]
  }]
}

def missingRefStoragePathModule : Module := {
  name := "BadMissingRefStoragePath"
  structs := #[profileStorageStruct, personStorageStructNoRef]
  state := #[personStorageState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.effect (.storagePathRead "person" #[.field "profile", .field "age"]))
    ]
  }]
}

def mapPathMissingKeyModule : Module := {
  name := "BadMapPathMissingKey"
  state := #[balancesMapState]
  entrypoints := #[{
    name := "bad"
    returns := .hash
    body := #[
      .return (.effect (.storagePathRead "balances" #[.field "missing"]))
    ]
  }]
}

def mapPathKeyTypeMismatchModule : Module := {
  name := "BadMapPathKeyType"
  state := #[balancesMapState]
  entrypoints := #[{
    name := "bad"
    returns := .hash
    body := #[
      .return (.effect (.storagePathRead "balances" #[.mapKey (.literal (.u64 1))]))
    ]
  }]
}

def unknownLocalModule : Module := {
  name := "BadUnknownLocal"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.local "missing")
    ]
  }]
}

def letTypeMismatchModule : Module := {
  name := "BadLetTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u64 (.literal (.bool true))
  ]]
}

def arrayElementMismatchModule : Module := {
  name := "BadArrayElementMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "xs" (.fixedArray .u64 2) (.arrayLit .u64 #[
      .literal (.u64 1),
      .literal (.bool true)
    ])
  ]]
}

def arrayLengthMismatchModule : Module := {
  name := "BadArrayLengthMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "xs" (.fixedArray .u64 2) (.arrayLit .u64 #[
      .literal (.u64 1)
    ])
  ]]
}

def structLiteralFieldMismatchModule : Module := {
  name := "BadStructLiteralFieldMismatch"
  structs := #[pairStruct]
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .structType "Pair"
    body := #[
      .return (.structLit "Pair" #[("left", .literal (.u64 1))])
    ]
  }]
}

def hashPreimageMismatchModule : Module := {
  name := "BadHashPreimageMismatch"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .hash
    body := #[
      .return (.hash (.literal (.u64 1)))
    ]
  }]
}

def hashValuePartMismatchModule : Module := {
  name := "BadHashValuePartMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "h" .hash (.hashValue
      (.literal (.u32 1))
      (.literal (.u64 2))
      (.literal (.u64 3))
      (.literal (.u64 4)))
  ]]
}

def immutableAssignModule : Module := {
  name := "BadImmutableAssign"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u64 (.literal (.u64 1)),
    .assign (.local "x") (.literal (.u64 2))
  ]]
}

def compoundAssignTypeMismatchModule : Module := {
  name := "BadCompoundAssignTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letMutBind "x" .u32 (.literal (.u32 1)),
    .assignOp (.local "x") .add (.literal (.u64 2))
  ]]
}

def immutableCompoundAssignModule : Module := {
  name := "BadImmutableCompoundAssign"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u32 (.literal (.u32 1)),
    .assignOp (.local "x") .bitOr (.literal (.u32 2))
  ]]
}

def returnTypeMismatchModule : Module := {
  name := "BadReturnTypeMismatch"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.literal (.bool true))
    ]
  }]
}

def missingReturnModule : Module := {
  name := "BadMissingReturn"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .letBind "x" .u64 (.literal (.u64 1))
    ]
  }]
}

def storageWriteTypeMismatchModule : Module := {
  name := "BadStorageWriteTypeMismatch"
  state := #[countState]
  entrypoints := #[unitEntrypoint "bad" #[
    .effect (.storageScalarWrite "count" (.literal (.bool true)))
  ]]
}

def storageScalarAssignTypeMismatchModule : Module := {
  name := "BadStorageScalarAssignTypeMismatch"
  state := #[countState]
  entrypoints := #[unitEntrypoint "bad" #[
    .effect (.storageScalarAssignOp "count" .add (.literal (.bool true)))
  ]]
}

def equalityTypeMismatchModule : Module := {
  name := "BadEqualityTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .assert (.eq (.literal (.u64 1)) (.literal (.bool true))) "bad equality"
  ]]
}

def comparisonTypeMismatchModule : Module := {
  name := "BadComparisonTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .assert (.lt (.literal (.bool true)) (.literal (.bool false))) "bad comparison"
  ]]
}

def subtractionTypeMismatchModule : Module := {
  name := "BadSubtractionTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u64 (.sub (.literal (.bool true)) (.literal (.u64 1)))
  ]]
}

def multiplicationTypeMismatchModule : Module := {
  name := "BadMultiplicationTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u64 (.mul (.literal (.u64 2)) (.literal (.bool true)))
  ]]
}

def divisionTypeMismatchModule : Module := {
  name := "BadDivisionTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u32 (.div (.literal (.u32 8)) (.literal (.u64 2)))
  ]]
}

def unsupportedCastModule : Module := {
  name := "BadUnsupportedCast"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .hash (.cast (.literal (.u32 1)) .hash)
  ]]
}

def bitwiseTypeMismatchModule : Module := {
  name := "BadBitwiseTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u32 (.bitAnd (.literal (.bool true)) (.literal (.u32 1)))
  ]]
}

def shiftTypeMismatchModule : Module := {
  name := "BadShiftTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .letBind "x" .u32 (.shiftLeft (.literal (.u32 1)) (.literal (.u64 1)))
  ]]
}

def booleanOperatorTypeMismatchModule : Module := {
  name := "BadBooleanOperatorTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .assert (.boolAnd (.literal (.u64 1)) (.literal (.bool true))) "bad boolean op"
  ]]
}

def ifConditionTypeMismatchModule : Module := {
  name := "BadIfConditionTypeMismatch"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .ifElse (.literal (.u64 1)) #[
      .assert (.literal (.bool true)) "then branch"
    ] #[]
  ]]
}

def branchLocalEscapeModule : Module := {
  name := "BadBranchLocalEscape"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .ifElse (.literal (.bool true)) #[
        .letBind "x" .u64 (.literal (.u64 1))
      ] #[],
      .return (.local "x")
    ]
  }]
}

def nativeValueExprModule : Module := {
  name := "BadNativeValue"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return .nativeValue
    ]
  }]
}

def typedCrosscallModule : Module := {
  name := "BadTypedCrosscall"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .bool
    body := #[
      .return (.crosscallInvokeTyped (.literal (.u64 1)) (.literal (.u64 2)) #[] .bool)
    ]
  }]
}

def valueTypedCrosscallModule : Module := {
  name := "BadValueTypedCrosscall"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.crosscallInvokeValueTyped (.literal (.u64 1)) (.literal (.u64 2)) .nativeValue #[] .u64)
    ]
  }]
}

def staticTypedCrosscallModule : Module := {
  name := "BadStaticTypedCrosscall"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.crosscallInvokeStaticTyped (.literal (.u64 1)) (.literal (.u64 2)) #[] .u64)
    ]
  }]
}

def delegateTypedCrosscallModule : Module := {
  name := "BadDelegateTypedCrosscall"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.crosscallInvokeDelegateTyped (.literal (.u64 1)) (.literal (.u64 2)) #[] .u64)
    ]
  }]
}

def createCrosscallModule : Module := {
  name := "BadCreateCrosscall"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.crosscallCreate (.literal (.u64 0)) "6000")
    ]
  }]
}

def create2CrosscallModule : Module := {
  name := "BadCreate2Crosscall"
  state := #[markerState]
  entrypoints := #[{
    name := "bad"
    returns := .u64
    body := #[
      .return (.crosscallCreate2 (.literal (.u64 0)) (.literal (.hash4 0 0 0 7)) "6000")
    ]
  }]
}

def indexedEventModule : Module := {
  name := "BadIndexedEvent"
  state := #[markerState]
  entrypoints := #[unitEntrypoint "bad" #[
    .effect (.eventEmitIndexed "Seen" #[("user", .literal (.u64 1))] #[("value", .literal (.u64 2))])
  ]]
}

def renderError? (module : Module) : Option String :=
  match ProofForge.Backend.Psy.IR.renderModule module with
  | .ok _ => none
  | .error err => some err.render

def cases : Array (String × Module × String) := #[
  (
    "invalid module identifier",
    invalidModuleIdentifierModule,
    "module name `Bad-Module` is not a valid Psy identifier; identifiers must start with an ASCII letter or `_` and contain only ASCII letters, digits, or `_`"
  ),
  (
    "empty state",
    emptyStateModule,
    "Psy IR v0 requires at least one state field because Dargo v0.1.0 rejects empty #[derive(Storage)] contracts; add a marker state field for stateless fixtures"
  ),
  (
    "duplicate state id",
    duplicateStateModule,
    "duplicate state id `count`"
  ),
  (
    "duplicate entrypoint name",
    duplicateEntrypointModule,
    "duplicate entrypoint name `bad`"
  ),
  (
    "reserved local identifier",
    reservedLocalIdentifierModule,
    "local name in entrypoint `bad` `let` is reserved in Psy"
  ),
  (
    "unit entrypoint parameter",
    unitParamModule,
    "entrypoint `bad` parameter `x` uses Unit; Psy IR v0 entrypoint parameters must use Felt, U32, Bool, Hash, Address, fixed arrays, or declared structs"
  ),
  (
    "zero-length ABI array parameter",
    zeroArrayParamModule,
    "entrypoint `bad` parameter `xs` uses a zero-length fixed array; Psy IR v0 fixed arrays must have non-zero length"
  ),
  (
    "unknown struct return type",
    unknownReturnStructModule,
    "entrypoint `bad` return type references unknown struct type `Missing`"
  ),
  (
    "unsupported map key/value shape",
    unsupportedMapModule,
    "map state `bad_map` has unsupported Psy IR v0 type Map<U64, U64>; only Map<Hash, Hash, N> is supported"
  ),
  (
    "unsupported unit array state",
    unsupportedUnitArrayStateModule,
    "array state `units` has unsupported Psy IR v0 element type `Unit`; only Felt, Bool, U32, Hash, and deriveStorage structs are supported"
  ),
  (
    "non-storage struct state",
    nonStorageStructStateModule,
    "state `current` uses struct `Point`, but the struct is not marked deriveStorage"
  ),
  (
    "empty struct declaration",
    emptyStructModule,
    "struct `Empty` must declare at least one field"
  ),
  (
    "invalid bounded loop range",
    invalidLoopModule,
    "bounded loop `_i` must have stop greater than start"
  ),
  (
    "storage write used as expression",
    storageWriteExprModule,
    "storage.scalar.write is a statement effect, not an expression"
  ),
  (
    "storage scalar assign_op used as expression",
    storageScalarAssignExprModule,
    "storage.scalar.assign_op is a statement effect, not an expression"
  ),
  (
    "storage path assign_op used as expression",
    storagePathAssignExprModule,
    "storage.path.assign_op is a statement effect, not an expression"
  ),
  (
    "storage read used as statement",
    storageReadStmtModule,
    "storage.scalar.read must be used as an expression"
  ),
  (
    "invalid assignment target",
    invalidAssignTargetModule,
    "assignment target must be a local, array index, or field path"
  ),
  (
    "empty storage path",
    emptyStoragePathModule,
    "storage path for state `person` must contain at least one segment"
  ),
  (
    "missing nested storage ref",
    missingRefStoragePathModule,
    "storage path field `profile` in struct `Person` must be marked ref to access nested storage"
  ),
  (
    "map storage path missing key",
    mapPathMissingKeyModule,
    "storage path state `balances` is map storage; first segment must be a map key"
  ),
  (
    "map storage path key type mismatch",
    mapPathKeyTypeMismatchModule,
    "map `balances` key expected `Hash`, got `U64`"
  ),
  (
    "unknown local",
    unknownLocalModule,
    "unknown local `missing`"
  ),
  (
    "let type mismatch",
    letTypeMismatchModule,
    "let binding `x` expected `U64`, got `Bool`"
  ),
  (
    "array element mismatch",
    arrayElementMismatchModule,
    "array literal element expected `U64`, got `Bool`"
  ),
  (
    "array length mismatch",
    arrayLengthMismatchModule,
    "let binding `xs` expected `Array<U64,2>`, got `Array<U64,1>`"
  ),
  (
    "struct literal field mismatch",
    structLiteralFieldMismatchModule,
    "struct literal `Pair` expected 2 field(s), got 1"
  ),
  (
    "hash preimage mismatch",
    hashPreimageMismatchModule,
    "hash preimage expected `Hash`, got `U64`"
  ),
  (
    "hash value part mismatch",
    hashValuePartMismatchModule,
    "hash value part 0 expected `U64`, got `U32`"
  ),
  (
    "immutable assignment",
    immutableAssignModule,
    "assignment target local `x` is not mutable"
  ),
  (
    "compound assignment type mismatch",
    compoundAssignTypeMismatchModule,
    "compound assignment addition right operand expected `U32`, got `U64`"
  ),
  (
    "immutable compound assignment",
    immutableCompoundAssignModule,
    "assignment target local `x` is not mutable"
  ),
  (
    "return type mismatch",
    returnTypeMismatchModule,
    "entrypoint `bad` return expected `U64`, got `Bool`"
  ),
  (
    "missing return",
    missingReturnModule,
    "entrypoint `bad` returns `U64` but does not end with a return statement"
  ),
  (
    "storage write type mismatch",
    storageWriteTypeMismatchModule,
    "scalar state `count` write expected `U64`, got `Bool`"
  ),
  (
    "storage scalar assign_op type mismatch",
    storageScalarAssignTypeMismatchModule,
    "compound assignment addition right operand expected `U64`, got `Bool`"
  ),
  (
    "equality type mismatch",
    equalityTypeMismatchModule,
    "equality right operand expected `U64`, got `Bool`"
  ),
  (
    "comparison type mismatch",
    comparisonTypeMismatchModule,
    "less-than left operand expected numeric `U32` or `U64`, got `Bool`"
  ),
  (
    "subtraction type mismatch",
    subtractionTypeMismatchModule,
    "subtraction left operand expected numeric `U32` or `U64`, got `Bool`"
  ),
  (
    "multiplication type mismatch",
    multiplicationTypeMismatchModule,
    "multiplication right operand expected `U64`, got `Bool`"
  ),
  (
    "division type mismatch",
    divisionTypeMismatchModule,
    "division right operand expected `U32`, got `U64`"
  ),
  (
    "unsupported cast",
    unsupportedCastModule,
    "cast from `U32` to `Hash` is not supported by Psy IR v0"
  ),
  (
    "bitwise type mismatch",
    bitwiseTypeMismatchModule,
    "bitwise and left operand expected numeric `U32` or `U64`, got `Bool`"
  ),
  (
    "shift type mismatch",
    shiftTypeMismatchModule,
    "shift-left right operand expected `U32`, got `U64`"
  ),
  (
    "boolean operator type mismatch",
    booleanOperatorTypeMismatchModule,
    "boolean and left operand expected `Bool`, got `U64`"
  ),
  (
    "if condition type mismatch",
    ifConditionTypeMismatchModule,
    "if condition expected `Bool`, got `U64`"
  ),
  (
    "branch local escape",
    branchLocalEscapeModule,
    "unknown local `x`"
  ),
  (
    "native value not supported",
    nativeValueExprModule,
    "native value inspection is not supported by Psy IR v0"
  ),
  (
    "typed crosscall unsupported",
    typedCrosscallModule,
    "typed crosscall return `Bool` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets"
  ),
  (
    "value-bearing typed crosscall unsupported",
    valueTypedCrosscallModule,
    "value-bearing typed crosscall return `U64` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets"
  ),
  (
    "static typed crosscall unsupported",
    staticTypedCrosscallModule,
    "static typed crosscall return `U64` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets"
  ),
  (
    "delegate typed crosscall unsupported",
    delegateTypedCrosscallModule,
    "delegate typed crosscall return `U64` is not supported by Psy IR v0; use untyped U64 crosscallInvoke for Psy targets"
  ),
  (
    "create crosscall unsupported",
    createCrosscallModule,
    "EVM contract creation is not supported by Psy IR v0"
  ),
  (
    "create2 crosscall unsupported",
    create2CrosscallModule,
    "EVM deterministic contract creation is not supported by Psy IR v0"
  ),
  (
    "indexed event unsupported",
    indexedEventModule,
    "event `Seen` uses indexed fields, which are not supported by Psy IR v0"
  )
]

def checkCase (name : String) (module : Module) (expected : String) : IO Bool := do
  match renderError? module with
  | some actual =>
      if actual == expected then
        IO.println s!"psy-diagnostics: ok: {name}"
        pure true
      else
        IO.eprintln s!"psy-diagnostics: FAILED: {name}"
        IO.eprintln s!"  expected: {expected}"
        IO.eprintln s!"  actual:   {actual}"
        pure false
  | none =>
      IO.eprintln s!"psy-diagnostics: FAILED: {name}"
      IO.eprintln "  expected an error, but Psy source generation succeeded"
      pure false

def main : IO UInt32 := do
  let mut failures : Nat := 0
  for (name, module, expected) in cases do
    let ok ← checkCase name module expected
    if !ok then
      failures := failures + 1
  if failures == 0 then
    IO.println s!"psy-diagnostics: {cases.size} cases passed"
    pure 0
  else
    IO.eprintln s!"psy-diagnostics: {failures} case(s) failed"
    pure 1

end ProofForge.Tests.PsyDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.PsyDiagnostics.main
