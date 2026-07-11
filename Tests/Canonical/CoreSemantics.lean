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
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def emptyState : LogicalState := { storage := fun _ => none }

def runEntry (contract : CheckedCanonicalContract) (f : FunctionId) (args : Array CoreValue) (state : LogicalState) : IO ExecutionResult :=
  expectOk "execute" <| execute defaultHostSemantics 100 contract f args state

def interfaceEntrypoint (function : Function) (mutatesState : Bool) : InterfaceEntrypoint := {
  functionId := function.id
  kind := "call"
  mutatesState := mutatesState
  params := function.params.map (·.type)
  retType := function.retType
}

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
    interface := { entrypoints := #[interfaceEntrypoint scalarIsolationFunction true] }
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
    interface := { entrypoints := #[interfaceEntrypoint wrappingAddFunction true] }
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
    interface := { entrypoints := #[interfaceEntrypoint checkedAddFunction true] }
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
      ⟨#[], .assert { id := ⟨1⟩, type := .bool } { id := ⟨1⟩ }⟩
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
    terminator := .revert { id := ⟨2⟩ }
  }]
}

def assertArgFunction : Function := {
  id := ⟨3⟩
  params := #[]
  retType := .unit
  entry := ⟨0⟩
  blocks := #[{
    id := ⟨0⟩
    instructions := #[
      ⟨#[⟨⟨1⟩, .u8⟩], .pure (.literal (.u8Lit 7))⟩,
      ⟨#[⟨⟨2⟩, .bool⟩], .pure (.literal (.boolLit false))⟩,
      ⟨#[], .assert { id := ⟨2⟩, type := .bool }
        { id := ⟨3⟩, args := #[{ id := ⟨1⟩, type := .u8 }] }⟩
    ]
    terminator := .return #[]
  }]
}

def errorContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := {
      name := "CoreSemantics"
      structs := #[]
      state := #[]
      events := #[]
      errors := #[
        { id := ⟨1⟩, namespace_ := "test", name := "Assertion", code := 1 },
        { id := ⟨2⟩, namespace_ := "test", name := "Revert", code := 2 },
        { id := ⟨3⟩, namespace_ := "test", name := "WithArg", code := 3, params := #[.u8] }
      ]
      functions := #[divZeroFunction, assertFailFunction, revertFunction, assertArgFunction]
    }
    interface := { entrypoints := #[
      interfaceEntrypoint divZeroFunction true,
      interfaceEntrypoint assertFailFunction true,
      interfaceEntrypoint revertFunction true,
      interfaceEntrypoint assertArgFunction true
    ] }
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
    interface := { entrypoints := #[interfaceEntrypoint mapIsolationFunction true] }
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
    interface := { entrypoints := #[
      interfaceEntrypoint arrayIsolationFunction true,
      interfaceEntrypoint arrayOutOfBoundsFunction true
    ] }
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
    interface := { entrypoints := #[interfaceEntrypoint branchFunction true] }
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
    interface := { entrypoints := #[interfaceEntrypoint loopFunction true] }
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
    interface := { entrypoints := #[interfaceEntrypoint unknownHostFunction true] }
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
    interface := { entrypoints := #[interfaceEntrypoint dominatingJumpFunction false] }
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
    interface := { entrypoints := #[interfaceEntrypoint wideningCastFunction false] }
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
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def wrongTypedHostSemantics : HostSemantics where
  handle _ _ state := .ok (.u8 9, state)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request _ := .error (.unsupportedCrosscall request.mode)

def traceInstructions : Array Instruction := #[
  ⟨#[], .emit ⟨20⟩ #[{ id := ⟨103⟩, type := .u64 }]⟩,
  ⟨#[⟨⟨104⟩, .u64⟩], .hostCall {
    id := traceHostId
    args := #[{ id := ⟨103⟩, type := .u64 }]
  }⟩,
  ⟨#[], .emit ⟨21⟩ #[{ id := ⟨104⟩, type := .u64 }]⟩
]

def unsupportedHashInstruction : Instruction :=
  ⟨#[⟨⟨105⟩, .hash⟩], .pure (.hash { id := ⟨103⟩, type := .hash })⟩

def unsupportedContextInstruction : Instruction :=
  ⟨#[⟨⟨106⟩, .address⟩], .contextRead .sender⟩

def unsupportedCrosscallInstruction : Instruction :=
  ⟨#[⟨⟨107⟩, .u64⟩], .crosscall {
    mode := .invoke
    target := { id := ⟨110⟩, type := .address }
    method := { id := ⟨111⟩, type := .string }
    paramTypes := #[]
    returnType := .u64
  } #[]⟩

def expectedCrosscallRequest : RuntimeCrosscallRequest := {
  mode := .invoke
  target := .address "remote"
  method := .string "transfer"
  gas := some (.u64 10)
  value := some (.u128 20)
  args := #[.u8 7]
  returnType := .u64
}

def crosscallHostSemantics : HostSemantics where
  handle _ _ state := .error (.unknownHostOp traceHostId)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall request state :=
    let mutated := setStateCell state ⟨999⟩ (.scalar (.u64 99))
    if request == expectedCrosscallRequest then .ok (some (.u64 123), mutated)
    else if request.returnType == .unit then .ok (none, mutated)
    else .error .typeMismatch

def successfulCrosscallInstruction : Instruction :=
  ⟨#[⟨⟨115⟩, .u64⟩], .crosscall {
    mode := .invoke
    target := { id := ⟨110⟩, type := .address }
    method := { id := ⟨111⟩, type := .string }
    gas := some { id := ⟨112⟩, type := .u64 }
    value := some { id := ⟨113⟩, type := .u128 }
    paramTypes := #[.u8]
    returnType := .u64
  } #[{ id := ⟨114⟩, type := .u8 }]⟩

def unitCrosscallInstruction : Instruction :=
  ⟨#[], .crosscall {
    mode := .staticInvoke
    target := { id := ⟨110⟩, type := .address }
    method := { id := ⟨111⟩, type := .string }
    paramTypes := #[]
    returnType := .unit
  } #[]⟩

def delegateCrosscallInstruction : Instruction :=
  ⟨#[], .crosscall {
    mode := .delegateInvoke
    target := { id := ⟨110⟩, type := .address }
    method := { id := ⟨111⟩, type := .string }
    paramTypes := #[]
    returnType := .unit
  } #[]⟩

def delegateCrosscallHostSemantics : HostSemantics where
  handle _ _ state := .error (.unknownHostOp traceHostId)
  handleContext field := .error (.unsupportedContext field)
  handleHash _ := .error .unsupportedHash
  handleCrosscall _ state :=
    let mutated := setStateCell state ⟨999⟩ (.scalar (.u64 99))
    .ok (none, { mutated with memory := #[] })

def nestedStorageModule : Module := {
  name := "NestedStorage"
  structs := #[{
    id := ⟨30⟩
    fields := #[{ id := ⟨0⟩, type := .fixedArray .u8 4 }]
  }]
  state := #[⟨⟨30⟩, .map .address (.structType ⟨30⟩) none⟩]
}

def orderedStructModule : Module := {
  name := "OrderedStruct"
  structs := [{
    id := ⟨31⟩
    fields := #[
      { id := ⟨0⟩, type := .u64 },
      { id := ⟨1⟩, type := .u8 }
    ]
  }]
}

def orderedStructValue : CoreValue :=
  .structValue ⟨31⟩ #[(⟨0⟩, .u64 7), (⟨1⟩, .u8 9)]

def reversedStructValue : CoreValue :=
  .structValue ⟨31⟩ #[(⟨1⟩, .u8 9), (⟨0⟩, .u64 7)]

def nestedStoragePath : StorageRef := {
  root := ⟨30⟩
  path := #[
    .mapKey { id := ⟨200⟩, type := .address },
    .field ⟨0⟩,
    .index { id := ⟨201⟩, type := .u64 }
  ]
  resultType := .u8
}

def hiddenFunction : Function := {
  id := ⟨50⟩
  params := #[]
  retType := .unit
  entry := ⟨500⟩
  blocks := #[{ id := ⟨500⟩, instructions := #[], terminator := .return #[] }]
}

def aggregateArgFunction : Function := {
  id := ⟨51⟩
  params := #[⟨⟨510⟩, .array .u64⟩]
  retType := .unit
  entry := ⟨510⟩
  blocks := #[{ id := ⟨510⟩, instructions := #[], terminator := .return #[] }]
}

def memoryLifecycleFunction : Function := {
  id := ⟨52⟩
  params := #[]
  retType := .unit
  entry := ⟨520⟩
  blocks := #[{
    id := ⟨520⟩
    instructions := #[
      ⟨#[⟨⟨5200⟩, .u64⟩], .pure (.literal (.u64Lit 1))⟩,
      ⟨#[⟨⟨5201⟩, .memoryRef .u64⟩], .memoryAlloc .u64
        { id := ⟨5200⟩, type := .u64 }⟩
    ]
    terminator := .return #[]
  }]
}

def memoryLifecycleContract : Except ProofForge.IR.Core.Error.ValidationError CheckedCanonicalContract :=
  validateCanonical {
    schemaVersion := 1
    module := { name := "MemoryLifecycle", functions := #[memoryLifecycleFunction] }
    interface := { entrypoints := #[interfaceEntrypoint memoryLifecycleFunction false] }
    materialization := {}
    requirements := #[]
  }

def aggregateLimitModule : Module := {
  name := "AggregateLimit"
  state := #[⟨⟨80⟩, .fixedArray (.array .unit) 2⟩]
}

def aggregateLimitPath (indexId : ValueId) : StorageRef := {
  root := ⟨80⟩
  path := #[.index { id := indexId, type := .u64 }]
  resultType := .array .unit
}

def resizeLimitModule : Module := {
  name := "ResizeLimit"
  state := #[⟨⟨81⟩, .dynamicArray (.array .unit)⟩]
}

def malformedStateModule : Module := {
  name := "MalformedState"
  structs := #[{ id := ⟨90⟩, fields := #[{ id := ⟨0⟩, type := .u64 }] }]
  state := #[
    ⟨⟨90⟩, .map .u64 .u64 (some 1)⟩,
    ⟨⟨91⟩, .fixedArray .u8 2⟩,
    ⟨⟨92⟩, .scalar .u64⟩,
    ⟨⟨93⟩, .record ⟨90⟩⟩
  ]
}

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
  expectError (.assertionFailure { id := ⟨1⟩, args := #[] }) <| execute defaultHostSemantics 100 errorContract ⟨1⟩ #[] emptyState
  expectError (.explicitRevert { id := ⟨2⟩, args := #[] }) <| execute defaultHostSemantics 100 errorContract ⟨2⟩ #[] emptyState
  expectError (.assertionFailure { id := ⟨3⟩, args := #[.u8 7] }) <|
    execute defaultHostSemantics 100 errorContract ⟨3⟩ #[] emptyState

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
    bindResults zeroBoundModule #[⟨⟨108⟩, .u64⟩] #[.u8 7] {}
  let wideningResult ← runEntry wideningCastContract ⟨13⟩ #[] emptyState
  require (wideningResult.returnValue == .u64 7 &&
      typeOfValue wideningResult.returnValue == .u64)
    "validated widening cast did not produce the declared runtime type"

  expectRuntimeError .typeMismatch <|
    execBlock defaultHostSemantics 1 { zeroBoundModule with functions := #[returnTypeMismatchFunction] }
      returnTypeMismatchFunction (Std.HashMap.ofList [(⟨102⟩, .u8 1)]) emptyState {} ⟨0⟩

  expectRuntimeError .unsupportedHash <|
    execInstruction defaultHostSemantics zeroBoundModule
      (Std.HashMap.ofList [(⟨103⟩, .hash "preimage")]) emptyState {} unsupportedHashInstruction
  expectRuntimeError (.unsupportedContext .sender) <|
    execInstruction defaultHostSemantics zeroBoundModule {} emptyState {} unsupportedContextInstruction
  expectRuntimeError (.unsupportedCrosscall .invoke) <|
    execInstruction defaultHostSemantics zeroBoundModule
      (Std.HashMap.ofList [(⟨110⟩, .address "remote"), (⟨111⟩, .string "method")])
      emptyState {} unsupportedCrosscallInstruction

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
  require (valueHasType orderedStructModule orderedStructValue (.structType ⟨31⟩))
    "declaration-ordered struct failed runtime type checking"
  require (!(valueHasType orderedStructModule reversedStructValue (.structType ⟨31⟩)))
    "field-reordered struct was accepted as a canonical runtime value"
  require (findMapValue? #[(orderedStructValue, .u64 1)] reversedStructValue).isNone
    "field-reordered struct aliased a canonical map key"
  require (orderedStructValue == orderedStructValue &&
      hash orderedStructValue == hash orderedStructValue)
    "CoreValue BEq and Hashable disagreed on a canonical struct value"

  let multibyte := String.ofList [Char.ofNat 0x4e2d]
  require (valueFootprint (.address multibyte) == multibyte.toUTF8.size)
    "address footprint did not count UTF-8 bytes"
  require (valueFootprint (.hash multibyte) == multibyte.toUTF8.size)
    "hash footprint did not count UTF-8 bytes"

  let checkedAnd ← expectOk "checked bitwise and" <|
    evalArithmetic .and .checked (.u8 3) (.u8 1)
  require (checkedAnd == .u8 1) "checked bitwise and reported overflow"
  let checkedShift ← expectOk "checked right shift" <|
    evalArithmetic .shr .checked (.u8 8) (.u8 1)
  require (checkedShift == .u8 4) "checked right shift reported overflow"
  expectRuntimeError .arithmeticOverflow <|
    evalArithmetic .shl .checked (.u8 128) (.u8 1)

  let (memoryState, memoryRef) ← expectOk "memory allocation" <|
    allocMemory zeroBoundModule emptyState .u64 (.u64 2)
  expectRuntimeError
      (.collectionLimitExceeded (maxLogicalCollectionLength + 1) maxLogicalCollectionLength) <|
    allocMemory zeroBoundModule emptyState .u64
      (.u64 (UInt64.ofNat (maxLogicalCollectionLength + 1)))
  let memoryState ← expectOk "memory store" <|
    storeMemory zeroBoundModule memoryState memoryRef (.u64 1) (.u64 9)
  let memoryValue ← expectOk "memory load" <|
    loadMemory zeroBoundModule memoryState memoryRef (.u64 1)
  require (memoryValue == .u64 9) "memory round-trip changed value"
  expectRuntimeError .typeMismatch <|
    loadMemory zeroBoundModule memoryState (.memRef .u8 0) (.u64 1)
  expectRuntimeError (.invalidMemoryRef 99) <|
    releaseMemory zeroBoundModule memoryState (.memRef .u64 99)
  let releasedState ← expectOk "memory release" <|
    releaseMemory zeroBoundModule memoryState memoryRef
  expectRuntimeError (.memoryAlreadyReleased 0) <|
    releaseMemory zeroBoundModule releasedState memoryRef
  expectRuntimeError (.memoryAlreadyReleased 0) <|
    loadMemory zeroBoundModule releasedState memoryRef (.u64 0)

  expectRuntimeError
      (.collectionLimitExceeded (maxLogicalCollectionLength + 1)
        maxLogicalCollectionLength) <|
    allocMemory zeroBoundModule emptyState
      (.fixedArray .unit maxLogicalCollectionLength) (.u64 2)

  let (aggregateMemory, aggregateMemoryRef) ← expectOk "aggregate memory allocation" <|
    allocMemory zeroBoundModule emptyState (.array .unit) (.u64 2)
  let halfEntries := Array.replicate (maxLogicalCollectionLength / 2 + 1) CoreValue.unit
  let largeArray := CoreValue.array .unit halfEntries
  let aggregateMemory ← expectOk "first aggregate memory store" <|
    storeMemory zeroBoundModule aggregateMemory aggregateMemoryRef (.u64 0) largeArray
  expectRuntimeError
      (.collectionLimitExceeded (maxLogicalCollectionLength + 1)
        maxLogicalCollectionLength) <|
    storeMemory zeroBoundModule aggregateMemory aggregateMemoryRef (.u64 1) largeArray

  let splitEnv := Std.HashMap.ofList [
    (⟨800⟩, .u64 0), (⟨801⟩, .u64 1)
  ]
  let splitState ← expectOk "first aggregate storage write" <|
    writePath aggregateLimitModule splitEnv emptyState (aggregateLimitPath ⟨800⟩) largeArray
  expectRuntimeError
      (.collectionLimitExceeded (maxLogicalCollectionLength + 1)
        maxLogicalCollectionLength) <|
    writePath aggregateLimitModule splitEnv splitState (aggregateLimitPath ⟨801⟩) largeArray

  let retainedEntries := Array.replicate maxLogicalCollectionLength CoreValue.unit
  let retainedState := setStateCell emptyState ⟨81⟩
    (.dynamicArray (.array .unit) #[.array .unit retainedEntries])
  expectRuntimeError
      (.collectionLimitExceeded (maxLogicalCollectionLength + 1)
        maxLogicalCollectionLength) <|
    storageResize resizeLimitModule retainedState ⟨81⟩ (.u64 2)

  let memoryLifecycleContract ← expectChecked "memory lifecycle validation"
    memoryLifecycleContract
  let seededMemoryState := {
    emptyState with memory := #[some (.u8, #[.u8 7])]
  }
  let memoryLifecycleResult ← expectOk "memory lifecycle execute" <|
    execute defaultHostSemantics 10 memoryLifecycleContract ⟨52⟩ #[] seededMemoryState
  require memoryLifecycleResult.finalState.memory.isEmpty
    "execute leaked caller or callee ephemeral memory"

  expectRuntimeError .invalidStorageShape <| getStateCell malformedStateModule {
    emptyState with storage := fun id =>
      if id == ⟨90⟩ then some (.map .u64 .u64 none #[]) else none
  } ⟨90⟩
  expectRuntimeError .invalidStorageShape <| getStateCell malformedStateModule {
    emptyState with storage := fun id =>
      if id == ⟨91⟩ then some (.fixedArray .u8 #[.u8 0]) else none
  } ⟨91⟩
  expectRuntimeError .typeMismatch <| getStateCell malformedStateModule {
    emptyState with storage := fun id =>
      if id == ⟨92⟩ then some (.scalar (.bool false)) else none
  } ⟨92⟩
  expectRuntimeError .invalidStorageShape <| getStateCell malformedStateModule {
    emptyState with storage := fun id =>
      if id == ⟨93⟩ then some (.record ⟨91⟩ (fun _ => none)) else none
  } ⟨93⟩

  let capacityOne : StorageCell := .map .u64 .u64 (some 1) #[]
  let capacityOne ← expectOk "first bounded map insert" <|
    capacityOne.writeMap (.u64 1) (.u64 10)
  let capacityOne ← expectOk "bounded map existing-key update" <|
    capacityOne.writeMap (.u64 1) (.u64 11)
  expectRuntimeError (.mapCapacityExceeded 1) <|
    capacityOne.writeMap (.u64 2) (.u64 20)

  let crosscallEnv := Std.HashMap.ofList [
    (⟨110⟩, .address "remote"), (⟨111⟩, .string "transfer"),
    (⟨112⟩, .u64 10), (⟨113⟩, .u128 20), (⟨114⟩, .u8 7)
  ]
  let (crosscallEnv, crosscallState, crosscallTrace) ← expectOk "successful crosscall" <|
    execInstruction crosscallHostSemantics zeroBoundModule crosscallEnv emptyState {}
      successfulCrosscallInstruction
  require (Std.HashMap.get? crosscallEnv ⟨115⟩ == some (.u64 123))
    "crosscall result did not match declared return type"
  require (crosscallTrace.effects == #[.crosscall expectedCrosscallRequest])
    "crosscall trace lost evaluated request fields"
  require ((crosscallState.storage ⟨999⟩).isNone)
    "invoke crosscall mutated caller logical storage"
  let unitEnv := Std.HashMap.ofList [
    (⟨110⟩, .address "remote"), (⟨111⟩, .string "ping")
  ]
  let (_, unitState, unitTrace) ← expectOk "unit crosscall" <|
    execInstruction crosscallHostSemantics zeroBoundModule unitEnv emptyState {}
      unitCrosscallInstruction
  require (unitTrace.effects.size == 1) "unit crosscall was not observable"
  require ((unitState.storage ⟨999⟩).isNone)
    "static crosscall mutated caller logical storage"
  let delegateInput := {
    emptyState with memory := #[some (.u8, #[.u8 7])]
  }
  let (_, delegateState, _) ← expectOk "delegate crosscall" <|
    execInstruction delegateCrosscallHostSemantics zeroBoundModule unitEnv delegateInput {}
      delegateCrosscallInstruction
  require ((delegateState.storage ⟨999⟩).isSome)
    "delegate crosscall discarded host storage changes"
  require (delegateState.memory == delegateInput.memory)
    "delegate crosscall replaced caller memory with host memory"

  let nestedEnv := Std.HashMap.ofList [
    (⟨200⟩, .address "owner"), (⟨201⟩, .u64 2)
  ]
  let nestedState ← expectOk "nested storage write" <|
    writePath nestedStorageModule nestedEnv emptyState nestedStoragePath (.u8 9)
  let nestedValue ← expectOk "nested storage read" <|
    readPath nestedStorageModule nestedEnv nestedState nestedStoragePath
  require (nestedValue == .u8 9) "nested map/record/array path changed value"

  let hiddenChecked ← expectChecked "hidden function contract" <| validateCanonical {
    schemaVersion := 1
    module := { name := "Hidden", functions := #[hiddenFunction] }
    interface := { entrypoints := #[] }
    materialization := {}
    requirements := #[]
  }
  expectError .missingFunction <|
    execute defaultHostSemantics 10 hiddenChecked ⟨50⟩ #[] emptyState

  let aggregateChecked ← expectChecked "aggregate argument contract" <| validateCanonical {
    schemaVersion := 1
    module := { name := "AggregateArg", functions := #[aggregateArgFunction] }
    interface := { entrypoints := #[interfaceEntrypoint aggregateArgFunction false] }
    materialization := {}
    requirements := #[]
  }
  expectError .argMismatch <| execute defaultHostSemantics 10 aggregateChecked ⟨51⟩
    #[.array .u64 #[.bool true]] emptyState

  let (_, _, orderedTrace) ← expectOk "ordered trace" <|
    execInstructions successfulHostSemantics zeroBoundModule
      (Std.HashMap.ofList [(⟨103⟩, .u64 7)]) emptyState {} traceInstructions
  require (orderedTrace.effects == #[
      .emit ⟨20⟩ #[.u64 7],
      .hostCall traceHostId #[.u64 7],
      .emit ⟨21⟩ #[.u64 9]
    ]) "emit/host effects lost their cross-kind order"

  IO.println "canonical-core-semantics: ok"
