import ProofForgeV2.Semantic.PreservationABI
import ProofForgeV2.Semantic.PreservationShapeV1
import ProofForgeV2.Semantic.RequirementsV1

/-
  Residual pin golden for the product-normalized `Root.EvenCounter` program
  (wave-3′ mig-b1 redo). Callables are **defined as**
  `PreservationShapeV1` constructors (increment-add-two / view-load / UInt64
  parity invariant) so same-file proofs are shape-family apply + rfl/decide —
  not a second contract-local micro-path.

  Residual golden (data/bytes/structure/encode) stays in product only as pin
  accelerator until mig-c1 deletes pin + residual modules. Sole step remains
  `admitReferenceProgramSliceV1` / `stepReferenceSliceV1`.
-/

namespace ProofForgeV2.Semantic.ParityCounterShapeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.PreservationABI
open ProofForgeV2.Semantic.PreservationShapeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1

/-- Exact product qualified name for the first closed instance. -/
def qualifiedName : QualifiedName :=
  { components := ⟨"Root", #["EvenCounter"]⟩ }

/-- Product Normalize type table: anonymous UInt64 followed by Bool. -/
def uint64Type : TypeDeclV1 :=
  { id := 0, name := none, shape := .uint 64 }

def boolType : TypeDeclV1 :=
  { id := 1, name := none, shape := .bool }

def types : Array TypeDeclV1 := #[uint64Type, boolType]

/-- Sole default-zero public state slot. -/
def countState : StateDeclV1 :=
  { id := 0, name := "count", typeId := 0, visibility := .public_ }

def valueDef (valueId typeId : UInt32) : ValueDefV1 :=
  { valueId, typeId }

def valueInstruction
    (valueId typeId : UInt32) (op : SemanticOpV1) : InstructionV1 :=
  { result := some (valueDef valueId typeId), op }

def voidInstruction (op : SemanticOpV1) : InstructionV1 :=
  { result := none, op }

/-- Canonical UInt64 literals used by the entry and invariant. -/
def twoBytes : ByteArray := ByteArray.mk #[2, 0, 0, 0, 0, 0, 0, 0]

def zeroBytes : ByteArray := ByteArray.mk #[0, 0, 0, 0, 0, 0, 0, 0]

private theorem twoBytes_eq_two8 : twoBytes = two8BytesV1 := rfl
private theorem zeroBytes_eq_zero8 : zeroBytes = zero8BytesV1 := rfl

/-- `increment`: load, add the even literal 2, store, reload, return. -/
def incrementBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[
    valueInstruction 0 0 (.stateLoad 0),
    valueInstruction 1 0 (.literal 0 twoBytes),
    valueInstruction 2 0 (.binary .add 0 1),
    voidInstruction (.stateStore 0 2),
    valueInstruction 3 0 (.stateLoad 0)
  ]
  terminator := .return_ (some 3)
}

def incrementCallable : CallableV1 := {
  id := 0
  kind := .entry
  name := some "increment"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[incrementBlock]
  loopBounds := #[]
  invariantSteps := none
}

/-- mig-b1: residual golden callables match PreservationShape constructors. -/
theorem incrementCallable_is_incrementAddTwo :
    incrementCallable =
      incrementAddTwoCallableV1 0 (some "increment") 0 0 := by
  simp [incrementCallable, incrementBlock, valueInstruction, valueDef,
    voidInstruction, incrementAddTwoCallableV1, twoBytes_eq_two8]

/-- `get`: read-only state projection. -/
def getBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[valueInstruction 0 0 (.stateLoad 0)]
  terminator := .return_ (some 0)
}

def getCallable : CallableV1 := {
  id := 1
  kind := .view
  name := some "get"
  params := #[]
  result := { typeId := 0, visibility := .public_ }
  entryBlock := 0
  blocks := #[getBlock]
  loopBounds := #[]
  invariantSteps := none
}

theorem getCallable_is_viewLoad :
    getCallable = viewLoadCallableV1 1 (some "get") 0 0 := by
  simp [getCallable, getBlock, valueInstruction, valueDef, viewLoadCallableV1]

/-- Executable parity predicate: `(count % 2) == 0`. -/
def evenBlock : BlockV1 := {
  id := 0
  params := #[]
  instructions := #[
    valueInstruction 0 0 (.stateLoad 0),
    valueInstruction 1 0 (.literal 0 twoBytes),
    valueInstruction 2 0 (.binary .mod 0 1),
    valueInstruction 3 0 (.literal 0 zeroBytes),
    valueInstruction 4 1 (.binary .eq 2 3)
  ]
  terminator := .return_ (some 4)
}

def evenCallable : CallableV1 := {
  id := 2
  kind := .invariant
  name := some "even"
  params := #[]
  result := { typeId := 1, visibility := .public_ }
  entryBlock := 0
  blocks := #[evenBlock]
  loopBounds := #[]
  invariantSteps := some 7
}

theorem evenCallable_is_uint64Parity :
    evenCallable =
      uint64ParityInvariantCallableV1 2 (some "even") 0 1 0 .public_ (some 7) := by
  simp [evenCallable, evenBlock, valueInstruction, valueDef,
    uint64ParityInvariantCallableV1, twoBytes_eq_two8, zeroBytes_eq_zero8]

def evenInvariant : InvariantDeclV1 :=
  { id := 0, name := "even", callableId := 2 }

def requirement
    (id : String) (digestBytes : ByteArray) : RequirementRequestV1 := {
  id
  version := s2RequirementVersionV1
  digest := { algorithm := .sha256, bytes := digestBytes }
  predicates := #[]
}

def rollbackRequirement : RequirementRequestV1 :=
  requirement "failure.atomic-rollback" s2FailureAtomicRollbackDigestBytesV1

def persistentStateRequirement : RequirementRequestV1 :=
  requirement "state.persistent" s2StatePersistentDigestBytesV1

def checkedArithmeticRequirement : RequirementRequestV1 :=
  requirement "value.checked-arithmetic" s2ValueCheckedArithmeticDigestBytesV1

/-- Exact decoded `SemanticProgramDataV1` produced by Normalize. -/
def data : SemanticProgramDataV1 := {
  qualifiedName
  types
  constants := #[]
  logicalState := #[countState]
  events := #[]
  errors := #[]
  callables := #[incrementCallable, getCallable, evenCallable]
  invariants := #[evenInvariant]
  requirements := {
    items := #[rollbackRequirement, persistentStateRequirement,
      checkedArithmeticRequirement]
  }
}

/-- Exact transparent product bytes for `Root.EvenCounter` (1,795 bytes). -/
def canonicalSpine : List UInt8 := [
  112, 102, 46, 115, 101, 109, 97, 110, 116, 105, 99, 46, 118, 49, 0, 20, 0, 0, 0, 83, 101, 109, 97, 110, 116, 105, 99, 80, 114, 111, 103, 114, 97, 109, 46, 68, 97, 116, 97, 9, 0, 2, 0, 0, 0, 4, 0, 0, 0, 82, 111, 111, 116, 11, 0, 0, 0, 69, 118, 101, 110, 67, 111, 117, 110, 116, 101, 114, 2, 0, 0, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 85, 73, 110, 116, 1, 0, 64, 0, 8, 0, 0, 0, 84, 121, 112, 101, 68, 101, 99, 108, 3, 0, 1, 0, 0, 0, 0, 9, 0, 0, 0, 84, 121, 112, 101, 46, 66, 111, 111, 108, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0, 0, 83, 116, 97, 116, 101, 68, 101, 99, 108, 4, 0, 0, 0, 0, 0, 5, 0, 0, 0, 99, 111, 117, 110, 116, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 69, 110, 116, 114, 121, 0, 0, 1, 9, 0, 0, 0, 105, 110, 99, 114, 101, 109, 101, 110, 116, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100, 1, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 79, 112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 10, 0, 0, 0, 66, 105, 110, 97, 114, 121, 46, 65, 100, 100, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 0, 13, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 83, 116, 111, 114, 101, 2, 0, 0, 0, 0, 0, 2, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 3, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100, 1, 0, 0, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 1, 0, 0, 0, 13, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 86, 105, 101, 119, 0, 0, 1, 3, 0, 0, 0, 103, 101, 116, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116, 2, 0, 0, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100, 1, 0, 0, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 9, 0, 2, 0, 0, 0, 18, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 46, 73, 110, 118, 97, 114, 105, 97, 110, 116, 0, 0, 1, 4, 0, 0, 0, 101, 118, 101, 110, 0, 0, 0, 0, 14, 0, 0, 0, 67, 97, 108, 108, 97, 98, 108, 101, 82, 101, 115, 117, 108, 116, 2, 0, 1, 0, 0, 0, 17, 0, 0, 0, 86, 105, 115, 105, 98, 105, 108, 105, 116, 121, 46, 80, 117, 98, 108, 105, 99, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, 66, 108, 111, 99, 107, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0, 0, 79, 112, 46, 83, 116, 97, 116, 101, 76, 111, 97, 100, 1, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 79, 112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 10, 0, 0, 0, 66, 105, 110, 97, 114, 121, 46, 77, 111, 100, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 3, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 79, 112, 46, 76, 105, 116, 101, 114, 97, 108, 2, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 73, 110, 115, 116, 114, 117, 99, 116, 105, 111, 110, 2, 0, 1, 8, 0, 0, 0, 86, 97, 108, 117, 101, 68, 101, 102, 2, 0, 4, 0, 0, 0, 1, 0, 0, 0, 9, 0, 0, 0, 79, 112, 46, 66, 105, 110, 97, 114, 121, 3, 0, 9, 0, 0, 0, 66, 105, 110, 97, 114, 121, 46, 69, 113, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 11, 0, 0, 0, 84, 101, 114, 109, 46, 82, 101, 116, 117, 114, 110, 1, 0, 1, 4, 0, 0, 0, 0, 0, 0, 0, 1, 7, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 13, 0, 0, 0, 73, 110, 118, 97, 114, 105, 97, 110, 116, 68, 101, 99, 108, 3, 0, 0, 0, 0, 0, 4, 0, 0, 0, 101, 118, 101, 110, 2, 0, 0, 0, 19, 0, 0, 0, 80, 114, 111, 103, 114, 97, 109, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 115, 1, 0, 3, 0, 0, 0, 18, 0, 0, 0, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116, 4, 0, 23, 0, 0, 0, 102, 97, 105, 108, 117, 114, 101, 46, 97, 116, 111, 109, 105, 99, 45, 114, 111, 108, 108, 98, 97, 99, 107, 5, 0, 0, 0, 49, 46, 48, 46, 48, 254, 98, 216, 232, 64, 20, 227, 236, 31, 23, 247, 108, 127, 85, 250, 195, 25, 2, 68, 236, 163, 173, 18, 77, 208, 78, 23, 195, 201, 209, 17, 101, 0, 0, 0, 0, 18, 0, 0, 0, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116, 4, 0, 16, 0, 0, 0, 115, 116, 97, 116, 101, 46, 112, 101, 114, 115, 105, 115, 116, 101, 110, 116, 5, 0, 0, 0, 49, 46, 48, 46, 48, 2, 63, 255, 245, 41, 95, 167, 238, 77, 158, 78, 73, 144, 154, 62, 183, 241, 252, 12, 86, 31, 142, 126, 160, 111, 18, 66, 52, 12, 20, 110, 229, 0, 0, 0, 0, 18, 0, 0, 0, 82, 101, 113, 117, 105, 114, 101, 109, 101, 110, 116, 82, 101, 113, 117, 101, 115, 116, 4, 0, 24, 0, 0, 0, 118, 97, 108, 117, 101, 46, 99, 104, 101, 99, 107, 101, 100, 45, 97, 114, 105, 116, 104, 109, 101, 116, 105, 99, 5, 0, 0, 0, 49, 46, 48, 46, 48, 226, 24, 107, 1, 207, 88, 19, 81, 17, 247, 78, 197, 106, 83, 227, 51, 135, 188, 48, 22, 72, 104, 7, 27, 31, 82, 74, 242, 34, 184, 191, 205, 0, 0, 0, 0
]

/-- Same transparent spine shape as elaborator `quoteByteArraySpine` so product
    `EvenCounter.Proof.subjectBytesV1` can be definitionally the closed instance. -/
def canonicalBytes : ByteArray := ByteArray.mk (List.toArray canonicalSpine)

def program : SemanticProgramV1 := { canonicalBytes }

set_option maxRecDepth 10000 in
theorem canonicalSpine_length : canonicalSpine.length = 1795 := by
  rfl

/-! ### Production structure certificate -/

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
  simp [data, types, uint64Type, boolType, countState,
    incrementCallable, getCallable, evenCallable, incrementBlock, getBlock,
    evenBlock, evenInvariant, valueInstruction, valueDef, voidInstruction,
    rollbackRequirement, persistentStateRequirement, checkedArithmeticRequirement,
    requirement, validateSemanticProgramStructurePreludeV1, checkTableIdsV1,
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

private theorem callablesValueBytes :
    validateCallablesValueBytesV1 types data.callables maxCanonicalProgramBytes =
      .ok (maxCanonicalProgramBytes - 27) := by
  have htwo0 :
      validateOpValueBytesV1 types (.literal 0 twoBytes)
        maxCanonicalProgramBytes = .ok (maxCanonicalProgramBytes - 9) := by
    apply validateOpValueBytesV1_literal_uint64_eq_ok types 0 uint64Type
      2 0 0 0 0 0 0 0
    · rfl
    · rfl
    · decide
  have htwo1 :
      validateOpValueBytesV1 types (.literal 0 twoBytes)
        (maxCanonicalProgramBytes - 9) =
        .ok (maxCanonicalProgramBytes - 18) := by
    have h := validateOpValueBytesV1_literal_uint64_eq_ok types 0 uint64Type
      2 0 0 0 0 0 0 0 (maxCanonicalProgramBytes - 9) (by rfl) (by rfl)
      (by decide)
    have hbudget : maxCanonicalProgramBytes - 9 - 9 =
        maxCanonicalProgramBytes - 18 := by omega
    rw [hbudget] at h
    simpa [twoBytes] using h
  have hzero :
      validateOpValueBytesV1 types (.literal 0 zeroBytes)
        (maxCanonicalProgramBytes - 18) =
        .ok (maxCanonicalProgramBytes - 27) := by
    have h := validateOpValueBytesV1_literal_uint64_eq_ok types 0 uint64Type
      0 0 0 0 0 0 0 0 (maxCanonicalProgramBytes - 18) (by rfl) (by rfl)
      (by decide)
    have hbudget : maxCanonicalProgramBytes - 18 - 9 =
        maxCanonicalProgramBytes - 27 := by omega
    rw [hbudget] at h
    simpa [zeroBytes] using h
  have hload (stateId : StateIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.stateLoad stateId) budget = .ok budget := rfl
  have hstore (stateId : StateIdV1) (value : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.stateStore stateId value) budget = .ok budget := rfl
  have hbinary (op : BinaryOpV1) (left right : ValueIdV1) (budget : Nat) :
      validateOpValueBytesV1 types (.binary op left right) budget = .ok budget := rfl
  have hreturn (value : Option ValueIdV1) (budget : Nat) :
      validateTerminatorValueBytesV1 types (.return_ value) budget = .ok budget := rfl
  simp [data, incrementCallable, getCallable, evenCallable, incrementBlock,
    getBlock, evenBlock, valueInstruction, valueDef, voidInstruction,
    validateCallablesValueBytesV1, hload, hstore, hbinary, hreturn,
    htwo0, htwo1, hzero, Pure.pure, Except.pure, Bind.bind, Except.bind]

private theorem constantNames :
    validateConstantNameUniquenessV1 data.constants = .ok () := by
  simp [data, validateConstantNameUniquenessV1, checkUniqueDeclarationNamesV1,
    Pure.pure, Except.pure]

private theorem logicalStateNames :
    validateLogicalStateNameUniquenessV1 data.logicalState = .ok () := by
  simp [data, countState, validateLogicalStateNameUniquenessV1,
    checkUniqueDeclarationNamesV1, Pure.pure, Except.pure]

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
    simp [data, types, uint64Type, boolType, incrementCallable, getCallable,
      evenCallable, incrementBlock, getBlock, evenBlock, valueInstruction,
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
  simpa [data, rollbackRequirement, persistentStateRequirement,
    checkedArithmeticRequirement, requirement] using
    (validateProgramRequirementsStructure_failure_state_checked_eq_ok
      s2RequirementVersionV1 s2RequirementVersionV1 s2RequirementVersionV1
      { algorithm := .sha256, bytes := s2FailureAtomicRollbackDigestBytesV1 }
      { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
      { algorithm := .sha256, bytes := s2ValueCheckedArithmeticDigestBytesV1 })

private theorem contextReadRequirements :
    validateContextReadRequirementsV1 data = .ok () := by
  rfl

private theorem commitRequirements :
    validateCommitRequirementsV1 data = .ok () := by
  rfl

private theorem envReadRequirements :
    validateEnvReadRequirementsV1 data = .ok () := by
  rfl

private theorem incrementCfg :
    validateCallableCfgShape incrementCallable types.size types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    incrementCallable types.size types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases incrementCallable #[true]
      #[(0, 0), (1, 0), (2, 0), (3, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, incrementCallable, incrementBlock,
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

private theorem evenCfg :
    validateCallableCfgShape evenCallable types.size types data = .ok () := by
  refine validateCallableCfgShape_eq_ok_of_phases
    evenCallable types.size types data #[true] ?_ ?_ ?_ ?_ ?_
  · rfl
  · rfl
  · rfl
  · apply validateCallableCfgValueFlow_eq_ok_of_phases evenCallable #[true]
      #[(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)]
    · rfl
    · rfl
    · simp [checkValueIdUsesExist, evenCallable, evenBlock, valueInstruction,
        valueDef, opValueUses, terminatorValueUses, Pure.pure, Except.pure,
        Bind.bind, Except.bind]
    · rfl
  · rfl

private theorem genericCfgPhases :
    validateGenericCfgPhasesV1 data = .ok () := by
  apply validateGenericCfgPhasesV1_three_eq_ok data
    incrementCallable getCallable evenCallable
  · rfl
  · exact incrementCfg
  · exact getCfg
  · exact evenCfg
  · rfl

private def closureMembers : Array Bool := #[false, false, true]

private theorem closureMembershipResult :
    invariantClosureMembershipResultV1 data.callables = .ok closureMembers := by
  simp [invariantClosureMembershipResultV1, closureMembers, data,
    incrementCallable, getCallable, evenCallable, incrementBlock, getBlock,
    evenBlock, valueInstruction, valueDef, voidInstruction]
  rfl

private theorem closureMembershipPhases :
    validateInvariantClosureMembershipPhasesV1 data.callables =
      .ok closureMembers := by
  apply validateInvariantClosureMembershipPhasesV1_eq_ok
  · rfl
  · exact closureMembershipResult
  · apply validatePureFnInvariantClosureMembershipThreeV1
      incrementCallable getCallable evenCallable <;> rfl

private theorem closureDagPhases :
    validateInvariantClosureDagPhasesV1 data.callables = .ok closureMembers := by
  apply validateInvariantClosureDagPhasesV1_eq_ok
  · exact closureMembershipPhases
  · apply validateInvariantClosureDagCanonicalThreeV1
    · simp [data, incrementCallable, getCallable, evenCallable, incrementBlock,
        getBlock, evenBlock, valueInstruction, valueDef, voidInstruction]
      rfl
    · rfl
    · rfl

private theorem invariantClosurePhases :
    validateInvariantClosurePhasesV1 data.callables = .ok closureMembers := by
  apply validateInvariantClosurePhasesV1_eq_ok
  · exact closureDagPhases
  · exact (validateInvariantClosurePostDagCanonicalThreeV1
      incrementCallable getCallable evenCallable evenBlock (by rfl) (by rfl)
      (by rfl)).1
  · exact (validateInvariantClosurePostDagCanonicalThreeV1
      incrementCallable getCallable evenCallable evenBlock (by rfl) (by rfl)
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

/-- Every production Semantic structure phase accepts the exact normalized
    EvenCounter data. -/
theorem structure_ok : validateSemanticProgramStructureV1 data = .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases
    data maxCanonicalProgramBytes (maxCanonicalProgramBytes - 27)
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

/- The sole production encoder yields the exact product-normalized 1,795-byte
   carrier pinned above. -/
set_option maxHeartbeats 80000000 in
theorem encode_ok : encodeSemanticProgramDataV1 data = .ok canonicalBytes := by
  set_option maxRecDepth 400000 in
    unfold encodeSemanticProgramDataV1
    rw [structure_ok]
    rfl

end ProofForgeV2.Semantic.ParityCounterShapeV1
