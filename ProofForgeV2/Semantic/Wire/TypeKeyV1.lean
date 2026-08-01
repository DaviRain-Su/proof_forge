import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1
import Std.Data.HashMap

/-!
  ProofForgeV2.Semantic.Wire.TypeKeyV1 — type-shape/FieldSpec/Map-key legality
  and TypeKey phases (named-prefix, primitive leaf, recursive anonymous,
  named-body Option-cycle).

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
private def legalIntegerWidthV1 (width : UInt16) : Bool :=
  width == 8 || width == 16 || width == 32 || width == 64 ||
  width == 128 || width == 256

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
  unless spec.id.value == bn254FrFieldIdV1 do
    return ← err .badType
  unless spec.modulusBE == bn254FrModulusBEV1 do
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
def validatePrimitiveAnonymousTypeKeyUniquenessV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let mut keys : Array ByteArray := #[]
  for decl in types do
    let isPrimitive := match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .unit | .string | .bytes _ | .field _ => true
      | .array _ _ | .map _ _ | .option _ | .struct _ | .enum _ => false
    if isPrimitive then
      keys := keys.push (← encodeTypeShapeV1 decl.shape)
  -- Zero/one key is unique by construction. Besides avoiding unnecessary
  -- sorting work, this keeps the minimal closed proof subject on transparent
  -- collection operations only.
  if keys.size ≤ 1 then return
  -- Keep the small-table path transparent and allocation-free: at most three
  -- unordered pairs are checked with the same production byte comparator.
  -- All keys have already been encoded, preserving encoding-error precedence.
  if keys.size ≤ 3 then
    if compareByteArrayLex keys[0]! keys[1]! == .eq then
      return ← err .nonCanonical
    if keys.size == 3 then
      if compareByteArrayLex keys[0]! keys[2]! == .eq then
        return ← err .nonCanonical
      if compareByteArrayLex keys[1]! keys[2]! == .eq then
        return ← err .nonCanonical
    return
  let sorted := keys.qsort fun left right =>
    compareByteArrayLex left right == .lt
  let mut index : Nat := 1
  while index < sorted.size do
    if compareByteArrayLex sorted[index - 1]! sorted[index]! == .eq then
      return ← err .nonCanonical
    index := index + 1
  pure ()

/-- Fixed-size internal structural-class signature builder (SPEC §5
    engineering subset). This is **not** the SPEC canonical unsigned-
    lexicographic anonymous TypeKey/ranking bytes; that ranking/order is a
    separate normalizer concern and remains deferred. The signature is a
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
    gate; the full TypeKey closure (anonymous canonical key bytes/rank/order,
    reachability, usage closure) and normalizer/provenance/product wire
    remain deferred. -/

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
    prefix rank), `primitiveLeaf`, `recursiveAnonymous`, and
    `namedBodyCycle` (the SPEC §5 rule that any recursive cycle must pass
    through an `Option`, enforced after `recursiveAnonymous`). -/
inductive TypeKeyValidationPhaseV1
  | namedPrefix
  | primitiveLeaf
  | recursiveAnonymous
  | namedBodyCycle
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

/-- Runs the exact stable §5 TypeKey segment used by the structure gate in
    the fixed order: named contiguous-prefix rank first, then leaf primitive
    anonymous TypeKey uniqueness, then recursive anonymous container
    structural-class uniqueness (anonymous-container-cycle rejection without
    a named anchor), then named-body `Option`-cycle legality (remove every
    `Option` node and require the induced TypeId graph to be acyclic).
    Type-shape/FieldSpec/Map-key legality and shallow reference range are
    earlier prerequisites. The public wire error is unchanged; only the phase
    is exposed for focused tests. -/
def validateTypeKeyPhasesV1 (types : Array TypeDeclV1) :
    Except TypeKeyValidationFailureV1 Unit := do
  liftTypeKeyValidationPhaseV1 .namedPrefix
    (validateNamedPrefixRankV1 types)
  liftTypeKeyValidationPhaseV1 .primitiveLeaf
    (validatePrimitiveAnonymousTypeKeyUniquenessV1 types)
  liftTypeKeyValidationPhaseV1 .recursiveAnonymous
    (validateRecursiveAnonymousTypeKeyUniquenessV1 types)
  liftTypeKeyValidationPhaseV1 .namedBodyCycle
    (validateNamedBodyOptionCycleLegalityV1 types)

/-- Compose the sole production TypeKey seam from success of its four exact
    subphases. Each premise is a result of the production implementation, not
    a parallel TypeKey-validity predicate. -/
theorem validateTypeKeyPhasesV1_eq_ok_of_phases (types : Array TypeDeclV1)
    (hNamedPrefix : validateNamedPrefixRankV1 types = .ok ())
    (hPrimitive : validatePrimitiveAnonymousTypeKeyUniquenessV1 types = .ok ())
    (hRecursive : validateRecursiveAnonymousTypeKeyUniquenessV1 types = .ok ())
    (hNamedBody : validateNamedBodyOptionCycleLegalityV1 types = .ok ()) :
    validateTypeKeyPhasesV1 types = .ok () := by
  simp only [validateTypeKeyPhasesV1, hNamedPrefix, hPrimitive, hRecursive,
    hNamedBody, liftTypeKeyValidationPhaseV1, Bind.bind, Except.bind]

end ProofForgeV2.Semantic.WireV1
