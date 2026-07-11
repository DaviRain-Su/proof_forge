import ProofForge.IR.Core
import ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.IR.Canonical

/- Base valid canonical contract. All negative variants mutate this. -/

def baseModule : Module := {
  name := "CoreValidate"
  structs := #[⟨⟨10⟩, #[⟨⟨20⟩, .u64⟩]⟩]
  state := #[
    ⟨⟨0⟩, .scalar .u64⟩,
    ⟨⟨1⟩, .map .address .u128 (some 100)⟩,
    ⟨⟨2⟩, .fixedArray .u8 32⟩,
    ⟨⟨3⟩, .dynamicArray .u32⟩,
    ⟨⟨4⟩, .record ⟨10⟩⟩
  ]
  events := #[⟨⟨5⟩, #[⟨⟨30⟩, .u64⟩]⟩]
  functions := #[{
    id := ⟨0⟩
    params := #[⟨⟨0⟩, .u64⟩]
    retType := .u64
    entry := ⟨0⟩
    blocks := #[
      {
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨1⟩, .u64⟩], .pure (.arithmetic .add .checked
            { id := ⟨0⟩, type := .u64 }
            { id := ⟨0⟩, type := .u64 })⟩
        ]
        terminator := .return #[{ id := ⟨1⟩, type := .u64 }]
      }
    ]
  }]
}

def baseInterface : InterfaceContract := {
  entrypoints := #[⟨⟨0⟩, "call", true⟩]
}

def baseMaterialization : MaterializationContract := {
  constructorBindings := #[⟨⟨0⟩, .u64Lit 0⟩]
}

def baseContract : CanonicalContract := {
  schemaVersion := 1
  module := baseModule
  interface := baseInterface
  materialization := baseMaterialization
  requirements := #[]
}

def expectError (tag : ValidationErrorTag) (c : CanonicalContract) : IO Unit := do
  match validateCanonical c with
  | .ok _ => throw <| IO.userError s!"expected error tag {repr tag}, but validation succeeded"
  | .error e =>
    unless e.tag == tag do
      throw <| IO.userError
        s!"expected error tag {repr tag}, got {repr e.tag}: {e.reason}"

/- Duplicate state ID. -/

def duplicateIdContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    state := #[
      ⟨⟨0⟩, .scalar .u64⟩,
      ⟨⟨0⟩, .scalar .u32⟩
    ]
  }
}

/- Unknown storage root. -/

def unknownReferenceContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
          ⟨#[], .storageStore {
            root := ⟨99⟩
            path := #[]
            resultType := .u64
          } { id := ⟨0⟩, type := .u64 }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

/- Literal 256 stored into u8 result. -/

def literalOutOfRangeContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .u8
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨1⟩, .u8⟩], .pure (.literal (.u32Lit 256))⟩
        ]
        terminator := .return #[{ id := ⟨1⟩, type := .u8 }]
      }]
    }]
  }
}

/- Use value ⟨2⟩ before it is defined. -/

def invalidDominanceContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .u64
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨1⟩, .u64⟩], .pure (.unary .neg { id := ⟨2⟩, type := .u64 })⟩
        ]
        terminator := .return #[{ id := ⟨1⟩, type := .u64 }]
      }]
    }]
  }
}

/- Arithmetic on bool operands. -/

def typeMismatchContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .bool⟩]
      retType := .bool
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨2⟩, .bool⟩], .pure (.arithmetic .add .checked
            { id := ⟨0⟩, type := .bool }
            { id := ⟨0⟩, type := .bool })⟩
        ]
        terminator := .return #[{ id := ⟨2⟩, type := .bool }]
      }]
    }]
  }
}

/- Map key on scalar state. -/

def invalidStoragePathScalarContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .address⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
          ⟨#[], .storageStore {
            root := ⟨0⟩
            path := #[.mapKey { id := ⟨0⟩, type := .address }]
            resultType := .u64
          } { id := ⟨1⟩, type := .u64 }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

/- Array index with non-integer type. -/

def invalidStoragePathIndexContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .address⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨1⟩, .u8⟩], .pure (.literal (.u8Lit 0))⟩,
          ⟨#[], .storageStore {
            root := ⟨2⟩
            path := #[.index { id := ⟨0⟩, type := .address }]
            resultType := .u8
          } { id := ⟨1⟩, type := .u8 }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

/- Back edge without a LoopBound. -/

def missingLoopBoundContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .jump ⟨1⟩ #[] none
        },
        {
          id := ⟨1⟩
          params := #[]
          instructions := #[]
          terminator := .jump ⟨0⟩ #[] none
        }
      ]
    }]
  }
}

/- Return arity/type mismatch. -/

def invalidReturnContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .u64
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨0⟩, .bool⟩], .pure (.literal (.boolLit true))⟩
        ]
        terminator := .return #[{ id := ⟨0⟩, type := .bool }]
      }]
    }]
  }
}

/- Interface references unknown function. -/

def invalidInterfaceContract : CanonicalContract := {
  baseContract with
  interface := {
    entrypoints := #[⟨⟨99⟩, "call", true⟩]
  }
}

/- Constructor binding references unknown state. -/

def invalidMaterializationContract : CanonicalContract := {
  baseContract with
  materialization := {
    constructorBindings := #[⟨⟨99⟩, .u64Lit 0⟩]
  }
}

/- Duplicate block ID inside one function. -/

def duplicateBlockIdContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .u64⟩]
      retType := .u64
      entry := ⟨0⟩
      blocks := #[
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
        },
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
        }
      ]
    }]
  }
}

/- Duplicate value ID (parameter and instruction result share ⟨0⟩). -/

def duplicateValueIdContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .u64⟩]
      retType := .u64
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩
        ]
        terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
      }]
    }]
  }
}

/- Interface entrypoint references an unknown function. -/

def unknownFunctionRefContract : CanonicalContract := {
  baseContract with
  interface := {
    entrypoints := #[⟨⟨99⟩, "call", true⟩]
  }
}

/- Emit references an unknown event ID. -/

def unknownEventRefContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[⟨#[], .emit ⟨99⟩ #[]⟩]
        terminator := .return #[]
      }]
    }]
  }
}

/- Storage path traverses a record whose struct type is not declared. -/

def unknownStructRefContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    state := baseModule.state ++ #[⟨⟨6⟩, .record ⟨99⟩⟩]
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .u64⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[], .storageStore {
            root := ⟨6⟩
            path := #[.field ⟨0⟩]
            resultType := .u64
          } { id := ⟨0⟩, type := .u64 }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

def main : IO Unit := do
  expectError .duplicateId duplicateIdContract
  expectError .unknownReference unknownReferenceContract
  expectError .literalOutOfRange literalOutOfRangeContract
  expectError .invalidDominance invalidDominanceContract
  expectError .typeMismatch typeMismatchContract
  expectError .invalidStoragePath invalidStoragePathScalarContract
  expectError .invalidStoragePath invalidStoragePathIndexContract
  expectError .missingLoopBound missingLoopBoundContract
  expectError .invalidReturn invalidReturnContract
  expectError .invalidInterface invalidInterfaceContract
  expectError .invalidMaterialization invalidMaterializationContract
  expectError .duplicateId duplicateBlockIdContract
  expectError .duplicateId duplicateValueIdContract
  expectError .invalidInterface unknownFunctionRefContract
  expectError .unknownReference unknownEventRefContract
  expectError .unknownReference unknownStructRefContract
  IO.println "canonical-core-validate: ok"
