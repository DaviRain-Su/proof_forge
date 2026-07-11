import ProofForge.IR.Core
import ProofForge.IR.Core.Semantics
import ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics
open ProofForge.IR.Canonical

/--
error: invalid {...} notation, constructor for `CheckedCanonicalContract` is marked as private
-/
#guard_msgs in
def forgedCheckedContract : CheckedCanonicalContract := { contract := default }

/--
error: invalid {...} notation, constructor for `CheckedCanonicalContract` is marked as private
-/
#guard_msgs in
def mutatedCheckedContract (checked : CheckedCanonicalContract) : CheckedCanonicalContract :=
  { checked with contract := default }

/--
error: failed to synthesize
  Inhabited CheckedCanonicalContract

Hint: Additional diagnostic information may be available using the `set_option diagnostics true` command.
-/
#guard_msgs in
#synth Inhabited CheckedCanonicalContract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def expectOk {α : Type} (message : String) (r : Except RuntimeError α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{message}: {repr e}"

def expectRuntimeError {α : Type} (tag : RuntimeError)
    (r : Except RuntimeError α) : IO Unit :=
  match r with
  | .ok _ => throw <| IO.userError s!"expected error {repr tag}, but execution succeeded"
  | .error e =>
    unless e == tag do
      throw <| IO.userError s!"expected error {repr tag}, got {repr e}"

def expectChecked (message : String)
    (r : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract) :
    IO CheckedCanonicalContract :=
  match r with
  | .ok contract => pure contract
  | .error e => throw <| IO.userError s!"{message}: {repr e}"

def expectError (tag : RuntimeError) (r : Except RuntimeError ExecutionResult) : IO Unit :=
  match r with
  | .ok _ => throw <| IO.userError s!"expected error {repr tag}, but execution succeeded"
  | .error e =>
    unless e == tag do
      throw <| IO.userError s!"expected error {repr tag}, got {repr e}"

def defaultHostSemantics : HostSemantics where
  handle _ _ _ := .error (.unknownHostOp { namespace_ := "test", name := "unknown", version := { major := 1, minor := 0, patch := 0 } })
  handleContext field _ := .error (.unsupportedContext field)
  handleHash _ _ := .error .unsupportedHash
  handleCrosscall spec _ _ := .error (.unsupportedCrosscall spec.family)

def emptyState : LogicalState := { storage := fun _ => none }

def runEntry (contract : CheckedCanonicalContract) (f : FunctionId) (args : Array CoreValue) (state : LogicalState) : IO ExecutionResult :=
  expectOk "execute" <| execute defaultHostSemantics 100 contract f args state

/- Two logical scalar states remain isolated. -/

def scalarIsolationFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 7))⟩,
      ⟨#[], .storageStore { root := ⟨0⟩, path := #[], resultType := .u64 } { id := ⟨1⟩, type := .u64 }⟩,
      ⟨#[⟨⟨2⟩, .u64⟩], .storageLoad { root := ⟨1⟩, path := #[], resultType := .u64 }⟩
    ]
    terminator := .return #[{ id := ⟨2⟩, type := .u64 }]
  }]
}

def scalarIsolationContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := {
      name := "CoreSemantics"
      structs := #[]
      state := #[⟨⟨0⟩, .scalar .u64⟩, ⟨⟨1⟩, .scalar .u64⟩]
      events := #[]
      functions := #[scalarIsolationFunction]
    }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Wrapping u8 255 + 1 returns zero. -/

def wrappingAddFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u8
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u8⟩], .pure (.literal (.u8Lit 255))⟩,
      ⟨#[⟨⟨2⟩, .u8⟩], .pure (.literal (.u8Lit 1))⟩,
      ⟨#[⟨⟨3⟩, .u8⟩], .pure (.arithmetic .add .wrapping { id := ⟨1⟩, type := .u8 } { id := ⟨2⟩, type := .u8 })⟩
    ]
    terminator := .return #[{ id := ⟨3⟩, type := .u8 }]
  }]
}

def wrappingAddContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[wrappingAddFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Checked u8 255 + 1 returns overflow error. -/

def checkedAddFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u8
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u8⟩], .pure (.literal (.u8Lit 255))⟩,
      ⟨#[⟨⟨2⟩, .u8⟩], .pure (.literal (.u8Lit 1))⟩,
      ⟨#[⟨⟨3⟩, .u8⟩], .pure (.arithmetic .add .checked { id := ⟨1⟩, type := .u8 } { id := ⟨2⟩, type := .u8 })⟩
    ]
    terminator := .return #[{ id := ⟨3⟩, type := .u8 }]
  }]
}

def checkedAddContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[checkedAddFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Divide by zero, failed assert, and explicit revert have distinct errors. -/

def divZeroFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
      ⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
      ⟨#[⟨⟨3⟩, .u64⟩], .pure (.arithmetic .div .checked { id := ⟨1⟩, type := .u64 } { id := ⟨2⟩, type := .u64 })⟩
    ]
    terminator := .return #[{ id := ⟨3⟩, type := .u64 }]
  }]
}

def assertFailFunction : Function := {
  id := ⟨1⟩
  params := #[]
  retType := .unit
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .bool⟩], .pure (.literal (.boolLit false))⟩,
      ⟨#[], .assert { id := ⟨1⟩, type := .bool } { namespace_ := "test", code := 1 }⟩
    ]
    terminator := .return #[]
  }]
}

def revertFunction : Function := {
  id := ⟨2⟩
  params := #[]
  retType := .unit
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[]
    terminator := .revert { namespace_ := "test", code := 2 }
  }]
}

def errorContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[divZeroFunction, assertFailFunction, revertFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩, ⟨⟨1⟩, "call", true⟩, ⟨⟨2⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Map keys and array indices remain isolated. -/

def mapIsolationFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
      ⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 2))⟩,
      ⟨#[⟨⟨3⟩, .u64⟩], .pure (.literal (.u64Lit 100))⟩,
      ⟨#[⟨⟨4⟩, .u64⟩], .pure (.literal (.u64Lit 200))⟩,
      ⟨#[], .storageStore { root := ⟨2⟩, path := #[.mapKey { id := ⟨1⟩, type := .u64 }], resultType := .u64 } { id := ⟨3⟩, type := .u64 }⟩,
      ⟨#[], .storageStore { root := ⟨2⟩, path := #[.mapKey { id := ⟨2⟩, type := .u64 }], resultType := .u64 } { id := ⟨4⟩, type := .u64 }⟩,
      ⟨#[⟨⟨5⟩, .u64⟩], .storageLoad { root := ⟨2⟩, path := #[.mapKey { id := ⟨1⟩, type := .u64 }], resultType := .u64 }⟩
    ]
    terminator := .return #[{ id := ⟨5⟩, type := .u64 }]
  }]
}

def mapIsolationContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[⟨⟨2⟩, .map .u64 .u64 (some 10)⟩], events := #[], functions := #[mapIsolationFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Array index isolation and out-of-bounds. -/

def arrayIsolationFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
      ⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
      ⟨#[⟨⟨3⟩, .u64⟩], .pure (.literal (.u64Lit 100))⟩,
      ⟨#[⟨⟨4⟩, .u64⟩], .pure (.literal (.u64Lit 200))⟩,
      ⟨#[], .storageStore { root := ⟨3⟩, path := #[.index { id := ⟨1⟩, type := .u64 }], resultType := .u64 } { id := ⟨3⟩, type := .u64 }⟩,
      ⟨#[], .storageStore { root := ⟨3⟩, path := #[.index { id := ⟨2⟩, type := .u64 }], resultType := .u64 } { id := ⟨4⟩, type := .u64 }⟩,
      ⟨#[⟨⟨5⟩, .u64⟩], .storageLoad { root := ⟨3⟩, path := #[.index { id := ⟨1⟩, type := .u64 }], resultType := .u64 }⟩
    ]
    terminator := .return #[{ id := ⟨5⟩, type := .u64 }]
  }]
}

def arrayOutOfBoundsFunction : Function := {
  id := ⟨1⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 10))⟩,
      ⟨#[⟨⟨2⟩, .u64⟩], .storageLoad { root := ⟨3⟩, path := #[.index { id := ⟨1⟩, type := .u64 }], resultType := .u64 }⟩
    ]
    terminator := .return #[{ id := ⟨2⟩, type := .u64 }]
  }]
}

def arrayContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[⟨⟨3⟩, .fixedArray .u64 4⟩], events := #[], functions := #[arrayIsolationFunction, arrayOutOfBoundsFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩, ⟨⟨1⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Branch and block arguments select the correct return. -/

def branchFunction : Function := {
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
      instructions := #[⟨#[⟨⟨1⟩, .u64⟩], .pure (.literal (.u64Lit 42))⟩]
      terminator := .jump ⟨3⟩ #[{ id := ⟨1⟩, type := .u64 }] none
    },
    {
      id := ⟨2⟩
      params := #[]
      instructions := #[⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 99))⟩]
      terminator := .jump ⟨3⟩ #[{ id := ⟨2⟩, type := .u64 }] none
    },
    {
      id := ⟨3⟩
      params := #[⟨⟨3⟩, .u64⟩]
      instructions := #[]
      terminator := .return #[{ id := ⟨3⟩, type := .u64 }]
    }
  ]
}

def branchContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[branchFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Bounded loop consumes the declared number of iterations. -/

def loopFunction : Function := {
  id := ⟨0⟩
  params := #[⟨⟨0⟩, .u64⟩]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[
    {
      id := ⟨0⟩
      params := #[]
      instructions := #[
        ⟨#[], .storageStore { root := ⟨4⟩, path := #[], resultType := .u64 } { id := ⟨0⟩, type := .u64 }⟩
      ]
      terminator := .jump ⟨1⟩ #[] none
    },
    {
      id := ⟨1⟩
      params := #[]
      instructions := #[
        ⟨#[⟨⟨1⟩, .u64⟩], .storageLoad { root := ⟨4⟩, path := #[], resultType := .u64 }⟩,
        ⟨#[⟨⟨2⟩, .u64⟩], .pure (.literal (.u64Lit 0))⟩,
        ⟨#[⟨⟨3⟩, .bool⟩], .pure (.compare .gt { id := ⟨1⟩, type := .u64 } { id := ⟨2⟩, type := .u64 })⟩
      ]
      terminator := .branch { id := ⟨3⟩, type := .bool } ⟨2⟩ ⟨3⟩
    },
    {
      id := ⟨2⟩
      params := #[]
      instructions := #[
        ⟨#[⟨⟨4⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
        ⟨#[⟨⟨5⟩, .u64⟩], .storageLoad { root := ⟨4⟩, path := #[], resultType := .u64 }⟩,
        ⟨#[⟨⟨6⟩, .u64⟩], .pure (.arithmetic .sub .wrapping { id := ⟨5⟩, type := .u64 } { id := ⟨4⟩, type := .u64 })⟩,
        ⟨#[], .storageStore { root := ⟨4⟩, path := #[], resultType := .u64 } { id := ⟨6⟩, type := .u64 }⟩
      ]
      terminator := .jump ⟨1⟩ #[] (some (.atMost 5))
    },
    {
      id := ⟨3⟩
      params := #[]
      instructions := #[
        ⟨#[⟨⟨7⟩, .u64⟩], .storageLoad { root := ⟨4⟩, path := #[], resultType := .u64 }⟩
      ]
      terminator := .return #[{ id := ⟨7⟩, type := .u64 }]
    }
  ]
}

def loopContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[⟨⟨4⟩, .scalar .u64⟩], events := #[], functions := #[loopFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Missing HostSemantics binding fails instead of returning a default. -/

def unknownHostFunction : Function := {
  id := ⟨0⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨1⟩, .u64⟩], .hostCall {
        id := { namespace_ := "test", name := "unknown", version := { major := 1, minor := 0, patch := 0 } },
        args := #[]
      }⟩
    ]
    terminator := .return #[{ id := ⟨1⟩, type := .u64 }]
  }]
}

def hostContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[unknownHostFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

/- Values defined in a dominating block survive a jump with no block params. -/

def dominatingJumpFunction : Function := {
  id := ⟨10⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[
    {
      id := ⟨0⟩
      params := #[]
      instructions := #[
        ⟨#[⟨⟨100⟩, .u64⟩], .pure (.literal (.u64Lit 42))⟩
      ]
      terminator := .jump ⟨1⟩ #[] none
    },
    {
      id := ⟨1⟩
      params := #[]
      instructions := #[]
      terminator := .return #[{ id := ⟨100⟩, type := .u64 }]
    }
  ]
}

def dominatingJumpContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := {
      name := "DominatingJump"
      structs := #[]
      state := #[]
      events := #[]
      functions := #[dominatingJumpFunction]
    }
    interface := { entrypoints := #[⟨⟨10⟩, "call", false⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

def wideningCastFunction : Function := {
  id := ⟨13⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[
      ⟨#[⟨⟨110⟩, .u8⟩], .pure (.literal (.u8Lit 7))⟩,
      ⟨#[⟨⟨111⟩, .u64⟩], .pure (.cast .u64 { id := ⟨110⟩, type := .u8 })⟩
    ]
    terminator := .return #[{ id := ⟨111⟩, type := .u64 }]
  }]
}

def wideningCastContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := {
      name := "WideningCast"
      structs := #[]
      state := #[]
      events := #[]
      functions := #[wideningCastFunction]
    }
    interface := { entrypoints := #[⟨⟨13⟩, "call", false⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  }

def zeroBoundHostId : HostOpId := {
  namespace_ := "test"
  name := "must-not-run"
  version := { major := 1, minor := 0, patch := 0 }
}

def zeroBoundFunction : Function := {
  id := ⟨11⟩
  params := #[]
  retType := .unit
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[⟨#[⟨⟨101⟩, .u64⟩], .hostCall { id := zeroBoundHostId, args := #[] }⟩]
    terminator := .jump ⟨0⟩ #[] (some (.atMost 0))
  }]
}

def zeroBoundModule : Module := {
  name := "ZeroBound"
  structs := #[]
  state := #[]
  events := #[]
  functions := #[zeroBoundFunction]
}

def returnTypeMismatchFunction : Function := {
  id := ⟨12⟩
  params := #[]
  retType := .u64
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    params := #[]
    instructions := #[]
    terminator := .return #[{ id := ⟨102⟩, type := .u8 }]
  }]
}

def traceHostId : HostOpId := {
  namespace_ := "test"
  name := "trace"
  version := { major := 1, minor := 0, patch := 0 }
}

def successfulHostSemantics : HostSemantics where
  handle _ _ state := .ok (.u64 9, state)
  handleContext field _ := .error (.unsupportedContext field)
  handleHash _ _ := .error .unsupportedHash
  handleCrosscall spec _ _ := .error (.unsupportedCrosscall spec.family)

def wrongTypedHostSemantics : HostSemantics where
  handle _ _ state := .ok (.u8 9, state)
  handleContext field _ := .error (.unsupportedContext field)
  handleHash _ _ := .error .unsupportedHash
  handleCrosscall spec _ _ := .error (.unsupportedCrosscall spec.family)

def traceInstructions : Array Instruction := #[
  ⟨#[], .emit ⟨20⟩ #[{ id := ⟨103⟩, type := .u64 }]⟩,
  ⟨#[⟨⟨104⟩, .u64⟩], .hostCall {
    id := traceHostId
    args := #[{ id := ⟨103⟩, type := .u64 }]
  }⟩,
  ⟨#[], .emit ⟨21⟩ #[{ id := ⟨104⟩, type := .u64 }]⟩
]

def unsupportedHashInstruction : Instruction :=
  ⟨#[⟨⟨105⟩, .hash⟩], .pure (.hash { id := ⟨103⟩, type := .u64 })⟩

def unsupportedContextInstruction : Instruction :=
  ⟨#[⟨⟨106⟩, .address⟩], .contextRead .sender⟩

def unsupportedCrosscallInstruction : Instruction :=
  ⟨#[⟨⟨107⟩, .u64⟩], .crosscall {
    family := "remote"
    gas := none
    value := none
  } #[]⟩

def main : IO Unit := do
  let scalarIsolationContract ← expectChecked "scalar isolation validation" scalarIsolationContract
  let wrappingAddContract ← expectChecked "wrapping add validation" wrappingAddContract
  let checkedAddContract ← expectChecked "checked add validation" checkedAddContract
  let errorContract ← expectChecked "error contract validation" errorContract
  let mapIsolationContract ← expectChecked "map isolation validation" mapIsolationContract
  let arrayContract ← expectChecked "array validation" arrayContract
  let branchContract ← expectChecked "branch validation" branchContract
  let loopContract ← expectChecked "loop validation" loopContract
  let hostContract ← expectChecked "host validation" hostContract
  let dominatingJumpContract ← expectChecked "dominating jump validation" dominatingJumpContract
  let wideningCastContract ← expectChecked "widening cast validation" wideningCastContract

  let r1 ← runEntry scalarIsolationContract ⟨0⟩ #[] emptyState
  require (r1.returnValue == .u64 0) "scalar isolation: expected 0"

  let r2 ← runEntry wrappingAddContract ⟨0⟩ #[] emptyState
  require (r2.returnValue == .u8 0) "wrapping add: expected 0"

  expectError (.arithmeticOverflow) <| execute defaultHostSemantics 100 checkedAddContract ⟨0⟩ #[] emptyState

  expectError .divisionByZero <| execute defaultHostSemantics 100 errorContract ⟨0⟩ #[] emptyState
  expectError (.assertionFailure { namespace_ := "test", code := 1 }) <| execute defaultHostSemantics 100 errorContract ⟨1⟩ #[] emptyState
  expectError (.explicitRevert { namespace_ := "test", code := 2 }) <| execute defaultHostSemantics 100 errorContract ⟨2⟩ #[] emptyState

  let r3 ← runEntry mapIsolationContract ⟨0⟩ #[] emptyState
  require (r3.returnValue == .u64 100) "map isolation: expected 100"

  let r4 ← runEntry arrayContract ⟨0⟩ #[] emptyState
  require (r4.returnValue == .u64 100) "array isolation: expected 100"

  expectError .arrayOutOfBounds <| execute defaultHostSemantics 100 arrayContract ⟨1⟩ #[] emptyState

  let r5 ← runEntry branchContract ⟨0⟩ #[.bool true] emptyState
  require (r5.returnValue == .u64 42) "branch true: expected 42"
  let r6 ← runEntry branchContract ⟨0⟩ #[.bool false] emptyState
  require (r6.returnValue == .u64 99) "branch false: expected 99"

  let r7 ← runEntry loopContract ⟨0⟩ #[.u64 5] emptyState
  require (r7.returnValue == .u64 0) "bounded loop: expected 0"

  expectError (.unknownHostOp { namespace_ := "test", name := "unknown", version := { major := 1, minor := 0, patch := 0 } }) <|
    execute defaultHostSemantics 100 hostContract ⟨0⟩ #[] emptyState

  let r8 ← runEntry dominatingJumpContract ⟨10⟩ #[] emptyState
  require (r8.returnValue == .u64 42) "jump discarded a dominating value"

  expectRuntimeError (.loopBoundExceeded ⟨0⟩) <|
    execBlock defaultHostSemantics 10 zeroBoundModule zeroBoundFunction {} emptyState {} ⟨0⟩

  expectRuntimeError .typeMismatch <|
    bindResults #[⟨⟨108⟩, .u64⟩] #[.u8 7] {}
  let wideningResult ← runEntry wideningCastContract ⟨13⟩ #[] emptyState
  require (wideningResult.returnValue == .u64 7 &&
      typeOfValue wideningResult.returnValue == .u64)
    "validated widening cast did not produce the declared runtime type"

  expectRuntimeError .typeMismatch <|
    execBlock defaultHostSemantics 1 { zeroBoundModule with functions := #[returnTypeMismatchFunction] }
      returnTypeMismatchFunction (Std.HashMap.ofList [(⟨102⟩, .u8 1)]) emptyState {} ⟨0⟩

  expectRuntimeError .unsupportedHash <|
    execInstruction defaultHostSemantics zeroBoundModule
      (Std.HashMap.ofList [(⟨103⟩, .u64 7)]) emptyState {} unsupportedHashInstruction
  expectRuntimeError (.unsupportedContext .sender) <|
    execInstruction defaultHostSemantics zeroBoundModule {} emptyState {} unsupportedContextInstruction
  expectRuntimeError (.unsupportedCrosscall "remote") <|
    execInstruction defaultHostSemantics zeroBoundModule {} emptyState {} unsupportedCrosscallInstruction

  expectRuntimeError .typeMismatch <|
    execInstruction wrongTypedHostSemantics zeroBoundModule {} emptyState {} {
      results := #[⟨⟨109⟩, .u64⟩]
      op := .hostCall { id := traceHostId, args := #[] }
    }

  match ← expectOk "dynamic array write" <|
      StorageCell.writeArray 0 (.u64 9) (.dynamicArray .u64 #[.u64 0]) with
  | .dynamicArray .u64 values =>
    require (values == #[.u64 9]) "dynamic array write returned wrong contents"
  | _ => throw <| IO.userError "dynamic array write changed the storage shape"

  require (typeOfValue (typeDefault (.fixedArray .u64 2)) == .fixedArray .u64 2)
    "fixed-array default lost its declared shape"
  require (typeOfValue (typeDefault (.array .u64)) == .array .u64)
    "dynamic-array default lost its declared shape"
  require (typeOfValue (typeDefault (.structType ⟨30⟩)) == .structType ⟨30⟩)
    "struct default lost its declared shape"

  let (_, _, orderedTrace) ← expectOk "ordered trace" <|
    execInstructions successfulHostSemantics zeroBoundModule
      (Std.HashMap.ofList [(⟨103⟩, .u64 7)]) emptyState {} traceInstructions
  require (orderedTrace.effects == #[
      .emit ⟨20⟩ #[.u64 7],
      .hostCall traceHostId #[.u64 7],
      .emit ⟨21⟩ #[.u64 9]
    ]) "emit/host effects lost their cross-kind order"

  IO.println "canonical-core-semantics: ok"
