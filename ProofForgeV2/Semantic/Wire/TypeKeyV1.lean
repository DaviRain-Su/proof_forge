import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1
import Std.Data.HashMap

/-!
  ProofForgeV2.Semantic.Wire.TypeKeyV1 — type-shape/FieldSpec/Map-key legality
  and TypeKey phases (named-prefix, primitive leaf, recursive anonymous,
  named-body Option-cycle). Isolated SPEC `typeKey` byte-form encoder is
  pinned here and is not a structure gate.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def checkCallableIdInRange (callableId : CallableIdV1) (callableCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless callableId.toNat < callableCount do
    return ← err .badReference
  pure ()

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def checkTypeShapeRefs (shape : TypeShapeV1) (typeCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  match shape with
  | .array element _length =>
      checkTypeIdInRange element typeCount
  | .map key value => do
      checkTypeIdInRange key typeCount
      checkTypeIdInRange value typeCount
  | .option element =>
      checkTypeIdInRange element typeCount
  | .struct fields =>
      for f in fields do
        checkTypeIdInRange f.typeId typeCount
  | .enum variants =>
      for v in variants do
        for t in v.payloadTypes do
          checkTypeIdInRange t typeCount
  | .bool | .uint _ | .int _ | .principal | .unit | .string | .bytes _ | .field _ =>
      pure ()

/-- Integer widths allowed by SPEC-SEM-WIRE-001 §5. -/
def legalIntegerWidthV1 (width : UInt16) : Bool :=
  width == 8 || width == 16 || width == 32 || width == 64 ||
  width == 128 || width == 256

/-- Closed legal widths used by Normalize multi-width and simple-closure certs. -/
theorem legalIntegerWidthV1_64 : legalIntegerWidthV1 64 = true := by decide
theorem legalIntegerWidthV1_8 : legalIntegerWidthV1 8 = true := by decide
theorem legalIntegerWidthV1_16 : legalIntegerWidthV1 16 = true := by decide
theorem legalIntegerWidthV1_32 : legalIntegerWidthV1 32 = true := by decide
theorem legalIntegerWidthV1_128 : legalIntegerWidthV1 128 = true := by decide
theorem legalIntegerWidthV1_256 : legalIntegerWidthV1 256 = true := by decide

private def checkUniqueIntraTypeNames (names : Array String) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Array String := #[]
  for name in names do
    if seen.any (· == name) then
      return ← err .duplicate
    seen := seen.push name
  pure ()

private def validateFieldSpecCatalogV1 (spec : FieldSpecV1) :
    Except SemanticWireErrorV1 Unit := do
  -- T14 catalog v2: the closed FieldSpec catalog admits three exact (id,
  -- modulusBE) entries (bn254 Fr, BLS12-377 Fr, Goldilocks). No arbitrary
  -- modulus is accepted; a FieldSpec must match one of these exactly.
  unless fieldSpecCatalogV1.any (fun entry =>
      entry.id == spec.id && entry.modulusBE == spec.modulusBE) do
    return ← err .badType
  pure ()

/-- Map key legality (SPEC §5): Bool|UInt|Int|Principal|Bytes|Struct of legal keys.
    Recursion fuel defaults to `types.size`; fuel exhaustion / illegal leaf → `.badType`.
    Out-of-range TypeId is `.badReference` (shallow range still owns that class).
    Internal WireV1-family helper (not a public contract). -/
def checkLegalMapKeyTypeV1 (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel : Nat) → Except SemanticWireErrorV1 Unit
  | 0 => err .badType
  | fuel + 1 => do
    match types[typeId.toNat]? with
    | none => err .badReference
    | some decl =>
      match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .bytes _ =>
          pure ()
      | .struct fields =>
          for f in fields do
            checkLegalMapKeyTypeV1 types f.typeId fuel
      -- String is deliberately not a Map key (N4 engineering decision:
      -- variable-length NFC UTF-8; keep Map-key closure Bool|UInt|Int|Principal|
      -- Bytes|Struct-of-legal-keys).
      | .option _ | .array _ _ | .map _ _ | .enum _ | .unit | .field _ | .string =>
          err .badType

/-- Internal production named rule: `name=some` iff shape is struct|enum
    (SPEC §5). Exposed as a proof/refinement phase, not as a complete type
    validator. -/
def validateTypeDeclNamedRuleV1 (decl : TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  let isNamedShape :=
    match decl.shape with
    | .struct _ | .enum _ => true
    | _ => false
  match decl.name, isNamedShape with
  | some _, true => pure ()
  | none, false => pure ()
  | some _, false | none, true => err .badType

/-- Internal production declaration-shape/catalog phase consumed by
    `validateTypesStructureV1`. This is not a standalone acceptance gate. -/
def validateTypeDeclShapeV1 (decl : TypeDeclV1) (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  validateTypeDeclNamedRuleV1 decl
  match decl.shape with
  | .bool | .principal | .unit | .string | .option _ =>
      pure ()
  | .uint width | .int width =>
      unless legalIntegerWidthV1 width do
        return ← err .badType
  | .bytes length =>
      unless length.toNat ≤ maxTypeLengthV1 do
        return ← err .badType
  | .array _ length =>
      unless length.toNat ≤ maxTypeLengthV1 do
        return ← err .badType
  | .field spec =>
      validateFieldSpecCatalogV1 spec
  | .struct fields =>
      if fields.isEmpty then
        return ← err .badType
      checkUniqueIntraTypeNames (fields.map (·.name))
  | .enum variants =>
      if variants.isEmpty then
        return ← err .badType
      checkUniqueIntraTypeNames (variants.map (·.name))
  | .map key _value =>
      checkLegalMapKeyTypeV1 types key types.size

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def validateTypesStructureV1 (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  for decl in types do
    validateTypeDeclShapeV1 decl types
  pure ()

/-- SPEC §5 named TypeDecl contiguous-prefix rank: all `name=some` named
    Struct/Enum declarations must occupy a contiguous prefix of the `types`
    table (indices `0 .. namedCount-1`). Any named declaration appearing
    after an anonymous declaration is `.nonCanonical`. This is the
    `namedPrefix` subphase of `validateTypeKeyPhasesV1`, ordered before the
    `primitiveLeaf` and `recursiveAnonymous` subphases; it shares the public
    `.nonCanonical` wire error while the phase seam makes precedence
    observable. Runs only after table id/index, shallow reference range, and
    type-shape/Map-key legality succeed. Named-name uniqueness, canonical
    valueBytes, callable signature, and requirements are later successors.
    The SPEC canonical anonymous sort/rank bytes and usage closure remain
    deferred; named-body cycle legality is now enforced by a later
    `namedBodyCycle` subphase (after `recursiveAnonymous`), not here. The
    scan is a single forward pass with
    O(n) time and O(1) extra space: once an anonymous declaration is seen, a
    `seenAnonymous` flag is set and any subsequent `name=some` declaration is
    rejected. -/
-- Internal production named-prefix TypeKey subphase exposed for refinement.
-- The complete TypeKey gate remains `validateTypeKeyPhasesV1`.
def validateNamedPrefixRankV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let mut seenAnonymous := false
  for decl in types do
    match decl.name with
    | some _ =>
      if seenAnonymous then
        return ← err .nonCanonical
    | none =>
      seenAnonymous := true
  pure ()

/-- Leaf primitive anonymous TypeKeys are structurally interned (SPEC §5):
    Bool, width-specific UInt/Int, Principal, Unit, length-specific Bytes, and
    the exact catalog Field shape each have at most one TypeId. Their existing
    canonical TypeShape wire is injective for this leaf subset, so an
    exhaustive pair scan for at most three keys, otherwise a private byte sort
    plus adjacent comparison, detects duplicates without changing public table
    order. This is
    the `primitiveLeaf` subphase of `validateTypeKeyPhasesV1`, ordered before
    the `recursiveAnonymous` subphase; both report the same public
    `.nonCanonical` wire error while the phase seam makes precedence
    observable. Full anonymous rank/reachability remains pending. Runs only
    after every declaration shape/catalog check succeeds. -/
-- Internal production primitive-leaf TypeKey subphase exposed for refinement.
-- The complete TypeKey gate remains `validateTypeKeyPhasesV1`.
def collectPrimitiveAnonymousTypeKeysV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 (Array ByteArray) := do
  let mut keys : Array ByteArray := #[]
  for decl in types do
    let isPrimitive := match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .unit | .string | .bytes _ | .field _ => true
      | .array _ _ | .map _ _ | .option _ | .struct _ | .enum _ => false
    if isPrimitive then
      keys := keys.push (← encodeTypeShapeV1 decl.shape)
  pure keys

/-- Small-table branch of the production primitive TypeKey uniqueness scan. -/
@[simp] def validatePrimitiveAnonymousTypeKeysSmallV1
    (keys : Array ByteArray) : Except SemanticWireErrorV1 Unit := do
  if compareByteArrayLex keys[0]! keys[1]! == .eq then
    return ← err .nonCanonical
  if keys.size == 3 then
    if compareByteArrayLex keys[0]! keys[2]! == .eq then
      return ← err .nonCanonical
    if compareByteArrayLex keys[1]! keys[2]! == .eq then
      return ← err .nonCanonical
  pure ()

/-- Three pairwise-distinct encoded primitive keys pass the exact production
    small-table branch. -/
theorem validatePrimitiveAnonymousTypeKeysSmallV1_three_eq_ok
    (k0 k1 k2 : ByteArray)
    (h01 : (compareByteArrayLex k0 k1 == .eq) = false)
    (h02 : (compareByteArrayLex k0 k2 == .eq) = false)
    (h12 : (compareByteArrayLex k1 k2 == .eq) = false) :
    validatePrimitiveAnonymousTypeKeysSmallV1 #[k0, k1, k2] = .ok () := by
  simp [validatePrimitiveAnonymousTypeKeysSmallV1, h01, h02, h12,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Allocation-backed branch of the same production primitive-key scan. It is
    named separately so small-table certificates do not elaborate or replay
    the unreachable sort/loop proof term. -/
def validatePrimitiveAnonymousTypeKeysLargeV1
    (keys : Array ByteArray) : Except SemanticWireErrorV1 Unit := do
  let sorted := keys.qsort fun left right =>
    compareByteArrayLex left right == .lt
  let mut index : Nat := 1
  while index < sorted.size do
    if compareByteArrayLex sorted[index - 1]! sorted[index]! == .eq then
      return ← err .nonCanonical
    index := index + 1
  pure ()

/-- Production primitive anonymous TypeKey uniqueness scan, composed from the
    exact collection, small-table, and allocation-backed branches above. -/
def validatePrimitiveAnonymousTypeKeyUniquenessV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let keys ← collectPrimitiveAnonymousTypeKeysV1 types
  -- Zero/one key is unique by construction. Besides avoiding unnecessary
  -- sorting work, this keeps the minimal closed proof subject on transparent
  -- collection operations only.
  if keys.size ≤ 1 then return
  -- Keep the small-table path transparent and allocation-free: at most three
  -- unordered pairs are checked with the same production byte comparator.
  -- All keys have already been encoded, preserving encoding-error precedence.
  if keys.size ≤ 3 then
    validatePrimitiveAnonymousTypeKeysSmallV1 keys
  else
    validatePrimitiveAnonymousTypeKeysLargeV1 keys

/-- Compose the exact production collector and small-table branch for three
    pairwise-distinct primitive keys. -/
theorem validatePrimitiveAnonymousTypeKeyUniquenessV1_collect_three_eq_ok
    (types : Array TypeDeclV1) (k0 k1 k2 : ByteArray)
    (hcollect : collectPrimitiveAnonymousTypeKeysV1 types = .ok #[k0, k1, k2])
    (h01 : (compareByteArrayLex k0 k1 == .eq) = false)
    (h02 : (compareByteArrayLex k0 k2 == .eq) = false)
    (h12 : (compareByteArrayLex k1 k2 == .eq) = false) :
    validatePrimitiveAnonymousTypeKeyUniquenessV1 types = .ok () := by
  simp [validatePrimitiveAnonymousTypeKeyUniquenessV1, hcollect,
    validatePrimitiveAnonymousTypeKeysSmallV1, h01, h02, h12,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Fixed-size internal structural-class signature builder (SPEC §5
    engineering subset). This is **not** the SPEC canonical unsigned-
    lexicographic anonymous TypeKey/ranking bytes; that ranking/order is a
    separate normalizer concern and remains deferred. The SPEC `typeKey`
    byte form is pinned by the isolated encoder at the bottom of this
    module and is not consumed here. The signature is a
    deterministic, injective, fixed-size byte encoding used only for exact
    structural-class equality and interning, so the per-TypeId state stays
    constant size regardless of recursion depth (avoiding the Θ(n²)
    nested-byte expansion of inlining full child structural keys). Tag framing
    follows the SPEC `typeKey` shape: `u16le(tagLen) || tag || u32le(fieldCount)
    || concat(u32le(fieldLen) || field)`; the Field SchemaId field uses
    canonical length-prefixed UTF-8 bytes (`u32le len || utf8`) matching
    `encodeString` framing (the outer field length wraps it again).

    Signatures are:
    · primitive leaves: tag + exact shape params (uint/int width, bytes
      length, field SchemaId + modulusBE);
    · named Struct/Enum: `tag("named", [u32le reservedId])` — a terminal
      anchor that does not recurse into the named body, so two same-shape
      named declarations keep distinct reserved identity;
    · anonymous `.array`/`.map`/`.option`: tag + child **structural class
      IDs** (not final child TypeIds, not nested child keys) plus the
      container's own shape params (Array length). Two different child TypeIds
      whose reachable structure is identical receive the same child class ID
      and therefore the same container signature/class. -/
private def structuralClassSignatureTag (tag : String)
    (fields : Array ByteArray) : ByteArray := Id.run do
  let tagBytes := tag.toUTF8
  let tagLen := encodeU16le (UInt16.ofNat tagBytes.size)
  let fieldCount := encodeU32le (UInt32.ofNat fields.size)
  let mut out := (tagLen.append tagBytes).append fieldCount
  for field in fields do
    out := out.append ((encodeU32le (UInt32.ofNat field.size)).append field)
  pure out

private def lengthPrefixedUtf8 (s : String) : ByteArray :=
  let raw := s.toUTF8
  (encodeU32le (UInt32.ofNat raw.size)).append raw

/-- Fixed-size signature for a terminal (non-anonymous-container) node. Named
    Struct/Enum and primitive leaves resolve here without recursion. -/
private def terminalStructuralSignature (decl : TypeDeclV1) : ByteArray :=
  match decl.shape with
  | .bool => structuralClassSignatureTag "bool" #[]
  | .uint w => structuralClassSignatureTag "uint" #[encodeU16le w]
  | .int w => structuralClassSignatureTag "int" #[encodeU16le w]
  | .principal => structuralClassSignatureTag "principal" #[]
  | .unit => structuralClassSignatureTag "unit" #[]
  | .string => structuralClassSignatureTag "string" #[]
  | .bytes len => structuralClassSignatureTag "bytes" #[encodeU32le len]
  | .field spec =>
      structuralClassSignatureTag "field"
        #[lengthPrefixedUtf8 spec.id.value, spec.modulusBE]
  | .struct _ | .enum _ =>
      -- Named Struct/Enum: terminal anchor keyed by reserved TypeId only.
      structuralClassSignatureTag "named" #[encodeU32le (UInt32.ofNat decl.id.toNat)]
  | _ => structuralClassSignatureTag "unknown" #[]

/-- Children TypeIds that an anonymous container recurses through. Named
    Struct/Enum and primitive leaves have no recursive children: their
    signature is terminal. -/
private def anonymousContainerChildren (shape : TypeShapeV1) :
    Option (Array TypeIdV1) :=
  match shape with
  | .array element _ => some #[element]
  | .map key value => some #[key, value]
  | .option element => some #[element]
  | _ => none

/-- Compose a fixed-size anonymous-container signature from black children's
    structural class IDs plus the container's own shape params. The signature
    is constant-size (tag + one u32 per child class ID + Array length); it
    never inlines nested child keys. -/
private def anonymousContainerSignature (shape : TypeShapeV1)
    (childClassIds : Array UInt32) : ByteArray := Id.run do
  match shape with
  | .array _ length =>
      let mut fieldBytes : Array ByteArray := #[]
      for cid in childClassIds do fieldBytes := fieldBytes.push (encodeU32le cid)
      fieldBytes := fieldBytes.push (encodeU32le length)
      pure (structuralClassSignatureTag "array" fieldBytes)
  | .map _ _ =>
      let mut fieldBytes : Array ByteArray := #[]
      for cid in childClassIds do fieldBytes := fieldBytes.push (encodeU32le cid)
      pure (structuralClassSignatureTag "map" fieldBytes)
  | .option _ =>
      let mut fieldBytes : Array ByteArray := #[]
      for cid in childClassIds do fieldBytes := fieldBytes.push (encodeU32le cid)
      pure (structuralClassSignatureTag "option" fieldBytes)
  | _ => pure (structuralClassSignatureTag "unknown" #[])

/-- Is this TypeDecl a named Struct/Enum (terminal structural anchor)? -/
private def isNamedStructOrEnum (decl : TypeDeclV1) : Bool :=
  match decl.shape with
  | .struct _ | .enum _ => decl.name.isSome
  | _ => false

/-- Compute a structural class ID per TypeId (SPEC §5 engineering subset).
    Each TypeId receives a fixed-size structural-class signature:
    · primitive leaves and named Struct/Enum get a terminal signature;
    · anonymous `.array`/`.map`/`.option` get a signature built from their
      children's already-computed structural class IDs (not final child
      TypeIds), so two structurally-equivalent child graphs receive the same
      child class ID and the same container class. Identical signatures are
    interned to a single sequential class ID via a `Std.HashMap` used only for
    lookup/insert (never iterated); hash collisions are resolved by exact
    byte equality (`ByteArray.instBEq`), so distinct signatures never collapse.

    Anonymous-container cycle rejection (SPEC §5): a bounded iterative DFS
    over the types table assigns each TypeId a memoized class ID. Only
    anonymous containers are marked in-progress (gray); primitive leaves and
    named anchors resolve to a terminal signature and become black without
    recursion, so reaching a gray node is always an anonymous-container cycle
    with no named anchor, rejected as `.nonCanonical`. Each node is entered
    and exited at most once (memoization short-circuits re-entry to black);
    there are no nested structural rescans — the DFS visits each node a
    constant number of times and class materialization is one bounded linear
    pass. This class computation uses expected `O(n)` time and `O(n)` space
    (one HashMap lookup/insert per node, constant-size signature composition);
    the consuming validator separately collects class IDs linearly and sorts
    them in `O(n log n)`. There is no host map iteration, unbounded recursion,
    stack-depth risk (explicit stack array), or nested-byte expansion.

    Prerequisites: the production caller has already validated table IDs,
    shallow references, type shapes/FieldSpec/Map-key legality, and primitive
    leaf uniqueness. This helper defensively rejects OOR/cycles but does not
    replace those earlier structure phases.

    Scope: this helper rejects only anonymous-container cycles that pass
    through no named anchor. It does not itself enforce the named-body
    `Option`-cycle condition; a later `namedBodyCycle` subphase removes every
    `Option` node and requires the induced TypeId graph to be acyclic, and
    together with this helper that closes the complete SPEC §5 cycle
    condition (every recursive cycle passes simultaneously through a
    reserved named key and an `Option`). Runs after leaf
    primitive interning. -/
def computeStructuralTypeClassIdsV1 (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 (Array UInt32) := do
  let n := types.size
  let mut color : Array Nat := Array.replicate n 0
  let mut classIds : Array (Option UInt32) := Array.replicate n none
  let mut classes : Std.HashMap ByteArray UInt32 :=
    Std.HashMap.emptyWithCapacity n
  let mut nextClass : UInt32 := 0
  let mut stack : Array (Nat × Nat) := #[]
  let mut root := 0
  while h : root < n do
    if color[root]! == 0 then
      stack := stack.push (0, root)
      while stack.isEmpty == false do
        let (kind, tid) := stack.back!
        stack := stack.pop
        if kind == 1 then
          -- exit: compose anonymous-container signature from black child
          -- class IDs and intern to a class ID.
          match types[tid]? with
          | none => return ← err .badReference
          | some decl =>
            match anonymousContainerChildren decl.shape with
            | none => pure ()
            | some childIds =>
              let mut childClasses : Array UInt32 := #[]
              let mut missing := false
              let mut ci := 0
              while h2 : ci < childIds.size do
                let cid := childIds[ci]
                match classIds[cid.toNat]? with
                | some (some cls) => childClasses := childClasses.push cls
                | _ => missing := true
                ci := ci + 1
              if missing then return ← err .nonCanonical
              let sig := anonymousContainerSignature decl.shape childClasses
              let (existing, updated) := classes.getThenInsertIfNew? sig nextClass
              let cls := existing.getD nextClass
              classes := updated
              if existing.isNone then nextClass := nextClass + 1
              classIds := classIds.set! tid (some cls)
              color := color.set! tid 2
        else
          -- enter
          match color[tid]! with
          | 2 => pure ()  -- memoized
          | 1 => return ← err .nonCanonical  -- anonymous-container cycle
          | _ =>
            match types[tid]? with
            | none => return ← err .badReference
            | some decl =>
              if isNamedStructOrEnum decl then
                let sig := terminalStructuralSignature decl
                let (existing, updated) := classes.getThenInsertIfNew? sig nextClass
                let cls := existing.getD nextClass
                classes := updated
                if existing.isNone then nextClass := nextClass + 1
                classIds := classIds.set! tid (some cls)
                color := color.set! tid 2
              else match anonymousContainerChildren decl.shape with
                | none =>
                  let sig := terminalStructuralSignature decl
                  let (existing, updated) := classes.getThenInsertIfNew? sig nextClass
                  let cls := existing.getD nextClass
                  classes := updated
                  if existing.isNone then nextClass := nextClass + 1
                  classIds := classIds.set! tid (some cls)
                  color := color.set! tid 2
                | some childIds =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  let mut ci := childIds.size
                  while h3 : ci > 0 do
                    ci := ci - 1
                    stack := stack.push (0, (childIds[ci]!).toNat)
    root := root + 1
  -- Materialize the per-TypeId class ID array (every node is black here).
  let mut out : Array UInt32 := Array.replicate n 0
  let mut i := 0
  while h : i < n do
    match classIds[i]? with
    | some (some cls) => out := out.set! i cls
    | _ => return ← err .nonCanonical
    i := i + 1
  pure out

/-- Recursive anonymous structural-class uniqueness (SPEC §5). Anonymous
    `.array`/`.map`/`.option` are interned by exact recursive child structural
    class identity, not by final child TypeId. Two anonymous containers with
    structurally-equivalent child graphs receive the same structural class;
    a duplicate anonymous container class is rejected as `.nonCanonical`.
    Anonymous-container cycles that pass through no named anchor are rejected
    during class computation (`.nonCanonical`). This helper does not itself
    enforce the named-body `Option`-cycle condition; a later `namedBodyCycle`
    subphase closes the complete SPEC §5 cycle condition. This is the
    `recursiveAnonymous` subphase of
    `validateTypeKeyPhasesV1`, ordered after the `primitiveLeaf` subphase and
    before `namedBodyCycle`; all three report the same public `.nonCanonical`
    wire error while the phase seam makes precedence observable. Runs after
    leaf primitive interning and
    before named-name/canonical-value/signature/requirement phases. -/
-- Internal production recursive-anonymous TypeKey subphase exposed for
-- refinement. The complete TypeKey gate remains `validateTypeKeyPhasesV1`.
def validateRecursiveAnonymousTypeKeyUniquenessV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  -- Without an anonymous container there is no recursive class to compare or
  -- anonymous-only cycle to detect. Avoid constructing the runtime HashMap on
  -- this mathematically empty path; full programs retain the existing logic.
  let hasAnonymousContainer := types.any fun decl =>
    match decl.shape with
    | .array _ _ | .map _ _ | .option _ => true
    | _ => false
  if !hasAnonymousContainer then return
  let classIds ← computeStructuralTypeClassIdsV1 types
  -- Collect anonymous container class IDs and reject duplicates via a
  -- private sort + adjacent comparison. Public table order is unchanged.
  let mut anonClasses : Array UInt32 := #[]
  let mut i := 0
  while i < types.size do
    match types[i]? with
    | some decl =>
      match decl.shape with
      | .array _ _ | .map _ _ | .option _ =>
        anonClasses := anonClasses.push (classIds[i]!)
      | _ => pure ()
    | none => pure ()
    i := i + 1
  let sorted := anonClasses.qsort fun a b => a < b
  let mut j := 1
  while j < sorted.size do
    if sorted[j - 1]! == sorted[j]! then
      return ← err .nonCanonical
    j := j + 1
  pure ()

/-- The production recursive-anonymous phase takes its allocation-free success
    branch when the exact production container scan is empty. -/
theorem validateRecursiveAnonymousTypeKeyUniquenessV1_eq_ok_of_none
    (types : Array TypeDeclV1)
    (hnone : (types.any fun decl =>
      match decl.shape with
      | .array _ _ | .map _ _ | .option _ => true
      | _ => false) = false) :
    validateRecursiveAnonymousTypeKeyUniquenessV1 types = .ok () := by
  simp only [validateRecursiveAnonymousTypeKeyUniquenessV1, hnone,
    Bool.not_false, ↓reduceIte, Pure.pure, Except.pure]

/-! ### named-body Option-cycle legality (SPEC §5)

    SPEC §5 requires that every recursive cycle in the type graph pass
    simultaneously through a reserved named Struct/Enum key and an anonymous
    `Option` node. The earlier `recursiveAnonymous` subphase rejects all
    anonymous-container cycles that pass through no named anchor. This slice
    closes the remaining gap: any cycle that passes through a reserved named
    key must also pass through at least one anonymous `Option`.

    Equivalent global algorithm: build the directed graph on TypeIds with an
    edge `u → v` for each child TypeId `v` referenced by a non-`Option`
    declaration `u` where `v` itself is not an `Option` declaration (i.e.
    remove every `.option` node and its incident edges), then require the
    induced subgraph to be acyclic. This rejects exactly the cycles that
    contain no `Option`; combined with `recursiveAnonymous` rejecting
    anonymous-only cycles, the two gates together ensure an accepted cycle
    simultaneously contains a named key and an `Option`. Per-named-root DFS
    and "path has seen an Option" walks are rejected because they miss the
    sibling-branch trap (a node can have both an Option branch and a direct
    non-Option branch; the direct branch forms an Option-free cycle the
    path-local walk would miss).

    Implementation: a single explicit-stack white/gray/black DFS over the
    types table. For each TypeId, the child set is collected from the
    declaration's Struct fields / Enum payloads / Array element / Map key +
    value, but `Option` declarations contribute no children (they are removed
    nodes), and any child TypeId that resolves to an `Option` declaration is
    skipped (its incident edges are removed). Primitive leaves have no
    children; named Struct/Enum contribute their fields/payloads (those are
    the edges that form a named-body cycle). A standard gray back-edge is
    `.nonCanonical`.
    O(V+E) time, O(V+stack) space, no recursion, no HashMap iteration, no
    nested TypeKey bytes, no public reorder. Defensive OOR → `.badReference`
    is retained but earlier shallow reference checks report first. Runs
    after `recursiveAnonymous` and before named-name uniqueness / canonical
    valueBytes / callable signature / CFG / requirements. The complete SPEC
    §5 cycle condition is closed by the combination of the earlier
    `recursiveAnonymous` anonymous-cycle gate and this `namedBodyCycle`
    gate; the full TypeKey closure (anonymous canonical rank/order of the
    isolated SPEC `typeKey` bytes, reachability, usage closure) and
    normalizer/provenance/product wire remain deferred. The byte form
    itself is pinned separately and is not a structure gate. -/

/-- Children TypeIds that a declaration contributes to the Option-removed
    induced graph. `Option` declarations return `none` (removed nodes). Any
    child reference whose target is an `Option` declaration is filtered by
    the caller. The Enum branch is a linear flatten over variants and their
    payloads (a single mutable `push` per child), preserving source order and
    keeping the whole helper O(E) — a high-fanout Enum does not degrade to
    quadratic accumulator copying. -/
private def nonOptionChildTypeIds
    (decl : TypeDeclV1) : Option (Array TypeIdV1) :=
  match decl.shape with
  | .option _ => none
  | .struct fields => some (fields.map (·.typeId))
  | .enum variants =>
    some (Id.run do
      let mut acc : Array TypeIdV1 := Array.emptyWithCapacity
        (variants.foldl (fun s v => s + v.payloadTypes.size) 0)
      for v in variants do
        for t in v.payloadTypes do
          acc := acc.push t
      pure acc)
  | .array element _ => some #[element]
  | .map key value => some #[key, value]
  | _ => none

/-- Is the declaration at the given index an anonymous `.option`? The
    induced graph removes Option nodes, so edges into or out of them are
    dropped. -/
private def isOptionDecl (types : Array TypeDeclV1) (id : TypeIdV1) : Bool :=
  match types[id.toNat]? with
  | some { shape := .option _, .. } => true
  | _ => false

/-- SPEC §5 named-body Option-cycle legality: remove every `Option` node and
    its incident edges from the TypeId directed graph, then require the
    induced subgraph to be acyclic. A standard gray back-edge in an
    explicit-stack white/gray/black DFS is `.nonCanonical`. Runs as the
    `namedBodyCycle` subphase of `validateTypeKeyPhasesV1`, ordered after
    `recursiveAnonymous`. -/
-- Internal production named-body Option-cycle TypeKey subphase exposed for
-- refinement. The complete TypeKey gate remains `validateTypeKeyPhasesV1`.
def validateNamedBodyOptionCycleLegalityV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  -- Primitive/Option-only tables cannot contain an edge in the induced graph.
  -- Struct/Enum remain explicit edge sources so named-body cycles still reach
  -- the DFS; this shortcut is intentionally narrower than "no containers".
  let hasNonOptionEdgeSource := types.any fun decl =>
    match decl.shape with
    | .array _ _ | .map _ _ | .struct _ | .enum _ => true
    | _ => false
  if !hasNonOptionEdgeSource then return
  let n := types.size
  let mut color : Array Nat := Array.replicate n 0
  let mut stack : Array (Nat × Nat) := #[]
  let mut root := 0
  while _ : root < n do
    if color[root]! == 0 then
      -- Skip removed Option nodes entirely (no DFS entry).
      if isOptionDecl types (UInt32.ofNat root) then
        color := color.set! root 2
      else
        stack := stack.push (0, root)
        while stack.isEmpty == false do
          let (kind, tid) := stack.back!
          stack := stack.pop
          if kind == 1 then
            -- exit: black.
            color := color.set! tid 2
          else
            -- enter.
            match color[tid]! with
            | 2 => pure ()  -- memoized
            | 1 => return ← err .nonCanonical  -- gray back-edge: Option-free cycle
            | _ =>
              match types[tid]? with
              | none => return ← err .badReference
              | some decl =>
                -- Mark gray; push an exit marker, then push children.
                color := color.set! tid 1
                stack := stack.push (1, tid)
                match nonOptionChildTypeIds decl with
                | none => pure ()  -- no children (Option node / primitive leaf)
                | some childIds =>
                  let mut ci := childIds.size
                  while _ : ci > 0 do
                    ci := ci - 1
                    let child := childIds[ci]!
                    let childIdx := child.toNat
                    if childIdx ≥ n then
                      return ← err .badReference
                    -- Drop edges into removed Option nodes.
                    if isOptionDecl types child then
                      pure ()
                    else
                      stack := stack.push (0, childIdx)
    root := root + 1
  pure ()

/-- The production named-body cycle phase takes its allocation-free success
    branch when the exact production edge-source scan is empty. -/
theorem validateNamedBodyOptionCycleLegalityV1_eq_ok_of_none
    (types : Array TypeDeclV1)
    (hnone : (types.any fun decl =>
      match decl.shape with
      | .array _ _ | .map _ _ | .struct _ | .enum _ => true
      | _ => false) = false) :
    validateNamedBodyOptionCycleLegalityV1 types = .ok () := by
  simp only [validateNamedBodyOptionCycleLegalityV1, hnone, Bool.not_false,
    ↓reduceIte, Pure.pure, Except.pure]

/-! ### TypeKey validation phase seam (SPEC §5)

    Named-prefix rank, leaf primitive anonymous TypeKey uniqueness,
    recursive anonymous container structural-class uniqueness, and named-body
    `Option`-cycle legality all report the
    same public wire error `.nonCanonical`. To make their precedence
    observable to focused tests without changing the public wire contract,
    this closed phase seam mirrors the `CfgInvariantValidationPhaseV1`
    pattern: a non-serialized phase enum plus the unchanged public error,
    consumed exactly by the structure gate which erases only `phase`. The
    phase is not serialized and does not appear in any wire/CLI output. -/

/-- Closed non-wire phase distinguishing the TypeKey subphases that
    share the public `.nonCanonical` error: `namedPrefix` (named contiguous
    prefix rank), `primitiveLeaf`, `recursiveAnonymous`,
    `namedBodyCycle` (the SPEC §5 rule that any recursive cycle must pass
    through an `Option`, enforced after `recursiveAnonymous`),
    `anonymousRank` (SPEC §5 unsigned-lex `typeKey` order of the anonymous
    suffix), and `usageClosure` (every anonymous TypeDecl is reached from a
    named body or a Core type slot). -/
inductive TypeKeyValidationPhaseV1
  | namedPrefix
  | primitiveLeaf
  | recursiveAnonymous
  | namedBodyCycle
  | anonymousRank
  | usageClosure
  deriving BEq, Repr

/-- Internal phase plus the unchanged public wire error. -/
structure TypeKeyValidationFailureV1 where
  phase : TypeKeyValidationPhaseV1
  error : SemanticWireErrorV1
  deriving BEq, Repr

private def liftTypeKeyValidationPhaseV1
    (phase : TypeKeyValidationPhaseV1)
    (result : Except SemanticWireErrorV1 Unit) :
    Except TypeKeyValidationFailureV1 Unit :=
  match result with
  | .ok () => .ok ()
  | .error error => .error { phase, error }

/-- Runs the exact stable §5 TypeKey *prefix* segment (named prefix through
    named-body Option-cycle). Anonymous `typeKey` rank and Core/named usage
    closure are composed by `validateTypeKeyPhasesV1` after
    `encodeAnonymousTypeRankKeyV1` is defined below. -/
def validateTypeKeyPhasesPrefixV1 (types : Array TypeDeclV1) :
    Except TypeKeyValidationFailureV1 Unit := do
  liftTypeKeyValidationPhaseV1 .namedPrefix
    (validateNamedPrefixRankV1 types)
  liftTypeKeyValidationPhaseV1 .primitiveLeaf
    (validatePrimitiveAnonymousTypeKeyUniquenessV1 types)
  liftTypeKeyValidationPhaseV1 .recursiveAnonymous
    (validateRecursiveAnonymousTypeKeyUniquenessV1 types)
  liftTypeKeyValidationPhaseV1 .namedBodyCycle
    (validateNamedBodyOptionCycleLegalityV1 types)

/-- Compose the TypeKey prefix seam from its four exact subphases. -/
theorem validateTypeKeyPhasesPrefixV1_eq_ok_of_phases (types : Array TypeDeclV1)
    (hNamedPrefix : validateNamedPrefixRankV1 types = .ok ())
    (hPrimitive : validatePrimitiveAnonymousTypeKeyUniquenessV1 types = .ok ())
    (hRecursive : validateRecursiveAnonymousTypeKeyUniquenessV1 types = .ok ())
    (hNamedBody : validateNamedBodyOptionCycleLegalityV1 types = .ok ()) :
    validateTypeKeyPhasesPrefixV1 types = .ok () := by
  simp only [validateTypeKeyPhasesPrefixV1, hNamedPrefix, hPrimitive, hRecursive,
    hNamedBody, liftTypeKeyValidationPhaseV1, Bind.bind, Except.bind]

/-! ### Isolated SPEC §5 `typeKey` byte form

    Pins the canonical `typeKey(tag, fields)` / `nameBytes` framing from
    SPEC-SEM-WIRE-001 §5. Rank checking consumes the same byte form via
    `encodeAnonymousTypeRankKeyV1` / `validateAnonymousTypeKeyRankV1`.
    Pretty names, hashes, locale sort, and final TypeId are not sort keys. -/

/-- SPEC `typeKey` frame: `u16le(ASCII(tag).size) || ASCII(tag) ||
    u32le(fields.size) || concat(u32le(field.size) || field)`.
    Pure fold (no `Id.run`) so closed-table certificates stay kernel-checkable. -/
private def typeKeyFrameBytesV1 (tag : String) (fields : Array ByteArray) :
    ByteArray :=
  let tagBytes := tag.toUTF8
  let header :=
    ((encodeU16le (UInt16.ofNat tagBytes.size)).append tagBytes).append
      (encodeU32le (UInt32.ofNat fields.size))
  fields.foldl (init := header) fun out field =>
    out.append ((encodeU32le (UInt32.ofNat field.size)).append field)

/-- Closure / top-level tags only. Nested helpers are excluded. -/
private def isTypeKeyClosureTagV1 (tag : String) : Bool :=
  tag == "named" || tag == "bool" || tag == "uint" || tag == "int" ||
    tag == "principal" || tag == "unit" || tag == "bytes" ||
    tag == "array" || tag == "map" || tag == "option" || tag == "field" ||
    tag == "struct" || tag == "enum"

/-- Nested record helpers. Legal only inside a parent `struct`/`enum` key. -/
private def isTypeKeyNestedHelperTagV1 (tag : String) : Bool :=
  tag == "struct-field" || tag == "enum-variant"

/-- Frame a `typeKey` after the tag allowlist. `allowNestedHelper` is true
    only for `struct-field` / `enum-variant` items emitted under a parent
    struct/enum key. Unknown tags and nested helpers used as a closure
    declaration tag fail closed. -/
private def encodeTypeKeyFrameCheckedV1 (tag : String)
    (fields : Array ByteArray) (allowNestedHelper : Bool) :
    Except SemanticWireErrorV1 ByteArray := do
  if isTypeKeyClosureTagV1 tag then
    pure (typeKeyFrameBytesV1 tag fields)
  else if allowNestedHelper && isTypeKeyNestedHelperTagV1 tag then
    pure (typeKeyFrameBytesV1 tag fields)
  else
    err .badType

/-- Closed Bool anonymous rank key (`typeKey("bool", [])`). Pinned concrete
    bytes so product certificates never depend on `String.toUTF8` reduction
    or `decide` / `Lean.ofReduceBool`. -/
def typeKeyBoolRankBytesV1 : ByteArray :=
  ByteArray.mk #[4, 0, 98, 111, 111, 108, 0, 0, 0, 0]

/-- Closed UInt64 anonymous rank key (`typeKey("uint", [u16le 64])`). -/
def typeKeyUInt64RankBytesV1 : ByteArray :=
  ByteArray.mk #[4, 0, 117, 105, 110, 116, 1, 0, 0, 0, 2, 0, 0, 0, 64, 0]

/-- Closed Unit anonymous rank key (`typeKey("unit", [])`). -/
def typeKeyUnitRankBytesV1 : ByteArray :=
  ByteArray.mk #[4, 0, 117, 110, 105, 116, 0, 0, 0, 0]

/-- Closed Principal anonymous rank key (`typeKey("principal", [])`). -/
def typeKeyPrincipalRankBytesV1 : ByteArray :=
  ByteArray.mk #[9, 0, 112, 114, 105, 110, 99, 105, 112, 97, 108, 0, 0, 0, 0]

/-- Engineering string rank frame (`typeKey("string", [])`) for
    `stringExtension = true`. -/
def typeKeyStringRankBytesV1 : ByteArray :=
  ByteArray.mk #[6, 0, 115, 116, 114, 105, 110, 103, 0, 0, 0, 0]

/-- SPEC `typeKey` of one TypeId. Named Struct/Enum emit `named` + reserved
    `u32le` id and do not expand the body. Anonymous Struct/Enum expand as
    `struct`/`enum` with nested helpers. Child TypeIds are resolved against
    `types` (index = TypeId); OOR fails closed. Fuel is `maxNesting` (256)
    and is consumed on each nested TypeId.

    `stringExtension = false` is the pinned SPEC §5 byte form (`.string` is
    not a SPEC §4.2 tag → `.badType`). `stringExtension = true` additionally
    frames the engineering `.string` TypeShape as `typeKey("string", [])` so
    the product anonymous rank key is total over every shape the Normalize
    interner can produce; the `"string"` tag stays outside
    `isTypeKeyClosureTagV1` and is framed directly, so the SPEC test hooks
    keep rejecting it.

    Leaf Bool / Unit / UInt64 / string frames return pinned concrete bytes
    (same bit pattern as `typeKeyFrameBytesV1`) so InlineProofAudit product
    certificates stay free of `decide`. -/
private def encodeTypeKeyFromTypeIdV1 (types : Array TypeDeclV1)
    (typeId : TypeIdV1) (stringExtension : Bool) :
    Nat → Except SemanticWireErrorV1 ByteArray
  | 0 => err .limitExceeded
  | fuel + 1 => do
      match types[typeId.toNat]? with
      | none => err .badReference
      | some decl =>
          match decl.name, decl.shape with
          | some _, .struct _ =>
              encodeTypeKeyFrameCheckedV1 "named"
                #[encodeU32le decl.id] false
          | some _, .enum _ =>
              encodeTypeKeyFrameCheckedV1 "named"
                #[encodeU32le decl.id] false
          | _, .bool =>
              pure typeKeyBoolRankBytesV1
          | _, .uint 64 =>
              pure typeKeyUInt64RankBytesV1
          | _, .uint w =>
              encodeTypeKeyFrameCheckedV1 "uint" #[encodeU16le w] false
          | _, .int w =>
              encodeTypeKeyFrameCheckedV1 "int" #[encodeU16le w] false
          | _, .principal =>
              pure typeKeyPrincipalRankBytesV1
          | _, .unit =>
              pure typeKeyUnitRankBytesV1
          | _, .string =>
              if stringExtension then
                pure typeKeyStringRankBytesV1
              else
                err .badType
          | _, .bytes len =>
              encodeTypeKeyFrameCheckedV1 "bytes" #[encodeU32le len] false
          | _, .field spec => do
              let idB ← encodeString spec.id.value
              encodeTypeKeyFrameCheckedV1 "field" #[idB, spec.modulusBE] false
          | _, .array element length => do
              let child ←
                encodeTypeKeyFromTypeIdV1 types element stringExtension fuel
              encodeTypeKeyFrameCheckedV1 "array"
                #[child, encodeU32le length] false
          | _, .map key value => do
              let keyB ←
                encodeTypeKeyFromTypeIdV1 types key stringExtension fuel
              let valueB ←
                encodeTypeKeyFromTypeIdV1 types value stringExtension fuel
              encodeTypeKeyFrameCheckedV1 "map" #[keyB, valueB] false
          | _, .option element => do
              let child ←
                encodeTypeKeyFromTypeIdV1 types element stringExtension fuel
              encodeTypeKeyFrameCheckedV1 "option" #[child] false
          | none, .struct fields => do
              let mut items : Array ByteArray := #[]
              for f in fields do
                let nameB ← encodeString f.name
                let child ←
                  encodeTypeKeyFromTypeIdV1 types f.typeId stringExtension fuel
                let item ← encodeTypeKeyFrameCheckedV1 "struct-field"
                  #[nameB, child] true
                items := items.push item
              encodeTypeKeyFrameCheckedV1 "struct" items false
          | none, .enum variants => do
              let mut items : Array ByteArray := #[]
              for v in variants do
                let nameB ← encodeString v.name
                let mut packed :=
                  encodeU32le (UInt32.ofNat v.payloadTypes.size)
                for payload in v.payloadTypes do
                  let payloadKey ←
                    encodeTypeKeyFromTypeIdV1 types payload stringExtension fuel
                  packed := packed.append
                    ((encodeU32le (UInt32.ofNat payloadKey.size)).append
                      payloadKey)
                let item ← encodeTypeKeyFrameCheckedV1 "enum-variant"
                  #[nameB, packed] true
                items := items.push item
              encodeTypeKeyFrameCheckedV1 "enum" items false

/-- Test-only SPEC `typeKey` encoder. Not a structure gate, not a rank
    checker, and not a product API. Resolves `typeId` against `types` with
    fuel `maxNesting`. -/
def encodeTypeKeyBytesForTestV1 (types : Array TypeDeclV1)
    (typeId : TypeIdV1) : Except SemanticWireErrorV1 ByteArray :=
  encodeTypeKeyFromTypeIdV1 types typeId false maxNesting

/-- Product anonymous canonical-rank key (Normalize TypeKey rank cutover,
    Stage A). Exactly the SPEC §5 `typeKey` byte form plus the engineering
    `string` frame (`typeKey("string", [])`) so the key is total over every
    TypeShape the Normalize interner produces. Named Struct/Enum anchors use
    reserved-prefix ids only, and anonymous children expand structurally, so
    the key of an anonymous TypeDecl never depends on anonymous TypeId
    numbering — the unsigned-lex sort over these keys is well defined before
    the final ids are assigned. -/
def encodeAnonymousTypeRankKeyV1 (types : Array TypeDeclV1)
    (typeId : TypeIdV1) : Except SemanticWireErrorV1 ByteArray :=
  encodeTypeKeyFromTypeIdV1 types typeId true maxNesting

/-- Adjacent unsigned-lex strict ascent over an already-encoded key list. -/
def checkAnonymousTypeKeyRankListV1 :
    List ByteArray → Except SemanticWireErrorV1 Unit
  | [] => pure ()
  | [_] => pure ()
  | a :: b :: rest => do
      match compareByteArrayLex a b with
      | .lt => checkAnonymousTypeKeyRankListV1 (b :: rest)
      | _ => err .nonCanonical

/-- Two distinct ascending keys pass the list rank checker. -/
theorem checkAnonymousTypeKeyRankListV1_two_eq_ok
    (k0 k1 : ByteArray)
    (hlt : compareByteArrayLex k0 k1 = .lt) :
    checkAnonymousTypeKeyRankListV1 [k0, k1] = .ok () := by
  simp [checkAnonymousTypeKeyRankListV1, hlt, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- Three distinct ascending keys pass the list rank checker. -/
theorem checkAnonymousTypeKeyRankListV1_three_eq_ok
    (k0 k1 k2 : ByteArray)
    (h01 : compareByteArrayLex k0 k1 = .lt)
    (h12 : compareByteArrayLex k1 k2 = .lt) :
    checkAnonymousTypeKeyRankListV1 [k0, k1, k2] = .ok () := by
  simp [checkAnonymousTypeKeyRankListV1, h01, h12, Pure.pure, Except.pure,
    Bind.bind, Except.bind]

/-- Leading named contiguous-prefix length (anonymous suffix starts here). -/
private def namedTypePrefixCountListV1 : List TypeDeclV1 → Nat
  | [] => 0
  | d :: rest =>
      if d.name.isSome then namedTypePrefixCountListV1 rest + 1 else 0

def namedTypePrefixCountV1 (types : Array TypeDeclV1) : Nat :=
  namedTypePrefixCountListV1 types.toList

/-- Anonymous rank keys for the suffix list starting at absolute index `start`. -/
private def collectAnonymousTypeRankKeysListV1
    (types : Array TypeDeclV1) :
    List TypeDeclV1 → Nat → Except SemanticWireErrorV1 (List ByteArray)
  | [], _ => pure []
  | d :: rest, i =>
      if d.name.isSome then
        err .nonCanonical
      else do
        let key ← encodeAnonymousTypeRankKeyV1 types (UInt32.ofNat i)
        let restKeys ← collectAnonymousTypeRankKeysListV1 types rest (i + 1)
        pure (key :: restKeys)

/-- Anonymous rank keys from `start` through the end of `types`, in table
    order. Named rows inside the suffix fail closed. -/
def collectAnonymousTypeRankKeysFromV1
    (types : Array TypeDeclV1) (start : Nat) :
    Except SemanticWireErrorV1 (List ByteArray) :=
  collectAnonymousTypeRankKeysListV1 types (types.toList.drop start) start

/-- SPEC §5 anonymous suffix rank: after the named contiguous prefix, every
    anonymous TypeDecl must appear in strictly ascending unsigned-lex order
    of `encodeAnonymousTypeRankKeyV1` (the same key Normalize uses). Wrong
    order is `.nonCanonical`. This is the `anonymousRank` subphase. -/
def validateAnonymousTypeKeyRankV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let keys ← collectAnonymousTypeRankKeysFromV1 types (namedTypePrefixCountV1 types)
  checkAnonymousTypeKeyRankListV1 keys

private theorem encodeTypeKeyFromTypeIdV1_bool
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (stringExtension : Bool)
    (fuel : Nat) (id : TypeIdV1)
    (hget : types[typeId.toNat]? = some { id := id, name := none, shape := .bool }) :
    encodeTypeKeyFromTypeIdV1 types typeId stringExtension (fuel + 1) =
      .ok typeKeyBoolRankBytesV1 := by
  simp [encodeTypeKeyFromTypeIdV1, hget, Pure.pure, Except.pure]

private theorem encodeTypeKeyFromTypeIdV1_uint64
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (stringExtension : Bool)
    (fuel : Nat) (id : TypeIdV1)
    (hget : types[typeId.toNat]? =
      some { id := id, name := none, shape := .uint 64 }) :
    encodeTypeKeyFromTypeIdV1 types typeId stringExtension (fuel + 1) =
      .ok typeKeyUInt64RankBytesV1 := by
  simp [encodeTypeKeyFromTypeIdV1, hget, Pure.pure, Except.pure]

private theorem encodeTypeKeyFromTypeIdV1_unit
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (stringExtension : Bool)
    (fuel : Nat) (id : TypeIdV1)
    (hget : types[typeId.toNat]? =
      some { id := id, name := none, shape := .unit }) :
    encodeTypeKeyFromTypeIdV1 types typeId stringExtension (fuel + 1) =
      .ok typeKeyUnitRankBytesV1 := by
  simp [encodeTypeKeyFromTypeIdV1, hget, Pure.pure, Except.pure]

private theorem encodeTypeKeyFromTypeIdV1_principal
    (types : Array TypeDeclV1) (typeId : TypeIdV1) (stringExtension : Bool)
    (fuel : Nat) (id : TypeIdV1)
    (hget : types[typeId.toNat]? =
      some { id := id, name := none, shape := .principal }) :
    encodeTypeKeyFromTypeIdV1 types typeId stringExtension (fuel + 1) =
      .ok typeKeyPrincipalRankBytesV1 := by
  simp [encodeTypeKeyFromTypeIdV1, hget, Pure.pure, Except.pure]

/-- Encode the Bool anonymous rank key at a concrete table index. -/
theorem encodeAnonymousTypeRankKeyV1_bool
    (types : Array TypeDeclV1) (i : Nat) (id : TypeIdV1)
    (hget : types[i]? = some { id := id, name := none, shape := .bool })
    (hi : (UInt32.ofNat i).toNat = i) :
    encodeAnonymousTypeRankKeyV1 types (UInt32.ofNat i) =
      .ok typeKeyBoolRankBytesV1 := by
  have hget' : types[(UInt32.ofNat i).toNat]? =
      some { id := id, name := none, shape := .bool } := by
    simpa [hi] using hget
  simpa [encodeAnonymousTypeRankKeyV1, maxNesting, show (256 : Nat) = 255 + 1 from rfl]
    using encodeTypeKeyFromTypeIdV1_bool types (UInt32.ofNat i) true 255 id hget'

/-- Encode the UInt64 anonymous rank key at a concrete table index. -/
theorem encodeAnonymousTypeRankKeyV1_uint64
    (types : Array TypeDeclV1) (i : Nat) (id : TypeIdV1)
    (hget : types[i]? = some { id := id, name := none, shape := .uint 64 })
    (hi : (UInt32.ofNat i).toNat = i) :
    encodeAnonymousTypeRankKeyV1 types (UInt32.ofNat i) =
      .ok typeKeyUInt64RankBytesV1 := by
  have hget' : types[(UInt32.ofNat i).toNat]? =
      some { id := id, name := none, shape := .uint 64 } := by
    simpa [hi] using hget
  simpa [encodeAnonymousTypeRankKeyV1, maxNesting, show (256 : Nat) = 255 + 1 from rfl]
    using encodeTypeKeyFromTypeIdV1_uint64 types (UInt32.ofNat i) true 255 id hget'

/-- Encode the Unit anonymous rank key at a concrete table index. -/
theorem encodeAnonymousTypeRankKeyV1_unit
    (types : Array TypeDeclV1) (i : Nat) (id : TypeIdV1)
    (hget : types[i]? = some { id := id, name := none, shape := .unit })
    (hi : (UInt32.ofNat i).toNat = i) :
    encodeAnonymousTypeRankKeyV1 types (UInt32.ofNat i) =
      .ok typeKeyUnitRankBytesV1 := by
  have hget' : types[(UInt32.ofNat i).toNat]? =
      some { id := id, name := none, shape := .unit } := by
    simpa [hi] using hget
  simpa [encodeAnonymousTypeRankKeyV1, maxNesting, show (256 : Nat) = 255 + 1 from rfl]
    using encodeTypeKeyFromTypeIdV1_unit types (UInt32.ofNat i) true 255 id hget'

/-- Encode the Principal anonymous rank key at a concrete table index. -/
theorem encodeAnonymousTypeRankKeyV1_principal
    (types : Array TypeDeclV1) (i : Nat) (id : TypeIdV1)
    (hget : types[i]? = some { id := id, name := none, shape := .principal })
    (hi : (UInt32.ofNat i).toNat = i) :
    encodeAnonymousTypeRankKeyV1 types (UInt32.ofNat i) =
      .ok typeKeyPrincipalRankBytesV1 := by
  have hget' : types[(UInt32.ofNat i).toNat]? =
      some { id := id, name := none, shape := .principal } := by
    simpa [hi] using hget
  simpa [encodeAnonymousTypeRankKeyV1, maxNesting, show (256 : Nat) = 255 + 1 from rfl]
    using encodeTypeKeyFromTypeIdV1_principal types (UInt32.ofNat i) true 255 id hget'

/-- Unsigned-lex: Bool typeKey sorts before UInt64 typeKey. -/
theorem compare_typeKeyBool_typeKeyUInt64_ltV1 :
    compareByteArrayLex typeKeyBoolRankBytesV1 typeKeyUInt64RankBytesV1 = .lt := by
  rw [compareByteArrayLex]
  change compareByteArrayLexLoopV1 typeKeyBoolRankBytesV1 typeKeyUInt64RankBytesV1
      (Nat.min typeKeyBoolRankBytesV1.size typeKeyUInt64RankBytesV1.size) 0 = .lt
  simp only [typeKeyBoolRankBytesV1, typeKeyUInt64RankBytesV1, ByteArray.size]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

/-- Unsigned-lex: UInt64 typeKey sorts before Unit typeKey. -/
theorem compare_typeKeyUInt64_typeKeyUnit_ltV1 :
    compareByteArrayLex typeKeyUInt64RankBytesV1 typeKeyUnitRankBytesV1 = .lt := by
  rw [compareByteArrayLex]
  change compareByteArrayLexLoopV1 typeKeyUInt64RankBytesV1 typeKeyUnitRankBytesV1
      (Nat.min typeKeyUInt64RankBytesV1.size typeKeyUnitRankBytesV1.size) 0 = .lt
  simp only [typeKeyUInt64RankBytesV1, typeKeyUnitRankBytesV1, ByteArray.size]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 2 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

/-- Unsigned-lex: Bool typeKey sorts before Unit typeKey. -/
theorem compare_typeKeyBool_typeKeyUnit_ltV1 :
    compareByteArrayLex typeKeyBoolRankBytesV1 typeKeyUnitRankBytesV1 = .lt := by
  rw [compareByteArrayLex]
  change compareByteArrayLexLoopV1 typeKeyBoolRankBytesV1 typeKeyUnitRankBytesV1
      (Nat.min typeKeyBoolRankBytesV1.size typeKeyUnitRankBytesV1.size) 0 = .lt
  simp only [typeKeyBoolRankBytesV1, typeKeyUnitRankBytesV1, ByteArray.size]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 0 (by decide) (by decide)]
  rw [compareByteArrayLexLoopV1_eq_next _ _ _ 1 (by decide) (by decide)]
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

/-- Unsigned-lex: Unit typeKey sorts before Principal typeKey (tag-length first). -/
theorem compare_typeKeyUnit_typeKeyPrincipal_ltV1 :
    compareByteArrayLex typeKeyUnitRankBytesV1 typeKeyPrincipalRankBytesV1 = .lt := by
  rw [compareByteArrayLex]
  change compareByteArrayLexLoopV1 typeKeyUnitRankBytesV1 typeKeyPrincipalRankBytesV1
      (Nat.min typeKeyUnitRankBytesV1.size typeKeyPrincipalRankBytesV1.size) 0 = .lt
  simp only [typeKeyUnitRankBytesV1, typeKeyPrincipalRankBytesV1, ByteArray.size]
  -- tag length 4 < 9 at index 0
  apply compareByteArrayLexLoopV1_eq_lt
  · decide
  · decide

/-- Kernel certificate: anonymous table `#[Bool]` passes rank. -/
theorem validateAnonymousTypeKeyRankV1_bool_only_eq_ok
    (t0 : TypeDeclV1)
    (h0 : t0 = { id := 0, name := none, shape := .bool }) :
    validateAnonymousTypeKeyRankV1 #[t0] = .ok () := by
  subst h0
  have hnamed :
      namedTypePrefixCountV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .bool }] = 0 := by
    simp [namedTypePrefixCountV1, namedTypePrefixCountListV1]
  have hk0 :=
    encodeAnonymousTypeRankKeyV1_bool
      #[{ id := (0 : TypeIdV1), name := none, shape := .bool }]
      0 0 (by simp) (by decide)
  have hkeys :
      collectAnonymousTypeRankKeysFromV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .bool }] 0 =
        .ok [typeKeyBoolRankBytesV1] := by
    unfold collectAnonymousTypeRankKeysFromV1
    simp only [collectAnonymousTypeRankKeysListV1, Array.toList, List.drop]
    rw [hk0]
    rfl
  simp [validateAnonymousTypeKeyRankV1, hnamed, hkeys,
    checkAnonymousTypeKeyRankListV1, Pure.pure, Except.pure, Bind.bind, Except.bind]

/-- Kernel certificate: anonymous table `#[Bool, UInt64]` passes rank. -/
theorem validateAnonymousTypeKeyRankV1_bool_uint64_eq_ok
    (t0 t1 : TypeDeclV1)
    (h0 : t0 = { id := 0, name := none, shape := .bool })
    (h1 : t1 = { id := 1, name := none, shape := .uint 64 }) :
    validateAnonymousTypeKeyRankV1 #[t0, t1] = .ok () := by
  subst h0; subst h1
  have hnamed :
      namedTypePrefixCountV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
          { id := (1 : TypeIdV1), name := none, shape := .uint 64 }] = 0 := by
    simp [namedTypePrefixCountV1, namedTypePrefixCountListV1]
  have hk0 :=
    encodeAnonymousTypeRankKeyV1_bool
      #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
        { id := (1 : TypeIdV1), name := none, shape := .uint 64 }]
      0 0 (by simp) (by decide)
  have hk1 :=
    encodeAnonymousTypeRankKeyV1_uint64
      #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
        { id := (1 : TypeIdV1), name := none, shape := .uint 64 }]
      1 1 (by simp) (by decide)
  have hkeys :
      collectAnonymousTypeRankKeysFromV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
          { id := (1 : TypeIdV1), name := none, shape := .uint 64 }] 0 =
        .ok [typeKeyBoolRankBytesV1, typeKeyUInt64RankBytesV1] := by
    unfold collectAnonymousTypeRankKeysFromV1
    simp only [collectAnonymousTypeRankKeysListV1, Array.toList, List.drop]
    rw [hk0, hk1]
    rfl

  simp [validateAnonymousTypeKeyRankV1, hnamed, hkeys,
    checkAnonymousTypeKeyRankListV1_two_eq_ok _ _ compare_typeKeyBool_typeKeyUInt64_ltV1,
    Bind.bind, Except.bind]

/-- Kernel certificate: anonymous table `#[UInt64, Unit]` passes rank. -/
theorem validateAnonymousTypeKeyRankV1_uint64_unit_eq_ok
    (t0 t1 : TypeDeclV1)
    (h0 : t0 = { id := 0, name := none, shape := .uint 64 })
    (h1 : t1 = { id := 1, name := none, shape := .unit }) :
    validateAnonymousTypeKeyRankV1 #[t0, t1] = .ok () := by
  subst h0; subst h1
  have hnamed :
      namedTypePrefixCountV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .uint 64 },
          { id := (1 : TypeIdV1), name := none, shape := .unit }] = 0 := by
    simp [namedTypePrefixCountV1, namedTypePrefixCountListV1]
  have hk0 :=
    encodeAnonymousTypeRankKeyV1_uint64
      #[{ id := (0 : TypeIdV1), name := none, shape := .uint 64 },
        { id := (1 : TypeIdV1), name := none, shape := .unit }]
      0 0 (by simp) (by decide)
  have hk1 :=
    encodeAnonymousTypeRankKeyV1_unit
      #[{ id := (0 : TypeIdV1), name := none, shape := .uint 64 },
        { id := (1 : TypeIdV1), name := none, shape := .unit }]
      1 1 (by simp) (by decide)
  have hkeys :
      collectAnonymousTypeRankKeysFromV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .uint 64 },
          { id := (1 : TypeIdV1), name := none, shape := .unit }] 0 =
        .ok [typeKeyUInt64RankBytesV1, typeKeyUnitRankBytesV1] := by
    unfold collectAnonymousTypeRankKeysFromV1
    simp only [collectAnonymousTypeRankKeysListV1, Array.toList, List.drop]
    rw [hk0, hk1]
    rfl
  simp [validateAnonymousTypeKeyRankV1, hnamed, hkeys,
    checkAnonymousTypeKeyRankListV1_two_eq_ok _ _ compare_typeKeyUInt64_typeKeyUnit_ltV1,
    Bind.bind, Except.bind]

/-- Kernel certificate: anonymous table `#[Bool, UInt64, Unit]` passes rank. -/
theorem validateAnonymousTypeKeyRankV1_bool_uint64_unit_eq_ok
    (t0 t1 t2 : TypeDeclV1)
    (h0 : t0 = { id := 0, name := none, shape := .bool })
    (h1 : t1 = { id := 1, name := none, shape := .uint 64 })
    (h2 : t2 = { id := 2, name := none, shape := .unit }) :
    validateAnonymousTypeKeyRankV1 #[t0, t1, t2] = .ok () := by
  subst h0; subst h1; subst h2
  let types : Array TypeDeclV1 :=
    #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
      { id := (1 : TypeIdV1), name := none, shape := .uint 64 },
      { id := (2 : TypeIdV1), name := none, shape := .unit }]
  have hnamed : namedTypePrefixCountV1 types = 0 := by
    simp [types, namedTypePrefixCountV1, namedTypePrefixCountListV1]
  have hk0 := encodeAnonymousTypeRankKeyV1_bool types 0 0 (by simp [types]) (by decide)
  have hk1 := encodeAnonymousTypeRankKeyV1_uint64 types 1 1 (by simp [types]) (by decide)
  have hk2 := encodeAnonymousTypeRankKeyV1_unit types 2 2 (by simp [types]) (by decide)
  have hkeys :
      collectAnonymousTypeRankKeysFromV1 types 0 =
        .ok [typeKeyBoolRankBytesV1, typeKeyUInt64RankBytesV1, typeKeyUnitRankBytesV1] := by
    unfold collectAnonymousTypeRankKeysFromV1
    simp only [collectAnonymousTypeRankKeysListV1, types, Array.toList, List.drop]
    rw [hk0, hk1, hk2]
    rfl

  simp [validateAnonymousTypeKeyRankV1, types, hnamed, hkeys,
    checkAnonymousTypeKeyRankListV1_three_eq_ok _ _ _
      compare_typeKeyBool_typeKeyUInt64_ltV1 compare_typeKeyUInt64_typeKeyUnit_ltV1,
    Bind.bind, Except.bind]

/-- Kernel certificate: anonymous table `#[Bool, Unit, Principal]` passes rank. -/
theorem validateAnonymousTypeKeyRankV1_bool_unit_principal_eq_ok
    (t0 t1 t2 : TypeDeclV1)
    (h0 : t0 = { id := 0, name := none, shape := .bool })
    (h1 : t1 = { id := 1, name := none, shape := .unit })
    (h2 : t2 = { id := 2, name := none, shape := .principal }) :
    validateAnonymousTypeKeyRankV1 #[t0, t1, t2] = .ok () := by
  subst h0; subst h1; subst h2
  have hnamed :
      namedTypePrefixCountV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
          { id := (1 : TypeIdV1), name := none, shape := .unit },
          { id := (2 : TypeIdV1), name := none, shape := .principal }] = 0 := by
    simp [namedTypePrefixCountV1, namedTypePrefixCountListV1]
  have hk0 :=
    encodeAnonymousTypeRankKeyV1_bool
      #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
        { id := (1 : TypeIdV1), name := none, shape := .unit },
        { id := (2 : TypeIdV1), name := none, shape := .principal }]
      0 0 (by simp) (by decide)
  have hk1 :=
    encodeAnonymousTypeRankKeyV1_unit
      #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
        { id := (1 : TypeIdV1), name := none, shape := .unit },
        { id := (2 : TypeIdV1), name := none, shape := .principal }]
      1 1 (by simp) (by decide)
  have hk2 :=
    encodeAnonymousTypeRankKeyV1_principal
      #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
        { id := (1 : TypeIdV1), name := none, shape := .unit },
        { id := (2 : TypeIdV1), name := none, shape := .principal }]
      2 2 (by simp) (by decide)
  have hkeys :
      collectAnonymousTypeRankKeysFromV1
        #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
          { id := (1 : TypeIdV1), name := none, shape := .unit },
          { id := (2 : TypeIdV1), name := none, shape := .principal }] 0 =
        .ok [typeKeyBoolRankBytesV1, typeKeyUnitRankBytesV1,
          typeKeyPrincipalRankBytesV1] := by
    unfold collectAnonymousTypeRankKeysFromV1
    simp only [collectAnonymousTypeRankKeysListV1, Array.toList, List.drop]
    rw [hk0, hk1, hk2]
    rfl
  simp [validateAnonymousTypeKeyRankV1, hnamed, hkeys,
    checkAnonymousTypeKeyRankListV1_three_eq_ok _ _ _
      compare_typeKeyBool_typeKeyUnit_ltV1 compare_typeKeyUnit_typeKeyPrincipal_ltV1,
    Bind.bind, Except.bind]

/-- Boolean observation of anonymous rank success (tests / non-product only;
    product certificates must use the kernel lemmas above — `native_decide`
    introduces `Lean.ofReduceBool`, which InlineProofAudit rejects). -/
def isOkAnonymousTypeKeyRankV1 (types : Array TypeDeclV1) : Bool :=
  match validateAnonymousTypeKeyRankV1 types with
  | .ok () => true
  | .error _ => false

theorem validateAnonymousTypeKeyRankV1_eq_ok_of_isOk
    (types : Array TypeDeclV1)
    (h : isOkAnonymousTypeKeyRankV1 types = true) :
    validateAnonymousTypeKeyRankV1 types = .ok () := by
  unfold isOkAnonymousTypeKeyRankV1 at h
  split at h
  · assumption
  · exact (Bool.noConfusion h)

/-- Child TypeIds embedded in one TypeShape (named-body / anonymous closure
    edges). -/
private def typeShapeChildTypeIdsV1 (shape : TypeShapeV1) : Array TypeIdV1 :=
  match shape with
  | .array element _ => #[element]
  | .map key value => #[key, value]
  | .option element => #[element]
  | .struct fields => fields.map (·.typeId)
  | .enum variants =>
      Id.run do
        let mut out : Array TypeIdV1 := #[]
        for v in variants do
          out := out.append v.payloadTypes
        pure out
  | _ => #[]

/-- Mark one TypeId and transitively every shape-child TypeId as used. -/
private def markTypeIdUsedV1 (types : Array TypeDeclV1)
    (used : Array Bool) (typeId : TypeIdV1) : Array Bool :=
  Id.run do
    let mut used := used
    let mut work : Array TypeIdV1 := #[typeId]
    let mut cursor := 0
    while cursor < work.size do
      let id := work[cursor]!
      cursor := cursor + 1
      let i := id.toNat
      if i < used.size && !used[i]! then
        used := used.set! i true
        match types[i]? with
        | none => pure ()
        | some decl =>
            for child in typeShapeChildTypeIdsV1 decl.shape do
              work := work.push child
    pure used

private def isUsageLeafTypeShapeV1 (shape : TypeShapeV1) : Bool :=
  match shape with
  | .bool | .uint _ | .int _ | .unit | .principal | .bytes _ => true
  | _ => false

private def isUsageLeafTypeDeclV1 (decl : TypeDeclV1) : Bool :=
  decl.name.isNone && isUsageLeafTypeShapeV1 decl.shape

private def allUsageLeafTypesV1 (types : Array TypeDeclV1) : Bool :=
  types.all isUsageLeafTypeDeclV1

/-- Kernel-friendly Core-root fold for anonymous Bool+UInt64 tables (leaf rows only). -/
def foldBoolUInt64CoreRootsV1 (roots : Array TypeIdV1) : Array Bool :=
  roots.foldl
    (init := Array.replicate 2 false)
    fun used root =>
      match root.toNat with
      | 0 => used.set! 0 true
      | 1 => used.set! 1 true
      | _ => used

/-- Kernel-friendly Core-root fold for anonymous Bool+UInt64+Unit tables. -/
def foldBoolUInt64UnitCoreRootsV1 (roots : Array TypeIdV1) : Array Bool :=
  roots.foldl
    (init := Array.replicate 3 false)
    fun used root =>
      match root.toNat with
      | 0 => used.set! 0 true
      | 1 => used.set! 1 true
      | 2 => used.set! 2 true
      | _ => used

/-- Kernel-friendly Core-root fold for a single anonymous Bool row. -/
def foldBoolCoreRootsV1 (roots : Array TypeIdV1) : Array Bool :=
  roots.foldl
    (init := Array.replicate 1 false)
    fun used _root => used.set! 0 true

/-- Direct Core-root marking for all-anonymous leaf tables (no shape children).
    Dispatches to the kernel-friendly fold helpers for the standard 1/2/3-row
    anonymous leaf tables used by product usage-closure certificates. -/
private def markCoreTypeSlotRootsLeafV1 (typeCount : Nat) (used : Array Bool)
    (roots : Array TypeIdV1) : Array Bool :=
  match typeCount with
  | 1 => foldBoolCoreRootsV1 roots
  | 2 => foldBoolUInt64CoreRootsV1 roots
  | 3 => foldBoolUInt64UnitCoreRootsV1 roots
  | _ =>
      roots.foldl (init := used) fun u r =>
        let i := r.toNat
        if i < typeCount then u.set! i true else u

/-- Collect Core type-slot roots from a SemanticProgramData carrier. -/
def collectCoreTypeSlotRootsV1 (data : SemanticProgramDataV1) : Array TypeIdV1 :=
  let roots := data.constants.map (·.typeId)
  let roots := roots ++ data.logicalState.map (·.typeId)
  let roots := roots ++ data.events.flatMap (fun e => e.fields.map (·.typeId))
  let roots := roots ++ data.errors.flatMap (fun e => e.fields.map (·.typeId))
  let roots := roots ++ data.callables.flatMap fun callable =>
    let roots := callable.params.map (·.typeId)
    let roots := roots.push callable.result.typeId
    roots ++ callable.blocks.flatMap fun block =>
      let roots := roots ++ block.params.map (·.typeId)
      roots ++ block.instructions.flatMap fun instr =>
        let roots :=
          match instr.result with
          | some vd => #[vd.typeId]
          | none => #[]
        let roots :=
          match instr.op with
          | .literal typeId _ => roots.push typeId
          | .construct typeId _ _ => roots.push typeId
          | .checkedCast _ toType => roots.push toType
          | _ => roots
        roots
  roots

/-- Compute the usage bitmap for `validateAnonymousTypeUsageClosureV1`
    (named anchors + named-body children + Core type-slot roots). -/
def anonymousTypeUsageBitmapV1 (data : SemanticProgramDataV1) :
    Array Bool :=
  let types := data.types
  let roots := collectCoreTypeSlotRootsV1 data
  if allUsageLeafTypesV1 types then
    markCoreTypeSlotRootsLeafV1 types.size (Array.replicate types.size false) roots
  else
    Id.run do
      let mut used : Array Bool := Array.replicate types.size false
      let mut i := 0
      for decl in types do
        if decl.name.isSome then
          used := used.set! i true
          for child in typeShapeChildTypeIdsV1 decl.shape do
            used := markTypeIdUsedV1 types used child
        i := i + 1
      for root in roots do
        used := markTypeIdUsedV1 types used root
      pure used

/-- SPEC §5 usage closure: every anonymous TypeDecl must be reached from a
    named body field/payload or a Core type slot (transitively through shape
    children). Unused anonymous rows are `.nonCanonical`. Named prefix rows
    are always retained as declaration anchors. -/
def validateAnonymousTypeUsageClosureV1
    (data : SemanticProgramDataV1) : Except SemanticWireErrorV1 Unit := do
  let types := data.types
  if types.isEmpty then
    return ()
  let used := anonymousTypeUsageBitmapV1 data
  let mut i := 0
  for decl in types do
    if decl.name.isNone && !used[i]! then
      return ← err .nonCanonical
    i := i + 1
  pure ()

/-- Kernel certificate: one anonymous Bool row passes usage closure when the
    usage bitmap marks TypeId 0 used. -/
theorem validateAnonymousTypeUsageClosureV1_singletonBool_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  unfold validateAnonymousTypeUsageClosureV1
  rw [htypes]
  simp only [Array.size_singleton, ↓reduceIte]
  rw [hbitmap]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind, ForIn.forIn]

private def usageClosureBoolUInt64TypesV1 : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .bool },
  { id := 1, name := none, shape := .uint 64 }
]

private def usageClosureUInt64UnitTypesV1 : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .uint 64 },
  { id := 1, name := none, shape := .unit }
]

private def usageClosureBoolUInt64UnitTypesV1 : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .bool },
  { id := 1, name := none, shape := .uint 64 },
  { id := 2, name := none, shape := .unit }
]

private def usageClosureSingletonBoolTypesV1 : Array TypeDeclV1 := #[
  { id := 0, name := none, shape := .bool }
]

theorem anonymousTypeUsageBitmapV1_allAnonymousLeaf_boolUInt64
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .uint 64 }]) :
    anonymousTypeUsageBitmapV1 data =
      foldBoolUInt64CoreRootsV1 (collectCoreTypeSlotRootsV1 data) := by
  have hleaf : allUsageLeafTypesV1
      #[{ id := 0, name := none, shape := .bool },
        { id := 1, name := none, shape := .uint 64 }] = true := by
    simp [allUsageLeafTypesV1, isUsageLeafTypeDeclV1, isUsageLeafTypeShapeV1]
  dsimp [anonymousTypeUsageBitmapV1, markCoreTypeSlotRootsLeafV1]
  rw [htypes, hleaf]
  simp [usageClosureBoolUInt64TypesV1, Array.replicate, Array.size, ↓reduceIte]

theorem anonymousTypeUsageBitmapV1_allAnonymousLeaf_uint64Unit
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .uint 64 },
                            { id := 1, name := none, shape := .unit }]) :
    anonymousTypeUsageBitmapV1 data =
      foldBoolUInt64CoreRootsV1 (collectCoreTypeSlotRootsV1 data) := by
  have hleaf : allUsageLeafTypesV1
      #[{ id := 0, name := none, shape := .uint 64 },
        { id := 1, name := none, shape := .unit }] = true := by
    simp [allUsageLeafTypesV1, isUsageLeafTypeDeclV1, isUsageLeafTypeShapeV1]
  dsimp [anonymousTypeUsageBitmapV1, markCoreTypeSlotRootsLeafV1]
  rw [htypes, hleaf]
  simp [usageClosureUInt64UnitTypesV1, Array.replicate, Array.size, ↓reduceIte]

theorem anonymousTypeUsageBitmapV1_allAnonymousLeaf_boolUInt64Unit
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .uint 64 },
                            { id := 2, name := none, shape := .unit }]) :
    anonymousTypeUsageBitmapV1 data =
      foldBoolUInt64UnitCoreRootsV1 (collectCoreTypeSlotRootsV1 data) := by
  have hleaf : allUsageLeafTypesV1
      #[{ id := 0, name := none, shape := .bool },
        { id := 1, name := none, shape := .uint 64 },
        { id := 2, name := none, shape := .unit }] = true := by
    simp [allUsageLeafTypesV1, isUsageLeafTypeDeclV1, isUsageLeafTypeShapeV1]
  dsimp [anonymousTypeUsageBitmapV1, markCoreTypeSlotRootsLeafV1]
  rw [htypes, hleaf]
  simp [usageClosureBoolUInt64UnitTypesV1, Array.replicate, Array.size, ↓reduceIte]

theorem anonymousTypeUsageBitmapV1_allAnonymousLeaf_singletonBool
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool }]) :
    anonymousTypeUsageBitmapV1 data =
      foldBoolCoreRootsV1 (collectCoreTypeSlotRootsV1 data) := by
  have hleaf : allUsageLeafTypesV1 #[{ id := 0, name := none, shape := .bool }] = true := by
    simp [allUsageLeafTypesV1, isUsageLeafTypeDeclV1, isUsageLeafTypeShapeV1]
  dsimp [anonymousTypeUsageBitmapV1, markCoreTypeSlotRootsLeafV1]
  rw [htypes, hleaf]
  simp [usageClosureSingletonBoolTypesV1, Array.replicate, Array.size, ↓reduceIte]

theorem foldBoolCoreRootsV1_simpleClosureSixZeros :
    foldBoolCoreRootsV1 #[0, 0, 0, 0, 0, 0] = #[true] := by
  unfold foldBoolCoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

theorem foldBoolUInt64CoreRootsV1_parityRoots :
    foldBoolUInt64CoreRootsV1
      #[1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0] = #[true, true] := by
  unfold foldBoolUInt64CoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

theorem foldBoolUInt64CoreRootsV1_fieldComparisonRoots :
    foldBoolUInt64CoreRootsV1
      #[1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0] = #[true, true] := by
  unfold foldBoolUInt64CoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

theorem foldBoolUInt64CoreRootsV1_statefulEqualityRoots :
    foldBoolUInt64CoreRootsV1 #[1, 1, 1, 1, 1, 0, 1, 1, 0] = #[true, true] := by
  unfold foldBoolUInt64CoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

/-- Kernel-friendly fold for the StateCell production Core-root list
    (logicalState UInt64 plus initializer Unit result plus body UInt64 slots). -/
theorem foldBoolUInt64CoreRootsV1_stateCellRoots :
    foldBoolUInt64CoreRootsV1
      #[0, 0, 1, 0, 0, 0, 0, 0, 0, 0] = #[true, true] := by
  unfold foldBoolUInt64CoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

private def markBoolUInt64RootV1 (used : Array Bool) (root : TypeIdV1) : Array Bool :=
  match root.toNat with
  | 0 => used.set! 0 true
  | 1 => used.set! 1 true
  | _ => used

private theorem foldBoolUInt64CoreRootsV1_eq_foldl_toList
    (roots : Array TypeIdV1) :
    foldBoolUInt64CoreRootsV1 roots =
      roots.toList.foldl markBoolUInt64RootV1 (Array.replicate 2 false) := by
  unfold foldBoolUInt64CoreRootsV1 markBoolUInt64RootV1
  simp [Array.foldl_toList]

private theorem markBoolUInt64RootV1_size
    (used : Array Bool) (root : TypeIdV1) (h : used.size = 2) :
    (markBoolUInt64RootV1 used root).size = 2 := by
  unfold markBoolUInt64RootV1
  split <;> simp [Array.size_setIfInBounds, h]

private theorem markBoolUInt64RootV1_preserves
    (used : Array Bool) (root : TypeIdV1) (h : used.size = 2)
    (i : Nat) (hi : i < 2)
    (htrue : used[i]'(by simp [h, hi]) = true) :
    (markBoolUInt64RootV1 used root)[i]'(by
        simp [markBoolUInt64RootV1_size used root h, hi]) = true := by
  have hj : i < used.size := by simp [h, hi]
  by_cases h0 : root.toNat = 0
  · have hmark : markBoolUInt64RootV1 used root = used.set! 0 true := by
      simp [markBoolUInt64RootV1, h0]
    simp [hmark, Array.getElem_setIfInBounds (hj := hj), htrue]
  · by_cases h1 : root.toNat = 1
    · have hmark : markBoolUInt64RootV1 used root = used.set! 1 true := by
        simp [markBoolUInt64RootV1, h1]
      simp [hmark, Array.getElem_setIfInBounds (hj := hj), htrue]
    · have hmark : markBoolUInt64RootV1 used root = used := by
        unfold markBoolUInt64RootV1
        split
        · next heq => exact (h0 heq).elim
        · next heq => exact (h1 heq).elim
        · rfl
      simpa [hmark] using htrue

private theorem markBoolUInt64RootV1_sets_zero
    (used : Array Bool) (h : used.size = 2) :
    (markBoolUInt64RootV1 used 0)[0]'(by
        simp [markBoolUInt64RootV1_size used 0 h]) = true := by
  unfold markBoolUInt64RootV1
  simp [Array.getElem_setIfInBounds_self]

private theorem markBoolUInt64RootV1_sets_one
    (used : Array Bool) (h : used.size = 2) :
    (markBoolUInt64RootV1 used 1)[1]'(by
        simp [markBoolUInt64RootV1_size used 1 h]) = true := by
  unfold markBoolUInt64RootV1
  simp [Array.getElem_setIfInBounds_self]

private theorem foldl_markBoolUInt64RootV1_size
    (roots : List TypeIdV1) (used : Array Bool) (h : used.size = 2) :
    (roots.foldl markBoolUInt64RootV1 used).size = 2 := by
  induction roots generalizing used with
  | nil => simpa
  | cons root rest ih =>
      exact ih (markBoolUInt64RootV1 used root) (markBoolUInt64RootV1_size used root h)

private theorem foldl_markBoolUInt64RootV1_preserves
    (roots : List TypeIdV1) (used : Array Bool) (h : used.size = 2)
    (i : Nat) (hi : i < 2)
    (htrue : used[i]'(by simp [h, hi]) = true) :
    (roots.foldl markBoolUInt64RootV1 used)[i]'(by
        simp [foldl_markBoolUInt64RootV1_size roots used h, hi]) = true := by
  induction roots generalizing used with
  | nil => simpa
  | cons root rest ih =>
      exact ih (markBoolUInt64RootV1 used root)
        (markBoolUInt64RootV1_size used root h)
        (markBoolUInt64RootV1_preserves used root h i hi htrue)

private theorem foldl_markBoolUInt64RootV1_mem_zero
    (roots : List TypeIdV1) (used : Array Bool) (h : used.size = 2)
    (hmem : (0 : TypeIdV1) ∈ roots) :
    (roots.foldl markBoolUInt64RootV1 used)[0]'(by
        simp [foldl_markBoolUInt64RootV1_size roots used h]) = true := by
  induction roots generalizing used with
  | nil => cases hmem
  | cons root rest ih =>
      have hsize' := markBoolUInt64RootV1_size used root h
      simp only [List.mem_cons] at hmem
      rcases hmem with hroot | hrest
      · subst hroot
        exact foldl_markBoolUInt64RootV1_preserves rest
          (markBoolUInt64RootV1 used 0) hsize' 0 (by decide)
          (markBoolUInt64RootV1_sets_zero used h)
      · exact ih (markBoolUInt64RootV1 used root) hsize' hrest

private theorem foldl_markBoolUInt64RootV1_mem_one
    (roots : List TypeIdV1) (used : Array Bool) (h : used.size = 2)
    (hmem : (1 : TypeIdV1) ∈ roots) :
    (roots.foldl markBoolUInt64RootV1 used)[1]'(by
        simp [foldl_markBoolUInt64RootV1_size roots used h]) = true := by
  induction roots generalizing used with
  | nil => cases hmem
  | cons root rest ih =>
      have hsize' := markBoolUInt64RootV1_size used root h
      simp only [List.mem_cons] at hmem
      rcases hmem with hroot | hrest
      · subst hroot
        exact foldl_markBoolUInt64RootV1_preserves rest
          (markBoolUInt64RootV1 used 1) hsize' 1 (by decide)
          (markBoolUInt64RootV1_sets_one used h)
      · exact ih (markBoolUInt64RootV1 used root) hsize' hrest

/-- Membership of TypeId 0 and 1 is enough to mark both anonymous UInt64+Unit
    slots; callers must not unfold instruction CFGs. -/
theorem foldBoolUInt64CoreRootsV1_of_mem
    (roots : Array TypeIdV1)
    (h0 : (0 : TypeIdV1) ∈ roots)
    (h1 : (1 : TypeIdV1) ∈ roots) :
    foldBoolUInt64CoreRootsV1 roots = #[true, true] := by
  have hlist0 : (0 : TypeIdV1) ∈ roots.toList := (Array.mem_def).1 h0
  have hlist1 : (1 : TypeIdV1) ∈ roots.toList := (Array.mem_def).1 h1
  have hsize : (Array.replicate 2 false).size = 2 := by simp
  let folded := roots.toList.foldl markBoolUInt64RootV1 (Array.replicate 2 false)
  have hfoldSize : folded.size = 2 :=
    foldl_markBoolUInt64RootV1_size roots.toList (Array.replicate 2 false) hsize
  have hfold0 :
      folded[0]'(by simp [hfoldSize]) = true :=
    foldl_markBoolUInt64RootV1_mem_zero roots.toList (Array.replicate 2 false)
      hsize hlist0
  have hfold1 :
      folded[1]'(by simp [hfoldSize]) = true :=
    foldl_markBoolUInt64RootV1_mem_one roots.toList (Array.replicate 2 false)
      hsize hlist1
  rw [foldBoolUInt64CoreRootsV1_eq_foldl_toList]
  change folded = #[true, true]
  apply Array.ext
  · exact hfoldSize.trans rfl
  · intro i hleft _
    have hi : i < 2 := hfoldSize ▸ hleft
    match i with
    | 0 => simpa [folded] using hfold0
    | 1 => simpa [folded] using hfold1
    | n + 2 =>
        have : n + 2 < 2 := hi
        omega

/-- Logical-state TypeIds are Core roots; does not inspect callable CFGs. -/
theorem collectCoreTypeSlotRootsV1_mem_logicalState
    (data : SemanticProgramDataV1) (s : StateDeclV1)
    (hs : s ∈ data.logicalState) :
    s.typeId ∈ collectCoreTypeSlotRootsV1 data := by
  unfold collectCoreTypeSlotRootsV1
  exact Array.mem_append_left _ <|
    Array.mem_append_left _ <|
    Array.mem_append_left _ <|
    Array.mem_append_right _ <|
      Array.mem_map_of_mem hs

private theorem callableResultTypeId_mem_callableRoots (callable : CallableV1) :
    callable.result.typeId ∈
      (let roots := callable.params.map (·.typeId)
       let roots := roots.push callable.result.typeId
       roots ++ callable.blocks.flatMap fun block =>
         let roots := roots ++ block.params.map (·.typeId)
         roots ++ block.instructions.flatMap fun instr =>
           let roots :=
             match instr.result with
             | some vd => #[vd.typeId]
             | none => #[]
           let roots :=
             match instr.op with
             | .literal typeId _ => roots.push typeId
             | .construct typeId _ _ => roots.push typeId
             | .checkedCast _ toType => roots.push toType
             | _ => roots
           roots) :=
  Array.mem_append_left _
    (Array.mem_push_self (xs := callable.params.map (·.typeId)))

/-- Callable result TypeIds are Core roots; does not inspect block bodies. -/
theorem collectCoreTypeSlotRootsV1_mem_callable_result
    (data : SemanticProgramDataV1) (callable : CallableV1)
    (hc : callable ∈ data.callables) :
    callable.result.typeId ∈ collectCoreTypeSlotRootsV1 data := by
  unfold collectCoreTypeSlotRootsV1
  exact Array.mem_append_right _ <|
    Array.mem_flatMap_of_mem hc (callableResultTypeId_mem_callableRoots callable)

theorem foldBoolUInt64UnitCoreRootsV1_initializerViewRoots :
    foldBoolUInt64UnitCoreRootsV1
      #[1, 1, 2, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0] = #[true, true, true] := by
  unfold foldBoolUInt64UnitCoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

theorem foldBoolUInt64UnitCoreRootsV1_initializerDepositRoots :
    foldBoolUInt64UnitCoreRootsV1
      #[1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0] =
        #[true, true, true] := by
  unfold foldBoolUInt64UnitCoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

theorem foldBoolUInt64UnitCoreRootsV1_initializerDepositWithdrawRoots :
    foldBoolUInt64UnitCoreRootsV1
      #[1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0] =
        #[true, true, true] := by
  unfold foldBoolUInt64UnitCoreRootsV1
  simp [Array.foldl, Array.set!, Array.replicate]

theorem validateAnonymousTypeUsageClosureV1_twoRow_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .unit }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true, true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  unfold validateAnonymousTypeUsageClosureV1
  rw [htypes]
  simp only [Array.isEmpty, Array.size, ↓reduceIte]
  rw [hbitmap]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind, ForIn.forIn]

theorem validateAnonymousTypeUsageClosureV1_threeRow_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .uint 64 },
                            { id := 2, name := none, shape := .unit }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true, true, true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  unfold validateAnonymousTypeUsageClosureV1
  rw [htypes]
  simp only [Array.isEmpty, Array.size, ↓reduceIte]
  rw [hbitmap]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind, ForIn.forIn]

theorem validateAnonymousTypeUsageClosureV1_bool_uint64_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .uint 64 }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true, true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  unfold validateAnonymousTypeUsageClosureV1
  rw [htypes]
  simp only [Array.isEmpty, Array.size, ↓reduceIte]
  rw [hbitmap]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind, ForIn.forIn]

theorem validateAnonymousTypeUsageClosureV1_uint64_unit_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .uint 64 },
                            { id := 1, name := none, shape := .unit }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true, true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  unfold validateAnonymousTypeUsageClosureV1
  rw [htypes]
  simp only [Array.isEmpty, Array.size, ↓reduceIte]
  rw [hbitmap]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind, ForIn.forIn]

theorem validateAnonymousTypeUsageClosureV1_bool_unit_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .unit }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true, true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  exact validateAnonymousTypeUsageClosureV1_twoRow_coreMarked_eq_ok data htypes hbitmap

theorem validateAnonymousTypeUsageClosureV1_bool_uint64_unit_coreMarked_eq_ok
    (data : SemanticProgramDataV1)
    (htypes : data.types = #[{ id := 0, name := none, shape := .bool },
                            { id := 1, name := none, shape := .uint 64 },
                            { id := 2, name := none, shape := .unit }])
    (hbitmap : anonymousTypeUsageBitmapV1 data = #[true, true, true]) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  exact validateAnonymousTypeUsageClosureV1_threeRow_coreMarked_eq_ok data htypes hbitmap

private def remapTypeIdForUsageCompactV1 (remap : Array TypeIdV1) (t : TypeIdV1) :
    TypeIdV1 :=
  remap[t.toNat]?.getD t

private def remapTypeShapeForUsageCompactV1 (remap : Array TypeIdV1) :
    TypeShapeV1 → TypeShapeV1
  | .array element length =>
      .array (remapTypeIdForUsageCompactV1 remap element) length
  | .map key value =>
      .map (remapTypeIdForUsageCompactV1 remap key)
        (remapTypeIdForUsageCompactV1 remap value)
  | .option element => .option (remapTypeIdForUsageCompactV1 remap element)
  | .struct fields =>
      .struct (fields.map fun f =>
        { f with typeId := remapTypeIdForUsageCompactV1 remap f.typeId })
  | .enum variants =>
      .enum (variants.map fun v =>
        { v with
          payloadTypes :=
            v.payloadTypes.map (remapTypeIdForUsageCompactV1 remap) })
  | shape => shape

private def remapOpForUsageCompactV1 (remap : Array TypeIdV1) :
    SemanticOpV1 → SemanticOpV1
  | .literal typeId valueBytes =>
      .literal (remapTypeIdForUsageCompactV1 remap typeId) valueBytes
  | .construct typeId ctor args =>
      .construct (remapTypeIdForUsageCompactV1 remap typeId) ctor args
  | .checkedCast value toType =>
      .checkedCast value (remapTypeIdForUsageCompactV1 remap toType)
  | op => op

private def remapTerminatorForUsageCompactV1 (remap : Array TypeIdV1) :
    TerminatorV1 → TerminatorV1
  | .switch scrutinee cases defaultTarget =>
      .switch scrutinee
        (cases.map fun c =>
          { c with typeId := remapTypeIdForUsageCompactV1 remap c.typeId })
        defaultTarget
  | terminator => terminator

private def remapCallableForUsageCompactV1 (remap : Array TypeIdV1)
    (callable : CallableV1) : CallableV1 :=
  { callable with
    params := callable.params.map fun p =>
      { p with typeId := remapTypeIdForUsageCompactV1 remap p.typeId }
    result := { callable.result with
      typeId := remapTypeIdForUsageCompactV1 remap callable.result.typeId }
    blocks := callable.blocks.map fun block =>
      { block with
        params := block.params.map fun bp =>
          { bp with typeId := remapTypeIdForUsageCompactV1 remap bp.typeId }
        instructions := block.instructions.map fun instr =>
          { result := instr.result.map fun r =>
              { r with typeId := remapTypeIdForUsageCompactV1 remap r.typeId }
            op := remapOpForUsageCompactV1 remap instr.op }
        terminator := remapTerminatorForUsageCompactV1 remap block.terminator } }

/-- Drop unused anonymous TypeDecls (keep every named row + used anonymous rows
    in table order), then remap every TypeId reference. Hand-built fat fixtures
    call this before structure validation so Stage D usage-closure does not
    invent fake Core uses. Production Normalize already emits closed tables;
    applying this to a closed table is identity on the `types` rows. -/
def compactSemanticProgramDataToUsageClosureV1
    (data : SemanticProgramDataV1) : SemanticProgramDataV1 := Id.run do
  let types := data.types
  if types.isEmpty then
    return data
  let used := anonymousTypeUsageBitmapV1 data
  let mut kept : Array TypeDeclV1 := #[]
  let mut remap : Array TypeIdV1 := Array.replicate types.size (0 : TypeIdV1)
  let mut newId : Nat := 0
  let mut i := 0
  for decl in types do
    let keep := decl.name.isSome || used[i]!
    if keep then
      remap := remap.set! i (UInt32.ofNat newId)
      kept := kept.push { decl with id := UInt32.ofNat newId }
      newId := newId + 1
    i := i + 1
  if kept.size == types.size then
    return data
  let keptRemapped := kept.map fun decl =>
    { decl with shape := remapTypeShapeForUsageCompactV1 remap decl.shape }
  { data with
    types := keptRemapped
    constants := data.constants.map fun c =>
      { c with typeId := remapTypeIdForUsageCompactV1 remap c.typeId }
    logicalState := data.logicalState.map fun s =>
      { s with typeId := remapTypeIdForUsageCompactV1 remap s.typeId }
    events := data.events.map fun e =>
      { e with fields := e.fields.map fun f =>
        { f with typeId := remapTypeIdForUsageCompactV1 remap f.typeId } }
    errors := data.errors.map fun e =>
      { e with fields := e.fields.map fun f =>
        { f with typeId := remapTypeIdForUsageCompactV1 remap f.typeId } }
    callables := data.callables.map (remapCallableForUsageCompactV1 remap) }

/-- Boolean observation of usage-closure success (tests / non-product only). -/
def isOkAnonymousTypeUsageClosureV1 (data : SemanticProgramDataV1) : Bool :=
  match validateAnonymousTypeUsageClosureV1 data with
  | .ok () => true
  | .error _ => false

theorem validateAnonymousTypeUsageClosureV1_eq_ok_of_isOk
    (data : SemanticProgramDataV1)
    (h : isOkAnonymousTypeUsageClosureV1 data = true) :
    validateAnonymousTypeUsageClosureV1 data = .ok () := by
  unfold isOkAnonymousTypeUsageClosureV1 at h
  split at h
  · assumption
  · exact (Bool.noConfusion h)

/-- Full production TypeKey seam over a `types` table: prefix uniqueness/cycle
    phases, then anonymous SPEC `typeKey` rank. Core/named usage closure is
    composed by `validateTypeKeyPhasesWithUsageClosureV1` because it requires
    the full SemanticProgramData carrier. -/
def validateTypeKeyPhasesV1 (types : Array TypeDeclV1) :
    Except TypeKeyValidationFailureV1 Unit := do
  validateTypeKeyPhasesPrefixV1 types
  liftTypeKeyValidationPhaseV1 .anonymousRank
    (validateAnonymousTypeKeyRankV1 types)

/-- Production TypeKey seam including SPEC §5 anonymous usage closure
    (`usageClosure` phase). StructureV1 consumes this helper and erases only
    the phase. -/
def validateTypeKeyPhasesWithUsageClosureV1
    (data : SemanticProgramDataV1) :
    Except TypeKeyValidationFailureV1 Unit := do
  validateTypeKeyPhasesV1 data.types
  liftTypeKeyValidationPhaseV1 .usageClosure
    (validateAnonymousTypeUsageClosureV1 data)

/-- Compose the types-table TypeKey seam from prefix success and rank success. -/
theorem validateTypeKeyPhasesV1_eq_ok_of_phases
    (types : Array TypeDeclV1)
    (hPrefix : validateTypeKeyPhasesPrefixV1 types = .ok ())
    (hRank : validateAnonymousTypeKeyRankV1 types = .ok ()) :
    validateTypeKeyPhasesV1 types = .ok () := by
  simp only [validateTypeKeyPhasesV1, hPrefix, hRank,
    liftTypeKeyValidationPhaseV1, Bind.bind, Except.bind]

/-- Compose types-table TypeKey + usage-closure from both successes. -/
theorem validateTypeKeyPhasesWithUsageClosureV1_eq_ok_of_phases
    (data : SemanticProgramDataV1)
    (hTypeKeys : validateTypeKeyPhasesV1 data.types = .ok ())
    (hUsageClosure : validateAnonymousTypeUsageClosureV1 data = .ok ()) :
    validateTypeKeyPhasesWithUsageClosureV1 data = .ok () := by
  simp only [validateTypeKeyPhasesWithUsageClosureV1, hTypeKeys, hUsageClosure,
    liftTypeKeyValidationPhaseV1, Bind.bind, Except.bind]

/-- Convenience: compose from the four prefix premises plus rank. -/
theorem validateTypeKeyPhasesV1_eq_ok_of_prefix_phases
    (types : Array TypeDeclV1)
    (hNamedPrefix : validateNamedPrefixRankV1 types = .ok ())
    (hPrimitive : validatePrimitiveAnonymousTypeKeyUniquenessV1 types = .ok ())
    (hRecursive : validateRecursiveAnonymousTypeKeyUniquenessV1 types = .ok ())
    (hNamedBody : validateNamedBodyOptionCycleLegalityV1 types = .ok ())
    (hRank : validateAnonymousTypeKeyRankV1 types = .ok ()) :
    validateTypeKeyPhasesV1 types = .ok () := by
  exact validateTypeKeyPhasesV1_eq_ok_of_phases types
    (validateTypeKeyPhasesPrefixV1_eq_ok_of_phases types
      hNamedPrefix hPrimitive hRecursive hNamedBody) hRank

/-- Kernel certificate: anonymous table `#[Bool, Unit]` passes rank. -/
theorem validateAnonymousTypeKeyRankV1_bool_unit_eq_ok
    (t0 t1 : TypeDeclV1)
    (h0 : t0 = { id := 0, name := none, shape := .bool })
    (h1 : t1 = { id := 1, name := none, shape := .unit }) :
    validateAnonymousTypeKeyRankV1 #[t0, t1] = .ok () := by
  subst h0; subst h1
  let types : Array TypeDeclV1 :=
    #[{ id := (0 : TypeIdV1), name := none, shape := .bool },
      { id := (1 : TypeIdV1), name := none, shape := .unit }]
  have hnamed : namedTypePrefixCountV1 types = 0 := by
    simp [types, namedTypePrefixCountV1, namedTypePrefixCountListV1]
  have hk0 := encodeAnonymousTypeRankKeyV1_bool types 0 0 (by simp [types]) (by decide)
  have hk1 := encodeAnonymousTypeRankKeyV1_unit types 1 1 (by simp [types]) (by decide)
  have hkeys :
      collectAnonymousTypeRankKeysFromV1 types 0 =
        .ok [typeKeyBoolRankBytesV1, typeKeyUnitRankBytesV1] := by
    unfold collectAnonymousTypeRankKeysFromV1
    simp only [collectAnonymousTypeRankKeysListV1, types, Array.toList, List.drop]
    rw [hk0, hk1]
    rfl
  simp [validateAnonymousTypeKeyRankV1, types, hnamed, hkeys,
    checkAnonymousTypeKeyRankListV1_two_eq_ok _ _
      compare_typeKeyBool_typeKeyUnit_ltV1,
    Bind.bind, Except.bind]

/-- Test-only top-level `typeKey` tag/frame hook. Nested helpers and
    unknown tags are rejected (`allowNestedHelper = false`). Not a
    structure gate. -/
def encodeTypeKeyFrameForTestV1 (tag : String) (fields : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray :=
  encodeTypeKeyFrameCheckedV1 tag fields false

/-- Test-only frame oracle for the engineering `string` rank frame (the
    checked frame hook intentionally keeps rejecting the `"string"` tag). -/
def encodeStringRankFrameForTestV1 : ByteArray :=
  typeKeyStringRankBytesV1

end ProofForgeV2.Semantic.WireV1
