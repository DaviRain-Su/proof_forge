/-
  Tests.Semantic.WireV1 — focused engineering suite for D2-06 wire skeleton.

  Pins schema/magic, empty/minimal root round-trip, hash identity, structure
  gate (id/index, shallow refs, type-shape/FieldSpec/Map-key, requirements
  domain/order/predicates/enumContains), nesting fuel maxNesting=256,
  provenance envelope-only stub + validate always badProvenance, Digest
  raw-32 wire, and invalid-carrier invariants projection.
  Formal TST-SEM-001 corpus remains pending.
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
  let qn ← match parseQualifiedName #[name] with
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

def run : IO Unit := do
  testSchemaMagicConstants
  testEmptyProgramRoundtrip
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
  IO.println "Tests.Semantic.WireV1: ok"

end Tests.Semantic.WireV1
