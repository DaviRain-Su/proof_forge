import ProofForge.IR.Core

open ProofForge.IR.Core

/- Six distinct logical state declarations covering all canonical state shapes. -/

def scalarState : StateDecl := ⟨⟨0⟩, .scalar .u64⟩
def mapState : StateDecl := ⟨⟨1⟩, .map .address .u128 (some 100)⟩
def fixedArrayState : StateDecl := ⟨⟨2⟩, .fixedArray .u8 32⟩
def dynamicArrayState : StateDecl := ⟨⟨3⟩, .dynamicArray .u32⟩
def recordState : StateDecl := ⟨⟨4⟩, .record ⟨10⟩⟩
def queueBackingState : StateDecl := ⟨⟨5⟩, .fixedArray .u64 16⟩

def stateDecls : Array StateDecl := #[
  scalarState, mapState, fixedArrayState, dynamicArrayState, recordState, queueBackingState
]

/- Logical `StateId` values are stable identities; two different values never
alias just because a target layout might place them at the same offset. -/

def stateIdA : StateId := ⟨7⟩
def stateIdB : StateId := ⟨8⟩

def hasDuplicateStateId (decls : Array StateDecl) : Bool :=
  let ids := decls.map (·.id) |>.toList
  ids.any fun x => (ids.filter (· == x)).length > 1

/- A storage path rooted at `StateId`, never at a `Nat` slot. -/

def storagePath : StorageRef := {
  root := ⟨0⟩
  path := #[.mapKey { id := ⟨2⟩, type := .address }]
  resultType := .u128
}

/- Arithmetic mode is part of the instruction, not an implicit default. -/

def checkedAdd : InstructionOp :=
  .pure (.arithmetic .add .checked
    { id := ⟨0⟩, type := .u64 }
    { id := ⟨1⟩, type := .u64 })

def wrappingAdd : InstructionOp :=
  .pure (.arithmetic .add .wrapping
    { id := ⟨0⟩, type := .u64 }
    { id := ⟨1⟩, type := .u64 })

/- A minimal valid ANF/CFG function exercising a bounded back-edge. -/

def entryBlock : Block := {
  id := ⟨0⟩
  params := #[⟨⟨0⟩, .u64⟩]
  instructions := #[⟨#[⟨⟨1⟩, .u64⟩], checkedAdd⟩]
  terminator := .jump ⟨1⟩ #[{ id := ⟨1⟩, type := .u64 }] (some (.atMost 10))
}

def loopBodyBlock : Block := {
  id := ⟨1⟩
  params := #[⟨⟨2⟩, .u64⟩]
  instructions := #[]
  terminator := .return #[{ id := ⟨2⟩, type := .u64 }]
}

def exampleFunction : Function := {
  id := ⟨0⟩
  params := #[⟨⟨0⟩, .u64⟩]
  retType := .u64
  blocks := #[entryBlock, loopBodyBlock]
  entry := ⟨0⟩
}

def exampleModule : Module := {
  name := "CoreSchema"
  state := stateDecls
  functions := #[exampleFunction]
}

def main : IO Unit := do
  if hasDuplicateStateId stateDecls then
    throw <| IO.userError "state declarations must have distinct StateId values"
  if stateIdA == stateIdB then
    throw <| IO.userError "different StateId values must not alias"
  if checkedAdd == wrappingAdd then
    throw <| IO.userError "checked and wrapping add must be distinguishable"
  if storagePath.root != ⟨0⟩ then
    throw <| IO.userError "storage path must be rooted at StateId"
  IO.println s!"CoreSchema OK: {exampleModule.name}"
