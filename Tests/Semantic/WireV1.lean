/-
  Tests.Semantic.WireV1 — focused engineering suite for D2-06 wire skeleton.

  Pins schema/magic, empty/minimal root round-trip, hash identity, structure
  gate (id/index, shallow refs, type-shape/FieldSpec/Map-key, canonical
  valueBytes for Constant/Op.Literal/SwitchCase, requirements domain/order/
  predicates/enumContains), nesting fuel maxNesting=256, provenance
  envelope-only stub + validate always badProvenance, Digest raw-32 wire,
  and invalid-carrier invariants projection.
  CFG shape/reachability pinned; dominance/ValueId SSA/provenance join/normalizer/product wire still pending.
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

    Per-callable: entryBlock == 0, block id == array index, terminator target
    range, total reachability from entry, jump/branch/switch target arg
    arity == target block params, and loopBounds back-edge coverage
    (exact coverage of every CFG back edge, `(header,backEdgeFrom)` unique
    ascending, maxIterations <= 4096, all `.badCfg`). NOT dominance, ValueId
    SSA, block-param TYPE, or terminator typing (those remain explicitly out
    of scope this slice). -/

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
           cfgInstr (some (cfgValueDef 2)) (.binary .add 0 1) ]
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
  -- N7 undefined use in switch scrutinee: switch 99 [] none (single block,
  --   no back edge, reachability ok).
  let n7 ← programWithTypes "SsaN7UndefSwitchScrut" cfgBoolTypes #[]
    #[cfgCallable #[cfgBlock 0 (.switch 99 #[] none)]]
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
  testValueBytesPositives
  testValueBytesNegatives
  testValueBytesTransportRegression
  testCfgShapeAndReachability
  testCfgBlockParamArity
  testCfgLoopBounds
  testCfgValueIdSsa
  testCfgDominanceOfUse
  IO.println "Tests.Semantic.WireV1: ok"

end Tests.Semantic.WireV1
