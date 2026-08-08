import ProofForgeV2.Semantic.PreservationABI
import ProofForgeV2.Semantic.RequirementsV1

/-
  Closed wave-3 MiniAmm empty-pool L1 instance data (bf3-preserve).

  Product-aligned `Root.MiniAmmEmptyPool` with P1 predicate emptyPool:
    !(totalSupply == 0) || (reserve0 == 0 && reserve1 == 0)

  Leanest complete closed surface for PreservationTheoremV1 packaging:
  three public UInt64 slots, nullary clear (zero all), getTotalSupply view,
  executable emptyPool invariant. Full vault MiniAmmL1 admit surface remains
  Examples/MiniAmmL1; this instance is the product-aligned closed golden
  (same pattern as EvenCounter / ZeroCounter). No second step machine;
  no MiniAmm-only Semantic helper in ProofForgeV2/Semantic/.
-/

namespace ProofForgeV2.ProofInstances.MiniAmmEmptyPoolV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1

def qualifiedName : QualifiedName :=
  { components := ⟨"Root", #["MiniAmmEmptyPool"]⟩ }

def uint64Type : TypeDeclV1 :=
  { id := 0, name := none, shape := .uint 64 }

def boolType : TypeDeclV1 :=
  { id := 1, name := none, shape := .bool }

def types : Array TypeDeclV1 := #[uint64Type, boolType]

def reserve0State : StateDeclV1 :=
  { id := 0, name := "reserve0", typeId := 0, visibility := .public_ }

def reserve1State : StateDeclV1 :=
  { id := 1, name := "reserve1", typeId := 0, visibility := .public_ }

def totalSupplyState : StateDeclV1 :=
  { id := 2, name := "totalSupply", typeId := 0, visibility := .public_ }

def valueDef (valueId typeId : UInt32) : ValueDefV1 :=
  { valueId, typeId }

def valueInstruction
    (valueId typeId : UInt32) (op : SemanticOpV1) : InstructionV1 :=
  { result := some (valueDef valueId typeId), op }

def voidInstruction (op : SemanticOpV1) : InstructionV1 :=
  { result := none, op }

def zeroBytes : ByteArray := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]

/-- `clear`: store 0 into reserve0/reserve1/totalSupply, reload totalSupply, return. -/
def clearBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[
    valueInstruction 0 0 (.literal 0 zeroBytes),
    voidInstruction (.stateStore 0 0),
    valueInstruction 1 0 (.literal 0 zeroBytes),
    voidInstruction (.stateStore 1 1),
    valueInstruction 2 0 (.literal 0 zeroBytes),
    voidInstruction (.stateStore 2 2),
    valueInstruction 3 0 (.stateLoad 2)
  ]
  terminator := .return_ (some 3)
}

def clearCallable : CallableV1 := {
  id := 0
  kind := .entry
  name := some "clear"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[clearBlock]
  loopBounds := #[]
  invariantSteps := none
}

def getBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[valueInstruction 0 0 (.stateLoad 2)]
  terminator := .return_ (some 0)
}

def getCallable : CallableV1 := {
  id := 1
  kind := .view
  name := some "getTotalSupply"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[getBlock]
  loopBounds := #[]
  invariantSteps := none
}

/-- P1: !(totalSupply == 0) || (reserve0 == 0 && reserve1 == 0). -/
def emptyPoolBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[
    valueInstruction 0 0 (.stateLoad 2),
    valueInstruction 1 0 (.literal 0 zeroBytes),
    valueInstruction 2 1 (.binary .eq 0 1),
    valueInstruction 3 1 (.unary .not 2),
    valueInstruction 4 0 (.stateLoad 0),
    valueInstruction 5 0 (.literal 0 zeroBytes),
    valueInstruction 6 1 (.binary .eq 4 5),
    valueInstruction 7 0 (.stateLoad 1),
    valueInstruction 8 0 (.literal 0 zeroBytes),
    valueInstruction 9 1 (.binary .eq 7 8),
    valueInstruction 10 1 (.binary .and 6 9),
    valueInstruction 11 1 (.binary .or 3 10)
  ]
  terminator := .return_ (some 11)
}

def emptyPoolCallable : CallableV1 := {
  id := 2
  kind := .invariant
  name := some "emptyPool"
  params := #[]
  result := { typeId := 1, visibility := .public_ }
  entryBlock := 0
  blocks := #[emptyPoolBlock]
  loopBounds := #[]
  invariantSteps := some 14
}

def emptyPoolInvariant : InvariantDeclV1 :=
  { id := 0, name := "emptyPool", callableId := 2 }

def requirement
    (id : String) (digestBytes : ByteArray) : RequirementRequestV1 := {
  id
  version := s2RequirementVersionV1
  digest := { algorithm := .sha256, bytes := digestBytes }
  predicates := #[]
}

def persistentStateRequirement : RequirementRequestV1 :=
  requirement "state.persistent" s2StatePersistentDigestBytesV1

def data : SemanticProgramDataV1 := {
  qualifiedName
  types
  constants := #[]
  logicalState := #[reserve0State, reserve1State, totalSupplyState]
  events := #[]
  errors := #[]
  callables := #[clearCallable, getCallable, emptyPoolCallable]
  invariants := #[emptyPoolInvariant]
  requirements := {
    items := #[persistentStateRequirement]
  }
}

/-- Exact encoder bytes for product-aligned closed MiniAmmEmptyPool (2,342 bytes). -/
def canonicalSpine : List UInt8 := [
  112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0, 20,
  0, 0, 0, 83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114,
  97, 109, 46, 68, 97, 116, 97, 9, 0, 2, 0, 0, 0, 4, 0, 0,
  0, 82, 111, 111, 116, 16, 0, 0, 0, 77, 105, 110, 105, 65, 109, 109,
  69, 109, 112, 116, 121, 80, 111, 111, 108, 2, 0, 0, 0, 8, 0, 0,
  0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 0, 0, 0, 0, 0,
  9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64,
  0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 1,
  0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111,
  108, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 9, 0, 0, 0, 83,
  116, 97, 116, 101, 68, 101, 99, 108, 4, 0, 0, 0, 0, 0, 8, 0,
  0, 0, 114, 101, 115, 101, 114, 118, 101, 48, 0, 0, 0, 0, 17, 0,
  0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98,
  108, 105, 99, 0, 0, 9, 0, 0, 0, 83, 116, 97, 116, 101, 68, 101,
  99, 108, 4, 0, 1, 0, 0, 0, 8, 0, 0, 0, 114, 101, 115, 101,
  114, 118, 101, 49, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105,
  98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 9,
  0, 0, 0, 83, 116, 97, 116, 101, 68, 101, 99, 108, 4, 0, 2, 0,
  0, 0, 11, 0, 0, 0, 116, 111, 116, 97, 108, 83, 117, 112, 112, 108,
  121, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108,
  105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 3, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108,
  97, 98, 108, 101, 9, 0, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97,
  108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121, 0, 0, 1, 5,
  0, 0, 0, 99, 108, 101, 97, 114, 0, 0, 0, 0, 14, 0, 0, 0,
  67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116, 2, 0,
  0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105,
  116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1,
  0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 11, 0, 0, 0, 73, 110,
  115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0,
  86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108,
  2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111,
  110, 2, 0, 0, 13, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101,
  83, 116, 111, 114, 101, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11,
  0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0,
  1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 1,
  0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105,
  116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114,
  117, 99, 116, 105, 111, 110, 2, 0, 0, 13, 0, 0, 0, 79, 112, 46,
  83, 116, 97, 116, 101, 83, 116, 111, 114, 101, 2, 0, 1, 0, 0, 0,
  1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116,
  105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68,
  101, 102, 2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0,
  79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0,
  8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0,
  73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 0, 13, 0,
  0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101, 2,
  0, 2, 0, 0, 0, 2, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115,
  116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86,
  97, 108, 117, 101, 68, 101, 102, 2, 0, 3, 0, 0, 0, 0, 0, 0,
  0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97,
  100, 1, 0, 2, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46,
  82, 101, 116, 117, 114, 110, 1, 0, 1, 3, 0, 0, 0, 0, 0, 0,
  0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0,
  1, 0, 0, 0, 13, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101,
  46, 86, 105, 101, 119, 0, 0, 1, 14, 0, 0, 0, 103, 101, 116, 84,
  111, 116, 97, 108, 83, 117, 112, 112, 108, 121, 0, 0, 0, 0, 14, 0,
  0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116,
  2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105,
  108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0,
  0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0,
  73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0,
  0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101,
  76, 111, 97, 100, 1, 0, 2, 0, 0, 0, 11, 0, 0, 0, 84, 101,
  114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108,
  101, 9, 0, 2, 0, 0, 0, 18, 0, 0, 0, 67, 97, 108, 108, 97,
  98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116, 0, 0, 1,
  9, 0, 0, 0, 101, 109, 112, 116, 121, 80, 111, 111, 108, 0, 0, 0,
  0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115,
  117, 108, 116, 2, 0, 1, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115,
  105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99,
  107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 11,
  0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0,
  1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116,
  97, 116, 101, 76, 111, 97, 100, 1, 0, 2, 0, 0, 0, 11, 0, 0,
  0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8,
  0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 1, 0, 0,
  0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101,
  114, 97, 108, 2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99,
  116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101,
  68, 101, 102, 2, 0, 2, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0,
  0, 79, 112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 9, 0, 0, 0,
  66, 105, 110, 97, 114, 121, 46, 69, 113, 0, 0, 0, 0, 0, 0, 1,
  0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105,
  111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101,
  102, 2, 0, 3, 0, 0, 0, 1, 0, 0, 0, 8, 0, 0, 0, 79,
  112, 46, 85, 110, 97, 114, 121, 2, 0, 9, 0, 0, 0, 85, 110, 97,
  114, 121, 46, 78, 111, 116, 0, 0, 2, 0, 0, 0, 11, 0, 0, 0,
  73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0,
  0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 4, 0, 0, 0,
  0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101,
  76, 111, 97, 100, 1, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110,
  115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0,
  86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 5, 0, 0, 0, 0, 0,
  0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108,
  2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111,
  110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102,
  2, 0, 6, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0, 0, 79, 112,
  46, 66, 105, 110, 97, 114, 121, 3, 0, 9, 0, 0, 0, 66, 105, 110,
  97, 114, 121, 46, 69, 113, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0,
  11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2,
  0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0,
  7, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83,
  116, 97, 116, 101, 76, 111, 97, 100, 1, 0, 1, 0, 0, 0, 11, 0,
  0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1,
  8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 8, 0,
  0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116,
  101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117,
  99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117,
  101, 68, 101, 102, 2, 0, 9, 0, 0, 0, 1, 0, 0, 0, 9, 0,
  0, 0, 79, 112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 9, 0, 0,
  0, 66, 105, 110, 97, 114, 121, 46, 69, 113, 0, 0, 7, 0, 0, 0,
  8, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116,
  105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68,
  101, 102, 2, 0, 10, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0, 0,
  79, 112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 10, 0, 0, 0, 66,
  105, 110, 97, 114, 121, 46, 65, 110, 100, 0, 0, 6, 0, 0, 0, 9,
  0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105,
  111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101,
  102, 2, 0, 11, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0, 0, 79,
  112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 9, 0, 0, 0, 66, 105,
  110, 97, 114, 121, 46, 79, 114, 0, 0, 3, 0, 0, 0, 10, 0, 0,
  0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110,
  1, 0, 1, 11, 0, 0, 0, 0, 0, 0, 0, 1, 14, 0, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97,
  114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0, 0, 0, 0, 0, 9,
  0, 0, 0, 101, 109, 112, 116, 121, 80, 111, 111, 108, 2, 0, 0, 0,
  19, 0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105,
  114, 101, 109, 101, 110, 116, 115, 1, 0, 1, 0, 0, 0, 18, 0, 0,
  0, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117,
  101, 115, 116, 4, 0, 16, 0, 0, 0, 115, 116, 97, 116, 101, 46, 112,
  101, 114, 115, 105, 115, 116, 101, 110, 116, 5, 0, 0, 0, 49, 46, 48,
  46, 48, 2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154,
  62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20,
  110, 229, 0, 0, 0, 0
]

def canonicalBytes : ByteArray := ByteArray.mk (List.toArray canonicalSpine)

def program : SemanticProgramV1 := { canonicalBytes }

set_option maxRecDepth 20000 in
theorem canonicalSpine_length : canonicalSpine.length = 2342 := by
  rfl


/-! ### Production structure certificate (adapted from ZeroCounter) -/

private def uint64TypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0]

private def boolTypeShapeBytes : ByteArray :=
  ByteArray.mk #[9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0]

private theorem encodeTypeShape_uint64 :
    encodeTypeShapeV1 (.uint 64) = .ok uint64TypeShapeBytes := by
  change encodeTagged "Type.UInt" #[encodeU16le 64] = .ok uint64TypeShapeBytes
  rw [encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
    (by decide) (by decide) (by decide) (by decide) (by decide)]
  rfl

private theorem encodeTypeShape_bool :
    encodeTypeShapeV1 (.bool : TypeShapeV1) = .ok boolTypeShapeBytes := by
  change encodeNullary "Type.Bool" = .ok boolTypeShapeBytes
  rw [encodeNullary_eq_okV1 "Type.Bool" (by decide) (by decide) (by decide)]
  congr 1

private theorem compare_uint64_bool :
    compareByteArrayLex uint64TypeShapeBytes boolTypeShapeBytes = .gt := by
  rw [compareByteArrayLex]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 2 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 3 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 4 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 5 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 6 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 7 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 8 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_gt
  · decide
  · decide

private theorem typeKeyNamedPrefix :
    validateNamedPrefixRankV1 types = .ok () := by
  simp [types, uint64Type, boolType, validateNamedPrefixRankV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem typeKeyPrimitiveLeaf :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 types = .ok () := by
  simp [types, uint64Type, boolType,
    validatePrimitiveAnonymousTypeKeyUniquenessV1,
    encodeTypeShape_uint64, encodeTypeShape_bool, compare_uint64_bool,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem typeKeyRecursiveAnonymous :
    validateRecursiveAnonymousTypeKeyUniquenessV1 types = .ok () := by
  simp [types, uint64Type, boolType,
    validateRecursiveAnonymousTypeKeyUniquenessV1, Pure.pure, Except.pure]

private theorem typeKeyNamedBodyCycle :
    validateNamedBodyOptionCycleLegalityV1 types = .ok () := by
  simp [types, uint64Type, boolType,
    validateNamedBodyOptionCycleLegalityV1, Pure.pure, Except.pure]

private theorem typeKeyPhases :
    validateTypeKeyPhasesV1 types = .ok () := by
  apply validateTypeKeyPhasesV1_eq_ok_of_phases
  · exact typeKeyNamedPrefix
  · exact typeKeyPrimitiveLeaf
  · exact typeKeyRecursiveAnonymous
  · exact typeKeyNamedBodyCycle

private theorem structurePrelude :
    validateSemanticProgramStructurePreludeV1 data = .ok () := by
  have hqn : 2 ≤ qualifiedName.components.toArray.size := by decide
  simp [data, types, uint64Type, boolType, reserve0State, reserve1State,
    totalSupplyState, clearCallable, getCallable, emptyPoolCallable, clearBlock,
    getBlock, emptyPoolBlock, emptyPoolInvariant, valueInstruction, valueDef,
    voidInstruction, persistentStateRequirement, requirement,
    validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
    validateProgramQualifiedNameShapeV1, checkTypeShapeRefs, checkTypeIdInRange,
    checkCallableIdInRange, checkIdEqualsIndex, Pure.pure, Except.pure,
    Bind.bind, Except.bind]
  rw [if_pos hqn]

private theorem typesStructure :
    validateTypesStructureV1 types = .ok () := by
  simp [types, uint64Type, boolType, validateTypesStructureV1,
    validateTypeDeclShapeV1, validateTypeDeclNamedRuleV1,
    legalIntegerWidthV1_64, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem namedTypeNames :
    validateNamedTypeNameUniquenessV1 types = .ok () := by
  simp [types, uint64Type, boolType, validateNamedTypeNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem constantsValueBytes :
    validateConstantsValueBytesV1 types data.constants maxCanonicalProgramBytes =
      .ok maxCanonicalProgramBytes := by
  simp [data, validateConstantsValueBytesV1, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- Six UInt64 zero literals (3 clear + 3 emptyPool) × 9 budget each. -/
private theorem callablesValueBytes :
    validateCallablesValueBytesV1 types data.callables maxCanonicalProgramBytes =
      .ok (maxCanonicalProgramBytes - 54) := by
  have hlit (budget : Nat) (hb : 9 ≤ budget) :
      validateOpValueBytesV1 types (.literal 0 zeroBytes) budget =
        .ok (budget - 9) := by
    have h := validateOpValueBytesV1_literal_uint64_eq_ok types 0 uint64Type
      0 0 0 0 0 0 0 0 budget (by rfl) (by rfl) hb
    simpa [zeroBytes] using h
  have h0 : validateOpValueBytesV1 types (.literal 0 zeroBytes)
      maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 9) :=
    hlit _ (by decide)
  have h1 : validateOpValueBytesV1 types (.literal 0 zeroBytes)
      (maxCanonicalProgramBytes - 9) = .ok (maxCanonicalProgramBytes - 18) := by
    have h := hlit (maxCanonicalProgramBytes - 9) (by decide)
    have hb : maxCanonicalProgramBytes - 9 - 9 = maxCanonicalProgramBytes - 18 := by omega
    rw [hb] at h; exact h
  have h2 : validateOpValueBytesV1 types (.literal 0 zeroBytes)
      (maxCanonicalProgramBytes - 18) = .ok (maxCanonicalProgramBytes - 27) := by
    have h := hlit (maxCanonicalProgramBytes - 18) (by decide)
    have hb : maxCanonicalProgramBytes - 18 - 9 = maxCanonicalProgramBytes - 27 := by omega
    rw [hb] at h; exact h
  have h3 : validateOpValueBytesV1 types (.literal 0 zeroBytes)
      (maxCanonicalProgramBytes - 27) = .ok (maxCanonicalProgramBytes - 36) := by
    have h := hlit (maxCanonicalProgramBytes - 27) (by decide)
    have hb : maxCanonicalProgramBytes - 27 - 9 = maxCanonicalProgramBytes - 36 := by omega
    rw [hb] at h; exact h
  have h4 : validateOpValueBytesV1 types (.literal 0 zeroBytes)
      (maxCanonicalProgramBytes - 36) = .ok (maxCanonicalProgramBytes - 45) := by
    have h := hlit (maxCanonicalProgramBytes - 36) (by decide)
    have hb : maxCanonicalProgramBytes - 36 - 9 = maxCanonicalProgramBytes - 45 := by omega
    rw [hb] at h; exact h
  have h5 : validateOpValueBytesV1 types (.literal 0 zeroBytes)
      (maxCanonicalProgramBytes - 45) = .ok (maxCanonicalProgramBytes - 54) := by
    have h := hlit (maxCanonicalProgramBytes - 45) (by decide)
    have hb : maxCanonicalProgramBytes - 45 - 9 = maxCanonicalProgramBytes - 54 := by omega
    rw [hb] at h; exact h
  have hload (stateId : StateIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.stateLoad stateId) budget = .ok budget := rfl
  have hstore (stateId : StateIdV1) (value : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.stateStore stateId value) budget = .ok budget := rfl
  have hbinary (op : BinaryOpV1) (left right : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.binary op left right) budget = .ok budget := rfl
  have hunary (op : UnaryOpV1) (operand : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.unary op operand) budget = .ok budget := rfl
  have hreturn (value : Option ValueIdV1) (budget : Nat) :
      validateTerminatorValueBytesV1 types (.return_ value) budget = .ok budget := rfl
  simp [data, clearCallable, getCallable, emptyPoolCallable, clearBlock,
    getBlock, emptyPoolBlock, valueInstruction, valueDef, voidInstruction,
    validateCallablesValueBytesV1, hload, hstore, hbinary, hunary, hreturn,
    h0, h1, h2, h3, h4, h5, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem constantNames :
    validateConstantNameUniquenessV1 data.constants = .ok () := by
  simp [data, validateConstantNameUniquenessV1, checkUniqueDeclarationNamesV1,
    Pure.pure, Except.pure]

private theorem logicalStateNames :
    validateLogicalStateNameUniquenessV1 data.logicalState = .ok () := by
  have hbool :
      (match validateLogicalStateNameUniquenessV1
          #[reserve0State, reserve1State, totalSupplyState] with
       | .ok () => true
       | .error _ => false) = true := by
    native_decide
  cases hres :
      validateLogicalStateNameUniquenessV1
        #[reserve0State, reserve1State, totalSupplyState] with
  | ok _ =>
      simpa [data, reserve0State, reserve1State, totalSupplyState] using hres
  | error _ =>
      simp [hres] at hbool

private theorem eventNames :
    validateEventNameUniquenessV1 data.events = .ok () := by
  simp [data, validateEventNameUniquenessV1, checkUniqueDeclarationNamesV1,
    Pure.pure, Except.pure]

private theorem errorNames :
    validateErrorNameUniquenessV1 data.errors = .ok () := by
  simp [data, validateErrorNameUniquenessV1, checkUniqueDeclarationNamesV1,
    Pure.pure, Except.pure]

private theorem interfaceFieldNames :
    validateInterfaceFieldNameUniquenessV1 data.events data.errors = .ok () := by
  simp [data, validateInterfaceFieldNameUniquenessV1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem callableSignatures :
    validateCallableSignaturePhasesV1 types data.callables = .ok () := by
  have hEntryInit : ((.entry : CallableKindV1) == .initializer) = false := by decide
  have hViewInit : ((.view : CallableKindV1) == .initializer) = false := by decide
  have hInvInit : ((.invariant : CallableKindV1) == .initializer) = false := by decide
  have hEntryInv : ((.entry : CallableKindV1) == .invariant) = false := by decide
  have hViewInv : ((.view : CallableKindV1) == .invariant) = false := by decide
  have hInvInv : ((.invariant : CallableKindV1) == .invariant) = true := by decide
  have hPublic : ((.public_ : VisibilityV1) == .public_) = true := by decide
  apply validateCallableSignaturePhasesV1_eq_ok_of_phases
  all_goals
    simp [data, types, uint64Type, boolType, clearCallable, getCallable,
      emptyPoolCallable, clearBlock, getBlock, emptyPoolBlock, valueInstruction,
      valueDef, voidInstruction, validateCallableKindNamePresenceV1,
      validateCallableNameUniquenessV1,
      validateCallableParameterNameUniquenessV1,
      validateCallableEntryViewPresenceV1, validateInitializerCardinalityV1,
      validateInitializerResultShapeV1, validateInvariantResultShapeV1,
      validateInvariantParameterShapeV1, validateInvariantLoopBoundsShapeV1,
      validateNonClosureCallableInvariantStepsV1,
      validateInvariantRootStepsPresenceV1, hEntryInit, hViewInit, hInvInit,
      hEntryInv, hViewInv, hInvInv, hPublic, Pure.pure, Except.pure,
      Bind.bind, Except.bind]

private theorem invariantDeclarationJoin :
    validateInvariantDeclarationJoinV1 data.callables data.invariants = .ok () := by
  rfl

private theorem declarationIdentifierNames :
    validateDeclarationIdentifierNamesV1 data = .ok () := by
  rfl

private theorem programRequirementsStructure :
    validateProgramRequirementsStructure data.requirements = .ok () := by
  simpa [data, persistentStateRequirement, requirement] using
    (validateProgramRequirementsStructure_singleton_state_persistent_eq_ok
      s2RequirementVersionV1
      { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 })

private theorem contextReadRequirements :
    validateContextReadRequirementsV1 data = .ok () := by
  rfl

private theorem commitRequirements :
    validateCommitRequirementsV1 data = .ok () := by
  rfl

private theorem envReadRequirements :
    validateEnvReadRequirementsV1 data = .ok () := by
  rfl

private theorem clearCfg :
    validateCallableCfgShape clearCallable types.size types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    clearCallable types.size types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases clearCallable #[true]
      #[(0, 0), (1, 0), (2, 0), (3, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, clearCallable, clearBlock,
        valueInstruction, valueDef, voidInstruction, opValueUses,
        terminatorValueUses, Pure.pure, Except.pure, Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem getCfg :
    validateCallableCfgShape getCallable types.size types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    getCallable types.size types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases getCallable #[true] #[(0, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, getCallable, getBlock, valueInstruction,
        valueDef, opValueUses, terminatorValueUses, Pure.pure, Except.pure,
        Bind.bind, Except.bind]
    · rfl
  · rfl

set_option maxRecDepth 400000 in
set_option maxHeartbeats 80000000 in
private theorem emptyPoolCfg :
    validateCallableCfgShape emptyPoolCallable types.size types data = .ok () := by
  have hbool :
      (match validateCallableCfgShape emptyPoolCallable types.size types data with
       | .ok () => true
       | .error _ => false) = true := by
    native_decide
  cases hres :
      validateCallableCfgShape emptyPoolCallable types.size types data with
  | ok _ => rfl
  | error _ =>
      simp [hres] at hbool

private theorem genericCfgPhases :
    validateGenericCfgPhasesV1 data = .ok () := by
  apply validateGenericCfgPhasesV1_three_eq_ok data
    clearCallable getCallable emptyPoolCallable
  · rfl
  · exact clearCfg
  · exact getCfg
  · exact emptyPoolCfg
  · rfl

private def closureMembers : Array Bool := #[false, false, true]

private theorem closureMembershipResult :
    invariantClosureMembershipResultV1 data.callables = .ok closureMembers := by
  simp [invariantClosureMembershipResultV1, closureMembers, data,
    clearCallable, getCallable, emptyPoolCallable, clearBlock, getBlock,
    emptyPoolBlock, valueInstruction, valueDef, voidInstruction]
  rfl

private theorem closureMembershipPhases :
    validateInvariantClosureMembershipPhasesV1 data.callables =
      .ok closureMembers := by
  apply validateInvariantClosureMembershipPhasesV1_eq_ok
  · rfl
  · exact closureMembershipResult
  · apply validatePureFnInvariantClosureMembershipThreeV1
      clearCallable getCallable emptyPoolCallable <;> rfl

private theorem closureDagPhases :
    validateInvariantClosureDagPhasesV1 data.callables = .ok closureMembers := by
  apply validateInvariantClosureDagPhasesV1_eq_ok
  · exact closureMembershipPhases
  · apply validateInvariantClosureDagCanonicalThreeV1
    · simp [data, clearCallable, getCallable, emptyPoolCallable, clearBlock,
        getBlock, emptyPoolBlock, valueInstruction, valueDef, voidInstruction]
      rfl
    · rfl
    · rfl

private theorem invariantClosurePhases :
    validateInvariantClosurePhasesV1 data.callables = .ok closureMembers := by
  apply validateInvariantClosurePhasesV1_eq_ok
  · exact closureDagPhases
  · exact (validateInvariantClosurePostDagCanonicalThreeV1
      clearCallable getCallable emptyPoolCallable emptyPoolBlock (by rfl) (by rfl)
      (by rfl)).1
  · exact (validateInvariantClosurePostDagCanonicalThreeV1
      clearCallable getCallable emptyPoolCallable emptyPoolBlock (by rfl) (by rfl)
      (by rfl)).2

private theorem invariantFuelPhases :
    validateInvariantFuelPhasesV1 data.callables closureMembers = .ok () := by
  rfl

private theorem cfgInvariantPhases :
    validateCfgInvariantPhasesV1 data = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok data closureMembers
  · exact genericCfgPhases
  · exact invariantClosurePhases
  · exact invariantFuelPhases

theorem structure_ok : validateSemanticProgramStructureV1 data = .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases
    data maxCanonicalProgramBytes (maxCanonicalProgramBytes - 54)
  · exact structurePrelude
  · exact typesStructure
  · exact typeKeyPhases
  · exact namedTypeNames
  · exact constantsValueBytes
  · exact callablesValueBytes
  · exact constantNames
  · exact logicalStateNames
  · exact eventNames
  · exact errorNames
  · exact interfaceFieldNames
  · exact callableSignatures
  · exact invariantDeclarationJoin
  · exact declarationIdentifierNames
  · exact cfgInvariantPhases
  · exact programRequirementsStructure
  · exact contextReadRequirements
  · exact commitRequirements
  · exact envReadRequirements

set_option maxHeartbeats 80000000 in
theorem encode_ok : encodeSemanticProgramDataV1 data = .ok canonicalBytes := by
  set_option maxRecDepth 400000 in
    unfold encodeSemanticProgramDataV1
    rw [structure_ok]
    rfl

theorem admission_bool_ok :
    referenceProgramDataAdmissionOkV1 data = true := by
  decide

theorem admission_check_ok :
    validateReferenceProgramDataAdmissionV1 data = .ok () :=
  validateReferenceProgramDataAdmissionV1_eq_ok_of_bool data admission_bool_ok

end ProofForgeV2.ProofInstances.MiniAmmEmptyPoolV1
