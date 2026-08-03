import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1
import ProofForgeV2.Semantic.Wire.TypeKeyV1

/-!
  ProofForgeV2.Semantic.Wire.ValueBytesV1 — canonical valueBytes encode/decode/
  validate for Constant / Op.Literal / SwitchCase (SPEC §5).

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-! ### Canonical valueBytes (SPEC-SEM-WIRE-001 §5)

    Type-driven encode/decode/validate shared by Constant, Op.Literal, and
    SwitchCase. Transport decode does not call this. Short/leftover/bad marker/
    range failures are `.nonCanonical` (not `.truncated`/`.trailingBytes`/
    `.badType` when the TypeId/shape is legal). OOR TypeId → `.badReference`.
    Nesting/size/map-count limits → `.limitExceeded`.
-/

private def takeByteNC (c : Cursor) :
    Except SemanticWireErrorV1 (UInt8 × Cursor) := do
  unless remaining c ≥ 1 do
    return ← err .nonCanonical
  pure (c.input.get! c.offset, ⟨c.input, c.offset + 1, c.nesting⟩)

private def takeBytesNC (c : Cursor) (n : Nat) :
    Except SemanticWireErrorV1 (ByteArray × Cursor) := do
  unless remaining c ≥ n do
    return ← err .nonCanonical
  pure (c.input.extract c.offset (c.offset + n), ⟨c.input, c.offset + n, c.nesting⟩)

private def takeU32leNC (c : Cursor) :
    Except SemanticWireErrorV1 (UInt32 × Cursor) := do
  let (b0, c) ← takeByteNC c
  let (b1, c) ← takeByteNC c
  let (b2, c) ← takeByteNC c
  let (b3, c) ← takeByteNC c
  let v := b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat v, c)

private def beBytesToNatV1 (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  for i in [:bytes.size] do
    n := n * 256 + (bytes.get! i).toNat
  pure n

private def leBytesToNatV1 (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  let mut place : Nat := 1
  for i in [:bytes.size] do
    n := n + (bytes.get! i).toNat * place
    place := place * 256
  pure n

/-- `ceil(bitLength(p)/8)` for Field value width (SPEC §5). -/
private def fieldValueByteLengthV1 (modulusBE : ByteArray) : Nat :=
  let p := beBytesToNatV1 modulusBE
  if p == 0 then 0
  else
    let bitLength := Nat.log2 p + 1
    (bitLength + 7) / 8

/-- Spend canonical-value work before continuing traversal or allocation. -/
private def spendCanonicalValueWorkV1 (budget cost : Nat) :
    Except SemanticWireErrorV1 Nat :=
  if cost ≤ budget then pure (budget - cost) else err .limitExceeded

/-- Decode one type-driven value and return its re-encoded canonical bytes and
    remaining cumulative work. Fuel bounds recursive shapes; unlike fuel, work
    is shared by every child and sibling. Each node costs one on entry and its
    own canonical output size (at least one) after its children. -/
private def decodeAndReencodeValueBytesV1 (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel budget : Nat) → (c : Cursor) →
      Except SemanticWireErrorV1 (ByteArray × Cursor × Nat)
  | 0, _, _ => err .limitExceeded
  | fuel + 1, budget, c => do
    let budget ← spendCanonicalValueWorkV1 budget 1
    let (out, c, budget) ←
    match types[typeId.toNat]? with
    | none => err .badReference
    | some decl =>
      match decl.shape with
      | .bool => do
          let (b, c) ← takeByteNC c
          unless b == 0 || b == 1 do
            return ← err .nonCanonical
          pure (encodeU8 b, c, budget)
      | .uint width => do
          let n := width.toNat / 8
          let (raw, c) ← takeBytesNC c n
          pure (raw, c, budget)
      | .int width => do
          let n := width.toNat / 8
          let (raw, c) ← takeBytesNC c n
          pure (raw, c, budget)
      | .principal => do
          let (lenU, c) ← takeU32leNC c
          let len := lenU.toNat
          unless 1 ≤ len && len ≤ maxTypeLengthV1 do
            return ← err .nonCanonical
          let (bodyBytes, c) ← takeBytesNC c len
          pure ((encodeU32le lenU).append bodyBytes, c, budget)
      | .unit =>
          pure (ByteArray.empty, c, budget)
      | .string => do
          -- N4: `u32le(byteLen) || UTF-8` with `0 ≤ byteLen ≤ maxTypeLengthV1`.
          -- Empty string is legal. Body must be valid UTF-8 in NFC form; the
          -- re-encode identity (encodeString ∘ decode) rejects non-NFC and
          -- alternate spellings. Truncation/overlong framing → `.nonCanonical`.
          let (lenU, c) ← takeU32leNC c
          let len := lenU.toNat
          unless len ≤ maxTypeLengthV1 do
            return ← err .nonCanonical
          let (bodyBytes, c) ← takeBytesNC c len
          match String.fromUTF8? bodyBytes with
          | none => err .nonCanonical
          | some s => do
              match requireNfc s with
              | .error _ => err .nonCanonical
              | .ok _ =>
                  -- Re-encode via production encodeString so length header and
                  -- NFC body are the sole canonical spelling.
                  match encodeString s with
                  | .error _ => err .nonCanonical
                  | .ok re =>
                      unless re == (encodeU32le lenU).append bodyBytes do
                        return ← err .nonCanonical
                      pure (re, c, budget)
      | .bytes length => do
          let (raw, c) ← takeBytesNC c length.toNat
          pure (raw, c, budget)
      | .array element length => do
          unless length.toNat ≤ maxTypeLengthV1 do return ← err .limitExceeded
          let mut out := ByteArray.empty
          let mut c := c
          let mut budget := budget
          for _ in [:length.toNat] do
            let (chunk, c', budget') ← decodeAndReencodeValueBytesV1 types element fuel budget c
            out := out.append chunk
            c := c'
            budget := budget'
          pure (out, c, budget)
      | .map keyType valueType => do
          let (countU, c) ← takeU32leNC c
          let count := countU.toNat
          unless count ≤ maxMapEntriesV1 do
            return ← err .limitExceeded
          let mut out := encodeU32le countU
          let mut c := c
          let mut budget := budget
          let mut prevKey? : Option ByteArray := none
          for _ in [:count] do
            let (keyLenU, c1) ← takeU32leNC c
            let keyLen := keyLenU.toNat
            let (keyBytes, c2) ← takeBytesNC c1 keyLen
            let (keyRe, keyC, budget') ←
              decodeAndReencodeValueBytesV1 types keyType fuel budget (start keyBytes)
            budget := budget'
            unless remaining keyC == 0 do
              return ← err .nonCanonical
            unless keyRe == keyBytes do
              return ← err .nonCanonical
            unless keyBytes.size == keyLen do
              return ← err .nonCanonical
            match prevKey? with
            | none => pure ()
            | some prev =>
              match compareByteArrayLex prev keyBytes with
              | .lt => pure ()
              | .eq | .gt => return ← err .nonCanonical
            prevKey? := some keyBytes
            let (valLenU, c3) ← takeU32leNC c2
            let valLen := valLenU.toNat
            let (valBytes, c4) ← takeBytesNC c3 valLen
            let (valRe, valC, budget') ←
              decodeAndReencodeValueBytesV1 types valueType fuel budget (start valBytes)
            budget := budget'
            unless remaining valC == 0 do
              return ← err .nonCanonical
            unless valRe == valBytes do
              return ← err .nonCanonical
            unless valBytes.size == valLen do
              return ← err .nonCanonical
            out :=
              ((out.append (encodeU32le keyLenU)).append keyBytes).append
                ((encodeU32le valLenU).append valBytes)
            c := c4
          pure (out, c, budget)
      | .option element => do
          let (m, c) ← takeByteNC c
          match m.toNat with
          | 0 => pure (encodeU8 0, c, budget)
          | 1 => do
              let (payload, c, budget) ← decodeAndReencodeValueBytesV1 types element fuel budget c
              pure ((encodeU8 1).append payload, c, budget)
          | _ => err .nonCanonical
      | .field spec => do
          let width := fieldValueByteLengthV1 spec.modulusBE
          let (raw, c) ← takeBytesNC c width
          let value := leBytesToNatV1 raw
          let modulus := beBytesToNatV1 spec.modulusBE
          unless value < modulus do
            return ← err .nonCanonical
          pure (raw, c, budget)
      | .struct fields => do
          let mut out := ByteArray.empty
          let mut c := c
          let mut budget := budget
          for f in fields do
            let (chunk, c', budget') ← decodeAndReencodeValueBytesV1 types f.typeId fuel budget c
            out := out.append chunk
            c := c'
            budget := budget'
          pure (out, c, budget)
      | .enum variants => do
          let (idxU, c) ← takeU32leNC c
          let idx := idxU.toNat
          match variants[idx]? with
          | none => err .nonCanonical
          | some variant => do
              let mut out := encodeU32le idxU
              let mut c := c
              let mut budget := budget
              for payloadType in variant.payloadTypes do
                let (chunk, c', budget') ←
                  decodeAndReencodeValueBytesV1 types payloadType fuel budget c
                out := out.append chunk
                c := c'
                budget := budget'
              pure (out, c, budget)
    let budget ← spendCanonicalValueWorkV1 budget (max 1 out.size)
    pure (out, c, budget)

/-- Validate a complete valueBytes slice with an explicit recursive-shape fuel
    budget. Kept private so public callers cannot select a weaker policy; the
    Struct assembler uses it only after reserving the outer Struct level. -/
private def validateValueBytesWithFuelV1 (types : Array TypeDeclV1)
    (typeId : TypeIdV1) (valueBytes : ByteArray) (fuel budget : Nat) :
    Except SemanticWireErrorV1 Nat := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let (reencoded, c, budget) ←
    decodeAndReencodeValueBytesV1 types typeId fuel budget (start valueBytes)
  unless remaining c == 0 do
    return ← err .nonCanonical
  unless reencoded == valueBytes do
    return ← err .nonCanonical
  pure budget

/-- Validate a complete valueBytes slice for `typeId` (full consume + re-encode). -/
def validateValueBytesV1 (types : Array TypeDeclV1) (typeId : TypeIdV1)
    (valueBytes : ByteArray) : Except SemanticWireErrorV1 Unit := do
  let _ ← validateValueBytesWithFuelV1 types typeId valueBytes maxNesting maxCanonicalProgramBytes
  pure ()

/-- Split one complete canonical Struct value into its canonical field byte
    slices. This is the narrow public aggregate-codec seam used by the
    reference machine: the outer Struct consumes one nesting level and every
    field is decoded by the sole type-driven canonical decoder above.
    Non-Struct types, malformed fields, trailing bytes, and oversized values
    fail closed. -/
def splitCanonicalStructValueV1 (types : Array TypeDeclV1)
    (structTypeId : TypeIdV1) (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 (Array ByteArray) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let fields ←
    match types[structTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .struct fields, .. } => pure fields
    | some _ => err .badType
  let mut chunks : Array ByteArray := #[]
  let mut c := start valueBytes
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for field in fields do
    let beginOffset := c.offset
    let (reencoded, c', budget') ←
      decodeAndReencodeValueBytesV1 types field.typeId (maxNesting - 1) budget c
    let source := valueBytes.extract beginOffset c'.offset
    unless reencoded == source do
      return ← err .nonCanonical
    chunks := chunks.push source
    c := c'
    budget := budget'
  unless remaining c == 0 do
    return ← err .nonCanonical
  let _ ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure chunks

/-- Assemble one canonical Struct value from exact source-order canonical
    field byte slices. Each field is validated against its declared TypeId;
    the aggregate cap is checked before allocation growth, and the outer node
    is charged under the same cumulative decoder work policy. -/
def encodeCanonicalStructValueV1 (types : Array TypeDeclV1)
    (structTypeId : TypeIdV1) (fieldBytes : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  let fields ←
    match types[structTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .struct fields, .. } => pure fields
    | some _ => err .badType
  unless fieldBytes.size == fields.size do
    return ← err .nonCanonical
  let mut out := ByteArray.empty
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  let mut i := 0
  while i < fields.size do
    match fields[i]?, fieldBytes[i]? with
    | some field, some bytes =>
        unless bytes.size ≤ maxCanonicalValueBytes - out.size do
          return ← err .limitExceeded
        budget ← validateValueBytesWithFuelV1 types field.typeId bytes
          (maxNesting - 1) budget
        out := out.append bytes
    | _, _ => return ← err .nonCanonical
    i := i + 1
  let _ ← spendCanonicalValueWorkV1 budget (max 1 out.size)
  pure out

/-- Split one complete canonical fixed-length Array value into exactly its
    declared number of canonical element slices. The outer Array reserves one
    nesting level and the sole type-driven decoder performs every split. -/
def splitCanonicalArrayValueV1 (types : Array TypeDeclV1)
    (arrayTypeId : TypeIdV1) (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 (Array ByteArray) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do return ← err .limitExceeded
  let (element, length) ←
    match types[arrayTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .array element length, .. } => pure (element, length.toNat)
    | some _ => err .badType
  unless length ≤ maxTypeLengthV1 do return ← err .limitExceeded
  let mut chunks : Array ByteArray := #[]
  let mut c := start valueBytes
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for _ in [:length] do
    let beginOffset := c.offset
    let (reencoded, c', budget') ←
      decodeAndReencodeValueBytesV1 types element (maxNesting - 1) budget c
    let source := valueBytes.extract beginOffset c'.offset
    unless reencoded == source do return ← err .nonCanonical
    chunks := chunks.push source
    c := c'
    budget := budget'
  unless chunks.size == length && remaining c == 0 do return ← err .nonCanonical
  let _ ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure chunks

/-- Assemble one fixed-length Array from exact canonical element slices,
    checking the canonical value cap before every append and revalidating the
    completed value through the sole decoder. -/
def encodeCanonicalArrayValueV1 (types : Array TypeDeclV1)
    (arrayTypeId : TypeIdV1) (elementBytes : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  let (element, length) ←
    match types[arrayTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .array element length, .. } => pure (element, length.toNat)
    | some _ => err .badType
  unless length ≤ maxTypeLengthV1 do return ← err .limitExceeded
  unless elementBytes.size == length do return ← err .nonCanonical
  let mut out := ByteArray.empty
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for bytes in elementBytes do
    unless bytes.size ≤ maxCanonicalValueBytes - out.size do
      return ← err .limitExceeded
    budget ← validateValueBytesWithFuelV1 types element bytes
      (maxNesting - 1) budget
    out := out.append bytes
  let _ ← spendCanonicalValueWorkV1 budget (max 1 out.size)
  pure out

/-- Canonical Map entry returned by the narrow public Map codec seam. -/
structure CanonicalMapEntryV1 where
  keyBytes   : ByteArray
  valueBytes : ByteArray
  deriving Inhabited

/-- Phase-aware Map mutation failure. Input failures retain their exact Wire
    error; only work/capacity failures after all inputs validate are resources. -/
inductive CanonicalMapUpdateErrorV1 where
  | invalidInput (error : SemanticWireErrorV1)
  | resourceExhausted
  deriving BEq, Repr

private def mapUpdateInputV1 (result : Except SemanticWireErrorV1 α) :
    Except CanonicalMapUpdateErrorV1 α :=
  match result with
  | .ok value => .ok value
  | .error error => .error (.invalidInput error)

private def canonicalMapShapeV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1) :
    Except SemanticWireErrorV1 (TypeIdV1 × TypeIdV1) := do
  match types[mapTypeId.toNat]? with
  | none => err .badReference
  | some { shape := .map key value, .. } =>
      -- Keep Map-key policy owned by Wire rather than duplicating or widening
      -- it in an evaluator.
      checkLegalMapKeyTypeV1 types key types.size
      pure (key, value)
  | some _ => err .badType

private def splitCanonicalMapValueWithBudgetV1 (types : Array TypeDeclV1)
    (mapTypeId : TypeIdV1) (valueBytes : ByteArray) (budget : Nat) :
    Except SemanticWireErrorV1 (Array CanonicalMapEntryV1 × Nat) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do return ← err .limitExceeded
  let (keyType, valueType) ← canonicalMapShapeV1 types mapTypeId
  let mut budget ← spendCanonicalValueWorkV1 budget 1
  let (countU, c0) ← takeU32leNC (start valueBytes)
  let count := countU.toNat
  unless count ≤ maxMapEntriesV1 do return ← err .limitExceeded
  let mut c := c0
  let mut entries : Array CanonicalMapEntryV1 := Array.emptyWithCapacity count
  let mut previous : Option ByteArray := none
  for _ in [:count] do
    let (keyLenU, c1) ← takeU32leNC c
    let (key, c2) ← takeBytesNC c1 keyLenU.toNat
    let (keyRe, keyCursor, budget') ←
      decodeAndReencodeValueBytesV1 types keyType (maxNesting - 1) budget (start key)
    budget := budget'
    unless remaining keyCursor == 0 && keyRe == key do return ← err .nonCanonical
    match previous with
    | some prior =>
        unless compareByteArrayLex prior key == .lt do return ← err .nonCanonical
    | none => pure ()
    previous := some key
    let (valueLenU, c3) ← takeU32leNC c2
    let (value, c4) ← takeBytesNC c3 valueLenU.toNat
    let (valueRe, valueCursor, budget') ←
      decodeAndReencodeValueBytesV1 types valueType (maxNesting - 1) budget (start value)
    budget := budget'
    unless remaining valueCursor == 0 && valueRe == value do return ← err .nonCanonical
    entries := entries.push { keyBytes := key, valueBytes := value }
    c := c4
  unless remaining c == 0 do return ← err .nonCanonical
  budget ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure (entries, budget)

/-- Split and validate one complete canonical Map under a single cumulative
    traversal budget. -/
def splitCanonicalMapValueV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1)
    (valueBytes : ByteArray) : Except SemanticWireErrorV1 (Array CanonicalMapEntryV1) := do
  let (entries, _) ← splitCanonicalMapValueWithBudgetV1 types mapTypeId valueBytes
    maxCanonicalProgramBytes
  pure entries

/-- Wire-owned canonical empty Map encoding. -/
def encodeCanonicalEmptyMapValueV1 (types : Array TypeDeclV1)
    (mapTypeId : TypeIdV1) : Except SemanticWireErrorV1 ByteArray := do
  let _ ← canonicalMapShapeV1 types mapTypeId
  let out := encodeU32le 0
  validateValueBytesV1 types mapTypeId out
  pure out

/-- Lookup an exact canonical key in a canonical Map. Both the map and key are
    validated against their exact TypeIds; ordering/framing remains private. -/
def lookupCanonicalMapValueV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1)
    (mapBytes keyBytes : ByteArray) : Except SemanticWireErrorV1 (Option ByteArray) := do
  let (keyType, _) ← canonicalMapShapeV1 types mapTypeId
  let budget ← validateValueBytesWithFuelV1 types keyType keyBytes (maxNesting - 1)
    maxCanonicalProgramBytes
  let (entries, budget) ←
    splitCanonicalMapValueWithBudgetV1 types mapTypeId mapBytes budget
  let mut budget := budget
  for entry in entries do
    budget ← spendCanonicalValueWorkV1 budget 1
    match compareByteArrayLex entry.keyBytes keyBytes with
    | .eq => return some entry.valueBytes
    | .gt => return none
    | .lt => pure ()
  pure none

/-- Immutable canonical Map upsert. Equal keys replace without count growth;
    otherwise insertion preserves strict unsigned-byte lexicographic order.
    Input validation and mutation resource failures remain distinguishable. -/
def upsertCanonicalMapValueV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1)
    (mapBytes keyBytes valueBytes : ByteArray) :
    Except CanonicalMapUpdateErrorV1 ByteArray := do
  let (keyType, valueType) ← mapUpdateInputV1 (canonicalMapShapeV1 types mapTypeId)
  let budget ← mapUpdateInputV1 <|
    validateValueBytesWithFuelV1 types keyType keyBytes (maxNesting - 1)
      maxCanonicalProgramBytes
  let budget ← mapUpdateInputV1 <|
    validateValueBytesWithFuelV1 types valueType valueBytes (maxNesting - 1) budget
  let (entries, budget) ← mapUpdateInputV1 <|
    splitCanonicalMapValueWithBudgetV1 types mapTypeId mapBytes budget
  let mut budget := budget
  budget ←
    match spendCanonicalValueWorkV1 budget entries.size with
    | .ok updatedBudget => pure updatedBudget
    | .error _ => throw .resourceExhausted
  let replacing := entries.any (fun e => e.keyBytes == keyBytes)
  unless replacing || entries.size < maxMapEntriesV1 do
    throw .resourceExhausted
  let count := if replacing then entries.size else entries.size + 1
  let mut out := encodeU32le (UInt32.ofNat count)
  let appendEntry (out : ByteArray) (key value : ByteArray) :
      Except CanonicalMapUpdateErrorV1 ByteArray := do
    unless key.size ≤ maxCanonicalValueBytes - 8 do throw .resourceExhausted
    let keyFramed := key.size + 8
    unless value.size ≤ maxCanonicalValueBytes - keyFramed do throw .resourceExhausted
    let needed := keyFramed + value.size
    unless needed ≤ maxCanonicalValueBytes - out.size do
      throw .resourceExhausted
    pure ((((out.append (encodeU32le (UInt32.ofNat key.size))).append key).append
      (encodeU32le (UInt32.ofNat value.size))).append value)
  let mut inserted := false
  for entry in entries do
    budget ←
      match spendCanonicalValueWorkV1 budget 1 with
      | .ok updatedBudget => pure updatedBudget
      | .error _ => throw .resourceExhausted
    match compareByteArrayLex entry.keyBytes keyBytes with
    | .lt => out ← appendEntry out entry.keyBytes entry.valueBytes
    | .eq =>
        out ← appendEntry out keyBytes valueBytes
        inserted := true
    | .gt =>
        unless inserted do
          out ← appendEntry out keyBytes valueBytes
          inserted := true
        out ← appendEntry out entry.keyBytes entry.valueBytes
  unless inserted do out ← appendEntry out keyBytes valueBytes
  let _ ←
    match spendCanonicalValueWorkV1 budget (max 1 out.size) with
    | .ok remainingBudget => pure remainingBudget
    | .error _ => throw .resourceExhausted
  pure out

/-- Split one complete canonical Option/Enum value into its constructor tag and
    canonical payload slices. The outer variant reserves one nesting level;
    payloads are decoded by the sole canonical decoder. -/
def splitCanonicalVariantValueV1 (types : Array TypeDeclV1)
    (variantTypeId : TypeIdV1) (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 (UInt32 × Array ByteArray) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let (tag, payloadTypes, payloadOffset) ←
    match types[variantTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .option element, .. } =>
        if valueBytes.size == 0 then err .nonCanonical
        else
          match valueBytes.get! 0 with
          | 0 => pure ((0 : UInt32), #[], 1)
          | 1 => pure ((1 : UInt32), #[element], 1)
          | _ => err .nonCanonical
    | some { shape := .enum variants, .. } => do
        let (tag, c) ← takeU32leNC (start valueBytes)
        match variants[tag.toNat]? with
        | some variant => pure (tag, variant.payloadTypes, c.offset)
        | none => err .nonCanonical
    | some _ => err .badType
  let mut chunks : Array ByteArray := #[]
  let mut c := { start valueBytes with offset := payloadOffset }
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for payloadType in payloadTypes do
    let beginOffset := c.offset
    let (reencoded, c', budget') ←
      decodeAndReencodeValueBytesV1 types payloadType (maxNesting - 1) budget c
    let source := valueBytes.extract beginOffset c'.offset
    unless reencoded == source do return ← err .nonCanonical
    chunks := chunks.push source
    c := c'
    budget := budget'
  unless remaining c == 0 do return ← err .nonCanonical
  let _ ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure (tag, chunks)

/-- Assemble one canonical Option/Enum from an exact constructor tag and exact
    canonical payload slices, checking the cap before every append and finally
    full-consuming/re-encoding the result through the sole value decoder. -/
def encodeCanonicalVariantValueV1 (types : Array TypeDeclV1)
    (variantTypeId : TypeIdV1) (tag : UInt32) (payloadBytes : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  let (headerBytes, payloadTypes) ←
    match types[variantTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .option element, .. } =>
        if tag == 0 then pure (encodeU8 0, #[])
        else if tag == 1 then pure (encodeU8 1, #[element])
        else err .nonCanonical
    | some { shape := .enum variants, .. } =>
        match variants[tag.toNat]? with
        | some variant => pure (encodeU32le tag, variant.payloadTypes)
        | none => err .nonCanonical
    | some _ => err .badType
  unless payloadBytes.size == payloadTypes.size do return ← err .nonCanonical
  let mut out := headerBytes
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  let mut i := 0
  while i < payloadTypes.size do
    match payloadTypes[i]?, payloadBytes[i]? with
    | some payloadType, some bytes =>
        unless bytes.size ≤ maxCanonicalValueBytes - out.size do
          return ← err .limitExceeded
        budget ← validateValueBytesWithFuelV1 types payloadType bytes
          (maxNesting - 1) budget
        out := out.append bytes
    | _, _ => return ← err .nonCanonical
    i := i + 1
  let _ ← spendCanonicalValueWorkV1 budget (max 1 out.size)
  pure out

-- Internal production operation traversal step exposed for refinement. The
-- complete callable valueBytes phase remains `validateCallablesValueBytesV1`.
def validateOpValueBytesV1 (types : Array TypeDeclV1) (op : SemanticOpV1)
    (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  match op with
  | .literal typeId valueBytes =>
      validateValueBytesWithFuelV1 types typeId valueBytes maxNesting budget
  | _ => pure budget

-- Internal production terminator traversal step exposed for refinement. The
-- complete callable valueBytes phase remains `validateCallablesValueBytesV1`.
def validateTerminatorValueBytesV1 (types : Array TypeDeclV1)
    (term : TerminatorV1) (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  match term with
  | .switch _scrutinee cases _default =>
      let mut budget := budget
      for sc in cases do
        budget ← validateValueBytesWithFuelV1 types sc.typeId sc.valueBytes
          maxNesting budget
      pure budget
  | _ => pure budget

/-- A canonical one-byte Bool literal consumes exactly one entry-work unit and
    one output-byte work unit through the sole production valueBytes decoder. -/
theorem validateOpValueBytesV1_literal_bool_eq_ok
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (decl : TypeDeclV1)
    (bit : UInt8) (budget : Nat)
    (hlookup : types[typeId.toNat]? = some decl)
    (hshape : decl.shape = .bool)
    (hbit : bit = 0 ∨ bit = 1)
    (hbudget : 2 ≤ budget) :
    validateOpValueBytesV1 types (.literal typeId (ByteArray.mk #[bit])) budget =
      .ok (budget - 2) := by
  have hentry : 1 ≤ budget := by omega
  have houtput : 1 ≤ budget - 1 := by omega
  have hsize : (ByteArray.mk #[bit]).size = 1 := by rfl
  have hlimit : (ByteArray.mk #[bit]).size ≤ maxCanonicalValueBytes := by
    rw [hsize]
    decide
  have hspendEntry : spendCanonicalValueWorkV1 budget 1 = .ok (budget - 1) := by
    simp [spendCanonicalValueWorkV1, hentry, Pure.pure, Except.pure]
  have htake : takeByteNC (start (ByteArray.mk #[bit])) =
      .ok (bit, ⟨ByteArray.mk #[bit], 1, 0⟩) := by
    rfl
  have hspendOutput : spendCanonicalValueWorkV1 (budget - 1) 1 =
      .ok (budget - 1 - 1) := by
    simp [spendCanonicalValueWorkV1, houtput, Pure.pure, Except.pure]
  have hremaining : remaining ⟨ByteArray.mk #[bit], 1, 0⟩ = 0 := by
    rfl
  have hremainingBeq :
      (remaining ⟨ByteArray.mk #[bit], 1, 0⟩ == 0) = true := by
    rw [hremaining]
    decide
  have hencoded : encodeU8 bit = ByteArray.mk #[bit] := by rfl
  have hbeq : (ByteArray.mk #[bit] == ByteArray.mk #[bit]) = true := by
    rcases hbit with hzero | hone
    · subst bit
      decide
    · subst bit
      decide
  unfold validateOpValueBytesV1 validateValueBytesWithFuelV1
  simp only [Pure.pure, Except.pure, Bind.bind, Except.bind]
  rw [if_pos hlimit, show maxNesting = 255 + 1 by rfl,
    decodeAndReencodeValueBytesV1.eq_2, hspendEntry, hlookup]
  dsimp only
  rw [hshape, htake]
  dsimp only
  simp only [Pure.pure, Except.pure, Bind.bind, Except.bind]
  rw [if_pos (by simpa using hbit), hencoded, hsize,
    show max 1 1 = 1 by rfl, hspendOutput]
  dsimp only
  rw [if_pos hremainingBeq, if_pos hbeq]
  congr 1

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def validateConstantsValueBytesV1 (types : Array TypeDeclV1)
    (constants : Array ConstantV1) (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  let mut budget := budget
  for c in constants do
    budget ← validateValueBytesWithFuelV1 types c.typeId c.valueBytes maxNesting budget
  pure budget

/-- Walk callable blocks for Op.Literal and SwitchCase valueBytes only.
    Does not check CFG reachability, dominance, or ValueId SSA. -/
def validateCallablesValueBytesV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  let mut budget := budget
  for callable in callables do
    for block in callable.blocks do
      for instr in block.instructions do
        budget ← validateOpValueBytesV1 types instr.op budget
      budget ← validateTerminatorValueBytesV1 types block.terminator budget
  pure budget

/-- Two single-block callables each carrying one value-producing op (Normalize
    view+invariant literal-true closure). Composes the sole production walker. -/
theorem validateCallablesValueBytesV1_two_single_op
    (types : Array TypeDeclV1) (c0 c1 : CallableV1)
    (b0 b1 : BlockV1) (i0 i1 : InstructionV1)
    (budget budget1 budget2 : Nat)
    (hB0 : c0.blocks = #[b0]) (hB1 : c1.blocks = #[b1])
    (hI0 : b0.instructions = #[i0]) (hI1 : b1.instructions = #[i1])
    (hT0 : validateTerminatorValueBytesV1 types b0.terminator budget1 = .ok budget1)
    (hT1 : validateTerminatorValueBytesV1 types b1.terminator budget2 = .ok budget2)
    (hOp0 : validateOpValueBytesV1 types i0.op budget = .ok budget1)
    (hOp1 : validateOpValueBytesV1 types i1.op budget1 = .ok budget2) :
    validateCallablesValueBytesV1 types #[c0, c1] budget = .ok budget2 := by
  simp [validateCallablesValueBytesV1, hB0, hB1, hI0, hI1, hOp0, hOp1, hT0, hT1,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

end ProofForgeV2.Semantic.WireV1
