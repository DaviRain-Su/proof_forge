import ProofForge.IR.Core
import ProofForge.IR.Core.Semantics
import ProofForge.IR.Canonical

open ProofForge.IR.Core
open ProofForge.IR.Core.Semantics
open ProofForge.IR.Canonical

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def expectOk {α : Type} (message : String) (r : Except RuntimeError α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{message}: {repr e}"

def expectError (tag : RuntimeError) (r : Except RuntimeError ExecutionResult) : IO Unit :=
  match r with
  | .ok _ => throw <| IO.userError s!"expected error {repr tag}, but execution succeeded"
  | .error e =>
    unless e == tag do
      throw <| IO.userError s!"expected error {repr tag}, got {repr e}"

def defaultHostSemantics : HostSemantics where
  handle _ _ _ := .error (.unknownHostOp { namespace_ := "test", name := "unknown", version := { major := 1, minor := 0, patch := 0 } })

def emptyState : LogicalState := { storage := {} }

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

def scalarIsolationContract : CheckedCanonicalContract :=
  match validateCanonical {
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
  } with
  | .ok c => c
  | .error e => panic! s!"scalar isolation contract failed: {repr e}"

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

def wrappingAddContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[wrappingAddFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"wrapping add contract failed: {repr e}"

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

def checkedAddContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[checkedAddFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"checked add contract failed: {repr e}"

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

def errorContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[divZeroFunction, assertFailFunction, revertFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩, ⟨⟨1⟩, "call", true⟩, ⟨⟨2⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"error contract failed: {repr e}"

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

def mapIsolationContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[⟨⟨2⟩, .map .u64 .u64 (some 10)⟩], events := #[], functions := #[mapIsolationFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"map isolation contract failed: {repr e}"

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

def arrayContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[⟨⟨3⟩, .fixedArray .u64 4⟩], events := #[], functions := #[arrayIsolationFunction, arrayOutOfBoundsFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩, ⟨⟨1⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"array contract failed: {repr e}"

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

def branchContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[branchFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"branch contract failed: {repr e}"

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

def loopContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[⟨⟨4⟩, .scalar .u64⟩], events := #[], functions := #[loopFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"loop contract failed: {repr e}"

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

def hostContract : CheckedCanonicalContract :=
  match validateCanonical {
    schemaVersion := 1
    module := { name := "CoreSemantics", structs := #[], state := #[], events := #[], functions := #[unknownHostFunction] }
    interface := { entrypoints := #[⟨⟨0⟩, "call", true⟩] }
    materialization := { constructorBindings := #[] }
    requirements := #[]
  } with
  | .ok c => c
  | .error e => panic! s!"host contract failed: {repr e}"

def main : IO Unit := do
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

  IO.println "canonical-core-semantics: ok"
