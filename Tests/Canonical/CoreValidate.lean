import ProofForge.IR.Core
import ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Error
open ProofForge.IR.Canonical

/- Base valid canonical contract. All negative variants mutate this. -/

def baseModule : Module := {
  name := "CoreValidate"
  structs := #[{ id := ⟨10⟩, fields := #[{ id := ⟨20⟩, type := .u64 }] }]
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
  entrypoints := #[{
    functionId := ⟨0⟩, kind := "call", mutatesState := true,
    params := #[.u64], retType := .u64
  }]
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

def expectErrorPass (tag : ValidationErrorTag) (pass : String)
    (c : CanonicalContract) : IO Unit := do
  match validateCanonical c with
  | .ok _ =>
    throw <| IO.userError
      s!"expected error tag {repr tag} in pass {pass}, but validation succeeded"
  | .error e =>
    unless e.tag == tag && e.pass == pass do
      throw <| IO.userError
        s!"expected error tag {repr tag} in pass {pass}, got {repr e.tag} in {e.pass}: {e.reason}"

def expectErrorContext (tag : ValidationErrorTag) (pass : String)
    (function : Option FunctionId) (block : Option BlockId)
    (instruction : Option Nat) (c : CanonicalContract) : IO Unit := do
  match validateCanonical c with
  | .ok _ =>
    throw <| IO.userError
      s!"expected located error tag {repr tag} in pass {pass}, but validation succeeded"
  | .error e =>
    unless e.tag == tag && e.pass == pass && e.function == function &&
        e.block == block && e.instruction == instruction do
      throw <| IO.userError
        s!"unexpected error context: {repr e}"

def expectOk (name : String) (c : CanonicalContract) : IO Unit := do
  match validateCanonical c with
  | .ok _ => pure ()
  | .error e =>
    throw <| IO.userError
      s!"expected {name} to validate, got {repr e.tag} in {e.pass}: {e.reason}"

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
          ⟨#[⟨⟨1⟩, .u8⟩], .pure (.literal (.u8Lit 256))⟩
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
    entrypoints := #[{
      functionId := ⟨99⟩, kind := "call", mutatesState := true,
      params := #[], retType := .unit
    }]
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
    entrypoints := #[{
      functionId := ⟨99⟩, kind := "call", mutatesState := true,
      params := #[], retType := .unit
    }]
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

/- A use-site type is not authoritative: it must match the defining value. -/

def forgedValueRefTypeContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .u64⟩]
      retType := .bool
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[]
        terminator := .return #[{ id := ⟨0⟩, type := .bool }]
      }]
    }]
  }
}

/- A value defined in the left sibling does not dominate the right sibling. -/

def siblingNonDominatingUseContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .bool⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .branch { id := ⟨0⟩, type := .bool } ⟨1⟩ ⟨2⟩
        },
        {
          id := ⟨1⟩
          params := #[]
          instructions := #[
            ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩
          ]
          terminator := .return #[]
        },
        {
          id := ⟨2⟩
          params := #[]
          instructions := #[
            ⟨#[⟨⟨2⟩, .u64⟩], .pure (.unary .neg { id := ⟨1⟩, type := .u64 })⟩
          ]
          terminator := .return #[]
        }
      ]
    }]
  }
}

/- A forged jump argument cannot adopt the target block parameter's type. -/

def forgedBlockArgumentContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .u64⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .jump ⟨1⟩ #[{ id := ⟨0⟩, type := .bool }] none
        },
        {
          id := ⟨1⟩
          params := #[⟨⟨1⟩, .bool⟩]
          instructions := #[]
          terminator := .return #[]
        }
      ]
    }]
  }
}

/- Acyclicity is a CFG property, independent of block serialization order. -/

def reorderedAcyclicContract : CanonicalContract := {
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
          id := ⟨2⟩
          params := #[]
          instructions := #[]
          terminator := .return #[]
        },
        {
          id := ⟨1⟩
          params := #[]
          instructions := #[]
          terminator := .jump ⟨2⟩ #[] none
        }
      ]
    }]
  }
}

/- Record declarations must resolve even when no instruction traverses them. -/

def unusedUnknownRecordContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    state := baseModule.state ++ #[⟨⟨6⟩, .record ⟨99⟩⟩]
  }
}

/- A map key with the wrong declared type is an invalid storage path. -/

def wrongMapKeyTypeContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .u64⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨1⟩, .u128⟩], .pure (.literal (.u128Lit 0))⟩,
          ⟨#[], .storageStore {
            root := ⟨1⟩
            path := #[.mapKey { id := ⟨0⟩, type := .u64 }]
            resultType := .u128
          } { id := ⟨1⟩, type := .u128 }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

/- Unit-returning functions cannot return a value. -/

def wrongReturnArityContract : CanonicalContract := {
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
          ⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩
        ]
        terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
      }]
    }]
  }
}

/- Every function completes CFG validation before any dominance validation. -/

def modulePassOrderContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    errors := #[{
      id := ⟨0⟩, namespace_ := "test", name := "Failure", code := 1
    }]
    functions := #[
      {
        id := ⟨0⟩
        params := #[]
        retType := .unit
        entry := ⟨0⟩
        blocks := #[{
          id := ⟨0⟩
          params := #[]
          instructions := #[
            ⟨#[], .assert { id := ⟨99⟩, type := .bool } { id := ⟨0⟩ }⟩
          ]
          terminator := .return #[]
        }]
      },
      {
        id := ⟨1⟩
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
      }
    ]
  }
}

/- HostOp reference validation is pass 7, after terminator pass 6. -/

def hostOpAfterTerminatorContract : CanonicalContract := {
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
          ⟨#[⟨⟨0⟩, .u64⟩], .hostCall {
            id := ⟨"", "bad", ⟨1, 0, 0⟩⟩
            args := #[]
          }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

def invalidHostOpContract : CanonicalContract := {
  hostOpAfterTerminatorContract with
  module := {
    hostOpAfterTerminatorContract.module with
    functions := #[{
      id := ⟨0⟩
      params := #[]
      retType := .u64
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[
          ⟨#[⟨⟨0⟩, .u64⟩], .hostCall {
            id := ⟨"", "bad", ⟨1, 0, 0⟩⟩
            args := #[]
          }⟩
        ]
        terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
      }]
    }]
  }
}

/- Entry block parameters have no incoming edge and therefore no runtime
binding. Function inputs are represented by `Function.params`. -/

def entryBlockParameterContract : CanonicalContract := {
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
        params := #[⟨⟨0⟩, .u64⟩]
        instructions := #[]
        terminator := .return #[{ id := ⟨0⟩, type := .u64 }]
      }]
    }]
  }
}

/- `branch` has no edge arguments, so neither branch target may declare block
parameters. Such parameters would be accepted by dominance but remain unbound
at execution time. -/

def branchTargetParameterContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .bool⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .branch { id := ⟨0⟩, type := .bool } ⟨1⟩ ⟨2⟩
        },
        {
          id := ⟨1⟩
          params := #[⟨⟨1⟩, .u64⟩]
          instructions := #[]
          terminator := .return #[]
        },
        {
          id := ⟨2⟩
          params := #[]
          instructions := #[]
          terminator := .return #[]
        }
      ]
    }]
  }
}

/- Aggregate roots cannot be loaded as scalar `.unit` values. A storage path
must select a concrete scalar leaf before a load/store. -/

def incompleteAggregatePathContract : CanonicalContract := {
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
          ⟨#[⟨⟨0⟩, .unit⟩], .storageLoad {
            root := ⟨1⟩
            path := #[]
            resultType := .unit
          }⟩
        ]
        terminator := .return #[]
      }]
    }]
  }
}

/- Every `CoreType.structType` occurrence must resolve, including function
signatures that never otherwise touch storage. -/

def unknownFunctionTypeContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .structType ⟨99⟩⟩]
      retType := .unit
      entry := ⟨0⟩
      blocks := #[{
        id := ⟨0⟩
        params := #[]
        instructions := #[]
        terminator := .return #[]
      }]
    }]
  }
}

/- A join block parameter is valid when every predecessor supplies it through a
`jump`; values defined in either sibling are not used directly at the join. -/

def validDiamondContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .bool⟩]
      retType := .u64
      entry := ⟨0⟩
      blocks := #[
        {
          id := ⟨0⟩
          params := #[]
          instructions := #[]
          terminator := .branch { id := ⟨0⟩, type := .bool } ⟨1⟩ ⟨2⟩
        },
        {
          id := ⟨1⟩
          params := #[]
          instructions := #[⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩]
          terminator := .jump ⟨3⟩ #[{ id := ⟨1⟩, type := .u64 }] none
        },
        {
          id := ⟨2⟩
          params := #[]
          instructions := #[⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 2))⟩]
          terminator := .jump ⟨3⟩ #[{ id := ⟨2⟩, type := .u64 }] none
        },
        {
          id := ⟨3⟩
          params := #[⟨⟨3⟩, .u64⟩]
          instructions := #[]
          terminator := .return #[{ id := ⟨3⟩, type := .u64 }]
        }
      ]
    }]
  }
}

/- A real bounded loop remains valid after the unbounded-cycle check removes
its annotated backedge. -/

def validBoundedLoopContract : CanonicalContract := {
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
          instructions := #[⟨#[⟨⟨0⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩]
          terminator := .jump ⟨1⟩ #[{ id := ⟨0⟩, type := .u64 }] none
        },
        {
          id := ⟨1⟩
          params := #[⟨⟨1⟩, .u64⟩]
          instructions := #[⟨#[⟨⟨2⟩, .bool⟩], .pure (.literal (.boolLit true))⟩]
          terminator := .branch { id := ⟨2⟩, type := .bool } ⟨2⟩ ⟨3⟩
        },
        {
          id := ⟨2⟩
          params := #[]
          instructions := #[
            ⟨#[⟨⟨3⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
            ⟨#[⟨⟨4⟩, .u64⟩], .pure (.arithmetic .add .wrapping
              { id := ⟨1⟩, type := .u64 }
              { id := ⟨3⟩, type := .u64 })⟩
          ]
          terminator := .jump ⟨1⟩ #[{ id := ⟨4⟩, type := .u64 }] (some (.atMost 3))
        },
        {
          id := ⟨3⟩
          params := #[]
          instructions := #[]
          terminator := .return #[]
        }
      ]
    }]
  }
}

/- A bounded edge elsewhere in the same SCC cannot hide a distinct unbounded
sub-cycle. -/

def mixedBoundedUnboundedCycleContract : CanonicalContract := {
  baseContract with
  module := {
    baseModule with
    functions := #[{
      id := ⟨0⟩
      params := #[⟨⟨0⟩, .bool⟩]
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
          terminator := .branch { id := ⟨0⟩, type := .bool } ⟨2⟩ ⟨3⟩
        },
        {
          id := ⟨2⟩
          params := #[]
          instructions := #[]
          terminator := .jump ⟨1⟩ #[] (some (.atMost 1))
        },
        {
          id := ⟨3⟩
          params := #[]
          instructions := #[]
          terminator := .jump ⟨1⟩ #[] none
        }
      ]
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
  expectErrorContext .duplicateId "symbol-uniqueness" (some ⟨0⟩) (some ⟨0⟩) none
    duplicateBlockIdContract
  expectErrorContext .duplicateId "symbol-uniqueness" (some ⟨0⟩) (some ⟨0⟩) (some 0)
    duplicateValueIdContract
  expectError .invalidInterface unknownFunctionRefContract
  expectError .unknownReference unknownEventRefContract
  expectError .unknownReference unknownStructRefContract
  expectError .typeMismatch forgedValueRefTypeContract
  expectError .invalidDominance siblingNonDominatingUseContract
  expectError .typeMismatch forgedBlockArgumentContract
  expectOk "reordered acyclic CFG" reorderedAcyclicContract
  expectError .unknownReference unusedUnknownRecordContract
  expectError .invalidStoragePath wrongMapKeyTypeContract
  expectError .invalidReturn wrongReturnArityContract
  expectErrorPass .missingLoopBound "cfg" modulePassOrderContract
  expectErrorPass .invalidReturn "terminator" hostOpAfterTerminatorContract
  expectErrorPass .unknownReference "capability-hostop" invalidHostOpContract
  expectErrorPass .typeMismatch "cfg" entryBlockParameterContract
  expectErrorPass .typeMismatch "terminator" branchTargetParameterContract
  expectErrorPass .invalidStoragePath "state-shape" incompleteAggregatePathContract
  expectErrorPass .unknownReference "state-shape" unknownFunctionTypeContract
  expectOk "diamond with jump-provided join parameter" validDiamondContract
  expectOk "bounded loop" validBoundedLoopContract
  expectErrorPass .missingLoopBound "cfg" mixedBoundedUnboundedCycleContract
  IO.println "canonical-core-validate: ok"
