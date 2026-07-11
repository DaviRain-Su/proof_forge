import ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.IR.Core.Validate
open ProofForge.IR.Canonical

def checkedAdd : InstructionOp :=
  .pure (.arithmetic .add .checked
    { id := ⟨40⟩, type := .u64 } { id := ⟨41⟩, type := .u64 })

def wrappingAdd : InstructionOp :=
  .pure (.arithmetic .add .wrapping
    { id := ⟨40⟩, type := .u64 } { id := ⟨41⟩, type := .u64 })

def recordType : Struct := {
  id := ⟨10⟩
  fields := #[
    { id := ⟨0⟩, type := .u64 },
    { id := ⟨1⟩, type := .fixedArray .u8 4 }
  ]
}

def transferEvent : Event := {
  id := ⟨0⟩
  fields := #[
    { id := ⟨0⟩, type := .address },
    { id := ⟨1⟩, type := .u8 }
  ]
}

def schemaError : ErrorDecl := {
  id := ⟨0⟩
  namespace_ := "schema"
  name := "AbsentValue"
  code := 1
  params := #[.u8]
}

def stateDecls : Array StateDecl := #[
  ⟨⟨0⟩, .scalar .u64⟩,
  ⟨⟨1⟩, .map .address (.structType ⟨10⟩) (some 100)⟩,
  ⟨⟨2⟩, .fixedArray .u8 32⟩,
  ⟨⟨3⟩, .dynamicArray .u32⟩,
  ⟨⟨4⟩, .record ⟨10⟩⟩,
  ⟨⟨5⟩, .fixedArray .u64 16⟩
]

def nestedStoragePath : StorageRef := {
  root := ⟨1⟩
  path := #[
    .mapKey { id := ⟨2⟩, type := .address },
    .field ⟨1⟩,
    .index { id := ⟨5⟩, type := .u64 }
  ]
  resultType := .u8
}

def mapPresencePath : StorageRef := {
  root := ⟨1⟩
  path := #[.mapKey { id := ⟨2⟩, type := .address }]
  resultType := .structType ⟨10⟩
}

def portableCall : CoreCrosscallSpec := {
  mode := .invoke
  target := { id := ⟨0⟩, type := .address }
  method := { id := ⟨1⟩, type := .string }
  gas := some { id := ⟨3⟩, type := .u64 }
  value := some { id := ⟨4⟩, type := .u128 }
  paramTypes := #[.u8]
  returnType := .u64
}

def entryBlock : Block := {
  id := ⟨0⟩
  instructions := #[
    ⟨#[⟨⟨10⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
    ⟨#[⟨⟨11⟩, .u8⟩], .storageLoad nestedStoragePath⟩,
    ⟨#[⟨⟨12⟩, .bool⟩], .storageContains mapPresencePath⟩,
    ⟨#[], .emit ⟨0⟩ #[
      { id := ⟨2⟩, type := .address }, { id := ⟨11⟩, type := .u8 }
    ]⟩,
    ⟨#[], .assert { id := ⟨12⟩, type := .bool }
      { id := ⟨0⟩, args := #[{ id := ⟨11⟩, type := .u8 }] }⟩,
    ⟨#[⟨⟨13⟩, .u64⟩], .crosscall portableCall #[
      { id := ⟨11⟩, type := .u8 }
    ]⟩
  ]
  terminator := .jump ⟨1⟩ #[{ id := ⟨10⟩, type := .u64 }]
}

def loopHeader : Block := {
  id := ⟨1⟩
  params := #[⟨⟨20⟩, .u64⟩]
  instructions := #[
    ⟨#[⟨⟨21⟩, .u64⟩], .pure (.literal (.u64Lit 3))⟩,
    ⟨#[⟨⟨22⟩, .bool⟩], .pure (.compare .lt
      { id := ⟨20⟩, type := .u64 } { id := ⟨21⟩, type := .u64 })⟩
  ]
  terminator := .branch { id := ⟨22⟩, type := .bool } ⟨2⟩ ⟨3⟩
}

def loopBody : Block := {
  id := ⟨2⟩
  instructions := #[
    ⟨#[⟨⟨23⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
    ⟨#[⟨⟨24⟩, .u64⟩], .pure (.arithmetic .add .wrapping
      { id := ⟨20⟩, type := .u64 } { id := ⟨23⟩, type := .u64 })⟩
  ]
  terminator := .jump ⟨1⟩ #[{ id := ⟨24⟩, type := .u64 }] (some (.atMost 3))
}

def exitBlock : Block := {
  id := ⟨3⟩
  instructions := #[]
  terminator := .return #[{ id := ⟨13⟩, type := .u64 }]
}

def exampleFunction : Function := {
  id := ⟨0⟩
  params := #[
    ⟨⟨0⟩, .address⟩, ⟨⟨1⟩, .string⟩, ⟨⟨2⟩, .address⟩,
    ⟨⟨3⟩, .u64⟩, ⟨⟨4⟩, .u128⟩, ⟨⟨5⟩, .u64⟩
  ]
  retType := .u64
  blocks := #[entryBlock, loopHeader, loopBody, exitBlock]
  entry := ⟨0⟩
}

def exampleModule : Module := {
  name := "CoreSchema"
  structs := #[recordType]
  state := stateDecls
  functions := #[exampleFunction]
  events := #[transferEvent]
  errors := #[schemaError]
}

def contractOf (m : Module) : CanonicalContract := {
  schemaVersion := 0
  module := m
  interface := { entrypoints := m.functions.map (fun f => {
    functionId := f.id, kind := "function", mutatesState := true,
    params := f.params.map (·.type), retType := f.retType
  }) }
  materialization := {}
  requirements := #[]
}

def literalOverflowModule : Module := {
  name := "LiteralOverflow"
  functions := #[{
    id := ⟨1⟩, params := #[], retType := .u8, entry := ⟨100⟩
    blocks := #[{
      id := ⟨100⟩
      instructions := #[⟨#[⟨⟨100⟩, .u8⟩], .pure (.literal (.u8Lit 256))⟩]
      terminator := .return #[{ id := ⟨100⟩, type := .u8 }]
    }]
  }]
}

def crossWidthLiteralModule : Module := {
  name := "CrossWidthLiteral"
  functions := #[{
    id := ⟨11⟩
    params := #[]
    retType := .u8
    entry := ⟨1100⟩
    blocks := #[{
      id := ⟨1100⟩
      instructions := #[⟨#[⟨⟨1100⟩, .u8⟩], .pure (.literal (.u128Lit 1))⟩]
      terminator := .return #[{ id := ⟨1100⟩, type := .u8 }]
    }]
  }]
}

def duplicateFieldModule : Module := {
  name := "DuplicateField"
  structs := #[{ id := ⟨11⟩, fields := #[
    { id := ⟨0⟩, type := .u8 }, { id := ⟨0⟩, type := .u64 }
  ] }]
}

def duplicateEventFieldModule : Module := {
  name := "DuplicateEventField"
  events := #[{
    id := ⟨10⟩
    fields := #[{ id := ⟨0⟩, type := .u8 }, { id := ⟨0⟩, type := .u64 }]
  }]
}

def recursiveStructModule : Module := {
  name := "RecursiveStruct"
  structs := #[{
    id := ⟨20⟩
    fields := #[{ id := ⟨0⟩, type := .structType ⟨20⟩, ownership := .value }]
  }]
}

def referenceOwnershipModule : Module := {
  name := "ReferenceOwnership"
  structs := #[{
    id := ⟨21⟩
    fields := #[{ id := ⟨0⟩, type := .u64, ownership := .reference }]
  }]
}

def linearRecordModule : Module := {
  name := "LinearRecord"
  structs := #[{ id := ⟨22⟩, fields := #[], semantics := .linearRecord }]
}

def badErrorArgsModule : Module := {
  name := "BadErrorArgs"
  errors := #[{
    id := ⟨5⟩, namespace_ := "schema", name := "NeedsU8", code := 5, params := #[.u8]
  }]
  functions := #[{
    id := ⟨5⟩
    params := #[⟨⟨500⟩, .bool⟩]
    retType := .unit
    entry := ⟨500⟩
    blocks := #[{
      id := ⟨500⟩
      instructions := #[⟨#[], .assert { id := ⟨500⟩, type := .bool } { id := ⟨5⟩ }⟩]
      terminator := .return #[]
    }]
  }]
}

def nonCycleBoundModule : Module := {
  name := "NonCycleBound"
  functions := #[{
    id := ⟨6⟩
    params := #[]
    retType := .unit
    entry := ⟨600⟩
    blocks := #[
      { id := ⟨600⟩, instructions := #[],
        terminator := .jump ⟨601⟩ #[] (some (.atMost 1)) },
      { id := ⟨601⟩, instructions := #[], terminator := .return #[] }
    ]
  }]
}

def ephemeralStateModule : Module := {
  name := "EphemeralState"
  state := #[⟨⟨60⟩, .scalar (.memoryRef .u64)⟩]
}

def oversizedCollectionModule : Module := {
  name := "OversizedCollection"
  state := #[⟨⟨61⟩, .fixedArray .u8 (maxLogicalCollectionLength + 1)⟩]
}

def oversizedNestedCollectionModule : Module := {
  name := "OversizedNestedCollection"
  state := #[⟨⟨62⟩,
    .fixedArray (.fixedArray .u8 maxLogicalCollectionLength) 2⟩]
}

def oversizedDynamicElementModule : Module := {
  name := "OversizedDynamicElement"
  state := #[⟨⟨63⟩,
    .dynamicArray (.fixedArray (.fixedArray .u8 maxLogicalCollectionLength) 2)⟩]
}

def oversizedMapFootprintModule : Module := {
  name := "OversizedMapFootprint"
  state := #[⟨⟨64⟩, .map .u64 .u64 (some maxLogicalCollectionLength)⟩]
}

def oversizedBytesLiteralModule : Module := {
  name := "OversizedBytesLiteral"
  functions := #[{
    id := ⟨12⟩
    params := #[]
    retType := .bytes
    entry := ⟨1200⟩
    blocks := #[{
      id := ⟨1200⟩
      instructions := #[⟨#[⟨⟨1201⟩, .bytes⟩], .pure (.literal (.bytesLit
        (ByteArray.mk (Array.replicate (maxLogicalCollectionLength + 1) 0))))⟩]
      terminator := .return #[{ id := ⟨1201⟩, type := .bytes }]
    }]
  }]
}

def oversizedStringLiteralModule : Module := {
  name := "OversizedStringLiteral"
  functions := #[{
    id := ⟨13⟩
    params := #[]
    retType := .string
    entry := ⟨1300⟩
    blocks := #[{
      id := ⟨1300⟩
      instructions := #[⟨#[⟨⟨1301⟩, .string⟩], .pure (.literal (.stringLit
        (String.ofList (List.replicate (maxLogicalCollectionLength + 1) 'a'))))⟩]
      terminator := .return #[{ id := ⟨1301⟩, type := .string }]
    }]
  }]
}

def oversizedMultibyteText : String :=
  String.ofList (List.replicate (maxLogicalCollectionLength / 3 + 1)
    (Char.ofNat 0x4e2d))

def oversizedAddressLiteralModule : Module := {
  name := "OversizedAddressLiteral"
  functions := #[{
    id := ⟨14⟩
    params := #[]
    retType := .address
    entry := ⟨1400⟩
    blocks := #[{
      id := ⟨1400⟩
      instructions := #[⟨#[⟨⟨1401⟩, .address⟩],
        .pure (.literal (.addressLit oversizedMultibyteText))⟩]
      terminator := .return #[{ id := ⟨1401⟩, type := .address }]
    }]
  }]
}

def oversizedHashLiteralModule : Module := {
  name := "OversizedHashLiteral"
  functions := #[{
    id := ⟨15⟩
    params := #[]
    retType := .hash
    entry := ⟨1500⟩
    blocks := #[{
      id := ⟨1500⟩
      instructions := #[⟨#[⟨⟨1501⟩, .hash⟩],
        .pure (.literal (.hashLit oversizedMultibyteText))⟩]
      terminator := .return #[{ id := ⟨1501⟩, type := .hash }]
    }]
  }]
}

def aggregateCrosscallModule : Module := {
  name := "AggregateCrosscall"
  structs := #[{
    id := ⟨80⟩
    fields := #[{ id := ⟨0⟩, type := .u64 }]
  }]
  functions := #[{
    id := ⟨11⟩
    params := #[
      ⟨⟨1100⟩, .address⟩,
      ⟨⟨1101⟩, .string⟩,
      ⟨⟨1102⟩, .structType ⟨80⟩⟩
    ]
    retType := .fixedArray (.structType ⟨80⟩) 2
    entry := ⟨1100⟩
    blocks := #[{
      id := ⟨1100⟩
      instructions := #[⟨#[⟨⟨1103⟩, .fixedArray (.structType ⟨80⟩) 2⟩], .crosscall {
        mode := .invoke
        target := { id := ⟨1100⟩, type := .address }
        method := { id := ⟨1101⟩, type := .string }
        paramTypes := #[.structType ⟨80⟩]
        returnType := .fixedArray (.structType ⟨80⟩) 2
      } #[{ id := ⟨1102⟩, type := .structType ⟨80⟩ }]⟩]
      terminator := .return #[{
        id := ⟨1103⟩
        type := .fixedArray (.structType ⟨80⟩) 2
      }]
    }]
  }]
}

def ordinaryArrayAsMemoryModule : Module := {
  name := "OrdinaryArrayAsMemory"
  functions := #[{
    id := ⟨7⟩
    params := #[⟨⟨700⟩, .array .u64⟩, ⟨⟨701⟩, .u64⟩]
    retType := .u64
    entry := ⟨700⟩
    blocks := #[{
      id := ⟨700⟩
      instructions := #[⟨#[⟨⟨702⟩, .u64⟩], .memoryLoad
        { id := ⟨700⟩, type := .array .u64 }
        { id := ⟨701⟩, type := .u64 }⟩]
      terminator := .return #[{ id := ⟨702⟩, type := .u64 }]
    }]
  }]
}

def invalidCastModule : Module := {
  name := "InvalidCast"
  functions := #[{
    id := ⟨8⟩
    params := #[⟨⟨800⟩, .u64⟩]
    retType := .array .u64
    entry := ⟨800⟩
    blocks := #[{
      id := ⟨800⟩
      instructions := #[⟨#[⟨⟨801⟩, .array .u64⟩], .pure (.cast (.array .u64)
        { id := ⟨800⟩, type := .u64 })⟩]
      terminator := .return #[{ id := ⟨801⟩, type := .array .u64 }]
    }]
  }]
}

def invalidCompareModule : Module := {
  name := "InvalidCompare"
  functions := #[{
    id := ⟨9⟩
    params := #[⟨⟨900⟩, .array .u64⟩, ⟨⟨901⟩, .array .u64⟩]
    retType := .bool
    entry := ⟨900⟩
    blocks := #[{
      id := ⟨900⟩
      instructions := #[⟨#[⟨⟨902⟩, .bool⟩], .pure (.compare .eq
        { id := ⟨900⟩, type := .array .u64 }
        { id := ⟨901⟩, type := .array .u64 })⟩]
      terminator := .return #[{ id := ⟨902⟩, type := .bool }]
    }]
  }]
}

def scalarLengthModule : Module := {
  name := "ScalarLength"
  state := #[⟨⟨70⟩, .scalar .u64⟩]
  functions := #[{
    id := ⟨10⟩
    params := #[]
    retType := .u64
    entry := ⟨1000⟩
    blocks := #[{
      id := ⟨1000⟩
      instructions := #[⟨#[⟨⟨1001⟩, .u64⟩], .storageLength ⟨70⟩⟩]
      terminator := .return #[{ id := ⟨1001⟩, type := .u64 }]
    }]
  }]
}

def unknownErrorModule : Module := {
  name := "UnknownError"
  functions := #[{
    id := ⟨2⟩
    params := #[]
    retType := .unit
    entry := ⟨200⟩
    blocks := #[{
      id := ⟨200⟩
      instructions := #[]
      terminator := .revert { id := ⟨99⟩, args := #[] }
    }]
  }]
}

def badCrosscallModule : Module := {
  name := "BadCrosscall"
  functions := #[{
    id := ⟨3⟩
    params := #[⟨⟨300⟩, .u64⟩, ⟨⟨301⟩, .string⟩]
    retType := .u64
    entry := ⟨300⟩
    blocks := #[{
      id := ⟨300⟩
      instructions := #[⟨#[⟨⟨302⟩, .u64⟩], .crosscall {
        mode := .invoke
        target := { id := ⟨300⟩, type := .u64 }
        method := { id := ⟨301⟩, type := .string }
        paramTypes := #[]
        returnType := .u64
      } #[]⟩]
      terminator := .return #[{ id := ⟨302⟩, type := .u64 }]
    }]
  }]
}

def expectValid (m : Module) : IO Unit :=
  match validateCanonical (contractOf m) with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"expected valid module, got {repr e}"

def expectInvalid (tag : ValidationErrorTag) (m : Module) : IO Unit :=
  match validateCanonical (contractOf m) with
  | .error e => unless e.tag == tag do
      throw <| IO.userError s!"{m.name}: expected {repr tag}, got {repr e}"
  | .ok _ => throw <| IO.userError s!"{m.name}: expected {repr tag}, validation succeeded"

def main : IO Unit := do
  if checkedAdd == wrappingAdd then
    throw <| IO.userError "checked and wrapping arithmetic must differ"
  expectValid exampleModule
  expectInvalid .literalOutOfRange literalOverflowModule
  expectInvalid .typeMismatch crossWidthLiteralModule
  expectInvalid .duplicateId duplicateFieldModule
  expectInvalid .duplicateId duplicateEventFieldModule
  expectInvalid .typeMismatch recursiveStructModule
  expectInvalid .typeMismatch referenceOwnershipModule
  expectInvalid .typeMismatch linearRecordModule
  expectInvalid .unknownReference unknownErrorModule
  expectInvalid .typeMismatch badErrorArgsModule
  expectInvalid .typeMismatch badCrosscallModule
  expectInvalid .typeMismatch nonCycleBoundModule
  expectInvalid .typeMismatch ephemeralStateModule
  expectInvalid .typeMismatch oversizedCollectionModule
  expectInvalid .typeMismatch oversizedNestedCollectionModule
  expectInvalid .typeMismatch oversizedDynamicElementModule
  expectInvalid .typeMismatch oversizedMapFootprintModule
  expectInvalid .literalOutOfRange oversizedBytesLiteralModule
  expectInvalid .literalOutOfRange oversizedStringLiteralModule
  expectInvalid .literalOutOfRange oversizedAddressLiteralModule
  expectInvalid .literalOutOfRange oversizedHashLiteralModule
  expectValid aggregateCrosscallModule
  expectInvalid .typeMismatch ordinaryArrayAsMemoryModule
  expectInvalid .typeMismatch invalidCastModule
  expectInvalid .typeMismatch invalidCompareModule
  expectInvalid .invalidStoragePath scalarLengthModule
  IO.println "CoreSchema OK: checked canonical schema and negative matrix"
