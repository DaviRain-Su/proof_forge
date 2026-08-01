/-
  Tests.Semantic.WireV1 — focused engineering suite for D2-06 wire skeleton.

  Pins schema/magic, empty/minimal root round-trip, hash identity, structure
  gate (program qualifiedName ≥2 components, id/index, shallow refs,
  type-shape/FieldSpec/Map-key, leaf primitive plus recursive anonymous
  `.array`/`.map`/`.option` structural-class uniqueness (fixed-size
  structural-class signatures, not nested child keys) with anonymous-
  container-cycle rejection (without a named anchor), canonical valueBytes for Constant/Op.Literal/
  SwitchCase, requirements domain/order/
  predicates/enumContains), nesting fuel maxNesting=256, provenance
  envelope transport + incomplete/foreign join negatives (complete S2
  positive join only in Normalize suite), Digest raw-32 wire,
  and invalid-carrier invariants projection.
  callable kind/name presence, CFG shape/reachability (including Switch
  nonempty/typed-value uniqueness), loop bounds, per-callable EffectId
  assignment, per-callable canonical ValueId assignment/use-existence/
  dominance, def-site TypeId range,
  block/terminator typing, step-j per-op contracts, invariant-closure
  membership/DAG/CFG/op restrictions, and exact checked computedInvariantSteps
  are pinned; named-prefix contiguous-rank and the named-body
  `Option`-cycle legality rule (recursive cycles must pass through an Option)
  are covered, while anonymous
  canonical rank/order, usage closure, provenance join/normalizer/product
  wire, and the remaining full TypeKey closure remain
  pending. Step j
  includes the exact CheckedCast contract (UInt/Int source and destination,
  result.typeId == toType), StateStore state lookup/value type/void-result,
  Assert Bool/error/args/void-result, Term.Revert ErrorDecl/args, and Emit
  EventDecl/args/void-result contracts; the §5.1 ContextRead same-key
  result-TypeId consistency pass is pinned (one exact SchemaId key → one
  Instruction.result TypeId across the whole program, `.badCfg`, `.cfg` phase
  after generic CFG/op typing and before invariant closure/fuel/requirements),
  the ContextRead static-only catalog binds its sole Unix-time-seconds key to
  anonymous UInt64 and one exact requirement row; Commit binds exact
  operand/result TypeIds and one exact disclosure.commitment row. Fixtures that
  exercise ContextRead/Commit pass those exact requirement rows explicitly via
  `programWithTypes` (no silent scan/injection). Formal TST-SEM-001 corpus
  remains pending.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1

/-! The first proof-validation seam is definitional on the transparent spine,
and its theorem is reusable without `native_decide`, axioms, or runtime IO. -/
example (bytes : TransparentByteSpineV1) (offset : Nat) :
    remainingBytesAtV1 (ByteArray.mk bytes.toArray) offset =
      spineRemainingV1 bytes offset :=
  remainingBytesAtV1_refinesSpine bytes offset

example : readSpineByteV1 [0x10, 0x20, 0x30] 1 = .ok 0x20 := by rfl

example : readSpineByteV1 [0x10, 0x20, 0x30] 3 = .error .truncated := by rfl

example (bytes : TransparentByteSpineV1) (offset : Nat) :
    readByteAtV1 (ByteArray.mk bytes.toArray) offset = readSpineByteV1 bytes offset :=
  readByteAtV1_refinesSpine bytes offset

example : readSpineU16leV1 [0xff, 0x34, 0x12, 0xee] 1 = .ok (0x1234, 3) := by rfl

example : readSpineU16leV1 [0x34] 0 = .error .truncated := by rfl

example (bytes : TransparentByteSpineV1) (offset : Nat) :
    readU16leAtV1 (ByteArray.mk bytes.toArray) offset = readSpineU16leV1 bytes offset :=
  readU16leAtV1_refinesSpine bytes offset

example : readSpineU32leV1 [0xff, 0x78, 0x56, 0x34, 0x12, 0xee] 1 =
    .ok (0x12345678, 5) := by rfl

example : readSpineU32leV1 [0x78, 0x56, 0x34] 0 = .error .truncated := by rfl

example (bytes : TransparentByteSpineV1) (offset : Nat) :
    readU32leAtV1 (ByteArray.mk bytes.toArray) offset = readSpineU32leV1 bytes offset :=
  readU32leAtV1_refinesSpine bytes offset

example :
    (decodeU16le (startAtNesting (ByteArray.mk [0x34, 0x12, 0xee].toArray) 7)).map
        (fun (value, cursor) => (value, remaining cursor, cursorNesting cursor)) =
      .ok (0x1234, 1, 7) := by rfl

example : decodeU16le (start ByteArray.empty) = .error .truncated := by rfl
example : decodeU16le (start (ByteArray.mk [0x34].toArray)) = .error .truncated := by rfl

example :
    (decodeU32le (startAtNesting (ByteArray.mk [0x78, 0x56, 0x34, 0x12, 0xee].toArray) 9)).map
        (fun (value, cursor) => (value, remaining cursor, cursorNesting cursor)) =
      .ok (0x12345678, 1, 9) := by rfl

example : decodeU32le (start ByteArray.empty) = .error .truncated := by rfl
example : decodeU32le (start (ByteArray.mk [0x78].toArray)) = .error .truncated := by rfl
example : decodeU32le (start (ByteArray.mk [0x78, 0x56].toArray)) = .error .truncated := by rfl
example : decodeU32le (start (ByteArray.mk [0x78, 0x56, 0x34].toArray)) =
    .error .truncated := by rfl

example : takeSpineBytesV1 [0x10, 0x20, 0x30, 0x40] 1 2 = .ok [0x20, 0x30] := by rfl

example : takeSpineBytesV1 [0x10, 0x20, 0x30, 0x40] 3 2 = .error .truncated := by rfl

example : takeSpineBytesV1 [0x10, 0x20] 3 0 = .ok [] := by rfl

example : takeSpineBytesV1 [0x10, 0x20] 3 1 = .error .truncated := by rfl

example (bytes : TransparentByteSpineV1) (offset count : Nat) :
    (takeBytesAtV1 (ByteArray.mk bytes.toArray) offset count).map
        (fun slice => slice.data.toList) =
      takeSpineBytesV1 bytes offset count :=
  takeBytesAtV1_refinesSpine bytes offset count

example : consumeMagicSpineBytesV1 [0xff, 0x70, 0x66, 0, 0xee] 1 [0x70, 0x66, 0] =
    .ok 4 := by rfl

example : consumeMagicSpineBytesV1 [0x70, 0x66] 0 [0x70, 0x66, 0] =
    .error .truncated := by rfl

example : consumeMagicSpineBytesV1 [0x70, 0x67, 0] 0 [0x70, 0x66, 0] =
    .error .badMagic := by rfl

example : consumeMagicSpineBytesV1 [0x70] 3 [] = .ok 3 := by rfl

example : consumeMagicSpineBytesV1 [0x70] 3 [0x70] = .error .truncated := by rfl

example : consumeMagicSpineBytesV1 [0x71] 0 [0x70, 0x66] =
    .error .truncated := by rfl

example (input want : TransparentByteSpineV1) (offset : Nat) :
    consumeMagicBytesAtV1 (ByteArray.mk input.toArray) offset
        (ByteArray.mk want.toArray) =
      consumeMagicSpineBytesV1 input offset want :=
  consumeMagicBytesAtV1_refinesSpine input want offset

example : readTagSpineBytesV1 [0xff, 3, 0, 0, 0, 0x41, 0x2e, 0x42, 0xee] 1 =
    .ok ([0x41, 0x2e, 0x42], 8) := by rfl

example : readTagSpineBytesV1 [0, 0, 0, 0] 0 = .error .badTag := by rfl

example : readTagSpineBytesV1 [2, 0, 0, 0, 0x41] 0 = .error .truncated := by rfl

example : readTagSpineBytesV1 [1, 0, 0, 0, 0x80] 0 = .error .badTag := by rfl

example (input : TransparentByteSpineV1) (offset : Nat) :
    (readTagBytesAtV1 (ByteArray.mk input.toArray) offset).map
        (fun (raw, next) => (raw.data.toList, next)) =
      readTagSpineBytesV1 input offset :=
  readTagBytesAtV1_refinesSpine input offset

example : expectTaggedHeaderSpineV1 [0xff, 3, 0, 0, 0, 0x41, 0x2e, 0x42, 2, 0]
    1 [0x41, 0x2e, 0x42] 2 = .ok 10 := by rfl

example : expectTaggedHeaderSpineV1 [3, 0, 0, 0, 0x41, 0x2e, 0x43]
    0 [0x41, 0x2e, 0x42] 2 = .error .badTag := by rfl

example : expectTaggedHeaderSpineV1 [3, 0, 0, 0, 0x41, 0x2e, 0x42]
    0 [0x41, 0x2e, 0x42] 2 = .error .truncated := by rfl

example : expectTaggedHeaderSpineV1 [3, 0, 0, 0, 0x41, 0x2e, 0x42, 1, 0]
    0 [0x41, 0x2e, 0x42] 2 = .error .badFieldCount := by rfl

example (input want : TransparentByteSpineV1) (offset fieldCount : Nat) :
    expectTaggedHeaderBytesAtV1 (ByteArray.mk input.toArray) offset
        (ByteArray.mk want.toArray) fieldCount =
      expectTaggedHeaderSpineV1 input offset want fieldCount :=
  expectTaggedHeaderBytesAtV1_refinesSpine input want offset fieldCount

example : readSizedSpineBytesV1 [0xff, 3, 0, 0, 0, 0x10, 0x20, 0x30, 0xee]
    1 3 = .ok ([0x10, 0x20, 0x30], 8) := by rfl

example : readSizedSpineBytesV1 [0, 0, 0, 0, 0xee] 0 0 = .ok ([], 4) := by rfl

example : readSizedSpineBytesV1 [4, 0, 0, 0] 0 3 = .error .limitExceeded := by rfl

example : readSizedSpineBytesV1 [3, 0, 0, 0, 0x10, 0x20] 0 3 =
    .error .truncated := by rfl

example : readSizedSpineBytesV1 [0xff, 0xff, 0xff, 0xff] 0 UInt32.size =
    .error .truncated := by rfl

example : readSizedSpineBytesV1 [0, 0, 0, 0] 1 0 = .error .truncated := by rfl

example (input : TransparentByteSpineV1) (offset maxLen : Nat) :
    (readSizedBytesAtV1 (ByteArray.mk input.toArray) offset maxLen).map
        (fun (payload, next) => (payload.data.toList, next)) =
      readSizedSpineBytesV1 input offset maxLen :=
  readSizedBytesAtV1_refinesSpine input offset maxLen

example : readArrayCountSpineV1 [0xff, 3, 0, 0, 0, 0xee] 1 3 = .ok (3, 5) := by rfl

example : readArrayCountSpineV1 [0, 0, 0, 0] 0 0 = .ok (0, 4) := by rfl

example : readArrayCountSpineV1 [4, 0, 0, 0] 0 3 = .error .limitExceeded := by rfl

example : readArrayCountSpineV1 [1, 0, 0] 0 3 = .error .truncated := by rfl

example : readArrayCountSpineV1 [0xff, 0xff, 0xff, 0xff] 0 UInt32.size =
    .ok (UInt32.size - 1, 4) := by rfl

example (input : TransparentByteSpineV1) (offset maxCount : Nat) :
    readArrayCountAtV1 (ByteArray.mk input.toArray) offset maxCount =
      readArrayCountSpineV1 input offset maxCount :=
  readArrayCountAtV1_refinesSpine input offset maxCount

example :
    decodeArrayElementsV1 decodeU32le 0 #[]
      ⟨ByteArray.mk [0xaa].toArray, 0, 7⟩ =
        .ok (#[], ⟨ByteArray.mk [0xaa].toArray, 0, 7⟩) := by rfl

example :
    (decodeArray 3 decodeU32le
      ⟨ByteArray.mk [2, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0xee].toArray, 0, 5⟩).map
        (fun (values, cursor) => (values, cursor.offset, cursor.nesting, remaining cursor)) =
      .ok (#[1, 2], 12, 5, 1) := by rfl

example :
    decodeArray 2 decodeU32le
      (start (ByteArray.mk [2, 0, 0, 0, 1, 0, 0, 0].toArray)) =
        .error .truncated := by rfl

example :
    decodeArray 1 decodeU32le
      (start (ByteArray.mk [1, 0, 0, 0].toArray)) =
        .error .truncated := by rfl

example (input : ByteArray) (offset nesting maxCount count afterCount : Nat)
    (hcount : readArrayCountAtV1 input offset maxCount = .ok (count, afterCount)) :
    decodeArray maxCount decodeU32le ⟨input, offset, nesting⟩ =
      decodeArrayElementsV1 decodeU32le count #[] ⟨input, afterCount, nesting⟩ :=
  decodeArray_eq_elementsV1 maxCount decodeU32le ⟨input, offset, nesting⟩ count afterCount hcount

example (c : Cursor) (count offset : Nat)
    (hcount : readArrayCountAtV1 c.input c.offset 256 = .ok (count, offset)) :
    decodeQualifiedName c =
      match decodeArrayElementsV1 decodeString count #[] ⟨c.input, offset, c.nesting⟩ with
      | .error e => .error e
      | .ok (components, c') =>
          match parseQualifiedName components with
          | .error _ => .error .badScalar
          | .ok name => .ok (name, c') :=
  decodeQualifiedName_eq_elementsV1 c count offset hcount

example :
    withTaggedNesting decodeU8
      ⟨ByteArray.mk [0xaa].toArray, 0, maxNesting⟩ = .error .limitExceeded := by rfl

example :
    (withTaggedNesting decodeU8 ⟨ByteArray.mk [0xaa].toArray, 0, 7⟩).map
        (fun (value, c) => (value, c.offset, c.nesting)) = .ok (0xaa, 1, 7) := by rfl

example :
    withTaggedNesting
      (fun _ => .ok (0xaa, ⟨ByteArray.mk [0xbb].toArray, 9, 99⟩))
      ⟨ByteArray.mk [0xcc].toArray, 3, 7⟩ =
        .ok (0xaa, ⟨ByteArray.mk [0xbb].toArray, 9, 7⟩) := by rfl

example (c : Cursor) (raw : ByteArray) (offset : Nat)
    (hread : readTagBytesAtV1 c.input c.offset = .ok (raw, offset)) :
    decodeTag c =
      match String.fromUTF8? raw with
      | none => .error .badTag
      | some tag =>
          if isAsciiTagV1 tag then
            .ok (tag, ⟨c.input, offset, c.nesting⟩)
          else
            .error .badTag :=
  decodeTag_eq_of_readBytesV1 c raw offset hread

example :
    (decodeU8 (start (ByteArray.mk [0x10, 0x20].toArray))).map
        (fun (byte, cursor) => (byte, remaining cursor, cursorNesting cursor)) =
      .ok (0x10, 1, 0) := by rfl

example : decodeU8 (start ByteArray.empty) = .error .truncated := by rfl

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def expectOk {α} (label : String) (r : Except SemanticWireErrorV1 α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: unexpected error {repr e}"

private def expectErr (label : String) (want : SemanticWireErrorV1)
    (r : Except SemanticWireErrorV1 α) : IO Unit :=
  match r with
  | .error e =>
    unless e == want do
      throw <| IO.userError s!"{label}: expected {repr want}, got {repr e}"
  | .ok _ => throw <| IO.userError s!"{label}: expected error {repr want}"

private def expectErrAny (label : String) (r : Except SemanticWireErrorV1 α) : IO Unit :=
  match r with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def bytesEqual (a b : ByteArray) : Bool := a == b

private def startsWithMagic (bytes : ByteArray) (magic : String) : Bool :=
  let want := magic.toUTF8.push 0
  bytes.size ≥ want.size && bytes.extract 0 want.size == want

private def emptyProgram (name : String) : IO SemanticProgramDataV1 := do
  let qn ← match parseQualifiedName #["Tests", name] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  pure {
    qualifiedName := qn
    types := #[]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables := #[]
    invariants := #[]
    requirements := { items := #[] }
  }

/-- Minimal valid `.entry` callable used to satisfy the SPEC §6 aggregate
    entry/view presence gate in structure-gated fixtures that exercise an
    unrelated phase. Its single block returns no value (`return_ none` is not
    result-type-checked per SPEC §5.1), its `result.typeId` is 0 (always in
    range for the non-empty type tables used by these fixtures), and its name
    `entry_gate` is chosen to avoid collisions with test callable names.
    `id` is supplied by the caller so it stays equal to the callable array
    index. Self-contained so it can be referenced by early builders/tests. -/
private def entryGateCallable (id : CallableIdV1) : CallableV1 :=
  {
    id
    kind := .entry
    name := some "entry_gate"
    params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions := #[],
                  terminator := .return_ none }]
    loopBounds := #[]
    invariantSteps := none
  }

/-- Bool type at TypeId 0 + one minimal `.entry` callable. This is the
    smallest structurally valid program under the SPEC §6 entry/view presence
    gate; it replaces the zero-callable `emptyProgram` as the base for
    structure-gated encoder/carrier/hash/provenance/type/value/requirements
    tests. `emptyProgram` remains available for raw transport fixtures and for
    structure negatives intentionally rejected by an earlier phase before the
    entry/view aggregate gate. -/
private def minimalValidProgram (name : String) : IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  pure { data0 with
    types := #[{ id := 0, name := none, shape := .bool }]
    callables := #[entryGateCallable 0] }

private def zeroDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }

private def oneDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (1 : UInt8)) }

private def v1_0_0 : SemVer :=
  { major := 1, minor := 0, patch := 0 }

private def emptyProvenance (name : String) : IO SemanticProvenanceV1 := do
  -- Match minimalValidProgram / emptyProgram qualifiedName shape Tests.<name>
  -- so incomplete-map / foreign-sourceHash negatives isolate join conditions
  -- rather than failing first on qualifiedName mismatch.
  let qn ← match parseQualifiedName #["Tests", name] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let schema ← match parseSchemaId semanticProvenanceSchemaIdV1 with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"parseSchemaId: {e}"
  pure {
    schema
    qualifiedName := qn
    sourceHash := zeroDigest
    semanticHash := zeroDigest
    originMap := #[]
  }

private def req (id : String) (predicates : Array RequirementPredicateV1 := #[])
    (digest : Digest := zeroDigest) : RequirementRequestV1 :=
  { id, version := v1_0_0, digest, predicates }

private def testSchemaMagicConstants : IO Unit := do
  expect (semanticProgramSchemaIdV1 == "proof-forge.semantic-program.v1")
    "program schema id"
  expect (semanticProgramMagicV1 == "pf.semantic.v1") "program magic"
  expect (semanticProvenanceSchemaIdV1 == "proof-forge.semantic-provenance.v1")
    "provenance schema id"
  expect (semanticProvenanceMagicV1 == "pf.semantic-provenance.v1") "provenance magic"
  expect (maxNesting == 256) "maxNesting is 256"

private def testEmptyProgramRoundtrip : IO Unit := do
  -- Zero-callable program: transport decode accepts and preserves it, but the
  -- SPEC §6 entry/view presence gate makes it structurally invalid, so
  -- encode, structure validation, and carrier decode all reject `.badCfg`.
  -- This zero-callable use is the raw transport fixture for this test; other
  -- `emptyProgram` uses may intentionally exercise earlier structure failures.
  let zero ← emptyProgram "EmptySem"
  let zQnB ← expectOk "zero qn" (encodeQualifiedName zero.qualifiedName)
  let zEmptyTypes ← expectOk "zero types" (encodeArray encodeTypeDeclV1 #[])
  let zEmptyConsts ← expectOk "zero consts" (encodeArray encodeConstantV1 #[])
  let zEmptyState ← expectOk "zero state" (encodeArray encodeStateDeclV1 #[])
  let zEmptyEvents ← expectOk "zero events" (encodeArray encodeEventDeclV1 #[])
  let zEmptyErrors ← expectOk "zero errors" (encodeArray encodeErrorDeclV1 #[])
  let zEmptyCallables ← expectOk "zero callables"
    (encodeArray encodeCallableV1 #[])
  let zEmptyInvs ← expectOk "zero invs" (encodeArray encodeInvariantDeclV1 #[])
  let zEmptyReqs ← expectOk "zero reqs"
    (encodeProgramRequirementsV1 { items := #[] })
  let zeroBody ← expectOk "zero body" (encodeTagged "SemanticProgram.Data" #[
    zQnB, zEmptyTypes, zEmptyConsts, zEmptyState, zEmptyEvents, zEmptyErrors,
    zEmptyCallables, zEmptyInvs, zEmptyReqs
  ])
  let zeroBytes := (semanticProgramMagicV1.toUTF8.push 0).append zeroBody
  let zeroDecoded ← expectOk "transport decode zero callables"
    (decodeSemanticProgramDataV1 zeroBytes)
  expect (zeroDecoded == zero) "transport preserves zero-callable envelope"
  expectErr "structure rejects zero callables" .badCfg
    (validateSemanticProgramStructureV1 zero)
  expectErr "encode rejects zero callables" .badCfg
    (encodeSemanticProgramDataV1 zero)
  expectErr "carrier rejects zero callables" .badCfg
    (decodeSemanticProgramV1 zeroBytes)
  -- Minimal structurally valid program (one Bool type + one entry) round-trips
  -- through encode/decode/carrier.
  let data ← minimalValidProgram "MinimalSem"
  let bytes ← expectOk "encode minimal" (encodeSemanticProgramDataV1 data)
  expect (startsWithMagic bytes semanticProgramMagicV1) "encode starts with program magic"
  let decoded ← expectOk "decode minimal" (decodeSemanticProgramDataV1 bytes)
  expect (decoded == data) "decode structural equality"
  let carrier ← expectOk "decodeSemanticProgramV1 minimal" (decodeSemanticProgramV1 bytes)
  expect (bytesEqual carrier.canonicalBytes bytes) "carrier bytes identity"
  -- trailing garbage
  expectErr "trailing" .trailingBytes
    (decodeSemanticProgramDataV1 (bytes.push 0))
  -- wrong magic
  let magicLen := semanticProgramMagicV1.toUTF8.size + 1
  expectErr "truncated magic" .truncated
    (decodeSemanticProgramDataV1 (bytes.extract 0 (magicLen - 1)))
  let badMagic := ("pf.wrong.v1".toUTF8.push 0).append
    (bytes.extract magicLen bytes.size)
  expectErr "wrong magic" .badMagic (decodeSemanticProgramDataV1 badMagic)
  -- wrong root tag
  let wrongBody ← expectOk "wrong tag body" (encodeTagged "Wrong.Root" #[])
  let wrongRoot := (semanticProgramMagicV1.toUTF8.push 0).append wrongBody
  expectErr "wrong root tag" .badTag (decodeSemanticProgramDataV1 wrongRoot)
  -- wrong fieldCount: SemanticProgram.Data with 0 fields
  let emptyFields ← expectOk "empty fields" (encodeTagged "SemanticProgram.Data" #[])
  let wrongCount := (semanticProgramMagicV1.toUTF8.push 0).append emptyFields
  expectErr "wrong fieldCount" .badFieldCount (decodeSemanticProgramDataV1 wrongCount)
  -- mutate one byte after magic
  if bytes.size > magicLen then
    let mut mutated := ByteArray.emptyWithCapacity bytes.size
    for i in [:bytes.size] do
      let b := bytes.get! i
      if i == magicLen then
        mutated := mutated.push (b ^^^ 0x01)
      else
        mutated := mutated.push b
    expectErrAny "mutated after magic" (decodeSemanticProgramV1 mutated)

/-- SPEC-SEM-WIRE-001 §6 program identity shape: a SemanticProgram root
    qualifiedName is module identity plus declaration name, so it must contain
    at least two components. Common QualifiedName itself permits one. -/
private def testProgramQualifiedNameShape : IO Unit := do
  let base ← emptyProgram "OnlyProgram"
  let singleName ← match parseQualifiedName #["OnlyProgram"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let single := { base with qualifiedName := singleName }
  expectErr "single-component program name structure" .badScalar
    (validateSemanticProgramStructureV1 single)
  expectErr "single-component program name encode" .badScalar
    (encodeSemanticProgramDataV1 single)
  -- Root shape has precedence over later structure and encoder size gates.
  let badId : SemanticProgramDataV1 := {
    single with types := #[{ id := 1, name := none, shape := .bool }]
  }
  expectErr "single program name before table id structure" .badScalar
    (validateSemanticProgramStructureV1 badId)
  expectErr "single program name before table id encode" .badScalar
    (encodeSemanticProgramDataV1 badId)
  let hugeTypes : Array TypeDeclV1 := Array.replicate (maxTableElements + 1)
    { id := 0, name := none, shape := .bool }
  let oversized : SemanticProgramDataV1 := { single with types := hugeTypes }
  expectErr "single program name before table size structure" .badScalar
    (validateSemanticProgramStructureV1 oversized)
  expectErr "single program name before table size encode" .badScalar
    (encodeSemanticProgramDataV1 oversized)
  -- Transport remains scalar-only: hand-build valid wire bytes for the
  -- common one-component QualifiedName, then ensure carrier decode rejects
  -- only on its structure-gated re-encode path.
  let qnB ← expectOk "single program qn wire" (encodeQualifiedName singleName)
  let typesB ← expectOk "single program types wire" (encodeArray encodeTypeDeclV1 #[])
  let constantsB ← expectOk "single program constants wire"
    (encodeArray encodeConstantV1 #[])
  let stateB ← expectOk "single program state wire" (encodeArray encodeStateDeclV1 #[])
  let eventsB ← expectOk "single program events wire" (encodeArray encodeEventDeclV1 #[])
  let errorsB ← expectOk "single program errors wire" (encodeArray encodeErrorDeclV1 #[])
  let callablesB ← expectOk "single program callables wire"
    (encodeArray encodeCallableV1 #[])
  let invariantsB ← expectOk "single program invariants wire"
    (encodeArray encodeInvariantDeclV1 #[])
  let reqB ← expectOk "single program requirements wire"
    (encodeProgramRequirementsV1 { items := #[] })
  let body ← expectOk "single program body wire" (encodeTagged "SemanticProgram.Data"
    #[qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB,
      invariantsB, reqB])
  let bytes := (semanticProgramMagicV1.toUTF8.push 0).append body
  let transported ← expectOk "single-component program transport"
    (decodeSemanticProgramDataV1 bytes)
  expect (transported == single) "single-component transport preserves data"
  expectErr "single-component program carrier" .badScalar
    (decodeSemanticProgramV1 bytes)
  let twoName ← match parseQualifiedName #["Example", "Program"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  -- `two`/`three` are structurally valid programs (valid multi-component name
  -- plus a minimal entry callable); `single` stays zero-callable because its
  -- single-component name fails at step 0 before the entry/view gate.
  let validBase ← minimalValidProgram "OnlyProgram"
  let two := { validBase with qualifiedName := twoName }
  let _ ← expectOk "two-component program name structure"
    (validateSemanticProgramStructureV1 two)
  let _ ← expectOk "two-component program name encode"
    (encodeSemanticProgramDataV1 two)
  let threeName ← match parseQualifiedName #["Org", "Example", "Program"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let three := { validBase with qualifiedName := threeName }
  let _ ← expectOk "three-component program name structure"
    (validateSemanticProgramStructureV1 three)
  let _ ← expectOk "three-component program name encode"
    (encodeSemanticProgramDataV1 three)
  pure ()

private def testSemanticHash : IO Unit := do
  let data1 ← minimalValidProgram "EmptySem"
  let data2 ← minimalValidProgram "EmptySem"
  let data3 ← minimalValidProgram "OtherSem"
  let bytes1 ← expectOk "enc1" (encodeSemanticProgramDataV1 data1)
  let bytes2 ← expectOk "enc2" (encodeSemanticProgramDataV1 data2)
  let bytes3 ← expectOk "enc3" (encodeSemanticProgramDataV1 data3)
  let p1 ← expectOk "dec1" (decodeSemanticProgramV1 bytes1)
  let p2 ← expectOk "dec2" (decodeSemanticProgramV1 bytes2)
  let p3 ← expectOk "dec3" (decodeSemanticProgramV1 bytes3)
  let h1 ← expectOk "hash1" (semanticHashV1 p1)
  let h2 ← expectOk "hash2" (semanticHashV1 p2)
  let h3 ← expectOk "hash3" (semanticHashV1 p3)
  expect (h1 == h2) "equal programs same hash"
  expect (h1 != h3) "different qualifiedName changes hash"
  let expected := sha256Bytes bytes1
  expect (h1 == expected) "hash is Digest of exact canonical bytes"
  expect (h1.bytes.size == 32) "digest width 32"
  expect (h1.algorithm == .sha256) "digest algorithm sha256"

private def testProvenanceEnvelope : IO Unit := do
  let p ← emptyProvenance "EmptySem"
  let bytes ← expectOk "enc provenance" (encodeSemanticProvenanceV1 p)
  expect (startsWithMagic bytes semanticProvenanceMagicV1)
    "provenance starts with magic"
  let decoded ← expectOk "dec provenance" (decodeSemanticProvenanceV1 bytes)
  expect (decoded == p) "provenance structural equality"
  expect (decoded.schema.value == semanticProvenanceSchemaIdV1)
    "provenance schema field"
  -- Incomplete empty originMap fails the join-gated digest.
  let data ← minimalValidProgram "EmptySem"
  let progBytes ← expectOk "enc prog for dig" (encodeSemanticProgramDataV1 data)
  let carrier ← expectOk "carrier for dig" (decodeSemanticProgramV1 progBytes)
  let inv : SourceNodeInventoryV1 := { sourceHash := zeroDigest, nodes := #[] }
  expectErr "prov digest requires complete join" .badProvenance
    (semanticProvenanceDigestJoinV1
      p.qualifiedName p.qualifiedName zeroDigest #[] inv carrier p)
  let badMagic := ("pf.wrong-provenance.v1".toUTF8.push 0).append
    (bytes.extract (semanticProvenanceMagicV1.toUTF8.size + 1) bytes.size)
  expectErr "prov wrong magic" .badMagic (decodeSemanticProvenanceV1 badMagic)

private def testProvenanceValidateIncompleteBad : IO Unit := do
  -- Empty originMap on an otherwise minimal program is incomplete → .badProvenance.
  let p ← emptyProvenance "EmptySem"
  let data ← minimalValidProgram "EmptySem"
  let bytes ← expectOk "enc prog" (encodeSemanticProgramDataV1 data)
  let carrier ← expectOk "carrier" (decodeSemanticProgramV1 bytes)
  let inv : SourceNodeInventoryV1 := { sourceHash := zeroDigest, nodes := #[] }
  expectErr "validate provenance incomplete empty map" .badProvenance
    (validateSemanticProvenanceJoinV1
      p.qualifiedName p.qualifiedName zeroDigest #[] inv carrier p)
  -- Foreign sourceHash still bad even with empty map (expected hash is true zero).
  let pForeign := { p with sourceHash := oneDigest }
  expectErr "validate provenance foreign sourceHash" .badProvenance
    (validateSemanticProvenanceJoinV1
      pForeign.qualifiedName pForeign.qualifiedName zeroDigest #[] inv carrier pForeign)
  -- Mutually replaced foreign inventory+provenance hashes still fail when
  -- expectedSourceHash is the authoritative snapshot hash.
  let invForeign : SourceNodeInventoryV1 := { sourceHash := oneDigest, nodes := #[] }
  let pBothForeign := { p with sourceHash := oneDigest }
  expectErr "validate mutually foreign hashes vs expected" .badProvenance
    (validateSemanticProvenanceJoinV1
      pBothForeign.qualifiedName pBothForeign.qualifiedName
      zeroDigest #[] invForeign carrier pBothForeign)

private def testDigestWireRaw32 : IO Unit := do
  -- DigestEquals predicate encodes Digest as 32 raw bytes (no sha256: prefix).
  let dig := zeroDigest
  let digB ← expectOk "enc dig" (encodeDigest dig)
  expect (digB.size == 32) "digest wire is 32 raw bytes"
  -- Must not look like ASCII "sha256:"
  let shaTag := "sha256:".toUTF8
  expect (!(digB.size ≥ shaTag.size && digB.extract 0 shaTag.size == shaTag))
    "digest wire has no sha256: prefix"
  let c := start digB
  let (decoded, c') ← expectOk "dec dig" (decodeDigest c)
  expectOk "finish dig" (finish c')
  expect (decoded == dig) "digest round-trip"

private def testInvariantsProjectionInvalid : IO Unit := do
  let invalid : SemanticProgramV1 := ⟨ByteArray.empty⟩
  expect (SemanticProgramV1.invariants invalid == #[])
    "invalid carrier invariants projection is empty"
  let data ← minimalValidProgram "EmptySem"
  let bytes ← expectOk "enc" (encodeSemanticProgramDataV1 data)
  let carrier ← expectOk "dec" (decodeSemanticProgramV1 bytes)
  expect (SemanticProgramV1.invariants carrier == #[])
    "valid program with no invariants projects empty array"

private def testMinimalNestedTypeRoundtrip : IO Unit := do
  -- Non-empty nested TypeDecl table must fully round-trip (not silent-drop).
  -- A minimal entry callable satisfies the SPEC §6 entry/view presence gate.
  let data0 ← emptyProgram "WithType"
  let data : SemanticProgramDataV1 := {
    data0 with
    types := #[{
      id := 0
      name := none
      shape := .bool
    }]
    callables := #[entryGateCallable 0]
  }
  let bytes ← expectOk "enc typed" (encodeSemanticProgramDataV1 data)
  let decoded ← expectOk "dec typed" (decodeSemanticProgramDataV1 bytes)
  expect (decoded == data) "type table round-trip"
  let _ ← expectOk "carrier typed" (decodeSemanticProgramV1 bytes)

private def testStructureGateIdIndex : IO Unit := do
  let data0 ← emptyProgram "BadId"
  let bad : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 1, name := none, shape := .bool }]
  }
  expectErr "id != index encode" .duplicate (encodeSemanticProgramDataV1 bad)
  expectErr "id != index structure" .duplicate
    (validateSemanticProgramStructureV1 bad)
  -- transport decode of a hand-built invalid carrier is not required here;
  -- structure-gated encode/decodeSemanticProgramV1 re-encode path rejects it.

private def testStructureGateShallowRef : IO Unit := do
  let data0 ← emptyProgram "BadRef"
  -- constant typeId 0 with empty types table → out of range
  let bad : SemanticProgramDataV1 := {
    data0 with
    constants := #[{
      id := 0
      name := "c"
      typeId := 0
      valueBytes := ByteArray.empty
    }]
  }
  expectErr "bad type ref encode" .badReference (encodeSemanticProgramDataV1 bad)
  expectErr "bad type ref structure" .badReference
    (validateSemanticProgramStructureV1 bad)
  -- invariant callableId out of range
  let badInv : SemanticProgramDataV1 := {
    data0 with
    invariants := #[{ id := 0, name := "I", callableId := 0 }]
  }
  expectErr "bad callable ref" .badReference
    (validateSemanticProgramStructureV1 badInv)

private def testRequirementsDomainAndOrder : IO Unit := do
  let data0 ← minimalValidProgram "Reqs"
  -- positive: known CAP domain, sorted keys
  let okData : SemanticProgramDataV1 := {
    data0 with
    requirements := {
      items := #[
        req "effect.emit",
        req "state.persistent"
      ]
    }
  }
  let _ ← expectOk "req positive encode" (encodeSemanticProgramDataV1 okData)
  expectOk "req positive structure" (validateSemanticProgramStructureV1 okData)
  -- unknown domain
  let badDomain : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "notadomain.foo"] }
  }
  expectErr "unknown domain" .badRequirement
    (validateSemanticProgramStructureV1 badDomain)
  -- single segment
  let badSeg : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "state"] }
  }
  expectErr "single segment" .badRequirement
    (validateSemanticProgramStructureV1 badSeg)
  -- empty id
  let badEmpty : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req ""] }
  }
  expectErr "empty id" .badRequirement
    (validateSemanticProgramStructureV1 badEmpty)
  -- out-of-order keys (state before effect is reverse of byte order: 'e' < 's')
  let badOrder : SemanticProgramDataV1 := {
    data0 with
    requirements := {
      items := #[
        req "state.persistent",
        req "effect.emit"
      ]
    }
  }
  expectErr "req key order" .badRequirement
    (validateSemanticProgramStructureV1 badOrder)
  -- duplicate key (same id/version/digest)
  let badDup : SemanticProgramDataV1 := {
    data0 with
    requirements := {
      items := #[req "state.persistent", req "state.persistent"]
    }
  }
  expectErr "req key dup" .badRequirement
    (validateSemanticProgramStructureV1 badDup)
  -- same id, digest order (zero before one)
  let okDigestOrder : SemanticProgramDataV1 := {
    data0 with
    requirements := {
      items := #[
        req "state.persistent" (digest := zeroDigest),
        req "state.persistent" (digest := oneDigest)
      ]
    }
  }
  expectOk "digest tie-break order" (validateSemanticProgramStructureV1 okDigestOrder)

private def testRequirementPredicates : IO Unit := do
  let data0 ← minimalValidProgram "Preds"
  -- positive sorted by name then rank
  let predsOk : Array RequirementPredicateV1 := #[
    .boolEquals "alpha" true,
    .uintAtLeast "beta" 1,
    .uintAtMost "beta" 10
  ]
  let okData : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.bound" predsOk] }
  }
  expectOk "pred order positive" (validateSemanticProgramStructureV1 okData)
  let _ ← expectOk "pred order encode" (encodeSemanticProgramDataV1 okData)
  -- name order violation
  let predsBadName : Array RequirementPredicateV1 := #[
    .uintAtLeast "zeta" 1,
    .boolEquals "alpha" true
  ]
  let badName : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.bound" predsBadName] }
  }
  expectErr "pred name order" .badRequirement
    (validateSemanticProgramStructureV1 badName)
  -- same name: rank order (uintAtLeast=0 before uintAtMost=1) reversed
  let predsBadRank : Array RequirementPredicateV1 := #[
    .uintAtMost "beta" 10,
    .uintAtLeast "beta" 1
  ]
  let badRank : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.bound" predsBadRank] }
  }
  expectErr "pred rank order" .badRequirement
    (validateSemanticProgramStructureV1 badRank)
  -- enumContains nonempty unique ascending
  let enumOk : Array RequirementPredicateV1 := #[
    .enumContains "mode" #["a", "b", "c"]
  ]
  let okEnum : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.mode" enumOk] }
  }
  expectOk "enumContains ok" (validateSemanticProgramStructureV1 okEnum)
  -- empty enumContains
  let enumEmpty : Array RequirementPredicateV1 := #[
    .enumContains "mode" #[]
  ]
  let badEmpty : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.mode" enumEmpty] }
  }
  expectErr "enumContains empty" .badRequirement
    (validateSemanticProgramStructureV1 badEmpty)
  -- unsorted enumContains
  let enumUnsorted : Array RequirementPredicateV1 := #[
    .enumContains "mode" #["b", "a"]
  ]
  let badSort : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.mode" enumUnsorted] }
  }
  expectErr "enumContains unsorted" .badRequirement
    (validateSemanticProgramStructureV1 badSort)
  -- duplicate enum value
  let enumDup : Array RequirementPredicateV1 := #[
    .enumContains "mode" #["a", "a"]
  ]
  let badDup : SemanticProgramDataV1 := {
    data0 with
    requirements := { items := #[req "value.mode" enumDup] }
  }
  expectErr "enumContains dup" .badRequirement
    (validateSemanticProgramStructureV1 badDup)

private def testNestingLimit : IO Unit := do
  -- Shared tagged path: Type.Bool at nesting == maxNesting fails enter.
  let shapeB ← expectOk "enc bool" (encodeTypeShapeV1 .bool)
  expectErr "nesting at maxNesting" .limitExceeded
    (decodeTypeShapeV1 (startAtNesting shapeB maxNesting))
  -- At maxNesting-1 a single tagged value still enters successfully.
  let (shape, cOk) ← expectOk "nesting at max-1"
    (decodeTypeShapeV1 (startAtNesting shapeB (maxNesting - 1)))
  expect (shape == .bool) "decoded Type.Bool at maxNesting-1"
  expectOk "finish nesting ok" (finish cOk)
  expect (cursorNesting cOk == maxNesting - 1)
    "nesting restored after tagged body"
  -- Nested tags share the same fuel: Type.Field → FieldSpec needs 2 frames.
  let schema ← match parseSchemaId "proof-forge.field.bn254-fr.v1" with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"schema: {e}"
  let modulus := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let fieldShape : TypeShapeV1 := .field { id := schema, modulusBE := modulus }
  let fieldB ← expectOk "enc field" (encodeTypeShapeV1 fieldShape)
  -- start at maxNesting-1: outer Type.Field enters, inner FieldSpec exceeds
  expectErr "nested FieldSpec exceeds" .limitExceeded
    (decodeTypeShapeV1 (startAtNesting fieldB (maxNesting - 1)))
  -- start at maxNesting-2: both frames fit
  let (shape2, c2) ← expectOk "nested field at max-2"
    (decodeTypeShapeV1 (startAtNesting fieldB (maxNesting - 2)))
  match shape2 with
  | .field _ => pure ()
  | _ => throw <| IO.userError "expected field shape"
  expectOk "finish nested" (finish c2)
  -- withTaggedNesting is the shared enter for all tagged readers (scope note
  -- in module header). >256 enter attempts via maxNesting synthetic depth.
  expect (maxNesting == 256) "nesting cap constant"

private def testDecodeDataNoStructureGate : IO Unit := do
  -- Transport decode accepts structurally invalid tables; structure is only
  -- on encode / decodeSemanticProgramV1 re-encode / validateSemanticProgramV1.
  let data0 ← emptyProgram "Transport"
  let bad : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 7, name := none, shape := .bool }]
  }
  -- Cannot use encode (structure-gated). Build via encode bypass: encode a
  -- valid program then we only check that structure API rejects bad data and
  -- that encode of valid still works (transport/structure split is pinned by
  -- validateSemanticProgramStructureV1 vs the module header).
  expectErr "structure rejects bad id" .duplicate
    (validateSemanticProgramStructureV1 bad)
  let good ← minimalValidProgram "Transport"
  let bytes ← expectOk "good encode" (encodeSemanticProgramDataV1 good)
  let _ ← expectOk "transport decode good" (decodeSemanticProgramDataV1 bytes)

private def testTypeShapePositives : IO Unit := do
  let data0 ← emptyProgram "TypeShapeOk"
  -- Each positive adds a minimal entry callable (result typeId 0, always in
  -- range) to satisfy the SPEC §6 entry/view presence gate; the type-shape
  -- phase runs before callable signatures so the entry does not interfere.
  -- legal uint64 + bytes 0/4096
  let okWidths : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .uint 64 },
      { id := 1, name := none, shape := .int 128 },
      { id := 2, name := none, shape := .bytes 0 },
      { id := 3, name := none, shape := .bytes 4096 },
      { id := 4, name := none, shape := .array 0 4096 }
    ]
    callables := #[entryGateCallable 0]
  }
  expectOk "widths/lengths structure" (validateSemanticProgramStructureV1 okWidths)
  let _ ← expectOk "widths/lengths encode" (encodeSemanticProgramDataV1 okWidths)
  -- named nonempty struct + enum (named declarations occupy a contiguous
  -- prefix per SPEC §5; anonymous types follow).
  let okNamed : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "Point"
        shape := .struct #[
          { name := "x", typeId := 2 },
          { name := "y", typeId := 2 }
        ]
      },
      {
        id := 1
        name := some "Color"
        shape := .enum #[
          { name := "Red", payloadTypes := #[] },
          { name := "Blue", payloadTypes := #[2] }
        ]
      },
      { id := 2, name := none, shape := .uint 32 }
    ]
    callables := #[entryGateCallable 0]
  }
  expectOk "named struct/enum structure" (validateSemanticProgramStructureV1 okNamed)
  let bytesNamed ← expectOk "named struct/enum encode" (encodeSemanticProgramDataV1 okNamed)
  let _ ← expectOk "named carrier" (decodeSemanticProgramV1 bytesNamed)
  -- exact bn254 field type
  let okField : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := none, shape := .field bn254FrFieldSpecV1 }]
    callables := #[entryGateCallable 0]
  }
  expect (bn254FrFieldSpecV1.id.value == bn254FrFieldIdV1) "field catalog id"
  expect (bn254FrFieldSpecV1.modulusBE == bn254FrModulusBEV1) "field catalog modulus"
  expect (bn254FrModulusBEV1.size == 32) "modulus is 32 bytes"
  expectOk "bn254 field structure" (validateSemanticProgramStructureV1 okField)
  let _ ← expectOk "bn254 field encode" (encodeSemanticProgramDataV1 okField)
  -- Map over Bool / UInt / Bytes keys
  let okMapPrim : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 64 },
      { id := 2, name := none, shape := .bytes 8 },
      { id := 3, name := none, shape := .map 0 1 },
      { id := 4, name := none, shape := .map 1 0 },
      { id := 5, name := none, shape := .map 2 1 }
    ]
    callables := #[entryGateCallable 0]
  }
  expectOk "map primitive keys structure" (validateSemanticProgramStructureV1 okMapPrim)
  let _ ← expectOk "map primitive keys encode" (encodeSemanticProgramDataV1 okMapPrim)
  -- Map over Struct-of-UInt key (named Key occupies prefix index 0).
  let okMapStruct : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "Key"
        shape := .struct #[{ name := "a", typeId := 1 }]
      },
      { id := 1, name := none, shape := .uint 32 },
      { id := 2, name := none, shape := .bool },
      { id := 3, name := none, shape := .map 0 2 }
    ]
    callables := #[entryGateCallable 0]
  }
  expectOk "map struct key structure" (validateSemanticProgramStructureV1 okMapStruct)
  let _ ← expectOk "map struct key encode" (encodeSemanticProgramDataV1 okMapStruct)

private def testTypeShapeNegatives : IO Unit := do
  let data0 ← emptyProgram "TypeShapeBad"
  -- name=some on bool
  let badNameSome : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := some "B", shape := .bool }]
  }
  expectErr "name some on bool" .badType
    (validateSemanticProgramStructureV1 badNameSome)
  expectErr "name some on bool encode" .badType
    (encodeSemanticProgramDataV1 badNameSome)
  -- name=none on struct
  let badNameNone : SemanticProgramDataV1 := {
    data0 with
    types := #[{
      id := 0
      name := none
      shape := .struct #[{ name := "x", typeId := 0 }]
    }]
  }
  expectErr "name none on struct" .badType
    (validateSemanticProgramStructureV1 badNameNone)
  -- empty struct / enum
  let badEmptyStruct : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := some "S", shape := .struct #[] }]
  }
  expectErr "empty struct" .badType
    (validateSemanticProgramStructureV1 badEmptyStruct)
  let badEmptyEnum : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := some "E", shape := .enum #[] }]
  }
  expectErr "empty enum" .badType
    (validateSemanticProgramStructureV1 badEmptyEnum)
  -- uint 7 / bytes 4097
  let badWidth : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := none, shape := .uint 7 }]
  }
  expectErr "uint width 7" .badType
    (validateSemanticProgramStructureV1 badWidth)
  let badBytes : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := none, shape := .bytes 4097 }]
  }
  expectErr "bytes 4097" .badType
    (validateSemanticProgramStructureV1 badBytes)
  let badArray : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .array 0 4097 }
    ]
  }
  expectErr "array 4097" .badType
    (validateSemanticProgramStructureV1 badArray)
  -- bad FieldSpec id
  let badFieldId : SemanticProgramDataV1 := {
    data0 with
    types := #[{
      id := 0
      name := none
      shape := .field {
        id := { value := "proof-forge.field.unknown.v1" }
        modulusBE := bn254FrModulusBEV1
      }
    }]
  }
  expectErr "bad field id" .badType
    (validateSemanticProgramStructureV1 badFieldId)
  -- correct id + zero modulus
  let zeroMod := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let badFieldMod : SemanticProgramDataV1 := {
    data0 with
    types := #[{
      id := 0
      name := none
      shape := .field { id := bn254FrFieldSpecV1.id, modulusBE := zeroMod }
    }]
  }
  expectErr "zero modulus" .badType
    (validateSemanticProgramStructureV1 badFieldMod)
  -- duplicate field / variant names (named S occupies prefix index 0).
  let badDupField : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "S"
        shape := .struct #[
          { name := "x", typeId := 1 },
          { name := "x", typeId := 1 }
        ]
      },
      { id := 1, name := none, shape := .uint 8 }
    ]
  }
  expectErr "dup field names" .duplicate
    (validateSemanticProgramStructureV1 badDupField)
  let badDupVariant : SemanticProgramDataV1 := {
    data0 with
    types := #[{
      id := 0
      name := some "E"
      shape := .enum #[
        { name := "A", payloadTypes := #[] },
        { name := "A", payloadTypes := #[] }
      ]
    }]
  }
  expectErr "dup variant names" .duplicate
    (validateSemanticProgramStructureV1 badDupVariant)
  -- Map with Option / Array / Unit / Enum key
  let badMapOption : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .option 0 },
      { id := 2, name := none, shape := .map 1 0 }
    ]
  }
  expectErr "map option key" .badType
    (validateSemanticProgramStructureV1 badMapOption)
  let badMapArray : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .array 0 1 },
      { id := 2, name := none, shape := .map 1 0 }
    ]
  }
  expectErr "map array key" .badType
    (validateSemanticProgramStructureV1 badMapArray)
  let badMapUnit : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .unit },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .map 0 1 }
    ]
  }
  expectErr "map unit key" .badType
    (validateSemanticProgramStructureV1 badMapUnit)
  let badMapEnum : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "E"
        shape := .enum #[{ name := "A", payloadTypes := #[] }]
      },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .map 0 1 }
    ]
  }
  expectErr "map enum key" .badType
    (validateSemanticProgramStructureV1 badMapEnum)
  -- Map key = named Struct whose field type is illegal: exercises the recursive
  -- `.struct` branch of checkLegalMapKeyTypeV1 (flat Option/Array/Unit/Enum
  -- above would pass even if field walk were dropped). Keep Struct-of-UInt
  -- positive in testTypeShapePositives.
  let badMapStructOption : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "BadKey"
        shape := .struct #[{ name := "inner", typeId := 2 }]
      },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .option 1 },
      { id := 3, name := none, shape := .map 0 1 }
    ]
  }
  expectErr "map struct-of-option key" .badType
    (validateSemanticProgramStructureV1 badMapStructOption)
  expectErr "map struct-of-option key encode" .badType
    (encodeSemanticProgramDataV1 badMapStructOption)
  let badMapStructField : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "FieldKey"
        shape := .struct #[{ name := "f", typeId := 1 }]
      },
      { id := 1, name := none, shape := .field bn254FrFieldSpecV1 },
      { id := 2, name := none, shape := .bool },
      { id := 3, name := none, shape := .map 0 2 }
    ]
  }
  expectErr "map struct-of-field key" .badType
    (validateSemanticProgramStructureV1 badMapStructField)
  expectErr "map struct-of-field key encode" .badType
    (encodeSemanticProgramDataV1 badMapStructField)
  let badMapStructMap : SemanticProgramDataV1 := {
    data0 with
    types := #[
      {
        id := 0
        name := some "MapKey"
        shape := .struct #[{ name := "m", typeId := 3 }]
      },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .uint 8 },
      { id := 3, name := none, shape := .map 1 2 },
      { id := 4, name := none, shape := .map 0 1 }
    ]
  }
  expectErr "map struct-of-map key" .badType
    (validateSemanticProgramStructureV1 badMapStructMap)
  expectErr "map struct-of-map key encode" .badType
    (encodeSemanticProgramDataV1 badMapStructMap)

private def testTypeShapeRegressionTransportAndNesting : IO Unit := do
  -- Nesting fuel path still encodes zero-modulus Field shape outside program
  -- structure (encodeTypeShapeV1 does not run FieldSpec catalog).
  let zeroMod := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let fieldShape : TypeShapeV1 :=
    .field { id := bn254FrFieldSpecV1.id, modulusBE := zeroMod }
  let fieldB ← expectOk "enc zero-mod field shape" (encodeTypeShapeV1 fieldShape)
  let (decoded, c) ← expectOk "dec zero-mod field shape" (decodeTypeShapeV1 (start fieldB))
  expectOk "finish zero-mod field" (finish c)
  match decoded with
  | .field spec =>
      expect (spec.modulusBE == zeroMod) "zero modulus preserved on shape wire"
  | _ => throw <| IO.userError "expected field shape"
  -- Transport decode remains structure-free: bad type name still not gated
  -- at decodeSemanticProgramDataV1 (only via encode / structure / carrier).
  let data0 ← emptyProgram "TransportType"
  let badNamed : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := some "B", shape := .bool }]
  }
  expectErr "structure gates named bool" .badType
    (validateSemanticProgramStructureV1 badNamed)
  expectErr "encode gates named bool" .badType
    (encodeSemanticProgramDataV1 badNamed)

/-! ### Canonical valueBytes (SPEC §5) -/

private def u32le (n : Nat) : ByteArray :=
  encodeU32le (UInt32.ofNat n)

private def leBytesFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def beBytesToNat (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  for i in [:bytes.size] do
    n := n * 256 + (bytes.get! i).toNat
  pure n

private def constOf (id : ConstantIdV1) (name : String) (typeId : TypeIdV1)
    (valueBytes : ByteArray) : ConstantV1 :=
  { id, name, typeId, valueBytes }

/-- Exact ContextRead catalog requirement row (sole wire-owned key).
    Fixtures that use `.contextRead` must pass this explicitly via
    `programWithTypes` / `programWithTypesWithReqs` — no silent injection. -/
private def exactContextRequirementRowV1 : IO RequirementRequestV1 :=
  match unixTimeSecondsContextRequirementV1 with
  | .ok row => pure row
  | .error e => throw <| IO.userError s!"ContextRead requirement: {e}"

/-- Exact Commit disclosure requirement row. Fixtures that use `.commit` must
    pass this explicitly — no silent injection. -/
private def exactCommitRequirementRowV1 : IO RequirementRequestV1 :=
  match commitmentDisclosureRequirementV1 with
  | .ok row => pure row
  | .error e => throw <| IO.userError s!"Commit requirement: {e}"

/-- Structure-gated program builder. Appends a minimal valid `.entry` callable
    (`entryGateCallable`) so fixtures satisfy the SPEC §6 aggregate entry/view
    presence gate while exercising an unrelated phase. The appended entry's
    `id` equals `callables.size` (array index), and errors in the supplied
    callables still fire first because all earlier gates run in source order.
    Requirements default to empty — fixtures that use `.contextRead` /
    `.commit` must pass exact rows via `programWithTypesWithReqs` (or the
    `requirements` parameter) so CFG suites do not become requirements-valid
    by accident. Tests that need to exercise the entry/view presence gate
    itself use `rawProgramWithTypes`, which does not append. -/
private def programWithTypes (name : String) (types : Array TypeDeclV1)
    (constants : Array ConstantV1 := #[])
    (callables : Array CallableV1 := #[])
    (requirements : Array RequirementRequestV1 := #[]) :
    IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  let entryId : CallableIdV1 := callables.size.toUInt32
  pure { data0 with
    types := types
    constants := constants
    callables := callables.push (entryGateCallable entryId)
    requirements := { items := requirements } }

/-- Same as `programWithTypes` but makes the requirement-row argument
    mandatory so ContextRead/Commit fixtures document intent at the call
    site. -/
private def programWithTypesWithReqs (name : String) (types : Array TypeDeclV1)
    (requirements : Array RequirementRequestV1)
    (constants : Array ConstantV1 := #[])
    (callables : Array CallableV1 := #[]) : IO SemanticProgramDataV1 :=
  programWithTypes name types constants callables requirements

private def minimalCallableLiteral (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CallableV1 :=
  {
    id := 0
    kind := .pureFn
    name := some "litFn"
    params := #[]
    result := { typeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId }
        op := .literal typeId valueBytes
      }]
      terminator := .return_ (some 0)
    }]
    loopBounds := #[]
    invariantSteps := none
  }

private def minimalCallableSwitch (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CallableV1 :=
  {
    id := 0
    kind := .pureFn
    name := some "swFn"
    params := #[]
    result := { typeId, visibility := .public_ }
    entryBlock := 0
    blocks := #[{
      id := 0
      params := #[]
      instructions := #[{
        result := some { valueId := 0, typeId }
        op := .literal typeId valueBytes
      }]
      terminator := .switch 0 #[{
        typeId
        valueBytes
        target := { blockId := 0, args := #[] }
      }] none
    }]
    -- Single-block switch case target is block 0 itself → a self back edge
    -- (0→0); declared here so the loopBounds back-edge coverage gate passes.
    loopBounds := #[{ header := 0, backEdgeFrom := 0, maxIterations := 1 }]
    invariantSteps := none
  }

private def expectValueOk (label : String) (data : SemanticProgramDataV1) : IO Unit := do
  expectOk s!"{label} structure" (validateSemanticProgramStructureV1 data)
  let bytes ← expectOk s!"{label} encode" (encodeSemanticProgramDataV1 data)
  let _ ← expectOk s!"{label} carrier" (decodeSemanticProgramV1 bytes)

private def expectValueNonCanonical (label : String) (data : SemanticProgramDataV1) :
    IO Unit := do
  expectErr s!"{label} structure" .nonCanonical
    (validateSemanticProgramStructureV1 data)
  expectErr s!"{label} encode" .nonCanonical
    (encodeSemanticProgramDataV1 data)

private def testValueBytesPositives : IO Unit := do
  -- Bool true/false constants
  let boolTypes : Array TypeDeclV1 := #[{ id := 0, name := none, shape := .bool }]
  let boolFalse ← programWithTypes "VBBoolF" boolTypes
    #[constOf 0 "f" 0 (ByteArray.mk #[0])]
  let boolTrue ← programWithTypes "VBBoolT" boolTypes
    #[constOf 0 "t" 0 (ByteArray.mk #[1])]
  expectValueOk "bool false" boolFalse
  expectValueOk "bool true" boolTrue
  -- UInt8 / UInt64
  let u8 ← programWithTypes "VBU8"
    #[{ id := 0, name := none, shape := .uint 8 }]
    #[constOf 0 "u" 0 (ByteArray.mk #[0x2a])]
  let u64 ← programWithTypes "VBU64"
    #[{ id := 0, name := none, shape := .uint 64 }]
    #[constOf 0 "u" 0 (ByteArray.mk #[1, 0, 0, 0, 0, 0, 0, 0])]
  expectValueOk "uint8" u8
  expectValueOk "uint64" u64
  -- Int8 negative (-1 = 0xFF)
  let i8 ← programWithTypes "VBI8"
    #[{ id := 0, name := none, shape := .int 8 }]
    #[constOf 0 "n" 0 (ByteArray.mk #[0xff])]
  expectValueOk "int8 neg" i8
  -- Unit empty
  let unitP ← programWithTypes "VBUnit"
    #[{ id := 0, name := none, shape := .unit }]
    #[constOf 0 "u" 0 ByteArray.empty]
  expectValueOk "unit" unitP
  -- Bytes length 0 and exact N=3
  let bytes0 ← programWithTypes "VBBytes0"
    #[{ id := 0, name := none, shape := .bytes 0 }]
    #[constOf 0 "b" 0 ByteArray.empty]
  let bytes3 ← programWithTypes "VBBytes3"
    #[{ id := 0, name := none, shape := .bytes 3 }]
    #[constOf 0 "b" 0 (ByteArray.mk #[1, 2, 3])]
  expectValueOk "bytes0" bytes0
  expectValueOk "bytes3" bytes3
  -- Option none / some Bool
  let optTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .option 0 }
  ]
  let optNone ← programWithTypes "VBOptN" optTypes
    #[constOf 0 "n" 1 (ByteArray.mk #[0])]
  let optSome ← programWithTypes "VBOptS" optTypes
    #[constOf 0 "s" 1 (ByteArray.mk #[1, 1])]
  expectValueOk "option none" optNone
  expectValueOk "option some bool" optSome
  -- bn254 Field 0 and p-1
  let fieldTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .field bn254FrFieldSpecV1 }]
  let field0 ← programWithTypes "VBField0" fieldTypes
    #[constOf 0 "z" 0 (ByteArray.mk (Array.replicate 32 (0 : UInt8)))]
  let p := beBytesToNat bn254FrModulusBEV1
  let fieldPm1 ← programWithTypes "VBFieldPm1" fieldTypes
    #[constOf 0 "m" 0 (leBytesFromNat (p - 1) 32)]
  expectValueOk "field 0" field0
  expectValueOk "field p-1" fieldPm1
  -- named Struct of two UInt8 (named Pair occupies prefix index 0).
  let structTypes : Array TypeDeclV1 := #[
    {
      id := 0
      name := some "Pair"
      shape := .struct #[
        { name := "a", typeId := 1 },
        { name := "b", typeId := 1 }
      ]
    },
    { id := 1, name := none, shape := .uint 8 }
  ]
  let structP ← programWithTypes "VBStruct" structTypes
    #[constOf 0 "p" 0 (ByteArray.mk #[0x10, 0x20])]
  expectValueOk "struct two u8" structP
  -- Enum variant 0 empty + variant with UInt8 payload (named E occupies
  -- prefix index 0).
  let enumTypes : Array TypeDeclV1 := #[
    {
      id := 0
      name := some "E"
      shape := .enum #[
        { name := "A", payloadTypes := #[] },
        { name := "B", payloadTypes := #[1] }
      ]
    },
    { id := 1, name := none, shape := .uint 8 }
  ]
  let enum0 ← programWithTypes "VBEnum0" enumTypes
    #[constOf 0 "a" 0 (u32le 0)]
  let enum1 ← programWithTypes "VBEnum1" enumTypes
    #[constOf 0 "b" 0 ((u32le 1).append (ByteArray.mk #[0x99]))]
  expectValueOk "enum v0 empty" enum0
  expectValueOk "enum v1 payload" enum1
  -- Map Bool→UInt8 empty and one sorted entry (false→7)
  let mapTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .map 0 1 }
  ]
  let mapEmpty ← programWithTypes "VBMapE" mapTypes
    #[constOf 0 "m" 2 (u32le 0)]
  let mapOneBytes :=
    (((((u32le 1).append (u32le 1)).append (ByteArray.mk #[0])).append
      (u32le 1)).append (ByteArray.mk #[7]))
  let mapOne ← programWithTypes "VBMap1" mapTypes
    #[constOf 0 "m" 2 mapOneBytes]
  expectValueOk "map empty" mapEmpty
  expectValueOk "map one entry" mapOne
  -- Array UInt8 length 2
  let arrTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .uint 8 },
    { id := 1, name := none, shape := .array 0 2 }
  ]
  let arrP ← programWithTypes "VBArr" arrTypes
    #[constOf 0 "a" 1 (ByteArray.mk #[3, 4])]
  expectValueOk "array u8x2" arrP
  -- Op.Literal shares decoder
  let litProg ← programWithTypes "VBLit" boolTypes #[]
    #[minimalCallableLiteral 0 (ByteArray.mk #[1])]
  expectValueOk "op.literal bool" litProg
  -- SwitchCase shares decoder
  let swProg ← programWithTypes "VBSw" boolTypes #[]
    #[minimalCallableSwitch 0 (ByteArray.mk #[0])]
  expectValueOk "switch case bool" swProg

private def testValueBytesNegatives : IO Unit := do
  let boolTypes : Array TypeDeclV1 := #[{ id := 0, name := none, shape := .bool }]
  -- Bool 02
  let badBool ← programWithTypes "VBBadBool" boolTypes
    #[constOf 0 "b" 0 (ByteArray.mk #[2])]
  expectValueNonCanonical "bool 02" badBool
  -- UInt64 wrong length
  let badU64 ← programWithTypes "VBBadU64"
    #[{ id := 0, name := none, shape := .uint 64 }]
    #[constOf 0 "u" 0 (ByteArray.mk #[1, 2, 3])]
  expectValueNonCanonical "uint64 short" badU64
  -- Bytes N wrong length
  let badBytes ← programWithTypes "VBBadBytes"
    #[{ id := 0, name := none, shape := .bytes 2 }]
    #[constOf 0 "b" 0 (ByteArray.mk #[1])]
  expectValueNonCanonical "bytes wrong len" badBytes
  -- Option marker 02
  let optTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .option 0 }
  ]
  let badOpt ← programWithTypes "VBBadOpt" optTypes
    #[constOf 0 "o" 1 (ByteArray.mk #[2])]
  expectValueNonCanonical "option marker 02" badOpt
  -- Field ≥ modulus (p itself as LE)
  let fieldTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .field bn254FrFieldSpecV1 }]
  let p := beBytesToNat bn254FrModulusBEV1
  let badField ← programWithTypes "VBBadField" fieldTypes
    #[constOf 0 "f" 0 (leBytesFromNat p 32)]
  expectValueNonCanonical "field >= p" badField
  -- Map unsorted keys (true before false)
  let mapTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .map 0 1 }
  ]
  -- true-before-false is reverse unsigned-lex order
  let unsorted :=
    (((((((((u32le 2).append (u32le 1)).append (ByteArray.mk #[1])).append
      (u32le 1)).append (ByteArray.mk #[1])).append (u32le 1)).append
      (ByteArray.mk #[0])).append (u32le 1)).append (ByteArray.mk #[2]))
  let badUnsorted ← programWithTypes "VBMapUnsorted" mapTypes
    #[constOf 0 "m" 2 unsorted]
  expectValueNonCanonical "map unsorted" badUnsorted
  -- Map duplicate keys
  let dupKeys :=
    (((((((((u32le 2).append (u32le 1)).append (ByteArray.mk #[0])).append
      (u32le 1)).append (ByteArray.mk #[1])).append (u32le 1)).append
      (ByteArray.mk #[0])).append (u32le 1)).append (ByteArray.mk #[2]))
  let badDup ← programWithTypes "VBMapDup" mapTypes
    #[constOf 0 "m" 2 dupKeys]
  expectValueNonCanonical "map dup keys" badDup
  -- Map keyLen not exact for key type (keyLen=2 for Bool)
  let badKeyLen :=
    (((((u32le 1).append (u32le 2)).append (ByteArray.mk #[0, 0])).append
      (u32le 1)).append (ByteArray.mk #[7]))
  let badKL ← programWithTypes "VBMapKL" mapTypes
    #[constOf 0 "m" 2 badKeyLen]
  expectValueNonCanonical "map keyLen not exact" badKL
  -- Enum OOB variant
  let enumTypes : Array TypeDeclV1 := #[{
    id := 0
    name := some "E"
    shape := .enum #[{ name := "A", payloadTypes := #[] }]
  }]
  let badEnum ← programWithTypes "VBEnumOOB" enumTypes
    #[constOf 0 "e" 0 (u32le 1)]
  expectValueNonCanonical "enum OOB" badEnum
  -- trailing extra byte on otherwise-valid Bool true
  let trailing ← programWithTypes "VBTrail" boolTypes
    #[constOf 0 "b" 0 (ByteArray.mk #[1, 0])]
  expectValueNonCanonical "trailing extra" trailing
  -- truncated payload (empty for Bool)
  let trunc ← programWithTypes "VBTrunc" boolTypes
    #[constOf 0 "b" 0 ByteArray.empty]
  expectValueNonCanonical "truncated bool" trunc
  -- Literal + SwitchCase negative paths
  let badLit ← programWithTypes "VBBadLit" boolTypes #[]
    #[minimalCallableLiteral 0 (ByteArray.mk #[2])]
  expectValueNonCanonical "literal bad bool" badLit
  let badSw ← programWithTypes "VBBadSw" boolTypes #[]
    #[minimalCallableSwitch 0 (ByteArray.mk #[2])]
  expectValueNonCanonical "switch bad bool" badSw

private def testValueBytesTransportRegression : IO Unit := do
  -- Hand-assemble transport with garbage constant valueBytes; structure-free
  -- decodeSemanticProgramDataV1 must accept it. Structure/encode reject.
  let data0 ← emptyProgram "VBTransport"
  let types : Array TypeDeclV1 := #[{ id := 0, name := none, shape := .bool }]
  let garbage : ByteArray := ByteArray.mk #[0x02, 0xff]
  let constants : Array ConstantV1 := #[constOf 0 "g" 0 garbage]
  let qnB ← expectOk "qn" (encodeQualifiedName data0.qualifiedName)
  let typesB ← expectOk "types" (encodeArray encodeTypeDeclV1 types)
  let constantsB ← expectOk "consts" (encodeArray encodeConstantV1 constants)
  let emptyArr ← expectOk "empty arr" (encodeArray encodeStateDeclV1 #[])
  let emptyEvents ← expectOk "empty events" (encodeArray encodeEventDeclV1 #[])
  let emptyErrors ← expectOk "empty errors" (encodeArray encodeErrorDeclV1 #[])
  let emptyCallables ← expectOk "empty callables" (encodeArray encodeCallableV1 #[])
  let emptyInvariants ← expectOk "empty inv" (encodeArray encodeInvariantDeclV1 #[])
  let reqB ← expectOk "reqs" (encodeProgramRequirementsV1 { items := #[] })
  let body ← expectOk "body" (encodeTagged "SemanticProgram.Data" #[
    qnB, typesB, constantsB, emptyArr, emptyEvents, emptyErrors,
    emptyCallables, emptyInvariants, reqB
  ])
  let magic := semanticProgramMagicV1.toUTF8.push 0
  let bytes := magic.append body
  let decoded ← expectOk "transport garbage valueBytes"
    (decodeSemanticProgramDataV1 bytes)
  expect (decoded.constants.size == 1) "constant present on transport"
  match decoded.constants[0]? with
  | some c => expect (c.valueBytes == garbage) "garbage preserved"
  | none => throw <| IO.userError "expected constant at 0"
  expectErr "structure rejects garbage valueBytes" .nonCanonical
    (validateSemanticProgramStructureV1 decoded)
  expectErr "encode rejects garbage valueBytes" .nonCanonical
    (encodeSemanticProgramDataV1 decoded)
  -- Minimal structurally valid program still green; incomplete provenance
  -- (empty originMap) still fails the complete join. (Zero-callable
  -- `emptyProgram` is no longer structurally valid under the SPEC §6
  -- entry/view presence gate.)
  let empty ← minimalValidProgram "VBEmptyStill"
  expectValueOk "minimal still" empty
  let p ← emptyProvenance "VBEmptyStill"
  let inv : SourceNodeInventoryV1 := { sourceHash := zeroDigest, nodes := #[] }
  let enc ← expectOk "enc minimal" (encodeSemanticProgramDataV1 empty)
  let carrier ← expectOk "carrier minimal" (decodeSemanticProgramV1 enc)
  expectErr "provenance incomplete still bad" .badProvenance
    (validateSemanticProvenanceJoinV1
      p.qualifiedName p.qualifiedName zeroDigest #[] inv carrier p)

/-! ### CFG shape + reachability + block-param arity + loopBounds (D2-06 CFG layers)

    Per-callable: entryBlock == 0, block id == array index, Switch cases
    nonempty, terminator target range, total reachability from entry,
    jump/branch/switch target arg arity == target block params, and loopBounds
    back-edge coverage (exact coverage of every CFG back edge,
    `(header,backEdgeFrom)` unique ascending, maxIterations <= 4096, all
    `.badCfg`). Later sections in this same suite pin SSA, dominance,
    block-param/terminator typing, EffectId assignment, and per-op contracts. -/

private def cfgBoolTypes : Array TypeDeclV1 :=
  #[{ id := 0, name := none, shape := .bool }]

private def cfgLoopBound (header backEdgeFrom : BlockIdV1)
    (maxIterations : UInt32) : LoopBoundV1 :=
  { header, backEdgeFrom, maxIterations }

private def cfgCallable (blocks : Array BlockV1) (entryBlock : BlockIdV1 := 0)
    (loopBounds : Array LoopBoundV1 := #[]) : CallableV1 :=
  {
    id := 0
    kind := .pureFn
    name := some "f"
    params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock
    blocks
    loopBounds
    invariantSteps := none
  }

private def cfgBlock (id : BlockIdV1) (terminator : TerminatorV1) :
    BlockV1 :=
  { id, params := #[], instructions := #[], terminator }

private def cfgJumpTarget (blockId : BlockIdV1) : JumpTargetV1 :=
  { blockId, args := #[] }

/-- Callable whose sole block is a valid self back-edge with its exact bound. -/
private def cfgCallableKindNameLoop (kind : CallableKindV1) (name : Option String)
    (resultTypeId : TypeIdV1 := 0) : CallableV1 :=
  {
    (cfgCallable #[cfgBlock 0 (.jump (cfgJumpTarget 0))]
      (loopBounds := #[cfgLoopBound 0 0 1])) with
      kind, name, result := { typeId := resultTypeId, visibility := .public_ }
  }

/-- Single empty-block callable fixture. For invariant roots the exact step
    count is `1 + (0 instructions + 1 terminator) = 2`; other kinds are outside
    the focused root-presence contract and retain `none`. -/
private def cfgCallableKindName (kind : CallableKindV1) (name : Option String)
    (resultTypeId : TypeIdV1 := 0) : CallableV1 :=
  { (cfgCallable #[cfgBlock 0 (.return_ none)]) with
    kind
    name
    result := { typeId := resultTypeId, visibility := .public_ }
    invariantSteps := if kind == .invariant then some 2 else none }

/-- Block with explicit params (for block-param arity tests). All params use
    typeId 0 (Bool, present in cfgBoolTypes) to avoid unrelated badReference. -/
private def cfgBlockWithParams (id : BlockIdV1)
    (params : Array BlockParameterV1) (terminator : TerminatorV1) : BlockV1 :=
  { id, params, instructions := #[], terminator }

/-- JumpTarget with explicit arg ValueIds (for block-param arity tests). -/
private def cfgJumpTargetWithArgs (blockId : BlockIdV1)
    (args : Array ValueIdV1) : JumpTargetV1 :=
  { blockId, args }

/-- Bool block param at `valueId` (typeId 0 = Bool in cfgBoolTypes). -/
private def cfgBoolParam (valueId : ValueIdV1) : BlockParameterV1 :=
  { valueId, typeId := 0 }

/-- ValueDef at `valueId` with typeId 0 (Bool in cfgBoolTypes). -/
private def cfgValueDef (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 0 }

/-- Instruction with optional result and given op. -/
private def cfgInstr (result? : Option ValueDefV1) (op : SemanticOpV1) :
    InstructionV1 :=
  { result := result?, op }

/-- Bool literal op at typeId 0 with a single 0/1 byte (no ValueId uses). -/
private def cfgBoolLit (byte : UInt8) : SemanticOpV1 :=
  .literal 0 (ByteArray.mk #[byte])

/-! ### step h/i fixtures (Bool + UInt8 types)

    Two-type fixture: typeId 0 = Bool, typeId 1 = UInt8. Used by
    testCfgBlockParamTypeAndTerminatorTyping for branch-cond Bool, switch
    case == scrutinee, target arg type, and return-value type checks. -/

private def cfgUint8Types : Array TypeDeclV1 :=
  #[{ id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 }]

/-- UInt8 block param at `valueId` (typeId 1 = UInt8 in cfgUint8Types). -/
private def cfgUint8Param (valueId : ValueIdV1) : BlockParameterV1 :=
  { valueId, typeId := 1 }

/-- ValueDef at `valueId` with typeId 1 (UInt8 in cfgUint8Types). -/
private def cfgUint8ValueDef (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 1 }

/-- UInt8 literal op at typeId 1 with a single byte (UInt8 canonical valueBytes
    per SPEC §5 = single byte). No ValueId uses. -/
private def cfgUint8Lit (byte : UInt8) : SemanticOpV1 :=
  .literal 1 (ByteArray.mk #[byte])

/-- UInt32 literal op at typeId 2 with 4 little-endian bytes (UInt32
    canonical valueBytes per SPEC §5). No ValueId uses. Used by indexGet
    Array/Bytes index and binary shift rhs fixtures. -/
private def cfgUInt32Lit (value : UInt32) : SemanticOpV1 :=
  .literal 2 (leBytesFromNat value.toNat 4)

/-- ValueDef at `valueId` with typeId 2 (UInt32). -/
private def cfgUInt32ValueDef (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 2 }

/-- Block with explicit instructions plus terminator. -/
private def cfgBlockInstrs (id : BlockIdV1) (instructions : Array InstructionV1)
    (terminator : TerminatorV1) : BlockV1 :=
  { id, params := #[], instructions, terminator }

/-- Callable with explicit params (for SSA callable-param tests). -/
private def cfgCallableWithParams (params : Array ParameterV1)
    (blocks : Array BlockV1) (entryBlock : BlockIdV1 := 0)
    (loopBounds : Array LoopBoundV1 := #[]) : CallableV1 :=
  {
    id := 0
    kind := .pureFn
    name := some "f"
    params
    result := { typeId := 0, visibility := .public_ }
    entryBlock
    blocks
    loopBounds
    invariantSteps := none
  }

private def expectCfgOk (label : String) (data : SemanticProgramDataV1) :
    IO Unit := do
  expectOk s!"{label} structure" (validateSemanticProgramStructureV1 data)
  let _ ← expectOk s!"{label} encode" (encodeSemanticProgramDataV1 data)

private def expectCfgErr (label : String) (data : SemanticProgramDataV1) :
    IO Unit := do
  expectErr s!"{label} structure" .badCfg
    (validateSemanticProgramStructureV1 data)
  expectErr s!"{label} encode" .badCfg (encodeSemanticProgramDataV1 data)

/-- Structure + encode dual path expecting a specific error code (used by
    step h `.badReference` cases). -/
private def expectCfgErrCode (label : String) (code : SemanticWireErrorV1)
    (data : SemanticProgramDataV1) : IO Unit := do
  expectErr s!"{label} structure" code
    (validateSemanticProgramStructureV1 data)
  expectErr s!"{label} encode" code (encodeSemanticProgramDataV1 data)

/-- Pin the stable CFG/invariant subphase even when competing failures share
    the same public `.badCfg` value. The production structure gate consumes
    this exact phase-aware helper and erases only the phase. -/
private def expectCfgInvariantPhase (label : String)
    (phase : CfgInvariantValidationPhaseV1) (code : SemanticWireErrorV1)
    (data : SemanticProgramDataV1) : IO Unit := do
  match validateCfgInvariantPhasesV1 data with
  | .ok () =>
      throw <| IO.userError s!"{label}: expected phase failure {repr phase}"
  | .error failure =>
      unless failure.phase == phase do
        throw <| IO.userError
          s!"{label}: expected phase {repr phase}, got {repr failure.phase}"
      unless failure.error == code do
        throw <| IO.userError
          s!"{label}: expected error {repr code}, got {repr failure.error}"

/-- Pin the stable TypeKey subphase even when the primitive-leaf and
    recursive-anonymous subphases share the same public `.nonCanonical`
    value. The production structure gate consumes this exact phase-aware
    helper and erases only the phase. -/
private def expectTypeKeyPhase (label : String)
    (phase : TypeKeyValidationPhaseV1) (code : SemanticWireErrorV1)
    (types : Array TypeDeclV1) : IO Unit := do
  match validateTypeKeyPhasesV1 types with
  | .ok () =>
      throw <| IO.userError s!"{label}: expected phase failure {repr phase}"
  | .error failure =>
      unless failure.phase == phase do
        throw <| IO.userError
          s!"{label}: expected phase {repr phase}, got {repr failure.phase}"
      unless failure.error == code do
        throw <| IO.userError
          s!"{label}: expected error {repr code}, got {repr failure.error}"

/-- Pin callable-signature precedence when neighboring checks share the public
    `.badCfg` wire error. The production structure gate consumes this exact
    non-serialized helper and erases only its phase. -/
private def expectCallableSignaturePhase (label : String)
    (phase : CallableSignatureValidationPhaseV1)
    (code : SemanticWireErrorV1) (data : SemanticProgramDataV1) : IO Unit := do
  match validateCallableSignaturePhasesV1 data.types data.callables with
  | .ok () =>
      throw <| IO.userError s!"{label}: expected phase failure {repr phase}"
  | .error failure =>
      unless failure.phase == phase do
        throw <| IO.userError
          s!"{label}: expected phase {repr phase}, got {repr failure.phase}"
      unless failure.error == code do
        throw <| IO.userError
          s!"{label}: expected error {repr code}, got {repr failure.error}"

/-- SPEC-SEM-WIRE-001 §5 gives every anonymous primitive shape one structural
    TypeKey/TypeId. This bounded slice covers leaf primitive keys only; the
    recursive anonymous container structural-class uniqueness and cycle-
    rejection algorithm is pinned by
    `testRecursiveAnonymousTypeKeyUniqueness`. Every case drives both the
    production structure gate and the structure-gated encoder. -/
private def testPrimitiveAnonymousTypeKeyUniqueness : IO Unit := do
  let singleton ← programWithTypes "PrimitiveTypeKeySingleton"
    #[{ id := 0, name := none, shape := .bool }]
  expectCfgOk "singleton primitive table fast path" singleton
  let distinctTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .uint 16 },
    { id := 3, name := none, shape := .int 8 },
    { id := 4, name := none, shape := .int 16 },
    { id := 5, name := none, shape := .principal },
    { id := 6, name := none, shape := .unit },
    { id := 7, name := none, shape := .bytes 0 },
    { id := 8, name := none, shape := .bytes 1 },
    { id := 9, name := none, shape := .field bn254FrFieldSpecV1 }
  ]
  let p0 ← programWithTypes "PrimitiveTypeKeyP0Distinct" distinctTypes
  expectCfgOk "P0 distinct primitive anonymous shapes" p0
  let expectDuplicate (name label : String) (shape : TypeShapeV1) : IO Unit := do
    let data ← programWithTypes name #[
      { id := 0, name := none, shape },
      { id := 1, name := none, shape }
    ]
    expectCfgErrCode label .nonCanonical data
  expectDuplicate "PrimitiveTypeKeyN1Bool" "N1 duplicate Bool" .bool
  expectDuplicate "PrimitiveTypeKeyN2UInt" "N2 duplicate UInt width" (.uint 32)
  expectDuplicate "PrimitiveTypeKeyN3Int" "N3 duplicate Int width" (.int 64)
  expectDuplicate "PrimitiveTypeKeyN4Principal" "N4 duplicate Principal" .principal
  expectDuplicate "PrimitiveTypeKeyN5Unit" "N5 duplicate Unit" .unit
  expectDuplicate "PrimitiveTypeKeyN6Bytes" "N6 duplicate Bytes length" (.bytes 8)
  expectDuplicate "PrimitiveTypeKeyN7Field" "N7 duplicate exact FieldSpec"
    (.field bn254FrFieldSpecV1)
  -- Table id/index validation precedes every type graph check.
  let n8 ← programWithTypes "PrimitiveTypeKeyN8TableIdFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 7, name := none, shape := .bool }
  ]
  expectCfgErrCode "N8 table id before primitive uniqueness" .duplicate n8
  -- Every shallow TypeId reference is checked before primitive interning.
  let n9 ← programWithTypes "PrimitiveTypeKeyN9ReferenceFirst" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "x", typeId := 99 }] },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .bool }
  ]
  expectCfgErrCode "N9 shallow reference before primitive uniqueness"
    .badReference n9
  -- Every declaration shape, FieldSpec catalog entry, and Map-key legality
  -- check completes before primitive interning.
  let n10 ← programWithTypes "PrimitiveTypeKeyN10ShapeFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .uint 7 }
  ]
  expectCfgErrCode "N10 type shape before primitive uniqueness" .badType n10
  let zeroMod := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let n11 ← programWithTypes "PrimitiveTypeKeyN11FieldFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none,
      shape := .field { id := bn254FrFieldSpecV1.id, modulusBE := zeroMod } }
  ]
  expectCfgErrCode "N11 FieldSpec before primitive uniqueness" .badType n11
  let n12 ← programWithTypes "PrimitiveTypeKeyN12MapKeyFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .option 0 },
    { id := 3, name := none, shape := .map 2 0 }
  ]
  expectCfgErrCode "N12 Map-key legality before primitive uniqueness"
    .badType n12
  -- Primitive interning precedes named-name, canonical-value, callable-
  -- signature, and requirement phases, preserving one authoritative order.
  -- Named declarations occupy the contiguous prefix; the duplicate anonymous
  -- Bool pair triggers the primitive-leaf subphase before named-name checks.
  let n13 ← programWithTypes "PrimitiveTypeKeyN13NamedLater" #[
    { id := 0, name := some "Dup",
      shape := .struct #[{ name := "x", typeId := 2 }] },
    { id := 1, name := some "Dup",
      shape := .enum #[{ name := "v", payloadTypes := #[2] }] },
    { id := 2, name := none, shape := .bool },
    { id := 3, name := none, shape := .bool }
  ]
  expectCfgErrCode "N13 primitive uniqueness before named names"
    .nonCanonical n13
  let n14 ← programWithTypes "PrimitiveTypeKeyN14ValueLater" #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .bool }
    ] #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
  expectCfgErrCode "N14 primitive uniqueness before canonical value"
    .nonCanonical n14
  let n15 ← programWithTypes "PrimitiveTypeKeyN15SignatureLater" #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .bool }
    ] #[] #[cfgCallableKindName .pureFn none]
  expectCfgErrCode "N15 primitive uniqueness before callable signature"
    .nonCanonical n15
  let n16Base ← programWithTypes "PrimitiveTypeKeyN16RequirementLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool }
  ]
  let n16 : SemanticProgramDataV1 := {
    n16Base with requirements := { items := #[req "unknown.capability"] }
  }
  expectCfgErrCode "N16 primitive uniqueness before requirements"
    .nonCanonical n16

/-- SPEC-SEM-WIRE-001 §5 anonymous `.array`/`.map`/`.option` TypeKeys are
    interned by exact recursive child structural-class identity, not by the
    final child TypeId: two anonymous containers with structurally-equivalent
    child graphs receive the same structural class. Anonymous-container cycles
    that pass through no named anchor are illegal; recursion through a named
    `named(reserved TypeId)` anchor is accepted. This gate runs after leaf
    primitive interning and before named-name/canonical-value/signature/
    requirement phases. The shipped behavior is pinned through
    `validateSemanticProgramStructureV1` + the structure-gated encoder on
    every case; the public class seam `computeStructuralTypeClassIdsV1` is
    exercised directly to prove structural-class identity invariants, and the
    public phase seam `validateTypeKeyPhasesV1` is exercised to make the
    primitive-leaf vs recursive-anonymous precedence observable (both share
    the public `.nonCanonical` wire error). These seam assertions complement,
    not replace, the shipped gate. The long-chain positive uses a strictly
    acyclic fixture (named struct field references the terminal Bool, not
    itself and not an Option). Named-body `Option`-cycle legality is now
    enforced by a later `namedBodyCycle` subphase (pinned by
    `testNamedBodyOptionCycleLegality`); the P1/P2 named-anchor positives
    below are legal under that complete cycle condition. -/
private def testRecursiveAnonymousTypeKeyUniqueness : IO Unit := do
  -- Positives: distinct Array element/length, Map key/value, Option element
  -- structural classes. None of these duplicates another container shape.
  let p0Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .array 0 4 },
    { id := 3, name := none, shape := .array 0 8 },
    { id := 4, name := none, shape := .array 1 4 },
    { id := 5, name := none, shape := .map 0 1 },
    { id := 6, name := none, shape := .map 1 0 },
    { id := 7, name := none, shape := .option 0 },
    { id := 8, name := none, shape := .option 1 }
  ]
  let p0 ← programWithTypes "RecursiveTypeKeyP0Distinct" p0Types
  expectCfgOk "P0 distinct anonymous container structural classes" p0
  -- Helper: duplicate exact container shape → `.nonCanonical` on both
  -- shipped paths (structure gate + structure-gated encoder).
  let expectDup (name label : String)
      (types : Array TypeDeclV1) : IO Unit := do
    let data ← programWithTypes name types
    expectCfgErrCode label .nonCanonical data
  -- N1 duplicate exact Array structural class (same element + length).
  expectDup "RecursiveTypeKeyN1Array" "N1 duplicate Array structural class" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 }
  ]
  -- N2 duplicate exact Map structural class (same key + value).
  expectDup "RecursiveTypeKeyN2Map" "N2 duplicate Map structural class" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .map 0 1 },
    { id := 3, name := none, shape := .map 0 1 }
  ]
  -- N3 duplicate exact Option structural class (same element).
  expectDup "RecursiveTypeKeyN3Option" "N3 duplicate Option structural class" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .option 0 },
    { id := 2, name := none, shape := .option 0 }
  ]
  -- N4 nested structural duplicate: two `Option (Array Bool 4)` with the
  -- same inner structure collapse to one structural class.
  expectDup "RecursiveTypeKeyN4Nested" "N4 nested duplicate structural class" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .option 1 },
    { id := 3, name := none, shape := .option 1 }
  ]
  -- N5 self Option cycle: anonymous `Option T` where `T == self`. No named
  -- anchor, so this is an illegal anonymous-container cycle.
  let n5 ← programWithTypes "RecursiveTypeKeyN5SelfOption" #[
    { id := 0, name := none, shape := .option 0 }
  ]
  expectCfgErrCode "N5 self Option cycle" .nonCanonical n5
  -- N6 two-node Option cycle: `Option T` → `Option S` → `Option T` with no
  -- named anchor.
  let n6 ← programWithTypes "RecursiveTypeKeyN6TwoNodeOption" #[
    { id := 0, name := none, shape := .option 1 },
    { id := 1, name := none, shape := .option 0 }
  ]
  expectCfgErrCode "N6 two-node Option cycle" .nonCanonical n6
  -- N7 Array↔Option cycle: anonymous Array<Option<Array<...>>> forms a cycle
  -- without a named anchor.
  let n7 ← programWithTypes "RecursiveTypeKeyN7ArrayOption" #[
    { id := 0, name := none, shape := .array 1 4 },
    { id := 1, name := none, shape := .option 0 }
  ]
  expectCfgErrCode "N7 Array Option cycle" .nonCanonical n7
  -- N8 Map-value↔Option cycle: anonymous Map key→Option→Map cycle.
  let n8 ← programWithTypes "RecursiveTypeKeyN8MapValueOption" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .map 0 2 },
    { id := 2, name := none, shape := .option 1 }
  ]
  expectCfgErrCode "N8 Map value Option cycle" .nonCanonical n8
  -- P1 legal recursion through a named Struct/Enum anchor: a named Struct
  -- field points back at a container that holds an Option of the named
  -- Struct. The named reserved TypeId is the terminal structural anchor, so
  -- the recursive Option class resolves through `named(reserved TypeId)`.
  -- This case is legal under the complete SPEC §5 cycle condition, now
  -- enforced by a later `namedBodyCycle` subphase: the cycle passes through
  -- both a reserved named key (Node) and an `Option`, so the
  -- Option-removed induced graph is acyclic.
  let p1Types : Array TypeDeclV1 := #[
    { id := 0, name := some "Node",
      shape := .struct #[{ name := "tail", typeId := 1 }] },
    { id := 1, name := none, shape := .option 0 }
  ]
  let p1 ← programWithTypes "RecursiveTypeKeyP1NamedAnchor" p1Types
  expectCfgOk "P1 legal recursion through named Struct anchor" p1
  -- P2 legal recursion through a named Enum anchor.
  let p2Types : Array TypeDeclV1 := #[
    { id := 0, name := some "Tree",
      shape := .enum #[{ name := "leaf", payloadTypes := #[1] }] },
    { id := 1, name := none, shape := .option 0 }
  ]
  let p2 ← programWithTypes "RecursiveTypeKeyP2NamedEnumAnchor" p2Types
  expectCfgOk "P2 legal recursion through named Enum anchor" p2
  -- P3 named identities stay distinct even with the same body shape. Two
  -- Option containers each wrap a same-body-but-different-reserved-Id named
  -- Struct declaration; the two Option classes differ (the named anchor
  -- carries the reserved TypeId), so both shipped paths accept the program.
  let p3Types : Array TypeDeclV1 := #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "x", typeId := 4 }] },
    { id := 1, name := some "B",
      shape := .struct #[{ name := "x", typeId := 4 }] },
    { id := 2, name := none, shape := .option 0 },
    { id := 3, name := none, shape := .option 1 },
    { id := 4, name := none, shape := .bool }
  ]
  let p3 ← programWithTypes "RecursiveTypeKeyP3NamedDistinct" p3Types
  expectCfgOk "P3 Option containers over distinct named anchors distinct" p3
  -- Class-seam evidence for P3: the two Option containers (ids 2,3) over
  -- different reserved named anchors receive distinct structural class IDs.
  let p3Classes ← expectOk "P3 class computation"
    (computeStructuralTypeClassIdsV1 p3Types)
  expect (p3Classes[2]! != p3Classes[3]!)
    "P3 Option classes over distinct named anchors must differ"
  -- Seam S1: structurally-equivalent child graphs at different TypeIds
  -- receive the same structural class. Two separate `Array Bool 4` nodes
  -- (different TypeIds, identical structure) share one class; the validator
  -- rejects the duplicate anonymous class, but the seam proves equivalence.
  let s1Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 }
  ]
  let s1Classes ← expectOk "S1 class computation over duplicate structure"
    (computeStructuralTypeClassIdsV1 s1Types)
  expect (s1Classes[1]! == s1Classes[2]!)
    "S1 structurally-equivalent Array nodes must share a class"
  expect (s1Classes[0]! != s1Classes[1]!)
    "S1 Bool leaf must differ from Array class"
  let s1 ← programWithTypes "RecursiveTypeKeyS1DuplicateRejected" s1Types
  expectCfgErrCode "S1 duplicate class rejected by shipped gate"
    .nonCanonical s1
  -- Seam S2: nested structural equivalence. Two `Option (Array Bool 4)` at
  -- different TypeIds (built over separate-but-equivalent inner Array nodes)
  -- share one class.
  let s2Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 },
    { id := 3, name := none, shape := .option 1 },
    { id := 4, name := none, shape := .option 2 }
  ]
  let s2Classes ← expectOk "S2 nested class computation"
    (computeStructuralTypeClassIdsV1 s2Types)
  expect (s2Classes[1]! == s2Classes[2]!)
    "S2 inner Array classes equal"
  expect (s2Classes[3]! == s2Classes[4]!)
    "S2 Option classes over equivalent inner Arrays equal"
  -- Seam S3: distinct tags / lengths / Map operand order yield distinct
  -- classes. Array Bool 4 vs Array Bool 8 vs Option Bool vs Map Bool UInt8
  -- vs Map UInt8 Bool all differ.
  let s3Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .array 0 4 },
    { id := 3, name := none, shape := .array 0 8 },
    { id := 4, name := none, shape := .option 0 },
    { id := 5, name := none, shape := .map 0 1 },
    { id := 6, name := none, shape := .map 1 0 }
  ]
  let s3Classes ← expectOk "S3 distinct-structure class computation"
    (computeStructuralTypeClassIdsV1 s3Types)
  expect (s3Classes[2]! != s3Classes[3]!) "S3 Array lengths differ"
  expect (s3Classes[2]! != s3Classes[4]!) "S3 Array vs Option differ"
  expect (s3Classes[5]! != s3Classes[6]!) "S3 Map operand order differs"
  -- Long-chain resource regression: a 10000-deep acyclic chain of anonymous
  -- Option nodes anchored at a single named Struct must complete the
  -- structure gate without quadratic memory. The fixture is strictly
  -- acyclic and respects id == array index: id 0 is the named anchor (its
  -- field references the terminal Bool at id chainDepth+1), id 1..chainDepth
  -- are anonymous Option nodes where Option i wraps Option(i-1) (Option 1
  -- wraps the named anchor 0), and id chainDepth+1 is the terminal Bool. No
  -- named-body cycle is constructed (the named struct field references Bool,
  -- not itself and not an Option); this is an acyclic resource fixture that
  -- exercises linear-space class computation, not a named-body cycle case.
  -- Each Option node has a
  -- distinct structural class (different nesting depth), so no duplicate
  -- anonymous class is reported. Exercises linear-space class computation on
  -- a real shipped path (structure gate + encoder).
  let chainDepth : Nat := 10000
  let boolId : UInt32 := UInt32.ofNat (chainDepth + 1)
  let mut chainTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "Anchor",
      shape := .struct #[{ name := "v", typeId := boolId }] }
  ]
  let mut i := 1
  while i ≤ chainDepth do
    -- Array index i, id i: Option i wraps Option(i-1) (Option 1 wraps anchor).
    chainTypes := chainTypes.push
      { id := UInt32.ofNat i, name := none, shape := .option (UInt32.ofNat (i - 1)) }
    i := i + 1
  -- Terminal Bool at array index chainDepth+1, id chainDepth+1.
  chainTypes := chainTypes.push
    { id := boolId, name := none, shape := .bool }
  let chain ← programWithTypes "RecursiveTypeKeyLongChain" chainTypes
  expectCfgOk "Long chain (10k Option nodes) structure gate" chain
  -- Also confirm the seam returns a class per node without blowing up.
  let _ ← expectOk "Long chain class computation"
    (computeStructuralTypeClassIdsV1 chainTypes)
  -- Phase precedence: leaf primitive interning runs before recursive
  -- anonymous structural-class uniqueness. A duplicate primitive plus a
  -- duplicate anonymous container fails on the primitive-leaf phase first.
  -- The public wire error stays `.nonCanonical`; the phase seam observes
  -- `.primitiveLeaf`. This makes the ordering observable (the public code
  -- alone cannot distinguish the two subphases).
  let prec1Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .array 0 4 },
    { id := 3, name := none, shape := .array 0 4 }
  ]
  let prec1 ← programWithTypes "RecursiveTypeKeyPrec1PrimitiveFirst" prec1Types
  expectCfgErrCode "Prec1 primitive duplicate before recursive (wire)"
    .nonCanonical prec1
  expectTypeKeyPhase "Prec1 primitive duplicate before recursive (phase)"
    .primitiveLeaf .nonCanonical prec1Types
  -- A pure recursive duplicate (no primitive duplicate) must report the
  -- `.recursiveAnonymous` phase with the same public `.nonCanonical` wire
  -- error, proving the recursive subphase is reachable and ordered after
  -- the primitive-leaf subphase.
  let prec1bTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 }
  ]
  expectTypeKeyPhase "Prec1b pure recursive duplicate phase"
    .recursiveAnonymous .nonCanonical prec1bTypes
  -- A pure recursive anonymous cycle (no primitive duplicate) must also
  -- report the `.recursiveAnonymous` phase.
  let prec1cTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .option 1 },
    { id := 1, name := none, shape := .option 0 }
  ]
  expectTypeKeyPhase "Prec1c pure recursive cycle phase"
    .recursiveAnonymous .nonCanonical prec1cTypes
  -- Phase precedence: table id/index validation precedes the TypeKey
  -- segment. A bad table id plus a duplicate recursive container fails on
  -- the table-id check first (`.duplicate`).
  let prec2a ← programWithTypes "RecursiveTypeKeyPrec2aTableIdFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 7, name := none, shape := .array 0 4 },
    { id := 8, name := none, shape := .array 0 4 }
  ]
  expectCfgErrCode "Prec2a table id before recursive" .duplicate prec2a
  -- Phase precedence: shallow reference range precedes the TypeKey segment.
  -- An OOR container child fails as `.badReference` first, even when a
  -- duplicate Array structural class would also exist.
  let prec2b ← programWithTypes "RecursiveTypeKeyPrec2bRefFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 99 4 },
    { id := 2, name := none, shape := .array 99 4 }
  ]
  expectCfgErrCode "Prec2b shallow ref before recursive" .badReference prec2b
  -- Phase precedence: type-shape legality precedes the TypeKey segment. An
  -- invalid Array length (>4096) plus a duplicate Array fails on the shape
  -- check first (`.badType`).
  let prec2c ← programWithTypes "RecursiveTypeKeyPrec2cArrayLengthFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 5000 },
    { id := 2, name := none, shape := .array 0 4 },
    { id := 3, name := none, shape := .array 0 4 }
  ]
  expectCfgErrCode "Prec2c invalid Array length before recursive" .badType
    prec2c
  -- Phase precedence: FieldSpec catalog legality precedes the TypeKey
  -- segment. An invalid FieldSpec (wrong modulus) plus a duplicate Option
  -- fails on the FieldSpec check first (`.badType`).
  let zeroMod := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let prec2d ← programWithTypes "RecursiveTypeKeyPrec2dFieldSpecFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none,
      shape := .field { id := bn254FrFieldSpecV1.id, modulusBE := zeroMod } },
    { id := 2, name := none, shape := .option 0 },
    { id := 3, name := none, shape := .option 0 }
  ]
  expectCfgErrCode "Prec2d invalid FieldSpec before recursive" .badType prec2d
  -- Phase precedence: Map-key legality precedes the TypeKey segment. An
  -- illegal Map key fails as `.badType` first, even when a duplicate Option
  -- also exists.
  let prec3 ← programWithTypes "RecursiveTypeKeyPrec3MapKeyFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .option 0 },
    { id := 2, name := none, shape := .map 1 0 },
    { id := 3, name := none, shape := .option 0 }
  ]
  expectCfgErrCode "Prec3 Map-key legality before recursive" .badType prec3
  -- Phase precedence: recursive structural uniqueness runs before named
  -- type-name uniqueness. A recursive duplicate + duplicate named names
  -- fails on the recursive duplicate first.
  let prec4 ← programWithTypes "RecursiveTypeKeyPrec4NamedLater" #[
    { id := 0, name := some "Dup",
      shape := .struct #[{ name := "x", typeId := 4 }] },
    { id := 1, name := some "Dup",
      shape := .enum #[{ name := "v", payloadTypes := #[4] }] },
    { id := 2, name := none, shape := .bool },
    { id := 3, name := none, shape := .array 2 4 },
    { id := 4, name := none, shape := .array 2 4 }
  ]
  expectCfgErrCode "Prec4 recursive before named names" .nonCanonical prec4
  -- Phase precedence: recursive structural uniqueness runs before canonical
  -- valueBytes. A recursive duplicate + a malformed Constant value fails on
  -- the recursive duplicate first.
  let prec5 ← programWithTypes "RecursiveTypeKeyPrec5ValueLater"
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .array 0 4 },
      { id := 2, name := none, shape := .array 0 4 }]
    #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
  expectCfgErrCode "Prec5 recursive before canonical value" .nonCanonical
    prec5
  -- Phase precedence: recursive structural uniqueness runs before callable
  -- signature.
  let prec6 ← programWithTypes "RecursiveTypeKeyPrec6SignatureLater"
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .array 0 4 },
      { id := 2, name := none, shape := .array 0 4 }]
    #[] #[cfgCallableKindName .pureFn none]
  expectCfgErrCode "Prec6 recursive before callable signature" .nonCanonical
    prec6
  -- Phase precedence: recursive structural uniqueness runs before
  -- requirements.
  let prec7Base ← programWithTypes "RecursiveTypeKeyPrec7RequirementLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 }
  ]
  let prec7 : SemanticProgramDataV1 := {
    prec7Base with requirements := { items := #[req "unknown.capability"] }
  }
  expectCfgErrCode "Prec7 recursive before requirements" .nonCanonical prec7

/-- SPEC-SEM-WIRE-001 §6 callable kind/name presence: initializer is the only
    anonymous kind; entry/view/pureFn/invariant must be named. This test does
    not validate identifier spelling, uniqueness, initializer result/cardinality,
    or the full invariant declaration/closure join. -/
private def testCallableKindNamePresence : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  -- Positives: initializer anonymous; every other kind named.
  let p1 ← programWithTypes "CallableNameP1Init" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1]
  expectCfgOk "P1 initializer anonymous" p1
  let p2 ← programWithTypes "CallableNameP2Entry" cfgBoolTypes #[]
    #[cfgCallableKindName .entry (some "run")]
  expectCfgOk "P2 entry named" p2
  let p3 ← programWithTypes "CallableNameP3View" cfgBoolTypes #[]
    #[cfgCallableKindName .view (some "read")]
  expectCfgOk "P3 view named" p3
  let p4 ← programWithTypes "CallableNameP4Pure" cfgBoolTypes #[]
    #[cfgCallableKindName .pureFn (some "f")]
  expectCfgOk "P4 pureFn named" p4
  let p5Base ← programWithTypes "CallableNameP5Invariant" cfgBoolTypes #[]
    #[cfgCallableKindName .invariant (some "safe")]
  let p5 : SemanticProgramDataV1 := {
    p5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P5 invariant named" p5
  -- Negatives: wrong Option shape for each kind.
  let n1 ← programWithTypes "CallableNameN1InitNamed" boolUnitTypes #[]
    #[cfgCallableKindName .initializer (some "init") 1]
  expectCfgErr "N1 initializer named" n1
  let n2 ← programWithTypes "CallableNameN2EntryAnon" cfgBoolTypes #[]
    #[cfgCallableKindName .entry none]
  expectCfgErr "N2 entry anonymous" n2
  let n3 ← programWithTypes "CallableNameN3ViewAnon" cfgBoolTypes #[]
    #[cfgCallableKindName .view none]
  expectCfgErr "N3 view anonymous" n3
  let n4 ← programWithTypes "CallableNameN4PureAnon" cfgBoolTypes #[]
    #[cfgCallableKindName .pureFn none]
  expectCfgErr "N4 pureFn anonymous" n4
  let n5Base ← programWithTypes "CallableNameN5InvariantAnon" cfgBoolTypes #[]
    #[cfgCallableKindName .invariant none]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N5 invariant anonymous" n5
  -- N6: canonical value validation precedes signature presence. The malformed
  -- Bool literal must report `.nonCanonical` before the anonymous pureFn.
  let badValueCallable : CallableV1 := {
    (cfgCallableKindName .pureFn none) with
    blocks := #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0))
        (.literal 0 (ByteArray.mk #[2]))]
      (.return_ none)]
  }
  let n6 ← programWithTypes "CallableNameN6ValueFirst" cfgBoolTypes #[]
    #[badValueCallable]
  expectCfgErrCode "N6 canonical value before signature" .nonCanonical n6
  -- N7: signature presence precedes CFG/def-site validation. TypeId 99 on the
  -- result ValueDef would later be `.badReference`, but anonymous pureFn wins.
  let badCfgCallable : CallableV1 := {
    (cfgCallableKindName .pureFn none) with
    blocks := #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)]
  }
  let n7 ← programWithTypes "CallableNameN7SignatureFirst" cfgBoolTypes #[]
    #[badCfgCallable]
  expectCfgErr "N7 signature before def-site TypeId" n7

/-- SPEC-SEM-WIRE-001 §6 named callable table uniqueness. This slice compares
    exact String values only; identifier grammar and NFC remain separate. -/
private def testCallableNameUniqueness : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let initializer0 := cfgCallableKindName .initializer none 1
  let entry1 : CallableV1 := {
    (cfgCallableKindName .entry (some "run")) with id := 1
  }
  let view2 : CallableV1 := {
    (cfgCallableKindName .view (some "read")) with id := 2
  }
  let pure3 : CallableV1 := {
    (cfgCallableKindName .pureFn (some "f")) with id := 3
  }
  let invariant4 : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with id := 4
  }
  let p0Base ← programWithTypes "CallableUniqueP0Kinds" boolUnitTypes #[]
    #[initializer0, entry1, view2, pure3, invariant4]
  let p0 : SemanticProgramDataV1 := {
    p0Base with invariants := #[{ id := 0, name := "safe", callableId := 4 }]
  }
  expectCfgOk "P0 initializer plus four distinct named kinds" p0
  let upper1 : CallableV1 := {
    (cfgCallableKindName .view (some "F")) with id := 1
  }
  let p1 ← programWithTypes "CallableUniqueP1Case" boolUnitTypes #[]
    #[cfgCallableKindName .entry (some "f"), upper1]
  expectCfgOk "P1 callable names are case sensitive" p1
  let duplicatePure1 : CallableV1 := {
    (cfgCallableKindName .pureFn (some "dup")) with id := 1
  }
  let n1 ← programWithTypes "CallableUniqueN1Pure" boolUnitTypes #[]
    #[cfgCallableKindName .pureFn (some "dup"), duplicatePure1]
  expectCfgErr "N1 duplicate pureFn names" n1
  let duplicateInvariant1 : CallableV1 := {
    (cfgCallableKindName .invariant (some "same")) with id := 1
  }
  let n2Base ← programWithTypes "CallableUniqueN2CrossKind" boolUnitTypes #[]
    #[cfgCallableKindName .entry (some "same"), duplicateInvariant1]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "same", callableId := 1 }]
  }
  expectCfgErr "N2 duplicate names across callable kinds" n2
  -- Shallow result TypeId range precedes name uniqueness.
  let badRefCallable : CallableV1 := {
    (cfgCallableKindName .pureFn (some "dup")) with
      result := { typeId := 99, visibility := .public_ }
  }
  let n3 ← programWithTypes "CallableUniqueN3ReferenceFirst" boolUnitTypes #[]
    #[badRefCallable, duplicatePure1]
  expectCfgErrCode "N3 result TypeId before name uniqueness" .badReference n3
  -- Canonical valueBytes validation precedes name uniqueness.
  let badValueCallable : CallableV1 := {
    (cfgCallableKindName .pureFn (some "dup")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n4 ← programWithTypes "CallableUniqueN4ValueFirst" boolUnitTypes #[]
    #[badValueCallable, duplicatePure1]
  expectCfgErrCode "N4 canonical value before name uniqueness" .nonCanonical n4
  -- Name uniqueness precedes per-callable CFG def-site TypeId validation.
  let badCfgDuplicate1 : CallableV1 := {
    duplicatePure1 with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n5 ← programWithTypes "CallableUniqueN5UniquenessFirst" boolUnitTypes #[]
    #[cfgCallableKindName .pureFn (some "dup"), badCfgDuplicate1]
  expectCfgErr "N5 name uniqueness before def-site TypeId" n5

/-- SPEC-SEM-WIRE-001 §6 parameter names are exact-string unique within each
    callable. Different callables may reuse a parameter name; grammar/NFC is
    separate. -/
private def testCallableParameterNameUniqueness : IO Unit := do
  let paramX0 : ParameterV1 := {
    valueId := 0, name := "x", typeId := 0, visibility := .public_
  }
  let paramY1 : ParameterV1 := {
    valueId := 1, name := "y", typeId := 0, visibility := .public_
  }
  let paramUpper1 : ParameterV1 := {
    valueId := 1, name := "X", typeId := 0, visibility := .public_
  }
  let paramX1 : ParameterV1 := {
    valueId := 1, name := "x", typeId := 0, visibility := .public_
  }
  let p0 ← programWithTypes "ParamNameP0Distinct" cfgBoolTypes #[]
    #[cfgCallableWithParams #[paramX0, paramY1] #[cfgBlock 0 (.return_ none)]]
  expectCfgOk "P0 distinct parameter names" p0
  let secondCallable : CallableV1 := {
    (cfgCallableWithParams #[paramX0] #[cfgBlock 0 (.return_ none)]) with
      id := 1, name := some "g"
  }
  let p1 ← programWithTypes "ParamNameP1PerCallable" cfgBoolTypes #[]
    #[cfgCallableWithParams #[paramX0] #[cfgBlock 0 (.return_ none)], secondCallable]
  expectCfgOk "P1 parameter name scope resets per callable" p1
  let p2 ← programWithTypes "ParamNameP2Case" cfgBoolTypes #[]
    #[cfgCallableWithParams #[paramX0, paramUpper1] #[cfgBlock 0 (.return_ none)]]
  expectCfgOk "P2 parameter names are case sensitive" p2
  let duplicateParamsCallable :=
    cfgCallableWithParams #[paramX0, paramX1] #[cfgBlock 0 (.return_ none)]
  let n1 ← programWithTypes "ParamNameN1PureFn" cfgBoolTypes #[]
    #[duplicateParamsCallable]
  expectCfgErr "N1 duplicate parameter names in pureFn" n1
  let duplicateEntry : CallableV1 := {
    duplicateParamsCallable with kind := .entry, name := some "run"
  }
  let n2 ← programWithTypes "ParamNameN2Entry" cfgBoolTypes #[]
    #[duplicateEntry]
  expectCfgErr "N2 duplicate parameter names in entry" n2
  -- Shallow parameter TypeId range validation precedes name uniqueness.
  let badRefParam1 : ParameterV1 := { paramX1 with typeId := 99 }
  let n3 ← programWithTypes "ParamNameN3ReferenceFirst" cfgBoolTypes #[]
    #[cfgCallableWithParams #[paramX0, badRefParam1] #[cfgBlock 0 (.return_ none)]]
  expectCfgErrCode "N3 parameter TypeId before name uniqueness" .badReference n3
  -- Canonical valueBytes validation precedes parameter-name uniqueness.
  let badValueCallable : CallableV1 := {
    duplicateParamsCallable with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 2, typeId := 0 })
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n4 ← programWithTypes "ParamNameN4ValueFirst" cfgBoolTypes #[]
    #[badValueCallable]
  expectCfgErrCode "N4 canonical value before parameter names" .nonCanonical n4
  -- Parameter-name uniqueness precedes CFG def-site TypeId range.
  let badCfgCallable : CallableV1 := {
    duplicateParamsCallable with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 2, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n5 ← programWithTypes "ParamNameN5UniquenessFirst" cfgBoolTypes #[]
    #[badCfgCallable]
  expectCfgErr "N5 parameter names before def-site TypeId" n5

/-! ### SPEC §6 aggregate callable entry/view presence

    `SemanticProgramDataV1.callables` must contain at least one callable of
    kind `.entry` or `.view`; a program with only initializers/pureFns/
    invariants (or zero callables) has no externally invokable surface. This
    is a structure-gate-only rule; raw `decodeSemanticProgramDataV1` transport
    remains permissive. The gate runs after callable kind/name presence,
    callable-name uniqueness, and per-callable parameter-name uniqueness, and
    before initializer/invariant signature checks, CFG, and requirements.

    The fixtures below use `rawProgramWithTypes`, which intentionally does NOT
    append the auto-entry callable that the structure-gated `programWithTypes`
    helper adds, so the aggregate gate is exercised directly. -/

/-- Program builder that does NOT append an entry/view callable, for direct
    exercise of the SPEC §6 entry/view presence aggregate gate. All other
    structure-gated fixtures use `programWithTypes`, which appends a minimal
    valid `.entry` callable so they satisfy the new gate. -/
private def rawProgramWithTypes (name : String) (types : Array TypeDeclV1)
    (callables : Array CallableV1 := #[]) : IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  pure { data0 with types, callables }

/-- SPEC-SEM-WIRE-001 §6 callables must contain at least one `.entry` or
    `.view`. Positives: entry only; view only; initializer+entry;
    pureFn/invariant plus a later view. Negatives: zero callables;
    initializer only; pureFn only; invariant only (with valid metadata/join);
    initializer+pureFn+invariant but no entry/view. Stable-order mixed-invalid
    cases pin the phase seam: malformed callable kind/name, duplicate named
    callable, and duplicate parameter name all precede the new aggregate gate;
    absence of entry/view precedes duplicate initializer, malformed invariant
    signature/join, generic CFG error, and bad requirements. Transport decode
    of a hand-built zero-callable envelope remains permissive while structure
    validator, encoder, and carrier decoder reject `.badCfg`. -/
private def testCallableEntryViewPresence : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  -- Positives: each program has at least one entry/view and is otherwise
  -- fully valid under existing gates.
  let p1 ← rawProgramWithTypes "EntryViewP1Entry" cfgBoolTypes
    #[cfgCallableKindName .entry (some "run")]
  expectCfgOk "P1 entry only" p1
  let p2 ← rawProgramWithTypes "EntryViewP2View" cfgBoolTypes
    #[cfgCallableKindName .view (some "read")]
  expectCfgOk "P2 view only" p2
  let p3 ← rawProgramWithTypes "EntryViewP3InitEntry" boolUnitTypes
    #[cfgCallableKindName .initializer none 1,
      { (cfgCallableKindName .entry (some "run")) with id := 1 }]
  expectCfgOk "P3 initializer plus entry" p3
  let p4Base ← rawProgramWithTypes "EntryViewP4PureInvView" cfgBoolTypes
    #[cfgCallableKindName .pureFn (some "f"),
      { (cfgCallableKindName .invariant (some "safe")) with id := 1 },
      { (cfgCallableKindName .view (some "read")) with id := 2 }]
  let p4 : SemanticProgramDataV1 := {
    p4Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P4 pureFn/invariant plus later view" p4
  -- Negatives: no entry/view anywhere. Both shipped structure validator and
  -- structure-gated encoder must reject `.badCfg`.
  let n0 ← rawProgramWithTypes "EntryViewN0Zero" cfgBoolTypes
  expectCfgErr "N0 zero callables" n0
  let n1 ← rawProgramWithTypes "EntryViewN1InitOnly" boolUnitTypes
    #[cfgCallableKindName .initializer none 1]
  expectCfgErr "N1 initializer only" n1
  let n2 ← rawProgramWithTypes "EntryViewN2PureOnly" cfgBoolTypes
    #[cfgCallableKindName .pureFn (some "f")]
  expectCfgErr "N2 pureFn only" n2
  let n3Base ← rawProgramWithTypes "EntryViewN3InvariantOnly" cfgBoolTypes
    #[cfgCallableKindName .invariant (some "safe")]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N3 invariant only with valid metadata/join" n3
  let n4Base ← rawProgramWithTypes "EntryViewN4InitPureInv" boolUnitTypes
    #[cfgCallableKindName .initializer none 1,
      { (cfgCallableKindName .pureFn (some "f")) with id := 1 },
      { (cfgCallableKindName .invariant (some "safe")) with id := 2 }]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N4 initializer+pureFn+invariant no entry/view" n4
  -- Stable-order mixed-invalid: earlier callable-name/parameter gates precede
  -- the new aggregate gate. Malformed kind/name on the first callable fires
  -- before the absence-of-entry/view is observed on the whole table.
  let n5 ← rawProgramWithTypes "EntryViewN5KindNameFirst" cfgBoolTypes
    #[cfgCallableKindName .pureFn none,
      { (cfgCallableKindName .pureFn (some "f")) with id := 1 }]
  expectCfgErr "N5 malformed callable kind/name before aggregate gate" n5
  expectCallableSignaturePhase "N5 kind/name phase"
    .kindName .badCfg n5
  let n6 ← rawProgramWithTypes "EntryViewN6DuplicateName" cfgBoolTypes
    #[cfgCallableKindName .pureFn (some "dup"),
      { (cfgCallableKindName .pureFn (some "dup")) with id := 1 }]
  expectCfgErr "N6 duplicate named callable before aggregate gate" n6
  expectCallableSignaturePhase "N6 callable-name phase"
    .callableName .badCfg n6
  let dupParam : ParameterV1 :=
    { valueId := 0, name := "x", typeId := 0, visibility := .public_ }
  let dupParamCallable : CallableV1 := {
    (cfgCallableKindName .pureFn (some "f")) with
      params := #[dupParam, { dupParam with valueId := 1 }]
  }
  let n7 ← rawProgramWithTypes "EntryViewN7DuplicateParam" cfgBoolTypes
    #[dupParamCallable]
  expectCfgErr "N7 duplicate parameter name before aggregate gate" n7
  expectCallableSignaturePhase "N7 parameter-name phase"
    .parameterName .badCfg n7
  -- Stable-order mixed-invalid: absence of entry/view precedes later
  -- initializer/invariant signature, CFG, and requirements gates. N8/N9 use
  -- the production-consumed non-wire seam to distinguish same-`.badCfg`
  -- signature subphases. N10/N11 additionally use distinguishable later public
  -- errors (`.badReference`/`.badRequirement`), so the shipped dual paths
  -- prove that the aggregate `.badCfg` wins before CFG/requirements.
  let n8 ← rawProgramWithTypes "EntryViewN8BeforeDupInit" boolUnitTypes
    #[cfgCallableKindName .initializer none 1,
      { (cfgCallableKindName .initializer none 1) with id := 1 }]
  expectCfgErr "N8 absence of entry/view before duplicate initializer" n8
  expectCallableSignaturePhase "N8 entry/view before duplicate initializer"
    .entryView .badCfg n8
  let n9Base ← rawProgramWithTypes "EntryViewN9BeforeInvSig" cfgBoolTypes
    #[{ (cfgCallableKindName .invariant (some "safe")) with
        result := { typeId := 0, visibility := .private_ } }]
  let n9 : SemanticProgramDataV1 := {
    n9Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N9 absence of entry/view before malformed invariant signature" n9
  expectCallableSignaturePhase "N9 entry/view before invariant signature"
    .entryView .badCfg n9
  let n10BadCfg : CallableV1 := {
    (cfgCallableKindName .pureFn (some "f")) with
    blocks := #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 })
        (.literal 0 (ByteArray.mk #[0]))]
      (.return_ none)]
  }
  let n10 ← rawProgramWithTypes "EntryViewN10BeforeCfg" cfgBoolTypes
    #[n10BadCfg]
  expectCfgErrCode "N10 absence of entry/view before generic badReference"
    .badCfg n10
  expectCallableSignaturePhase "N10 entry/view before CFG"
    .entryView .badCfg n10
  let n11 ← rawProgramWithTypes "EntryViewN11BeforeReqs" cfgBoolTypes
    #[cfgCallableKindName .pureFn (some "f")]
  let n11Bad : SemanticProgramDataV1 := {
    n11 with requirements := { items := #[req "notadomain.foo"] }
  }
  expectCfgErrCode "N11 absence of entry/view before bad requirements"
    .badCfg n11Bad
  expectCallableSignaturePhase "N11 entry/view before requirements"
    .entryView .badCfg n11Bad
  -- Transport decode of a hand-built zero-callable envelope is permissive:
  -- `decodeSemanticProgramDataV1` accepts and exactly preserves it, while the
  -- shipped structure validator, structure-gated encoder, and carrier decoder
  -- all reject `.badCfg`.
  let zeroData ← emptyProgram "EntryViewTransportZero"
  let zQnB ← expectOk "transport qn" (encodeQualifiedName zeroData.qualifiedName)
  let zTypesB ← expectOk "transport types"
    (encodeArray encodeTypeDeclV1 #[])
  let zConstsB ← expectOk "transport consts"
    (encodeArray encodeConstantV1 #[])
  let zStateB ← expectOk "transport state" (encodeArray encodeStateDeclV1 #[])
  let zEventsB ← expectOk "transport events" (encodeArray encodeEventDeclV1 #[])
  let zErrorsB ← expectOk "transport errors" (encodeArray encodeErrorDeclV1 #[])
  let zCallablesB ← expectOk "transport callables"
    (encodeArray encodeCallableV1 #[])
  let zInvsB ← expectOk "transport invs"
    (encodeArray encodeInvariantDeclV1 #[])
  let zReqB ← expectOk "transport reqs"
    (encodeProgramRequirementsV1 { items := #[] })
  let zBody ← expectOk "transport body" (encodeTagged "SemanticProgram.Data" #[
    zQnB, zTypesB, zConstsB, zStateB, zEventsB, zErrorsB,
    zCallablesB, zInvsB, zReqB
  ])
  let zMagic := semanticProgramMagicV1.toUTF8.push 0
  let zBytes := zMagic.append zBody
  let zDecoded ← expectOk "transport decode zero callables"
    (decodeSemanticProgramDataV1 zBytes)
  expect (zDecoded == zeroData) "transport preserves zero-callable envelope"
  expect (zDecoded.callables.isEmpty) "transport zero callables preserved"
  expectErr "structure rejects zero callables" .badCfg
    (validateSemanticProgramStructureV1 zDecoded)
  expectErr "encode rejects zero callables" .badCfg
    (encodeSemanticProgramDataV1 zDecoded)
  expectErr "carrier rejects zero callables" .badCfg
    (decodeSemanticProgramV1 zBytes)

/-- SPEC-SEM-WIRE-001 §5/§6 named Struct/Enum TypeDecl names are
    exact-string unique within the named-type namespace. Full TypeKey closure,
    identifier grammar/NFC, and anonymous type interning remain separate. -/
private def testNamedTypeNameUniqueness : IO Unit := do
  let p0 ← programWithTypes "NamedTypeNameP0Anonymous" cfgBoolTypes
  expectCfgOk "P0 anonymous-only type table" p0
  let orderedTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "a", typeId := 3 }] },
    { id := 1, name := some "E",
      shape := .enum #[{ name := "v", payloadTypes := #[3] }] },
    { id := 2, name := some "s",
      shape := .struct #[{ name := "b", typeId := 3 }] },
    { id := 3, name := none, shape := .bool }
  ]
  let p1 ← programWithTypes "NamedTypeNameP1Distinct" orderedTypes
  expectCfgOk "P1 distinct case-sensitive named type names" p1
  let p1Bytes ← expectOk "P1 named type order encode"
    (encodeSemanticProgramDataV1 p1)
  let p1Decoded ← expectOk "P1 named type order decode"
    (decodeSemanticProgramDataV1 p1Bytes)
  expect (p1Decoded.types == orderedTypes)
    "P1 named TypeDecl source order survives wire round-trip"
  let duplicateStruct : TypeDeclV1 := {
    id := 0, name := some "Dup",
    shape := .struct #[{ name := "a", typeId := 2 }]
  }
  let duplicateEnum : TypeDeclV1 := {
    id := 1, name := some "Dup",
    shape := .enum #[{ name := "v", payloadTypes := #[2] }]
  }
  let anonymousBool : TypeDeclV1 := { id := 2, name := none, shape := .bool }
  let duplicateTypes := #[duplicateStruct, duplicateEnum, anonymousBool]
  let n1 ← programWithTypes "NamedTypeNameN1Duplicate" duplicateTypes
  expectCfgErrCode "N1 duplicate named types across Struct/Enum" .duplicate n1
  -- Shallow TypeId range validation precedes named-type uniqueness.
  let badRefTypes : Array TypeDeclV1 := #[
    duplicateStruct,
    { id := 1, name := some "Dup",
      shape := .enum #[{ name := "v", payloadTypes := #[99] }] },
    anonymousBool
  ]
  let n2 ← programWithTypes "NamedTypeNameN2ReferenceFirst" badRefTypes
  expectCfgErrCode "N2 named type child ref before names" .badReference n2
  -- Per-declaration type-shape validity precedes named-type uniqueness.
  let badShapeTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "Dup", shape := .struct #[] },
    duplicateEnum, anonymousBool
  ]
  let n3 ← programWithTypes "NamedTypeNameN3ShapeFirst" badShapeTypes
  expectCfgErrCode "N3 type shape before named type names" .badType n3
  -- Named-type uniqueness precedes every canonical valueBytes site.
  let n4 ← programWithTypes "NamedTypeNameN4ConstantLater" duplicateTypes
    #[constOf 0 "bad" 2 (ByteArray.mk #[2])]
  expectCfgErrCode "N4 named types before Constant value" .duplicate n4
  let badValueCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[2]))]
      (.return_ none)] with
      id := 0
  }
  let n5 ← programWithTypes "NamedTypeNameN5LiteralLater" duplicateTypes #[]
    #[badValueCallable]
  expectCfgErrCode "N5 named types before Op.Literal value" .duplicate n5
  let badSwitchCallable := cfgCallable #[
    cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
      (.switch 0 #[{
        typeId := 0
        valueBytes := ByteArray.mk #[2]
        target := cfgJumpTarget 1
      }] none),
    cfgBlock 1 (.return_ (some 0))
  ]
  let n6 ← programWithTypes "NamedTypeNameN6SwitchLater" duplicateTypes #[]
    #[badSwitchCallable]
  expectCfgErrCode "N6 named types before SwitchCase value" .duplicate n6
  -- Named-type uniqueness also precedes callable signature and CFG phases.
  let badSignatureCallable := cfgCallableKindName .pureFn none
  let n7 ← programWithTypes "NamedTypeNameN7SignatureLater" duplicateTypes #[]
    #[badSignatureCallable]
  expectCfgErrCode "N7 named types before callable signature" .duplicate n7
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
  }
  let n8 ← programWithTypes "NamedTypeNameN8CfgLater" duplicateTypes #[]
    #[badCfgCallable]
  expectCfgErrCode "N8 named types before CFG" .duplicate n8

/-- SPEC-SEM-WIRE-001 §5 named TypeDecl contiguous-prefix rank: all
    `name=some` named Struct/Enum declarations must occupy a contiguous prefix
    of the `types` table (indices `0 .. namedCount-1`). Any named declaration
    appearing after an anonymous declaration is `.nonCanonical` on both shipped
    paths (structure gate + structure-gated encoder). Transport decode is
    unchanged. The `namedPrefix` subphase of `validateTypeKeyPhasesV1` runs
    before the `primitiveLeaf` and `recursiveAnonymous` subphases; table id/
    index, shallow references, and type-shape/FieldSpec/Map-key legality are
    earlier prerequisites, while named-name uniqueness, canonical valueBytes,
    callable signature, and requirements are later successors. -/
private def testNamedTypePrefixRank : IO Unit := do
  -- P0: anonymous-only type table — no named declarations, legal.
  let p0 ← programWithTypes "NamedPrefixP0Anonymous" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 }
  ]
  expectCfgOk "P0 anonymous-only type table" p0
  -- P1: all-named type table — contiguous prefix covers the whole table.
  --   Two named Enum declarations, each with one variant whose payloadTypes
  --   is empty (a legal shape: enum variants must be nonempty, but each
  --   variant's payload list may be empty). No recursive named-body
  --   reference is constructed, so the named-body `Option`-cycle legality
  --   rule (now enforced by a later `namedBodyCycle` subphase) is not
  --   exercised as a positive here.
  let p1 ← programWithTypes "NamedPrefixP1AllNamed" #[
    { id := 0, name := some "E1",
      shape := .enum #[{ name := "a", payloadTypes := #[] }] },
    { id := 1, name := some "E2",
      shape := .enum #[{ name := "b", payloadTypes := #[] }] }
  ]
  expectCfgOk "P1 all-named contiguous prefix" p1
  -- P2: named prefix + anonymous suffix — named declarations at indices 0,1
  -- followed by anonymous declarations. Legal: the named prefix is contiguous.
  let p2 ← programWithTypes "NamedPrefixP2NamedThenAnon" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "x", typeId := 2 }] },
    { id := 1, name := some "E",
      shape := .enum #[{ name := "v", payloadTypes := #[2] }] },
    { id := 2, name := none, shape := .bool },
    { id := 3, name := none, shape := .array 2 4 }
  ]
  expectCfgOk "P2 named prefix then anonymous suffix" p2
  -- N1: anonymous→named — an anonymous declaration precedes a named one, so
  -- the named declarations are not a contiguous prefix.
  let n1 ← programWithTypes "NamedPrefixN1AnonBeforeNamed" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  expectCfgErrCode "N1 anonymous before named" .nonCanonical n1
  -- N2: named→anonymous→named — the named prefix is broken by an anonymous
  -- declaration in the middle; the second named declaration is out of prefix.
  let n2 ← programWithTypes "NamedPrefixN2NamedAnonNamed" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "x", typeId := 2 }] },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := some "E",
      shape := .enum #[{ name := "v", payloadTypes := #[1] }] }
  ]
  expectCfgErrCode "N2 named then anonymous then named" .nonCanonical n2
  -- Phase precedence: namedPrefix runs before primitiveLeaf. A broken prefix
  -- plus a duplicate primitive Bool must report the `.namedPrefix` phase first
  -- (both share the public `.nonCanonical` wire error).
  let phase1Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  let phase1 ← programWithTypes "NamedPrefixPhase1PrefixBeforePrimitive"
    phase1Types
  expectCfgErrCode "Phase1 prefix before primitive (wire)" .nonCanonical phase1
  expectTypeKeyPhase "Phase1 prefix before primitive (phase)"
    .namedPrefix .nonCanonical phase1Types
  -- Phase precedence: namedPrefix runs before recursiveAnonymous. A broken
  -- prefix plus a duplicate anonymous Array class must report `.namedPrefix`.
  let phase2Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 },
    { id := 3, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  expectTypeKeyPhase "Phase2 prefix before recursive"
    .namedPrefix .nonCanonical phase2Types
  -- Phase seam regression: a pure primitive duplicate (no named declarations)
  -- still reports `.primitiveLeaf`; a pure recursive duplicate still reports
  -- `.recursiveAnonymous`. The new phase does not disturb existing ordering.
  let purePrimTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .bool }
  ]
  expectTypeKeyPhase "Phase seam pure primitive duplicate" .primitiveLeaf
    .nonCanonical purePrimTypes
  let pureRecTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 }
  ]
  expectTypeKeyPhase "Phase seam pure recursive duplicate" .recursiveAnonymous
    .nonCanonical pureRecTypes
  -- Predecessor ordering: table id/index precedes namedPrefix. A bad table id
  -- plus a broken prefix fails on the table-id check first (`.duplicate`).
  let pre1 ← programWithTypes "NamedPrefixPre1TableIdFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 7, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  expectCfgErrCode "Pre1 table id before prefix" .duplicate pre1
  -- Predecessor ordering: shallow reference range precedes namedPrefix. An OOR
  -- child plus a broken prefix fails as `.badReference` first.
  let pre2 ← programWithTypes "NamedPrefixPre2RefFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 99 }] }
  ]
  expectCfgErrCode "Pre2 shallow ref before prefix" .badReference pre2
  -- Predecessor ordering: type-shape legality precedes namedPrefix. An invalid
  -- integer width plus a broken prefix fails as `.badType` first.
  let pre3 ← programWithTypes "NamedPrefixPre3ShapeFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 7 },
    { id := 2, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  expectCfgErrCode "Pre3 type shape before prefix" .badType pre3
  -- Predecessor ordering: FieldSpec catalog legality precedes namedPrefix. An
  -- invalid FieldSpec modulus plus a broken prefix fails as `.badType` first.
  let zeroMod := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let pre4 ← programWithTypes "NamedPrefixPre4FieldSpecFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none,
      shape := .field { id := bn254FrFieldSpecV1.id, modulusBE := zeroMod } },
    { id := 2, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  expectCfgErrCode "Pre4 FieldSpec before prefix" .badType pre4
  -- Predecessor ordering: Map-key legality precedes namedPrefix. An illegal
  -- Map key plus a broken prefix fails as `.badType` first.
  let pre5 ← programWithTypes "NamedPrefixPre5MapKeyFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .option 0 },
    { id := 2, name := none, shape := .map 1 0 },
    { id := 3, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  expectCfgErrCode "Pre5 Map-key legality before prefix" .badType pre5
  -- Successor ordering: namedPrefix precedes named-name uniqueness. A broken
  -- prefix plus duplicate named names fails on the prefix first.
  let post1 ← programWithTypes "NamedPrefixPost1NamedNamesLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "Dup",
      shape := .struct #[{ name := "x", typeId := 0 }] },
    { id := 2, name := some "Dup",
      shape := .enum #[{ name := "v", payloadTypes := #[0] }] }
  ]
  expectCfgErrCode "Post1 prefix before named names" .nonCanonical post1
  -- Successor ordering: namedPrefix precedes canonical valueBytes.
  let post2 ← programWithTypes "NamedPrefixPost2ValueLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ] #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
  expectCfgErrCode "Post2 prefix before canonical value" .nonCanonical post2
  -- Successor ordering: namedPrefix precedes callable signature.
  let post3 ← programWithTypes "NamedPrefixPost3SignatureLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ] #[] #[cfgCallableKindName .pureFn none]
  expectCfgErrCode "Post3 prefix before callable signature" .nonCanonical post3
  -- Successor ordering: namedPrefix precedes requirements.
  let post4Base ← programWithTypes "NamedPrefixPost4RequirementLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  let post4 : SemanticProgramDataV1 := {
    post4Base with requirements := { items := #[req "unknown.capability"] }
  }
  expectCfgErrCode "Post4 prefix before requirements" .nonCanonical post4
  -- Successor ordering: namedPrefix precedes per-callable CFG. A broken
  --   prefix plus a signature-valid but CFG-invalid callable fails on the
  --   prefix first (`.nonCanonical`); removing/deferring the prefix gate
  --   would expose the later `.badCfg`. The callable is not signature-invalid
  --   (pureFn "f" with a Bool result); the CFG invalidity is an out-of-range
  --   jump target (block id 9 with no such block).
  let cfgInvalidCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 }) (cfgBoolLit 0)]
      (.jump (cfgJumpTarget 9))] with
      id := 0
  }
  let post5 ← programWithTypes "NamedPrefixPost5CfgLater" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ] #[] #[cfgInvalidCallable]
  expectCfgErrCode "Post5 prefix before CFG" .nonCanonical post5
  -- Transport regression: `decodeSemanticProgramDataV1` is structure-free and
  --   must accept an interleaved anonymous→named TypeDecl carrier exactly as
  --   shipped, while the structure gate, the structure-gated encoder, and the
  --   carrier re-encode path (`decodeSemanticProgramV1`) all reject it as
  --   `.nonCanonical`. The raw envelope is hand-assembled with the low-level
  --   encode helpers (not `encodeSemanticProgramDataV1`, which is
  --   structure-gated), mirroring `testValueBytesTransportRegression`.
  let trBase ← emptyProgram "NamedPrefixTransport"
  let trTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "x", typeId := 0 }] }
  ]
  let trQnB ← expectOk "tr qn" (encodeQualifiedName trBase.qualifiedName)
  let trTypesB ← expectOk "tr types" (encodeArray encodeTypeDeclV1 trTypes)
  let trEmptyState ← expectOk "tr state" (encodeArray encodeStateDeclV1 #[])
  let trEmptyEvents ← expectOk "tr events" (encodeArray encodeEventDeclV1 #[])
  let trEmptyErrors ← expectOk "tr errors" (encodeArray encodeErrorDeclV1 #[])
  let trEmptyCallables ←
    expectOk "tr callables" (encodeArray encodeCallableV1 #[])
  let trEmptyInvariants ←
    expectOk "tr inv" (encodeArray encodeInvariantDeclV1 #[])
  let trEmptyConstants ←
    expectOk "tr consts" (encodeArray encodeConstantV1 #[])
  let trReqB ←
    expectOk "tr reqs" (encodeProgramRequirementsV1 { items := #[] })
  let trBody ← expectOk "tr body" (encodeTagged "SemanticProgram.Data" #[
    trQnB, trTypesB, trEmptyConstants, trEmptyState, trEmptyEvents,
    trEmptyErrors, trEmptyCallables, trEmptyInvariants, trReqB
  ])
  let trMagic := semanticProgramMagicV1.toUTF8.push 0
  let trBytes := trMagic.append trBody
  let trDecoded ← expectOk "tr transport accepts interleaved prefix"
    (decodeSemanticProgramDataV1 trBytes)
  expect (trDecoded.types == trTypes)
    "tr interleaved TypeDecl table preserved on transport"
  expectErr "tr structure rejects interleaved prefix" .nonCanonical
    (validateSemanticProgramStructureV1 trDecoded)
  expectErr "tr encode rejects interleaved prefix" .nonCanonical
    (encodeSemanticProgramDataV1 trDecoded)
  expectErr "tr carrier rejects interleaved prefix" .nonCanonical
    (decodeSemanticProgramV1 trBytes)

/-! ### named-body Option-cycle legality (SPEC §5)

    SPEC §5 requires that every recursive cycle in the type graph pass
    simultaneously through a reserved named key and an `Option` node. The
    earlier `recursiveAnonymous` subphase already rejects all
    anonymous-container cycles that pass through no named anchor. This slice
    closes the remaining gap: any cycle that passes through a reserved named
    Struct/Enum key must also pass through at least one anonymous `Option`.

    The recommended equivalent global algorithm is implemented: remove every
    `.option` node (and its incident edges) from the TypeId directed graph,
    then require the induced subgraph on the remaining nodes to be acyclic.
    This rejects exactly the cycles that contain no `Option`; combined with
    `recursiveAnonymous` rejecting anonymous-only cycles, the two gates
    together ensure an accepted cycle simultaneously contains a named key
    and an `Option`. Per-named-root DFS and "path has seen an Option" walks
    are rejected because they miss the sibling-branch trap. The new phase is
    ordered after `recursiveAnonymous` and before named-name uniqueness /
    canonical valueBytes / callable signature / CFG / requirements. -/

private def testNamedBodyOptionCycleLegality : IO Unit := do
  -- Positives — acyclic or Option-on-cycle; both shipped paths accept.
  -- P1: acyclic named Struct → Bool. No cycle.
  let p1 ← programWithTypes "NamedBodyP1AcyclicNamedBool" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "x", typeId := 1 }] },
    { id := 1, name := none, shape := .bool }
  ]
  expectCfgOk "P1 acyclic named Struct → Bool" p1
  -- P2: named Struct → Option(self). The Option node is removed from the
  --   induced graph, so the Struct has no outgoing edge and there is no cycle.
  let p2 ← programWithTypes "NamedBodyP2StructOptionSelf" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "tail", typeId := 1 }] },
    { id := 1, name := none, shape := .option 0 }
  ]
  expectCfgOk "P2 named Struct → Option(self)" p2
  -- P3: named Enum variant payload → Option(self). Same reasoning: the
  --   Option edge is removed, so the Enum has no outgoing edge.
  let p3 ← programWithTypes "NamedBodyP3EnumPayloadOptionSelf" #[
    { id := 0, name := some "E",
      shape := .enum #[{ name := "v", payloadTypes := #[1] }] },
    { id := 1, name := none, shape := .option 0 }
  ]
  expectCfgOk "P3 named Enum payload → Option(self)" p3
  -- P4: mutual named cycle whose actual path includes an Option. A→B (direct
  --   field), B→Option A (the only B→A path goes through the removed Option).
  --   After removing the Option, B has no outgoing edge, so the induced graph
  --   is acyclic. The named anchor + Option both lie on the recursive cycle.
  let p4 ← programWithTypes "NamedBodyP4MutualCycleWithOption" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "b", typeId := 1 }] },
    { id := 1, name := some "B",
      shape := .struct #[{ name := "a", typeId := 2 }] },
    { id := 2, name := none, shape := .option 0 }
  ]
  expectCfgOk "P4 mutual named cycle through Option" p4
  -- P5: named → Array → Option → named. The Array's element is an Option,
  --   so the Array's only outgoing edge is removed. The named Struct's edge
  --   to the Array stays, but the Array has no further edge in the induced
  --   graph. No cycle.
  let p5 ← programWithTypes "NamedBodyP5NamedArrayOptionNamed" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "xs", typeId := 1 }] },
    { id := 1, name := none, shape := .array 2 4 },
    { id := 2, name := none, shape := .option 0 }
  ]
  expectCfgOk "P5 named → Array → Option → named" p5
  -- P6: Map value path includes an Option. A→Map (Bool → Option A). The Map's
  --   value edge is to the Option, which is removed; the key edge is to Bool
  --   (a leaf). So the Map has no edge to A; the induced graph is acyclic.
  --   Named prefix: A at index 0, anonymous Bool/Map/Option suffix.
  let p6 ← programWithTypes "NamedBodyP6MapValueOptionNamed" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "m", typeId := 2 }] },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .map 1 3 },
    { id := 3, name := none, shape := .option 0 }
  ]
  expectCfgOk "P6 Map value path includes Option" p6
  -- Negatives — a cycle in the induced graph (no Option on the cycle). All
  -- reject as `.nonCanonical` on both shipped paths.
  -- N1: direct named Struct self-cycle, no Option.
  let n1 ← programWithTypes "NamedBodyN1StructSelf" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "self", typeId := 0 }] }
  ]
  expectCfgErrCode "N1 direct named Struct self-cycle" .nonCanonical n1
  -- N2: named Enum self payload, no Option.
  let n2 ← programWithTypes "NamedBodyN2EnumSelfPayload" #[
    { id := 0, name := some "E",
      shape := .enum #[{ name := "v", payloadTypes := #[0] }] }
  ]
  expectCfgErrCode "N2 named Enum self payload" .nonCanonical n2
  -- N3: two named mutual cycle, no Option.
  let n3 ← programWithTypes "NamedBodyN3TwoMutualNoOption" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "b", typeId := 1 }] },
    { id := 1, name := some "B",
      shape := .struct #[{ name := "a", typeId := 0 }] }
  ]
  expectCfgErrCode "N3 two named mutual no Option" .nonCanonical n3
  -- N4: three named mutual cycle, no Option.
  let n4 ← programWithTypes "NamedBodyN4ThreeMutualNoOption" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "b", typeId := 1 }] },
    { id := 1, name := some "B",
      shape := .struct #[{ name := "c", typeId := 2 }] },
    { id := 2, name := some "C",
      shape := .struct #[{ name := "a", typeId := 0 }] }
  ]
  expectCfgErrCode "N4 three named mutual no Option" .nonCanonical n4
  -- N5: Struct → Array(self). The Array element is the named Struct, so the
  --   induced graph has A→Array and Array→A, a cycle with no Option.
  let n5 ← programWithTypes "NamedBodyN5StructArraySelf" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "xs", typeId := 1 }] },
    { id := 1, name := none, shape := .array 0 4 }
  ]
  expectCfgErrCode "N5 Struct → Array(self)" .nonCanonical n5
  -- N6: Struct → Map<Bool,self>. The Map value is the named Struct; both the
  --   Map key (Bool, leaf) and value (A) edges stay, giving A→Map and Map→A.
  --   Named prefix: A at index 0, anonymous Bool/Map suffix.
  let n6 ← programWithTypes "NamedBodyN6StructMapBoolSelf" #[
    { id := 0, name := some "A",
      shape := .struct #[{ name := "m", typeId := 2 }] },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .map 1 0 }
  ]
  expectCfgErrCode "N6 Struct → Map<Bool,self>" .nonCanonical n6
  -- N7: sibling-branch trap. A has both an Option(B) field and a direct B
  --   field; B→A. A "path has seen an Option" walk that follows the
  --   Option(B) branch would wrongly accept, because the Option sits on that
  --   branch. But the direct A→B→A cycle contains no Option. The global
  --   induced-graph algorithm correctly rejects: A→B (direct field, both
  --   non-Option) and B→A (non-Option) form a cycle with no Option node.
  let n7 ← programWithTypes "NamedBodyN7SiblingBranchTrap" #[
    { id := 0, name := some "A",
      shape := .struct #[
        { name := "optB", typeId := 2 },
        { name := "b", typeId := 1 }
      ] },
    { id := 1, name := some "B",
      shape := .struct #[{ name := "a", typeId := 0 }] },
    { id := 2, name := none, shape := .option 1 }
  ]
  expectCfgErrCode "N7 sibling-branch trap (direct A→B→A no Option)"
    .nonCanonical n7
  -- Phase precedence: the new `.namedBodyCycle` phase is ordered after
  --   `recursiveAnonymous`. A pure recursive duplicate (no named-body cycle)
  --   must still report `.recursiveAnonymous`, not the new phase.
  let prec1Types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .array 0 4 },
    { id := 2, name := none, shape := .array 0 4 }
  ]
  expectTypeKeyPhase "Prec1 recursiveAnonymous before namedBodyCycle"
    .recursiveAnonymous .nonCanonical prec1Types
  -- A pure named-body cycle (no primitive/recursive duplicate) must report
  --   the `.namedBodyCycle` phase.
  expectTypeKeyPhase "Prec2 pure named-body cycle phase"
    .namedBodyCycle .nonCanonical
    #[{ id := 0, name := some "S",
        shape := .struct #[{ name := "self", typeId := 0 }] }]
  -- Predecessor ordering: table id/index precedes the new phase. A bad table
  --   id plus a named self-cycle fails on the table-id check first.
  let pre1 ← programWithTypes "NamedBodyPre1TableIdFirst" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "self", typeId := 7 }] },
    { id := 7, name := some "S",
      shape := .struct #[{ name := "self", typeId := 0 }] }
  ]
  expectCfgErrCode "Pre1 table id before named-body cycle" .duplicate pre1
  -- Predecessor: shallow reference range precedes the new phase.
  let pre2 ← programWithTypes "NamedBodyPre2ReferenceFirst" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "self", typeId := 99 }] }
  ]
  expectCfgErrCode "Pre2 shallow ref before named-body cycle" .badReference
    pre2
  -- Predecessor: type-shape legality precedes the new phase. An empty struct
  --   plus a named self-cycle fails on the shape check first.
  let pre3 ← programWithTypes "NamedBodyPre3ShapeFirst" #[
    { id := 0, name := some "S", shape := .struct #[] },
    { id := 1, name := some "T",
      shape := .struct #[{ name := "self", typeId := 1 }] }
  ]
  expectCfgErrCode "Pre3 type shape before named-body cycle" .badType pre3
  -- Predecessor: namedPrefix precedes the new phase. A broken prefix plus a
  --   named self-cycle fails on the prefix first.
  let pre4 ← programWithTypes "NamedBodyPre4NamedPrefixFirst" #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := some "S",
      shape := .struct #[{ name := "self", typeId := 1 }] }
  ]
  expectCfgErrCode "Pre4 namedPrefix before named-body cycle" .nonCanonical
    pre4
  -- Predecessor: primitiveLeaf precedes the new phase. A duplicate primitive
  --   plus a named self-cycle fails on primitive interning first. Named
  --   prefix occupies index 0; duplicate anonymous Bools follow.
  let pre5 ← programWithTypes "NamedBodyPre5PrimitiveLeafFirst" #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "self", typeId := 0 }] },
    { id := 1, name := none, shape := .bool },
    { id := 2, name := none, shape := .bool }
  ]
  expectCfgErrCode "Pre5 primitiveLeaf before named-body cycle" .nonCanonical
    pre5
  -- Predecessor: recursiveAnonymous precedes the new phase. An
  --   anonymous-container self cycle plus a named self-cycle fails on the
  --   recursive phase first. Named prefix occupies index 0; the anonymous
  --   Option self-cycle node follows.
  let pre6Types : Array TypeDeclV1 := #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "self", typeId := 0 }] },
    { id := 1, name := none, shape := .option 1 }
  ]
  let pre6 ← programWithTypes "NamedBodyPre6RecursiveAnonymousFirst"
    pre6Types
  expectCfgErrCode "Pre6 recursiveAnonymous before named-body cycle"
    .nonCanonical pre6
  expectTypeKeyPhase "Pre6 recursiveAnonymous phase before namedBodyCycle"
    .recursiveAnonymous .nonCanonical pre6Types
  -- Successor ordering: the new phase precedes named-name uniqueness. A named
  --   self-cycle plus duplicate named names fails on the cycle first.
  let post1 ← programWithTypes "NamedBodyPost1NamedNamesLater" #[
    { id := 0, name := some "Dup",
      shape := .struct #[{ name := "self", typeId := 0 }] },
    { id := 1, name := some "Dup",
      shape := .struct #[{ name := "self", typeId := 1 }] }
  ]
  expectCfgErrCode "Post1 named-body cycle before named names" .nonCanonical
    post1
  -- Successor: the new phase precedes canonical valueBytes. A named
  --   self-cycle plus a malformed Constant value fails on the cycle first.
  let post2 ← programWithTypes "NamedBodyPost2ValueLater"
    #[{ id := 0, name := some "S",
        shape := .struct #[{ name := "self", typeId := 0 }] }]
    #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
  expectCfgErrCode "Post2 named-body cycle before canonical value"
    .nonCanonical post2
  -- Successor: the new phase precedes callable signature.
  let post3 ← programWithTypes "NamedBodyPost3SignatureLater"
    #[{ id := 0, name := some "S",
        shape := .struct #[{ name := "self", typeId := 0 }] }]
    #[] #[cfgCallableKindName .pureFn none]
  expectCfgErrCode "Post3 named-body cycle before callable signature"
    .nonCanonical post3
  -- Successor: the new phase precedes requirements.
  let post4Base ← programWithTypes "NamedBodyPost4RequirementLater"
    #[{ id := 0, name := some "S",
        shape := .struct #[{ name := "self", typeId := 0 }] }]
  let post4 : SemanticProgramDataV1 := {
    post4Base with requirements := { items := #[req "unknown.capability"] }
  }
  expectCfgErrCode "Post4 named-body cycle before requirements" .nonCanonical
    post4
  -- Successor: the new phase precedes per-callable CFG. A named self-cycle
  --   plus a CFG-invalid callable fails on the cycle first.
  let cfgInvalidCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 }) (cfgBoolLit 0)]
      (.jump (cfgJumpTarget 9))] with
      id := 0
  }
  let post5 ← programWithTypes "NamedBodyPost5CfgLater"
    #[{ id := 0, name := some "S",
        shape := .struct #[{ name := "self", typeId := 0 }] }]
    #[] #[cfgInvalidCallable]
  expectCfgErrCode "Post5 named-body cycle before CFG" .nonCanonical post5
  -- Transport regression: `decodeSemanticProgramDataV1` is structure-free and
  --   must accept a direct named Struct self-cycle exactly as shipped, while
  --   the structure gate, the structure-gated encoder, and the carrier
  --   re-encode path (`decodeSemanticProgramV1`) all reject it as
  --   `.nonCanonical`. The raw envelope is hand-assembled with the
  --   low-level encode helpers (not `encodeSemanticProgramDataV1`, which is
  --   structure-gated).
  let trBase ← emptyProgram "NamedBodyTransport"
  let trTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := "self", typeId := 0 }] }
  ]
  let trQnB ← expectOk "tr qn" (encodeQualifiedName trBase.qualifiedName)
  let trTypesB ← expectOk "tr types" (encodeArray encodeTypeDeclV1 trTypes)
  let trEmptyState ← expectOk "tr state" (encodeArray encodeStateDeclV1 #[])
  let trEmptyEvents ← expectOk "tr events" (encodeArray encodeEventDeclV1 #[])
  let trEmptyErrors ← expectOk "tr errors" (encodeArray encodeErrorDeclV1 #[])
  let trEmptyCallables ←
    expectOk "tr callables" (encodeArray encodeCallableV1 #[])
  let trEmptyInvariants ←
    expectOk "tr inv" (encodeArray encodeInvariantDeclV1 #[])
  let trEmptyConstants ←
    expectOk "tr consts" (encodeArray encodeConstantV1 #[])
  let trReqB ←
    expectOk "tr reqs" (encodeProgramRequirementsV1 { items := #[] })
  let trBody ← expectOk "tr body" (encodeTagged "SemanticProgram.Data" #[
    trQnB, trTypesB, trEmptyConstants, trEmptyState, trEmptyEvents,
    trEmptyErrors, trEmptyCallables, trEmptyInvariants, trReqB
  ])
  let trMagic := semanticProgramMagicV1.toUTF8.push 0
  let trBytes := trMagic.append trBody
  let trDecoded ← expectOk "tr transport accepts named self-cycle"
    (decodeSemanticProgramDataV1 trBytes)
  expect (trDecoded.types == trTypes)
    "tr named self-cycle TypeDecl table preserved on transport"
  expectErr "tr structure rejects named self-cycle" .nonCanonical
    (validateSemanticProgramStructureV1 trDecoded)
  expectErr "tr encode rejects named self-cycle" .nonCanonical
    (encodeSemanticProgramDataV1 trDecoded)
  expectErr "tr carrier rejects named self-cycle" .nonCanonical
    (decodeSemanticProgramV1 trBytes)
  -- Resource regression: an approximately 5000-node named Struct acyclic
  --   chain (all named prefix, terminal anonymous Bool suffix) must complete
  --   the structure gate and the structure-gated encoder on a real shipped
  --   path. Each named Struct S_i has a single field pointing at S_{i+1};
  --   the last points at the terminal anonymous Bool. No cycle is
  --   constructed, so this is an acyclic resource fixture that exercises the
  --   O(V+E) time / O(V+stack) space DFS linearly; the named-body cycle
  --   condition is not exercised here (no cycle present).
  let chainLen : Nat := 5000
  let boolId : UInt32 := UInt32.ofNat chainLen
  let mut chainTypes : Array TypeDeclV1 := Array.emptyWithCapacity
    (chainLen + 1)
  let mut i := 0
  while i < chainLen do
    chainTypes := chainTypes.push {
      id := UInt32.ofNat i
      name := some s!"S{i}"
      shape := .struct #[{ name := "n", typeId := UInt32.ofNat (i + 1) }]
    }
    i := i + 1
  -- Terminal anonymous Bool at the suffix (after the named prefix).
  chainTypes := chainTypes.push
    { id := boolId, name := none, shape := .bool }
  let chain ← programWithTypes "NamedBodyResourceChain" chainTypes
  expectCfgOk "Resource chain (5k named Struct) structure + encode" chain
  -- High-fanout acyclic named Enum resource case: a single named Enum with
  --   many variants, each carrying one UInt8 payload (all pointing at the
  --   same leaf). The induced graph is acyclic (Enum → UInt8 leaf, leaf has
  --   no children), so both shipped paths accept. This locks the linear
  --   `nonOptionChildTypeIds` Enum flatten: a high-fanout Enum must not
  --   degrade to O(E²) accumulator copying, and the DFS must finish linearly.
  --   Bounded to keep the test light while exercising a wide fan-out.
  let fanout : Nat := 1000
  let mut enumVariants : Array EnumVariantV1 :=
    Array.emptyWithCapacity fanout
  let mut vi := 0
  while vi < fanout do
    enumVariants := enumVariants.push
      { name := s!"v{vi}", payloadTypes := #[1] }
    vi := vi + 1
  let highFanoutTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "Wide",
      shape := .enum enumVariants },
    { id := 1, name := none, shape := .uint 8 }
  ]
  let highFanout ← programWithTypes "NamedBodyHighFanoutEnum" highFanoutTypes
  expectCfgOk "High-fanout acyclic named Enum (1k variants) structure + encode"
    highFanout

/-- SPEC-SEM-WIRE-001 §6 Constant names are exact-string unique within
    the constants table. Identifier grammar/NFC and other declaration tables
    remain separate gates. -/
private def testConstantNameUniqueness : IO Unit := do
  let p0 ← programWithTypes "ConstantNameP0Empty" cfgBoolTypes
  expectCfgOk "P0 empty constants table" p0
  let p1 ← programWithTypes "ConstantNameP1Distinct" cfgBoolTypes
    #[constOf 0 "x" 0 (ByteArray.mk #[0]),
      constOf 1 "y" 0 (ByteArray.mk #[1]),
      constOf 2 "X" 0 (ByteArray.mk #[0])]
  expectCfgOk "P1 distinct case-sensitive constant names" p1
  let duplicateConstants : Array ConstantV1 :=
    #[constOf 0 "x" 0 (ByteArray.mk #[0]),
      constOf 1 "x" 0 (ByteArray.mk #[1])]
  let n1 ← programWithTypes "ConstantNameN1Duplicate" cfgBoolTypes
    duplicateConstants
  expectCfgErrCode "N1 duplicate constant names" .duplicate n1
  -- Shallow Constant TypeId range validation precedes name uniqueness.
  let n2 ← programWithTypes "ConstantNameN2ReferenceFirst" cfgBoolTypes
    #[constOf 0 "x" 0 (ByteArray.mk #[0]),
      constOf 1 "x" 99 (ByteArray.mk #[1])]
  expectCfgErrCode "N2 Constant TypeId before names" .badReference n2
  -- Canonical Constant valueBytes validation precedes name uniqueness.
  let n3 ← programWithTypes "ConstantNameN3ValueFirst" cfgBoolTypes
    #[constOf 0 "x" 0 (ByteArray.mk #[0]),
      constOf 1 "x" 0 (ByteArray.mk #[2])]
  expectCfgErrCode "N3 Constant value before names" .nonCanonical n3
  -- Canonical callable valueBytes also precede Constant-name uniqueness.
  let badValueCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[2]))]
      (.return_ none)] with
      id := 0
  }
  let n4 ← programWithTypes "ConstantNameN4CallableValueFirst" cfgBoolTypes
    duplicateConstants #[badValueCallable]
  expectCfgErrCode "N4 callable value before constant names" .nonCanonical n4
  -- Constant-name uniqueness precedes callable signature validation.
  let badSignatureCallable := cfgCallableKindName .pureFn none
  let n5 ← programWithTypes "ConstantNameN5BeforeSignature" cfgBoolTypes
    duplicateConstants #[badSignatureCallable]
  expectCfgErrCode "N5 constant names before callable signature" .duplicate n5
  -- Constant-name uniqueness also precedes per-callable CFG validation.
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
  }
  let n6 ← programWithTypes "ConstantNameN6BeforeCfg" cfgBoolTypes
    duplicateConstants #[badCfgCallable]
  expectCfgErrCode "N6 constant names before CFG" .duplicate n6

/-- SPEC-SEM-WIRE-001 §6 StateDecl names are exact-string unique within the
    logicalState table. Identifier grammar/NFC and other declaration tables
    remain separate gates. -/
private def testLogicalStateNameUniqueness : IO Unit := do
  let stateX0 : StateDeclV1 := {
    id := 0, name := "x", typeId := 0, visibility := .public_
  }
  let stateY1 : StateDeclV1 := {
    id := 1, name := "y", typeId := 0, visibility := .public_
  }
  let stateUpperX2 : StateDeclV1 := {
    id := 2, name := "X", typeId := 0, visibility := .public_
  }
  let base ← programWithTypes "LogicalStateNameBase" cfgBoolTypes
  let p0 := { base with logicalState := #[] }
  expectCfgOk "P0 empty logicalState table" p0
  let orderedStates := #[stateX0, stateY1, stateUpperX2]
  let p1 := { base with logicalState := orderedStates }
  expectCfgOk "P1 distinct case-sensitive state names" p1
  let p1Bytes ← expectOk "P1 logicalState order encode"
    (encodeSemanticProgramDataV1 p1)
  let p1Decoded ← expectOk "P1 logicalState order decode"
    (decodeSemanticProgramDataV1 p1Bytes)
  expect (p1Decoded.logicalState == orderedStates)
    "P1 logicalState source order survives wire round-trip"
  let stateX1 : StateDeclV1 := { stateX0 with id := 1 }
  let duplicateStates := #[stateX0, stateX1]
  let n1 := { base with logicalState := duplicateStates }
  expectCfgErrCode "N1 duplicate logicalState names" .duplicate n1
  -- Shallow StateDecl TypeId range validation precedes name uniqueness.
  let badRefStateX1 : StateDeclV1 := { stateX1 with typeId := 99 }
  let n2 := { base with logicalState := #[stateX0, badRefStateX1] }
  expectCfgErrCode "N2 StateDecl TypeId before names" .badReference n2
  -- Canonical Constant valueBytes validation precedes state-name uniqueness.
  let n3 := {
    base with
      constants := #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
      logicalState := duplicateStates
  }
  expectCfgErrCode "N3 Constant value before state names" .nonCanonical n3
  -- Canonical callable valueBytes also precede state-name uniqueness.
  let badValueCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[2]))]
      (.return_ none)] with
      id := 0
  }
  let n4 := {
    base with logicalState := duplicateStates, callables := #[badValueCallable]
  }
  expectCfgErrCode "N4 callable value before state names" .nonCanonical n4
  -- State-name uniqueness precedes callable signature validation.
  let badSignatureCallable := cfgCallableKindName .pureFn none
  let n5 := {
    base with logicalState := duplicateStates, callables := #[badSignatureCallable]
  }
  expectCfgErrCode "N5 state names before callable signature" .duplicate n5
  -- State-name uniqueness also precedes per-callable CFG validation.
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
  }
  let n6 := {
    base with logicalState := duplicateStates, callables := #[badCfgCallable]
  }
  expectCfgErrCode "N6 state names before CFG" .duplicate n6

/-- SPEC-SEM-WIRE-001 §6 EventDecl names are exact-string unique within
    the events table. Identifier grammar/NFC and other declaration tables
    remain separate gates. -/
private def testEventNameUniqueness : IO Unit := do
  let eventX0 : EventDeclV1 := { id := 0, name := "x", fields := #[] }
  let eventY1 : EventDeclV1 := { id := 1, name := "y", fields := #[] }
  let eventUpperX2 : EventDeclV1 := { id := 2, name := "X", fields := #[] }
  let base ← programWithTypes "EventNameBase" cfgBoolTypes
  let p0 := { base with events := #[] }
  expectCfgOk "P0 empty events table" p0
  let orderedEvents := #[eventX0, eventY1, eventUpperX2]
  let p1 := { base with events := orderedEvents }
  expectCfgOk "P1 distinct case-sensitive event names" p1
  let p1Bytes ← expectOk "P1 events order encode"
    (encodeSemanticProgramDataV1 p1)
  let p1Decoded ← expectOk "P1 events order decode"
    (decodeSemanticProgramDataV1 p1Bytes)
  expect (p1Decoded.events == orderedEvents)
    "P1 EventDecl source order survives wire round-trip"
  let eventX1 : EventDeclV1 := { eventX0 with id := 1 }
  let duplicateEvents := #[eventX0, eventX1]
  let n1 := { base with events := duplicateEvents }
  expectCfgErrCode "N1 duplicate EventDecl names" .duplicate n1
  -- Shallow InterfaceField TypeId range validation precedes name uniqueness.
  let badRefField : InterfaceFieldV1 := {
    name := "payload", typeId := 99, visibility := .public_
  }
  let badRefEventX1 : EventDeclV1 := { eventX1 with fields := #[badRefField] }
  let n2 := { base with events := #[eventX0, badRefEventX1] }
  expectCfgErrCode "N2 Event field TypeId before names" .badReference n2
  -- Canonical Constant valueBytes validation precedes the duplicate-name phase.
  let n3 := {
    base with
      constants := #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
      events := duplicateEvents
  }
  expectCfgErrCode "N3 Constant value before event names" .nonCanonical n3
  -- Canonical callable valueBytes also precede the duplicate-name phase.
  let badValueCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[2]))]
      (.return_ none)] with
      id := 0
  }
  let n4 := { base with events := duplicateEvents, callables := #[badValueCallable] }
  expectCfgErrCode "N4 callable value before event names" .nonCanonical n4
  -- Canonical SwitchCase valueBytes also precede the duplicate-name phase.
  let badSwitchCallable := cfgCallable #[
    cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
      (.switch 0 #[{
        typeId := 0
        valueBytes := ByteArray.mk #[2]
        target := cfgJumpTarget 1
      }] none),
    cfgBlock 1 (.return_ (some 0))
  ]
  let n5 := {
    base with events := duplicateEvents, callables := #[badSwitchCallable]
  }
  expectCfgErrCode "N5 SwitchCase value before event names" .nonCanonical n5
  -- The grouped duplicate-name phase precedes callable signature validation.
  let badSignatureCallable := cfgCallableKindName .pureFn none
  let n6 := {
    base with events := duplicateEvents, callables := #[badSignatureCallable]
  }
  expectCfgErrCode "N6 event names before callable signature" .duplicate n6
  -- The grouped duplicate-name phase also precedes per-callable CFG validation.
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
  }
  let n7 := { base with events := duplicateEvents, callables := #[badCfgCallable] }
  expectCfgErrCode "N7 event names before CFG" .duplicate n7

/-- SPEC-SEM-WIRE-001 §6 ErrorDecl names are exact-string unique within
    the errors table. Identifier grammar/NFC and other declaration tables
    remain separate gates. -/
private def testErrorNameUniqueness : IO Unit := do
  let errorX0 : ErrorDeclV1 := { id := 0, name := "x", fields := #[] }
  let errorY1 : ErrorDeclV1 := { id := 1, name := "y", fields := #[] }
  let errorUpperX2 : ErrorDeclV1 := { id := 2, name := "X", fields := #[] }
  let base ← programWithTypes "ErrorNameBase" cfgBoolTypes
  let p0 := { base with errors := #[] }
  expectCfgOk "P0 empty errors table" p0
  let orderedErrors := #[errorX0, errorY1, errorUpperX2]
  let p1 := { base with errors := orderedErrors }
  expectCfgOk "P1 distinct case-sensitive error names" p1
  let p1Bytes ← expectOk "P1 errors order encode"
    (encodeSemanticProgramDataV1 p1)
  let p1Decoded ← expectOk "P1 errors order decode"
    (decodeSemanticProgramDataV1 p1Bytes)
  expect (p1Decoded.errors == orderedErrors)
    "P1 ErrorDecl source order survives wire round-trip"
  let errorX1 : ErrorDeclV1 := { errorX0 with id := 1 }
  let duplicateErrors := #[errorX0, errorX1]
  let n1 := { base with errors := duplicateErrors }
  expectCfgErrCode "N1 duplicate ErrorDecl names" .duplicate n1
  -- Shallow InterfaceField TypeId range validation precedes name uniqueness.
  let badRefField : InterfaceFieldV1 := {
    name := "payload", typeId := 99, visibility := .public_
  }
  let badRefErrorX1 : ErrorDeclV1 := { errorX1 with fields := #[badRefField] }
  let n2 := { base with errors := #[errorX0, badRefErrorX1] }
  expectCfgErrCode "N2 Error field TypeId before names" .badReference n2
  -- Canonical Constant valueBytes validation precedes the duplicate-name phase.
  let n3 := {
    base with
      constants := #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
      errors := duplicateErrors
  }
  expectCfgErrCode "N3 Constant value before error names" .nonCanonical n3
  -- Canonical callable Op.Literal also precedes the duplicate-name phase.
  let badValueCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 0 })
        (.literal 0 (ByteArray.mk #[2]))]
      (.return_ none)] with
      id := 0
  }
  let n4 := { base with errors := duplicateErrors, callables := #[badValueCallable] }
  expectCfgErrCode "N4 callable value before error names" .nonCanonical n4
  -- Canonical SwitchCase valueBytes also precede the duplicate-name phase.
  let badSwitchCallable := cfgCallable #[
    cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
      (.switch 0 #[{
        typeId := 0
        valueBytes := ByteArray.mk #[2]
        target := cfgJumpTarget 1
      }] none),
    cfgBlock 1 (.return_ (some 0))
  ]
  let n5 := {
    base with errors := duplicateErrors, callables := #[badSwitchCallable]
  }
  expectCfgErrCode "N5 SwitchCase value before error names" .nonCanonical n5
  -- The grouped duplicate-name phase precedes callable signature validation.
  let badSignatureCallable := cfgCallableKindName .pureFn none
  let n6 := {
    base with errors := duplicateErrors, callables := #[badSignatureCallable]
  }
  expectCfgErrCode "N6 error names before callable signature" .duplicate n6
  -- The grouped duplicate-name phase also precedes per-callable CFG validation.
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
  }
  let n7 := { base with errors := duplicateErrors, callables := #[badCfgCallable] }
  expectCfgErrCode "N7 error names before CFG" .duplicate n7

/-- SPEC-SEM-WIRE-001 §6 event/error interface-field names are exact-string
    unique within each declaration. Different declarations and declaration
    kinds may reuse a field name; identifier grammar/NFC remains separate. -/
private def testInterfaceFieldNameUniqueness : IO Unit := do
  let fieldX : InterfaceFieldV1 := {
    name := "x", typeId := 0, visibility := .public_
  }
  let fieldY : InterfaceFieldV1 := {
    name := "y", typeId := 0, visibility := .public_
  }
  let fieldUpperX : InterfaceFieldV1 := {
    name := "X", typeId := 0, visibility := .public_
  }
  let event0 : EventDeclV1 := {
    id := 0, name := "E0", fields := #[fieldX, fieldY]
  }
  let event1 : EventDeclV1 := {
    id := 1, name := "E1", fields := #[fieldX]
  }
  let error0 : ErrorDeclV1 := {
    id := 0, name := "R0", fields := #[fieldX, fieldUpperX]
  }
  let error1 : ErrorDeclV1 := {
    id := 1, name := "R1", fields := #[fieldX]
  }
  let base ← programWithTypes "InterfaceFieldNameBase" cfgBoolTypes
  let p0 := { base with events := #[event0], errors := #[error0] }
  expectCfgOk "P0 distinct case-sensitive interface field names" p0
  let p1 := { base with events := #[event0, event1], errors := #[error0, error1] }
  expectCfgOk "P1 interface field scope resets per declaration" p1
  let duplicateEvent : EventDeclV1 := {
    id := 0, name := "E", fields := #[fieldX, fieldX]
  }
  let n1 := { base with events := #[duplicateEvent] }
  expectCfgErrCode "N1 duplicate event field names" .duplicate n1
  let duplicateError : ErrorDeclV1 := {
    id := 0, name := "R", fields := #[fieldX, fieldX]
  }
  let n2 := { base with errors := #[duplicateError] }
  expectCfgErrCode "N2 duplicate error field names" .duplicate n2
  -- Shallow interface-field TypeId range validation precedes name uniqueness.
  let badRefField : InterfaceFieldV1 := { fieldX with typeId := 99 }
  let badRefEvent : EventDeclV1 := {
    duplicateEvent with fields := #[fieldX, badRefField]
  }
  let n3 := { base with events := #[badRefEvent] }
  expectCfgErrCode "N3 interface field TypeId before names" .badReference n3
  -- Canonical valueBytes validation precedes interface-field name uniqueness.
  let n4 := {
    base with
      constants := #[constOf 0 "bad" 0 (ByteArray.mk #[2])]
      events := #[duplicateEvent]
  }
  expectCfgErrCode "N4 canonical value before interface field names" .nonCanonical n4
  -- Interface-field uniqueness precedes callable signature validation.
  let badSignatureCallable := cfgCallableKindName .pureFn none
  let n5 := {
    base with events := #[duplicateEvent], callables := #[badSignatureCallable]
  }
  expectCfgErrCode "N5 interface field names before callable signature" .duplicate n5
  -- Interface-field uniqueness also precedes per-callable CFG validation.
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
  }
  let n6 := { base with events := #[duplicateEvent], callables := #[badCfgCallable] }
  expectCfgErrCode "N6 interface field names before CFG" .duplicate n6

/-- SPEC-SEM-WIRE-001 §6 initializer cardinality: a program contains zero or
    one initializer, never two. Result shape is tested separately below. -/
private def testInitializerCardinality : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let p0 ← programWithTypes "InitCountP0None" boolUnitTypes
  expectCfgOk "P0 zero initializer" p0
  let p1 ← programWithTypes "InitCountP1One" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1]
  expectCfgOk "P1 one initializer" p1
  let entry1 : CallableV1 := { (cfgCallableKindName .entry (some "run")) with id := 1 }
  let p2 ← programWithTypes "InitCountP2InitEntry" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1, entry1]
  expectCfgOk "P2 initializer plus entry" p2
  let init1 : CallableV1 := { (cfgCallableKindName .initializer none 1) with id := 1 }
  let n1 ← programWithTypes "InitCountN1Two" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1, init1]
  expectCfgErr "N1 two initializers" n1
  let badInit1 : CallableV1 := {
    init1 with blocks := #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)]
  }
  let n2 ← programWithTypes "InitCountN2BeforeCfg" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1, badInit1]
  expectCfgErr "N2 initializer count before CFG" n2

/-- SPEC-SEM-WIRE-001 §6 initializer result signature: when present, an
    initializer has a Unit/public result. Other callable kinds are outside this
    slice. -/
private def testInitializerResultShape : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let p0 ← programWithTypes "InitResultP0NoInit" cfgBoolTypes
  expectCfgOk "P0 no initializer needs no Unit result" p0
  let p1 ← programWithTypes "InitResultP1UnitPublic" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1]
  expectCfgOk "P1 initializer Unit public" p1
  let n1 ← programWithTypes "InitResultN1BoolPublic" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 0]
  expectCfgErr "N1 initializer Bool public" n1
  let privateInit : CallableV1 := {
    (cfgCallableKindName .initializer none 1) with
      result := { typeId := 1, visibility := .private_ }
  }
  let n2 ← programWithTypes "InitResultN2UnitPrivate" boolUnitTypes #[]
    #[privateInit]
  expectCfgErr "N2 initializer Unit private" n2
  let commitmentInit : CallableV1 := {
    (cfgCallableKindName .initializer none 1) with
      result := { typeId := 1, visibility := .commitment }
  }
  let n3 ← programWithTypes "InitResultN3UnitCommitment" boolUnitTypes #[]
    #[commitmentInit]
  expectCfgErr "N3 initializer Unit commitment" n3
  -- Shallow TypeId range validation precedes signature shape.
  let badRefInit : CallableV1 := {
    (cfgCallableKindName .initializer none 1) with
      result := { typeId := 99, visibility := .private_ }
  }
  let n4 ← programWithTypes "InitResultN4ReferenceFirst" boolUnitTypes #[]
    #[badRefInit]
  expectCfgErrCode "N4 result TypeId before initializer signature" .badReference n4
  -- Canonical literal values precede callable signature validation.
  let badValueInit : CallableV1 := {
    (cfgCallableKindName .initializer none 0) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n5 ← programWithTypes "InitResultN5ValueFirst" boolUnitTypes #[]
    #[badValueInit]
  expectCfgErrCode "N5 canonical value before initializer signature" .nonCanonical n5
  -- Initializer signature validation precedes CFG def-site TypeId range.
  let badCfgInit : CallableV1 := {
    (cfgCallableKindName .initializer none 0) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n6 ← programWithTypes "InitResultN6SignatureFirst" boolUnitTypes #[]
    #[badCfgInit]
  expectCfgErr "N6 initializer signature before def-site TypeId" n6

/-- SPEC-SEM-WIRE-001 §6 invariant result signature: every invariant callable
    has a Bool/public result. Declaration identity/ordinal join, zero params,
    closure restrictions, and invariantSteps remain separate slices. -/
private def testInvariantResultShape : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let privatePureFn : CallableV1 := {
    (cfgCallableKindName .pureFn (some "f") 1) with
      result := { typeId := 1, visibility := .private_ }
  }
  let p0 ← programWithTypes "InvResultP0OtherKind" boolUnitTypes #[]
    #[privatePureFn]
  expectCfgOk "P0 non-invariant result is outside this gate" p0
  let p1Base ← programWithTypes "InvResultP1BoolPublic" boolUnitTypes #[]
    #[cfgCallableKindName .invariant (some "safe")]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P1 invariant Bool public" p1
  let n1Base ← programWithTypes "InvResultN1UnitPublic" boolUnitTypes #[]
    #[cfgCallableKindName .invariant (some "safe") 1]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant Unit public" n1
  let privateInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      result := { typeId := 0, visibility := .private_ }
  }
  let n2Base ← programWithTypes "InvResultN2BoolPrivate" boolUnitTypes #[]
    #[privateInvariant]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N2 invariant Bool private" n2
  let commitmentInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      result := { typeId := 0, visibility := .commitment }
  }
  let n3Base ← programWithTypes "InvResultN3BoolCommitment" boolUnitTypes #[]
    #[commitmentInvariant]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N3 invariant Bool commitment" n3
  -- Shallow result TypeId range validation precedes signature shape.
  let badRefInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      result := { typeId := 99, visibility := .private_ }
  }
  let n4Base ← programWithTypes "InvResultN4ReferenceFirst" boolUnitTypes #[]
    #[badRefInvariant]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 result TypeId before invariant signature" .badReference n4
  -- Shallow result TypeId range also precedes canonical valueBytes when both
  -- are malformed in the same invariant callable.
  let badRefAndValueInvariant : CallableV1 := {
    badRefInvariant with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n5Base ← programWithTypes "InvResultN5ReferenceBeforeValue" boolUnitTypes #[]
    #[badRefAndValueInvariant]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N5 result TypeId before canonical value" .badReference n5
  -- Canonical literal values precede callable signature validation.
  let badValueInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe") 1) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n6Base ← programWithTypes "InvResultN6ValueFirst" boolUnitTypes #[]
    #[badValueInvariant]
  let n6 : SemanticProgramDataV1 := {
    n6Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N6 canonical value before invariant signature" .nonCanonical n6
  -- Invariant signature validation precedes CFG def-site TypeId range.
  let badCfgInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe") 1) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n7Base ← programWithTypes "InvResultN7SignatureFirst" boolUnitTypes #[]
    #[badCfgInvariant]
  let n7 : SemanticProgramDataV1 := {
    n7Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N7 invariant signature before def-site TypeId" n7

/-- SPEC-SEM-WIRE-001 §8 invariant root signature: invariant callables have
    zero parameters. Declaration join, closure restrictions, and invariantSteps
    remain separate slices. -/
private def testInvariantParameterShape : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let param0 : ParameterV1 := {
    valueId := 0, name := "x", typeId := 0, visibility := .public_
  }
  let p0 ← programWithTypes "InvParamP0PureFn" boolUnitTypes #[]
    #[cfgCallableWithParams #[param0] #[cfgBlock 0 (.return_ none)]]
  expectCfgOk "P0 pureFn may have params" p0
  let initializerWithParam : CallableV1 := {
    (cfgCallableKindName .initializer none 1) with params := #[param0]
  }
  let p1 ← programWithTypes "InvParamP1Initializer" boolUnitTypes #[]
    #[initializerWithParam]
  expectCfgOk "P1 initializer may have params" p1
  let entryWithParam : CallableV1 := {
    (cfgCallableKindName .entry (some "run")) with params := #[param0]
  }
  let p2 ← programWithTypes "InvParamP2Entry" boolUnitTypes #[]
    #[entryWithParam]
  expectCfgOk "P2 entry may have params" p2
  let viewWithParam : CallableV1 := {
    (cfgCallableKindName .view (some "read")) with params := #[param0]
  }
  let p3 ← programWithTypes "InvParamP3View" boolUnitTypes #[]
    #[viewWithParam]
  expectCfgOk "P3 view may have params" p3
  let p4Base ← programWithTypes "InvParamP4Zero" boolUnitTypes #[]
    #[cfgCallableKindName .invariant (some "safe")]
  let p4 : SemanticProgramDataV1 := {
    p4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P4 invariant zero params" p4
  let oneParamInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with params := #[param0]
  }
  let n1Base ← programWithTypes "InvParamN1One" cfgBoolTypes #[]
    #[oneParamInvariant]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant one param" n1
  -- Shallow parameter TypeId range validation precedes signature shape.
  let badRefParam : ParameterV1 := { param0 with typeId := 99 }
  let badRefInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with params := #[badRefParam]
  }
  let n2Base ← programWithTypes "InvParamN2ReferenceFirst" cfgBoolTypes #[]
    #[badRefInvariant]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 param TypeId before invariant signature" .badReference n2
  -- Shallow parameter TypeId range also precedes canonical valueBytes when
  -- both are malformed in the same invariant callable.
  let badRefAndValueInvariant : CallableV1 := {
    badRefInvariant with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 1, typeId := 0 })
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n3Base ← programWithTypes "InvParamN3ReferenceBeforeValue" cfgBoolTypes #[]
    #[badRefAndValueInvariant]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N3 param TypeId before canonical value" .badReference n3
  -- Canonical literal values precede invariant parameter shape.
  let badValueInvariant : CallableV1 := {
    oneParamInvariant with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 1, typeId := 0 })
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n4Base ← programWithTypes "InvParamN4ValueFirst" cfgBoolTypes #[]
    #[badValueInvariant]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 canonical value before invariant params" .nonCanonical n4
  -- Invariant parameter shape precedes CFG def-site TypeId range.
  let badCfgInvariant : CallableV1 := {
    oneParamInvariant with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 1, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n5Base ← programWithTypes "InvParamN5SignatureFirst" cfgBoolTypes #[]
    #[badCfgInvariant]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N5 invariant params before def-site TypeId" n5

/-- SPEC-SEM-WIRE-001 §6 invariant declaration join: invariant callables and
    InvariantDecl rows correspond one-to-one in invariant-callable source order,
    with exact callableId/kind/name. Closure semantics remain separate. -/
private def testInvariantDeclarationJoin : IO Unit := do
  let p0 ← programWithTypes "InvJoinP0Empty" cfgBoolTypes
  expectCfgOk "P0 no invariant callables or rows" p0
  let invariantSafe := cfgCallableKindName .invariant (some "safe")
  let p1Base ← programWithTypes "InvJoinP1Exact" cfgBoolTypes #[]
    #[invariantSafe]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P1 one exact invariant row" p1
  -- P2: invariant ordinals skip non-invariant callables while callableId keeps
  -- the unified callable-table index.
  let entry0 := cfgCallableKindName .entry (some "run")
  let invariant1 : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with id := 1
  }
  let pure2 : CallableV1 := {
    (cfgCallableKindName .pureFn (some "f")) with id := 2
  }
  let invariant3 : CallableV1 := {
    (cfgCallableKindName .invariant (some "live")) with id := 3
  }
  let p2Base ← programWithTypes "InvJoinP2MixedOrder" cfgBoolTypes #[]
    #[entry0, invariant1, pure2, invariant3]
  let p2 : SemanticProgramDataV1 := {
    p2Base with invariants :=
      #[{ id := 0, name := "safe", callableId := 1 },
        { id := 1, name := "live", callableId := 3 }]
  }
  expectCfgOk "P2 invariant rows follow filtered callable source order" p2
  -- N1: every invariant callable has exactly one row.
  let n1 ← programWithTypes "InvJoinN1MissingRow" cfgBoolTypes #[]
    #[invariantSafe]
  expectCfgErr "N1 invariant callable missing row" n1
  -- Extra rows fail even when every row id equals its index and every
  -- callableId is in range.
  let nExtraBase ← programWithTypes "InvJoinN1bExtraRow" cfgBoolTypes #[]
    #[invariantSafe]
  let nExtra : SemanticProgramDataV1 := {
    nExtraBase with invariants :=
      #[{ id := 0, name := "safe", callableId := 0 },
        { id := 1, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1b extra invariant row" nExtra
  -- N2: count is equal, but the row points at a non-invariant callable.
  let pure0 := cfgCallableKindName .pureFn (some "f")
  let invariantAt1 : CallableV1 := { invariantSafe with id := 1 }
  let n2Base ← programWithTypes "InvJoinN2WrongKind" cfgBoolTypes #[]
    #[pure0, invariantAt1]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "f", callableId := 0 }]
  }
  expectCfgErr "N2 row references non-invariant callable" n2
  let n3Base ← programWithTypes "InvJoinN3WrongName" cfgBoolTypes #[]
    #[invariantSafe]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "other", callableId := 0 }]
  }
  expectCfgErr "N3 invariant row name mismatch" n3
  -- N4: each row matches an invariant by name/id, but rows reverse source
  -- order and therefore are noncanonical.
  let invariantLive1 : CallableV1 := {
    (cfgCallableKindName .invariant (some "live")) with id := 1
  }
  let n4Base ← programWithTypes "InvJoinN4Reordered" cfgBoolTypes #[]
    #[invariantSafe, invariantLive1]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants :=
      #[{ id := 0, name := "live", callableId := 1 },
        { id := 1, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N4 invariant rows reversed" n4
  -- N5: duplicate binding cannot replace the second source-order row.
  let n5Base ← programWithTypes "InvJoinN5DuplicateBinding" cfgBoolTypes #[]
    #[invariantSafe, invariantLive1]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants :=
      #[{ id := 0, name := "safe", callableId := 0 },
        { id := 1, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N5 duplicate invariant binding" n5
  -- N6: shallow callableId range wins over malformed canonical valueBytes.
  let malformedInvariant : CallableV1 := {
    invariantSafe with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ none)]
  }
  let n6Base ← programWithTypes "InvJoinN6ReferenceFirst" cfgBoolTypes #[]
    #[malformedInvariant]
  let n6 : SemanticProgramDataV1 := {
    n6Base with invariants := #[{ id := 0, name := "safe", callableId := 99 }]
  }
  expectCfgErrCode "N6 row reference before canonical value" .badReference n6
  -- N7: canonical value validation precedes the missing-row join failure.
  let n7 ← programWithTypes "InvJoinN7ValueFirst" cfgBoolTypes #[]
    #[malformedInvariant]
  expectCfgErrCode "N7 canonical value before invariant join" .nonCanonical n7
  -- N8: invariant declaration join precedes per-callable CFG validation.
  let badCfgInvariant : CallableV1 := {
    invariantSafe with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n8 ← programWithTypes "InvJoinN8JoinFirst" cfgBoolTypes #[]
    #[badCfgInvariant]
  expectCfgErr "N8 invariant join before def-site TypeId" n8

/-- SPEC-SEM-WIRE-001 §8 invariant root shape: invariant callables have
    loopBounds = #[]. Other callable kinds retain generic bounded loops. -/
private def testInvariantLoopBoundsShape : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let p0 ← programWithTypes "InvLoopP0Initializer" boolUnitTypes #[]
    #[cfgCallableKindNameLoop .initializer none 1]
  expectCfgOk "P0 initializer may carry bounded loop" p0
  let p1 ← programWithTypes "InvLoopP1Entry" boolUnitTypes #[]
    #[cfgCallableKindNameLoop .entry (some "run")]
  expectCfgOk "P1 entry may carry bounded loop" p1
  let p2 ← programWithTypes "InvLoopP2View" boolUnitTypes #[]
    #[cfgCallableKindNameLoop .view (some "read")]
  expectCfgOk "P2 view may carry bounded loop" p2
  let p3 ← programWithTypes "InvLoopP3PureFn" boolUnitTypes #[]
    #[cfgCallableKindNameLoop .pureFn (some "f")]
  expectCfgOk "P3 pureFn may carry bounded loop" p3
  let invariantNoLoop := cfgCallableKindName .invariant (some "safe")
  let p4Base ← programWithTypes "InvLoopP4Empty" boolUnitTypes #[]
    #[invariantNoLoop]
  let p4 : SemanticProgramDataV1 := {
    p4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P4 invariant loopBounds empty" p4
  let invariantWithLoop := cfgCallableKindNameLoop .invariant (some "safe")
  let n1Base ← programWithTypes "InvLoopN1BoundedBackEdge" boolUnitTypes #[]
    #[invariantWithLoop]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant bounded back edge" n1
  -- Canonical value validation precedes invariant loopBounds shape.
  let badValueInvariant : CallableV1 := {
    invariantWithLoop with
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        terminator := .jump (cfgJumpTarget 0)
      }]
  }
  let n2Base ← programWithTypes "InvLoopN2ValueFirst" boolUnitTypes #[]
    #[badValueInvariant]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 canonical value before invariant loopBounds" .nonCanonical n2
  -- Invariant loopBounds shape precedes CFG def-site TypeId range.
  let badCfgInvariant : CallableV1 := {
    invariantWithLoop with
      blocks := #[{
        id := 0
        params := #[]
        instructions := #[cfgInstr (some { valueId := 0, typeId := 99 })
          (cfgBoolLit 0)]
        terminator := .jump (cfgJumpTarget 0)
      }]
  }
  let n3Base ← programWithTypes "InvLoopN3SignatureFirst" boolUnitTypes #[]
    #[badCfgInvariant]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N3 invariant loopBounds before def-site TypeId" n3

/-- SPEC-SEM-WIRE-001 §8 invariant fuel metadata, bounded provable
    non-closure subsets: initializer/entry/view are always outside invariant
    closures; when no invariant root exists, every pureFn is outside too. A
    valid pureFn→invariant closure with `some` values pins that the rootless
    rule does not reject genuine closure members. Full membership/exact
    computation, DAG validation, and the 10M ceiling remain separate slices.
    Every case drives the structure and encoder gates. -/
private def testNonClosureCallableInvariantSteps : IO Unit := do
  let boolUnitTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .unit }]
  let p1 ← programWithTypes "InvStepsP1InitializerNone" boolUnitTypes #[]
    #[cfgCallableKindName .initializer none 1]
  expectCfgOk "P1 initializer invariantSteps none" p1
  let p2 ← programWithTypes "InvStepsP2EntryNone" boolUnitTypes #[]
    #[cfgCallableKindName .entry (some "run")]
  expectCfgOk "P2 entry invariantSteps none" p2
  let p3 ← programWithTypes "InvStepsP3ViewNone" boolUnitTypes #[]
    #[cfgCallableKindName .view (some "read")]
  expectCfgOk "P3 view invariantSteps none" p3
  -- P4 is a valid two-callable invariant closure. The pureFn has one literal
  -- plus one terminator, so steps=1+(1+1)=3. The invariant has one PureCall
  -- plus one terminator and includes its callee, so steps=1+(1+1)+3=6.
  -- Both `some` values must survive this bounded kind-disjoint gate.
  let closurePureFn : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      name := some "helper"
      invariantSteps := some 3
  }
  let closureInvariant : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 6
  }
  let p4Base ← programWithTypes "InvStepsP4ClosureSome" boolUnitTypes #[]
    #[closurePureFn, closureInvariant]
  let p4 : SemanticProgramDataV1 := {
    p4Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P4 pureFn/invariant closure invariantSteps some" p4
  let p5 ← programWithTypes "InvStepsP5RootlessPureNone" boolUnitTypes #[]
    #[cfgCallableKindName .pureFn (some "f")]
  expectCfgOk "P5 rootless pureFn invariantSteps none" p5
  let initializerWithSteps : CallableV1 := {
    (cfgCallableKindName .initializer none 1) with invariantSteps := some 1
  }
  let n1 ← programWithTypes "InvStepsN1InitializerSome" boolUnitTypes #[]
    #[initializerWithSteps]
  expectCfgErr "N1 initializer invariantSteps some" n1
  let entryWithSteps : CallableV1 := {
    (cfgCallableKindName .entry (some "run")) with invariantSteps := some 0
  }
  let n2 ← programWithTypes "InvStepsN2EntrySome" boolUnitTypes #[]
    #[entryWithSteps]
  expectCfgErr "N2 entry invariantSteps some" n2
  let viewWithSteps : CallableV1 := {
    (cfgCallableKindName .view (some "read")) with
      invariantSteps := some (18446744073709551615 : UInt64)
  }
  let n3 ← programWithTypes "InvStepsN3ViewSome" boolUnitTypes #[]
    #[viewWithSteps]
  expectCfgErr "N3 view invariantSteps some" n3
  -- Canonical value validation remains earlier than callable fuel metadata.
  let n4 ← programWithTypes "InvStepsN4ValueFirst" boolUnitTypes
    #[constOf 0 "bad" 0 (ByteArray.mk #[2])] #[entryWithSteps]
  expectCfgErrCode "N4 canonical value before invariantSteps" .nonCanonical n4
  -- Fuel metadata validation precedes per-callable CFG def-site TypeId range.
  -- Without this gate the instruction result below would be `.badReference`.
  let entryWithStepsBadDef : CallableV1 := {
    entryWithSteps with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n5 ← programWithTypes "InvStepsN5SignatureFirst" boolUnitTypes #[]
    #[entryWithStepsBadDef]
  expectCfgErr "N5 invariantSteps before def-site TypeId" n5
  let rootlessPureWithSteps : CallableV1 := {
    (cfgCallableKindName .pureFn (some "f")) with invariantSteps := some 2
  }
  let n6 ← programWithTypes "InvStepsN6RootlessPureSome" boolUnitTypes #[]
    #[rootlessPureWithSteps]
  expectCfgErr "N6 rootless pureFn invariantSteps some" n6
  -- The rootless-pureFn extension retains canonical-values-before-signature.
  let n7 ← programWithTypes "InvStepsN7RootlessValueFirst" boolUnitTypes
    #[constOf 0 "bad" 0 (ByteArray.mk #[2])] #[rootlessPureWithSteps]
  expectCfgErrCode "N7 canonical value before rootless pureFn steps"
    .nonCanonical n7
  -- It also retains signature-before-CFG using a distinguishable later error.
  let rootlessPureWithStepsBadDef : CallableV1 := {
    rootlessPureWithSteps with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
        (.return_ none)]
  }
  let n8 ← programWithTypes "InvStepsN8RootlessSignatureFirst" boolUnitTypes #[]
    #[rootlessPureWithStepsBadDef]
  expectCfgErr "N8 rootless pureFn steps before def-site TypeId" n8

/-- SPEC-SEM-WIRE-001 §8 bounded invariant-root fuel presence: every
    `kind=invariant` root carries `some invariantSteps`. Transitive pureFn
    membership, DAG/op validation, exact checked computation, and the 10M
    ceiling are separate post-CFG gates.
    All cases drive both the structure and encoder gates. -/
private def testInvariantRootStepsPresence : IO Unit := do
  let rootWithoutSteps : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := none
  }
  -- One literal plus one terminator: computed steps = 1 + (1 + 1) = 3.
  let rootWithSteps : CallableV1 := {
    rootWithoutSteps with invariantSteps := some 3
  }
  let p1Base ← programWithTypes "InvRootStepsP1Some" cfgBoolTypes #[]
    #[rootWithSteps]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P1 invariant root steps some" p1
  let n1Base ← programWithTypes "InvRootStepsN1None" cfgBoolTypes #[]
    #[rootWithoutSteps]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root steps none" n1
  -- Canonical valueBytes precede invariant-root fuel presence.
  let badValueRoot : CallableV1 := {
    rootWithoutSteps with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ (some 0))]
  }
  let n2Base ← programWithTypes "InvRootStepsN2ValueFirst" cfgBoolTypes #[]
    #[badValueRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 canonical value before invariant root steps"
    .nonCanonical n2
  -- Fuel presence precedes per-callable CFG def-site TypeId range.
  let badCfgRoot : CallableV1 := {
    rootWithoutSteps with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 1)]
        (.return_ none)]
  }
  let n3Base ← programWithTypes "InvRootStepsN3SignatureFirst" cfgBoolTypes #[]
    #[badCfgRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N3 invariant root steps before def-site TypeId" n3

/-- SPEC-SEM-WIRE-001 §8 intrinsic invariant fuel ceiling: every present
    `invariantSteps` value is at most 10,000,000. Exact checked closure
    computation now runs first in the same fuel phase; this suite retains the
    scalar boundary and earlier-phase precedence cases. -/
private def testInvariantStepsIntrinsicCeiling : IO Unit := do
  let simpleRoot := cfgCallableKindName .invariant (some "safe")
  let p1Base ← programWithTypes "InvCeilingP1Exact" cfgBoolTypes #[]
    #[simpleRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P1 exact simple invariant steps below ceiling" p1
  -- A carried value at the scalar ceiling is still invalid when it does not
  -- equal the exact computed value; exact computation precedes requirements.
  let rootAtCeiling : CallableV1 := {
    simpleRoot with invariantSteps := some 10000000
  }
  let p2Base ← programWithTypes "InvCeilingP2NonExact" cfgBoolTypes #[]
    #[rootAtCeiling]
  let p2 : SemanticProgramDataV1 := {
    p2Base with
      invariants := #[{ id := 0, name := "safe", callableId := 0 }]
      requirements := { items := #[req "notadomain.boundary"] }
  }
  expectCfgErrCode "P2 carried ceiling but non-exact" .badCfg p2
  expectCfgInvariantPhase "P2 exact computation before requirements"
    .invariantFuel .badCfg p2
  let rootOverCeiling : CallableV1 := {
    simpleRoot with invariantSteps := some 10000001
  }
  let n1Base ← programWithTypes "InvCeilingN1Root" cfgBoolTypes #[]
    #[rootOverCeiling]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root over intrinsic ceiling" n1
  -- The ceiling applies to pureFn closure metadata as well as invariant roots.
  let closurePureOver : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      name := some "helper"
      invariantSteps := some 10000001
  }
  let closureRoot : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 6
  }
  let n2Base ← programWithTypes "InvCeilingN2PureFn" cfgBoolTypes #[]
    #[closurePureOver, closureRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N2 closure pureFn over intrinsic ceiling" n2
  -- CFG failures precede the post-CFG ceiling phase.
  let badCfgRoot : CallableV1 := {
    rootOverCeiling with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 1)]
        (.return_ none)]
  }
  let n3Base ← programWithTypes "InvCeilingN3CfgFirst" cfgBoolTypes #[]
    #[badCfgRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N3 CFG def-site before invariant ceiling" .badReference n3
  -- A valid CFG with both ceiling and requirement errors reports fuel first.
  let n4 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-ceiling"] }
  }
  expectCfgErr "N4 invariant ceiling before requirements" n4
  -- Canonical valueBytes remain earlier than CFG and fuel phases.
  let badValueRoot : CallableV1 := {
    rootOverCeiling with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
          (.literal 0 (ByteArray.mk #[2]))]
        (.return_ (some 0))]
  }
  let n5Base ← programWithTypes "InvCeilingN5ValueFirst" cfgBoolTypes #[]
    #[badValueRoot]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N5 canonical value before invariant ceiling"
    .nonCanonical n5

/-- SPEC §8 exact checked `computedInvariantSteps` over the already-validated
    invariant-closure DAG. The count is `1 + Σ(block.instructions.size + 1)`
    plus the computed callee count for every static PureCall occurrence.
    Positives cover leaf/transitive/duplicate-call/multi-block shapes;
    negatives isolate exact metadata mismatch, duplicate-edge undercount,
    closure accumulation above the intrinsic ceiling, and phase order. -/
private def testInvariantStepsExactComputation : IO Unit := do
  let simpleRoot := cfgCallableKindName .invariant (some "safe")
  let p1Base ← programWithTypes "InvExactP1LeafRoot" cfgBoolTypes #[]
    #[simpleRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P1 exact leaf invariant steps" p1
  let leaf : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "leaf"
      invariantSteps := some 3
  }
  let directRoot : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 6
  }
  let p2Base ← programWithTypes "InvExactP2Direct" cfgBoolTypes #[]
    #[leaf, directRoot]
  let p2 : SemanticProgramDataV1 := {
    p2Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P2 direct closure exact steps" p2
  let duplicateRoot : CallableV1 := {
    directRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[]),
          cfgInstr (some (cfgValueDef 1)) (.pureCall 0 #[])]
        (.return_ (some 1))]
      invariantSteps := some 10
  }
  let p3Base ← programWithTypes "InvExactP3DuplicateCalls" cfgBoolTypes #[]
    #[leaf, duplicateRoot]
  let p3 : SemanticProgramDataV1 := {
    p3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P3 duplicate PureCall occurrences counted" p3
  let multiBlockRoot : CallableV1 := {
    (cfgCallable #[] ) with
      id := 0
      kind := .invariant
      name := some "safe"
      blocks := #[
        cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
          (.jump (cfgJumpTarget 1)),
        cfgBlockInstrs 1
          #[cfgInstr (some (cfgValueDef 1)) (.unary .not 0)]
          (.return_ (some 1))]
      invariantSteps := some 5
  }
  let p4Base ← programWithTypes "InvExactP4MultiBlock" cfgBoolTypes #[]
    #[multiBlockRoot]
  let p4 : SemanticProgramDataV1 := {
    p4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P4 every block terminator counted" p4
  let wrongLeafRoot : CallableV1 := {
    simpleRoot with invariantSteps := some 3
  }
  let n1Base ← programWithTypes "InvExactN1LeafMismatch" cfgBoolTypes #[]
    #[wrongLeafRoot]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N1 leaf root exact mismatch" .badCfg n1
  expectCfgInvariantPhase "N1 leaf mismatch fuel phase"
    .invariantFuel .badCfg n1
  let wrongLeaf : CallableV1 := { leaf with invariantSteps := some 4 }
  let n2Base ← programWithTypes "InvExactN2CalleeMismatch" cfgBoolTypes #[]
    #[wrongLeaf, directRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N2 closure callee exact mismatch" .badCfg n2
  expectCfgInvariantPhase "N2 callee mismatch fuel phase"
    .invariantFuel .badCfg n2
  let wrongDirectRoot : CallableV1 := {
    directRoot with invariantSteps := some 7
  }
  let n3Base ← programWithTypes "InvExactN3RootMismatch" cfgBoolTypes #[]
    #[leaf, wrongDirectRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 caller exact mismatch" .badCfg n3
  expectCfgInvariantPhase "N3 caller mismatch fuel phase"
    .invariantFuel .badCfg n3
  let undercountedDuplicateRoot : CallableV1 := {
    duplicateRoot with invariantSteps := some 7
  }
  let n4Base ← programWithTypes "InvExactN4DuplicateUndercount" cfgBoolTypes #[]
    #[leaf, undercountedDuplicateRoot]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N4 duplicate PureCall undercount" .badCfg n4
  expectCfgInvariantPhase "N4 duplicate undercount fuel phase"
    .invariantFuel .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-exact-steps"] }
  }
  expectCfgErrCode "N5 exact mismatch before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 exact mismatch fuel before requirements"
    .invariantFuel .badCfg n5
  let badCfgWrongRoot : CallableV1 := {
    wrongLeafRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 1)]
        (.return_ none)]
  }
  let n6Base ← programWithTypes "InvExactN6CfgFirst" cfgBoolTypes #[]
    #[badCfgWrongRoot]
  let n6 : SemanticProgramDataV1 := {
    n6Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N6 CFG before exact steps" .badReference n6
  expectCfgInvariantPhase "N6 CFG phase before exact steps"
    .cfg .badReference n6
  -- Hard-coded exact metadata for a duplicate-call chain through pureFn id 20.
  -- The invariant root repeats that same shape and computes to 14,680,060,
  -- above the 10M intrinsic ceiling, while all carried metadata remains ≤10M.
  let exactPureSteps : Array UInt64 := #[
    3, 10, 24, 52, 108, 220, 444, 892, 1788, 3580, 7164,
    14332, 28668, 57340, 114684, 229372, 458748, 917500,
    1835004, 3670012, 7340028]
  let mut largeClosure : Array CallableV1 := #[{
    leaf with name := some "f0", invariantSteps := some exactPureSteps[0]!
  }]
  for index in [1:exactPureSteps.size] do
    let calleeId := UInt32.ofNat (index - 1)
    let callable : CallableV1 := {
      (cfgCallable #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall calleeId #[]),
          cfgInstr (some (cfgValueDef 1)) (.pureCall calleeId #[])]
        (.return_ (some 1))]) with
        id := UInt32.ofNat index
        name := some s!"f{index}"
        invariantSteps := some exactPureSteps[index]!
    }
    largeClosure := largeClosure.push callable
  let largeRootId := UInt32.ofNat exactPureSteps.size
  let largeCalleeId := UInt32.ofNat (exactPureSteps.size - 1)
  let largeRoot : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall largeCalleeId #[]),
        cfgInstr (some (cfgValueDef 1)) (.pureCall largeCalleeId #[])]
      (.return_ (some 1))]) with
      id := largeRootId
      kind := .invariant
      name := some "safe"
      invariantSteps := some maxInvariantStepsV1
  }
  largeClosure := largeClosure.push largeRoot
  let n7Base ← programWithTypes "InvExactN7ComputedAboveCeiling" cfgBoolTypes #[]
    largeClosure
  let n7 : SemanticProgramDataV1 := {
    n7Base with invariants := #[{ id := 0, name := "safe", callableId := largeRootId }]
  }
  expectCfgErrCode "N7 computed closure exceeds intrinsic ceiling" .badCfg n7
  expectCfgInvariantPhase "N7 checked accumulation fuel phase"
    .invariantFuel .badCfg n7

private def testCfgShapeAndReachability : IO Unit := do
  -- Positive boundary: block 0 exists even when it contains no instructions.
  let p0 ← programWithTypes "CfgEmptyInstructions" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlock 0 (.return_ none)]]
  expectCfgOk "one block with no instructions" p0
  -- Positive 1: single-block callable, return terminator (re-pin).
  --   Defines ValueId 0 via a literal instruction so the return use is covered.
  let p1 ← programWithTypes "CfgSingle" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.return_ (some 0))]]
  expectCfgOk "single-block return" p1
  -- Positive 2: two-block jump, both reachable.
  let p2 ← programWithTypes "CfgJump" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "two-block jump" p2
  -- Positive 3: branch reachability (self-jump to entry allowed as target);
  --   the self-target is a back edge 0→0, declared in loopBounds.
  --   Defines ValueId 0 (branch condition) via a literal instruction.
  let p3 ← programWithTypes "CfgBranch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 0 1])]
  expectCfgOk "branch reachability" p3
  -- Positive 4: switch reachability with default target.
  --   Defines ValueId 0 (scrutinee) via a literal instruction.
  let p4 ← programWithTypes "CfgSwitch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 }]
          (some (cfgJumpTarget 1))),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "switch reachability" p4
  -- Positive 5: the builder's appended entry block remains valid when no
  -- focused callable fixture is supplied.
  let p5 ← programWithTypes "CfgEmpty" cfgBoolTypes
  expectCfgOk "appended entry callable" p5
  -- Every callable must contain entry block 0; an entry or view with an empty
  -- block array is rejected by both the structure and encoder pathways.
  let emptyEntry : CallableV1 := {
    (cfgCallable #[]) with kind := .entry, name := some "run"
  }
  let n0Entry ← programWithTypes "CfgEmptyEntryBlocks" cfgBoolTypes #[]
    #[emptyEntry]
  expectCfgErr "entry callable empty blocks" n0Entry
  let emptyView : CallableV1 := {
    (cfgCallable #[]) with kind := .view, name := some "read"
  }
  let n0View ← programWithTypes "CfgEmptyViewBlocks" cfgBoolTypes #[]
    #[emptyView]
  expectCfgErr "view callable empty blocks" n0View
  -- Keep the invariant signature, exact declaration join, and carried fuel
  -- otherwise valid. Missing entry block 0 is a CFG failure before exact fuel
  -- computation can compare the root's `some 1` metadata.
  let emptyInvariant : CallableV1 := {
    (cfgCallable #[]) with
      kind := .invariant
      name := some "safe"
      invariantSteps := some 1
  }
  let n0InvBase ← programWithTypes "CfgEmptyInvariantBlocks" cfgBoolTypes #[]
    #[emptyInvariant]
  let n0Inv : SemanticProgramDataV1 := {
    n0InvBase with
      invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "invariant callable empty blocks" n0Inv
  expectCfgInvariantPhase "invariant empty blocks fail before fuel"
    .cfg .badCfg n0Inv
  -- Negative 1: entryBlock != 0.
  let n1 ← programWithTypes "CfgBadEntry" cfgBoolTypes #[]
    #[cfgCallable
      #[cfgBlock 0 (.return_ none), cfgBlock 1 (.return_ none)]
      (entryBlock := 1)]
  expectCfgErr "entryBlock != 0" n1
  -- Negative 2: block id != array index.
  let n2 ← programWithTypes "CfgBadIdIndex" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 1 (.return_ none),
      cfgBlock 0 (.jump (cfgJumpTarget 0))
    ]]
  expectCfgErr "block id != index" n2
  -- Negative 3: jump target out of range.
  let n3 ← programWithTypes "CfgJumpOOR" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlock 0 (.jump (cfgJumpTarget 5))]]
  expectCfgErr "jump target oor" n3
  -- Negative 4: branch target out of range.
  let n4 ← programWithTypes "CfgBranchOOR" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 0 (cfgJumpTarget 5) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "branch target oor" n4
  -- Negative 5: switch case target out of range.
  let n5 ← programWithTypes "CfgSwitchOOR" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.switch 0
        #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
            target := cfgJumpTarget 5 }]
        none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "switch case target oor" n5
  -- Negative 6: unreachable block (block 1 not reachable from entry).
  let n6 ← programWithTypes "CfgUnreachable" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.return_ none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "unreachable block" n6

/-- SPEC-SEM-WIRE-001 §6 canonical control-flow shape: Term.Switch must carry
    at least one case. A zero-case branch must normalize to Term.Jump rather
    than retaining a second equivalent encoding. -/
private def testCfgSwitchCasesNonempty : IO Unit := do
  -- P1: one case without a default remains canonical.
  let p1 ← programWithTypes "SwitchCasesP1" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 }]
          none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "P1 switch one case" p1
  -- P2: one case plus a default remains canonical.
  let p2 ← programWithTypes "SwitchCasesP2" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 }]
          (some (cfgJumpTarget 1))),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "P2 switch one case and default" p2
  -- N1: empty cases remain invalid even with a valid reachable default.
  let n1 ← programWithTypes "SwitchCasesN1Default" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0 #[] (some (cfgJumpTarget 1))),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "N1 switch empty cases with default" n1
  -- N2: empty cases without a default are likewise non-canonical.
  let n2 ← programWithTypes "SwitchCasesN2NoDefault" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
      (.switch 0 #[] none)]]
  expectCfgErr "N2 switch empty cases without default" n2

/-- SPEC-SEM-WIRE-001 §6 Switch case values are unique as typed canonical
    constants within each Switch. Different targets do not disambiguate the
    same `(typeId,valueBytes)` key. -/
private def testCfgSwitchCaseValueUniqueness : IO Unit := do
  -- P1: distinct canonical Bool values are accepted.
  let p1 ← programWithTypes "SwitchUniqueP1Bool" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 },
            { typeId := 0, valueBytes := ByteArray.mk #[1],
              target := cfgJumpTarget 1 }]
          none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "P1 switch distinct Bool cases" p1
  -- P2: uniqueness is type-driven and also accepts distinct UInt8 values.
  let p2 ← programWithTypes "SwitchUniqueP2UInt8" cfgUint8Types #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7)]
        (.switch 0
          #[{ typeId := 1, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 },
            { typeId := 1, valueBytes := ByteArray.mk #[255],
              target := cfgJumpTarget 1 }]
          none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "P2 switch distinct UInt8 cases" p2
  -- N1: duplicate Bool value to the same target is invalid.
  let n1 ← programWithTypes "SwitchUniqueN1SameTarget" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 },
            { typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 }]
          none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "N1 switch duplicate Bool same target" n1
  -- N2: different targets still cannot disambiguate the same case value.
  let n2 ← programWithTypes "SwitchUniqueN2DifferentTargets" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[1],
              target := cfgJumpTarget 1 },
            { typeId := 0, valueBytes := ByteArray.mk #[1],
              target := cfgJumpTarget 2 }]
          none),
      cfgBlock 1 (.return_ none),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgErr "N2 switch duplicate Bool different targets" n2
  -- N3: duplicate UInt8 canonical values are likewise invalid.
  let n3 ← programWithTypes "SwitchUniqueN3UInt8" cfgUint8Types #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 9)]
        (.switch 0
          #[{ typeId := 1, valueBytes := ByteArray.mk #[7],
              target := cfgJumpTarget 1 },
            { typeId := 1, valueBytes := ByteArray.mk #[7],
              target := cfgJumpTarget 1 }]
          none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "N3 switch duplicate UInt8" n3
  -- P3: uniqueness resets for each Switch; the same typed key may appear in
  -- two distinct reachable terminators within one callable.
  let p3 ← programWithTypes "SwitchUniqueP3PerSwitch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 1 }]
          (some (cfgJumpTarget 3))),
      cfgBlockInstrs 1
        #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.switch 1
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTarget 2 }]
          (some (cfgJumpTarget 2))),
      cfgBlock 2 (.return_ none),
      cfgBlock 3 (.return_ none)
    ]]
  expectCfgOk "P3 switch uniqueness resets per terminator" p3
  -- N4: target args do not disambiguate duplicate typed case values. Both
  -- args are defined, dominate the Switch, and exactly match the target param.
  let n4 ← programWithTypes "SwitchUniqueN4DifferentArgs" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
          cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTargetWithArgs 1 #[1] },
            { typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTargetWithArgs 1 #[2] }]
          none),
      cfgBlockWithParams 1 #[cfgBoolParam 3] (.return_ (some 3))
    ]]
  expectCfgErr "N4 switch duplicate Bool different target args" n4
  -- N5: canonical value validation owns precedence over duplicate detection.
  -- Bool byte 2 is malformed, so both public paths return `.nonCanonical`.
  let n5 ← programWithTypes "SwitchUniqueN5MalformedDuplicate" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[2],
              target := cfgJumpTarget 1 },
            { typeId := 0, valueBytes := ByteArray.mk #[2],
              target := cfgJumpTarget 1 }]
          none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErrCode "N5 malformed duplicate before uniqueness" .nonCanonical n5

private def testCfgBlockParamArity : IO Unit := do
  -- Positive 1: jump to a 2-param block passing 2 args.
  --   Defines ValueIds 2 and 3 in block 0 (distinct from block 1 params 0,1
  --   so the exactly-once def gate holds) and passes them as jump args.
  let p1 ← programWithTypes "CfgArityJump2" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1) ]
        (.jump (cfgJumpTargetWithArgs 1 #[2, 3])),
      cfgBlockWithParams 1 #[cfgBoolParam 0, cfgBoolParam 1]
        (.return_ (some 0))
    ]]
  expectCfgOk "jump arity 2==2" p1
  -- Positive 2: branch then/else both targeting 1-param blocks, 1 arg each.
  --   Global ValueId order assigns later block params 0/1 first, then block-0
  --   results 2 (condition), 3/4 (jump args).
  let p2 ← programWithTypes "CfgArityBranch1" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 4)) (cfgBoolLit 1) ]
        (.branch 2
          (cfgJumpTargetWithArgs 1 #[3])
          (cfgJumpTargetWithArgs 2 #[4])),
      cfgBlockWithParams 1 #[cfgBoolParam 0] (.return_ (some 0)),
      cfgBlockWithParams 2 #[cfgBoolParam 1] (.return_ (some 1))
    ]]
  expectCfgOk "branch arity 1==1" p2
  -- Positive 3: switch case target 1-param (1 arg), default 0-param (0 args).
  --   Global ValueId order assigns block-1 param 0 before block-0 results
  --   1 (scrutinee) and 2 (case arg).
  let p3 ← programWithTypes "CfgAritySwitch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0) ]
        (.switch 1
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTargetWithArgs 1 #[2] }]
          (some (cfgJumpTarget 2))),
      cfgBlockWithParams 1 #[cfgBoolParam 0] (.return_ (some 0)),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgOk "switch arity case 1 / default 0" p3
  -- Positive 4: regression — single-block return (0 args, 0 params) still ok.
  --   Defines ValueId 0 via a literal so the return use is covered.
  let p4 ← programWithTypes "CfgArityReturn0" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.return_ (some 0))]]
  expectCfgOk "return 0==0 regression" p4
  -- Negative 1: jump to 2-param block with 1 arg (arity mismatch).
  let n1 ← programWithTypes "CfgArityJumpShort" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTargetWithArgs 1 #[0])),
      cfgBlockWithParams 1 #[cfgBoolParam 0, cfgBoolParam 1]
        (.return_ (some 0))
    ]]
  expectCfgErr "jump arity 1<2" n1
  -- Negative 2: jump to 2-param block with 3 args.
  let n2 ← programWithTypes "CfgArityJumpLong" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTargetWithArgs 1 #[0, 1, 2])),
      cfgBlockWithParams 1 #[cfgBoolParam 0, cfgBoolParam 1]
        (.return_ (some 0))
    ]]
  expectCfgErr "jump arity 3>2" n2
  -- Negative 3: branch thenTarget ok, elseTarget arity mismatch.
  let n3 ← programWithTypes "CfgArityBranchElse" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 0
        (cfgJumpTargetWithArgs 1 #[0])
        (cfgJumpTargetWithArgs 2 #[])),
      cfgBlockWithParams 1 #[cfgBoolParam 0] (.return_ (some 0)),
      cfgBlockWithParams 2 #[cfgBoolParam 1] (.return_ (some 1))
    ]]
  expectCfgErr "branch else arity mismatch" n3
  -- Negative 4: switch case target arity mismatch (0 args, 1-param block).
  let n4 ← programWithTypes "CfgAritySwitchCase" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.switch 0
        #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
            target := cfgJumpTarget 1 }]
        (some (cfgJumpTarget 2))),
      cfgBlockWithParams 1 #[cfgBoolParam 0] (.return_ (some 0)),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgErr "switch case arity mismatch" n4
  -- Negative 5: switch defaultTarget arity mismatch (default 1 arg, 0-param).
  let n5 ← programWithTypes "CfgAritySwitchDefault" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.switch 0
        #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
            target := cfgJumpTarget 1 }]
        (some (cfgJumpTargetWithArgs 2 #[0]))),
      cfgBlock 1 (.return_ none),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgErr "switch default arity mismatch" n5
  -- Negative 6: jump target OOR still reports via existing range check
  --   (re-pin: range owns OOR, not arity).
  let n6 ← programWithTypes "CfgArityJumpOOR" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTargetWithArgs 5 #[0, 1, 2]))
    ]]
  expectCfgErr "jump oor owns range" n6

private def testCfgLoopBounds : IO Unit := do
  -- POSITIVES (all reachable, entry==0, id==index, arity ok).
  --   Each branch/switch scrutinee ValueId is defined via a literal in block 0
  --   so the ValueId SSA use-existence gate (step f) is satisfied; dominance
  --   is out of scope so a single def anywhere in the callable suffices.
  -- Positive 1: single self-back-edge loop, header==backEdgeFrom==0, maxIter 10.
  let p1 ← programWithTypes "CfgLoopSelf" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 0 10])]
  expectCfgOk "self back-edge loop" p1
  -- Positive 2: two-block loop with back edge 1->0, maxIter 4096.
  let p2 ← programWithTypes "CfgLoop2Block" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 1 4096])]
  expectCfgOk "two-block back edge 1->0" p2
  -- Positive 3: header 0 back-edge 1 plus a forward-only region; exactly the
  --   one back edge, maxIter 1.
  let p3 ← programWithTypes "CfgLoopForwardTail" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
      cfgBlock 1 (.jump (cfgJumpTarget 0)),
      cfgBlock 2 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 1 1])]
  expectCfgOk "back edge plus forward tail" p3
  -- Positive 4: maxIterations == 0 still legal (bounded zero-trip loop is
  --   finite; SPEC only caps upper bound at 4096).
  let p4 ← programWithTypes "CfgLoopZeroIter" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 0 0])]
  expectCfgOk "zero-iter loop legal" p4
  -- Positive 5: loopBounds empty when CFG has no back edge (linear jump chain).
  let p5 ← programWithTypes "CfgLoopNoBackEdge" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgOk "no back edge empty loopBounds" p5
  -- Positive 6: two genuine back edges sorted ascending (0,0) then (0,1).
  --   block 0 self-loop plus 1->0; loopBounds sorted [(0,0),(0,1)].
  let p6 ← programWithTypes "CfgLoopTwoBackSorted" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.jump (cfgJumpTarget 0))
    ] (loopBounds := #[cfgLoopBound 0 0 5, cfgLoopBound 0 1 5])]
  expectCfgOk "two back edges sorted ascending" p6
  -- NEGATIVES (each must fail structure AND encode with .badCfg).
  -- Negative 1: missing back edge — two-block loop above but loopBounds := #[].
  let n1 ← programWithTypes "CfgLoopMissing" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgErr "missing back-edge coverage" n1
  -- Negative 2: extra loopBound not corresponding to any CFG back edge —
  --   linear CFG [0: jump 1, 1: return] with loopBounds [0<-1] (no edge 1->0).
  let n2 ← programWithTypes "CfgLoopExtra" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 1 10])]
  expectCfgErr "extra loopBound no back edge" n2
  -- Negative 3: wrong backEdgeFrom — real back edge is 1->0 but loopBound
  --   says backEdgeFrom 2 (block 2 absent → range first, then mismatch).
  let n3 ← programWithTypes "CfgLoopWrongFrom" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 2 5])]
  expectCfgErr "wrong backEdgeFrom" n3
  -- Negative 4: wrong header — back edge 1->0 but loopBound header := 1.
  let n4 ← programWithTypes "CfgLoopWrongHeader" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 1 1 5])]
  expectCfgErr "wrong header" n4
  -- Negative 5: maxIterations 4097 > 4096 (SPEC §6 cap).
  let n5 ← programWithTypes "CfgLoopMaxIterOver" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 0 4097])]
  expectCfgErr "maxIterations 4097 over cap" n5
  -- Negative 6: duplicate (header,backEdgeFrom) pair — two loopBounds (0,1).
  let n6 ← programWithTypes "CfgLoopDupPair" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlock 1 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 1 5, cfgLoopBound 0 1 5])]
  expectCfgErr "duplicate pair not unique" n6
  -- Negative 7: loopBounds not sorted ascending by (header,backEdgeFrom).
  --   Genuine back edges {0<-0, 0<-1} but in-memory order [(0,1),(0,0)]
  --   violates ascending and is rejected (the sorted sibling is Positive 6).
  let n7 ← programWithTypes "CfgLoopUnsorted" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.jump (cfgJumpTarget 0))
    ] (loopBounds := #[cfgLoopBound 0 1 5, cfgLoopBound 0 0 5])]
  expectCfgErr "unsorted loopBounds" n7
  -- Negative 8: loopBound header out of block range (header=5, blockCount=2).
  let n8 ← programWithTypes "CfgLoopHeaderOOR" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 5 0 5])]
  expectCfgErr "loopBound header oor" n8
  -- Negative 9: loopBound backEdgeFrom out of range.
  let n9 ← programWithTypes "CfgLoopFromOOR" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 0 (cfgJumpTarget 0) (cfgJumpTarget 1)),
      cfgBlock 1 (.return_ none)
    ] (loopBounds := #[cfgLoopBound 0 5 5])]
  expectCfgErr "loopBound backEdgeFrom oor" n9
  -- Negative 10: back edge target not actually a predecessor edge — single
  --   block [0: return] with loopBounds [(0,0)] (return has no self edge).
  let n10 ← programWithTypes "CfgLoopNoEdge" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlock 0 (.return_ none)]
      (loopBounds := #[cfgLoopBound 0 0 5])]
  expectCfgErr "no self edge single block" n10

/-! ### ValueId definition/use-existence regressions (D2-06 §6.2)

    Pins duplicate-definition rejection and use-existence under the stronger
    canonical assignment gate below. Canonical `0..n-1` assignment subsumes
    exactly-once; dominance and typing are exercised by their dedicated
    sections. All definition/use failures use `.badCfg`. -/

private def testCfgValueIdSsa : IO Unit := do
  -- POSITIVES (each via programWithTypes + expectCfgOk, structure + encode).
  -- P1 single-block: instr result 0 := literal, terminator return (some 0).
  let p1 ← programWithTypes "SsaP1Single" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.return_ (some 0))]]
  expectCfgOk "P1 single-block def+use" p1
  -- P2 callable param: param valueId 0, block 0 return (some 0).
  let p2 ← programWithTypes "SsaP2Param" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[cfgBlock 0 (.return_ (some 0))]]
  expectCfgOk "P2 callable param def+use" p2
  -- P3 block param + jump arg: callable param valueId 0, block 0 jump
  --   args #[0], block 1 param valueId 1, return (some 1). The jump arg
  --   use@0 of ValueId 0 is dominated by callable-param def@entry=0; the
  --   return use@1 of ValueId 1 is dominated by block-param def@1. Distinct
  --   ValueIds keep the SSA def-table exactly-once. No back edge.
  let p3 ← programWithTypes "SsaP3BlockParam" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.jump (cfgJumpTargetWithArgs 1 #[0])),
          cfgBlockWithParams 1 #[cfgBoolParam 1] (.return_ (some 1))
        ]]
  expectCfgOk "P3 block param + jump arg" p3
  -- P4 two defs + binary use: result 0 := lit, result 1 := lit,
  --   result 2 := binary add 0 1, return (some 2).
  let p4 ← programWithTypes "SsaP4Binary" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
           cfgInstr (some (cfgValueDef 2)) (.binary .and 0 1) ]
        (.return_ (some 2))]]
  expectCfgOk "P4 two defs + binary use" p4
  -- P5 branch condition use: block 0 instr result 0 := lit, then branch 0.
  let p5 ← programWithTypes "SsaP5BranchCond" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
      cfgBlock 1 (.return_ none),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgOk "P5 branch condition use" p5
  -- P6 switch scrutinee + case arg: global allocation assigns block-1 param
  --   0 before block-0 results 1/2; switch scrut 1, case arg 2, return 0.
  let p6 ← programWithTypes "SsaP6Switch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1) ]
        (.switch 1
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTargetWithArgs 1 #[2] }]
          (some (cfgJumpTarget 2))),
      cfgBlockWithParams 1 #[cfgBoolParam 0] (.return_ (some 0)),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgOk "P6 switch scrutinee + case arg" p6
  -- NEGATIVES (each via expectCfgErr .badCfg, structure + encode).
  -- N1 duplicate def: two instrs both result 0 := literal.
  let n1 ← programWithTypes "SsaN1DupDef" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1) ]
        (.return_ (some 0))]]
  expectCfgErr "N1 duplicate instr result" n1
  -- N2 duplicate across block param and instr result: block 0 param 0,
  --   instr result 0 := literal.
  let n2 ← programWithTypes "SsaN2DupBlockParamInstr" cfgBoolTypes #[]
    #[cfgCallable #[{
      id := 0
      params := #[cfgBoolParam 0]
      instructions := #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
      terminator := .return_ (some 0)
    }]]
  expectCfgErr "N2 duplicate block param + instr" n2
  -- N3 undefined use in op: instr result 0 := unary not 99 (no def for 99).
  let n3 ← programWithTypes "SsaN3UndefOp" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.unary .not 99)]
        (.return_ (some 0))]]
  expectCfgErr "N3 undefined use in op" n3
  -- N4 undefined use in return: block 0 return (some 99), no defs.
  let n4 ← programWithTypes "SsaN4UndefReturn" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlock 0 (.return_ (some 99))]]
  expectCfgErr "N4 undefined use in return" n4
  -- N5 undefined use in branch condition: branch 99, no defs.
  let n5 ← programWithTypes "SsaN5UndefBranchCond" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.branch 99 (cfgJumpTarget 1) (cfgJumpTarget 2)),
      cfgBlock 1 (.return_ none),
      cfgBlock 2 (.return_ none)
    ]]
  expectCfgErr "N5 undefined use in branch cond" n5
  -- N6 undefined use in jump arg: jump args #[99], no defs.
  let n6 ← programWithTypes "SsaN6UndefJumpArg" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTargetWithArgs 1 #[99])),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "N6 undefined use in jump arg" n6
  -- N7 undefined use in switch scrutinee. The case array is nonempty so the
  --   canonical Switch-shape gate passes and this remains an SSA-use test.
  let n7 ← programWithTypes "SsaN7UndefSwitchScrut" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.switch 99
        #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
            target := cfgJumpTarget 1 }]
        none),
      cfgBlock 1 (.return_ none)
    ]]
  expectCfgErr "N7 undefined use in switch scrut" n7
  -- N8 duplicate callable param vs block param: param 0, block 0 param 0.
  let n8 ← programWithTypes "SsaN8DupCallableBlockParam" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[cfgBlockWithParams 0 #[cfgBoolParam 0] (.return_ (some 0))]]
  expectCfgErr "N8 duplicate callable param + block param" n8

/-! ### Canonical per-callable ValueId assignment (SPEC §6)

    Allocation is three global passes: callable parameters; all block
    parameters in BlockId order; then all instruction results in
    BlockId/instruction order. Every pass contributes to one contiguous
    per-callable sequence `0..n-1`. This is deliberately not per-block
    interleaving. Raw transport remains structure-free. -/
private def testCfgValueIdCanonicalAssignment : IO Unit := do
  -- Positives drive the shipped structure validator and encoder.
  let p0 ← programWithTypes "ValueIdCanonP0Empty" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlock 0 (.return_ none)]]
  expectCfgOk "P0 no definitions" p0
  let p1 ← programWithTypes "ValueIdCanonP1Params" cfgBoolTypes #[]
    #[cfgCallableWithParams
      #[{ valueId := 0, name := "a", typeId := 0, visibility := .public_ },
        { valueId := 1, name := "b", typeId := 0, visibility := .public_ }]
      #[cfgBlock 0 (.return_ (some 0))]]
  expectCfgOk "P1 parameters exact sequence" p1
  -- Distinguishing positive exercising all three passes in one callable:
  -- callable parameter 0, later block parameter 1, then the earlier block's
  -- instruction result 2.
  let p2Callable := cfgCallableWithParams
    #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
    #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1)]
        (.jump (cfgJumpTargetWithArgs 1 #[2])),
      cfgBlockWithParams 1 #[cfgBoolParam 1] (.return_ (some 1))
    ]
  let p2 ← programWithTypes "ValueIdCanonP2GlobalCategories" cfgBoolTypes #[]
    #[p2Callable]
  expectCfgOk "P2 all block params before all results" p2
  let p2Bytes ← expectOk "P2 canonical carrier encode"
    (encodeSemanticProgramDataV1 p2)
  let p2Carrier ← expectOk "P2 canonical carrier decode"
    (decodeSemanticProgramV1 p2Bytes)
  expect (bytesEqual p2Carrier.canonicalBytes p2Bytes)
    "P2 canonical carrier preserves byte identity"
  -- Two later block parameters 0/1, then block-0 results 2/3 and block-1
  -- result 4. Uses remain dominance/type-correct.
  let p3 ← programWithTypes "ValueIdCanonP3MultiBlock" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
          cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 0)]
        (.branch 2
          (cfgJumpTargetWithArgs 1 #[3])
          (cfgJumpTargetWithArgs 2 #[3])),
      { id := 1
        params := #[cfgBoolParam 0]
        instructions := #[cfgInstr (some (cfgValueDef 4)) (.unary .not 0)]
        terminator := .return_ (some 4) },
      cfgBlockWithParams 2 #[cfgBoolParam 1] (.return_ (some 1))
    ]]
  expectCfgOk "P3 multi-block global sequence" p3
  let c0 := cfgCallable #[cfgBlockInstrs 0
    #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)] (.return_ (some 0))]
  let c1 : CallableV1 := { (cfgCallable #[cfgBlockInstrs 0
    #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)] (.return_ (some 0))]) with
    id := 1, name := some "g" }
  let p4 ← programWithTypes "ValueIdCanonP4Reset" cfgBoolTypes #[] #[c0, c1]
  expectCfgOk "P4 assignment resets per callable" p4

  -- Negatives are unique-definition programs accepted by the old
  -- exactly-once/use-existence gate but rejected by canonical assignment.
  let n1 ← programWithTypes "ValueIdCanonN1WrongStart" cfgBoolTypes #[]
    #[cfgCallableWithParams
      #[{ valueId := 1, name := "p", typeId := 0, visibility := .public_ }]
      #[cfgBlock 0 (.return_ (some 1))]]
  expectCfgErr "N1 first parameter starts at one" n1
  -- The same production collector is also pinned to the three global passes;
  -- this assertion is reached only after the shipped-path N1 RED is fixed.
  let p2Sites := collectValueDefSites p2Callable
  expect (p2Sites == #[(0, 0), (1, 1), (2, 0)])
    "P2 collector follows params then global block-param then result order"
  let n2 ← programWithTypes "ValueIdCanonN2ParamSwap" cfgBoolTypes #[]
    #[cfgCallableWithParams
      #[{ valueId := 1, name := "a", typeId := 0, visibility := .public_ },
        { valueId := 0, name := "b", typeId := 0, visibility := .public_ }]
      #[cfgBlock 0 (.return_ (some 0))]]
  expectCfgErr "N2 parameter IDs reordered" n2
  let n3 ← programWithTypes "ValueIdCanonN3BlockGap" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockWithParams 0 #[cfgBoolParam 2]
      (.return_ (some 2))]]
  expectCfgErr "N3 first block parameter has gap" n3
  -- Inverse of P2: old per-block-interleaved order is 0,1, but normative
  -- global category order is block-param 1 then result 0, so reject.
  let n4 ← programWithTypes "ValueIdCanonN4Interleaved" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.jump (cfgJumpTargetWithArgs 1 #[0])),
      cfgBlockWithParams 1 #[cfgBoolParam 1] (.return_ (some 1))
    ]]
  expectCfgErr "N4 per-block interleaving is noncanonical" n4
  let n5 ← programWithTypes "ValueIdCanonN5InstrReorder" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
        cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]]
  expectCfgErr "N5 instruction results reordered within block" n5
  let n6 ← programWithTypes "ValueIdCanonN6AcrossBlocks" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0)]
        (.jump (cfgJumpTarget 1)),
      cfgBlockInstrs 1
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))
    ]]
  expectCfgErr "N6 instruction results reordered across blocks" n6
  let n7 ← programWithTypes "ValueIdCanonN7Gap" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
        cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1)]
      (.return_ (some 2))]]
  expectCfgErr "N7 unique instruction-result gap" n7
  let n8 ← programWithTypes "ValueIdCanonN8UsedSparse" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 5)) (cfgBoolLit 0)]
      (.return_ (some 5))]]
  expectCfgErr "N8 used sparse definition remains noncanonical" n8

  -- Observable phase boundaries: canonical valueBytes is an earlier global
  -- prerequisite, while def-site TypeId range and requirements follow the
  -- ValueId assignment check. Same-`.badCfg` CFG neighbors are deliberately
  -- not overclaimed without a finer non-wire phase seam.
  let n9 ← programWithTypes "ValueIdCanonN9ValueBytesFirst" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 1)) (.literal 0 (ByteArray.mk #[2]))]
      (.return_ (some 1))]]
  expectCfgErrCode "N9 canonical valueBytes before ValueId assignment"
    .nonCanonical n9
  let n10 ← programWithTypes "ValueIdCanonN10AssignmentBeforeTypeRef"
    cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 1, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ (some 1))]]
  expectCfgErr "N10 ValueId assignment before def-site TypeId range" n10
  let n11 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.foo"] }
  }
  expectCfgErr "N11 ValueId assignment before requirements" n11

  -- Raw transport accepts and exactly preserves N4. Structure validation,
  -- structure-gated encode, and carrier decode reject the same bytes.
  let qnB ← expectOk "transport qn" (encodeQualifiedName n4.qualifiedName)
  let typesB ← expectOk "transport types" (encodeArray encodeTypeDeclV1 n4.types)
  let constsB ← expectOk "transport constants"
    (encodeArray encodeConstantV1 n4.constants)
  let stateB ← expectOk "transport state" (encodeArray encodeStateDeclV1 n4.logicalState)
  let eventsB ← expectOk "transport events" (encodeArray encodeEventDeclV1 n4.events)
  let errorsB ← expectOk "transport errors" (encodeArray encodeErrorDeclV1 n4.errors)
  let callablesB ← expectOk "transport callables"
    (encodeArray encodeCallableV1 n4.callables)
  let invsB ← expectOk "transport invariants"
    (encodeArray encodeInvariantDeclV1 n4.invariants)
  let reqsB ← expectOk "transport requirements"
    (encodeProgramRequirementsV1 n4.requirements)
  let body ← expectOk "transport body" (encodeTagged "SemanticProgram.Data" #[
    qnB, typesB, constsB, stateB, eventsB, errorsB, callablesB, invsB, reqsB])
  let raw := (semanticProgramMagicV1.toUTF8.push 0).append body
  let decoded ← expectOk "transport accepts noncanonical ValueIds"
    (decodeSemanticProgramDataV1 raw)
  expect (decoded == n4) "transport preserves noncanonical ValueIds exactly"
  expectCfgErr "transport-decoded noncanonical ValueIds" decoded
  expectErr "carrier rejects noncanonical ValueIds" .badCfg
    (decodeSemanticProgramV1 raw)

/-- SPEC §6.2 dominance-of-use: every ValueId use must be in a block dominated
    by the def's block. A block D dominates B iff every path from entry (0) to
    B passes through D. Failure → `.badCfg`. These cases pass the earlier
    reachability / arity / loopBounds / SSA def-table (exactly-once +
    use-existence) steps so the `.badCfg` is attributable purely to dominance. -/
private def testCfgDominanceOfUse : IO Unit := do
  -- POSITIVES (def block dominates use block).
  -- DP1 single-block: instr result 0 := lit; return (some 0). Def@0 dominates use@0.
  let dp1 ← programWithTypes "DomP1Single" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.return_ (some 0))]]
  expectCfgOk "DP1 single-block def dominates use" dp1
  -- DP2 callable param: param valueId 0, block 0 return (some 0).
  --   Callable param def@entry=0 dominates use@0.
  let dp2 ← programWithTypes "DomP2Param" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[cfgBlock 0 (.return_ (some 0))]]
  expectCfgOk "DP2 callable param dominates use" dp2
  -- DP3 block param self-domination: callable param valueId 0, block 0 jump
  --   args #[0] to block 1, block 1 param valueId 1 return (some 1). The
  --   jump-arg use@0 of ValueId 0 is dominated by callable-param def@entry=0;
  --   the block-param def@1 dominates the return use@1 of ValueId 1. Distinct
  --   ValueIds keep SSA exactly-once. No back edge → loopBounds := #[].
  let dp3 ← programWithTypes "DomP3BlockParam" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.jump (cfgJumpTargetWithArgs 1 #[0])),
          cfgBlockWithParams 1 #[cfgBoolParam 1] (.return_ (some 1))
        ]]
  expectCfgOk "DP3 block param dominates self use" dp3
  -- DP4 dominator on only path: the sole result is canonical ValueId 0;
  --   block 1 dominates block 2 on the only path 0→1→2.
  let dp4 ← programWithTypes "DomP4OnlyPath" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlockInstrs 1
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.jump (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ (some 0))
    ]]
  expectCfgOk "DP4 dominator on only path" dp4
  -- DP5 def in dominator of both branch arms: block 0 instr result 0 := lit,
  --   branch 0 → block 1 / block 2; block 1 return (some 0);
  --   block 2 return (some 0). Block 0 dominates both block 1 and block 2.
  let dp5 ← programWithTypes "DomP5BranchDominator" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
        (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
      cfgBlock 1 (.return_ (some 0)),
      cfgBlock 2 (.return_ (some 0))
    ]]
  expectCfgOk "DP5 branch dominator of both arms" dp5
  -- NEGATIVES (use in a block NOT dominated by def block).
  -- DN1 def in one branch arm, use at join: block 0 branch cond(0) → block 1 /
  --   block 2; block 1 instr result 1 := lit, jump 3; block 2 jump 3;
  --   block 3 return (some 1). Block 1 does NOT dominate block 3
  --   (path 0→2→3 avoids block 1). ValueId 1 is canonical after param 0,
  --   reachable → only dominance fails. Condition uses callable param 0
  --   (defined at entry, dominates all). No back edge.
  let dn1 ← programWithTypes "DomN1ArmDefJoinUse" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0)]
            (.jump (cfgJumpTarget 3)),
          cfgBlock 2 (.jump (cfgJumpTarget 3)),
          cfgBlock 3 (.return_ (some 1))
        ]]
  expectCfgErr "DN1 def in arm, use at join not dominated" dn1
  -- DN2 def in later block, use in earlier reachable block: block 0 branch
  --   cond(0) → block 1 / block 2; canonical results are block-1 ValueId 1
  --   (`not 2`) then block-2 ValueId 2; both arms reach block 3.
  --   ValueId 2 is defined only in block 2 but used in block 1; both arms
  --   reachable; block 2 does not dominate block 1 → only dominance fails.
  --   Condition uses callable param 0.
  let dn2 ← programWithTypes "DomN2LaterDefEarlierUse" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[cfgInstr (some (cfgValueDef 1)) (.unary .not 2)]
            (.jump (cfgJumpTarget 3)),
          cfgBlockInstrs 2
            #[cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0)]
            (.jump (cfgJumpTarget 3)),
          cfgBlock 3 (.return_ none)
        ]]
  expectCfgErr "DN2 later block def, earlier block use not dominated" dn2
  -- DN3 def in non-dominating arm used in sibling arm: block 0 branch cond(0)
  --   → block 1 / block 2; block 1 canonical result 1 := lit, return 1;
  --   block 2 returns 1. Block 1 does NOT dominate block 2. ValueId 1 is
  --   once, use-exists, both arms reachable → only dominance fails. Condition
  --   uses callable param 0.
  let dn3 ← programWithTypes "DomN3ArmDefSiblingUse" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0)]
            (.return_ (some 1)),
          cfgBlock 2 (.return_ (some 1))
        ]]
  expectCfgErr "DN3 arm def, sibling arm use not dominated" dn3

/-! ### step h/i: def-site TypeId range + terminator typing

    Positives P1–P5 (expectCfgOk) and negatives N1–N8 (dual path):
    N1/N2 → `.badReference` (def-site TypeId OOR); N3–N8 → `.badCfg`
    (terminator typing mismatch). Uses cfgUint8Types (Bool=0, UInt8=1) so
    type mismatches are observable. -/

private def cfgCallableResult (blocks : Array BlockV1)
    (resultTypeId : TypeIdV1 := 0) : CallableV1 :=
  {
    id := 0
    kind := .pureFn
    name := some "f"
    params := #[]
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks
    loopBounds := #[]
    invariantSteps := none
  }

private def testCfgBlockParamTypeAndTerminatorTyping : IO Unit := do
  -- P1: jump arg type matches target block param type (UInt8 → UInt8).
  let p1 ← programWithTypes "TypP1JumpArg" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7)]
          (.jump (cfgJumpTargetWithArgs 1 #[1])),
         cfgBlockWithParams 1 #[cfgUint8Param 0] (.return_ (some 0))
      ] 1]
  expectCfgOk "P1 jump arg type matches" p1
  -- P2: branch cond Bool + then/else arg types match (Bool cond, UInt8 args).
  let p2 ← programWithTypes "TypP2Branch" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 7) ]
          (.branch 2
            (cfgJumpTargetWithArgs 1 #[3])
            (cfgJumpTargetWithArgs 2 #[3])),
         cfgBlockWithParams 1 #[cfgUint8Param 0] (.return_ (some 0)),
         cfgBlockWithParams 2 #[cfgUint8Param 1] (.return_ (some 1))
      ] 1]
  expectCfgOk "P2 branch cond Bool + arg types match" p2
  -- P3: switch scrut Bool + case.typeId Bool + case arg type matches.
  let p3 ← programWithTypes "TypP3Switch" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 7) ]
          (.switch 2
            #[{ typeId := 0, valueBytes := ByteArray.mk #[1],
                target := cfgJumpTargetWithArgs 1 #[3] }]
            (some (cfgJumpTargetWithArgs 2 #[3]))),
         cfgBlockWithParams 1 #[cfgUint8Param 0] (.return_ (some 0)),
         cfgBlockWithParams 2 #[cfgUint8Param 1] (.return_ (some 1))
      ] 1]
  expectCfgOk "P3 switch scrut Bool + case.typeId Bool + arg match" p3
  -- P4: return value type == result type (UInt8).
  let p4 ← programWithTypes "TypP4Return" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 9)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P4 return value type == result type" p4
  -- P5: regression single-block Bool return (existing shape, type-stable).
  let p5 ← programWithTypes "TypP5BoolReturn" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
          (.return_ (some 0))
      ] 0]
  expectCfgOk "P5 single-block Bool return regression" p5
  -- N1: block-param typeId OOR → .badReference. Single block so no arity
  --   interaction; the OOR block param is the sole def of valueId 0.
  let n1 ← programWithTypes "TypN1BlockParamOOR" cfgUint8Types #[]
    #[cfgCallableResult
      #[ { id := 0,
           params := #[{ valueId := 0, typeId := 99 }],
           instructions := #[],
           terminator := .return_ (some 0) }
      ] 1]
  expectCfgErrCode "N1 block-param typeId OOR" .badReference n1
  -- N2: instr-result ValueDef typeId OOR → .badReference.
  let n2 ← programWithTypes "TypN2InstrResultOOR" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[{ result := some { valueId := 0, typeId := 99 },
              op := cfgUint8Lit 9 }]
          (.return_ (some 0))
      ] 1]
  expectCfgErrCode "N2 instr-result ValueDef typeId OOR" .badReference n2
  -- N3: branch cond non-Bool (UInt8) → .badCfg.
  let n3 ← programWithTypes "TypN3BranchNonBool" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1)]
          (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
         cfgBlock 1 (.return_ none),
         cfgBlock 2 (.return_ none)
      ] 0]
  expectCfgErr "N3 branch cond non-Bool" n3
  -- N4: switch case typeId != scrutinee type → .badCfg.
  let n4 ← programWithTypes "TypN4SwitchCaseType" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1)]
          (.switch 0
            #[{ typeId := 0, valueBytes := ByteArray.mk #[1],
                target := cfgJumpTarget 1 }]
            none),
         cfgBlock 1 (.return_ none)
      ] 0]
  expectCfgErr "N4 switch case typeId != scrutinee type" n4
  -- N5: jump arg type != target param type → .badCfg.
  let n5 ← programWithTypes "TypN5JumpArgType" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
          (.jump (cfgJumpTargetWithArgs 1 #[1])),
         cfgBlockWithParams 1 #[cfgUint8Param 0] (.return_ (some 0))
      ] 1]
  expectCfgErr "N5 jump arg type != target param type" n5
  -- N6: branch then-arg type mismatch → .badCfg.
  let n6 ← programWithTypes "TypN6BranchThenArg" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1) ]
          (.branch 2
            (cfgJumpTargetWithArgs 1 #[3])
            (cfgJumpTargetWithArgs 2 #[3])),
         cfgBlockWithParams 1 #[cfgUint8Param 0] (.return_ (some 0)),
         cfgBlockWithParams 2 #[cfgUint8Param 1] (.return_ (some 1))
      ] 1]
  expectCfgErr "N6 branch then-arg type mismatch" n6
  -- N7: return value type != result type → .badCfg.
  let n7 ← programWithTypes "TypN7ReturnType" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
          (.return_ (some 0))
      ] 1]
  expectCfgErr "N7 return value type != result type" n7
  -- N8: switch default-target arg type mismatch → .badCfg.
  let n8 ← programWithTypes "TypN8SwitchDefaultArg" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1) ]
          (.switch 2
            #[{ typeId := 0, valueBytes := ByteArray.mk #[1],
                target := cfgJumpTargetWithArgs 1 #[3] }]
            (some (cfgJumpTargetWithArgs 2 #[3]))),
         cfgBlockWithParams 1 #[cfgUint8Param 0] (.return_ (some 0)),
         cfgBlockWithParams 2 #[cfgUint8Param 1] (.return_ (some 1))
      ] 1]
  expectCfgErr "N8 switch default-target arg type mismatch" n8

/-! ### step j: per-op type/result contract (SPEC-SEM-WIRE-001 §5.1)

    Value-producing ops (literal/constant/stateLoad/construct/fieldGet/
    indexGet/unary/binary/pureCall) must produce a result whose TypeId matches
    the op's type contract, and any ValueId operand types must match the
    declared operand contract. Void/side-effecting ops with `result := none`
    are skipped (no result-type check this slice). All failures → `.badCfg`.
    Uses an 8-type fixture table:
      typeId 0 = Struct{a:UInt8, b:UInt8}, 1 = Enum{V(UInt8)},
      typeId 2 = Bool, 3 = UInt8, 4 = UInt32, 5 = Option<UInt8>,
      typeId 6 = Map<UInt8,UInt8>, 7 = Bytes(4). Named declarations occupy the
      contiguous prefix (SPEC §5). -/

private def cfgOpTypes : Array TypeDeclV1 :=
  #[{ id := 0, name := some "S",
       shape := .struct #[{ name := "a", typeId := 3 },
                          { name := "b", typeId := 3 }] },
    { id := 1, name := some "E",
       shape := .enum #[{ name := "v", payloadTypes := #[3] }] },
    { id := 2, name := none, shape := .bool },
    { id := 3, name := none, shape := .uint 8 },
    { id := 4, name := none, shape := .uint 32 },
    { id := 5, name := none, shape := .option 3 },
    { id := 6, name := none, shape := .map 3 3 },
    { id := 7, name := none, shape := .bytes 4 }]

/-- `cfgOpTypes`-specific helpers. The named-prefix migration moved
    Bool→typeId 2, UInt8→3, UInt32→4, Option→5, Struct→0, Enum→1 (Map/Bytes
    unchanged). These mirror the shared `cfg*` helpers but use the migrated
    `cfgOpTypes` typeIds so callers keep their original intent. -/
private def cfgOpBoolDef (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 2 }

private def cfgOpBoolLit (byte : UInt8) : SemanticOpV1 :=
  .literal 2 (ByteArray.mk #[byte])

private def cfgOpU8Def (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 3 }

private def cfgOpU8Lit (byte : UInt8) : SemanticOpV1 :=
  .literal 3 (ByteArray.mk #[byte])

private def cfgOpU32Def (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 4 }

private def cfgOpU32Lit (value : UInt32) : SemanticOpV1 :=
  .literal 4 (leBytesFromNat value.toNat 4)

/-- `cfgCallableResult` with the default resultTypeId fixed to `cfgOpTypes`
    Bool (typeId 2). -/
private def cfgOpCallableResult (blocks : Array BlockV1)
    (resultTypeId : TypeIdV1 := 2) : CallableV1 :=
  {
    id := 0
    kind := .pureFn
    name := some "f"
    params := #[]
    result := { typeId := resultTypeId, visibility := .public_ }
    entryBlock := 0
    blocks
    loopBounds := #[]
    invariantSteps := none
  }

/-- Program builder that also accepts logicalState (cfgOpTyping needs a State
    row for stateLoad). -/
private def programWithState (name : String) (types : Array TypeDeclV1)
    (constants : Array ConstantV1) (state : Array StateDeclV1)
    (callables : Array CallableV1) : IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  let entryId : CallableIdV1 := callables.size.toUInt32
  pure { data0 with
    types := types
    constants := constants
    logicalState := state
    callables := callables.push (entryGateCallable entryId) }

/-- State row (id, name, typeId, visibility). -/
private def stateRow (id : StateIdV1) (name : String) (typeId : TypeIdV1) :
    StateDeclV1 :=
  { id, name, typeId, visibility := .public_ }

/-- Public interface field for ErrorDecl/EventDecl declaration-join tests. -/
private def interfaceField (name : String) (typeId : TypeIdV1) :
    InterfaceFieldV1 :=
  { name, typeId, visibility := .public_ }

private def errorRow (id : ErrorIdV1) (name : String)
    (fields : Array InterfaceFieldV1) : ErrorDeclV1 :=
  { id, name, fields }

private def eventRow (id : EventIdV1) (name : String)
    (fields : Array InterfaceFieldV1) : EventDeclV1 :=
  { id, name, fields }

private def programWithEvents (name : String) (types : Array TypeDeclV1)
    (events : Array EventDeclV1) (callables : Array CallableV1) :
    IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  let entryId : CallableIdV1 := callables.size.toUInt32
  pure { data0 with
    types := types
    events := events
    callables := callables.push (entryGateCallable entryId) }

private def programWithErrors (name : String) (types : Array TypeDeclV1)
    (errors : Array ErrorDeclV1) (callables : Array CallableV1) :
    IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  let entryId : CallableIdV1 := callables.size.toUInt32
  pure { data0 with
    types := types
    errors := errors
    callables := callables.push (entryGateCallable entryId) }

/-- SPEC-SEM-WIRE-001 §8 bounded invariant-root direct-op closure slice:
    StateLoad is allowed, but StateStore is forbidden directly in an invariant
    root. Transitive pureFn closure and other forbidden op families remain
    separate. All cases drive structure and encoder paths. -/
private def testInvariantRootStateStoreProhibited : IO Unit := do
  let state := #[stateRow 0 "flag" 0]
  let allowedLoadRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.stateLoad 0)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithState "InvStoreP1Load" cfgBoolTypes #[] state
    #[allowedLoadRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgOk "P1 invariant root direct StateLoad allowed" p1
  let forbiddenStoreRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.stateStore 0 0)]
        (.return_ (some 0))]
      invariantSteps := some 4
  }
  let n1Base ← programWithState "InvStoreN1Root" cfgBoolTypes #[] state
    #[forbiddenStoreRoot]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root direct StateStore forbidden" n1
  -- Scope guard: the same valid StateStore remains allowed in an entry.
  let entryStore : CallableV1 := {
    forbiddenStoreRoot with
      kind := .entry
      name := some "run"
      invariantSteps := none
  }
  let p2 ← programWithState "InvStoreP2Entry" cfgBoolTypes #[] state
    #[entryStore]
  expectCfgOk "P2 entry direct StateStore remains allowed" p2
  -- Canonical valueBytes precede CFG and invariant closure restrictions.
  let badValueRoot : CallableV1 := {
    forbiddenStoreRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0))
            (.literal 0 (ByteArray.mk #[2])),
          cfgInstr none (.stateStore 0 0)]
        (.return_ (some 0))]
  }
  let n2Base ← programWithState "InvStoreN2ValueFirst" cfgBoolTypes #[] state
    #[badValueRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 canonical value before invariant StateStore"
    .nonCanonical n2
  -- Complete CFG/op typing precedes the invariant closure restriction.
  let badCfgRoot : CallableV1 := {
    forbiddenStoreRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 1),
          cfgInstr none (.stateStore 0 0)]
        (.return_ none)]
  }
  let n3Base ← programWithState "InvStoreN3CfgFirst" cfgBoolTypes #[] state
    #[badCfgRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N3 CFG def-site before invariant StateStore"
    .badReference n3
  expectCfgInvariantPhase "N3 CFG def-site phase wins"
    .cfg .badReference n3
  -- Valid references still reach StateStore op typing before the closure gate:
  -- value 0 is UInt8 while state 0 is Bool. Value 1 keeps the invariant's
  -- required Bool return independently valid.
  let badStoreTypingRoot : CallableV1 := {
    forbiddenStoreRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
          cfgInstr none (.stateStore 0 0)]
        (.return_ (some 1))]
  }
  let n4Base ← programWithState "InvStoreN4StoreTyping" cfgUint8Types #[] state
    #[badStoreTypingRoot]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 StateStore op typing before invariant closure"
    .badCfg n4
  expectCfgInvariantPhase "N4 StateStore typing phase wins"
    .cfg .badCfg n4
  -- An allowed invariant StateLoad with valid references but a mismatched
  -- result type proves generic op typing is active independently of StateStore.
  let badLoadTypingRoot : CallableV1 := {
    allowedLoadRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (.stateLoad 0),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n5Base ← programWithState "InvStoreN5LoadTyping" cfgUint8Types #[] state
    #[badLoadTypingRoot]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N5 invariant StateLoad op typing enforced"
    .badCfg n5
  expectCfgInvariantPhase "N5 StateLoad typing phase isolated"
    .cfg .badCfg n5
  -- Invariant closure restrictions precede intrinsic fuel and requirements.
  let n6 : SemanticProgramDataV1 := {
    n1 with callables := #[{ forbiddenStoreRoot with
      invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N6 invariant StateStore before fuel ceiling" .badCfg n6
  expectCfgInvariantPhase "N6 invariant closure phase wins"
    .invariantClosure .badCfg n6
  let n7 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-store"] }
  }
  expectCfgErr "N7 invariant StateStore before requirements" n7

/-- SPEC-SEM-WIRE-001 §8 bounded invariant-root direct-op closure slice:
    ContextRead is forbidden directly in an invariant root but remains outside
    this slice for other callable kinds. Exact ContextRead key/requirement type
    binding and the transitive pureFn closure op allowlist remain separate. -/
private def testInvariantRootContextReadProhibited : IO Unit := do
  let ctxKey := unixTimeSecondsContextKeyV1
  let ctxTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 64 }]
  let ctxReq := #[← exactContextRequirementRowV1]
  let forbiddenReadRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 1 }) (.contextRead ctxKey),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
      invariantSteps := some 4
  }
  let n1Base ← programWithTypes "InvCtxN1Root" ctxTypes #[]
    #[forbiddenReadRoot] ctxReq
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root direct ContextRead forbidden" n1
  expectCfgInvariantPhase "N1 invariant ContextRead closure phase"
    .invariantClosure .badCfg n1
  -- Scope guard: ContextRead remains accepted in an entry; its local op
  --   branch is presence-only and the §5.1 same-key result-TypeId global
  --   consistency pass is satisfied by the single Bool read below.
  let entryRead : CallableV1 := {
    forbiddenReadRoot with
      kind := .entry
      name := some "run"
      invariantSteps := none
  }
  let p1 ← programWithTypes "InvCtxP1Entry" ctxTypes #[] #[entryRead] ctxReq
  expectCfgOk "P1 entry direct ContextRead remains allowed" p1
  -- Generic result-presence typing must win before the closure restriction.
  -- The separate Bool literal keeps the invariant return valid.
  let missingResultRoot : CallableV1 := {
    forbiddenReadRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.contextRead ctxKey),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 4
  }
  let n2Base ← programWithTypes "InvCtxN2Typing" ctxTypes #[]
    #[missingResultRoot] ctxReq
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 ContextRead typing before invariant closure" .badCfg n2
  expectCfgInvariantPhase "N2 ContextRead typing phase wins" .cfg .badCfg n2
  -- Closure restrictions precede intrinsic fuel and requirements.
  let n3 : SemanticProgramDataV1 := {
    n1 with callables := #[{ forbiddenReadRoot with
      invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N3 invariant ContextRead before fuel ceiling" .badCfg n3
  expectCfgInvariantPhase "N3 ContextRead closure phase wins"
    .invariantClosure .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-context-read"] }
  }
  expectCfgErr "N4 invariant ContextRead before requirements" n4

/-- SPEC-SEM-WIRE-001 §8 bounded invariant-root direct-op closure slice:
    Commit is forbidden directly in an invariant root but remains allowed in an
    entry when operand/result TypeIds match. Exact disclosure requirement
    validation and the transitive pureFn closure op allowlist remain separate. -/
private def testInvariantRootCommitProhibited : IO Unit := do
  let commitReq := #[← exactCommitRequirementRowV1]
  let forbiddenCommitRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr (some (cfgValueDef 1)) (.commit 0)]
        (.return_ (some 1))]
      invariantSteps := some 4
  }
  let n1Base ← programWithTypes "InvCommitN1Root" cfgBoolTypes #[]
    #[forbiddenCommitRoot] commitReq
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root direct Commit forbidden" n1
  expectCfgInvariantPhase "N1 invariant Commit closure phase"
    .invariantClosure .badCfg n1
  let entryCommit : CallableV1 := {
    forbiddenCommitRoot with
      kind := .entry
      name := some "run"
      invariantSteps := none
  }
  let p1 ← programWithTypes "InvCommitP1Entry" cfgBoolTypes #[]
    #[entryCommit] commitReq
  expectCfgOk "P1 entry direct Commit remains allowed" p1
  -- Generic result-presence typing must win before the closure restriction.
  let missingResultRoot : CallableV1 := {
    forbiddenCommitRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.commit 0),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
      invariantSteps := some 5
  }
  let n2Base ← programWithTypes "InvCommitN2Typing" cfgBoolTypes #[]
    #[missingResultRoot] commitReq
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 Commit typing before invariant closure" .badCfg n2
  expectCfgInvariantPhase "N2 Commit typing phase wins" .cfg .badCfg n2
  -- Closure restrictions precede intrinsic fuel and requirements.
  let n3 : SemanticProgramDataV1 := {
    n1 with callables := #[{ forbiddenCommitRoot with
      invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N3 invariant Commit before fuel ceiling" .badCfg n3
  expectCfgInvariantPhase "N3 Commit closure phase wins"
    .invariantClosure .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-commit"] }
  }
  expectCfgErr "N4 invariant Commit before requirements" n4

/-- SPEC-SEM-WIRE-001 §8 bounded invariant-root direct-op closure slice:
    Emit is forbidden directly in an invariant root but remains allowed in an
    entry. Generic EventDecl/args/void-result typing and EffectId assignment run
    before this restriction; the transitive pureFn closure op allowlist remains
    separate. -/
private def testInvariantRootEmitProhibited : IO Unit := do
  let forbiddenEmitRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.emit 0 0 #[])]
        (.return_ (some 0))]
      invariantSteps := some 4
  }
  let n1Base ← programWithEvents "InvEmitN1Root" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[forbiddenEmitRoot]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root direct Emit forbidden" n1
  expectCfgInvariantPhase "N1 invariant Emit closure phase"
    .invariantClosure .badCfg n1
  let entryEmit : CallableV1 := {
    forbiddenEmitRoot with
      kind := .entry
      name := some "run"
      invariantSteps := none
  }
  let p1 ← programWithEvents "InvEmitP1Entry" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[entryEmit]
  expectCfgOk "P1 entry direct Emit remains allowed" p1
  -- Generic void-result typing must win before the closure restriction.
  let badTypingRoot : CallableV1 := {
    forbiddenEmitRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr (some (cfgValueDef 1)) (.emit 0 0 #[])]
        (.return_ (some 0))]
  }
  let n2Base ← programWithEvents "InvEmitN2Typing" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[badTypingRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 Emit typing before invariant closure" .badCfg n2
  expectCfgInvariantPhase "N2 Emit typing phase wins" .cfg .badCfg n2
  let badEffectRoot : CallableV1 := {
    forbiddenEmitRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.emit 1 0 #[])]
        (.return_ (some 0))]
  }
  let n3Base ← programWithEvents "InvEmitN3Effect" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[badEffectRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N3 EffectId before invariant Emit closure" .badCfg n3
  expectCfgInvariantPhase "N3 EffectId phase wins" .cfg .badCfg n3
  let badEventRoot : CallableV1 := {
    forbiddenEmitRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.emit 0 1 #[])]
        (.return_ (some 0))]
  }
  let n4Base ← programWithEvents "InvEmitN4Event" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[badEventRoot]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 event lookup before invariant Emit closure" .badCfg n4
  expectCfgInvariantPhase "N4 event lookup phase wins" .cfg .badCfg n4
  let n5Base ← programWithEvents "InvEmitN5Arity" cfgBoolTypes
    #[eventRow 0 "Value" #[interfaceField "value" 0]] #[forbiddenEmitRoot]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N5 Emit arity before invariant closure" .badCfg n5
  expectCfgInvariantPhase "N5 Emit arity phase wins" .cfg .badCfg n5
  let badTypeRoot : CallableV1 := {
    forbiddenEmitRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.emit 0 0 #[0])]
        (.return_ (some 0))]
  }
  let n6Base ← programWithEvents "InvEmitN6Type" cfgUint8Types
    #[eventRow 0 "Value" #[interfaceField "value" 1]] #[badTypeRoot]
  let n6 : SemanticProgramDataV1 := {
    n6Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N6 Emit arg type before invariant closure" .badCfg n6
  expectCfgInvariantPhase "N6 Emit arg type phase wins" .cfg .badCfg n6
  let badSsaRoot : CallableV1 := {
    forbiddenEmitRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.emit 0 0 #[99])]
        (.return_ (some 0))]
  }
  let n7Base ← programWithEvents "InvEmitN7Ssa" cfgBoolTypes
    #[eventRow 0 "Value" #[interfaceField "value" 0]] #[badSsaRoot]
  let n7 : SemanticProgramDataV1 := {
    n7Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N7 Emit SSA use before invariant closure" .badCfg n7
  expectCfgInvariantPhase "N7 Emit SSA phase wins" .cfg .badCfg n7
  -- Closure restrictions precede intrinsic fuel and requirements.
  let n8 : SemanticProgramDataV1 := {
    n1 with callables := #[{ forbiddenEmitRoot with
      invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N8 invariant Emit before fuel ceiling" .badCfg n8
  expectCfgInvariantPhase "N8 Emit closure phase wins"
    .invariantClosure .badCfg n8
  let n9 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-emit"] }
  }
  expectCfgErr "N9 invariant Emit before requirements" n9

/-- SPEC §8 bounded invariant-root direct-op slice for ExternalCall. Generic
    EffectId, callee-shape, SSA, and void-result checks run first; argument
    serializability and the transitive pureFn closure op allowlist remain
    deferred. -/
private def testInvariantRootExternalCallProhibited : IO Unit := do
  let callee ← match parseQualifiedName #["mod", "callee"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let shortCallee ← match parseQualifiedName #["callee"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let forbiddenRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.externalCall 0 callee #[])]
        (.return_ (some 0))]
      invariantSteps := some 4
  }
  let n1Base ← programWithTypes "InvCallN1Root" cfgBoolTypes #[] #[forbiddenRoot]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root direct ExternalCall forbidden" n1
  expectCfgInvariantPhase "N1 ExternalCall closure phase"
    .invariantClosure .badCfg n1
  let entryCall : CallableV1 := {
    forbiddenRoot with
      kind := .entry
      name := some "run"
      invariantSteps := none
  }
  let p1 ← programWithTypes "InvCallP1Entry" cfgBoolTypes #[] #[entryCall]
  expectCfgOk "P1 entry direct ExternalCall remains allowed" p1
  let badResultRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr (some (cfgValueDef 1)) (.externalCall 0 callee #[])]
        (.return_ (some 0))]
  }
  let n2Base ← programWithTypes "InvCallN2Result" cfgBoolTypes #[] #[badResultRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 ExternalCall result before closure" .badCfg n2
  expectCfgInvariantPhase "N2 ExternalCall result phase wins" .cfg .badCfg n2
  let badEffectRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.externalCall 1 callee #[])]
        (.return_ (some 0))]
  }
  let n3Base ← programWithTypes "InvCallN3Effect" cfgBoolTypes #[] #[badEffectRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N3 ExternalCall EffectId before closure" .badCfg n3
  expectCfgInvariantPhase "N3 ExternalCall EffectId phase wins" .cfg .badCfg n3
  let badCalleeRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.externalCall 0 shortCallee #[])]
        (.return_ (some 0))]
  }
  let n4Base ← programWithTypes "InvCallN4Callee" cfgBoolTypes #[] #[badCalleeRoot]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 ExternalCall callee before closure" .badCfg n4
  expectCfgInvariantPhase "N4 ExternalCall callee phase wins" .cfg .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with callables := #[{ forbiddenRoot with
      invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N5 ExternalCall before fuel" .badCfg n5
  expectCfgInvariantPhase "N5 ExternalCall closure phase wins"
    .invariantClosure .badCfg n5
  let n6 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-external-call"] }
  }
  expectCfgErr "N6 ExternalCall before requirements" n6

/-- SPEC §8 bounded invariant-root direct-op slice for Schedule. Generic
    EffectId, callee-shape, void-result, SSA-existence, and dominance checks run
    first; argument serializability and transitive pureFn closure remain
    deferred. -/
private def testInvariantRootScheduleProhibited : IO Unit := do
  let callee ← match parseQualifiedName #["mod", "workflow"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let shortCallee ← match parseQualifiedName #["workflow"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let forbiddenRoot : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.schedule 0 callee #[])]
        (.return_ (some 0))]
      invariantSteps := some 4
  }
  let n1Base ← programWithTypes "InvScheduleN1Root" cfgBoolTypes #[] #[forbiddenRoot]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N1 invariant root direct Schedule forbidden" n1
  expectCfgInvariantPhase "N1 Schedule closure phase"
    .invariantClosure .badCfg n1
  let entrySchedule : CallableV1 := {
    forbiddenRoot with
      kind := .entry
      name := some "run"
      invariantSteps := none
  }
  let p1 ← programWithTypes "InvScheduleP1Entry" cfgBoolTypes #[] #[entrySchedule]
  expectCfgOk "P1 entry direct Schedule remains allowed" p1
  let badResultRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr (some (cfgValueDef 1)) (.schedule 0 callee #[])]
        (.return_ (some 0))]
  }
  let n2Base ← programWithTypes "InvScheduleN2Result" cfgBoolTypes #[] #[badResultRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N2 Schedule result before closure" .badCfg n2
  expectCfgInvariantPhase "N2 Schedule result phase wins" .cfg .badCfg n2
  let badEffectRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.schedule 1 callee #[])]
        (.return_ (some 0))]
  }
  let n3Base ← programWithTypes "InvScheduleN3Effect" cfgBoolTypes #[] #[badEffectRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N3 Schedule EffectId before closure" .badCfg n3
  expectCfgInvariantPhase "N3 Schedule EffectId phase wins" .cfg .badCfg n3
  let badCalleeRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.schedule 0 shortCallee #[])]
        (.return_ (some 0))]
  }
  let n4Base ← programWithTypes "InvScheduleN4Callee" cfgBoolTypes #[] #[badCalleeRoot]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 Schedule callee before closure" .badCfg n4
  expectCfgInvariantPhase "N4 Schedule callee phase wins" .cfg .badCfg n4
  let undefinedArgRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.schedule 0 callee #[99])]
        (.return_ (some 0))]
  }
  let n5Base ← programWithTypes "InvScheduleN5UndefinedArg"
    cfgBoolTypes #[] #[undefinedArgRoot]
  let n5 : SemanticProgramDataV1 := {
    n5Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N5 Schedule undefined arg before closure" .badCfg n5
  expectCfgInvariantPhase "N5 Schedule undefined arg phase wins" .cfg .badCfg n5
  let nonDominatingArgRoot : CallableV1 := {
    forbiddenRoot with
      blocks := #[
        cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
          (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
        cfgBlockInstrs 1
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0)]
          (.jump (cfgJumpTarget 3)),
        cfgBlock 2 (.jump (cfgJumpTarget 3)),
        cfgBlockInstrs 3
          #[cfgInstr none (.schedule 0 callee #[1])]
          (.return_ (some 0))]
  }
  let n6Base ← programWithTypes "InvScheduleN6NonDominatingArg"
    cfgBoolTypes #[] #[nonDominatingArgRoot]
  let n6 : SemanticProgramDataV1 := {
    n6Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N6 Schedule non-dominating arg before closure" .badCfg n6
  expectCfgInvariantPhase "N6 Schedule non-dominating arg phase wins" .cfg .badCfg n6
  let n7 : SemanticProgramDataV1 := {
    n1 with callables := #[{ forbiddenRoot with
      invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N7 Schedule before fuel" .badCfg n7
  expectCfgInvariantPhase "N7 Schedule closure phase wins"
    .invariantClosure .badCfg n7
  let n8 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-schedule"] }
  }
  expectCfgErr "N8 Schedule before requirements" n8

/-- SPEC §8 exact transitive pureFn closure-membership metadata slice. A
    pureFn carries `invariantSteps=some` iff reachable by `Op.PureCall` from an
    invariant root; other pureFns carry none. Reachable call-graph DAG and
    closure-CFG acyclicity are separate post-membership gates; op allowlists and
    exact step computation remain deferred. -/
private def testInvariantPureFnClosureMembership : IO Unit := do
  let leaf : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "leaf"
      invariantSteps := some 3
  }
  let middle : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      name := some "middle"
      invariantSteps := some 6
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
      (.return_ (some 0))]) with
      id := 2
      kind := .invariant
      name := some "safe"
      invariantSteps := some 9
  }
  let p1Base ← programWithTypes "InvClosureMembershipP1Transitive"
    cfgBoolTypes #[] #[leaf, middle, root]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgOk "P1 transitive pureFn closure members carry steps" p1
  let unused : CallableV1 := {
    leaf with name := some "unused", invariantSteps := none
  }
  let literalRoot : CallableV1 := {
    root with
      id := 1
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p2Base ← programWithTypes "InvClosureMembershipP2UnusedNone"
    cfgBoolTypes #[] #[unused, literalRoot]
  let p2 : SemanticProgramDataV1 := {
    p2Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P2 unused pureFn carries no steps despite invariant root" p2
  let rightLeaf : CallableV1 := {
    leaf with id := 1, name := some "rightLeaf"
  }
  let leftRoot : CallableV1 := {
    root with
      id := 2
      name := some "leftSafe"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
        (.return_ (some 0))]
      invariantSteps := some 6
  }
  let rightRoot : CallableV1 := {
    root with
      id := 3
      name := some "rightSafe"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 6
  }
  let p3Base ← programWithTypes "InvClosureMembershipP3TwoRoots"
    cfgBoolTypes #[] #[leaf, rightLeaf, leftRoot, rightRoot]
  let p3 : SemanticProgramDataV1 := {
    p3Base with invariants := #[
      { id := 0, name := "leftSafe", callableId := 2 },
      { id := 1, name := "rightSafe", callableId := 3 }]
  }
  expectCfgOk "P3 every invariant root seeds its disjoint closure" p3
  let n1 : SemanticProgramDataV1 := {
    p2 with callables := #[{ unused with invariantSteps := some 3 }, literalRoot]
  }
  expectCfgErr "N1 unused pureFn with steps" n1
  expectCfgInvariantPhase "N1 unused pureFn membership phase"
    .invariantClosure .badCfg n1
  let n2 : SemanticProgramDataV1 := {
    p1 with callables := #[{ leaf with invariantSteps := none }, middle, root]
  }
  expectCfgErr "N2 transitive closure pureFn missing steps" n2
  expectCfgInvariantPhase "N2 transitive membership phase"
    .invariantClosure .badCfg n2
  let badCfgRoot : CallableV1 := {
    literalRoot with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 99 #[])]
        (.return_ (some 0))]
  }
  let n3Base ← programWithTypes "InvClosureMembershipN3CfgFirst"
    cfgBoolTypes #[] #[{ unused with invariantSteps := some 3 }, badCfgRoot]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 malformed PureCall before closure membership" .badCfg n3
  expectCfgInvariantPhase "N3 generic CFG phase wins" .cfg .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n2 with callables := #[
      { leaf with invariantSteps := none },
      middle,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 membership before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 closure membership phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-membership"] }
  }
  expectCfgErr "N5 membership before requirements" n5
  expectCfgInvariantPhase "N5 closure membership before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 reachable invariant-closure `Op.PureCall` graph must be a
    DAG. This slice rejects self and multi-node cycles only when reachable from
    an invariant root; closure-CFG acyclicity is a following gate, while op
    allowlists and exact checked step computation remain separate. -/
private def testInvariantPureFnClosureDag : IO Unit := do
  let leaf : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "leaf"
      invariantSteps := some 3
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 6
  }
  let p1Base ← programWithTypes "InvClosureDagP1Acyclic"
    cfgBoolTypes #[] #[leaf, root]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 acyclic invariant PureCall closure" p1
  let unreachableA : CallableV1 := {
    leaf with
      name := some "unreachableA"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := none
  }
  let unreachableB : CallableV1 := {
    unreachableA with
      id := 1
      name := some "unreachableB"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
        (.return_ (some 0))]
  }
  let literalRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p2Base ← programWithTypes "InvClosureDagP2UnreachableCycle"
    cfgBoolTypes #[] #[unreachableA, unreachableB, literalRoot]
  let p2 : SemanticProgramDataV1 := {
    p2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgOk "P2 unreachable pureFn cycle outside invariant closure" p2
  let duplicateEdgeRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[]),
          cfgInstr (some (cfgValueDef 1)) (.pureCall 0 #[])]
        (.return_ (some 1))]
      invariantSteps := some 10
  }
  let p3Base ← programWithTypes "InvClosureDagP3DuplicateEdges"
    cfgBoolTypes #[] #[leaf, duplicateEdgeRoot]
  let p3 : SemanticProgramDataV1 := {
    p3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P3 duplicate static PureCall edges counted independently" p3
  let selfCycle : CallableV1 := {
    leaf with
      name := some "selfCycle"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
        (.return_ (some 0))]
  }
  let n1Base ← programWithTypes "InvClosureDagN1SelfCycle"
    cfgBoolTypes #[] #[selfCycle, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn self-cycle" n1
  expectCfgInvariantPhase "N1 self-cycle closure phase"
    .invariantClosure .badCfg n1
  let cycleA : CallableV1 := {
    leaf with
      name := some "cycleA"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
  }
  let cycleB : CallableV1 := {
    cycleA with
      id := 1
      name := some "cycleB"
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
        (.return_ (some 0))]
  }
  let cycleRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
        (.return_ (some 0))]
      invariantSteps := some 9
  }
  let n2Base ← programWithTypes "InvClosureDagN2TwoCycle"
    cfgBoolTypes #[] #[cycleA, cycleB, cycleRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 reachable two-pureFn cycle" n2
  expectCfgInvariantPhase "N2 two-cycle closure phase"
    .invariantClosure .badCfg n2
  let n3 : SemanticProgramDataV1 := {
    n2 with callables := #[cycleA, cycleB,
      { cycleRoot with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N3 cycle before intrinsic fuel" .badCfg n3
  expectCfgInvariantPhase "N3 cycle closure phase wins"
    .invariantClosure .badCfg n3
  let badCfgA : CallableV1 := {
    cycleA with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 99 #[])]
        (.return_ (some 0))]
  }
  let n4Base ← programWithTypes "InvClosureDagN4CfgFirst"
    cfgBoolTypes #[] #[badCfgA, cycleB, cycleRoot]
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErrCode "N4 malformed PureCall before closure DAG" .badCfg n4
  expectCfgInvariantPhase "N4 generic CFG phase wins" .cfg .badCfg n4

/-- SPEC §8 every callable in an invariant closure has an acyclic CFG.
    Generic loopBounds validation runs first; this closure gate rejects any
    remaining reachable member back edge while leaving unreachable pureFn loops
    to the generic bounded-loop contract. -/
private def testInvariantClosureCfgBackEdges : IO Unit := do
  let leaf : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "leaf"
      invariantSteps := some 3
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 6
  }
  let p1Base ← programWithTypes "InvClosureCfgP1Acyclic"
    cfgBoolTypes #[] #[leaf, root]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 acyclic closure callable CFGs" p1
  let unreachableLoop : CallableV1 :=
    cfgCallableKindNameLoop .pureFn (some "unreachableLoop")
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p2Base ← programWithTypes "InvClosureCfgP2UnreachableLoop"
    cfgBoolTypes #[] #[unreachableLoop, literalRoot]
  let p2 : SemanticProgramDataV1 := {
    p2Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P2 unreachable pureFn bounded loop outside closure" p2
  let reachableLoop : CallableV1 := {
    unreachableLoop with invariantSteps := some 2
  }
  let n1Base ← programWithTypes "InvClosureCfgN1ReachableLoop"
    cfgBoolTypes #[] #[reachableLoop, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn CFG self back-edge" n1
  expectCfgInvariantPhase "N1 closure CFG phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      name := some "middle"
      invariantSteps := some 5
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 8
  }
  let n2Base ← programWithTypes "InvClosureCfgN2TransitiveLoop"
    cfgBoolTypes #[] #[reachableLoop, middle, transitiveRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn CFG back-edge" n2
  expectCfgInvariantPhase "N2 transitive closure CFG phase"
    .invariantClosure .badCfg n2
  let malformedLoop : CallableV1 := {
    reachableLoop with loopBounds := #[]
  }
  let n3Base ← programWithTypes "InvClosureCfgN3GenericFirst"
    cfgBoolTypes #[] #[malformedLoop, root]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 generic loop coverage before closure CFG" .badCfg n3
  expectCfgInvariantPhase "N3 generic CFG phase wins" .cfg .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[reachableLoop,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 closure CFG before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 closure CFG phase wins"
    .invariantClosure .badCfg n4

/-- SPEC §8 forbids logical-state reads in pureFn callables that belong to an
    invariant closure. Invariant roots may still read state directly, and an
    unreachable pureFn remains outside this closure-only restriction. Generic
    StateLoad typing runs before the post-CFG closure gate. -/
private def testInvariantClosurePureFnStateLoadProhibited : IO Unit := do
  let state := #[stateRow 0 "flag" 0]
  let stateReader : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.stateLoad 0)]
      (.return_ (some 0))]) with
      id := 0
      name := some "stateReader"
      invariantSteps := some 3
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 6
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithState "InvClosureLoadP1Unreachable" cfgBoolTypes #[]
    state #[{ stateReader with invariantSteps := none }, literalRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn StateLoad outside invariant closure" p1
  let n1Base ← programWithState "InvClosureLoadN1Reachable" cfgBoolTypes #[]
    state #[stateReader, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn StateLoad" n1
  expectCfgInvariantPhase "N1 pureFn StateLoad closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 6
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 9
  }
  let n2Base ← programWithState "InvClosureLoadN2Transitive" cfgBoolTypes #[]
    state #[stateReader, middle, transitiveRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn StateLoad" n2
  expectCfgInvariantPhase "N2 transitive StateLoad closure phase"
    .invariantClosure .badCfg n2
  let malformedReader : CallableV1 := {
    stateReader with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (.stateLoad 0),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3Base ← programWithState "InvClosureLoadN3CfgFirst" cfgUint8Types #[]
    state #[malformedReader, root]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 malformed StateLoad before closure restriction" .badCfg n3
  expectCfgInvariantPhase "N3 generic StateLoad typing phase wins"
    .cfg .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[stateReader,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn StateLoad before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 StateLoad closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-state-load"] }
  }
  expectCfgErrCode "N5 pureFn StateLoad before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 StateLoad closure before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 forbids logical-state writes in pureFn callables that belong to an
    invariant closure. An unreachable pureFn remains outside this closure-only
    restriction. Generic StateStore typing runs before the post-CFG closure
    gate. -/
private def testInvariantClosurePureFnStateStoreProhibited : IO Unit := do
  let state := #[stateRow 0 "flag" 0]
  let stateWriter : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
        cfgInstr none (.stateStore 0 0)]
      (.return_ (some 0))]) with
      id := 0
      name := some "stateWriter"
      invariantSteps := some 4
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 7
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithState "InvClosureStoreP1Unreachable" cfgBoolTypes #[]
    state #[{ stateWriter with invariantSteps := none }, literalRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn StateStore outside invariant closure" p1
  let n1Base ← programWithState "InvClosureStoreN1Reachable" cfgBoolTypes #[]
    state #[stateWriter, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn StateStore" n1
  expectCfgInvariantPhase "N1 pureFn StateStore closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 7
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 10
  }
  let n2Base ← programWithState "InvClosureStoreN2Transitive" cfgBoolTypes #[]
    state #[stateWriter, middle, transitiveRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn StateStore" n2
  expectCfgInvariantPhase "N2 transitive StateStore closure phase"
    .invariantClosure .badCfg n2
  let malformedWriter : CallableV1 := {
    stateWriter with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
          cfgInstr none (.stateStore 0 0),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3Base ← programWithState "InvClosureStoreN3CfgFirst" cfgUint8Types #[]
    state #[malformedWriter, root]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 malformed StateStore before closure restriction" .badCfg n3
  expectCfgInvariantPhase "N3 generic StateStore typing phase wins"
    .cfg .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[stateWriter,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn StateStore before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 StateStore closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-state-store"] }
  }
  expectCfgErrCode "N5 pureFn StateStore before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 StateStore closure before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 forbids context reads in pureFn callables that belong to an
    invariant closure. An unreachable pureFn remains outside this closure-only
    restriction. Generic ContextRead result-presence validation runs before the
    post-CFG closure gate. -/
private def testInvariantClosurePureFnContextReadProhibited : IO Unit := do
  let ctxKey := unixTimeSecondsContextKeyV1
  let ctxTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 64 }]
  let ctxReq := #[← exactContextRequirementRowV1]
  let contextReader : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 1 }) (.contextRead ctxKey),
        cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
      (.return_ (some 1))]) with
      id := 0
      name := some "contextReader"
      invariantSteps := some 4
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 7
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithTypes "InvClosureCtxP1Unreachable" ctxTypes #[]
    #[{ contextReader with invariantSteps := none }, literalRoot] ctxReq
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn ContextRead outside invariant closure" p1
  let n1Base ← programWithTypes "InvClosureCtxN1Reachable" ctxTypes #[]
    #[contextReader, root] ctxReq
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn ContextRead" n1
  expectCfgInvariantPhase "N1 pureFn ContextRead closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 7
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 10
  }
  let n2Base ← programWithTypes "InvClosureCtxN2Transitive" ctxTypes #[]
    #[contextReader, middle, transitiveRoot] ctxReq
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn ContextRead" n2
  expectCfgInvariantPhase "N2 transitive ContextRead closure phase"
    .invariantClosure .badCfg n2
  let missingResultReader : CallableV1 := {
    contextReader with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.contextRead ctxKey),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3Base ← programWithTypes "InvClosureCtxN3CfgFirst" ctxTypes #[]
    #[missingResultReader, root] ctxReq
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 malformed ContextRead before closure restriction" .badCfg n3
  expectCfgInvariantPhase "N3 generic ContextRead typing phase wins"
    .cfg .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[contextReader,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn ContextRead before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 ContextRead closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-context-read"] }
  }
  expectCfgErrCode "N5 pureFn ContextRead before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 ContextRead closure before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 forbids commitment creation in pureFn callables that belong to an
    invariant closure. An unreachable pureFn remains outside this closure-only
    restriction. Generic Commit operand/result typing runs before the post-CFG
    closure gate. -/
private def testInvariantClosurePureFnCommitProhibited : IO Unit := do
  let commitReq := #[← exactCommitRequirementRowV1]
  let committer : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
        cfgInstr (some (cfgValueDef 1)) (.commit 0)]
      (.return_ (some 1))]) with
      id := 0
      name := some "committer"
      invariantSteps := some 4
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 7
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithTypes "InvClosureCommitP1Unreachable" cfgBoolTypes #[]
    #[{ committer with invariantSteps := none }, literalRoot] commitReq
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn Commit outside invariant closure" p1
  let n1Base ← programWithTypes "InvClosureCommitN1Reachable" cfgBoolTypes #[]
    #[committer, root] commitReq
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn Commit" n1
  expectCfgInvariantPhase "N1 pureFn Commit closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 7
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 10
  }
  let n2Base ← programWithTypes "InvClosureCommitN2Transitive" cfgBoolTypes #[]
    #[committer, middle, transitiveRoot] commitReq
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn Commit" n2
  expectCfgInvariantPhase "N2 transitive Commit closure phase"
    .invariantClosure .badCfg n2
  let missingResultCommitter : CallableV1 := {
    committer with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          cfgInstr none (.commit 0),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3Base ← programWithTypes "InvClosureCommitN3CfgFirst" cfgBoolTypes #[]
    #[missingResultCommitter, root] commitReq
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 malformed Commit before closure restriction" .badCfg n3
  expectCfgInvariantPhase "N3 generic Commit typing phase wins"
    .cfg .badCfg n3
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[committer,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn Commit before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 Commit closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-commit"] }
  }
  expectCfgErrCode "N5 pureFn Commit before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 Commit closure before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 forbids event emission in pureFn callables that belong to an
    invariant closure. An unreachable pureFn remains outside this closure-only
    restriction. Generic Emit declaration/result/EffectId validation runs
    before the post-CFG closure gate. -/
private def testInvariantClosurePureFnEmitProhibited : IO Unit := do
  let emitter : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr none (.emit 0 0 #[]),
        cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "emitter"
      invariantSteps := some 4
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 7
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithEvents "InvClosureEmitP1Unreachable" cfgBoolTypes
    #[eventRow 0 "Ping" #[]]
    #[{ emitter with invariantSteps := none }, literalRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn Emit outside invariant closure" p1
  let n1Base ← programWithEvents "InvClosureEmitN1Reachable" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[emitter, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn Emit" n1
  expectCfgInvariantPhase "N1 pureFn Emit closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 7
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 10
  }
  let n2Base ← programWithEvents "InvClosureEmitN2Transitive" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[emitter, middle, transitiveRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn Emit" n2
  expectCfgInvariantPhase "N2 transitive Emit closure phase"
    .invariantClosure .badCfg n2
  let malformedEmitter : CallableV1 := {
    emitter with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.emit 0 0 #[]),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3Base ← programWithEvents "InvClosureEmitN3CfgFirst" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[malformedEmitter, root]
  let n3 : SemanticProgramDataV1 := {
    n3Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 malformed Emit before closure restriction" .badCfg n3
  expectCfgInvariantPhase "N3 generic Emit typing phase wins"
    .cfg .badCfg n3
  let missingEventEmitter : CallableV1 := {
    emitter with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.emit 0 99 #[]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3EventBase ← programWithEvents "InvClosureEmitN3MissingEvent" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[missingEventEmitter, root]
  let n3Event : SemanticProgramDataV1 := {
    n3EventBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 unresolved EventDecl before closure" .badCfg n3Event
  expectCfgInvariantPhase "N3 unresolved EventDecl generic phase wins"
    .cfg .badCfg n3Event
  let n3ArityBase ← programWithEvents "InvClosureEmitN3Arity" cfgBoolTypes
    #[eventRow 0 "Ping" #[interfaceField "flag" 0]] #[emitter, root]
  let n3Arity : SemanticProgramDataV1 := {
    n3ArityBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Emit arg arity before closure" .badCfg n3Arity
  expectCfgInvariantPhase "N3 Emit arg arity generic phase wins"
    .cfg .badCfg n3Arity
  let wrongArgTypeEmitter : CallableV1 := {
    emitter with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
          cfgInstr none (.emit 0 0 #[0]),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3TypeBase ← programWithEvents "InvClosureEmitN3Type" cfgUint8Types
    #[eventRow 0 "Ping" #[interfaceField "flag" 0]] #[wrongArgTypeEmitter, root]
  let n3Type : SemanticProgramDataV1 := {
    n3TypeBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Emit arg type before closure" .badCfg n3Type
  expectCfgInvariantPhase "N3 Emit arg type generic phase wins"
    .cfg .badCfg n3Type
  let badEffectIdEmitter : CallableV1 := {
    emitter with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.emit 1 0 #[]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3EffectBase ← programWithEvents "InvClosureEmitN3EffectId" cfgBoolTypes
    #[eventRow 0 "Ping" #[]] #[badEffectIdEmitter, root]
  let n3Effect : SemanticProgramDataV1 := {
    n3EffectBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Emit EffectId before closure" .badCfg n3Effect
  expectCfgInvariantPhase "N3 Emit EffectId generic phase wins"
    .cfg .badCfg n3Effect
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[emitter,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn Emit before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 Emit closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-emit"] }
  }
  expectCfgErrCode "N5 pureFn Emit before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 Emit closure before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 forbids synchronous external calls in pureFn callables that belong
    to an invariant closure. An unreachable pureFn remains outside this
    closure-only restriction. Generic void-result, EffectId, callee-shape, and
    SSA validation runs before the post-CFG closure gate; argument
    serializability remains deferred. -/
private def testInvariantClosurePureFnExternalCallProhibited : IO Unit := do
  let callee ← match parseQualifiedName #["mod", "callee"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let shortCallee ← match parseQualifiedName #["callee"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let caller : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr none (.externalCall 0 callee #[]),
        cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "caller"
      invariantSteps := some 4
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 7
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithTypes "InvClosureCallP1Unreachable" cfgBoolTypes #[]
    #[{ caller with invariantSteps := none }, literalRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn ExternalCall outside invariant closure" p1
  let n1Base ← programWithTypes "InvClosureCallN1Reachable" cfgBoolTypes #[]
    #[caller, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn ExternalCall" n1
  expectCfgInvariantPhase "N1 pureFn ExternalCall closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 7
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 10
  }
  let n2Base ← programWithTypes "InvClosureCallN2Transitive" cfgBoolTypes #[]
    #[caller, middle, transitiveRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn ExternalCall" n2
  expectCfgInvariantPhase "N2 transitive ExternalCall closure phase"
    .invariantClosure .badCfg n2
  let badResultCaller : CallableV1 := {
    caller with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.externalCall 0 callee #[]),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3ResultBase ← programWithTypes "InvClosureCallN3Result" cfgBoolTypes #[]
    #[badResultCaller, root]
  let n3Result : SemanticProgramDataV1 := {
    n3ResultBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 ExternalCall result before closure" .badCfg n3Result
  expectCfgInvariantPhase "N3 ExternalCall result generic phase wins"
    .cfg .badCfg n3Result
  let badEffectCaller : CallableV1 := {
    caller with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.externalCall 1 callee #[]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3EffectBase ← programWithTypes "InvClosureCallN3Effect" cfgBoolTypes #[]
    #[badEffectCaller, root]
  let n3Effect : SemanticProgramDataV1 := {
    n3EffectBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 ExternalCall EffectId before closure" .badCfg n3Effect
  expectCfgInvariantPhase "N3 ExternalCall EffectId generic phase wins"
    .cfg .badCfg n3Effect
  let badCalleeCaller : CallableV1 := {
    caller with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.externalCall 0 shortCallee #[]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3CalleeBase ← programWithTypes "InvClosureCallN3Callee" cfgBoolTypes #[]
    #[badCalleeCaller, root]
  let n3Callee : SemanticProgramDataV1 := {
    n3CalleeBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 ExternalCall callee before closure" .badCfg n3Callee
  expectCfgInvariantPhase "N3 ExternalCall callee generic phase wins"
    .cfg .badCfg n3Callee
  let badSsaCaller : CallableV1 := {
    caller with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.externalCall 0 callee #[99]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3SsaBase ← programWithTypes "InvClosureCallN3Ssa" cfgBoolTypes #[]
    #[badSsaCaller, root]
  let n3Ssa : SemanticProgramDataV1 := {
    n3SsaBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 ExternalCall SSA before closure" .badCfg n3Ssa
  expectCfgInvariantPhase "N3 ExternalCall SSA generic phase wins"
    .cfg .badCfg n3Ssa
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[caller,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn ExternalCall before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 ExternalCall closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-external-call"] }
  }
  expectCfgErrCode "N5 pureFn ExternalCall before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 ExternalCall closure before requirements"
    .invariantClosure .badCfg n5

/-- SPEC §8 forbids asynchronous scheduling in pureFn callables that belong to
    an invariant closure. An unreachable pureFn remains outside this
    closure-only restriction. Generic void-result, EffectId, callee-shape, and
    SSA validation runs before the post-CFG closure gate; argument
    serializability remains deferred. -/
private def testInvariantClosurePureFnScheduleProhibited : IO Unit := do
  let callee ← match parseQualifiedName #["mod", "workflow"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let shortCallee ← match parseQualifiedName #["workflow"] with
    | .ok name => pure name
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let scheduler : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr none (.schedule 0 callee #[]),
        cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
      (.return_ (some 0))]) with
      id := 0
      name := some "scheduler"
      invariantSteps := some 4
  }
  let root : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 7
  }
  let literalRoot : CallableV1 := {
    root with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
      invariantSteps := some 3
  }
  let p1Base ← programWithTypes "InvClosureScheduleP1Unreachable" cfgBoolTypes #[]
    #[{ scheduler with invariantSteps := none }, literalRoot]
  let p1 : SemanticProgramDataV1 := {
    p1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgOk "P1 unreachable pureFn Schedule outside invariant closure" p1
  let n1Base ← programWithTypes "InvClosureScheduleN1Reachable" cfgBoolTypes #[]
    #[scheduler, root]
  let n1 : SemanticProgramDataV1 := {
    n1Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N1 reachable pureFn Schedule" n1
  expectCfgInvariantPhase "N1 pureFn Schedule closure phase"
    .invariantClosure .badCfg n1
  let middle : CallableV1 := {
    root with
      id := 1
      kind := .pureFn
      name := some "middle"
      invariantSteps := some 7
  }
  let transitiveRoot : CallableV1 := {
    root with
      id := 2
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.pureCall 1 #[])]
        (.return_ (some 0))]
      invariantSteps := some 10
  }
  let n2Base ← programWithTypes "InvClosureScheduleN2Transitive" cfgBoolTypes #[]
    #[scheduler, middle, transitiveRoot]
  let n2 : SemanticProgramDataV1 := {
    n2Base with invariants := #[{ id := 0, name := "safe", callableId := 2 }]
  }
  expectCfgErr "N2 transitive closure pureFn Schedule" n2
  expectCfgInvariantPhase "N2 transitive Schedule closure phase"
    .invariantClosure .badCfg n2
  let badResultScheduler : CallableV1 := {
    scheduler with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (.schedule 0 callee #[]),
          cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
        (.return_ (some 1))]
  }
  let n3ResultBase ← programWithTypes "InvClosureScheduleN3Result" cfgBoolTypes #[]
    #[badResultScheduler, root]
  let n3Result : SemanticProgramDataV1 := {
    n3ResultBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Schedule result before closure" .badCfg n3Result
  expectCfgInvariantPhase "N3 Schedule result generic phase wins"
    .cfg .badCfg n3Result
  let badEffectScheduler : CallableV1 := {
    scheduler with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.schedule 1 callee #[]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3EffectBase ← programWithTypes "InvClosureScheduleN3Effect" cfgBoolTypes #[]
    #[badEffectScheduler, root]
  let n3Effect : SemanticProgramDataV1 := {
    n3EffectBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Schedule EffectId before closure" .badCfg n3Effect
  expectCfgInvariantPhase "N3 Schedule EffectId generic phase wins"
    .cfg .badCfg n3Effect
  let badCalleeScheduler : CallableV1 := {
    scheduler with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.schedule 0 shortCallee #[]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3CalleeBase ← programWithTypes "InvClosureScheduleN3Callee" cfgBoolTypes #[]
    #[badCalleeScheduler, root]
  let n3Callee : SemanticProgramDataV1 := {
    n3CalleeBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Schedule callee before closure" .badCfg n3Callee
  expectCfgInvariantPhase "N3 Schedule callee generic phase wins"
    .cfg .badCfg n3Callee
  let badSsaScheduler : CallableV1 := {
    scheduler with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr none (.schedule 0 callee #[99]),
          cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
        (.return_ (some 0))]
  }
  let n3SsaBase ← programWithTypes "InvClosureScheduleN3Ssa" cfgBoolTypes #[]
    #[badSsaScheduler, root]
  let n3Ssa : SemanticProgramDataV1 := {
    n3SsaBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Schedule SSA before closure" .badCfg n3Ssa
  expectCfgInvariantPhase "N3 Schedule SSA generic phase wins"
    .cfg .badCfg n3Ssa
  let badDominanceScheduler : CallableV1 := {
    scheduler with
      blocks := #[
        cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
          (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
        cfgBlockInstrs 1
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
          (.return_ (some 1)),
        cfgBlockInstrs 2
          #[cfgInstr none (.schedule 0 callee #[1]),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1)]
          (.return_ (some 2))]
  }
  let n3DomBase ← programWithTypes "InvClosureScheduleN3Dominance" cfgBoolTypes #[]
    #[badDominanceScheduler, root]
  let n3Dom : SemanticProgramDataV1 := {
    n3DomBase with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErrCode "N3 Schedule dominance before closure" .badCfg n3Dom
  expectCfgInvariantPhase "N3 Schedule dominance generic phase wins"
    .cfg .badCfg n3Dom
  let n4 : SemanticProgramDataV1 := {
    n1 with callables := #[scheduler,
      { root with invariantSteps := some (maxInvariantStepsV1 + 1) }]
  }
  expectCfgErrCode "N4 pureFn Schedule before intrinsic fuel" .badCfg n4
  expectCfgInvariantPhase "N4 Schedule closure phase wins"
    .invariantClosure .badCfg n4
  let n5 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-schedule"] }
  }
  expectCfgErrCode "N5 pureFn Schedule before requirements" .badCfg n5
  expectCfgInvariantPhase "N5 Schedule closure before requirements"
    .invariantClosure .badCfg n5

/-- A second pureFn callable (id 1) with one UInt8 param and UInt8 result,
    for pureCall tests. -/
private def cfgPureFn1 : CallableV1 :=
  {
    id := 1
    kind := .pureFn
    name := some "g"
    params := #[{ valueId := 0, name := "x", typeId := 3,
                  visibility := .public_ }]
    result := { typeId := 3, visibility := .public_ }
    entryBlock := 0
    blocks := #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1)]
      (.return_ (some 1))]
    loopBounds := #[]
    invariantSteps := none
  }

/-- An entry callable (id 0, kind .entry) for the pureCall non-pureFn
    negative. Empty body, return none. -/
private def cfgEntry0 : CallableV1 :=
  {
    id := 0
    kind := .entry
    name := some "e"
    params := #[]
    result := { typeId := 2, visibility := .public_ }
    entryBlock := 0
    blocks := #[cfgBlock 0 (.return_ none)]
    loopBounds := #[]
    invariantSteps := none
  }

private def testCfgOpTyping : IO Unit := do
  -- P1: literal result.typeId == op.typeId (UInt8 literal → result UInt8).
  let p1 ← programWithTypes "OpP1Lit" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7)]
          (.return_ (some 0))
      ] 3]
  expectCfgOk "P1 literal result==typeId" p1
  -- P2: constant load — result.typeId == data.constants[constantId].typeId.
  --   constantId 0 has typeId 3 (UInt8); result ValueDef typeId 3.
  let p2 ← programWithTypes "OpP2Const" cfgOpTypes
    #[constOf 0 "c" 3 (ByteArray.mk #[3])]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (.constant 0)]
          (.return_ (some 0))
      ] 3]
  expectCfgOk "P2 constant load result==constant.typeId" p2
  -- P3: stateLoad — result.typeId == data.logicalState[stateId].typeId.
  --   stateId 0 has typeId 3 (UInt8); result ValueDef typeId 3.
  let p3 ← programWithState "OpP3State" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (.stateLoad 0)]
          (.return_ (some 0))
      ] 3]
  expectCfgOk "P3 stateLoad result==state.typeId" p3
  -- P4: construct Struct — constructorIndex 0, 2 UInt8 args, result==0.
  --   Args are ValueIds 1 and 2 defined as UInt8 literals; result ValueId 3
  --   has typeId 0 (the struct type). Operands 1/2 are UInt8 (typeId 3).
  let p4 ← programWithTypes "OpP4ConstructStruct" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]) ]
          (.return_ (some 2))
      ] 0]
  expectCfgOk "P4 construct Struct 2 UInt8 args result==struct" p4
  -- P5: fieldGet Struct — base is a constructed Struct at ValueId 1 (typeId 0);
  --   fieldGet 1 1 → result ValueId 2 typeId 3 (fields[1].typeId == UInt8).
  let p5 ← programWithTypes "OpP5FieldGet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (.fieldGet 2 1) ]
          (.return_ (some 3))
      ] 3]
  expectCfgOk "P5 fieldGet Struct fieldIndex 1 result==field.typeId" p5
  -- P6: indexGet Array — base Array<UInt8,2>, index UInt32, result==element.
  --   Dedicated anonymous type table: typeId 0 Bool, 1 UInt8, 2 UInt32,
  --   3 Array<UInt8, length 2>, 4 Option<UInt8>.
  let arrTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 8 },
      { id := 2, name := none, shape := .uint 32 },
      { id := 3, name := none, shape := .array 1 2 },
      { id := 4, name := none, shape := .option 1 }]
  -- construct Array<UInt8,2> from two UInt8 ValueIds (10,11); indexGet with
  --   UInt32 index (ValueId 2, typeId 2); result ValueId 3 typeId 1 (UInt8).
  let p6 ← programWithTypes "OpP6IndexGetArray" arrTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 3 })
               (.construct 3 0 #[0, 1]),
             cfgInstr (some (cfgUInt32ValueDef 3)) (cfgUInt32Lit 1),
             cfgInstr (some (cfgUint8ValueDef 4)) (.indexGet 2 3) ]
          (.return_ (some 4))
      ] 1]
  expectCfgOk "P6 indexGet Array UInt32 index result==element" p6
  -- P7: unary not Bool → result Bool. Operand ValueId 1 (Bool, typeId 2);
  --   result ValueId 2 typeId 2 (Bool).
  let p7 ← programWithTypes "OpP7UnaryNot" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgOpBoolDef 1)) (.unary .not 0) ]
          (.return_ (some 1))
      ] 2]
  expectCfgOk "P7 unary not Bool→Bool" p7
  -- P8: binary add UInt8+UInt8 → UInt8. Operands ValueId 1,2 (UInt8);
  --   result ValueId 3 typeId 3 (UInt8).
  let p8 ← programWithTypes "OpP8BinaryAdd" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some (cfgOpU8Def 2)) (.binary .add 0 1) ]
          (.return_ (some 2))
      ] 3]
  expectCfgOk "P8 binary add UInt8+UInt8→UInt8" p8
  -- P9: pureCall — callee pureFn (id 1), arg type matches param (UInt8),
  --   result==callee.result.typeId (UInt8). Callable 0 calls Callable 1.
  let p9 ← programWithTypes "OpP9PureCall" cfgOpTypes #[]
    #[ cfgOpCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 5),
                 cfgInstr (some (cfgOpU8Def 1)) (.pureCall 1 #[0]) ]
              (.return_ (some 1))
          ] 3,
      cfgPureFn1 ]
  expectCfgOk "P9 pureCall pureFn arg matches result==callee.result" p9
  -- NEGATIVES (all .badCfg via structure+encode).
  -- N1: construct Struct wrong arg count (1 arg, expects 2).
  let n1 ← programWithTypes "OpN1ConstructArgCount" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 0 })
               (.construct 0 0 #[0]) ]
          (.return_ (some 1))
      ] 0]
  expectCfgErr "N1 construct wrong arg count" n1
  -- N2: construct Struct arg type mismatch (arg is Bool, field expects UInt8).
  let n2 ← programWithTypes "OpN2ConstructArgType" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]) ]
          (.return_ (some 2))
      ] 0]
  expectCfgErr "N2 construct arg type mismatch" n2
  -- N3: fieldGet on non-struct base (base type UInt8, typeId 3).
  let n3 ← programWithTypes "OpN3FieldGetNonStruct" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (.fieldGet 0 0) ]
          (.return_ (some 1))
      ] 3]
  expectCfgErr "N3 fieldGet on non-struct base" n3
  -- N4: fieldGet fieldIndex OOR (base Struct with 2 fields, fieldIndex 5).
  let n4 ← programWithTypes "OpN4FieldGetOOR" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (.fieldGet 2 5) ]
          (.return_ (some 3))
      ] 3]
  expectCfgErr "N4 fieldGet fieldIndex OOR" n4
  -- N5: indexGet Array wrong index type (UInt8 not UInt32).
  let n5 ← programWithTypes "OpN5IndexGetArrayIdxType" arrTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 3 })
               (.construct 3 0 #[0, 1]),
             cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 4)) (.indexGet 2 3) ]
          (.return_ (some 4))
      ] 1]
  expectCfgErr "N5 indexGet Array wrong index type" n5
  -- N6: indexGet Map result not Option<value>. Map<UInt8,UInt8> at typeId 6;
  --   base ValueId 1 typeId 6 (Map) built via construct empty Map
  --   (constructorIndex 0, args #[]); index ValueId 2 (UInt8, typeId 3);
  --   result ValueId 3 declared typeId 3 (UInt8) but the contract requires
  --   the unique Option<value> TypeId (typeId 5 in cfgOpTypes). The declared
  --   result.typeId mismatch → .badCfg.
  let n6 ← programWithTypes "OpN6IndexGetMapResult" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 0, typeId := 6 })
               (.construct 6 0 #[]),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
            cfgInstr (some (cfgOpU8Def 2)) (.indexGet 0 1) ]
          (.return_ (some 2))
      ] 3]
  expectCfgErr "N6 indexGet Map result not Option<value>" n6
  -- N7: unary neg on UInt8 (neg requires Int or Field).
  let n7 ← programWithTypes "OpN7UnaryNegUInt8" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (.unary .neg 0) ]
          (.return_ (some 1))
      ] 3]
  expectCfgErr "N7 unary neg on UInt8" n7
  -- N8: binary add operand type mismatch (lhs UInt8, rhs Bool).
  let n8 ← programWithTypes "OpN8BinaryAddMismatch" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgOpU8Def 2)) (.binary .add 0 1) ]
          (.return_ (some 2))
      ] 3]
  expectCfgErr "N8 binary add operand type mismatch" n8
  -- N9: binary eq result not Bool (declared result.typeId 3 = UInt8, must be Bool).
  let n9 ← programWithTypes "OpN9BinaryEqResult" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some (cfgOpU8Def 2)) (.binary .eq 0 1) ]
          (.return_ (some 2))
      ] 3]
  expectCfgErr "N9 binary eq result not Bool" n9
  -- N10: binary shift rhs not UInt32 (rhs is UInt8, typeId 3; shl rhs must be UInt32).
  let n10 ← programWithTypes "OpN10BinaryShiftRhs" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 2)) (.binary .shl 0 1) ]
          (.return_ (some 2))
      ] 3]
  expectCfgErr "N10 binary shift rhs not UInt32" n10
  -- N11: pureCall non-pureFn callee (callee id 0 is .entry).
  --   Two callables: id 0 entry (callee), id 1 pureFn that calls id 0.
  let n11 ← programWithTypes "OpN11PureCallNonPure" cfgOpTypes #[]
    #[ cfgEntry0,
      { cfgOpCallableResult
        #[ cfgBlockInstrs 0
            #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 5),
               cfgInstr (some (cfgOpU8Def 1)) (.pureCall 0 #[0]) ]
            (.return_ (some 1))
        ] 3 with id := 1 } ]
  expectCfgErr "N11 pureCall non-pureFn callee" n11
  -- N12: pureCall arg type mismatch (callee param UInt8, arg is Bool).
  let n12 ← programWithTypes "OpN12PureCallArgType" cfgOpTypes #[]
    #[ cfgOpCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
                 cfgInstr (some (cfgOpU8Def 1)) (.pureCall 1 #[0]) ]
              (.return_ (some 1))
          ] 3,
      cfgPureFn1 ]
  expectCfgErr "N12 pureCall arg type mismatch" n12

/-! ### step j extension: void-op result-presence (SPEC-SEM-WIRE-001 §5.1)

    The five genuinely-void ops (`StateStore`/`Assert`/`Emit`/`ExternalCall`/
    `Schedule`) MUST carry `result := none`; a spurious `result := some _` is
    an invalid Core trap → `.badCfg`. This suite isolates result presence;
    its StateStore, Assert, and Emit fixtures also satisfy their later exact
    state/error/event declaration and operand contracts. EffectId numbering
    and call argument typing remain out of scope here, and spurious results
    fail before those deferred joins. Uses the same 8-type `cfgOpTypes` fixture. -/

-- A qualified name with ≥2 components for externalCall/schedule callees.
private def cfgCalleeName : IO QualifiedName := do
  match parseQualifiedName #["mod", "callee"] with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"

-- Common QualifiedName accepts one component; ExternalCall/Schedule impose a
-- stricter SemanticProgramV1 structure rule requiring at least two.
private def cfgSingleComponentCalleeName : IO QualifiedName := do
  match parseQualifiedName #["callee"] with
  | .ok n => pure n
  | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"

-- A fresh spurious-result ValueDef at `valueId` with typeId 3 (UInt8, in
-- `cfgOpTypes` range) — registered as a def site by `collectValueTypeDefs`
-- (step h range ok), not used anywhere (use-existence only requires
-- uses→defs), so the ONLY step-j failure is the void-op result-presence.
private def cfgSpuriousVoidResult (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 3 }

private def testCfgVoidOpResultPresence : IO Unit := do
  let calleeName ← cfgCalleeName
  -- POSITIVES (result := none on the void op; expectCfgOk).
  -- P1: StateStore — ValueId 0 (UInt8 lit) exactly matches state type;
  --   state row present (stateId 0). result none, return none.
  let p1 ← programWithState "VoidP1StateStore" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
             cfgInstr none (.stateStore 0 0) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P1 stateStore result none" p1
  -- P2: Assert — condition ValueId 0 (Bool lit), assert_ 0 none #[] result none.
  let p2 ← programWithTypes "VoidP2Assert" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.assert_ 0 none #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P2 assert result none" p2
  -- P3: Emit — exact empty EventDecl, result none.
  let p3 ← programWithEvents "VoidP3Emit" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.emit 0 0 #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P3 emit result none" p3
  -- P4: ExternalCall — externalCall 0 calleeName #[] result none.
  let p4 ← programWithTypes "VoidP4ExternalCall" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.externalCall 0 calleeName #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P4 externalCall result none" p4
  -- P5: Schedule — schedule 0 calleeName #[] result none.
  let p5 ← programWithTypes "VoidP5Schedule" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.schedule 0 calleeName #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P5 schedule result none" p5
  -- NEGATIVES (spurious result := some _ on the void op; expectCfgErr .badCfg,
  --   dual path structure+encode). The spurious result ValueDef uses a fresh
  --   ValueId 5 (not used elsewhere) with typeId 3 (UInt8, in range) so
  --   steps a–i all pass and ONLY step j void-op result-presence fails.
  -- N1: StateStore with spurious result some.
  let n1 ← programWithState "VoidN1StateStore" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
             cfgInstr (some (cfgSpuriousVoidResult 5)) (.stateStore 0 0) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N1 stateStore spurious result" n1
  -- N2: Assert with spurious result some.
  let n2 ← programWithTypes "VoidN2Assert" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5)) (.assert_ 0 none #[]) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N2 assert spurious result" n2
  -- N3: Emit with valid empty EventDecl and spurious result some.
  let n3 ← programWithEvents "VoidN3Emit" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5)) (.emit 0 0 #[]) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N3 emit spurious result" n3
  -- N4: ExternalCall with spurious result some.
  let n4 ← programWithTypes "VoidN4ExternalCall" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5))
               (.externalCall 0 calleeName #[]) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N4 externalCall spurious result" n4
  -- N5: Schedule with spurious result some.
  let n5 ← programWithTypes "VoidN5Schedule" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5))
               (.schedule 0 calleeName #[]) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N5 schedule spurious result" n5

/-! ### step j extension: value-producing result presence (SPEC-SEM-WIRE-001
    §4.3/§5.1)

    Every value-producing op MUST carry `Instruction.result = some _`. The
    typed families (Literal/Constant/StateLoad/Construct/FieldGet/IndexGet/
    Unary/Binary/PureCall) already required an exact result TypeId; this
    slice additionally makes a missing result `.badCfg` (previously silently
    ignored). Seven families (FieldSet/VariantTag/VariantPayload/IndexSet/
    CheckedCast/ContextRead/Commit) originally entered through presence-only
    validation; later focused suites now enforce exact contracts for the first
    five. `Op.ContextRead` retains a presence-only local op branch but now
    carries the §5.1 same-key result-TypeId global consistency pass (a
    separate post-CFG suite); `Op.Commit` now requires operand/result TypeId
    equality plus its exact later requirement row. The fixtures here use
    operands/results valid under the current contracts so they continue to
    isolate missing-result behavior. The void rule remains unchanged. -/

private def testCfgValueOpResultPresence : IO Unit := do
  let calleeName ← cfgCalleeName
  -- POSITIVES (result := some _ on each value-producing op; expectCfgOk,
  --   structure+encode dual path). Families with later exact contracts use
  --   operands and result TypeIds valid under those contracts; ContextRead
  --   has a presence-only local op branch plus the §5.1 same-key result-TypeId
  --   global consistency pass, and Commit uses an exact matching result. Operands are
  --   otherwise defined so that
  --   steps a–i (use-existence, def-site range, dominance, terminator
  --   typing) all pass and this suite isolates result presence.
  -- P1: Literal with result present (typed family — exact typeId already
  --   covered by testCfgOpTyping P1; here re-pinned for the presence slice).
  let p1 ← programWithTypes "PresP1Lit" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7)]
          (.return_ (some 0))
      ] 3]
  expectCfgOk "P1 literal result present" p1
  -- P2: Constant with result present.
  let p2 ← programWithTypes "PresP2Const" cfgOpTypes
    #[constOf 0 "c" 3 (ByteArray.mk #[3])]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (.constant 0)]
          (.return_ (some 0))
      ] 3]
  expectCfgOk "P2 constant result present" p2
  -- P3: StateLoad with result present.
  let p3 ← programWithState "PresP3State" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (.stateLoad 0)]
          (.return_ (some 0))
      ] 3]
  expectCfgOk "P3 stateLoad result present" p3
  -- P4: Construct (Struct) with result present.
  let p4 ← programWithTypes "PresP4Construct" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]) ]
          (.return_ (some 2))
      ] 0]
  expectCfgOk "P4 construct result present" p4
  -- P5: FieldGet with result present.
  let p5 ← programWithTypes "PresP5FieldGet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (.fieldGet 2 1) ]
          (.return_ (some 3))
      ] 3]
  expectCfgOk "P5 fieldGet result present" p5
  -- P6: IndexGet (Array) with result present.
  let arrTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 8 },
      { id := 2, name := none, shape := .uint 32 },
      { id := 3, name := none, shape := .array 1 2 },
      { id := 4, name := none, shape := .option 1 }]
  let p6 ← programWithTypes "PresP6IndexGet" arrTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 3 })
               (.construct 3 0 #[0, 1]),
             cfgInstr (some (cfgUInt32ValueDef 3)) (cfgUInt32Lit 1),
             cfgInstr (some (cfgUint8ValueDef 4)) (.indexGet 2 3) ]
          (.return_ (some 4))
      ] 1]
  expectCfgOk "P6 indexGet result present" p6
  -- P7: Unary (not Bool) with result present.
  let p7 ← programWithTypes "PresP7Unary" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr (some (cfgOpBoolDef 1)) (.unary .not 0) ]
          (.return_ (some 1))
      ] 2]
  expectCfgOk "P7 unary result present" p7
  -- P8: Binary (add UInt8) with result present.
  let p8 ← programWithTypes "PresP8Binary" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some (cfgOpU8Def 2)) (.binary .add 0 1) ]
          (.return_ (some 2))
      ] 3]
  expectCfgOk "P8 binary result present" p8
  -- P9: PureCall with result present.
  let p9 ← programWithTypes "PresP9PureCall" cfgOpTypes #[]
    #[ cfgOpCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 5),
                 cfgInstr (some (cfgOpU8Def 1)) (.pureCall 1 #[0]) ]
              (.return_ (some 1))
          ] 3,
      cfgPureFn1 ]
  expectCfgOk "P9 pureCall result present" p9
  -- P10: FieldSet (deferred family) with result present. base/value are
  --   defined UInt8 literals; result ValueId 3 typeId 0 (Struct, in range).
  --   Input typing is NOT checked this slice.
  --   NOTE: FieldSet now carries the full §5.1 contract (base must be a
  --   Struct, fieldIndex in range, type(value) == field.typeId, result.typeId
  --   == type(base)). P10 here re-pins presence with a valid Struct base so
  --   the full FieldSet typing test lives in testCfgFieldSetTyping.
  let p10 ← programWithTypes "PresP10FieldSet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 9),
             cfgInstr (some { valueId := 4, typeId := 0 })
               (.fieldSet 2 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P10 fieldSet result present" p10
  -- P11: VariantTag with result present. NOTE: VariantTag now carries the
  --   full §5.1 contract (base must be Enum/Option, result.typeId == unique
  --   UInt32 TypeId). P11 here re-pins presence with a valid Enum base so
  --   the full VariantTag typing test lives in testCfgVariantTagTyping.
  let p11 ← programWithTypes "PresP11VariantTag" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 1 })
               (.construct 1 0 #[0]),
             cfgInstr (some (cfgOpU32Def 2)) (.variantTag 1) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P11 variantTag result present" p11
  -- P12: VariantPayload result present with a valid Option-some base.
  let p12 ← programWithTypes "PresP12VariantPayload" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 1 #[0]),
             cfgInstr (some (cfgOpU8Def 2))
               (.variantPayload 1 1 0) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P12 variantPayload result present" p12
  -- P13: IndexSet result present with a valid Map<U8,U8> base and exact
  --   key/value types, so the exact static contract also passes.
  let p13 ← programWithTypes "PresP13IndexSet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 0, typeId := 6 })
               (.construct 6 0 #[]),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 3, typeId := 6 })
               (.indexSet 0 1 2) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P13 indexSet result present" p13
  -- P14: CheckedCast with a valid UInt8→UInt8 exact contract and result.
  let p14 ← programWithTypes "PresP14CheckedCast" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (.checkedCast 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P14 checkedCast result present" p14
  -- P15: catalog-bound ContextRead with its exact UInt64 result present.
  let ctxKey := unixTimeSecondsContextKeyV1
  let ctxTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 64 }]
  let ctxReq := #[← exactContextRequirementRowV1]
  let commitReq := #[← exactCommitRequirementRowV1]
  let p15 ← programWithTypes "PresP15ContextRead" ctxTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 0, typeId := 1 }) (.contextRead ctxKey) ]
          (.return_ none)
      ] 0] ctxReq
  expectCfgOk "P15 contextRead result present" p15
  -- P16: Commit with an operand-matching result present.
  let p16 ← programWithTypes "PresP16Commit" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (.commit 0) ]
          (.return_ none)
      ] 2] commitReq
  expectCfgOk "P16 commit result present" p16
  -- NEGATIVES (result := none on each value-producing op; expectCfgErr
  --   .badCfg, structure+encode dual path). Each op's ValueId operands are
  --   defined by a preceding literal-with-result instruction so that steps
  --   a–i all pass and ONLY step j result-presence fails. The terminator
  --   returns none (or a separately-defined ValueId) so terminator typing
  --   and use-existence are unaffected by the missing result.
  -- N1: Literal with result none.
  let n1 ← programWithTypes "PresN1Lit" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr none (cfgOpU8Lit 7)]
          (.return_ none)
      ] 2]
  expectCfgErr "N1 literal result none" n1
  -- N2: Constant with result none.
  let n2 ← programWithTypes "PresN2Const" cfgOpTypes
    #[constOf 0 "c" 3 (ByteArray.mk #[3])]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr none (.constant 0)]
          (.return_ none)
      ] 2]
  expectCfgErr "N2 constant result none" n2
  -- N3: StateLoad with result none.
  let n3 ← programWithState "PresN3State" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr none (.stateLoad 0)]
          (.return_ none)
      ] 2]
  expectCfgErr "N3 stateLoad result none" n3
  -- N4: Construct with result none (operands defined first).
  let n4 ← programWithTypes "PresN4Construct" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr none (.construct 0 0 #[0, 1]) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N4 construct result none" n4
  -- N5: FieldGet with result none (base defined first).
  let n5 ← programWithTypes "PresN5FieldGet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr none (.fieldGet 2 1) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N5 fieldGet result none" n5
  -- N6: IndexGet with result none (base + index defined first).
  let n6 ← programWithTypes "PresN6IndexGet" arrTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 3 })
               (.construct 3 0 #[0, 1]),
             cfgInstr (some (cfgUInt32ValueDef 3)) (cfgUInt32Lit 1),
             cfgInstr none (.indexGet 2 3) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N6 indexGet result none" n6
  -- N7: Unary with result none (operand defined first).
  let n7 ← programWithTypes "PresN7Unary" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.unary .not 0) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N7 unary result none" n7
  -- N8: Binary with result none (operands defined first).
  let n8 ← programWithTypes "PresN8Binary" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr none (.binary .add 0 1) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N8 binary result none" n8
  -- N9: PureCall with result none (arg defined first).
  let n9 ← programWithTypes "PresN9PureCall" cfgOpTypes #[]
    #[ cfgOpCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 5),
                 cfgInstr none (.pureCall 1 #[0]) ]
              (.return_ none)
          ] 2,
      cfgPureFn1 ]
  expectCfgErr "N9 pureCall result none" n9
  -- N10: FieldSet with result none (presence gate). Uses a valid Struct
  --   base (ValueId 2, typeId 0) and a valid value (UInt8, field 0 type) so
  --   steps a–i and the FieldSet typing preconditions all pass and only the
  --   missing result fails.
  let n10 ← programWithTypes "PresN10FieldSet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 9),
             cfgInstr none (.fieldSet 2 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N10 fieldSet result none" n10
  -- N11: VariantTag with result none. NOTE: VariantTag now carries the full
  --   §5.1 contract; N11 uses a valid Enum base (ValueId 1, typeId 1) so
  --   steps a–i and the VariantTag typing preconditions all pass and only
  --   the missing result fails.
  let n11 ← programWithTypes "PresN11VariantTag" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 1 })
               (.construct 1 0 #[0]),
             cfgInstr none (.variantTag 1) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N11 variantTag result none" n11
  -- N12: VariantPayload with a valid Option-some base but result none, so
  --   only the result-presence gate fails.
  let n12 ← programWithTypes "PresN12VariantPayload" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 1 #[0]),
             cfgInstr none (.variantPayload 1 1 0) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N12 variantPayload result none" n12
  -- N13: valid Map<U8,U8> IndexSet with result none, so only the presence
  --   requirement fails.
  let n13 ← programWithTypes "PresN13IndexSet" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 0, typeId := 6 })
               (.construct 6 0 #[]),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 2),
             cfgInstr none (.indexSet 0 1 2) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N13 indexSet result none" n13
  -- N14: CheckedCast with result none.
  let n14 ← programWithTypes "PresN14CheckedCast" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr none (.checkedCast 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N14 checkedCast result none" n14
  -- N15: ContextRead with result none.
  let n15 ← programWithTypes "PresN15ContextRead" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr none (.contextRead ctxKey) ]
          (.return_ none)
      ] 2] ctxReq
  expectCfgErr "N15 contextRead result none" n15
  -- N16: Commit with result none.
  let n16 ← programWithTypes "PresN16Commit" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr none (.commit 0) ]
          (.return_ none)
      ] 2] commitReq
  expectCfgErr "N16 commit result none" n16
  -- REGRESSION: the void rule is unchanged — every void family with
  --   result := none remains accepted. (P1–P5 of testCfgVoidOpResultPresence
  --   already pin StateStore/Assert/Emit/ExternalCall/Schedule result none
  --   as expectCfgOk; re-asserted here so the presence slice does not
  --   silently regress the void rule.)
  let r1 ← programWithState "PresRegStateStore" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
             cfgInstr none (.stateStore 0 0) ]
          (.return_ none)
      ] 2]
  expectCfgOk "Reg stateStore result none still accepted" r1
  let r2 ← programWithTypes "PresRegAssert" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.assert_ 0 none #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "Reg assert result none still accepted" r2
  let r3 ← programWithEvents "PresRegEmit" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.emit 0 0 #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "Reg emit result none still accepted" r3
  let r4 ← programWithTypes "PresRegExternalCall" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.externalCall 0 calleeName #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "Reg externalCall result none still accepted" r4
  let r5 ← programWithTypes "PresRegSchedule" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
             cfgInstr none (.schedule 0 calleeName #[]) ]
          (.return_ none)
      ] 2]
  expectCfgOk "Reg schedule result none still accepted" r5

/-- testCfgFieldSetTyping: SPEC-SEM-WIRE-001 §5.1 Op.FieldSet exact contract.
    base ValueId type MUST resolve to a Struct; fieldIndex MUST be in range;
    type(value) MUST exactly equal fields[fieldIndex].typeId; `result` MUST be
    present and result.typeId MUST exactly equal type(base) (the whole struct
    type). All failures → `.badCfg` via structure+encode dual path. Each
    negative isolates FieldSet typing: operands are otherwise valid SSA /
    dominance definitions and earlier steps pass, so only step j FieldSet
    typing fails. Uses cfgOpTypes (typeId 4 = Struct{a:UInt8, b:UInt8}). -/
private def testCfgFieldSetTyping : IO Unit := do
  -- POSITIVES
  -- P1: FieldSet on first field (index 0). base is a constructed Struct
  --   ValueId 1 (typeId 4); value ValueId 2 (UInt8); result ValueId 3
  --   typeId 4 (== type(base)).
  let p1 ← programWithTypes "FSetP1FirstField" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 9),
             cfgInstr (some { valueId := 4, typeId := 0 })
               (.fieldSet 2 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P1 fieldSet first field result==struct" p1
  -- P2: FieldSet on a later field (index 1). value ValueId 2 (UInt8); result
  --   ValueId 3 typeId 4 (== type(base)).
  let p2 ← programWithTypes "FSetP2LaterField" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 7),
             cfgInstr (some { valueId := 4, typeId := 0 })
               (.fieldSet 2 1 3) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P2 fieldSet later field result==struct" p2
  -- NEGATIVES (all .badCfg via structure+encode dual path; operands are
  --   otherwise valid SSA/dominance definitions so each negative isolates
  --   FieldSet typing).
  -- N1: non-Struct base. base is a UInt8 literal (typeId 1), not a Struct.
  let n1 ← programWithTypes "FSetN1NonStructBase" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 9),
             cfgInstr (some { valueId := 2, typeId := 3 })
               (.fieldSet 0 0 1) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N1 fieldSet non-Struct base" n1
  -- N2: out-of-range fieldIndex. base Struct has 2 fields (indices 0,1);
  --   fieldIndex 2 is OOR. value is a valid UInt8; result typeId 4.
  let n2 ← programWithTypes "FSetN2OORFieldIndex" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 9),
             cfgInstr (some { valueId := 4, typeId := 0 })
               (.fieldSet 2 2 3) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N2 fieldSet out-of-range fieldIndex" n2
  -- N3: wrong value type. base Struct field 0 expects UInt8 (typeId 1) but
  --   value is Bool (typeId 0). result typeId 4 (== type(base)).
  let n3 ← programWithTypes "FSetN3WrongValueType" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpBoolDef 3)) (cfgOpBoolLit 1),
             cfgInstr (some { valueId := 4, typeId := 0 })
               (.fieldSet 2 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N3 fieldSet wrong value type" n3
  -- N4: wrong result type. base Struct (typeId 4), field 0 expects UInt8,
  --   value UInt8, but result.typeId is 1 (UInt8) instead of 4 (struct).
  let n4 ← programWithTypes "FSetN4WrongResultType" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
             cfgInstr (some { valueId := 2, typeId := 0 })
               (.construct 0 0 #[0, 1]),
             cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 9),
             cfgInstr (some { valueId := 4, typeId := 3 })
               (.fieldSet 2 0 3) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N4 fieldSet wrong result type" n4

/-- testCfgVariantTagTyping: SPEC-SEM-WIRE-001 §5.1 Op.VariantTag exact
    contract. base ValueId type MUST resolve to a Type.Enum or Type.Option;
    `Instruction.result` MUST be present and its typeId MUST exactly equal
    the unique UInt32 TypeId (resolved via the `uint32TypeId` helper). N1–N3
    isolate VariantTag typing and fail `.badCfg` via structure+encode after
    otherwise-valid SSA/dominance setup. N4 is intentionally different: its
    duplicate anonymous UInt32 shape is rejected earlier by the authoritative
    primitive TypeKey interning phase as `.nonCanonical`, before step j runs.
    Uses cfgOpTypes (typeId 2 = UInt32, typeId 3 = Option<UInt8>, typeId 5 =
    Enum{v(UInt8)}); N4 uses a custom 5-type duplicate table. -/
private def testCfgVariantTagTyping : IO Unit := do
  -- POSITIVES
  -- P1: VariantTag on an Enum base. Construct Enum (typeId 5) variant 0
  --   with a UInt8 payload (ValueId 10) → ValueId 1 (typeId 5); VariantTag
  --   1 → result ValueId 2 typeId 2 (the unique UInt32 TypeId).
  let p1 ← programWithTypes "VTagP1Enum" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 1 })
               (.construct 1 0 #[0]),
             cfgInstr (some (cfgOpU32Def 2)) (.variantTag 1) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P1 variantTag Enum base result==UInt32" p1
  -- P2: VariantTag on an Option-some base. Construct Option-some (typeId 3,
  --   ctorIdx 1) with a UInt8 (ValueId 10) → ValueId 1 (typeId 3);
  --   VariantTag 1 → result ValueId 2 typeId 2 (UInt32).
  let p2 ← programWithTypes "VTagP2OptionSome" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 1 #[0]),
             cfgInstr (some (cfgOpU32Def 2)) (.variantTag 1) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P2 variantTag Option-some base result==UInt32" p2
  -- P3: VariantTag on an Option-none base. Construct Option-none (typeId 3,
  --   ctorIdx 0, no args) → ValueId 1 (typeId 3); VariantTag 1 → result
  --   ValueId 2 typeId 2 (UInt32).
  let p3 ← programWithTypes "VTagP3OptionNone" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 0, typeId := 5 })
               (.construct 5 0 #[]),
             cfgInstr (some (cfgOpU32Def 1)) (.variantTag 0) ]
          (.return_ none)
      ] 2]
  expectCfgOk "P3 variantTag Option-none base result==UInt32" p3
  -- NEGATIVES (all .badCfg via structure+encode dual path; operands are
  --   otherwise valid SSA/dominance definitions so each negative isolates
  --   VariantTag typing).
  -- N1: non-Enum/Option base (primitive). base is a UInt8 literal
  --   (typeId 1), not Enum/Option; result typeId 2 (UInt32, in range).
  let n1 ← programWithTypes "VTagN1PrimitiveBase" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some (cfgOpU32Def 1)) (.variantTag 0) ]
          (.return_ none)
      ] 2]
  expectCfgErr "N1 variantTag non-Enum/Option base" n1
  -- N2: no UInt32 closure type. Custom type table without a UInt32 shape:
  --   typeId 0 = Bool, 1 = UInt8, 2 = Enum{v(UInt8)} (no UInt32). Construct
  --   Enum (typeId 2) variant 0 with UInt8 → ValueId 1 (typeId 2);
  --   VariantTag 1 → result ValueId 2 typeId 0 (Bool, in range). The
  --   `uint32TypeId` helper returns none → `.badCfg`.
  let noU32Types : Array TypeDeclV1 :=
    #[{ id := 0, name := some "E",
         shape := .enum #[{ name := "v", payloadTypes := #[2] }] },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .uint 8 }]
  let n2 ← programWithTypes "VTagN2NoUInt32Type" noU32Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 0, typeId := 2 })
               (.literal 2 (ByteArray.mk #[1])),
             cfgInstr (some { valueId := 1, typeId := 0 })
               (.construct 0 0 #[0]),
             cfgInstr (some { valueId := 2, typeId := 1 }) (.variantTag 1) ]
          (.return_ none)
      ] 1]
  expectCfgErr "N2 variantTag no UInt32 closure type" n2
  -- N3: wrong result type. base Enum (typeId 1), the unique UInt32 TypeId
  --   is typeId 4, but result.typeId is 3 (UInt8) instead of 4.
  let n3 ← programWithTypes "VTagN3WrongResultType" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 1 #[0]),
             cfgInstr (some (cfgOpU8Def 2)) (.variantTag 1) ]
          (.return_ none)
      ] 4]
  expectCfgErr "N3 variantTag wrong result type" n3
  -- N4: duplicate UInt32 anonymous shape. The authoritative primitive
  --   TypeKey interning phase now rejects this as `.nonCanonical` before the
  --   later VariantTag contract attempts to resolve the unique UInt32 TypeId.
  let dupU32Types : Array TypeDeclV1 :=
    #[{ id := 0, name := some "E",
         shape := .enum #[{ name := "v", payloadTypes := #[2] }] },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .uint 8 },
      { id := 3, name := none, shape := .uint 32 },
      { id := 4, name := none, shape := .uint 32 }]
  let n4 ← programWithTypes "VTagN4DupUInt32Type" dupU32Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 0 })
               (.construct 0 0 #[10]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 1]
  expectCfgErrCode "N4 variantTag duplicate UInt32 anonymous shape"
    .nonCanonical n4

/-- SPEC-SEM-WIRE-001 §5.1 `Op.VariantPayload` exact static contract.
    Enum bases require in-range variant/payload indices and return the selected
    payload type. Option bases permit only `(variantIndex=1,payloadIndex=0)` and
    return the element type. Every case drives the real structure gate and
    encoder through `expectCfgOk` / `expectCfgErr`. -/
private def testCfgVariantPayloadTyping : IO Unit := do
  -- P1: Enum variant 0 payload 0 is UInt8, so the result is UInt8.
  let p1 ← programWithTypes "VPayloadP1Enum" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 1 })
              (.construct 1 0 #[0]),
            cfgInstr (some (cfgOpU8Def 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 2]
  expectCfgOk "P1 variantPayload Enum payload result" p1
  -- P2: Option-some `(1,0)` returns the Option element UInt8.
  let p2 ← programWithTypes "VPayloadP2Option" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 5 })
              (.construct 5 1 #[0]),
            cfgInstr (some (cfgOpU8Def 2))
              (.variantPayload 1 1 0)]
          (.return_ none)] 2]
  expectCfgOk "P2 variantPayload Option-some result" p2
  -- N1: primitive base is neither Enum nor Option.
  let n1 ← programWithTypes "VPayloadN1Primitive" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU8Def 1))
              (.variantPayload 0 0 0)]
          (.return_ none)] 2]
  expectCfgErr "N1 variantPayload primitive base" n1
  -- N2: Enum variant index is out of range.
  let n2 ← programWithTypes "VPayloadN2VariantOor" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 1 })
              (.construct 1 0 #[0]),
            cfgInstr (some (cfgOpU8Def 2))
              (.variantPayload 1 1 0)]
          (.return_ none)] 2]
  expectCfgErr "N2 variantPayload Enum variant OOR" n2
  -- N3: Enum payload index is out of range.
  let n3 ← programWithTypes "VPayloadN3PayloadOor" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 1 })
              (.construct 1 0 #[0]),
            cfgInstr (some (cfgOpU8Def 2))
              (.variantPayload 1 0 1)]
          (.return_ none)] 2]
  expectCfgErr "N3 variantPayload Enum payload OOR" n3
  -- N4: Option-none variant 0 has no payload.
  let n4 ← programWithTypes "VPayloadN4OptionNone" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 5 })
              (.construct 5 0 #[]),
            cfgInstr (some (cfgOpU8Def 1))
              (.variantPayload 0 0 0)]
          (.return_ none)] 2]
  expectCfgErr "N4 variantPayload Option-none" n4
  -- N5: Option-some permits payload index 0 only.
  let n5 ← programWithTypes "VPayloadN5OptionPayloadOor" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 5 })
              (.construct 5 1 #[0]),
            cfgInstr (some (cfgOpU8Def 2))
              (.variantPayload 1 1 1)]
          (.return_ none)] 2]
  expectCfgErr "N5 variantPayload Option payload OOR" n5
  -- N6: selected Enum payload is UInt8 but result is Bool.
  let n6 ← programWithTypes "VPayloadN6WrongResult" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 1 })
              (.construct 1 0 #[0]),
            cfgInstr (some (cfgOpBoolDef 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 2]
  expectCfgErr "N6 variantPayload wrong result type" n6
  -- N7: an empty Enum variant has no payload index 0.
  let emptyVariantTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := some "E",
         shape := .enum #[{ name := "Empty", payloadTypes := #[] }] },
      { id := 1, name := none, shape := .bool },
      { id := 2, name := none, shape := .uint 8 }]
  let n7 ← programWithTypes "VPayloadN7EmptyVariant" emptyVariantTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 0 })
              (.construct 0 0 #[]),
            cfgInstr (some { valueId := 1, typeId := 2 })
              (.variantPayload 0 0 0)]
          (.return_ none)] 1]
  expectCfgErr "N7 variantPayload empty Enum variant" n7

/-- SPEC-SEM-WIRE-001 §5.1 `Op.IndexSet` static type/result contract for
    Array, Bytes, and Map. Runtime index bounds remain an interpreter concern;
    these fixtures drive the real structure+encode gate. -/
private def testCfgIndexSetTyping : IO Unit := do
  let indexSetTypes := cfgOpTypes.push
    { id := 8, name := none, shape := .array 3 2 }
  -- P1: Array<U8,2>, UInt32 index, UInt8 value, Array result.
  let p1 ← programWithTypes "ISetP1Array" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
            cfgInstr (some { valueId := 2, typeId := 8 })
              (.construct 8 0 #[0, 1]),
            cfgInstr (some (cfgOpU32Def 3)) (cfgOpU32Lit 0),
            cfgInstr (some (cfgOpU8Def 4)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 5, typeId := 8 })
              (.indexSet 2 3 4)]
          (.return_ none)] 2]
  expectCfgOk "P1 indexSet Array" p1
  -- P2: Bytes<4>, UInt32 index, UInt8 value, Bytes result.
  let p2 ← programWithTypes "ISetP2Bytes" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgOpU32Def 1)) (cfgOpU32Lit 0),
            cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 3, typeId := 7 })
              (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgOk "P2 indexSet Bytes" p2
  -- P3: Map<U8,U8>, exact key/value, Map result.
  let p3 ← programWithTypes "ISetP3Map" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 3, typeId := 6 })
              (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgOk "P3 indexSet Map" p3
  -- N1: primitive base is not index-settable.
  let n1 ← programWithTypes "ISetN1Primitive" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU32Def 1)) (cfgOpU32Lit 0),
            cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 9),
            cfgInstr (some (cfgOpU8Def 3)) (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgErr "N1 indexSet primitive base" n1
  -- N2: Array index must be UInt32, not Bool.
  let n2 ← programWithTypes "ISetN2ArrayIndex" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
            cfgInstr (some { valueId := 2, typeId := 8 })
              (.construct 8 0 #[0, 1]),
            cfgInstr (some (cfgOpBoolDef 3)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 4)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 5, typeId := 8 })
              (.indexSet 2 3 4)]
          (.return_ none)] 2]
  expectCfgErr "N2 indexSet Array wrong index" n2
  -- N3: Array value must equal element type.
  let n3 ← programWithTypes "ISetN3ArrayValue" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 2),
            cfgInstr (some { valueId := 2, typeId := 8 })
              (.construct 8 0 #[0, 1]),
            cfgInstr (some (cfgOpU32Def 3)) (cfgOpU32Lit 0),
            cfgInstr (some (cfgOpBoolDef 4)) (cfgOpBoolLit 1),
            cfgInstr (some { valueId := 5, typeId := 8 })
              (.indexSet 2 3 4)]
          (.return_ none)] 2]
  expectCfgErr "N3 indexSet Array wrong value" n3
  -- N4: Bytes index must be UInt32.
  let n4 ← programWithTypes "ISetN4BytesIndex" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 3, typeId := 7 })
              (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgErr "N4 indexSet Bytes wrong index" n4
  -- N5: Bytes value must be UInt8.
  let n5 ← programWithTypes "ISetN5BytesValue" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgOpU32Def 1)) (cfgOpU32Lit 0),
            cfgInstr (some (cfgOpBoolDef 2)) (cfgOpBoolLit 1),
            cfgInstr (some { valueId := 3, typeId := 7 })
              (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgErr "N5 indexSet Bytes wrong value" n5
  -- N6: Map index must match key type.
  let n6 ← programWithTypes "ISetN6MapKey" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 3, typeId := 6 })
              (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgErr "N6 indexSet Map wrong key" n6
  -- N7: Map value must match value type.
  let n7 ← programWithTypes "ISetN7MapValue" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpBoolDef 2)) (cfgOpBoolLit 1),
            cfgInstr (some { valueId := 3, typeId := 6 })
              (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgErr "N7 indexSet Map wrong value" n7
  -- N8: result type must equal base type.
  let n8 ← programWithTypes "ISetN8WrongResult" indexSetTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 1),
            cfgInstr (some (cfgOpU8Def 2)) (cfgOpU8Lit 9),
            cfgInstr (some (cfgOpU8Def 3)) (.indexSet 0 1 2)]
          (.return_ none)] 2]
  expectCfgErr "N8 indexSet wrong result type" n8
  -- N9: duplicate anonymous UInt8 declarations are rejected by primitive
  --   TypeKey interning as `.nonCanonical` before the later Bytes IndexSet
  --   contract resolves its unique UInt8 result/value type.
  let dupU8Types := cfgOpTypes.push
    { id := 8, name := none, shape := .uint 8 }
  let n9 ← programWithTypes "ISetN9DuplicateUInt8" dupU8Types #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgOpU32Def 2)) (cfgOpU32Lit 0),
            cfgInstr (some (cfgOpU8Def 3)) (cfgOpU8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 7 })
              (.indexSet 1 2 3)]
          (.return_ none)] 2]
  expectCfgErrCode "N9 indexSet duplicate UInt8 anonymous shape"
    .nonCanonical n9

/-- SPEC-SEM-WIRE-001 §5.1 `Op.CheckedCast` static type/result contract.
    Both source and destination must be UInt/Int TypeIds, and the instruction
    result must exactly equal `toType`. Runtime representability remains a
    D2-07 interpreter concern; these fixtures drive the real structure+encode
    gate. -/
private def testCfgCheckedCastTyping : IO Unit := do
  let castTypes := (cfgOpTypes.push
    { id := 8, name := none, shape := .int 8 }).push
    { id := 9, name := none, shape := .int 32 }
  -- P1: UInt8 -> UInt32.
  let p1 ← programWithTypes "CastP1UIntUInt" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpU32Def 1)) (.checkedCast 0 4)]
          (.return_ none)] 2]
  expectCfgOk "P1 checkedCast UInt to UInt" p1
  -- P2: UInt32 -> Int8.
  let p2 ← programWithTypes "CastP2UIntInt" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU32Def 0)) (cfgOpU32Lit 7),
            cfgInstr (some { valueId := 1, typeId := 8 })
              (.checkedCast 0 8)]
          (.return_ none)] 2]
  expectCfgOk "P2 checkedCast UInt to Int" p2
  -- P3: Int8 -> UInt8.
  let p3 ← programWithTypes "CastP3IntUInt" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 8 })
              (.literal 8 (ByteArray.mk #[1])),
            cfgInstr (some (cfgOpU8Def 1)) (.checkedCast 0 3)]
          (.return_ none)] 2]
  expectCfgOk "P3 checkedCast Int to UInt" p3
  -- P4: Int8 -> Int32.
  let p4 ← programWithTypes "CastP4IntInt" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 8 })
              (.literal 8 (ByteArray.mk #[0xff])),
            cfgInstr (some { valueId := 1, typeId := 9 })
              (.checkedCast 0 9)]
          (.return_ none)] 2]
  expectCfgOk "P4 checkedCast Int to Int" p4
  -- N1: Bool is not a legal cast source.
  let n1 ← programWithTypes "CastN1BoolSource" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 1)) (.checkedCast 0 3)]
          (.return_ none)] 2]
  expectCfgErr "N1 checkedCast Bool source" n1
  -- N2: Bytes is not a legal cast source.
  let n2 ← programWithTypes "CastN2BytesSource" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 0, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgOpU8Def 1)) (.checkedCast 0 3)]
          (.return_ none)] 2]
  expectCfgErr "N2 checkedCast Bytes source" n2
  -- N3: Bool is not a legal cast destination.
  let n3 ← programWithTypes "CastN3BoolDestination" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpBoolDef 1)) (.checkedCast 0 2)]
          (.return_ none)] 2]
  expectCfgErr "N3 checkedCast Bool destination" n3
  -- N4: Bytes is not a legal cast destination.
  let n4 ← programWithTypes "CastN4BytesDestination" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some { valueId := 1, typeId := 7 })
              (.checkedCast 0 7)]
          (.return_ none)] 2]
  expectCfgErr "N4 checkedCast Bytes destination" n4
  -- N5: result.typeId must exactly equal toType.
  let n5 ← programWithTypes "CastN5WrongResult" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpU8Def 1)) (.checkedCast 0 4)]
          (.return_ none)] 2]
  expectCfgErr "N5 checkedCast wrong result type" n5
  -- N6: toType must resolve to an in-range UInt/Int declaration.
  let n6 ← programWithTypes "CastN6MissingDestination" castTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpU8Def 1)) (.checkedCast 0 99)]
          (.return_ none)] 2]
  expectCfgErr "N6 checkedCast missing destination type" n6

/-- SPEC-SEM-WIRE-001 §5.1 `Op.Commit` local static contract: the operand
    ValueId must resolve and the result TypeId must exactly equal type(value).
    Aggregate values with canonical encodings remain admissible; this gate
    deliberately does not reuse the narrower Eq/Ne serializability predicate.
    Exact disclosure.commitment requirement binding and Reference execution
    remain deferred. -/
private def testCfgCommitTyping : IO Unit := do
  let commitReq := #[← exactCommitRequirementRowV1]
  -- P1: primitive UInt8 operand/result exact match.
  let p1 ← programWithTypes "CommitP1UInt8" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpU8Def 1)) (.commit 0)]
          (.return_ (some 1))] 3] commitReq
  expectCfgOk "P1 Commit UInt8 exact result" p1
  -- P2: Option<UInt8> proves Commit does not inherit Eq/Ne's aggregate
  -- exclusion; result remains the exact aggregate TypeId.
  let p2 ← programWithTypes "CommitP2Option" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some { valueId := 1, typeId := 5 }) (.construct 5 1 #[0]),
            cfgInstr (some { valueId := 2, typeId := 5 }) (.commit 1)]
          (.return_ (some 2))] 5] commitReq
  expectCfgOk "P2 Commit canonical Option exact result" p2
  -- N1: wrong but in-range result TypeId.
  let n1 ← programWithTypes "CommitN1WrongResult" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpBoolDef 1)) (.commit 0)]
          (.return_ none)] 2] commitReq
  expectCfgErr "N1 Commit wrong result TypeId" n1
  -- N2: undefined operand remains a generic CFG failure.
  let n2 ← programWithTypes "CommitN2UndefinedOperand" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (.commit 99)]
          (.return_ none)] 2] commitReq
  expectCfgErr "N2 Commit undefined operand" n2
  expectCfgInvariantPhase "N2 Commit undefined operand cfg phase" .cfg .badCfg n2
  -- N3: local type failure precedes the later requirement structure phase.
  let n3 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-commit-type"] }
  }
  expectCfgErrCode "N3 Commit typing before requirements" .badCfg n3
  expectCfgInvariantPhase "N3 Commit typing is cfg phase" .cfg .badCfg n3
  -- N4: malformed Commit in an invariant root fails generic typing before
  -- the otherwise-authoritative invariant closure prohibition.
  let badInvariant : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
          cfgInstr (some (cfgOpBoolDef 1)) (.commit 0)]
        (.return_ (some 1))]
      invariantSteps := some 4
  }
  let n4Base ← programWithTypes "CommitN4InvariantTyping" cfgOpTypes #[]
    #[badInvariant] commitReq
  let n4 : SemanticProgramDataV1 := {
    n4Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErrCode "N4 Commit typing before invariant prohibition" .badCfg n4
  expectCfgInvariantPhase "N4 malformed Commit cfg phase" .cfg .badCfg n4
  -- N5: operand ValueId 1 exists and has the exact result TypeId, but its
  -- definition is confined to the sibling branch and does not dominate the
  -- Commit use in block 2. This isolates generic dominance before step j.
  let condParam : ParameterV1 := {
    valueId := 0, name := "cond", typeId := 2, visibility := .public_
  }
  let siblingCommit : CallableV1 := {
    (cfgOpCallableResult
      #[cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
        cfgBlockInstrs 1
          #[cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 7)]
          (.return_ none),
        cfgBlockInstrs 2
          #[cfgInstr (some (cfgOpU8Def 2)) (.commit 1)]
          (.return_ none)] 2) with
      params := #[condParam]
  }
  let n5 ← programWithTypes "CommitN5SiblingDominance" cfgOpTypes #[]
    #[siblingCommit] commitReq
  expectCfgErr "N5 Commit operand does not dominate sibling use" n5
  expectCfgInvariantPhase "N5 Commit dominance cfg phase" .cfg .badCfg n5

/-- SPEC-SEM-WIRE-001 §5.1 `Op.StateStore` exact declaration/type contract.
    stateId must resolve, type(value) must equal the selected state.typeId, and
    the instruction remains void (`result := none`). These fixtures drive the
    real structure+encode gate; spurious-result coverage remains in
    `testCfgVoidOpResultPresence`. -/
private def testCfgStateStoreTyping : IO Unit := do
  -- P1: UInt8 value exactly matches UInt8 state.
  let p1 ← programWithState "StoreP1UInt8" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr none (.stateStore 0 0)]
          (.return_ none)] 2]
  expectCfgOk "P1 stateStore UInt8 exact" p1
  -- P2: Bool value exactly matches Bool state.
  let p2 ← programWithState "StoreP2Bool" cfgOpTypes #[]
    #[stateRow 0 "flag" 2]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr none (.stateStore 0 0)]
          (.return_ none)] 2]
  expectCfgOk "P2 stateStore Bool exact" p2
  -- P3: stateId selects the second declaration, whose type is UInt32.
  let p3 ← programWithState "StoreP3SelectedState" cfgOpTypes #[]
    #[stateRow 0 "flag" 2, stateRow 1 "count" 4]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU32Def 0)) (cfgOpU32Lit 7),
            cfgInstr none (.stateStore 1 0)]
          (.return_ none)] 2]
  expectCfgOk "P3 stateStore selected declaration" p3
  -- N1: stateId does not resolve in an empty logicalState table.
  let n1 ← programWithTypes "StoreN1MissingState" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr none (.stateStore 0 0)]
          (.return_ none)] 2]
  expectCfgErr "N1 stateStore missing state" n1
  -- N2: Bool value does not match the selected UInt8 state.
  let n2 ← programWithState "StoreN2WrongValue" cfgOpTypes #[]
    #[stateRow 0 "s" 3]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr none (.stateStore 0 0)]
          (.return_ none)] 2]
  expectCfgErr "N2 stateStore wrong value type" n2
  -- N3: lookup must use the selected stateId rather than another row's type.
  let n3 ← programWithState "StoreN3WrongSelectedState" cfgOpTypes #[]
    #[stateRow 0 "flag" 2, stateRow 1 "count" 4]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr none (.stateStore 1 0)]
          (.return_ none)] 2]
  expectCfgErr "N3 stateStore selected type mismatch" n3

/-- SPEC-SEM-WIRE-001 §5.1/§6 `Op.Assert` exact condition/error join.
    condition must be Bool; `errorId = none` requires empty args, while
    `some errorId` must resolve and args must positionally match ErrorDecl
    fields. Assert remains void. Fixtures drive structure+encode dual paths. -/
private def testCfgAssertTyping : IO Unit := do
  -- P1: standard assertion failure form — Bool condition, no error, no args.
  let p1 ← programWithTypes "AssertP1Standard" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr none (.assert_ 0 none #[])]
          (.return_ none)] 2]
  expectCfgOk "P1 assert standard" p1
  -- P2: declared error with two positional args of exact field types.
  let p2 ← programWithErrors "AssertP2Declared" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 3, interfaceField "fatal" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpBoolDef 2)) (cfgOpBoolLit 0),
            cfgInstr none (.assert_ 0 (some 0) #[1, 2])]
          (.return_ none)] 2]
  expectCfgOk "P2 assert declared error args" p2
  -- P3: errorId selects the second declaration and its UInt32 field.
  let p3 ← programWithErrors "AssertP3SelectedError" cfgOpTypes
    #[errorRow 0 "Empty" #[],
      errorRow 1 "CountFailure" #[interfaceField "count" 4]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU32Def 1)) (cfgOpU32Lit 7),
            cfgInstr none (.assert_ 0 (some 1) #[1])]
          (.return_ none)] 2]
  expectCfgOk "P3 assert selected error" p3
  -- N1: condition must be Bool, not UInt8.
  let n1 ← programWithTypes "AssertN1Condition" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 1),
            cfgInstr none (.assert_ 0 none #[])]
          (.return_ none)] 2]
  expectCfgErr "N1 assert non-Bool condition" n1
  -- N2: errorId none requires args empty.
  let n2 ← programWithTypes "AssertN2StandardArgs" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 7),
            cfgInstr none (.assert_ 0 none #[1])]
          (.return_ none)] 2]
  expectCfgErr "N2 assert standard args nonempty" n2
  -- N3: declared errorId must resolve.
  let n3 ← programWithTypes "AssertN3MissingError" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr none (.assert_ 0 (some 0) #[])]
          (.return_ none)] 2]
  expectCfgErr "N3 assert missing error" n3
  -- N4: declared error arg count must equal fields.size.
  let n4 ← programWithErrors "AssertN4Arity" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 3, interfaceField "fatal" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 7),
            cfgInstr none (.assert_ 0 (some 0) #[1])]
          (.return_ none)] 2]
  expectCfgErr "N4 assert error arg count" n4
  -- N5: declared error args must match field types positionally.
  let n5 ← programWithErrors "AssertN5ArgType" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 3, interfaceField "fatal" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 0),
            cfgInstr (some (cfgOpBoolDef 2)) (cfgOpBoolLit 1),
            cfgInstr none (.assert_ 0 (some 0) #[1, 2])]
          (.return_ none)] 2]
  expectCfgErr "N5 assert error arg type" n5
  -- N6: lookup must use the selected errorId rather than another row's shape.
  let n6 ← programWithErrors "AssertN6SelectedError" cfgOpTypes
    #[errorRow 0 "FlagFailure" #[interfaceField "flag" 2],
      errorRow 1 "CountFailure" #[interfaceField "count" 4]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 1),
            cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 0),
            cfgInstr none (.assert_ 0 (some 1) #[1])]
          (.return_ none)] 2]
  expectCfgErr "N6 assert selected error arg type" n6

/-- SPEC-SEM-WIRE-001 §6 `Term.Revert` exact ErrorDecl join. errorId must
    resolve and args must match ErrorDecl fields positionally by exact TypeId.
    Fixtures drive the real structure+encode terminator-typing path. -/
private def testCfgRevertTyping : IO Unit := do
  -- P1: zero-field declared error with no args.
  let p1 ← programWithErrors "RevertP1Empty" cfgOpTypes
    #[errorRow 0 "Failure" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[] (.revert 0 #[])] 2]
  expectCfgOk "P1 revert empty error" p1
  -- P2: two args match ErrorDecl fields in source order.
  let p2 ← programWithErrors "RevertP2Args" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 3, interfaceField "fatal" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 0)]
          (.revert 0 #[0, 1])] 2]
  expectCfgOk "P2 revert declared args" p2
  -- P3: errorId selects the second declaration and its UInt32 field.
  let p3 ← programWithErrors "RevertP3Selected" cfgOpTypes
    #[errorRow 0 "Empty" #[],
      errorRow 1 "CountFailure" #[interfaceField "count" 4]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU32Def 0)) (cfgOpU32Lit 7)]
          (.revert 1 #[0])] 2]
  expectCfgOk "P3 revert selected error" p3
  -- N1: errorId must resolve.
  let n1 ← programWithTypes "RevertN1MissingError" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[] (.revert 0 #[])] 2]
  expectCfgErr "N1 revert missing error" n1
  -- N2: args count must equal fields.size.
  let n2 ← programWithErrors "RevertN2Arity" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 3, interfaceField "fatal" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7)]
          (.revert 0 #[0])] 2]
  expectCfgErr "N2 revert arg count" n2
  -- N3: args must match field types positionally.
  let n3 ← programWithErrors "RevertN3ArgType" cfgOpTypes
    #[errorRow 0 "Failure" #[interfaceField "code" 3]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 0)]
          (.revert 0 #[0])] 2]
  expectCfgErr "N3 revert arg type" n3
  -- N4: lookup must use selected errorId rather than another row's field type.
  let n4 ← programWithErrors "RevertN4Selected" cfgOpTypes
    #[errorRow 0 "FlagFailure" #[interfaceField "flag" 2],
      errorRow 1 "CountFailure" #[interfaceField "count" 4]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 0)]
          (.revert 1 #[0])] 2]
  expectCfgErr "N4 revert selected error arg type" n4
  -- N5 (review repair): distinct two-field types supplied in reverse order
  --   must fail, pinning source-order positional matching rather than a
  --   non-positional/multiset check.
  let n5 ← programWithErrors "RevertN5ReversedArgs" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 3, interfaceField "fatal" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 0),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 7)]
          (.revert 0 #[0, 1])] 2]
  expectCfgErr "N5 revert reversed positional args" n5

/-- SPEC-SEM-WIRE-001 §5.1 `Op.Emit` exact EventDecl join. eventId must
    resolve and args must match EventDecl fields positionally by exact TypeId;
    Emit remains void. EffectId global numbering is a separate §6 slice. -/
private def testCfgEmitTyping : IO Unit := do
  -- P1: zero-field event with no args.
  let p1 ← programWithEvents "EmitP1Empty" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.return_ none)] 2]
  expectCfgOk "P1 emit empty event" p1
  -- P2: two args match EventDecl fields in source order.
  let p2 ← programWithEvents "EmitP2Args" cfgOpTypes
    #[eventRow 0 "Tick"
        #[interfaceField "count" 3, interfaceField "final" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr (some (cfgOpBoolDef 1)) (cfgOpBoolLit 0),
            cfgInstr none (.emit 0 0 #[0, 1])]
          (.return_ none)] 2]
  expectCfgOk "P2 emit declared args" p2
  -- P3: eventId selects the second declaration and its UInt32 field.
  let p3 ← programWithEvents "EmitP3Selected" cfgOpTypes
    #[eventRow 0 "Ping" #[],
      eventRow 1 "Count" #[interfaceField "count" 4]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU32Def 0)) (cfgOpU32Lit 7),
            cfgInstr none (.emit 0 1 #[0])]
          (.return_ none)] 2]
  expectCfgOk "P3 emit selected event" p3
  -- N1: eventId must resolve.
  let n1 ← programWithTypes "EmitN1MissingEvent" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.return_ none)] 2]
  expectCfgErr "N1 emit missing event" n1
  -- N2: args count must equal fields.size.
  let n2 ← programWithEvents "EmitN2Arity" cfgOpTypes
    #[eventRow 0 "Tick"
        #[interfaceField "count" 3, interfaceField "final" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
            cfgInstr none (.emit 0 0 #[0])]
          (.return_ none)] 2]
  expectCfgErr "N2 emit arg count" n2
  -- N3: args must match field types positionally.
  let n3 ← programWithEvents "EmitN3ArgType" cfgOpTypes
    #[eventRow 0 "Tick" #[interfaceField "count" 3]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 0),
            cfgInstr none (.emit 0 0 #[0])]
          (.return_ none)] 2]
  expectCfgErr "N3 emit arg type" n3
  -- N4: lookup must use selected eventId rather than another row's type.
  let n4 ← programWithEvents "EmitN4Selected" cfgOpTypes
    #[eventRow 0 "Flag" #[interfaceField "flag" 2],
      eventRow 1 "Count" #[interfaceField "count" 4]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 0),
            cfgInstr none (.emit 0 1 #[0])]
          (.return_ none)] 2]
  expectCfgErr "N4 emit selected event arg type" n4
  -- N5: distinct field types supplied in reverse order must fail.
  let n5 ← programWithEvents "EmitN5ReversedArgs" cfgOpTypes
    #[eventRow 0 "Tick"
        #[interfaceField "count" 3, interfaceField "final" 2]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgOpBoolDef 0)) (cfgOpBoolLit 0),
            cfgInstr (some (cfgOpU8Def 1)) (cfgOpU8Lit 7),
            cfgInstr none (.emit 0 0 #[0, 1])]
          (.return_ none)] 2]
  expectCfgErr "N5 emit reversed positional args" n5

/-- SPEC-SEM-WIRE-001 §6 ExternalCall/Schedule callee shape: unlike the
    common QualifiedName carrier (which permits one component), effect callees
    must contain at least two components. Args remain empty here so this suite
    isolates the callee structure rule from the deferred serializability gate. -/
private def testCfgExternalCalleeShape : IO Unit := do
  let qualified ← cfgCalleeName
  let single ← cfgSingleComponentCalleeName
  -- P1/P2: both effect families accept a two-component callee.
  let p1 ← programWithTypes "CalleeP1External" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.externalCall 0 qualified #[])]
          (.return_ none)] 2]
  expectCfgOk "P1 externalCall qualified callee" p1
  let p2 ← programWithTypes "CalleeP2Schedule" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.schedule 0 qualified #[])]
          (.return_ none)] 2]
  expectCfgOk "P2 schedule qualified callee" p2
  -- P3: the lower bound is not an exact-two restriction.
  let three ← match parseQualifiedName #["org", "mod", "callee"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let p3 ← programWithTypes "CalleeP3Three" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.externalCall 0 three #[])]
          (.return_ none)] 2]
  expectCfgOk "P3 externalCall three-component callee" p3
  -- N1/N2: one component is valid for the common carrier but invalid for
  -- ExternalCall/Schedule. expectCfgErr checks structure and encode paths.
  let n1 ← programWithTypes "CalleeN1External" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.externalCall 0 single #[])]
          (.return_ none)] 2]
  expectCfgErr "N1 externalCall single-component callee" n1
  let n2 ← programWithTypes "CalleeN2Schedule" cfgOpTypes #[]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.schedule 0 single #[])]
          (.return_ none)] 2]
  expectCfgErr "N2 schedule single-component callee" n2

/- SPEC-SEM-WIRE-001 §5.1 closed ContextRead catalog coverage. The sole exact
   key has the program's unique anonymous UInt64 result and exact requirement;
   catalog validation follows all per-callable CFG validation and precedes
   invariant closure, fuel, and requirements. -/
private def testCfgContextReadResultTypeConsistency : IO Unit := do
  let ctxKey := unixTimeSecondsContextKeyV1
  let ctxReq := #[← exactContextRequirementRowV1]
  -- typeId 0 = Bool (wrong in-range shape), typeId 1 = UInt64 (catalog shape).
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 64 }]
  -- Instruction with a ContextRead op producing a result at the given
  --   ValueId/TypeId for the given key.
  let ctxRead (vid : ValueIdV1) (tid : TypeIdV1) (key : SchemaId) :
      InstructionV1 :=
    cfgInstr (some { valueId := vid, typeId := tid }) (.contextRead key)
  -- Entry callable with one block whose instructions are supplied; returns
  --   none. `id`/`name` default to 0/"run"; callers override for
  --   multi-callable programs so the name-uniqueness gate stays satisfied.
  let entryCallable (instrs : Array InstructionV1)
      (id : CallableIdV1 := 0) (name : String := "run") : CallableV1 :=
    { (cfgCallableKindName .entry (some name)
          (resultTypeId := 0)) with
      id
      blocks := #[cfgBlockInstrs 0 instrs (.return_ none)] }
  -- P1: zero reads (no ContextRead → no requirement row required).
  let p1 ← programWithTypes "CtxConsP1Zero" types #[]
    #[entryCallable #[]]
  expectCfgOk "P1 zero reads" p1
  -- P2: one exact catalog read.
  let p2 ← programWithTypes "CtxConsP2One" types #[]
    #[entryCallable #[ctxRead 0 1 ctxKey]] ctxReq
  expectCfgOk "P2 one read" p2
  -- P3: same key, same TypeId across two callables.
  let p3 ← programWithTypes "CtxConsP3TwoCalls" types #[]
    #[entryCallable #[ctxRead 0 1 ctxKey] 0 "runA",
      entryCallable #[ctxRead 0 1 ctxKey] 1 "runB"] ctxReq
  expectCfgOk "P3 same key same type across callables" p3
  -- P4: same key, same TypeId across two blocks within one callable. The
  --   branch is split between block 1 (then) and block 2 (else), each
  --   reading the key with the Bool TypeId and returning none. Block 0
  --   defines the branch condition via a Bool literal.
  let p4 ← programWithTypes "CtxConsP4Branches" types #[]
    #[{ (cfgCallableKindName .entry (some "run")
          (resultTypeId := 0)) with
        id := 0
        blocks := #[
          cfgBlockInstrs 0
            #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
            (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[ctxRead 1 1 ctxKey]
            (.return_ none),
          cfgBlockInstrs 2
            #[ctxRead 2 1 ctxKey]
            (.return_ none)
        ] }] ctxReq
  expectCfgOk "P4 same key same type across branches" p4
  -- P5: same key, same TypeId repeated within one block. Local repetition of
  --   the same exact key with the same result TypeId is allowed; the global
  --   consistency gate only rejects a divergent TypeId for an already-seen
  --   key.
  let p5 ← programWithTypes "CtxConsP5LocalRepeat" types #[]
    #[entryCallable
        #[ctxRead 0 1 ctxKey, ctxRead 1 1 ctxKey]] ctxReq
  expectCfgOk "P5 same key same UInt64 repeated one block" p5
  -- N1: known key with wrong in-range Bool result.
  let n1 ← programWithTypes "CtxConsN1Block" types #[]
    #[entryCallable
        #[ctxRead 0 1 ctxKey, ctxRead 1 0 ctxKey]] ctxReq
  expectCfgErr "N1 same key different type one block" n1
  expectCfgInvariantPhase "N1 cfg consistency phase" .cfg .badCfg n1
  -- N2: same key, different TypeId across branches.
  let n2 ← programWithTypes "CtxConsN2Branches" types #[]
    #[{ (cfgCallableKindName .entry (some "run")
          (resultTypeId := 0)) with
        id := 0
        blocks := #[
          cfgBlockInstrs 0
            #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0)]
            (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[ctxRead 1 1 ctxKey]
            (.return_ none),
          cfgBlockInstrs 2
            #[ctxRead 2 0 ctxKey]
            (.return_ none)
        ] }] ctxReq
  expectCfgErr "N2 same key different type across branches" n2
  expectCfgInvariantPhase "N2 cfg consistency phase" .cfg .badCfg n2
  -- N3: same key, different TypeId across different callables.
  let n3 ← programWithTypes "CtxConsN3Callables" types #[]
    #[entryCallable #[ctxRead 0 1 ctxKey] 0 "runA",
      entryCallable #[ctxRead 0 0 ctxKey] 1 "runB"] ctxReq
  expectCfgErr "N3 same key different type across callables" n3
  expectCfgInvariantPhase "N3 cfg consistency phase" .cfg .badCfg n3
  -- N4: unknown keys are rejected by the closed catalog.
  let nearKey : SchemaId := { value := "proof-forge.context.unknown.v1" }
  let n4 ← programWithTypes "CtxConsN4ExactKey" types #[]
    #[entryCallable #[ctxRead 0 1 nearKey]] ctxReq
  expectCfgErrCode "N4 unknown key rejected" .badCfg n4
  -- Precedence: a missing ContextRead result (generic CFG/op typing) fails
  --   before the global consistency pass.
  let n5 ← programWithTypes "CtxConsN5MissingResult" types #[]
    #[entryCallable
        #[cfgInstr none (.contextRead ctxKey)]] ctxReq
  expectCfgErrCode "N5 missing result before consistency" .badCfg n5
  expectCfgInvariantPhase "N5 generic typing before consistency" .cfg .badCfg n5
  -- Precedence: a def-site TypeId OOR (step h) fails as `.badReference`
  --   before the global consistency pass. Here the ContextRead result
  --   declares typeId 99 (out of range).
  let n6 ← programWithTypes "CtxConsN6TypeOOR" types #[]
    #[entryCallable
        #[cfgInstr (some { valueId := 0, typeId := 99 })
            (.contextRead ctxKey)]] ctxReq
  expectCfgErrCode "N6 def TypeId OOR before consistency"
    .badReference n6
  -- Precedence: a generic CFG failure (undefined terminator use) fails before
  --   consistency. The branch references an undefined ValueId 7.
  let n7 ← programWithTypes "CtxConsN7CfgBefore" types #[]
    #[{ (cfgCallableKindName .entry (some "run")
          (resultTypeId := 0)) with
        id := 0
        blocks := #[
          cfgBlockInstrs 0
            #[ctxRead 0 1 ctxKey]
            (.branch 7 (cfgJumpTarget 1) (cfgJumpTarget 1)),
          cfgBlock 1 (.return_ none)
        ] }] ctxReq
  expectCfgErrCode "N7 generic CFG before consistency" .badCfg n7
  expectCfgInvariantPhase "N7 generic CFG phase wins" .cfg .badCfg n7
  -- Mixed-invalid phase precedence 3a: a canonical valueBytes error (bad
  --   Bool literal byte 0x02) co-located with a same-key TypeId mismatch
  --   must fail as `.nonCanonical` first, because the valueBytes gate (step
  --   4) precedes the CFG/consistency segment (step 4.5).
  let badValueMismatch : CallableV1 :=
    entryCallable
      #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 2),
        ctxRead 1 1 ctxKey,
        ctxRead 2 0 ctxKey]
  let m1 ← programWithTypes "CtxConsM1ValueBeforeMismatch" types #[]
    #[badValueMismatch] ctxReq
  expectCfgErrCode "M1 canonical valueBytes before consistency"
    .nonCanonical m1
  -- Mixed-invalid phase precedence 3b: a same-key TypeId mismatch co-located
  --   with a later bad requirement must fail as `.badCfg` first; the
  --   requirement gate (step 5) runs only after the CFG/consistency segment.
  --   The available phase seam pins the consistency failure to `.cfg`.
  let m2 : SemanticProgramDataV1 := {
    n1 with requirements := { items := #[req "notadomain.after-ctx"] }
  }
  expectCfgErrCode "M2 consistency before bad requirement" .badCfg m2
  expectCfgInvariantPhase "M2 cfg before requirements" .cfg .badCfg m2
  -- Mixed-invalid phase precedence 3c: a named Struct/Enum duplicate
  --   (`.duplicate`, step 3) co-located with a same-key TypeId mismatch must
  --   fail as `.duplicate` first, because the named-name uniqueness gate
  --   precedes the CFG/consistency segment. The duplicate type table keeps
  --   child refs in range so the only competing earlier failure is the name
  --   clash.
  let dupTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "Dup",
      shape := .struct #[{ name := "a", typeId := 2 }] },
    { id := 1, name := some "Dup",
      shape := .enum #[{ name := "v", payloadTypes := #[2] }] },
    { id := 2, name := none, shape := .bool }
  ]
  let m3 ← programWithTypes "CtxConsM3NameDupBeforeMismatch" dupTypes #[]
    #[entryCallable
        #[ctxRead 0 1 ctxKey, ctxRead 1 0 ctxKey]] ctxReq
  expectCfgErrCode "M3 named-name duplicate before consistency"
    .duplicate m3
  -- Mixed-invalid cross-callable phase order 4: ALL per-callable generic
  --   CFG/op validation (the `.cfg` per-callable loop) must finish before the
  --   global same-key consistency pass begins. The first callable has a valid
  --   CFG but two ContextReads using the same key with UInt64/Bool result
  --   TypeIds (a global mismatch that only the post-loop consistency pass
  --   would catch). The later callable carries a distinguishable generic
  --   def-site TypeId out-of-range error (`.badReference`, step h). Because
  --   the per-callable loop visits every callable before the global pass,
  --   the later callable's `.badReference` must win over the first callable's
  --   latent same-key mismatch. Both shipped structure and the structure-
  --   gated encoder return `.badReference`; the phase seam pins it to `.cfg`
  --   with `.badReference`.
  let laterOor : CallableV1 :=
    entryCallable
      #[cfgInstr (some { valueId := 0, typeId := 99 })
          (.literal 0 (ByteArray.mk #[0]))]
      1 "runB"
  let m4 ← programWithTypes "CtxConsM4CrossCallablePhase" types #[]
    #[entryCallable
        #[ctxRead 0 1 ctxKey, ctxRead 1 0 ctxKey] 0 "runA",
      laterOor] ctxReq
  expectCfgErrCode "M4 per-callable OOR before global consistency"
    .badReference m4
  expectCfgInvariantPhase "M4 cfg phase per-callable OOR"
    .cfg .badReference m4
  -- Phase: a same-key mismatch inside an invariant root must fail as `.cfg`
  --   before the later invariant-closure ContextRead prohibition. The root
  --   declares two ContextReads with the same key but different TypeIds;
  --   generic op typing passes (result present, TypeIds in range), so the
  --   consistency gate fires first.
  let rootMismatch : CallableV1 := {
    (cfgCallableKindName .invariant (some "safe")
      (resultTypeId := 0)) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
          ctxRead 1 1 ctxKey,
          ctxRead 2 0 ctxKey]
        (.return_ (some 0))]
      invariantSteps := some 7
  }
  let n8Base ← programWithTypes "CtxConsN8RootPhase" types #[]
    #[rootMismatch] ctxReq
  let n8 : SemanticProgramDataV1 := {
    n8Base with invariants := #[{ id := 0, name := "safe", callableId := 0 }]
  }
  expectCfgErr "N8 consistency before invariant ContextRead prohibition" n8
  expectCfgInvariantPhase "N8 cfg before invariant closure" .cfg .badCfg n8
  -- Phase: valid ContextRead consistency (a single same-key Bool read) still
  --   present in a reachable invariant-closure pureFn must fail at the
  --   invariant-closure pureFn forbidden-op allowlist, not at the
  --   consistency gate. The consistency pass must have accepted the program
  --   up to that point.
  let contextReader : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 1 }) (.contextRead ctxKey),
        cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1)]
      (.return_ (some 1))]) with
      id := 0
      name := some "contextReader"
      invariantSteps := some 5
  }
  let invariantRoot : CallableV1 := {
    (cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgValueDef 0)) (.pureCall 0 #[])]
      (.return_ (some 0))]) with
      id := 1
      kind := .invariant
      name := some "safe"
      invariantSteps := some 8
  }
  let n9Base ← programWithTypes "CtxConsN9ClosureValidConsistency" types #[]
    #[contextReader, invariantRoot] ctxReq
  let n9 : SemanticProgramDataV1 := {
    n9Base with invariants := #[{ id := 0, name := "safe", callableId := 1 }]
  }
  expectCfgErr "N9 valid consistency, closure ContextRead forbidden" n9
  expectCfgInvariantPhase "N9 closure phase after valid consistency"
    .invariantClosure .badCfg n9
  -- Transport: hand-assemble a raw envelope carrying a same-key type
  --   mismatch. `decodeSemanticProgramDataV1` is structure-free and must
  --   accept and preserve it; structure gate, encoder, and carrier reject
  --   with `.badCfg`.
  let qn ← match parseQualifiedName #["Tests", "CtxConsTransport"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let qnB ← expectOk "tr qn" (encodeQualifiedName qn)
  let typesB ← expectOk "tr types" (encodeArray encodeTypeDeclV1 types)
  let emptyConsts ← expectOk "tr consts" (encodeArray encodeConstantV1 #[])
  let emptyState ← expectOk "tr state" (encodeArray encodeStateDeclV1 #[])
  let emptyEvents ← expectOk "tr events" (encodeArray encodeEventDeclV1 #[])
  let emptyErrors ← expectOk "tr errors" (encodeArray encodeErrorDeclV1 #[])
  let trCallable : CallableV1 :=
    entryCallable
      #[ctxRead 0 1 ctxKey, ctxRead 1 0 ctxKey]
  let callablesB ← expectOk "tr callables"
    (encodeArray encodeCallableV1 #[trCallable])
  let emptyInvariants ← expectOk "tr invariants"
    (encodeArray encodeInvariantDeclV1 #[])
  let reqB ← expectOk "tr reqs"
    (encodeProgramRequirementsV1 { items := #[] })
  let body ← expectOk "tr body" (encodeTagged "SemanticProgram.Data" #[
    qnB, typesB, emptyConsts, emptyState, emptyEvents, emptyErrors,
    callablesB, emptyInvariants, reqB
  ])
  let magic := semanticProgramMagicV1.toUTF8.push 0
  let trBytes := magic.append body
  let decoded ← expectOk "transport accepts same-key mismatch"
    (decodeSemanticProgramDataV1 trBytes)
  -- Transport is structure-free and must preserve the exact payload.
  expect (decoded.qualifiedName == qn) "transport qualifiedName preserved"
  expect (decoded.types == types) "transport types preserved"
  expect (decoded.callables == #[trCallable])
    "transport callables preserved"
  expectErr "structure rejects same-key mismatch" .badCfg
    (validateSemanticProgramStructureV1 decoded)
  expectErr "encoder rejects same-key mismatch" .badCfg
    (encodeSemanticProgramDataV1 decoded)
  expectErr "carrier rejects same-key mismatch" .badCfg
    (decodeSemanticProgramV1 trBytes)
  -- Resource: 2000 repetitions of the sole exact key/UInt64 row stay bounded.
  let mut instrs : Array InstructionV1 := #[]
  let mut vid : ValueIdV1 := 0
  for _ in [:2000] do
    instrs := instrs.push (ctxRead vid 1 ctxKey)
    vid := vid + 1
  -- The single entry callable must terminate; the large instruction array
  --   keeps all ValueIds distinct so SSA remains valid.
  let resourceCallable : CallableV1 := {
    (cfgCallableKindName .entry (some "run")
      (resultTypeId := 0)) with
      id := 0
      blocks := #[cfgBlockInstrs 0 instrs (.return_ none)] }
  let r ← programWithTypes "CtxConsResource" types #[]
    #[resourceCallable] ctxReq
  expectCfgOk "resource 2000 reads bounded" r

/-- Exact ContextRead requirement binding variants. -/
private def testCfgContextReadCatalogRequirements : IO Unit := do
  let types : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 64 }]
  let read (vid : ValueIdV1) (tid : TypeIdV1 := 1)
      (key : SchemaId := unixTimeSecondsContextKeyV1) : InstructionV1 :=
    cfgInstr (some { valueId := vid, typeId := tid }) (.contextRead key)
  let entry (instructions : Array InstructionV1) : CallableV1 := {
    (cfgCallableKindName .entry (some "run") (resultTypeId := 0)) with
      blocks := #[cfgBlockInstrs 0 instructions (.return_ none)] }
  let exact ← exactContextRequirementRowV1
  let ctxReq := #[exact]
  let base ← programWithTypes "ContextCatalog" types #[]
    #[entry #[read 0, read 1]] ctxReq
  expectCfgOk "exact ContextRead catalog row" base
  let repeated ← programWithTypes "ContextCatalogRepeated" types #[]
    #[entry (Array.ofFn (fun i : Fin 2000 => read i.val.toUInt32))] ctxReq
  expectCfgOk "bounded repeated ContextRead occurrences" repeated
  let unknown : SchemaId := { value := "proof-forge.context.unknown.v1" }
  let badKey ← programWithTypes "ContextCatalogUnknown" types #[]
    #[entry #[read 0 1 unknown]] ctxReq
  expectCfgErrCode "unknown ContextRead key" .badCfg badKey
  let badType ← programWithTypes "ContextCatalogWrongType" types #[]
    #[entry #[read 0 0]] ctxReq
  expectCfgErrCode "wrong in-range ContextRead shape" .badCfg badType
  expectCfgInvariantPhase "wrong ContextRead shape is cfg phase" .cfg .badCfg badType
  let missing : SemanticProgramDataV1 := { base with requirements := { items := #[] } }
  expectCfgErrCode "missing ContextRead requirement" .badRequirement missing
  let wrongVersion : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with version := { major := 1, minor := 0, patch := 1 } }] } }
  expectCfgErrCode "wrong ContextRead requirement version" .badRequirement wrongVersion
  let wrongDigest : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with digest := zeroDigest }] } }
  expectCfgErrCode "wrong ContextRead requirement digest" .badRequirement wrongDigest
  let wrongPredicates : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with predicates := #[.boolEquals "x" true] }] } }
  expectCfgErrCode "wrong ContextRead requirement predicates" .badRequirement wrongPredicates
  let wrongId : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with id := "context.unix-time-second" }] } }
  expectCfgErrCode "wrong ContextRead requirement id is missing" .badRequirement wrongId
  let alternateSameId : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ req "context.unix-time-seconds" with
      version := exact.version }] } }
  expectCfgErrCode "alternate same-id requirement row" .badRequirement alternateSameId
  let malformedFirst : SemanticProgramDataV1 := {
    base with requirements := { items := #[req "notadomain", exact] } }
  expectCfgErrCode "generic requirement structure precedes catalog binding"
    .badRequirement malformedFirst
  let unrelated := req "value.extra"
  let extra : SemanticProgramDataV1 := {
    base with requirements := { items := #[exact, unrelated] } }
  expectCfgOk "unrelated generic requirement accepted" extra

/-- Exact Commit disclosure requirement binding variants. Recognition of this
    Wire-owned row does not add it to any target support catalog. -/
private def testCfgCommitCatalogRequirements : IO Unit := do
  let exact ← exactCommitRequirementRowV1
  let commitReq := #[exact]
  let commitEntry : CallableV1 := {
    (cfgCallableKindName .entry (some "run") (resultTypeId := 3)) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some (cfgOpU8Def 0)) (cfgOpU8Lit 7),
          cfgInstr (some (cfgOpU8Def 1)) (.commit 0),
          cfgInstr (some (cfgOpU8Def 2)) (.commit 1)]
        (.return_ (some 2))] }
  let base ← programWithTypes "CommitCatalog" cfgOpTypes #[]
    #[commitEntry] commitReq
  expectCfgOk "exact Commit requirement row" base
  let missing : SemanticProgramDataV1 := { base with requirements := { items := #[] } }
  expectCfgErrCode "missing Commit requirement" .badRequirement missing
  let wrongVersion : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with
      version := { major := 1, minor := 0, patch := 1 } }] } }
  expectCfgErrCode "wrong Commit requirement version" .badRequirement wrongVersion
  let wrongDigest : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with digest := zeroDigest }] } }
  expectCfgErrCode "wrong Commit requirement digest" .badRequirement wrongDigest
  let wrongPredicates : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with
      predicates := #[.boolEquals "x" true] }] } }
  expectCfgErrCode "wrong Commit requirement predicates" .badRequirement wrongPredicates
  let wrongId : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ exact with id := "disclosure.commitments" }] } }
  expectCfgErrCode "wrong Commit requirement id is missing" .badRequirement wrongId
  let alternateSameId : SemanticProgramDataV1 := {
    base with requirements := { items := #[{ req commitmentDisclosureRequirementIdV1 with
      version := exact.version }] } }
  expectCfgErrCode "alternate same-id Commit row" .badRequirement alternateSameId
  let malformedFirst : SemanticProgramDataV1 := {
    base with requirements := { items := #[req "notadomain", exact] } }
  expectCfgErrCode "generic requirement structure precedes Commit binding"
    .badRequirement malformedFirst
  let unrelated := req "value.extra"
  let extra : SemanticProgramDataV1 := {
    base with requirements := { items := #[exact, unrelated] } }
  expectCfgOk "unrelated generic row accepted with Commit" extra
  let noCommit ← programWithTypes "CommitCatalogUnused" cfgOpTypes #[] #[]
  expectCfgOk "Commit requirement not required without Commit"
    { noCommit with requirements := { items := #[exact] } }
  -- Combined ContextRead + Commit rows remain in canonical UTF-8 order:
  -- context.unix-time-seconds precedes disclosure.commitment.
  let contextExact ← exactContextRequirementRowV1
  let combinedTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 64 }]
  let combinedEntry : CallableV1 := {
    (cfgCallableKindName .entry (some "run") (resultTypeId := 1)) with
      blocks := #[cfgBlockInstrs 0
        #[cfgInstr (some { valueId := 0, typeId := 1 })
            (.contextRead unixTimeSecondsContextKeyV1),
          cfgInstr (some { valueId := 1, typeId := 1 }) (.commit 0)]
        (.return_ (some 1))] }
  let combined ← programWithTypes "CommitContextCatalog" combinedTypes #[]
    #[combinedEntry] #[contextExact, exact]
  expect (combined.requirements.items == #[contextExact, exact])
    "combined Commit/Context requirements must be canonical"
  expectCfgOk "combined Commit/Context exact rows" combined

/-- SPEC-SEM-WIRE-001 §6 EffectId assignment: within each callable, every
    Emit/ExternalCall/Schedule instruction must carry the next contiguous
    EffectId in BlockId/instruction order, starting at zero. -/
private def testCfgEffectIdOrder : IO Unit := do
  let calleeName ← cfgCalleeName
  -- P1: all three effect families receive contiguous IDs in one block.
  let p1 ← programWithEvents "EffectP1Families" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[]),
            cfgInstr none (.externalCall 1 calleeName #[]),
            cfgInstr none (.schedule 2 calleeName #[])]
          (.return_ none)] 2]
  expectCfgOk "P1 effectId all families" p1
  -- P2: numbering follows BlockId order across reachable blocks.
  let p2 ← programWithEvents "EffectP2Blocks" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.jump (cfgJumpTarget 1)),
        cfgBlockInstrs 1
          #[cfgInstr none (.schedule 1 calleeName #[])]
          (.return_ none)] 2]
  expectCfgOk "P2 effectId across blocks" p2
  -- P3: EffectId numbering resets independently for each callable.
  let c0 := cfgCallableResult
    #[cfgBlockInstrs 0 #[cfgInstr none (.emit 0 0 #[])] (.return_ none)] 0
  let c1 : CallableV1 := {
    (cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.schedule 0 calleeName #[])]
        (.return_ none)] 0) with
    id := 1
    name := some "g"
  }
  let p3 ← programWithEvents "EffectP3PerCallable" cfgOpTypes
    #[eventRow 0 "Ping" #[]] #[c0, c1]
  expectCfgOk "P3 effectId per-callable reset" p3
  -- N1: first effect ID must be zero.
  let n1 ← programWithEvents "EffectN1StartsAtOne" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.emit 1 0 #[])] (.return_ none)] 2]
  expectCfgErr "N1 effectId starts at one" n1
  -- N2: duplicate IDs across effect families are invalid.
  let n2 ← programWithEvents "EffectN2Duplicate" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[]),
            cfgInstr none (.externalCall 0 calleeName #[])]
          (.return_ none)] 2]
  expectCfgErr "N2 effectId duplicate" n2
  -- N3: gaps are invalid even when IDs remain increasing.
  let n3 ← programWithEvents "EffectN3Gap" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[]),
            cfgInstr none (.schedule 2 calleeName #[])]
          (.return_ none)] 2]
  expectCfgErr "N3 effectId gap" n3
  -- N4: later block cannot restart or reverse numbering.
  let n4 ← programWithEvents "EffectN4BlockOrder" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgOpCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.jump (cfgJumpTarget 1)),
        cfgBlockInstrs 1
          #[cfgInstr none (.schedule 0 calleeName #[])]
          (.return_ none)] 2]
  expectCfgErr "N4 effectId block order" n4

/-- SPEC-SEM-WIRE-001 §6 declaration/field/parameter/invariant name grammar:
    structure authority applies the shared SPEC-COMMON identifier component
    rule (`validateIdentifierComponent`) to every present name site. This is
    not just `encodeString` NFC: digit-first/punctuation/empty/`_`/over-240
    fail closed on structure validate and structure-gated encode/carrier even
    when NFC UTF-8 transport would accept the bare string. Initializer
    `name=none` is not rejected. Exact uniqueness phases remain earlier and
    retain priority on mixed-invalid fixtures. -/
private def ofScalars (codePoints : List Nat) : String :=
  codePoints.foldl (fun acc cp => acc.push (Char.ofNat cp)) ""

private def repeatedChars (count : Nat) (value : Char) : String :=
  String.ofList (List.replicate count value)

private def nfcAcute : String := ofScalars [0x00E9]
private def nfdAcute : String := ofScalars [0x0065, 0x0301]
private def nameOver240 : String := repeatedChars 241 'a'
private def nameMax240 : String := repeatedChars 240 'a'

private def expectIdentOk (label : String) (data : SemanticProgramDataV1) :
    IO Unit := do
  expectCfgOk label data

private def expectIdentBad (label : String) (data : SemanticProgramDataV1) :
    IO Unit := do
  expectCfgErrCode label .badScalar data

/-- Build a transport envelope without the structure-gated program encoder so
    NFC-valid but identifier-illegal names can still be decoded as raw data. -/
private def transportEnvelope (data : SemanticProgramDataV1) : IO ByteArray := do
  let qnB ← expectOk "transport qn" (encodeQualifiedName data.qualifiedName)
  let typesB ← expectOk "transport types" (encodeArray encodeTypeDeclV1 data.types)
  let constsB ← expectOk "transport constants"
    (encodeArray encodeConstantV1 data.constants)
  let stateB ← expectOk "transport state"
    (encodeArray encodeStateDeclV1 data.logicalState)
  let eventsB ← expectOk "transport events"
    (encodeArray encodeEventDeclV1 data.events)
  let errorsB ← expectOk "transport errors"
    (encodeArray encodeErrorDeclV1 data.errors)
  let callablesB ← expectOk "transport callables"
    (encodeArray encodeCallableV1 data.callables)
  let invsB ← expectOk "transport invariants"
    (encodeArray encodeInvariantDeclV1 data.invariants)
  let reqsB ← expectOk "transport requirements"
    (encodeProgramRequirementsV1 data.requirements)
  let body ← expectOk "transport body" (encodeTagged "SemanticProgram.Data" #[
    qnB, typesB, constsB, stateB, eventsB, errorsB, callablesB, invsB, reqsB])
  pure ((semanticProgramMagicV1.toUTF8.push 0).append body)

private def testDeclarationIdentifierNames : IO Unit := do
  -- Positives: ASCII, underscore-prefixed, NFC non-ASCII, max-240, initializer
  -- none coexists with legal named callables/params.
  let pAscii ← programWithTypes "IdentP0Ascii" cfgBoolTypes
    #[constOf 0 "counter" 0 (ByteArray.mk #[0])]
  expectIdentOk "P0 ASCII constant name" pAscii
  let pUnder ← programWithTypes "IdentP1Under" cfgBoolTypes
    #[constOf 0 "_value" 0 (ByteArray.mk #[0])]
  expectIdentOk "P1 underscore-prefixed constant" pUnder
  let pNfc ← programWithTypes "IdentP2Nfc" cfgBoolTypes
    #[constOf 0 nfcAcute 0 (ByteArray.mk #[0])]
  expectIdentOk "P2 NFC non-ASCII constant" pNfc
  let pMax ← programWithTypes "IdentP3Max240" cfgBoolTypes
    #[constOf 0 nameMax240 0 (ByteArray.mk #[0])]
  expectIdentOk "P3 constant name max 240 UTF-8 bytes" pMax
  let unitType : TypeDeclV1 := { id := 0, name := none, shape := .unit }
  let initCallable : CallableV1 := {
    id := 0
    kind := .initializer
    name := none
    params := #[{ valueId := 0, name := "seed", typeId := 0,
                  visibility := .public_ }]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[{ id := 0, params := #[], instructions := #[],
                  terminator := .return_ none }]
    loopBounds := #[]
    invariantSteps := none
  }
  let pInit ← programWithTypes "IdentP4InitNone" #[unitType] #[] #[initCallable]
  expectIdentOk "P4 initializer name=none not rejected" pInit

  -- Negatives shared across illegal spellings (structure + encode dual path).
  let badVectors : Array (String × String) := #[
    ("empty", ""),
    ("anonymous", "_"),
    ("digitFirst", "1abc"),
    ("punctuation", "a-b"),
    ("nonNfc", nfdAcute),
    ("over240", nameOver240)
  ]
  for pair in badVectors do
    let (tag, bad) := pair
    -- Constant name category.
    let c ← programWithTypes s!"IdentNConst{tag}" cfgBoolTypes
      #[constOf 0 bad 0 (ByteArray.mk #[0])]
    expectIdentBad s!"constant name {tag}" c
    -- State name category.
    let sBase ← programWithTypes s!"IdentNState{tag}" cfgBoolTypes
    let s := { sBase with logicalState :=
      #[{ id := 0, name := bad, typeId := 0, visibility := .public_ }] }
    expectIdentBad s!"state name {tag}" s
    -- Event declaration name category.
    let eBase ← programWithTypes s!"IdentNEvent{tag}" cfgBoolTypes
    let e := { eBase with events :=
      #[{ id := 0, name := bad, fields := #[] }] }
    expectIdentBad s!"event name {tag}" e
    -- Error declaration name category.
    let rBase ← programWithTypes s!"IdentNError{tag}" cfgBoolTypes
    let r := { rBase with errors :=
      #[{ id := 0, name := bad, fields := #[] }] }
    expectIdentBad s!"error name {tag}" r

  -- One representative illegal spelling per remaining name category (digit-first).
  let bad := "1bad"
  -- Named Struct TypeDecl name.
  let namedStructTypes : Array TypeDeclV1 := #[
    { id := 0, name := some bad,
      shape := .struct #[{ name := "f", typeId := 1 }] },
    { id := 1, name := none, shape := .bool }
  ]
  let nNamed ← programWithTypes "IdentNNamedType" namedStructTypes
  expectIdentBad "named TypeDecl name digit-first" nNamed
  -- Struct field name.
  let structFieldTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "S",
      shape := .struct #[{ name := bad, typeId := 1 }] },
    { id := 1, name := none, shape := .bool }
  ]
  let nField ← programWithTypes "IdentNStructField" structFieldTypes
  expectIdentBad "struct field name digit-first" nField
  -- Enum variant name.
  let enumVariantTypes : Array TypeDeclV1 := #[
    { id := 0, name := some "E",
      shape := .enum #[{ name := bad, payloadTypes := #[] }] },
    { id := 1, name := none, shape := .bool }
  ]
  let nVar ← programWithTypes "IdentNEnumVariant" enumVariantTypes
  expectIdentBad "enum variant name digit-first" nVar
  -- Event interface field.
  let nEvFieldBase ← programWithTypes "IdentNEventField" cfgBoolTypes
  let nEvField := { nEvFieldBase with events :=
    #[{ id := 0, name := "Ev", fields :=
        #[{ name := bad, typeId := 0, visibility := .public_ }] }] }
  expectIdentBad "event field name digit-first" nEvField
  -- Error interface field.
  let nErFieldBase ← programWithTypes "IdentNErrorField" cfgBoolTypes
  let nErField := { nErFieldBase with errors :=
    #[{ id := 0, name := "Er", fields :=
        #[{ name := bad, typeId := 0, visibility := .public_ }] }] }
  expectIdentBad "error field name digit-first" nErField
  -- Named callable (entry_gate stays legal; extra pureFn carries illegal name).
  let nCall ← programWithTypes "IdentNCallable" cfgBoolTypes #[]
    #[{ (cfgCallableKindName .pureFn (some bad)) with id := 0 }]
  expectIdentBad "named callable digit-first" nCall
  -- Callable parameter name (callable name legal).
  let nParam ← programWithTypes "IdentNParam" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := bad, typeId := 0, visibility := .public_ }]
        #[cfgBlock 0 (.return_ none)]]
  expectIdentBad "callable parameter digit-first" nParam
  -- InvariantDecl name: join requires exact match with invariant callable name,
  -- so both carry the illegal spelling; walk checks invariants before callables.
  let invBad : CallableV1 :=
    { (cfgCallableKindName .invariant (some bad)) with id := 0 }
  let nInvBase ← programWithTypes "IdentNInvariant" cfgBoolTypes #[] #[invBad]
  let nInv : SemanticProgramDataV1 := {
    nInvBase with invariants := #[{ id := 0, name := bad, callableId := 0 }]
  }
  expectIdentBad "InvariantDecl name digit-first" nInv

  -- Mixed-invalid phase pins: earlier uniqueness/shape/join keep priority;
  -- grammar is not merely encodeString NFC (structure path rejects first).
  let dupConstants : Array ConstantV1 :=
    #[constOf 0 bad 0 (ByteArray.mk #[0]),
      constOf 1 bad 0 (ByteArray.mk #[1])]
  let nDup ← programWithTypes "IdentPhaseDupBeforeGrammar" cfgBoolTypes
    dupConstants
  expectCfgErrCode "duplicate constant names before identifier grammar"
    .duplicate nDup
  let nShape ← programWithTypes "IdentPhaseShapeBeforeGrammar"
    #[{ id := 0, name := some bad, shape := .struct #[] },
      { id := 1, name := none, shape := .bool }]
  expectCfgErrCode "empty struct shape before identifier grammar" .badType nShape
  let joinCallable : CallableV1 :=
    { (cfgCallableKindName .invariant (some "GoodInv")) with id := 0 }
  let nJoinBase ← programWithTypes "IdentPhaseJoinBeforeGrammar" cfgBoolTypes #[]
    #[joinCallable]
  let nJoin : SemanticProgramDataV1 := {
    nJoinBase with invariants := #[{ id := 0, name := bad, callableId := 0 }]
  }
  expectCfgErrCode "InvariantDecl join before identifier grammar" .badCfg nJoin
  let nRef ← programWithTypes "IdentPhaseRefBeforeGrammar" cfgBoolTypes
    #[constOf 0 bad 99 (ByteArray.mk #[0])]
  expectCfgErrCode "shallow TypeId before identifier grammar" .badReference nRef
  -- Grammar precedes CFG: illegal name + later CFG defect → .badScalar.
  let badCfgCallable : CallableV1 := {
    cfgCallable #[cfgBlockInstrs 0
      #[cfgInstr (some { valueId := 0, typeId := 99 }) (cfgBoolLit 0)]
      (.return_ none)] with
      id := 0
      name := some bad
  }
  let nCfg ← programWithTypes "IdentPhaseGrammarBeforeCfg" cfgBoolTypes #[]
    #[badCfgCallable]
  expectCfgErrCode "identifier grammar before CFG" .badScalar nCfg
  -- Grammar precedes requirements.
  let nReqBase ← programWithTypes "IdentPhaseGrammarBeforeReq" cfgBoolTypes
    #[constOf 0 bad 0 (ByteArray.mk #[0])]
  let nReq : SemanticProgramDataV1 := {
    nReqBase with requirements := { items := #[req "notadomain.foo"] }
  }
  expectCfgErrCode "identifier grammar before requirements" .badScalar nReq

  -- Transport accepts digit-first constant (NFC UTF-8 scalar only); structure
  -- authority, structure-gated encode, and carrier re-encode reject .badScalar.
  -- Proves the gate is not "only encodeString on the program encoder path".
  let raw ← transportEnvelope
    (← programWithTypes "IdentTransportDigitFirst" cfgBoolTypes
      #[constOf 0 bad 0 (ByteArray.mk #[0])])
  let decoded ← expectOk "transport accepts digit-first constant name"
    (decodeSemanticProgramDataV1 raw)
  expectIdentBad "structure rejects transport digit-first constant" decoded
  expectErr "carrier rejects digit-first constant name" .badScalar
    (decodeSemanticProgramV1 raw)
  -- Non-NFC bare strings are rejected even by transport decodeString; structure
  -- still independently rejects hand-built non-NFC via the shared Common rule.
  let handNfc : SemanticProgramDataV1 :=
    ← programWithTypes "IdentHandNonNfc" cfgBoolTypes
      #[constOf 0 nfdAcute 0 (ByteArray.mk #[0])]
  expectIdentBad "hand-built non-NFC constant structure" handNfc
  -- encodeString alone would reject non-NFC, but structure validate fails
  -- without needing the program encoder body emission path.
  match validateSemanticProgramStructureV1 handNfc with
  | .error .badScalar => pure ()
  | .error e =>
      throw <| IO.userError
        s!"hand non-NFC structure: expected badScalar, got {repr e}"
  | .ok () =>
      throw <| IO.userError "hand non-NFC structure: expected rejection"

def run : IO Unit := do
  testSchemaMagicConstants
  testEmptyProgramRoundtrip
  testProgramQualifiedNameShape
  testSemanticHash
  testProvenanceEnvelope
  testProvenanceValidateIncompleteBad
  testDigestWireRaw32
  testInvariantsProjectionInvalid
  testMinimalNestedTypeRoundtrip
  testStructureGateIdIndex
  testStructureGateShallowRef
  testRequirementsDomainAndOrder
  testRequirementPredicates
  testNestingLimit
  testDecodeDataNoStructureGate
  testTypeShapePositives
  testTypeShapeNegatives
  testTypeShapeRegressionTransportAndNesting
  testValueBytesPositives
  testValueBytesNegatives
  testValueBytesTransportRegression
  testPrimitiveAnonymousTypeKeyUniqueness
  testRecursiveAnonymousTypeKeyUniqueness
  testCallableKindNamePresence
  testCallableNameUniqueness
  testCallableParameterNameUniqueness
  testCallableEntryViewPresence
  testNamedTypeNameUniqueness
  testNamedTypePrefixRank
  testNamedBodyOptionCycleLegality
  testConstantNameUniqueness
  testLogicalStateNameUniqueness
  testEventNameUniqueness
  testErrorNameUniqueness
  testInterfaceFieldNameUniqueness
  testDeclarationIdentifierNames
  testInitializerCardinality
  testInitializerResultShape
  testInvariantResultShape
  testInvariantParameterShape
  testInvariantDeclarationJoin
  testInvariantLoopBoundsShape
  testNonClosureCallableInvariantSteps
  testInvariantRootStepsPresence
  testInvariantStepsIntrinsicCeiling
  testInvariantStepsExactComputation
  testInvariantRootStateStoreProhibited
  testInvariantRootContextReadProhibited
  testInvariantRootCommitProhibited
  testInvariantRootEmitProhibited
  testInvariantRootExternalCallProhibited
  testInvariantRootScheduleProhibited
  testInvariantPureFnClosureMembership
  testInvariantPureFnClosureDag
  testInvariantClosureCfgBackEdges
  testInvariantClosurePureFnStateLoadProhibited
  testInvariantClosurePureFnStateStoreProhibited
  testInvariantClosurePureFnContextReadProhibited
  testInvariantClosurePureFnCommitProhibited
  testInvariantClosurePureFnEmitProhibited
  testInvariantClosurePureFnExternalCallProhibited
  testInvariantClosurePureFnScheduleProhibited
  testCfgShapeAndReachability
  testCfgSwitchCasesNonempty
  testCfgSwitchCaseValueUniqueness
  testCfgBlockParamArity
  testCfgLoopBounds
  testCfgValueIdSsa
  testCfgValueIdCanonicalAssignment
  testCfgDominanceOfUse
  testCfgBlockParamTypeAndTerminatorTyping
  testCfgOpTyping
  testCfgVoidOpResultPresence
  testCfgValueOpResultPresence
  testCfgFieldSetTyping
  testCfgVariantTagTyping
  testCfgVariantPayloadTyping
  testCfgIndexSetTyping
  testCfgCheckedCastTyping
  testCfgCommitTyping
  testCfgStateStoreTyping
  testCfgAssertTyping
  testCfgRevertTyping
  testCfgEmitTyping
  testCfgExternalCalleeShape
  testCfgContextReadResultTypeConsistency
  testCfgContextReadCatalogRequirements
  testCfgCommitCatalogRequirements
  testCfgEffectIdOrder
  IO.println "Tests.Semantic.WireV1: ok"

end Tests.Semantic.WireV1
