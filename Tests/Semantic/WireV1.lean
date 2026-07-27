/-
  Tests.Semantic.WireV1 — focused engineering suite for D2-06 wire skeleton.

  Pins schema/magic, empty/minimal root round-trip, hash identity, structure
  gate (program qualifiedName ≥2 components, id/index, shallow refs,
  type-shape/FieldSpec/Map-key, canonical valueBytes for Constant/Op.Literal/
  SwitchCase, requirements domain/order/
  predicates/enumContains), nesting fuel maxNesting=256, provenance
  envelope-only stub + validate always badProvenance, Digest raw-32 wire,
  and invalid-carrier invariants projection.
  callable kind/name presence, CFG shape/reachability (including Switch
  nonempty/typed-value uniqueness), loop bounds, per-callable EffectId
  assignment, ValueId SSA/use-existence/
  dominance, def-site TypeId range,
  block/terminator typing, and step-j per-op contracts
  are pinned; provenance join/normalizer/product wire remain pending. Step j
  includes the exact CheckedCast contract (UInt/Int source and destination,
  result.typeId == toType), StateStore state lookup/value type/void-result,
  Assert Bool/error/args/void-result, Term.Revert ErrorDecl/args, and Emit
  EventDecl/args/void-result contracts; only ContextRead/Commit remain
  presence-only. Formal TST-SEM-001 corpus remains pending.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1

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

private def zeroDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }

private def oneDigest : Digest :=
  { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (1 : UInt8)) }

private def v1_0_0 : SemVer :=
  { major := 1, minor := 0, patch := 0 }

private def emptyProvenance (name : String) : IO SemanticProvenanceV1 := do
  let qn ← match parseQualifiedName #[name] with
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
  let data ← emptyProgram "EmptySem"
  let bytes ← expectOk "encode empty" (encodeSemanticProgramDataV1 data)
  expect (startsWithMagic bytes semanticProgramMagicV1) "encode starts with program magic"
  let decoded ← expectOk "decode empty" (decodeSemanticProgramDataV1 bytes)
  expect (decoded == data) "decode structural equality"
  let carrier ← expectOk "decodeSemanticProgramV1" (decodeSemanticProgramV1 bytes)
  expect (bytesEqual carrier.canonicalBytes bytes) "carrier bytes identity"
  -- trailing garbage
  expectErr "trailing" .trailingBytes
    (decodeSemanticProgramDataV1 (bytes.push 0))
  -- wrong magic
  let magicLen := semanticProgramMagicV1.toUTF8.size + 1
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
  let two := { single with qualifiedName := twoName }
  let _ ← expectOk "two-component program name structure"
    (validateSemanticProgramStructureV1 two)
  let _ ← expectOk "two-component program name encode"
    (encodeSemanticProgramDataV1 two)
  let threeName ← match parseQualifiedName #["Org", "Example", "Program"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let three := { single with qualifiedName := threeName }
  let _ ← expectOk "three-component program name structure"
    (validateSemanticProgramStructureV1 three)
  let _ ← expectOk "three-component program name encode"
    (encodeSemanticProgramDataV1 three)
  pure ()

private def testSemanticHash : IO Unit := do
  let data1 ← emptyProgram "EmptySem"
  let data2 ← emptyProgram "EmptySem"
  let data3 ← emptyProgram "OtherSem"
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
  let dig ← expectOk "prov digest" (semanticProvenanceDigestV1 p)
  expect (dig == sha256Bytes bytes)
    "provenance digest is envelope-only SHA-256 (not formal join)"
  let badMagic := ("pf.wrong-provenance.v1".toUTF8.push 0).append
    (bytes.extract (semanticProvenanceMagicV1.toUTF8.size + 1) bytes.size)
  expectErr "prov wrong magic" .badMagic (decodeSemanticProvenanceV1 badMagic)

private def testProvenanceValidateAlwaysBad : IO Unit := do
  let p ← emptyProvenance "EmptySem"
  let data ← emptyProgram "EmptySem"
  let bytes ← expectOk "enc prog" (encodeSemanticProgramDataV1 data)
  let carrier ← expectOk "carrier" (decodeSemanticProgramV1 bytes)
  let inv : SourceNodeInventoryV1 := { sourceHash := zeroDigest, nodes := #[] }
  expectErr "validate provenance always bad" .badProvenance
    (validateSemanticProvenanceV1
      p.qualifiedName p.qualifiedName inv carrier p)

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
  let data ← emptyProgram "EmptySem"
  let bytes ← expectOk "enc" (encodeSemanticProgramDataV1 data)
  let carrier ← expectOk "dec" (decodeSemanticProgramV1 bytes)
  expect (SemanticProgramV1.invariants carrier == #[])
    "empty program invariants array is empty"

private def testMinimalNestedTypeRoundtrip : IO Unit := do
  -- Non-empty nested TypeDecl table must fully round-trip (not silent-drop).
  let data0 ← emptyProgram "WithType"
  let data : SemanticProgramDataV1 := {
    data0 with
    types := #[{
      id := 0
      name := none
      shape := .bool
    }]
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
  let data0 ← emptyProgram "Reqs"
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
  let data0 ← emptyProgram "Preds"
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
  let good ← emptyProgram "Transport"
  let bytes ← expectOk "good encode" (encodeSemanticProgramDataV1 good)
  let _ ← expectOk "transport decode good" (decodeSemanticProgramDataV1 bytes)

private def testTypeShapePositives : IO Unit := do
  let data0 ← emptyProgram "TypeShapeOk"
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
  }
  expectOk "widths/lengths structure" (validateSemanticProgramStructureV1 okWidths)
  let _ ← expectOk "widths/lengths encode" (encodeSemanticProgramDataV1 okWidths)
  -- named nonempty struct + enum
  let okNamed : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .uint 32 },
      {
        id := 1
        name := some "Point"
        shape := .struct #[
          { name := "x", typeId := 0 },
          { name := "y", typeId := 0 }
        ]
      },
      {
        id := 2
        name := some "Color"
        shape := .enum #[
          { name := "Red", payloadTypes := #[] },
          { name := "Blue", payloadTypes := #[0] }
        ]
      }
    ]
  }
  expectOk "named struct/enum structure" (validateSemanticProgramStructureV1 okNamed)
  let bytesNamed ← expectOk "named struct/enum encode" (encodeSemanticProgramDataV1 okNamed)
  let _ ← expectOk "named carrier" (decodeSemanticProgramV1 bytesNamed)
  -- exact bn254 field type
  let okField : SemanticProgramDataV1 := {
    data0 with
    types := #[{ id := 0, name := none, shape := .field bn254FrFieldSpecV1 }]
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
  }
  expectOk "map primitive keys structure" (validateSemanticProgramStructureV1 okMapPrim)
  let _ ← expectOk "map primitive keys encode" (encodeSemanticProgramDataV1 okMapPrim)
  -- Map over Struct-of-UInt key
  let okMapStruct : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .uint 32 },
      {
        id := 1
        name := some "Key"
        shape := .struct #[{ name := "a", typeId := 0 }]
      },
      { id := 2, name := none, shape := .bool },
      { id := 3, name := none, shape := .map 1 2 }
    ]
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
  -- duplicate field / variant names
  let badDupField : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .uint 8 },
      {
        id := 1
        name := some "S"
        shape := .struct #[
          { name := "x", typeId := 0 },
          { name := "x", typeId := 0 }
        ]
      }
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
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .option 0 },
      {
        id := 2
        name := some "BadKey"
        shape := .struct #[{ name := "inner", typeId := 1 }]
      },
      { id := 3, name := none, shape := .map 2 0 }
    ]
  }
  expectErr "map struct-of-option key" .badType
    (validateSemanticProgramStructureV1 badMapStructOption)
  expectErr "map struct-of-option key encode" .badType
    (encodeSemanticProgramDataV1 badMapStructOption)
  let badMapStructField : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .field bn254FrFieldSpecV1 },
      {
        id := 1
        name := some "FieldKey"
        shape := .struct #[{ name := "f", typeId := 0 }]
      },
      { id := 2, name := none, shape := .bool },
      { id := 3, name := none, shape := .map 1 2 }
    ]
  }
  expectErr "map struct-of-field key" .badType
    (validateSemanticProgramStructureV1 badMapStructField)
  expectErr "map struct-of-field key encode" .badType
    (encodeSemanticProgramDataV1 badMapStructField)
  let badMapStructMap : SemanticProgramDataV1 := {
    data0 with
    types := #[
      { id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 8 },
      { id := 2, name := none, shape := .map 0 1 },
      {
        id := 3
        name := some "MapKey"
        shape := .struct #[{ name := "m", typeId := 2 }]
      },
      { id := 4, name := none, shape := .map 3 0 }
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

private def programWithTypes (name : String) (types : Array TypeDeclV1)
    (constants : Array ConstantV1 := #[])
    (callables : Array CallableV1 := #[]) : IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  pure { data0 with types, constants, callables }

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
  -- named Struct of two UInt8
  let structTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .uint 8 },
    {
      id := 1
      name := some "Pair"
      shape := .struct #[
        { name := "a", typeId := 0 },
        { name := "b", typeId := 0 }
      ]
    }
  ]
  let structP ← programWithTypes "VBStruct" structTypes
    #[constOf 0 "p" 1 (ByteArray.mk #[0x10, 0x20])]
  expectValueOk "struct two u8" structP
  -- Enum variant 0 empty + variant with UInt8 payload
  let enumTypes : Array TypeDeclV1 := #[
    { id := 0, name := none, shape := .uint 8 },
    {
      id := 1
      name := some "E"
      shape := .enum #[
        { name := "A", payloadTypes := #[] },
        { name := "B", payloadTypes := #[0] }
      ]
    }
  ]
  let enum0 ← programWithTypes "VBEnum0" enumTypes
    #[constOf 0 "a" 1 (u32le 0)]
  let enum1 ← programWithTypes "VBEnum1" enumTypes
    #[constOf 0 "b" 1 ((u32le 1).append (ByteArray.mk #[0x99]))]
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
  -- Empty/minimal still green; provenance still always bad
  let empty ← emptyProgram "VBEmptyStill"
  expectValueOk "empty still" empty
  let p ← emptyProvenance "VBEmptyStill"
  let inv : SourceNodeInventoryV1 := { sourceHash := zeroDigest, nodes := #[] }
  let enc ← expectOk "enc empty" (encodeSemanticProgramDataV1 empty)
  let carrier ← expectOk "carrier empty" (decodeSemanticProgramV1 enc)
  expectErr "provenance still bad" .badProvenance
    (validateSemanticProvenanceV1 p.qualifiedName p.qualifiedName inv carrier p)

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

private def cfgCallableKindName (kind : CallableKindV1) (name : Option String)
    (resultTypeId : TypeIdV1 := 0) : CallableV1 :=
  { (cfgCallable #[cfgBlock 0 (.return_ none)]) with
    kind, name, result := { typeId := resultTypeId, visibility := .public_ } }

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

private def testCfgShapeAndReachability : IO Unit := do
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
  -- Positive 5: empty-callables program still legal (regression).
  let p5 ← programWithTypes "CfgEmpty" cfgBoolTypes
  expectCfgOk "empty callables regression" p5
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
  --   Defines ValueId 0 (branch condition) and ValueIds 2, 3 (jump args,
  --   distinct from block 1/2 params 4,5) in block 0.
  let p2 ← programWithTypes "CfgArityBranch1" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1) ]
        (.branch 0
          (cfgJumpTargetWithArgs 1 #[2])
          (cfgJumpTargetWithArgs 2 #[3])),
      cfgBlockWithParams 1 #[cfgBoolParam 4] (.return_ (some 4)),
      cfgBlockWithParams 2 #[cfgBoolParam 5] (.return_ (some 5))
    ]]
  expectCfgOk "branch arity 1==1" p2
  -- Positive 3: switch case target 1-param (1 arg), default 0-param (0 args).
  --   Defines ValueId 0 (scrutinee) and ValueId 2 (case arg, distinct from
  --   block 1 param 4) in block 0.
  let p3 ← programWithTypes "CfgAritySwitch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0) ]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTargetWithArgs 1 #[2] }]
          (some (cfgJumpTarget 2))),
      cfgBlockWithParams 1 #[cfgBoolParam 4] (.return_ (some 4)),
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

/-! ### ValueId SSA definition-table + exactly-once + use-existence (D2-06 §6.2)

    Implements the 'each ValueId is defined exactly once' portion plus
    use-existence (every used ValueId has a def site). Dominance-of-use,
    block-param TYPE, and terminator typing remain explicitly out of scope
    (later slices). All SSA-def-table failures use `.badCfg`. -/

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
  -- P6 switch scrutinee + case arg: block 0 result 0 := lit, result 1 := lit,
  --   switch scrut 0, case target args #[1]; block 1 param 2 return (some 2);
  --   block 2 return none. Distinct ValueIds 0,1 @ block0 and 2 @ block1.
  let p6 ← programWithTypes "SsaP6Switch" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlockInstrs 0
        #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 0),
           cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1) ]
        (.switch 0
          #[{ typeId := 0, valueBytes := ByteArray.mk #[0],
              target := cfgJumpTargetWithArgs 1 #[1] }]
          (some (cfgJumpTarget 2))),
      cfgBlockWithParams 1 #[cfgBoolParam 2] (.return_ (some 2)),
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
  -- DP4 dominator on only path: block 0 jump 1; block 1 instr result 5 := lit;
  --   block 1 jump 2; block 2 return (some 5). Block 1 dominates block 2
  --   (only path 0→1→2). No back edge → loopBounds := #[].
  let dp4 ← programWithTypes "DomP4OnlyPath" cfgBoolTypes #[]
    #[cfgCallable #[
      cfgBlock 0 (.jump (cfgJumpTarget 1)),
      cfgBlockInstrs 1
        #[cfgInstr (some (cfgValueDef 5)) (cfgBoolLit 0)]
        (.jump (cfgJumpTarget 2)),
      cfgBlock 2 (.return_ (some 5))
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
  --   block 2; block 1 instr result 5 := lit, jump 3; block 2 jump 3;
  --   block 3 return (some 5). Block 1 does NOT dominate block 3
  --   (path 0→2→3 avoids block 1). 5 defined exactly once, use-exists, all
  --   reachable → only dominance fails. Condition uses callable param 0
  --   (defined at entry, dominates all). No back edge.
  let dn1 ← programWithTypes "DomN1ArmDefJoinUse" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[cfgInstr (some (cfgValueDef 5)) (cfgBoolLit 0)]
            (.jump (cfgJumpTarget 3)),
          cfgBlock 2 (.jump (cfgJumpTarget 3)),
          cfgBlock 3 (.return_ (some 5))
        ]]
  expectCfgErr "DN1 def in arm, use at join not dominated" dn1
  -- DN2 def in later block, use in earlier reachable block: block 0 branch
  --   cond(0) → block 1 / block 2; block 1 instr result 6 := unary not 5,
  --   jump 3; block 2 instr result 5 := lit, jump 3; block 3 return none.
  --   ValueId 5 defined exactly once (only in block 2), use-exists, both arms
  --   reachable; block 2 does not dominate block 1 → only dominance fails.
  --   Condition uses callable param 0.
  let dn2 ← programWithTypes "DomN2LaterDefEarlierUse" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[cfgInstr (some (cfgValueDef 6)) (.unary .not 5)]
            (.jump (cfgJumpTarget 3)),
          cfgBlockInstrs 2
            #[cfgInstr (some (cfgValueDef 5)) (cfgBoolLit 0)]
            (.jump (cfgJumpTarget 3)),
          cfgBlock 3 (.return_ none)
        ]]
  expectCfgErr "DN2 later block def, earlier block use not dominated" dn2
  -- DN3 def in non-dominating arm used in sibling arm: block 0 branch cond(0)
  --   → block 1 / block 2; block 1 instr result 5 := lit, return (some 5);
  --   block 2 return (some 5). Block 1 does NOT dominate block 2. 5 defined
  --   once, use-exists, both arms reachable → only dominance fails. Condition
  --   uses callable param 0.
  let dn3 ← programWithTypes "DomN3ArmDefSiblingUse" cfgBoolTypes #[]
    #[cfgCallableWithParams
        #[{ valueId := 0, name := "p", typeId := 0, visibility := .public_ }]
        #[
          cfgBlock 0 (.branch 0 (cfgJumpTarget 1) (cfgJumpTarget 2)),
          cfgBlockInstrs 1
            #[cfgInstr (some (cfgValueDef 5)) (cfgBoolLit 0)]
            (.return_ (some 5)),
          cfgBlock 2 (.return_ (some 5))
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
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7)]
          (.jump (cfgJumpTargetWithArgs 1 #[0])),
         cfgBlockWithParams 1 #[cfgUint8Param 1] (.return_ (some 1))
      ] 1]
  expectCfgOk "P1 jump arg type matches" p1
  -- P2: branch cond Bool + then/else arg types match (Bool cond, UInt8 args).
  let p2 ← programWithTypes "TypP2Branch" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7) ]
          (.branch 0
            (cfgJumpTargetWithArgs 1 #[1])
            (cfgJumpTargetWithArgs 2 #[1])),
         cfgBlockWithParams 1 #[cfgUint8Param 2] (.return_ (some 2)),
         cfgBlockWithParams 2 #[cfgUint8Param 3] (.return_ (some 3))
      ] 1]
  expectCfgOk "P2 branch cond Bool + arg types match" p2
  -- P3: switch scrut Bool + case.typeId Bool + case arg type matches.
  let p3 ← programWithTypes "TypP3Switch" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7) ]
          (.switch 0
            #[{ typeId := 0, valueBytes := ByteArray.mk #[1],
                target := cfgJumpTargetWithArgs 1 #[1] }]
            (some (cfgJumpTargetWithArgs 2 #[1]))),
         cfgBlockWithParams 1 #[cfgUint8Param 2] (.return_ (some 2)),
         cfgBlockWithParams 2 #[cfgUint8Param 3] (.return_ (some 3))
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
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1)]
          (.jump (cfgJumpTargetWithArgs 1 #[0])),
         cfgBlockWithParams 1 #[cfgUint8Param 1] (.return_ (some 1))
      ] 1]
  expectCfgErr "N5 jump arg type != target param type" n5
  -- N6: branch then-arg type mismatch → .badCfg.
  let n6 ← programWithTypes "TypN6BranchThenArg" cfgUint8Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1) ]
          (.branch 0
            (cfgJumpTargetWithArgs 1 #[1])
            (cfgJumpTargetWithArgs 2 #[1])),
         cfgBlockWithParams 1 #[cfgUint8Param 2] (.return_ (some 2)),
         cfgBlockWithParams 2 #[cfgUint8Param 3] (.return_ (some 3))
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
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1) ]
          (.switch 0
            #[{ typeId := 0, valueBytes := ByteArray.mk #[1],
                target := cfgJumpTargetWithArgs 1 #[1] }]
            (some (cfgJumpTargetWithArgs 2 #[1]))),
         cfgBlockWithParams 1 #[cfgUint8Param 2] (.return_ (some 2)),
         cfgBlockWithParams 2 #[cfgUint8Param 3] (.return_ (some 3))
      ] 1]
  expectCfgErr "N8 switch default-target arg type mismatch" n8

/-! ### step j: per-op type/result contract (SPEC-SEM-WIRE-001 §5.1)

    Value-producing ops (literal/constant/stateLoad/construct/fieldGet/
    indexGet/unary/binary/pureCall) must produce a result whose TypeId matches
    the op's type contract, and any ValueId operand types must match the
    declared operand contract. Void/side-effecting ops with `result := none`
    are skipped (no result-type check this slice). All failures → `.badCfg`.
    Uses an 8-type fixture table:
      typeId 0 = Bool, 1 = UInt8, 2 = UInt32, 3 = Option<UInt8>,
      typeId 4 = Struct{a:UInt8, b:UInt8}, 5 = Enum{V(UInt8)},
      typeId 6 = Map<UInt8,UInt8>, 7 = Bytes(4). -/

private def cfgOpTypes : Array TypeDeclV1 :=
  #[{ id := 0, name := none, shape := .bool },
    { id := 1, name := none, shape := .uint 8 },
    { id := 2, name := none, shape := .uint 32 },
    { id := 3, name := none, shape := .option 1 },
    { id := 4, name := some "S",
       shape := .struct #[{ name := "a", typeId := 1 },
                          { name := "b", typeId := 1 }] },
    { id := 5, name := some "E",
       shape := .enum #[{ name := "v", payloadTypes := #[1] }] },
    { id := 6, name := none, shape := .map 1 1 },
    { id := 7, name := none, shape := .bytes 4 }]

/-- Program builder that also accepts logicalState (cfgOpTyping needs a State
    row for stateLoad). -/
private def programWithState (name : String) (types : Array TypeDeclV1)
    (constants : Array ConstantV1) (state : Array StateDeclV1)
    (callables : Array CallableV1) : IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  pure { data0 with types, constants, logicalState := state, callables }

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
  pure { data0 with types, events, callables }

private def programWithErrors (name : String) (types : Array TypeDeclV1)
    (errors : Array ErrorDeclV1) (callables : Array CallableV1) :
    IO SemanticProgramDataV1 := do
  let data0 ← emptyProgram name
  pure { data0 with types, errors, callables }

/-- A second pureFn callable (id 1) with one UInt8 param and UInt8 result,
    for pureCall tests. -/
private def cfgPureFn1 : CallableV1 :=
  {
    id := 1
    kind := .pureFn
    name := some "g"
    params := #[{ valueId := 0, name := "x", typeId := 1,
                  visibility := .public_ }]
    result := { typeId := 1, visibility := .public_ }
    entryBlock := 0
    blocks := #[cfgBlockInstrs 0
      #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1)]
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
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[cfgBlock 0 (.return_ none)]
    loopBounds := #[]
    invariantSteps := none
  }

private def testCfgOpTyping : IO Unit := do
  -- P1: literal result.typeId == op.typeId (UInt8 literal → result UInt8).
  let p1 ← programWithTypes "OpP1Lit" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P1 literal result==typeId" p1
  -- P2: constant load — result.typeId == data.constants[constantId].typeId.
  --   constantId 0 has typeId 1 (UInt8); result ValueDef typeId 1.
  let p2 ← programWithTypes "OpP2Const" cfgOpTypes
    #[constOf 0 "c" 1 (ByteArray.mk #[3])]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (.constant 0)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P2 constant load result==constant.typeId" p2
  -- P3: stateLoad — result.typeId == data.logicalState[stateId].typeId.
  --   stateId 0 has typeId 1 (UInt8); result ValueDef typeId 1.
  let p3 ← programWithState "OpP3State" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (.stateLoad 0)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P3 stateLoad result==state.typeId" p3
  -- P4: construct Struct — constructorIndex 0, 2 UInt8 args, result==4.
  --   Args are ValueIds 1 and 2 defined as UInt8 literals; result ValueId 3
  --   has typeId 4 (the struct type). Operands 1/2 are UInt8 (typeId 1).
  let p4 ← programWithTypes "OpP4ConstructStruct" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.construct 4 0 #[1, 2]) ]
          (.return_ (some 3))
      ] 4]
  expectCfgOk "P4 construct Struct 2 UInt8 args result==struct" p4
  -- P5: fieldGet Struct — base is a constructed Struct at ValueId 1 (typeId 4);
  --   fieldGet 1 1 → result ValueId 2 typeId 1 (fields[1].typeId == UInt8).
  let p5 ← programWithTypes "OpP5FieldGet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (.fieldGet 1 1) ]
          (.return_ (some 2))
      ] 1]
  expectCfgOk "P5 fieldGet Struct fieldIndex 1 result==field.typeId" p5
  -- P6: indexGet Array — base Array<UInt8,2>, index UInt32, result==element.
  --   Dedicated type table: typeId 0 Bool, 1 UInt8, 2 UInt32,
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
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 0 #[10, 11]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (.indexGet 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgOk "P6 indexGet Array UInt32 index result==element" p6
  -- P7: unary not Bool → result Bool. Operand ValueId 1 (Bool, typeId 0);
  --   result ValueId 2 typeId 0 (Bool).
  let p7 ← programWithTypes "OpP7UnaryNot" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
             cfgInstr (some (cfgValueDef 2)) (.unary .not 1) ]
          (.return_ (some 2))
      ] 0]
  expectCfgOk "P7 unary not Bool→Bool" p7
  -- P8: binary add UInt8+UInt8 → UInt8. Operands ValueId 1,2 (UInt8);
  --   result ValueId 3 typeId 1 (UInt8).
  let p8 ← programWithTypes "OpP8BinaryAdd" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr (some (cfgUint8ValueDef 3)) (.binary .add 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgOk "P8 binary add UInt8+UInt8→UInt8" p8
  -- P9: pureCall — callee pureFn (id 1), arg type matches param (UInt8),
  --   result==callee.result.typeId (UInt8). Callable 0 calls Callable 1.
  let p9 ← programWithTypes "OpP9PureCall" cfgOpTypes #[]
    #[ cfgCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 5),
                 cfgInstr (some (cfgUint8ValueDef 2)) (.pureCall 1 #[1]) ]
              (.return_ (some 2))
          ] 1,
      cfgPureFn1 ]
  expectCfgOk "P9 pureCall pureFn arg matches result==callee.result" p9
  -- NEGATIVES (all .badCfg via structure+encode).
  -- N1: construct Struct wrong arg count (1 arg, expects 2).
  let n1 ← programWithTypes "OpN1ConstructArgCount" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.construct 4 0 #[1]) ]
          (.return_ (some 3))
      ] 4]
  expectCfgErr "N1 construct wrong arg count" n1
  -- N2: construct Struct arg type mismatch (arg is Bool, field expects UInt8).
  let n2 ← programWithTypes "OpN2ConstructArgType" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.construct 4 0 #[1, 2]) ]
          (.return_ (some 3))
      ] 4]
  expectCfgErr "N2 construct arg type mismatch" n2
  -- N3: fieldGet on non-struct base (base type UInt8, typeId 1).
  let n3 ← programWithTypes "OpN3FieldGetNonStruct" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (.fieldGet 1 0) ]
          (.return_ (some 2))
      ] 1]
  expectCfgErr "N3 fieldGet on non-struct base" n3
  -- N4: fieldGet fieldIndex OOR (base Struct with 2 fields, fieldIndex 5).
  let n4 ← programWithTypes "OpN4FieldGetOOR" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (.fieldGet 1 5) ]
          (.return_ (some 2))
      ] 1]
  expectCfgErr "N4 fieldGet fieldIndex OOR" n4
  -- N5: indexGet Array wrong index type (UInt8 not UInt32).
  let n5 ← programWithTypes "OpN5IndexGetArrayIdxType" arrTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (.indexGet 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgErr "N5 indexGet Array wrong index type" n5
  -- N6: indexGet Map result not Option<value>. Map<UInt8,UInt8> at typeId 6;
  --   base ValueId 1 typeId 6 (Map) built via construct empty Map
  --   (constructorIndex 0, args #[]); index ValueId 2 (UInt8, typeId 1);
  --   result ValueId 3 declared typeId 1 (UInt8) but the contract requires
  --   the unique Option<value> TypeId (typeId 3 in cfgOpTypes). The declared
  --   result.typeId mismatch → .badCfg.
  let n6 ← programWithTypes "OpN6IndexGetMapResult" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 1, typeId := 6 })
               (.construct 6 0 #[]),
            cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
            cfgInstr (some (cfgUint8ValueDef 3)) (.indexGet 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgErr "N6 indexGet Map result not Option<value>" n6
  -- N7: unary neg on UInt8 (neg requires Int or Field).
  let n7 ← programWithTypes "OpN7UnaryNegUInt8" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (.unary .neg 1) ]
          (.return_ (some 2))
      ] 1]
  expectCfgErr "N7 unary neg on UInt8" n7
  -- N8: binary add operand type mismatch (lhs UInt8, rhs Bool).
  let n8 ← programWithTypes "OpN8BinaryAddMismatch" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (.binary .add 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgErr "N8 binary add operand type mismatch" n8
  -- N9: binary eq result not Bool (declared result.typeId 1 = UInt8, must be Bool).
  let n9 ← programWithTypes "OpN9BinaryEqResult" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr (some (cfgUint8ValueDef 3)) (.binary .eq 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgErr "N9 binary eq result not Bool" n9
  -- N10: binary shift rhs not UInt32 (rhs is UInt8, typeId 1; shl rhs must be UInt32).
  let n10 ← programWithTypes "OpN10BinaryShiftRhs" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (.binary .shl 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgErr "N10 binary shift rhs not UInt32" n10
  -- N11: pureCall non-pureFn callee (callee id 0 is .entry).
  --   Two callables: id 0 entry (callee), id 1 pureFn that calls id 0.
  let n11 ← programWithTypes "OpN11PureCallNonPure" cfgOpTypes #[]
    #[ cfgEntry0,
      { cfgCallableResult
        #[ cfgBlockInstrs 0
            #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 5),
               cfgInstr (some (cfgUint8ValueDef 2)) (.pureCall 0 #[1]) ]
            (.return_ (some 2))
        ] 1 with id := 1 } ]
  expectCfgErr "N11 pureCall non-pureFn callee" n11
  -- N12: pureCall arg type mismatch (callee param UInt8, arg is Bool).
  let n12 ← programWithTypes "OpN12PureCallArgType" cfgOpTypes #[]
    #[ cfgCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
                 cfgInstr (some (cfgUint8ValueDef 2)) (.pureCall 1 #[1]) ]
              (.return_ (some 2))
          ] 1,
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

-- A fresh spurious-result ValueDef at `valueId` with typeId 1 (UInt8, in
-- `cfgOpTypes` range) — registered as a def site by `collectValueTypeDefs`
-- (step h range ok), not used anywhere (use-existence only requires
-- uses→defs), so the ONLY step-j failure is the void-op result-presence.
private def cfgSpuriousVoidResult (valueId : ValueIdV1) : ValueDefV1 :=
  { valueId, typeId := 1 }

private def testCfgVoidOpResultPresence : IO Unit := do
  let calleeName ← cfgCalleeName
  -- POSITIVES (result := none on the void op; expectCfgOk).
  -- P1: StateStore — ValueId 0 (UInt8 lit) exactly matches state type;
  --   state row present (stateId 0). result none, return none.
  let p1 ← programWithState "VoidP1StateStore" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7),
             cfgInstr none (.stateStore 0 0) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P1 stateStore result none" p1
  -- P2: Assert — condition ValueId 0 (Bool lit), assert_ 0 none #[] result none.
  let p2 ← programWithTypes "VoidP2Assert" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.assert_ 0 none #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P2 assert result none" p2
  -- P3: Emit — exact empty EventDecl, result none.
  let p3 ← programWithEvents "VoidP3Emit" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.emit 0 0 #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P3 emit result none" p3
  -- P4: ExternalCall — externalCall 0 calleeName #[] result none.
  let p4 ← programWithTypes "VoidP4ExternalCall" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.externalCall 0 calleeName #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P4 externalCall result none" p4
  -- P5: Schedule — schedule 0 calleeName #[] result none.
  let p5 ← programWithTypes "VoidP5Schedule" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.schedule 0 calleeName #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P5 schedule result none" p5
  -- NEGATIVES (spurious result := some _ on the void op; expectCfgErr .badCfg,
  --   dual path structure+encode). The spurious result ValueDef uses a fresh
  --   ValueId 5 (not used elsewhere) with typeId 1 (UInt8, in range) so
  --   steps a–i all pass and ONLY step j void-op result-presence fails.
  -- N1: StateStore with spurious result some.
  let n1 ← programWithState "VoidN1StateStore" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7),
             cfgInstr (some (cfgSpuriousVoidResult 5)) (.stateStore 0 0) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N1 stateStore spurious result" n1
  -- N2: Assert with spurious result some.
  let n2 ← programWithTypes "VoidN2Assert" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5)) (.assert_ 0 none #[]) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N2 assert spurious result" n2
  -- N3: Emit with valid empty EventDecl and spurious result some.
  let n3 ← programWithEvents "VoidN3Emit" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5)) (.emit 0 0 #[]) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N3 emit spurious result" n3
  -- N4: ExternalCall with spurious result some.
  let n4 ← programWithTypes "VoidN4ExternalCall" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5))
               (.externalCall 0 calleeName #[]) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N4 externalCall spurious result" n4
  -- N5: Schedule with spurious result some.
  let n5 ← programWithTypes "VoidN5Schedule" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr (some (cfgSpuriousVoidResult 5))
               (.schedule 0 calleeName #[]) ]
          (.return_ none)
      ] 0]
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
    five, while ContextRead/Commit remain presence-only. The fixtures here use
    operands/results valid under the current contracts so they continue to
    isolate missing-result behavior. The void rule remains unchanged. -/

private def testCfgValueOpResultPresence : IO Unit := do
  let calleeName ← cfgCalleeName
  -- POSITIVES (result := some _ on each value-producing op; expectCfgOk,
  --   structure+encode dual path). Families with later exact contracts use
  --   operands and result TypeIds valid under those contracts; ContextRead/
  --   Commit remain presence-only. Operands are otherwise defined so that
  --   steps a–i (use-existence, def-site range, dominance, terminator
  --   typing) all pass and this suite isolates result presence.
  -- P1: Literal with result present (typed family — exact typeId already
  --   covered by testCfgOpTyping P1; here re-pinned for the presence slice).
  let p1 ← programWithTypes "PresP1Lit" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P1 literal result present" p1
  -- P2: Constant with result present.
  let p2 ← programWithTypes "PresP2Const" cfgOpTypes
    #[constOf 0 "c" 1 (ByteArray.mk #[3])]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (.constant 0)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P2 constant result present" p2
  -- P3: StateLoad with result present.
  let p3 ← programWithState "PresP3State" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (.stateLoad 0)]
          (.return_ (some 0))
      ] 1]
  expectCfgOk "P3 stateLoad result present" p3
  -- P4: Construct (Struct) with result present.
  let p4 ← programWithTypes "PresP4Construct" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.construct 4 0 #[1, 2]) ]
          (.return_ (some 3))
      ] 4]
  expectCfgOk "P4 construct result present" p4
  -- P5: FieldGet with result present.
  let p5 ← programWithTypes "PresP5FieldGet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (.fieldGet 1 1) ]
          (.return_ (some 2))
      ] 1]
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
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 0 #[10, 11]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (.indexGet 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgOk "P6 indexGet result present" p6
  -- P7: Unary (not Bool) with result present.
  let p7 ← programWithTypes "PresP7Unary" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
             cfgInstr (some (cfgValueDef 2)) (.unary .not 1) ]
          (.return_ (some 2))
      ] 0]
  expectCfgOk "P7 unary result present" p7
  -- P8: Binary (add UInt8) with result present.
  let p8 ← programWithTypes "PresP8Binary" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr (some (cfgUint8ValueDef 3)) (.binary .add 1 2) ]
          (.return_ (some 3))
      ] 1]
  expectCfgOk "P8 binary result present" p8
  -- P9: PureCall with result present.
  let p9 ← programWithTypes "PresP9PureCall" cfgOpTypes #[]
    #[ cfgCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 5),
                 cfgInstr (some (cfgUint8ValueDef 2)) (.pureCall 1 #[1]) ]
              (.return_ (some 2))
          ] 1,
      cfgPureFn1 ]
  expectCfgOk "P9 pureCall result present" p9
  -- P10: FieldSet (deferred family) with result present. base/value are
  --   defined UInt8 literals; result ValueId 3 typeId 1 (in range). Input
  --   typing is NOT checked this slice.
  --   NOTE: FieldSet now carries the full §5.1 contract (base must be a
  --   Struct, fieldIndex in range, type(value) == field.typeId, result.typeId
  --   == type(base)). P10 here re-pins presence with a valid Struct base so
  --   the full FieldSet typing test lives in testCfgFieldSetTyping.
  let p10 ← programWithTypes "PresP10FieldSet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 9),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.fieldSet 1 0 2) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P10 fieldSet result present" p10
  -- P11: VariantTag with result present. NOTE: VariantTag now carries the
  --   full §5.1 contract (base must be Enum/Option, result.typeId == unique
  --   UInt32 TypeId). P11 here re-pins presence with a valid Enum base so
  --   the full VariantTag typing test lives in testCfgVariantTagTyping.
  let p11 ← programWithTypes "PresP11VariantTag" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 0 #[10]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P11 variantTag result present" p11
  -- P12: VariantPayload result present with a valid Option-some base.
  let p12 ← programWithTypes "PresP12VariantPayload" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 1 #[10]),
             cfgInstr (some (cfgUint8ValueDef 2))
               (.variantPayload 1 1 0) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P12 variantPayload result present" p12
  -- P13: IndexSet result present with a valid Map<U8,U8> base and exact
  --   key/value types, so the exact static contract also passes.
  let p13 ← programWithTypes "PresP13IndexSet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 1, typeId := 6 })
               (.construct 6 0 #[]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 4, typeId := 6 })
               (.indexSet 1 2 3) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P13 indexSet result present" p13
  -- P14: CheckedCast with a valid UInt8→UInt8 exact contract and result.
  let p14 ← programWithTypes "PresP14CheckedCast" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (.checkedCast 1 1) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P14 checkedCast result present" p14
  -- P15: ContextRead (deferred family) with result present. The key is a
  --   valid SchemaId; result ValueId 1 typeId 1 (in range).
  let ctxKey ← match parseSchemaId "proof-forge.ctx.k.v1" with
    | .ok k => pure k
    | .error e => throw <| IO.userError s!"parseSchemaId: {e}"
  let p15 ← programWithTypes "PresP15ContextRead" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (.contextRead ctxKey) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P15 contextRead result present" p15
  -- P16: Commit (deferred family) with result present.
  let p16 ← programWithTypes "PresP16Commit" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (.commit 1) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P16 commit result present" p16
  -- NEGATIVES (result := none on each value-producing op; expectCfgErr
  --   .badCfg, structure+encode dual path). Each op's ValueId operands are
  --   defined by a preceding literal-with-result instruction so that steps
  --   a–i all pass and ONLY step j result-presence fails. The terminator
  --   returns none (or a separately-defined ValueId) so terminator typing
  --   and use-existence are unaffected by the missing result.
  -- N1: Literal with result none.
  let n1 ← programWithTypes "PresN1Lit" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr none (cfgUint8Lit 7)]
          (.return_ none)
      ] 0]
  expectCfgErr "N1 literal result none" n1
  -- N2: Constant with result none.
  let n2 ← programWithTypes "PresN2Const" cfgOpTypes
    #[constOf 0 "c" 1 (ByteArray.mk #[3])]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr none (.constant 0)]
          (.return_ none)
      ] 0]
  expectCfgErr "N2 constant result none" n2
  -- N3: StateLoad with result none.
  let n3 ← programWithState "PresN3State" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[cfgInstr none (.stateLoad 0)]
          (.return_ none)
      ] 0]
  expectCfgErr "N3 stateLoad result none" n3
  -- N4: Construct with result none (operands defined first).
  let n4 ← programWithTypes "PresN4Construct" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr none (.construct 4 0 #[1, 2]) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N4 construct result none" n4
  -- N5: FieldGet with result none (base defined first).
  let n5 ← programWithTypes "PresN5FieldGet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr none (.fieldGet 1 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N5 fieldGet result none" n5
  -- N6: IndexGet with result none (base + index defined first).
  let n6 ← programWithTypes "PresN6IndexGet" arrTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 0 #[10, 11]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 1),
             cfgInstr none (.indexGet 1 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N6 indexGet result none" n6
  -- N7: Unary with result none (operand defined first).
  let n7 ← programWithTypes "PresN7Unary" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
             cfgInstr none (.unary .not 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N7 unary result none" n7
  -- N8: Binary with result none (operands defined first).
  let n8 ← programWithTypes "PresN8Binary" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 2),
             cfgInstr none (.binary .add 1 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N8 binary result none" n8
  -- N9: PureCall with result none (arg defined first).
  let n9 ← programWithTypes "PresN9PureCall" cfgOpTypes #[]
    #[ cfgCallableResult
          #[ cfgBlockInstrs 0
              #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 5),
                 cfgInstr none (.pureCall 1 #[1]) ]
              (.return_ none)
          ] 0,
      cfgPureFn1 ]
  expectCfgErr "N9 pureCall result none" n9
  -- N10: FieldSet with result none (presence gate). Uses a valid Struct
  --   base (ValueId 1, typeId 4) and a valid value (UInt8, field 0 type) so
  --   steps a–i and the FieldSet typing preconditions all pass and ONLY the
  --   missing result fails. Isolates the presence gate.
  let n10 ← programWithTypes "PresN10FieldSet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 9),
             cfgInstr none (.fieldSet 1 0 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N10 fieldSet result none" n10
  -- N11: VariantTag with result none. NOTE: VariantTag now carries the full
  --   §5.1 contract; N11 uses a valid Enum base (ValueId 1, typeId 5) so
  --   steps a–i and the VariantTag typing preconditions all pass and ONLY
  --   the missing result fails. Isolates the presence gate.
  let n11 ← programWithTypes "PresN11VariantTag" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 0 #[10]),
             cfgInstr none (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N11 variantTag result none" n11
  -- N12: VariantPayload with a valid Option-some base but result none, so
  --   only the result-presence gate fails.
  let n12 ← programWithTypes "PresN12VariantPayload" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 1 #[10]),
             cfgInstr none (.variantPayload 1 1 0) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N12 variantPayload result none" n12
  -- N13: valid Map<U8,U8> IndexSet with result none, so only the presence
  --   requirement fails.
  let n13 ← programWithTypes "PresN13IndexSet" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 1, typeId := 6 })
               (.construct 6 0 #[]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 2),
             cfgInstr none (.indexSet 1 2 3) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N13 indexSet result none" n13
  -- N14: CheckedCast with result none.
  let n14 ← programWithTypes "PresN14CheckedCast" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr none (.checkedCast 1 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N14 checkedCast result none" n14
  -- N15: ContextRead with result none.
  let n15 ← programWithTypes "PresN15ContextRead" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr none (.contextRead ctxKey) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N15 contextRead result none" n15
  -- N16: Commit with result none.
  let n16 ← programWithTypes "PresN16Commit" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr none (.commit 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N16 commit result none" n16
  -- REGRESSION: the void rule is unchanged — every void family with
  --   result := none remains accepted. (P1–P5 of testCfgVoidOpResultPresence
  --   already pin StateStore/Assert/Emit/ExternalCall/Schedule result none
  --   as expectCfgOk; re-asserted here so the presence slice does not
  --   silently regress the void rule.)
  let r1 ← programWithState "PresRegStateStore" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 7),
             cfgInstr none (.stateStore 0 0) ]
          (.return_ none)
      ] 0]
  expectCfgOk "Reg stateStore result none still accepted" r1
  let r2 ← programWithTypes "PresRegAssert" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.assert_ 0 none #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "Reg assert result none still accepted" r2
  let r3 ← programWithEvents "PresRegEmit" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.emit 0 0 #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "Reg emit result none still accepted" r3
  let r4 ← programWithTypes "PresRegExternalCall" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.externalCall 0 calleeName #[]) ]
          (.return_ none)
      ] 0]
  expectCfgOk "Reg externalCall result none still accepted" r4
  let r5 ← programWithTypes "PresRegSchedule" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
             cfgInstr none (.schedule 0 calleeName #[]) ]
          (.return_ none)
      ] 0]
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
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 9),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.fieldSet 1 0 2) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P1 fieldSet first field result==struct" p1
  -- P2: FieldSet on a later field (index 1). value ValueId 2 (UInt8); result
  --   ValueId 3 typeId 4 (== type(base)).
  let p2 ← programWithTypes "FSetP2LaterField" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 7),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.fieldSet 1 1 2) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P2 fieldSet later field result==struct" p2
  -- NEGATIVES (all .badCfg via structure+encode dual path; operands are
  --   otherwise valid SSA/dominance definitions so each negative isolates
  --   FieldSet typing).
  -- N1: non-Struct base. base is a UInt8 literal (typeId 1), not a Struct.
  let n1 ← programWithTypes "FSetN1NonStructBase" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 9),
             cfgInstr (some { valueId := 3, typeId := 1 })
               (.fieldSet 1 0 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N1 fieldSet non-Struct base" n1
  -- N2: out-of-range fieldIndex. base Struct has 2 fields (indices 0,1);
  --   fieldIndex 2 is OOR. value is a valid UInt8; result typeId 4.
  let n2 ← programWithTypes "FSetN2OORFieldIndex" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 9),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.fieldSet 1 2 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N2 fieldSet out-of-range fieldIndex" n2
  -- N3: wrong value type. base Struct field 0 expects UInt8 (typeId 1) but
  --   value is Bool (typeId 0). result typeId 4 (== type(base)).
  let n3 ← programWithTypes "FSetN3WrongValueType" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
             cfgInstr (some { valueId := 3, typeId := 4 })
               (.fieldSet 1 0 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N3 fieldSet wrong value type" n3
  -- N4: wrong result type. base Struct (typeId 4), field 0 expects UInt8,
  --   value UInt8, but result.typeId is 1 (UInt8) instead of 4 (struct).
  let n4 ← programWithTypes "FSetN4WrongResultType" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
             cfgInstr (some { valueId := 1, typeId := 4 })
               (.construct 4 0 #[10, 11]),
             cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 9),
             cfgInstr (some { valueId := 3, typeId := 1 })
               (.fieldSet 1 0 2) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N4 fieldSet wrong result type" n4

/-- testCfgVariantTagTyping: SPEC-SEM-WIRE-001 §5.1 Op.VariantTag exact
    contract. base ValueId type MUST resolve to a Type.Enum or Type.Option;
    `Instruction.result` MUST be present and its typeId MUST exactly equal
    the unique UInt32 TypeId (resolved via the `uint32TypeId` helper, which
    returns `some` only when exactly one `.uint 32` declaration exists). A
    non-Enum/Option base, a missing UInt32 closure type, a duplicate UInt32
    closure type, or a wrong result type is `.badCfg` via structure+encode
    dual path. Each negative isolates VariantTag typing: operands are
    otherwise valid SSA / dominance definitions and earlier steps pass, so
    only step j VariantTag typing fails. Uses cfgOpTypes (typeId 2 = UInt32,
    typeId 3 = Option<UInt8>, typeId 5 = Enum{v(UInt8)}); N4 uses a custom
    5-type table with a duplicate `.uint 32` declaration. -/
private def testCfgVariantTagTyping : IO Unit := do
  -- POSITIVES
  -- P1: VariantTag on an Enum base. Construct Enum (typeId 5) variant 0
  --   with a UInt8 payload (ValueId 10) → ValueId 1 (typeId 5); VariantTag
  --   1 → result ValueId 2 typeId 2 (the unique UInt32 TypeId).
  let p1 ← programWithTypes "VTagP1Enum" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 0 #[10]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P1 variantTag Enum base result==UInt32" p1
  -- P2: VariantTag on an Option-some base. Construct Option-some (typeId 3,
  --   ctorIdx 1) with a UInt8 (ValueId 10) → ValueId 1 (typeId 3);
  --   VariantTag 1 → result ValueId 2 typeId 2 (UInt32).
  let p2 ← programWithTypes "VTagP2OptionSome" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 1 #[10]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P2 variantTag Option-some base result==UInt32" p2
  -- P3: VariantTag on an Option-none base. Construct Option-none (typeId 3,
  --   ctorIdx 0, no args) → ValueId 1 (typeId 3); VariantTag 1 → result
  --   ValueId 2 typeId 2 (UInt32).
  let p3 ← programWithTypes "VTagP3OptionNone" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 0 #[]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgOk "P3 variantTag Option-none base result==UInt32" p3
  -- NEGATIVES (all .badCfg via structure+encode dual path; operands are
  --   otherwise valid SSA/dominance definitions so each negative isolates
  --   VariantTag typing).
  -- N1: non-Enum/Option base (primitive). base is a UInt8 literal
  --   (typeId 1), not Enum/Option; result typeId 2 (UInt32, in range).
  let n1 ← programWithTypes "VTagN1PrimitiveBase" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N1 variantTag non-Enum/Option base" n1
  -- N2: no UInt32 closure type. Custom type table without a UInt32 shape:
  --   typeId 0 = Bool, 1 = UInt8, 2 = Enum{v(UInt8)} (no UInt32). Construct
  --   Enum (typeId 2) variant 0 with UInt8 → ValueId 1 (typeId 2);
  --   VariantTag 1 → result ValueId 2 typeId 0 (Bool, in range). The
  --   `uint32TypeId` helper returns none → `.badCfg`.
  let noU32Types : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 8 },
      { id := 2, name := some "E",
         shape := .enum #[{ name := "v", payloadTypes := #[1] }] }]
  let n2 ← programWithTypes "VTagN2NoUInt32Type" noU32Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 2 })
               (.construct 2 0 #[10]),
             cfgInstr (some (cfgValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N2 variantTag no UInt32 closure type" n2
  -- N3: wrong result type. base Enum (typeId 5), the unique UInt32 TypeId
  --   is typeId 2, but result.typeId is 1 (UInt8) instead of 2.
  let n3 ← programWithTypes "VTagN3WrongResultType" cfgOpTypes #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 5 })
               (.construct 5 0 #[10]),
             cfgInstr (some (cfgUint8ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N3 variantTag wrong result type" n3
  -- N4: duplicate UInt32 closure type. Custom type table with TWO `.uint 32`
  --   declarations (typeId 2 and typeId 4): typeId 0 = Bool, 1 = UInt8,
  --   2 = UInt32, 3 = Enum{v(UInt8)}, 4 = UInt32 (duplicate). Construct
  --   Enum (typeId 3) variant 0 with UInt8 → ValueId 1 (typeId 3);
  --   VariantTag 1 → result ValueId 2 typeId 2 (one of the UInt32 typeIds,
  --   in range). Because `uint32TypeId` now enforces uniqueness and returns
  --   `none` on a duplicate anonymous `.uint 32` declaration, the
  --   VariantTag contract fails → `.badCfg` (structure+encode dual path).
  --   This pins the uniqueness gate that the prior first-match resolver
  --   silently bypassed.
  let dupU32Types : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 8 },
      { id := 2, name := none, shape := .uint 32 },
      { id := 3, name := some "E",
         shape := .enum #[{ name := "v", payloadTypes := #[1] }] },
      { id := 4, name := none, shape := .uint 32 }]
  let n4 ← programWithTypes "VTagN4DupUInt32Type" dupU32Types #[]
    #[cfgCallableResult
      #[ cfgBlockInstrs 0
          #[ cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
             cfgInstr (some { valueId := 1, typeId := 3 })
               (.construct 3 0 #[10]),
             cfgInstr (some (cfgUInt32ValueDef 2)) (.variantTag 1) ]
          (.return_ none)
      ] 0]
  expectCfgErr "N4 variantTag duplicate UInt32 closure type" n4

/-- SPEC-SEM-WIRE-001 §5.1 `Op.VariantPayload` exact static contract.
    Enum bases require in-range variant/payload indices and return the selected
    payload type. Option bases permit only `(variantIndex=1,payloadIndex=0)` and
    return the element type. Every case drives the real structure gate and
    encoder through `expectCfgOk` / `expectCfgErr`. -/
private def testCfgVariantPayloadTyping : IO Unit := do
  -- P1: Enum variant 0 payload 0 is UInt8, so the result is UInt8.
  let p1 ← programWithTypes "VPayloadP1Enum" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 5 })
              (.construct 5 0 #[10]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 0]
  expectCfgOk "P1 variantPayload Enum payload result" p1
  -- P2: Option-some `(1,0)` returns the Option element UInt8.
  let p2 ← programWithTypes "VPayloadP2Option" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 3 })
              (.construct 3 1 #[10]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 1 0)]
          (.return_ none)] 0]
  expectCfgOk "P2 variantPayload Option-some result" p2
  -- N1: primitive base is neither Enum nor Option.
  let n1 ← programWithTypes "VPayloadN1Primitive" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 0]
  expectCfgErr "N1 variantPayload primitive base" n1
  -- N2: Enum variant index is out of range.
  let n2 ← programWithTypes "VPayloadN2VariantOor" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 5 })
              (.construct 5 0 #[10]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 1 0)]
          (.return_ none)] 0]
  expectCfgErr "N2 variantPayload Enum variant OOR" n2
  -- N3: Enum payload index is out of range.
  let n3 ← programWithTypes "VPayloadN3PayloadOor" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 5 })
              (.construct 5 0 #[10]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 0 1)]
          (.return_ none)] 0]
  expectCfgErr "N3 variantPayload Enum payload OOR" n3
  -- N4: Option-none variant 0 has no payload.
  let n4 ← programWithTypes "VPayloadN4OptionNone" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 3 })
              (.construct 3 0 #[]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 0]
  expectCfgErr "N4 variantPayload Option-none" n4
  -- N5: Option-some permits payload index 0 only.
  let n5 ← programWithTypes "VPayloadN5OptionPayloadOor" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 3 })
              (.construct 3 1 #[10]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 1 1)]
          (.return_ none)] 0]
  expectCfgErr "N5 variantPayload Option payload OOR" n5
  -- N6: selected Enum payload is UInt8 but result is Bool.
  let n6 ← programWithTypes "VPayloadN6WrongResult" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some { valueId := 1, typeId := 5 })
              (.construct 5 0 #[10]),
            cfgInstr (some (cfgValueDef 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 0]
  expectCfgErr "N6 variantPayload wrong result type" n6
  -- N7: an empty Enum variant has no payload index 0.
  let emptyVariantTypes : Array TypeDeclV1 :=
    #[{ id := 0, name := none, shape := .bool },
      { id := 1, name := none, shape := .uint 8 },
      { id := 2, name := some "E",
         shape := .enum #[{ name := "Empty", payloadTypes := #[] }] }]
  let n7 ← programWithTypes "VPayloadN7EmptyVariant" emptyVariantTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 2 })
              (.construct 2 0 #[]),
            cfgInstr (some (cfgUint8ValueDef 2))
              (.variantPayload 1 0 0)]
          (.return_ none)] 0]
  expectCfgErr "N7 variantPayload empty Enum variant" n7

/-- SPEC-SEM-WIRE-001 §5.1 `Op.IndexSet` static type/result contract for
    Array, Bytes, and Map. Runtime index bounds remain an interpreter concern;
    these fixtures drive the real structure+encode gate. -/
private def testCfgIndexSetTyping : IO Unit := do
  let indexSetTypes := cfgOpTypes.push
    { id := 8, name := none, shape := .array 1 2 }
  -- P1: Array<U8,2>, UInt32 index, UInt8 value, Array result.
  let p1 ← programWithTypes "ISetP1Array" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
            cfgInstr (some { valueId := 1, typeId := 8 })
              (.construct 8 0 #[10, 11]),
            cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 0),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 8 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgOk "P1 indexSet Array" p1
  -- P2: Bytes<4>, UInt32 index, UInt8 value, Bytes result.
  let p2 ← programWithTypes "ISetP2Bytes" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 0),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 7 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgOk "P2 indexSet Bytes" p2
  -- P3: Map<U8,U8>, exact key/value, Map result.
  let p3 ← programWithTypes "ISetP3Map" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 6 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgOk "P3 indexSet Map" p3
  -- N1: primitive base is not index-settable.
  let n1 ← programWithTypes "ISetN1Primitive" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 0),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some (cfgUint8ValueDef 4)) (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N1 indexSet primitive base" n1
  -- N2: Array index must be UInt32, not Bool.
  let n2 ← programWithTypes "ISetN2ArrayIndex" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
            cfgInstr (some { valueId := 1, typeId := 8 })
              (.construct 8 0 #[10, 11]),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 8 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N2 indexSet Array wrong index" n2
  -- N3: Array value must equal element type.
  let n3 ← programWithTypes "ISetN3ArrayValue" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 10)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUint8ValueDef 11)) (cfgUint8Lit 2),
            cfgInstr (some { valueId := 1, typeId := 8 })
              (.construct 8 0 #[10, 11]),
            cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 0),
            cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1),
            cfgInstr (some { valueId := 4, typeId := 8 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N3 indexSet Array wrong value" n3
  -- N4: Bytes index must be UInt32.
  let n4 ← programWithTypes "ISetN4BytesIndex" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 7 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N4 indexSet Bytes wrong index" n4
  -- N5: Bytes value must be UInt8.
  let n5 ← programWithTypes "ISetN5BytesValue" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 0),
            cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1),
            cfgInstr (some { valueId := 4, typeId := 7 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N5 indexSet Bytes wrong value" n5
  -- N6: Map index must match key type.
  let n6 ← programWithTypes "ISetN6MapKey" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 6 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N6 indexSet Map wrong key" n6
  -- N7: Map value must match value type.
  let n7 ← programWithTypes "ISetN7MapValue" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
            cfgInstr (some (cfgValueDef 3)) (cfgBoolLit 1),
            cfgInstr (some { valueId := 4, typeId := 6 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N7 indexSet Map wrong value" n7
  -- N8: result type must equal base type.
  let n8 ← programWithTypes "ISetN8WrongResult" indexSetTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 6 })
              (.construct 6 0 #[]),
            cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 1),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some (cfgUint8ValueDef 4)) (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N8 indexSet wrong result type" n8
  -- N9: duplicate anonymous UInt8 declarations make the canonical Bytes
  --   value type ambiguous while all operands/results otherwise match the
  --   first UInt8 row. The structure gate must fail closed.
  let dupU8Types := cfgOpTypes.push
    { id := 8, name := none, shape := .uint 8 }
  let n9 ← programWithTypes "ISetN9DuplicateUInt8" dupU8Types #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgUInt32ValueDef 2)) (cfgUInt32Lit 0),
            cfgInstr (some (cfgUint8ValueDef 3)) (cfgUint8Lit 9),
            cfgInstr (some { valueId := 4, typeId := 7 })
              (.indexSet 1 2 3)]
          (.return_ none)] 0]
  expectCfgErr "N9 indexSet duplicate UInt8 closure type" n9

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
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgUInt32ValueDef 2)) (.checkedCast 1 2)]
          (.return_ none)] 0]
  expectCfgOk "P1 checkedCast UInt to UInt" p1
  -- P2: UInt32 -> Int8.
  let p2 ← programWithTypes "CastP2UIntInt" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUInt32ValueDef 1)) (cfgUInt32Lit 7),
            cfgInstr (some { valueId := 2, typeId := 8 })
              (.checkedCast 1 8)]
          (.return_ none)] 0]
  expectCfgOk "P2 checkedCast UInt to Int" p2
  -- P3: Int8 -> UInt8.
  let p3 ← programWithTypes "CastP3IntUInt" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 8 })
              (.literal 8 (ByteArray.mk #[1])),
            cfgInstr (some (cfgUint8ValueDef 2)) (.checkedCast 1 1)]
          (.return_ none)] 0]
  expectCfgOk "P3 checkedCast Int to UInt" p3
  -- P4: Int8 -> Int32.
  let p4 ← programWithTypes "CastP4IntInt" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 8 })
              (.literal 8 (ByteArray.mk #[0xff])),
            cfgInstr (some { valueId := 2, typeId := 9 })
              (.checkedCast 1 9)]
          (.return_ none)] 0]
  expectCfgOk "P4 checkedCast Int to Int" p4
  -- N1: Bool is not a legal cast source.
  let n1 ← programWithTypes "CastN1BoolSource" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 2)) (.checkedCast 1 1)]
          (.return_ none)] 0]
  expectCfgErr "N1 checkedCast Bool source" n1
  -- N2: Bytes is not a legal cast source.
  let n2 ← programWithTypes "CastN2BytesSource" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some { valueId := 1, typeId := 7 })
              (.literal 7 (ByteArray.mk #[1, 2, 3, 4])),
            cfgInstr (some (cfgUint8ValueDef 2)) (.checkedCast 1 1)]
          (.return_ none)] 0]
  expectCfgErr "N2 checkedCast Bytes source" n2
  -- N3: Bool is not a legal cast destination.
  let n3 ← programWithTypes "CastN3BoolDestination" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgValueDef 2)) (.checkedCast 1 0)]
          (.return_ none)] 0]
  expectCfgErr "N3 checkedCast Bool destination" n3
  -- N4: Bytes is not a legal cast destination.
  let n4 ← programWithTypes "CastN4BytesDestination" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some { valueId := 2, typeId := 7 })
              (.checkedCast 1 7)]
          (.return_ none)] 0]
  expectCfgErr "N4 checkedCast Bytes destination" n4
  -- N5: result.typeId must exactly equal toType.
  let n5 ← programWithTypes "CastN5WrongResult" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgUint8ValueDef 2)) (.checkedCast 1 2)]
          (.return_ none)] 0]
  expectCfgErr "N5 checkedCast wrong result type" n5
  -- N6: toType must resolve to an in-range UInt/Int declaration.
  let n6 ← programWithTypes "CastN6MissingDestination" castTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgUint8ValueDef 2)) (.checkedCast 1 99)]
          (.return_ none)] 0]
  expectCfgErr "N6 checkedCast missing destination type" n6

/-- SPEC-SEM-WIRE-001 §5.1 `Op.StateStore` exact declaration/type contract.
    stateId must resolve, type(value) must equal the selected state.typeId, and
    the instruction remains void (`result := none`). These fixtures drive the
    real structure+encode gate; spurious-result coverage remains in
    `testCfgVoidOpResultPresence`. -/
private def testCfgStateStoreTyping : IO Unit := do
  -- P1: UInt8 value exactly matches UInt8 state.
  let p1 ← programWithState "StoreP1UInt8" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr none (.stateStore 0 1)]
          (.return_ none)] 0]
  expectCfgOk "P1 stateStore UInt8 exact" p1
  -- P2: Bool value exactly matches Bool state.
  let p2 ← programWithState "StoreP2Bool" cfgOpTypes #[]
    #[stateRow 0 "flag" 0]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
            cfgInstr none (.stateStore 0 1)]
          (.return_ none)] 0]
  expectCfgOk "P2 stateStore Bool exact" p2
  -- P3: stateId selects the second declaration, whose type is UInt32.
  let p3 ← programWithState "StoreP3SelectedState" cfgOpTypes #[]
    #[stateRow 0 "flag" 0, stateRow 1 "count" 2]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUInt32ValueDef 1)) (cfgUInt32Lit 7),
            cfgInstr none (.stateStore 1 1)]
          (.return_ none)] 0]
  expectCfgOk "P3 stateStore selected declaration" p3
  -- N1: stateId does not resolve in an empty logicalState table.
  let n1 ← programWithTypes "StoreN1MissingState" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr none (.stateStore 0 1)]
          (.return_ none)] 0]
  expectCfgErr "N1 stateStore missing state" n1
  -- N2: Bool value does not match the selected UInt8 state.
  let n2 ← programWithState "StoreN2WrongValue" cfgOpTypes #[]
    #[stateRow 0 "s" 1]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
            cfgInstr none (.stateStore 0 1)]
          (.return_ none)] 0]
  expectCfgErr "N2 stateStore wrong value type" n2
  -- N3: lookup must use the selected stateId rather than another row's type.
  let n3 ← programWithState "StoreN3WrongSelectedState" cfgOpTypes #[]
    #[stateRow 0 "flag" 0, stateRow 1 "count" 2]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 1),
            cfgInstr none (.stateStore 1 1)]
          (.return_ none)] 0]
  expectCfgErr "N3 stateStore selected type mismatch" n3

/-- SPEC-SEM-WIRE-001 §5.1/§6 `Op.Assert` exact condition/error join.
    condition must be Bool; `errorId = none` requires empty args, while
    `some errorId` must resolve and args must positionally match ErrorDecl
    fields. Assert remains void. Fixtures drive structure+encode dual paths. -/
private def testCfgAssertTyping : IO Unit := do
  -- P1: standard assertion failure form — Bool condition, no error, no args.
  let p1 ← programWithTypes "AssertP1Standard" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr none (.assert_ 0 none #[])]
          (.return_ none)] 0]
  expectCfgOk "P1 assert standard" p1
  -- P2: declared error with two positional args of exact field types.
  let p2 ← programWithErrors "AssertP2Declared" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 1, interfaceField "fatal" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0),
            cfgInstr none (.assert_ 0 (some 0) #[1, 2])]
          (.return_ none)] 0]
  expectCfgOk "P2 assert declared error args" p2
  -- P3: errorId selects the second declaration and its UInt32 field.
  let p3 ← programWithErrors "AssertP3SelectedError" cfgOpTypes
    #[errorRow 0 "Empty" #[],
      errorRow 1 "CountFailure" #[interfaceField "count" 2]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgUInt32ValueDef 1)) (cfgUInt32Lit 7),
            cfgInstr none (.assert_ 0 (some 1) #[1])]
          (.return_ none)] 0]
  expectCfgOk "P3 assert selected error" p3
  -- N1: condition must be Bool, not UInt8.
  let n1 ← programWithTypes "AssertN1Condition" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 0)) (cfgUint8Lit 1),
            cfgInstr none (.assert_ 0 none #[])]
          (.return_ none)] 0]
  expectCfgErr "N1 assert non-Bool condition" n1
  -- N2: errorId none requires args empty.
  let n2 ← programWithTypes "AssertN2StandardArgs" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr none (.assert_ 0 none #[1])]
          (.return_ none)] 0]
  expectCfgErr "N2 assert standard args nonempty" n2
  -- N3: declared errorId must resolve.
  let n3 ← programWithTypes "AssertN3MissingError" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr none (.assert_ 0 (some 0) #[])]
          (.return_ none)] 0]
  expectCfgErr "N3 assert missing error" n3
  -- N4: declared error arg count must equal fields.size.
  let n4 ← programWithErrors "AssertN4Arity" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 1, interfaceField "fatal" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr none (.assert_ 0 (some 0) #[1])]
          (.return_ none)] 0]
  expectCfgErr "N4 assert error arg count" n4
  -- N5: declared error args must match field types positionally.
  let n5 ← programWithErrors "AssertN5ArgType" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 1, interfaceField "fatal" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 1),
            cfgInstr none (.assert_ 0 (some 0) #[1, 2])]
          (.return_ none)] 0]
  expectCfgErr "N5 assert error arg type" n5
  -- N6: lookup must use the selected errorId rather than another row's shape.
  let n6 ← programWithErrors "AssertN6SelectedError" cfgOpTypes
    #[errorRow 0 "FlagFailure" #[interfaceField "flag" 0],
      errorRow 1 "CountFailure" #[interfaceField "count" 2]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 0)) (cfgBoolLit 1),
            cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
            cfgInstr none (.assert_ 0 (some 1) #[1])]
          (.return_ none)] 0]
  expectCfgErr "N6 assert selected error arg type" n6

/-- SPEC-SEM-WIRE-001 §6 `Term.Revert` exact ErrorDecl join. errorId must
    resolve and args must match ErrorDecl fields positionally by exact TypeId.
    Fixtures drive the real structure+encode terminator-typing path. -/
private def testCfgRevertTyping : IO Unit := do
  -- P1: zero-field declared error with no args.
  let p1 ← programWithErrors "RevertP1Empty" cfgOpTypes
    #[errorRow 0 "Failure" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[] (.revert 0 #[])] 0]
  expectCfgOk "P1 revert empty error" p1
  -- P2: two args match ErrorDecl fields in source order.
  let p2 ← programWithErrors "RevertP2Args" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 1, interfaceField "fatal" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0)]
          (.revert 0 #[1, 2])] 0]
  expectCfgOk "P2 revert declared args" p2
  -- P3: errorId selects the second declaration and its UInt32 field.
  let p3 ← programWithErrors "RevertP3Selected" cfgOpTypes
    #[errorRow 0 "Empty" #[],
      errorRow 1 "CountFailure" #[interfaceField "count" 2]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUInt32ValueDef 1)) (cfgUInt32Lit 7)]
          (.revert 1 #[1])] 0]
  expectCfgOk "P3 revert selected error" p3
  -- N1: errorId must resolve.
  let n1 ← programWithTypes "RevertN1MissingError" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[] (.revert 0 #[])] 0]
  expectCfgErr "N1 revert missing error" n1
  -- N2: args count must equal fields.size.
  let n2 ← programWithErrors "RevertN2Arity" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 1, interfaceField "fatal" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7)]
          (.revert 0 #[1])] 0]
  expectCfgErr "N2 revert arg count" n2
  -- N3: args must match field types positionally.
  let n3 ← programWithErrors "RevertN3ArgType" cfgOpTypes
    #[errorRow 0 "Failure" #[interfaceField "code" 1]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0)]
          (.revert 0 #[1])] 0]
  expectCfgErr "N3 revert arg type" n3
  -- N4: lookup must use selected errorId rather than another row's field type.
  let n4 ← programWithErrors "RevertN4Selected" cfgOpTypes
    #[errorRow 0 "FlagFailure" #[interfaceField "flag" 0],
      errorRow 1 "CountFailure" #[interfaceField "count" 2]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0)]
          (.revert 1 #[1])] 0]
  expectCfgErr "N4 revert selected error arg type" n4
  -- N5 (review repair): distinct two-field types supplied in reverse order
  --   must fail, pinning source-order positional matching rather than a
  --   non-positional/multiset check.
  let n5 ← programWithErrors "RevertN5ReversedArgs" cfgOpTypes
    #[errorRow 0 "Failure"
        #[interfaceField "code" 1, interfaceField "fatal" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
            cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 7)]
          (.revert 0 #[1, 2])] 0]
  expectCfgErr "N5 revert reversed positional args" n5

/-- SPEC-SEM-WIRE-001 §5.1 `Op.Emit` exact EventDecl join. eventId must
    resolve and args must match EventDecl fields positionally by exact TypeId;
    Emit remains void. EffectId global numbering is a separate §6 slice. -/
private def testCfgEmitTyping : IO Unit := do
  -- P1: zero-field event with no args.
  let p1 ← programWithEvents "EmitP1Empty" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.return_ none)] 0]
  expectCfgOk "P1 emit empty event" p1
  -- P2: two args match EventDecl fields in source order.
  let p2 ← programWithEvents "EmitP2Args" cfgOpTypes
    #[eventRow 0 "Tick"
        #[interfaceField "count" 1, interfaceField "final" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr (some (cfgValueDef 2)) (cfgBoolLit 0),
            cfgInstr none (.emit 0 0 #[1, 2])]
          (.return_ none)] 0]
  expectCfgOk "P2 emit declared args" p2
  -- P3: eventId selects the second declaration and its UInt32 field.
  let p3 ← programWithEvents "EmitP3Selected" cfgOpTypes
    #[eventRow 0 "Ping" #[],
      eventRow 1 "Count" #[interfaceField "count" 2]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUInt32ValueDef 1)) (cfgUInt32Lit 7),
            cfgInstr none (.emit 0 1 #[1])]
          (.return_ none)] 0]
  expectCfgOk "P3 emit selected event" p3
  -- N1: eventId must resolve.
  let n1 ← programWithTypes "EmitN1MissingEvent" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.return_ none)] 0]
  expectCfgErr "N1 emit missing event" n1
  -- N2: args count must equal fields.size.
  let n2 ← programWithEvents "EmitN2Arity" cfgOpTypes
    #[eventRow 0 "Tick"
        #[interfaceField "count" 1, interfaceField "final" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgUint8ValueDef 1)) (cfgUint8Lit 7),
            cfgInstr none (.emit 0 0 #[1])]
          (.return_ none)] 0]
  expectCfgErr "N2 emit arg count" n2
  -- N3: args must match field types positionally.
  let n3 ← programWithEvents "EmitN3ArgType" cfgOpTypes
    #[eventRow 0 "Tick" #[interfaceField "count" 1]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
            cfgInstr none (.emit 0 0 #[1])]
          (.return_ none)] 0]
  expectCfgErr "N3 emit arg type" n3
  -- N4: lookup must use selected eventId rather than another row's type.
  let n4 ← programWithEvents "EmitN4Selected" cfgOpTypes
    #[eventRow 0 "Flag" #[interfaceField "flag" 0],
      eventRow 1 "Count" #[interfaceField "count" 2]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
            cfgInstr none (.emit 0 1 #[1])]
          (.return_ none)] 0]
  expectCfgErr "N4 emit selected event arg type" n4
  -- N5: distinct field types supplied in reverse order must fail.
  let n5 ← programWithEvents "EmitN5ReversedArgs" cfgOpTypes
    #[eventRow 0 "Tick"
        #[interfaceField "count" 1, interfaceField "final" 0]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr (some (cfgValueDef 1)) (cfgBoolLit 0),
            cfgInstr (some (cfgUint8ValueDef 2)) (cfgUint8Lit 7),
            cfgInstr none (.emit 0 0 #[1, 2])]
          (.return_ none)] 0]
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
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.externalCall 0 qualified #[])]
          (.return_ none)] 0]
  expectCfgOk "P1 externalCall qualified callee" p1
  let p2 ← programWithTypes "CalleeP2Schedule" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.schedule 0 qualified #[])]
          (.return_ none)] 0]
  expectCfgOk "P2 schedule qualified callee" p2
  -- P3: the lower bound is not an exact-two restriction.
  let three ← match parseQualifiedName #["org", "mod", "callee"] with
    | .ok n => pure n
    | .error e => throw <| IO.userError s!"parseQualifiedName: {e}"
  let p3 ← programWithTypes "CalleeP3Three" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.externalCall 0 three #[])]
          (.return_ none)] 0]
  expectCfgOk "P3 externalCall three-component callee" p3
  -- N1/N2: one component is valid for the common carrier but invalid for
  -- ExternalCall/Schedule. expectCfgErr checks structure and encode paths.
  let n1 ← programWithTypes "CalleeN1External" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.externalCall 0 single #[])]
          (.return_ none)] 0]
  expectCfgErr "N1 externalCall single-component callee" n1
  let n2 ← programWithTypes "CalleeN2Schedule" cfgOpTypes #[]
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.schedule 0 single #[])]
          (.return_ none)] 0]
  expectCfgErr "N2 schedule single-component callee" n2

/-- SPEC-SEM-WIRE-001 §6 EffectId assignment: within each callable, every
    Emit/ExternalCall/Schedule instruction must carry the next contiguous
    EffectId in BlockId/instruction order, starting at zero. -/
private def testCfgEffectIdOrder : IO Unit := do
  let calleeName ← cfgCalleeName
  -- P1: all three effect families receive contiguous IDs in one block.
  let p1 ← programWithEvents "EffectP1Families" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[]),
            cfgInstr none (.externalCall 1 calleeName #[]),
            cfgInstr none (.schedule 2 calleeName #[])]
          (.return_ none)] 0]
  expectCfgOk "P1 effectId all families" p1
  -- P2: numbering follows BlockId order across reachable blocks.
  let p2 ← programWithEvents "EffectP2Blocks" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.jump (cfgJumpTarget 1)),
        cfgBlockInstrs 1
          #[cfgInstr none (.schedule 1 calleeName #[])]
          (.return_ none)] 0]
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
    #[cfgCallableResult
      #[cfgBlockInstrs 0 #[cfgInstr none (.emit 1 0 #[])] (.return_ none)] 0]
  expectCfgErr "N1 effectId starts at one" n1
  -- N2: duplicate IDs across effect families are invalid.
  let n2 ← programWithEvents "EffectN2Duplicate" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[]),
            cfgInstr none (.externalCall 0 calleeName #[])]
          (.return_ none)] 0]
  expectCfgErr "N2 effectId duplicate" n2
  -- N3: gaps are invalid even when IDs remain increasing.
  let n3 ← programWithEvents "EffectN3Gap" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[]),
            cfgInstr none (.schedule 2 calleeName #[])]
          (.return_ none)] 0]
  expectCfgErr "N3 effectId gap" n3
  -- N4: later block cannot restart or reverse numbering.
  let n4 ← programWithEvents "EffectN4BlockOrder" cfgOpTypes
    #[eventRow 0 "Ping" #[]]
    #[cfgCallableResult
      #[cfgBlockInstrs 0
          #[cfgInstr none (.emit 0 0 #[])]
          (.jump (cfgJumpTarget 1)),
        cfgBlockInstrs 1
          #[cfgInstr none (.schedule 0 calleeName #[])]
          (.return_ none)] 0]
  expectCfgErr "N4 effectId block order" n4

def run : IO Unit := do
  testSchemaMagicConstants
  testEmptyProgramRoundtrip
  testProgramQualifiedNameShape
  testSemanticHash
  testProvenanceEnvelope
  testProvenanceValidateAlwaysBad
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
  testCallableKindNamePresence
  testInitializerCardinality
  testInitializerResultShape
  testInvariantResultShape
  testCfgShapeAndReachability
  testCfgSwitchCasesNonempty
  testCfgSwitchCaseValueUniqueness
  testCfgBlockParamArity
  testCfgLoopBounds
  testCfgValueIdSsa
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
  testCfgStateStoreTyping
  testCfgAssertTyping
  testCfgRevertTyping
  testCfgEmitTyping
  testCfgExternalCalleeShape
  testCfgEffectIdOrder
  IO.println "Tests.Semantic.WireV1: ok"

end Tests.Semantic.WireV1
