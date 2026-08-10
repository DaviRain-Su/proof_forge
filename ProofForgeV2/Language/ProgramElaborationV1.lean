import ProofForgeV2.Language.Syntax
import ProofForgeV2.Language.SubjectDataQuoteV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.PreservationABI
import ProofForgeV2.Semantic.StateModelV1
import ProofForgeV2.Semantic.UInt64ParityPreservationV1
import ProofForgeV2.Semantic.UInt64ParitySubjectV1
import ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1

open Lean Parser Command
open Lean.Elab.Command
open ProofForgeV2
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Language.SubjectDataQuoteV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Language

/-!
  ## B-SC-ELAB-THM (generated theorem lane)

  Target product surface for each supported literal-true simple-closure
  invariant:

    `<Program>.Proof.generated<Invariant>V1 : <Program>.Proof.<Invariant>`

  with no free premises, no Tests import, and adjacent theorems writable as
  `exact <Program>.Proof.generated…V1`.

  **Current engineering ship:** naming + exact semantic subject + concrete
  ASCII identifier legality witnesses + hypothesis-honest `_of_wireTrace`
  bridge + premise-free `generated…V1`. The final theorem is derived only from
  production legal-only encode/decode composition and the ordinal-0 invariant
  ABI; unsupported or non-ASCII parameter families emit no helper and fail
  closed during product certification.
-/

/-- Product naming for elaborator-minted simple-closure theorems.
    `safe` ↦ `generatedSafeV1`. Empty input is fail-closed to a non-legal
    placeholder that can never be a product invariant identifier. -/
def generatedSimpleClosureTheoremNameV1 (invName : String) : String :=
  if invName.isEmpty then
    "generatedEmptyV1"
  else
    -- Lean 4.31: prefer Pos.Raw over deprecated String.get.
    let head := (String.Pos.Raw.get invName 0).toUpper
    let tail := invName.drop 1
    "generated" ++ String.singleton head ++ tail ++ "V1"

/-- Compatibility bridge declaration name:
    `generatedSafeV1_of_wireTrace`. -/
def generatedSimpleClosureTheoremBridgeNameV1 (invName : String) : String :=
  generatedSimpleClosureTheoremNameV1 invName ++ "_of_wireTrace"

/-- Name-string definition emitted alongside the bridge:
    `generatedSafeV1Name`. -/
def generatedSimpleClosureTheoremNameDefV1 (invName : String) : String :=
  generatedSimpleClosureTheoremNameV1 invName ++ "Name"

/-- Fixed elaborator surface names authors must not use as invariant ids. -/
private def isFixedInlineProofSurfaceNameV1 (name : String) : Bool :=
  name == "subjectProgramV1" || name == "subjectBytesV1" ||
    name == "subjectDataV1" || name == "subjectBodyEncodeOkV1" ||
    name == "subjectRootGatesOkV1" || name == "subjectStructureOkV1" ||
    name == "simpleClosureParamsV1" || name == "simpleClosureDataV1" ||
    name == "simpleClosureQnTailLegalV1" ||
    name == "simpleClosureParamsLegalV1"

/-- Invariant names reserved so elaborator-minted generated-* decls never collide. -/
private def isReservedInlineProofSurfaceNameV1 (name : String) : Bool :=
  isFixedInlineProofSurfaceNameV1 name ||
    (name.startsWith "generated" && name.endsWith "Name") ||
    (name.startsWith "generated" && name.endsWith "_of_wireTrace") ||
    (name.startsWith "generated" && name.endsWith "V1")

private def quoteByteArray (bytes : ByteArray) : MacroM (TSyntax `term) := do
  let hex := bytes.foldl (fun acc byte =>
    (acc.push (Nat.digitChar (byte.toNat / 16))).push
      (Nat.digitChar (byte.toNat % 16))) ""
  `(ProofForgeV2.Language.ProgramExport.programExportBytesFromHex $(quote hex))

/-- Transparent `ByteArray.mk (List.toArray […])` form for proof subjects.
    Definitional equality with certificate `TransparentByteSpineV1` lists
    avoids hex reduction while preserving exact product bytes from Normalize. -/
private def quoteByteArraySpine (bytes : ByteArray) : MacroM (TSyntax `term) := do
  let mut elems : Array (TSyntax `term) := #[]
  for b in bytes do
    elems := elems.push (quote b.toNat)
  `(ByteArray.mk (List.toArray [$elems,*]))

/-- Quote a `String` array as `#[…]` for certificate param emission. -/
private def quoteStringArray (xs : Array String) : MacroM (TSyntax `term) := do
  let mut elems : Array (TSyntax `term) := #[]
  for s in xs do
    elems := elems.push (quote s)
  `(#[$elems,*])

private def quoteModelOptionStringV1
    (value : Option String) : MacroM (TSyntax `term) :=
  match value with
  | none => `(none)
  | some text => `(some $(quote text))

private def quoteModelVisibilityV1
    (visibility : ProofForgeV2.Semantic.WireV1.VisibilityV1) :
    MacroM (TSyntax `term) :=
  match visibility with
  | .public_ => `(ProofForgeV2.Semantic.WireV1.VisibilityV1.public_)
  | .private_ => `(ProofForgeV2.Semantic.WireV1.VisibilityV1.private_)
  | .commitment => `(ProofForgeV2.Semantic.WireV1.VisibilityV1.commitment)

/-- Quote name-parameterized simple-closure certificate params (no bytes). -/
private def quoteSimpleClosureParams
    (p : SimpleClosureParamsV1) : MacroM (TSyntax `term) := do
  let tail ← quoteStringArray p.qnTail
  `(ProofForgeV2.Semantic.SimpleClosureTraceV1.SimpleClosureParamsV1.mk
      $(quote p.qnHead) $tail $(quote p.viewName) $(quote p.invName))

/-- Kernel proof for one concrete ASCII identifier component. Runtime admission
    below is only a fail-closed precheck; this generated term is rechecked by
    the Lean kernel and contains no native evaluation or axiom. -/
private def quoteAsciiIdentifierProofV1
    (value : String) : MacroM (TSyntax `term) :=
  `(by
      change ProofForgeV2.Core.Common.validateIdentifierComponent $(quote value) =
        .ok ()
      rfl)

/-- Constructor spine proving every concrete QN tail component legal. -/
private def quoteIdentifierListLegalV1 :
    List String → MacroM (TSyntax `term)
  | [] =>
      `(ProofForgeV2.Semantic.SimpleClosureStructureCertV1.IdentifierListLegalV1.nil)
  | head :: tail => do
      let headProof ← quoteAsciiIdentifierProofV1 head
      let tailProof ← quoteIdentifierListLegalV1 tail
      `(ProofForgeV2.Semantic.SimpleClosureStructureCertV1.IdentifierListLegalV1.cons
          (head := $(quote head)) $headProof $tailProof)

private def identifierReadyForGeneratedProofV1 (value : String) : Bool :=
  ProofForgeV2.Core.Unicode.isAscii value &&
    match ProofForgeV2.Core.Common.validateIdentifierComponent value with
    | .ok () => true
    | .error _ => false

/-- Narrow compiler-owned admission for premise-free helper emission. Semantic
    encode/decode theorems remain Unicode-general; this elaborator slice only
    emits concrete `rfl` identifier certificates for ASCII portable names. -/
private def simpleClosureParamsReadyForGeneratedProofV1
    (p : SimpleClosureParamsV1) : Bool :=
  decide (2 ≤ p.qnSize) && decide (p.qnSize ≤ 256) &&
    decide (p.viewName ≠ p.invName) &&
    identifierReadyForGeneratedProofV1 p.qnHead &&
    p.qnTail.all identifierReadyForGeneratedProofV1 &&
    identifierReadyForGeneratedProofV1 p.viewName &&
    identifierReadyForGeneratedProofV1 p.invName

/-- Recover simple-closure certificate params from Normalize product bytes.
    Fail closed (none) when the carrier is outside the literal-true family. -/
private def extractSimpleClosureParamsFromCarrierV1
    (carrier : SemanticProgramV1) : Option SimpleClosureParamsV1 :=
  match decodeSemanticProgramDataV1 carrier.canonicalBytes with
  | .error _ => none
  | .ok data =>
      if isSimpleClosureFamilyDataV1 data then
        extractSimpleClosureParamsV1 data
      else
        none

private structure ProofSurfaceV1 where
  invariantNames : Array String
  holdsNames : Array String
  preservingNames : Array String

private inductive ModelStateScalarV1 where
  | bool
  | uint64

private structure ModelStateFieldV1 where
  name : String
  scalar : ModelStateScalarV1

private inductive ModelCallableResultV1 where
  | unit
  | bool
  | uint64

private structure ModelCallableParameterV1 where
  name : String
  typeId : TypeIdV1

private structure ModelCallableViewV1 where
  name : String
  callableId : CallableIdV1
  params : Array ModelCallableParameterV1
  resultTypeId : TypeIdV1
  result : ModelCallableResultV1

private structure ModelInvariantFieldEqualityV1 where
  invariant : InvariantDeclV1
  callable : CallableV1
  valueType : TypeDeclV1
  boolType : TypeDeclV1
  leftState : StateDeclV1
  rightState : StateDeclV1

private structure ModelInvariantViewV1 where
  name : String
  ordinal : Nat
  fieldEquality : Option ModelInvariantFieldEqualityV1

/-- Phase-1 typed-state support is deliberately narrow and fail closed. The
    mapping is read from the exact lowered subject data; source AST types are
    never reinterpreted here. `none` means no `Model` surface is emitted. -/
private def modelStateFieldsV1
    (data : SemanticProgramDataV1) : Option (Array ModelStateFieldV1) := do
  let mut fields := #[]
  for stateDecl in data.logicalState do
    -- Avoid names owned by a generated Lean structure in the pinned toolchain.
    -- This is only a Model-surface limitation: returning `none` must not reject
    -- or alter the existing DSL program and Proof subject surface.
    let structureOwnedName := match stateDecl.name with
      | "mk" | "rec" | "recOn" | "casesOn" | "ctorIdx"
      | "noConfusion" | "noConfusionType" | "_sizeOf_1" | "_sizeOf_inst" => true
      | _ => false
    guard (!structureOwnedName)
    let typeDecl ← data.types[stateDecl.typeId.toNat]?
    let scalar ← match typeDecl.shape with
      | .bool => some .bool
      | .uint 64 => some .uint64
      | _ => none
    fields := fields.push { name := stateDecl.name, scalar }
  pure fields

/-- Generated callable namespaces must not replace the fixed Model state/codec
    surface. Unsupported collisions with these exact names simply withhold that
    optional callable view; they never reject or reinterpret the DSL program. -/
private def isReservedModelCallableNameV1 (name : String) : Bool :=
  name == "State" || name == "encodeState" || name == "decodeState" ||
    name == "encode_exists" || name == "decode_encode" ||
    name == "encode_injective_of_eq_ok" ||
    name == "decode_existsUnique_of_conforms" ||
    name == "encode_decode_of_conforms" || name == "conforms_of_encode" ||
    name == "conforms_iff_exists_encode" || name == "ReferenceSubject" ||
    name == "admitReferenceSubject" || name == "LifecycleState" ||
    name == "initialLifecycleState" || name == "Outcome" ||
    name == "Invariant"

/-- Typed invariant predicates occupy the Model root while their exact
    evaluator bridge theorems live under `Model.Invariant`. Unsupported name
    collisions with either fixed surface fail closed without changing the DSL
    program or its Proof aliases. -/
private def isReservedModelInvariantNameV1 (name : String) : Bool :=
  isReservedModelCallableNameV1 name || name == "init"

/-- Recognize only the exact lowered CFG for equality between two generated
    UInt64 state fields. This reads `SemanticProgramDataV1`, not the source AST,
    and returns `none` for every additional block, instruction, value-id shape,
    type, or fuel variant. The result is metadata for theorem emission only;
    execution remains owned by `evalInvariantV1` / `runInvariantCallableV1`. -/
private def modelInvariantFieldEqualityV1?
    (data : SemanticProgramDataV1) (invariant : InvariantDeclV1)
    (ordinal : Nat) :
    Option ModelInvariantFieldEqualityV1 := do
  guard (invariant.id.toNat == ordinal)
  let callable ← data.callables[invariant.callableId.toNat]?
  guard (callable.id == invariant.callableId)
  guard (callable.kind == .invariant)
  guard (callable.name == some invariant.name)
  guard callable.params.isEmpty
  guard (callable.result.visibility == .public_)
  guard (callable.entryBlock == 0)
  guard callable.loopBounds.isEmpty
  guard (callable.invariantSteps == some 5)
  guard (callable.blocks.size == 1)
  let block ← callable.blocks[0]?
  guard (block.id == 0)
  guard block.params.isEmpty
  guard (block.instructions.size == 3)
  let leftInstruction ← block.instructions[0]?
  let rightInstruction ← block.instructions[1]?
  let equalityInstruction ← block.instructions[2]?
  let leftResult ← leftInstruction.result
  let rightResult ← rightInstruction.result
  let equalityResult ← equalityInstruction.result
  guard (leftResult.valueId == 0)
  guard (rightResult.valueId == 1)
  guard (equalityResult.valueId == 2)
  let leftStateId ← match leftInstruction.op with
    | .stateLoad stateId => some stateId
    | _ => none
  let rightStateId ← match rightInstruction.op with
    | .stateLoad stateId => some stateId
    | _ => none
  match equalityInstruction.op with
  | .binary .eq leftValueId rightValueId =>
      guard (leftValueId == 0 && rightValueId == 1)
  | _ => none
  match block.terminator with
  | .return_ (some valueId) => guard (valueId == 2)
  | _ => none
  guard (leftResult.typeId == rightResult.typeId)
  guard (callable.result.typeId == equalityResult.typeId)
  let valueType ← data.types[leftResult.typeId.toNat]?
  guard (valueType.id == leftResult.typeId)
  match valueType.shape with
  | .uint 64 => pure ()
  | _ => none
  let boolType ← data.types[equalityResult.typeId.toNat]?
  guard (boolType.id == equalityResult.typeId)
  guard boolType.name.isNone
  match boolType.shape with
  | .bool => pure ()
  | _ => none
  let leftState ← data.logicalState[leftStateId.toNat]?
  let rightState ← data.logicalState[rightStateId.toNat]?
  guard (leftState.id == leftStateId)
  guard (rightState.id == rightStateId)
  guard (leftState.typeId == valueType.id)
  guard (rightState.typeId == valueType.id)
  pure {
    invariant := invariant
    callable := callable
    valueType := valueType
    boolType := boolType
    leftState := leftState
    rightState := rightState
  }

private def modelInvariantViewsV1
    (data : SemanticProgramDataV1) : Array ModelInvariantViewV1 :=
  data.invariants.zipIdx.filterMap fun (invariant, ordinal) =>
    if isReservedModelInvariantNameV1 invariant.name then
      none
    else
      some {
        name := invariant.name
        ordinal
        fieldEquality := modelInvariantFieldEqualityV1? data invariant ordinal
      }

/-- Project the common supported callable shape from the exact lowered table.
    Root-kind selection remains separate below so initializer lifecycle cannot
    be folded into the initialized entry/view surface. -/
private def modelCallableShapeV1?
    (data : SemanticProgramDataV1) (callable : CallableV1) :
    Option ModelCallableViewV1 := do
  let name ← callable.name
  guard (!isReservedModelCallableNameV1 name)
  let params ← callable.params.mapM fun param => do
    let typeDecl ← data.types[param.typeId.toNat]?
    match typeDecl.shape with
    | .uint 64 =>
        pure { name := param.name, typeId := param.typeId }
    | _ => none
  let resultDecl ← data.types[callable.result.typeId.toNat]?
  let result ← match resultDecl.shape with
    | .unit => some .unit
    | .bool => some .bool
    | .uint 64 => some .uint64
    | _ => none
  pure {
    name
    callableId := callable.id
    params
    resultTypeId := callable.result.typeId
    result
  }

/-- Phase-2 initialized callable subset. Initializers are deliberately not
    selected here: they use the independent lifecycle emitter below. -/
private def modelCallableViewV1?
    (data : SemanticProgramDataV1) (callable : CallableV1) :
    Option ModelCallableViewV1 := do
  guard (callable.kind == .entry || callable.kind == .view)
  modelCallableShapeV1? data callable

private def modelCallableViewsV1
    (data : SemanticProgramDataV1) : Array ModelCallableViewV1 :=
  data.callables.filterMap (modelCallableViewV1? data)

/-- Phase-2 initializer subset. It shares only the exact parameter/result
    projection with ordinary callables; its relation starts from the production
    initial lifecycle carrier rather than an initialized typed `State`. -/
private def modelInitializerViewV1?
    (data : SemanticProgramDataV1) (callable : CallableV1) :
    Option ModelCallableViewV1 := do
  guard (callable.kind == .initializer)
  -- Initializers are anonymous on the canonical Wire surface. Give the sole
  -- source `init` declaration its author-facing namespace only in this proof
  -- projection, and fail closed if a named callable would collide with it.
  guard (!(data.callables.any fun candidate => candidate.name == some "init"))
  modelCallableShapeV1? data { callable with name := some "init" }

private def modelInitializerViewsV1
    (data : SemanticProgramDataV1) : Array ModelCallableViewV1 :=
  data.callables.filterMap (modelInitializerViewV1? data)

private def quoteModelStateTypeV1
    (scalar : ModelStateScalarV1) : MacroM (TSyntax `term) :=
  match scalar with
  | .bool => `(Bool)
  | .uint64 => `(UInt64)

private def quoteModelStateEncodeV1
    (stateName : TSyntax `ident)
    (fieldName : TSyntax `ident)
    (scalar : ModelStateScalarV1) : MacroM (TSyntax `term) :=
  match scalar with
  | .bool =>
      `(ProofForgeV2.Semantic.WireV1.encodeBool $stateName.$fieldName)
  | .uint64 =>
      `(ProofForgeV2.Semantic.WireV1.encodeU64le $stateName.$fieldName)

private def quoteModelStateDecodeV1
    (valueBytes : TSyntax `term)
    (scalar : ModelStateScalarV1) : MacroM (TSyntax `term) :=
  match scalar with
  | .bool =>
      `(ProofForgeV2.Semantic.StateModelV1.boolOfCanonicalValueBytesV1 $valueBytes)
  | .uint64 =>
      `(ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1 $valueBytes)

/-- Quote one supported callable result type. -/
private def quoteModelCallableResultTypeV1
    (result : ModelCallableResultV1) : MacroM (TSyntax `term) :=
  match result with
  | .unit => `(Unit)
  | .bool => `(Bool)
  | .uint64 => `(UInt64)

/-- Quote the exact canonical Reference result projection for one callable.
    Unit is represented by `none`; Bool/UInt64 retain the declaration TypeId and
    use the production Wire scalar encoding. -/
private def quoteModelCallableResultEncodeV1
    (result : ModelCallableResultV1)
    (typeId : TypeIdV1) : MacroM (TSyntax `term) := do
  let typeIdTerm : TSyntax `term :=
    ⟨Syntax.mkNumLit (toString typeId.toNat)⟩
  match result with
  | .unit =>
      `(fun _value : Unit => none)
  | .bool =>
      `(fun value : Bool => some ({
          typeId := $typeIdTerm
          valueBytes := ProofForgeV2.Semantic.WireV1.encodeBool value
        } : ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1))
  | .uint64 =>
      `(fun value : UInt64 => some ({
          typeId := $typeIdTerm
          valueBytes := ProofForgeV2.Semantic.WireV1.encodeU64le value
        } : ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1))

/-- Decode the callable's canonical Reference result with the exact lowered
    TypeId and the production valueBytes validator/projection. -/
private def quoteModelCallableResultDecodeV1
    (subjectDataName : TSyntax `ident)
    (result : ModelCallableResultV1)
    (typeId : TypeIdV1) : MacroM (TSyntax `term) := do
  let typeIdTerm : TSyntax `term :=
    ⟨Syntax.mkNumLit (toString typeId.toNat)⟩
  match result with
  | .unit =>
      `(fun referenceValue : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1 =>
        match referenceValue with
        | none => .ok ()
        | some _ => .error .nonCanonical)
  | .bool =>
      `(fun referenceValue : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1 =>
        match referenceValue with
        | none => ProofForgeV2.Semantic.WireV1.err .nonCanonical
        | some value =>
            if value.typeId == $typeIdTerm then do
              ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                ($subjectDataName).types $typeIdTerm value.valueBytes
              pure
                (ProofForgeV2.Semantic.StateModelV1.boolOfCanonicalValueBytesV1
                  value.valueBytes)
            else
              ProofForgeV2.Semantic.WireV1.err .nonCanonical)
  | .uint64 =>
      `(fun referenceValue : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1 =>
        match referenceValue with
        | none => ProofForgeV2.Semantic.WireV1.err .nonCanonical
        | some value =>
            if value.typeId == $typeIdTerm then do
              ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                ($subjectDataName).types $typeIdTerm value.valueBytes
              pure
                (ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1
                  value.valueBytes)
            else
              ProofForgeV2.Semantic.WireV1.err .nonCanonical)

/-- Close decode-after-encode for a generated result codec. UInt64 validation
    uses the production fixed-width theorem for the exact lowered type row. -/
private def quoteModelCallableResultDecodeEncodeV1
    (subjectDataName : TSyntax `ident)
    (encodeResultName decodeResultName : TSyntax `ident)
    (result : ModelCallableResultV1)
    (typeId : TypeIdV1)
    (typeDeclTerm : TSyntax `term) : MacroM (TSyntax `term) := do
  let typeIdTerm : TSyntax `term :=
    ⟨Syntax.mkNumLit (toString typeId.toNat)⟩
  match result with
  | .unit =>
      `(by
        unfold $encodeResultName $decodeResultName
        cases value
        rfl)
  | .bool =>
      `(by
        have hcanonical :
            ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                ($subjectDataName).types $typeIdTerm
                  (ProofForgeV2.Semantic.WireV1.encodeBool value) = .ok () := by
          apply
            ProofForgeV2.Semantic.WireV1.validateValueBytesV1_encodeBool
              ($subjectDataName).types $typeIdTerm $typeDeclTerm value
          · rfl
          · rfl
        unfold $encodeResultName $decodeResultName
        change
          (do
            ProofForgeV2.Semantic.WireV1.validateValueBytesV1
              ($subjectDataName).types $typeIdTerm
                (ProofForgeV2.Semantic.WireV1.encodeBool value)
            pure
              (ProofForgeV2.Semantic.StateModelV1.boolOfCanonicalValueBytesV1
                (ProofForgeV2.Semantic.WireV1.encodeBool value))) = .ok value
        rw [hcanonical]
        exact congrArg Except.ok
          (ProofForgeV2.Semantic.StateModelV1.boolOfCanonicalValueBytesV1_encodeBool
            value))
  | .uint64 =>
      `(by
        have hcanonical :
            ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                ($subjectDataName).types $typeIdTerm
                  (ProofForgeV2.Semantic.WireV1.encodeU64le value) = .ok () := by
          apply
            ProofForgeV2.Semantic.WireV1.validateValueBytesV1_uint64_of_size
              ($subjectDataName).types $typeIdTerm $typeDeclTerm
          · rfl
          · rfl
          · exact ProofForgeV2.Semantic.WireV1.encodeU64le_size value
        unfold $encodeResultName $decodeResultName
        change
          (do
            ProofForgeV2.Semantic.WireV1.validateValueBytesV1
              ($subjectDataName).types $typeIdTerm
                (ProofForgeV2.Semantic.WireV1.encodeU64le value)
            pure
              (ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1
                (ProofForgeV2.Semantic.WireV1.encodeU64le value))) = .ok value
        rw [hcanonical]
        exact congrArg Except.ok
          (ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1_encodeU64le
            value))

/-- Close exact typed decode/re-encode and uniqueness for every
    production-conforming result carrier in the generated Unit/Bool/UInt64
    subset. This consumes the machine's `ReferenceResultConformsV1` predicate
    and the same production validator used by `decodeResult`; it does not
    execute the callable. -/
private def quoteModelCallableResultDecodeCompleteV1
    (subjectDataName : TSyntax `ident)
    (encodeResultName decodeResultName : TSyntax `ident)
    (result : ModelCallableResultV1)
    (callableId : CallableIdV1)
    (typeId : TypeIdV1)
    (typeDeclTerm : TSyntax `term) : MacroM (TSyntax `term) := do
  let callableIdTerm : TSyntax `term :=
    ⟨Syntax.mkNumLit (toString callableId.toNat)⟩
  let typeIdTerm : TSyntax `term :=
    ⟨Syntax.mkNumLit (toString typeId.toNat)⟩
  match result with
  | .unit =>
      `(fun
          (referenceValue : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          (hconforms :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
              $subjectDataName
              (($subjectDataName).callables[$callableIdTerm]'(by decide)).result
              referenceValue) =>
          show ∃ value : Unit,
            $decodeResultName referenceValue = .ok value ∧
              $encodeResultName value = referenceValue ∧
                ∀ other : Unit,
                  $decodeResultName referenceValue = .ok other →
                    value = other from by
        cases referenceValue with
        | none =>
            refine ⟨(), rfl, rfl, ?_⟩
            intro other hother
            cases other
            rfl
        | some value =>
            have hfalse : False := by
              have htypeId :
                  (($subjectDataName).callables[$callableIdTerm]'(by decide)).result.typeId =
                    $typeIdTerm := by
                rfl
              have hisUnit :
                  (match ($subjectDataName).types[
                    (($typeIdTerm : ProofForgeV2.Semantic.WireV1.TypeIdV1).toNat)]? with
                  | some { shape := .unit, .. } => true
                  | _ => false) = true := by
                rfl
              unfold
                ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
                at hconforms
              rw [htypeId] at hconforms
              dsimp only at hconforms
              exact Bool.noConfusion (hisUnit.symm.trans hconforms.1)
            exact hfalse.elim)
  | .bool =>
      `(fun
          (referenceValue : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          (hconforms :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
              $subjectDataName
              (($subjectDataName).callables[$callableIdTerm]'(by decide)).result
              referenceValue) =>
          show ∃ value : Bool,
            $decodeResultName referenceValue = .ok value ∧
              $encodeResultName value = referenceValue ∧
                ∀ other : Bool,
                  $decodeResultName referenceValue = .ok other →
                    value = other from by
        cases referenceValue with
        | none =>
            have hfalse : False := by
              have htypeId :
                  (($subjectDataName).callables[$callableIdTerm]'(by decide)).result.typeId =
                    $typeIdTerm := by
                rfl
              have hisUnit :
                  (match ($subjectDataName).types[
                    (($typeIdTerm : ProofForgeV2.Semantic.WireV1.TypeIdV1).toNat)]? with
                  | some { shape := .unit, .. } => true
                  | _ => false) = false := by
                rfl
              unfold
                ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
                at hconforms
              rw [htypeId] at hconforms
              dsimp only at hconforms
              exact Bool.noConfusion (hisUnit.symm.trans hconforms)
            exact hfalse.elim
        | some referenceValue =>
            rcases referenceValue with ⟨valueTypeId, valueBytes⟩
            have hnormalized :
                valueTypeId = $typeIdTerm ∧
                  ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                    ($subjectDataName).types valueTypeId valueBytes = .ok () := by
              have htypeId :
                  (($subjectDataName).callables[$callableIdTerm]'(by decide)).result.typeId =
                    $typeIdTerm := by
                rfl
              have hisUnit :
                  (match ($subjectDataName).types[
                    (($typeIdTerm : ProofForgeV2.Semantic.WireV1.TypeIdV1).toNat)]? with
                  | some { shape := .unit, .. } => true
                  | _ => false) = false := by
                rfl
              unfold
                ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
                at hconforms
              rw [htypeId] at hconforms
              dsimp only at hconforms
              exact hconforms.2
            rcases hnormalized with ⟨htype, hcanonical⟩
            subst valueTypeId
            let typedValue :=
              ProofForgeV2.Semantic.StateModelV1.boolOfCanonicalValueBytesV1
                valueBytes
            have hsuccess :
                $decodeResultName (some {
                  typeId := $typeIdTerm
                  valueBytes := valueBytes
                }) = .ok typedValue := by
              unfold $decodeResultName
              simp [hcanonical, typedValue, Pure.pure, Except.pure, Bind.bind,
                Except.bind]
            have hencodeBytes :
                ProofForgeV2.Semantic.WireV1.encodeBool typedValue =
                  valueBytes :=
              ProofForgeV2.Semantic.StateModelV1.encodeBool_boolOfCanonicalValueBytesV1
                ($subjectDataName).types $typeIdTerm $typeDeclTerm valueBytes
                  (by rfl) (by rfl) hcanonical
            have hencode :
                $encodeResultName typedValue = some {
                  typeId := $typeIdTerm
                  valueBytes := valueBytes
                } := by
              unfold $encodeResultName
              exact congrArg
                (fun bytes => some ({
                  typeId := $typeIdTerm
                  valueBytes := bytes
                } : ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1))
                hencodeBytes
            refine ⟨typedValue, hsuccess, hencode, ?_⟩
            intro other hother
            exact Except.ok.inj (hsuccess.symm.trans hother))
  | .uint64 =>
      `(fun
          (referenceValue : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          (hconforms :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
              $subjectDataName
              (($subjectDataName).callables[$callableIdTerm]'(by decide)).result
              referenceValue) =>
          show ∃ value : UInt64,
            $decodeResultName referenceValue = .ok value ∧
              $encodeResultName value = referenceValue ∧
                ∀ other : UInt64,
                  $decodeResultName referenceValue = .ok other →
                    value = other from by
        cases referenceValue with
        | none =>
            have hfalse : False := by
              have htypeId :
                  (($subjectDataName).callables[$callableIdTerm]'(by decide)).result.typeId =
                    $typeIdTerm := by
                rfl
              have hisUnit :
                  (match ($subjectDataName).types[
                    (($typeIdTerm : ProofForgeV2.Semantic.WireV1.TypeIdV1).toNat)]? with
                  | some { shape := .unit, .. } => true
                  | _ => false) = false := by
                rfl
              unfold
                ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
                at hconforms
              rw [htypeId] at hconforms
              dsimp only at hconforms
              exact Bool.noConfusion (hisUnit.symm.trans hconforms)
            exact hfalse.elim
        | some referenceValue =>
            rcases referenceValue with ⟨valueTypeId, valueBytes⟩
            have hnormalized :
                valueTypeId = $typeIdTerm ∧
                  ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                    ($subjectDataName).types valueTypeId valueBytes = .ok () := by
              have htypeId :
                  (($subjectDataName).callables[$callableIdTerm]'(by decide)).result.typeId =
                    $typeIdTerm := by
                rfl
              have hisUnit :
                  (match ($subjectDataName).types[
                    (($typeIdTerm : ProofForgeV2.Semantic.WireV1.TypeIdV1).toNat)]? with
                  | some { shape := .unit, .. } => true
                  | _ => false) = false := by
                rfl
              unfold
                ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
                at hconforms
              rw [htypeId] at hconforms
              dsimp only at hconforms
              exact hconforms.2
            rcases hnormalized with ⟨htype, hcanonical⟩
            subst valueTypeId
            let typedValue :=
              ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1
                valueBytes
            have hsuccess :
                $decodeResultName (some {
                  typeId := $typeIdTerm
                  valueBytes := valueBytes
                }) = .ok typedValue := by
              unfold $decodeResultName
              simp [hcanonical, typedValue, Pure.pure, Except.pure, Bind.bind,
                Except.bind]
            have hencodeBytes :
                ProofForgeV2.Semantic.WireV1.encodeU64le typedValue =
                  valueBytes :=
              ProofForgeV2.Semantic.StateModelV1.encodeU64le_uint64OfCanonicalValueBytesV1
                ($subjectDataName).types $typeIdTerm $typeDeclTerm valueBytes
                  (by rfl) (by rfl) hcanonical
            have hencode :
                $encodeResultName typedValue = some {
                  typeId := $typeIdTerm
                  valueBytes := valueBytes
                } := by
              unfold $encodeResultName
              exact congrArg
                (fun bytes => some ({
                  typeId := $typeIdTerm
                  valueBytes := bytes
                } : ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1))
                hencodeBytes
            refine ⟨typedValue, hsuccess, hencode, ?_⟩
            intro other hother
            exact Except.ok.inj (hsuccess.symm.trans hother))

/-- Emit the program-level positive admission carrier and one exact relation
    namespace per supported entry/view. The generated surface constructs only
    canonical invocation values and delegates every outcome to
    `TypedCallableRelationV1`, whose sole executable authority is
    `stepReferenceSliceV1`. -/
private def elaborateCallableModelsV1
    (subjectProgramName : TSyntax `ident)
    (subjectDataName : TSyntax `ident)
    (encodeStateName : TSyntax `ident)
    (decodeStateName : TSyntax `ident)
    (encodeStateDecodeName : TSyntax `ident)
    (data : SemanticProgramDataV1)
    (views : Array ModelCallableViewV1) : CommandElabM Unit := do
  let referenceSubjectName := mkIdent `ReferenceSubject
  let admitReferenceSubjectName := mkIdent `admitReferenceSubject
  let outcomeName := mkIdent `Outcome
  let stateName := mkIdent `State
  let resultName := mkIdent `Result
  let encodeInjectiveName := mkIdent `encode_injective_of_eq_ok
  Lean.Elab.Command.elabCommand (← `(
    /-- Positive Reference admission carrier bound to this exact generated
        semantic subject. One value is shared by all callable relations. -/
    abbrev $referenceSubjectName :=
      ProofForgeV2.Semantic.PreservationABI.AdmittedSubjectV1
        $subjectProgramName))
  Lean.Elab.Command.elabCommand (← `(
    /-- Invoke the sole production admission function for this exact subject. -/
    def $admitReferenceSubjectName :
        Except ProofForgeV2.Semantic.ReferenceV1.ReferenceAdmissionErrorV1
          $referenceSubjectName :=
      ProofForgeV2.Semantic.PreservationABI.admitSubjectV1
        $subjectProgramName))
  Lean.Elab.Command.elabCommand (← `(
    /-- Typed three-branch outcome view; effects/reasons/faults remain the
        canonical Reference carriers. -/
    abbrev $outcomeName ($resultName : Type) :=
      ProofForgeV2.Semantic.PreservationABI.TypedOutcomeV1
        $stateName $resultName))
  for callableView in views do
    let callableNamespace := mkIdent (Name.mkSimple callableView.name)
    let invocationName := mkIdent `invocation
    let resultName := mkIdent `Result
    let encodeResultName := mkIdent `encodeResult
    let decodeResultName := mkIdent `decodeResult
    let decodeEncodeResultName := mkIdent `decode_encode_result
    let decodeResultCompleteName := mkIdent `decodeResult_complete_of_conforms
    let decodeResultExistsUniqueName :=
      mkIdent `decodeResult_existsUnique_of_conforms
    let decodeReturnedResultCompleteName :=
      mkIdent `decodeResult_complete_of_returned
    let decodeReturnedResultExistsUniqueName :=
      mkIdent `decodeResult_existsUnique_of_returned
    let decodeReturnedStateCompleteName :=
      mkIdent `decodeState_complete_of_returned
    let decodeReturnedStateExistsUniqueName :=
      mkIdent `decodeState_existsUnique_of_returned
    let encodeResultInjectiveName := mkIdent `encodeResult_injective
    let callableOutcomeName := mkIdent `Outcome
    let transitionName := mkIdent `Transition
    let transitionReturnedName := mkIdent `transition_returned_of_step
    let transitionRevertedName := mkIdent `transition_reverted_of_step
    let transitionTrappedName := mkIdent `transition_trapped_of_step
    let transitionExistsName := mkIdent `transition_exists
    let outcomeUniqueName := mkIdent `outcome_unique
    let subjectName := mkIdent `subject
    let preName := mkIdent `pre
    let contextName := mkIdent `context
    let responsesName := mkIdent `responses
    let vaultName := mkIdent `vault
    let typedOutcomeName := mkIdent `outcome
    let leftOutcomeName := mkIdent `left
    let rightOutcomeName := mkIdent `right
    let leftTransitionName := mkIdent `hleft
    let rightTransitionName := mkIdent `hright
    let referenceValueName := mkIdent `referenceValue
    let conformsName := mkIdent `hconforms
    let logicalPreName := mkIdent `logicalPre
    let logicalPostName := mkIdent `logicalPost
    let effectsName := mkIdent `effects
    let reasonName := mkIdent `reason
    let faultName := mkIdent `fault
    let unchangedName := mkIdent `unchanged
    let validateName := mkIdent `hvalidate
    let initializedName := mkIdent `hinitialized
    let encodePreName := mkIdent `hencodePre
    let stepName := mkIdent `hstep
    let callableIdTerm : TSyntax `term :=
      ⟨Syntax.mkNumLit (toString callableView.callableId.toNat)⟩
    let paramNames := callableView.params.map fun param =>
      mkIdent (Name.mkSimple (param.name ++ "Arg"))
    let paramTypes ← Lean.Elab.liftMacroM <|
      callableView.params.mapM fun _ => `(UInt64)
    let referenceArgs ← Lean.Elab.liftMacroM <|
      callableView.params.zip paramNames |>.mapM fun (param, paramName) => do
        let typeIdTerm : TSyntax `term :=
          ⟨Syntax.mkNumLit (toString param.typeId.toNat)⟩
        `(({ typeId := $typeIdTerm
             valueBytes := ProofForgeV2.Semantic.WireV1.encodeU64le $paramName
           } : ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1))
    let resultType ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultTypeV1 callableView.result
    let resultEncode ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultEncodeV1 callableView.result callableView.resultTypeId
    let resultDecode ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultDecodeV1
        subjectDataName callableView.result callableView.resultTypeId
    let resultTypeDecl ← match data.types[callableView.resultTypeId.toNat]? with
      | some value => pure value
      | none => throwError
          "generated callable result is missing its production type declaration"
    let resultTypeDeclTerm ← Lean.Elab.liftMacroM <|
      ProofForgeV2.Language.SubjectDataQuoteV1.quoteTypeDeclV1 resultTypeDecl
    let resultDecodeEncode ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultDecodeEncodeV1 subjectDataName encodeResultName
        decodeResultName callableView.result callableView.resultTypeId
        resultTypeDeclTerm
    let resultDecodeComplete ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultDecodeCompleteV1 subjectDataName encodeResultName
        decodeResultName callableView.result callableView.callableId
        callableView.resultTypeId resultTypeDeclTerm
    let invocationTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($invocationName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName)
    let returnedResultCompleteTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($decodeReturnedResultCompleteName $subjectName
        $logicalPreName $logicalPostName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $referenceValueName
        $effectsName $validateName $stepName)
    let returnedStateCompleteTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($decodeReturnedStateCompleteName $subjectName
        $logicalPreName $logicalPostName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $referenceValueName
        $effectsName $initializedName $validateName $stepName)
    let returnedTransitionPrefixTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($transitionName $subjectName $preName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName)
    let leftTransitionTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($transitionName $subjectName $preName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $leftOutcomeName)
    let rightTransitionTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($transitionName $subjectName $preName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $rightOutcomeName)
    Lean.Elab.Command.elabCommand (← `(namespace $callableNamespace))
    Lean.Elab.Command.elabCommand (← `(
      /-- Lean result type projected from this exact callable row. -/
      abbrev $resultName := $resultType))
    Lean.Elab.Command.elabCommand (← `(
      /-- Encode this callable result into its canonical Reference carrier. -/
      def $encodeResultName (value : $resultName) : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1 :=
        $resultEncode value))
    Lean.Elab.Command.elabCommand (← `(
      /-- Decode only this callable's exact canonical Reference result. -/
      def $decodeResultName (referenceValue : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1) :
          Except ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1 $resultName :=
        $resultDecode referenceValue))
    Lean.Elab.Command.elabCommand (← `(
      /-- Callable result codec roundtrip through the production scalar
          validator and projection. -/
      theorem $decodeEncodeResultName (value : $resultName) :
          $decodeResultName ($encodeResultName value) = .ok value :=
        $resultDecodeEncode))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every conforming Reference result decodes, re-encodes to the exact
          original carrier, and has no second typed decode. -/
      theorem $decodeResultCompleteName
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($conformsName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
              $subjectDataName
              (($subjectDataName).callables[$callableIdTerm]'(by decide)).result
              $referenceValueName) :
          ∃ value : $resultName,
            $decodeResultName $referenceValueName = .ok value ∧
              $encodeResultName value = $referenceValueName ∧
                ∀ other : $resultName,
                  $decodeResultName $referenceValueName = .ok other →
                    value = other :=
        $resultDecodeComplete $referenceValueName $conformsName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every Reference result conforming to this exact lowered callable row
          has one unique typed decode through the production validator. -/
      theorem $decodeResultExistsUniqueName
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($conformsName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
              $subjectDataName
              (($subjectDataName).callables[$callableIdTerm]'(by decide)).result
              $referenceValueName) :
          ∃ value : $resultName,
            $decodeResultName $referenceValueName = .ok value ∧
              ∀ other : $resultName,
                $decodeResultName $referenceValueName = .ok other →
                  value = other := by
        obtain ⟨value, hdecode, _hencode, hunique⟩ :=
          $decodeResultCompleteName $referenceValueName $conformsName
        exact ⟨value, hdecode, hunique⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- Canonical result encoding is injective because generated decoding is
          its left inverse. -/
      theorem $encodeResultInjectiveName :
          Function.Injective $encodeResultName := by
        intro left right h
        have hleft := ($decodeEncodeResultName left).symm
        have hmiddle := congrArg $decodeResultName h
        have hright := $decodeEncodeResultName right
        exact Except.ok.inj (hleft.trans (hmiddle.trans hright))))
    Lean.Elab.Command.elabCommand (← `(
      /-- Canonical invocation constructor for this exact callable row. Context
          remains explicit and is validated only by the sole Reference gate. -/
      def $invocationName
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1) :
          ProofForgeV2.Semantic.ReferenceV1.InvocationV1 := {
        callableId := $callableIdTerm
        args := #[$referenceArgs,*]
        context := $contextName
      }))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every successful production step for this generated invocation has
          one exact typed result decode/re-encode. Callable selection and result
          canonicality come from the sole Reference gate/machine. -/
      theorem $decodeReturnedResultCompleteName
          ($subjectName : $referenceSubjectName)
          ($logicalPreName $logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ value : $resultName,
            $decodeResultName $referenceValueName = .ok value ∧
              $encodeResultName value = $referenceValueName ∧
                ∀ other : $resultName,
                  $decodeResultName $referenceValueName = .ok other →
                    value = other := by
        have hadmittedData : ($subjectName).admitted.data = $subjectDataName :=
          (ProofForgeV2.Semantic.ReferenceV1.admitReferenceProgramSliceV1_ok_implies
            $subjectProgramName $subjectDataName ($subjectName).admitted
              $validateName ($subjectName).hadmit).2
        have hlookup :
            ($subjectName).admitted.data.callables[$callableIdTerm]? =
              some (($subjectDataName).callables[$callableIdTerm]'(by decide)) := by
          rw [hadmittedData]
          rfl
        have hconforms :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_returned_resultConformsV1_of_lookup
            ($subjectName).admitted $logicalPreName $logicalPostName $invocationTerm
              $responsesName $vaultName
              (($subjectDataName).callables[$callableIdTerm]'(by decide))
              $referenceValueName $effectsName hlookup $stepName
        rw [hadmittedData] at hconforms
        exact $decodeResultCompleteName $referenceValueName hconforms))
    Lean.Elab.Command.elabCommand (← `(
      /-- Compatibility projection of the exact returned-result package to
          decode existence and uniqueness. -/
      theorem $decodeReturnedResultExistsUniqueName
          ($subjectName : $referenceSubjectName)
          ($logicalPreName $logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ value : $resultName,
            $decodeResultName $referenceValueName = .ok value ∧
              ∀ other : $resultName,
                $decodeResultName $referenceValueName = .ok other →
                  value = other := by
        obtain ⟨value, hdecode, _hencode, hunique⟩ :=
          $returnedResultCompleteTerm
        exact ⟨value, hdecode, hunique⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every returned initialized entry/view post-state has one exact typed
          decode/re-encode. Initializer lifecycle remains a separate proof
          surface. -/
      theorem $decodeReturnedStateCompleteName
          ($subjectName : $referenceSubjectName)
          ($logicalPreName $logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($initializedName : ($logicalPreName).initialized = true)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ post : $stateName,
            $decodeStateName $logicalPostName = .ok post ∧
              $encodeStateName post = .ok $logicalPostName ∧
                ∀ other : $stateName,
                  $decodeStateName $logicalPostName = .ok other →
                    post = other := by
        have hconforms :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_returned_stateConformsV1_of_initialized
            $subjectProgramName ($subjectName).admitted $logicalPreName
              $logicalPostName $invocationTerm $responsesName $vaultName
              $referenceValueName $effectsName ($subjectName).hadmit
              $initializedName $stepName
        obtain ⟨post, hdecode, hencode⟩ :=
          $encodeStateDecodeName $logicalPostName $validateName hconforms
        refine ⟨post, hdecode, hencode, ?_⟩
        intro other hother
        exact Except.ok.inj (hdecode.symm.trans hother)))
    Lean.Elab.Command.elabCommand (← `(
      /-- Compatibility projection of the exact returned-state package to
          decode existence and uniqueness. -/
      theorem $decodeReturnedStateExistsUniqueName
          ($subjectName : $referenceSubjectName)
          ($logicalPreName $logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($initializedName : ($logicalPreName).initialized = true)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ post : $stateName,
            $decodeStateName $logicalPostName = .ok post ∧
              ∀ other : $stateName,
                $decodeStateName $logicalPostName = .ok other →
                  post = other := by
        obtain ⟨post, hdecode, _hencode, hunique⟩ :=
          $returnedStateCompleteTerm
        exact ⟨post, hdecode, hunique⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- Typed full-outcome view specialized to this callable result type. -/
      abbrev $callableOutcomeName :=
        ProofForgeV2.Semantic.PreservationABI.TypedOutcomeV1
          $stateName $resultName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Exact typed relation for this callable. This is a theorem view over
          the sole Reference step, not a generated executable evaluator. -/
      def $transitionName
          ($subjectName : $referenceSubjectName)
          ($preName : $stateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($typedOutcomeName : $callableOutcomeName) : Prop :=
        ProofForgeV2.Semantic.PreservationABI.TypedCallableRelationV1
          $encodeStateName $encodeResultName $subjectName $preName
          $invocationTerm
          $responsesName $vaultName $typedOutcomeName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Package one exact returned Reference step as a typed transition.
          State/result witnesses come only from production-conforming codecs;
          this theorem does not execute a second step function. -/
      theorem $transitionReturnedName
          ($subjectName : $referenceSubjectName)
          ($preName : $stateName)
          ($logicalPreName $logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($encodePreName :
            $encodeStateName $preName = .ok $logicalPreName)
          ($initializedName : ($logicalPreName).initialized = true)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ post : $stateName, ∃ value : $resultName,
            $decodeStateName $logicalPostName = .ok post ∧
              $decodeResultName $referenceValueName = .ok value ∧
                $returnedTransitionPrefixTerm
                  (.returned post value $effectsName) := by
        obtain ⟨postWitness, hdecodePost, hencodePost, _huniquePost⟩ :=
          $returnedStateCompleteTerm
        obtain ⟨valueWitness, hdecodeValue, hencodeValue, _huniqueValue⟩ :=
          $returnedResultCompleteTerm
        refine ⟨postWitness, valueWitness, hdecodePost, hdecodeValue, ?_⟩
        unfold $transitionName
          ProofForgeV2.Semantic.PreservationABI.TypedCallableRelationV1
        refine ⟨$logicalPreName, $encodePreName, $logicalPostName,
          hencodePost, ?_⟩
        rw [hencodeValue]
        exact $stepName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Package one exact reverted Reference step as a typed transition.
          The production machine theorem proves that the carried failure state
          is the exact encoded pre-state; no second step function is run. -/
      theorem $transitionRevertedName
          ($subjectName : $referenceSubjectName)
          ($preName : $stateName)
          ($logicalPreName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($reasonName :
            ProofForgeV2.Semantic.ReferenceV1.SemanticRevertV1)
          ($unchangedName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          ($encodePreName :
            $encodeStateName $preName = .ok $logicalPreName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .reverted $reasonName $unchangedName) :
          $unchangedName = $logicalPreName ∧
            $returnedTransitionPrefixTerm (.reverted $reasonName) := by
        have hunchanged :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_reverted_state_eq
            ($subjectName).admitted $logicalPreName $invocationTerm
              $responsesName $vaultName $reasonName $unchangedName $stepName
        subst $unchangedName
        refine ⟨rfl, ?_⟩
        unfold $transitionName
          ProofForgeV2.Semantic.PreservationABI.TypedCallableRelationV1
        exact ⟨$logicalPreName, $encodePreName, $stepName⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- Package one exact trapped Reference step as a typed transition.
          The production machine theorem proves that the carried failure state
          is the exact encoded pre-state; no second step function is run. -/
      theorem $transitionTrappedName
          ($subjectName : $referenceSubjectName)
          ($preName : $stateName)
          ($logicalPreName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($faultName :
            ProofForgeV2.Semantic.ReferenceV1.SemanticFaultV1)
          ($unchangedName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          ($encodePreName :
            $encodeStateName $preName = .ok $logicalPreName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted $logicalPreName $invocationTerm
                  $responsesName $vaultName =
              .trapped $faultName $unchangedName) :
          $unchangedName = $logicalPreName ∧
            $returnedTransitionPrefixTerm (.trapped $faultName) := by
        have hunchanged :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_trapped_state_eq
            ($subjectName).admitted $logicalPreName $invocationTerm
              $responsesName $vaultName $faultName $unchangedName $stepName
        subst $unchangedName
        refine ⟨rfl, ?_⟩
        unfold $transitionName
          ProofForgeV2.Semantic.PreservationABI.TypedCallableRelationV1
        exact ⟨$logicalPreName, $encodePreName, $stepName⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every execution of the sole Reference step from an initialized typed
          pre-state has a typed outcome in this relation. The proof classifies
          that actual Reference outcome and delegates to the three exact
          branch bridges; it does not define or run a typed evaluator. -/
      theorem $transitionExistsName
          ($subjectName : $referenceSubjectName)
          ($preName : $stateName)
          ($logicalPreName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($encodePreName :
            $encodeStateName $preName = .ok $logicalPreName)
          ($initializedName : ($logicalPreName).initialized = true)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName) :
          ∃ outcome : $callableOutcomeName,
            $returnedTransitionPrefixTerm outcome := by
        generalize $stepName :
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
              ($subjectName).admitted $logicalPreName $invocationTerm
                $responsesName $vaultName = referenceOutcome
        cases referenceOutcome with
        | returned logicalPost referenceValue effects =>
            obtain ⟨post, value, _hdecodePost, _hdecodeValue, htransition⟩ :=
              $transitionReturnedName
                (subject := $subjectName) (pre := $preName)
                (logicalPre := $logicalPreName) (logicalPost := logicalPost)
                (context := $contextName) (responses := $responsesName)
                (vault := $vaultName) (referenceValue := referenceValue)
                (effects := effects) (hencodePre := $encodePreName)
                (hinitialized := $initializedName)
                (hvalidate := $validateName) (hstep := $stepName)
            exact ⟨.returned post value effects, htransition⟩
        | reverted reason unchanged =>
            have htransition :=
              ($transitionRevertedName
                (subject := $subjectName) (pre := $preName)
                (logicalPre := $logicalPreName) (context := $contextName)
                (responses := $responsesName) (vault := $vaultName)
                (reason := reason) (unchanged := unchanged)
                (hencodePre := $encodePreName) (hstep := $stepName)).2
            exact ⟨.reverted reason, htransition⟩
        | trapped fault unchanged =>
            have htransition :=
              ($transitionTrappedName
                (subject := $subjectName) (pre := $preName)
                (logicalPre := $logicalPreName) (context := $contextName)
                (responses := $responsesName) (vault := $vaultName)
                (fault := fault) (unchanged := unchanged)
                (hencodePre := $encodePreName) (hstep := $stepName)).2
            exact ⟨.trapped fault, htransition⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- The exact typed relation has at most one outcome for fixed inputs.
          This is inherited from the sole Reference step plus codec
          injectivity; it is not a second executable callable. -/
      theorem $outcomeUniqueName
          ($subjectName : $referenceSubjectName)
          ($preName : $stateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($leftOutcomeName $rightOutcomeName : $callableOutcomeName)
          ($leftTransitionName : $leftTransitionTerm)
          ($rightTransitionName : $rightTransitionTerm) :
          $leftOutcomeName = $rightOutcomeName := by
        exact
          ProofForgeV2.Semantic.PreservationABI.typedCallableRelationV1_outcome_unique
            $encodeStateName $encodeResultName $encodeInjectiveName
            $encodeResultInjectiveName $subjectName $preName $invocationTerm
            $responsesName $vaultName $leftOutcomeName $rightOutcomeName
            $leftTransitionName $rightTransitionName))
    Lean.Elab.Command.elabCommand (← `(end $callableNamespace))

/-- Emit the initializer-only authoring surface. Its pre-state is an exact
    `initialLogicalStateV1` carrier and its returned state is the generated
    initialized business `State`; initializer lifecycle is therefore never
    folded into the ordinary entry/view relation. -/
private def elaborateInitializerModelsV1
    (subjectProgramName : TSyntax `ident)
    (subjectDataName : TSyntax `ident)
    (encodeStateName : TSyntax `ident)
    (decodeStateName : TSyntax `ident)
    (encodeStateDecodeName : TSyntax `ident)
    (data : SemanticProgramDataV1)
    (initializers : Array ModelCallableViewV1) : CommandElabM Unit := do
  if initializers.isEmpty then
    return
  let referenceSubjectName := mkIdent `ReferenceSubject
  let lifecycleStateName := mkIdent `LifecycleState
  let initialLifecycleStateName := mkIdent `initialLifecycleState
  let stateName := mkIdent `State
  let encodeInjectiveName := mkIdent `encode_injective_of_eq_ok
  Lean.Elab.Command.elabCommand (← `(
    /-- Exact production pre-initialization carrier. It is distinct from the
        initialized business `State` returned by an initializer. -/
    abbrev $lifecycleStateName :=
      ProofForgeV2.Semantic.PreservationABI.InitialLifecycleStateV1
        $subjectProgramName))
  Lean.Elab.Command.elabCommand (← `(
    /-- Construct the exact lifecycle state through the production initial
        state function; no generated default-state implementation is used. -/
    def $initialLifecycleStateName :
        Except ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1
          $lifecycleStateName :=
      ProofForgeV2.Semantic.PreservationABI.initialLifecycleStateV1
        $subjectProgramName))
  for callableView in initializers do
    let callableNamespace := mkIdent (Name.mkSimple callableView.name)
    let invocationName := mkIdent `invocation
    let resultName := mkIdent `Result
    let encodeResultName := mkIdent `encodeResult
    let decodeResultName := mkIdent `decodeResult
    let decodeEncodeResultName := mkIdent `decode_encode_result
    let decodeResultCompleteName := mkIdent `decodeResult_complete_of_conforms
    let decodeReturnedResultCompleteName :=
      mkIdent `decodeResult_complete_of_returned
    let decodeReturnedStateCompleteName :=
      mkIdent `decodeState_complete_of_returned
    let encodeResultInjectiveName := mkIdent `encodeResult_injective
    let callableOutcomeName := mkIdent `Outcome
    let transitionName := mkIdent `Transition
    let transitionReturnedName := mkIdent `transition_returned_of_step
    let transitionRevertedName := mkIdent `transition_reverted_of_step
    let transitionTrappedName := mkIdent `transition_trapped_of_step
    let transitionExistsName := mkIdent `transition_exists
    let outcomeUniqueName := mkIdent `outcome_unique
    let subjectName := mkIdent `subject
    let preName := mkIdent `pre
    let contextName := mkIdent `context
    let responsesName := mkIdent `responses
    let vaultName := mkIdent `vault
    let typedOutcomeName := mkIdent `outcome
    let leftOutcomeName := mkIdent `left
    let rightOutcomeName := mkIdent `right
    let leftTransitionName := mkIdent `hleft
    let rightTransitionName := mkIdent `hright
    let referenceValueName := mkIdent `referenceValue
    let conformsName := mkIdent `hconforms
    let logicalPostName := mkIdent `logicalPost
    let effectsName := mkIdent `effects
    let reasonName := mkIdent `reason
    let faultName := mkIdent `fault
    let unchangedName := mkIdent `unchanged
    let validateName := mkIdent `hvalidate
    let stepName := mkIdent `hstep
    let callableIdTerm : TSyntax `term :=
      ⟨Syntax.mkNumLit (toString callableView.callableId.toNat)⟩
    let paramNames := callableView.params.map fun param =>
      mkIdent (Name.mkSimple (param.name ++ "Arg"))
    let paramTypes ← Lean.Elab.liftMacroM <|
      callableView.params.mapM fun _ => `(UInt64)
    let referenceArgs ← Lean.Elab.liftMacroM <|
      callableView.params.zip paramNames |>.mapM fun (param, paramName) => do
        let typeIdTerm : TSyntax `term :=
          ⟨Syntax.mkNumLit (toString param.typeId.toNat)⟩
        `(({ typeId := $typeIdTerm
             valueBytes := ProofForgeV2.Semantic.WireV1.encodeU64le $paramName
           } : ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1))
    let resultType ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultTypeV1 callableView.result
    let resultEncode ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultEncodeV1 callableView.result callableView.resultTypeId
    let resultDecode ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultDecodeV1
        subjectDataName callableView.result callableView.resultTypeId
    let resultTypeDecl ← match data.types[callableView.resultTypeId.toNat]? with
      | some value => pure value
      | none => throwError
          "generated initializer result is missing its production type declaration"
    let resultTypeDeclTerm ← Lean.Elab.liftMacroM <|
      ProofForgeV2.Language.SubjectDataQuoteV1.quoteTypeDeclV1 resultTypeDecl
    let resultDecodeEncode ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultDecodeEncodeV1 subjectDataName encodeResultName
        decodeResultName callableView.result callableView.resultTypeId
        resultTypeDeclTerm
    let resultDecodeComplete ← Lean.Elab.liftMacroM <|
      quoteModelCallableResultDecodeCompleteV1 subjectDataName encodeResultName
        decodeResultName callableView.result callableView.callableId
        callableView.resultTypeId resultTypeDeclTerm
    let invocationTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($invocationName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName)
    let returnedResultCompleteTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($decodeReturnedResultCompleteName $subjectName $preName
        $logicalPostName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $referenceValueName
        $effectsName $validateName $stepName)
    let returnedStateCompleteTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($decodeReturnedStateCompleteName $subjectName $preName
        $logicalPostName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $referenceValueName
        $effectsName $validateName $stepName)
    let transitionPrefixTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($transitionName $subjectName $preName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName)
    let leftTransitionTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($transitionName $subjectName $preName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $leftOutcomeName)
    let rightTransitionTerm ← Lean.Elab.liftMacroM <| do
      let mut term ← `($transitionName $subjectName $preName)
      for paramName in paramNames do
        term ← `($term $paramName)
      `($term $contextName $responsesName $vaultName $rightOutcomeName)
    Lean.Elab.Command.elabCommand (← `(namespace $callableNamespace))
    Lean.Elab.Command.elabCommand (← `(
      /-- Lean result type projected from this exact initializer row. -/
      abbrev $resultName := $resultType))
    Lean.Elab.Command.elabCommand (← `(
      /-- Encode this initializer result into its canonical Reference carrier. -/
      def $encodeResultName (value : $resultName) : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1 :=
        $resultEncode value))
    Lean.Elab.Command.elabCommand (← `(
      /-- Decode only this initializer's exact canonical Reference result. -/
      def $decodeResultName (referenceValue : Option
          ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1) :
          Except ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1 $resultName :=
        $resultDecode referenceValue))
    Lean.Elab.Command.elabCommand (← `(
      /-- Initializer result codec roundtrip through the production scalar
          validator and projection. -/
      theorem $decodeEncodeResultName (value : $resultName) :
          $decodeResultName ($encodeResultName value) = .ok value :=
        $resultDecodeEncode))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every conforming Reference initializer result has one exact typed
          decode/re-encode and no second typed decode. -/
      theorem $decodeResultCompleteName
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($conformsName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceResultConformsV1
              $subjectDataName
              (($subjectDataName).callables[$callableIdTerm]'(by decide)).result
              $referenceValueName) :
          ∃ value : $resultName,
            $decodeResultName $referenceValueName = .ok value ∧
              $encodeResultName value = $referenceValueName ∧
                ∀ other : $resultName,
                  $decodeResultName $referenceValueName = .ok other →
                    value = other :=
        $resultDecodeComplete $referenceValueName $conformsName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Canonical result encoding is injective because generated decoding is
          its left inverse. -/
      theorem $encodeResultInjectiveName :
          Function.Injective $encodeResultName := by
        intro left right h
        have hleft := ($decodeEncodeResultName left).symm
        have hmiddle := congrArg $decodeResultName h
        have hright := $decodeEncodeResultName right
        exact Except.ok.inj (hleft.trans (hmiddle.trans hright))))
    Lean.Elab.Command.elabCommand (← `(
      /-- Canonical invocation constructor for this exact initializer row.
          Context remains explicit and production-validated. -/
      def $invocationName
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1) :
          ProofForgeV2.Semantic.ReferenceV1.InvocationV1 := {
        callableId := $callableIdTerm
        args := #[$referenceArgs,*]
        context := $contextName
      }))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every returned production initializer result has one exact typed
          decode/re-encode. Selection comes from the exact admitted row. -/
      theorem $decodeReturnedResultCompleteName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          ($logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted ($preName).logical $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ value : $resultName,
            $decodeResultName $referenceValueName = .ok value ∧
              $encodeResultName value = $referenceValueName ∧
                ∀ other : $resultName,
                  $decodeResultName $referenceValueName = .ok other →
                    value = other := by
        have hadmittedData : ($subjectName).admitted.data = $subjectDataName :=
          (ProofForgeV2.Semantic.ReferenceV1.admitReferenceProgramSliceV1_ok_implies
            $subjectProgramName $subjectDataName ($subjectName).admitted
              $validateName ($subjectName).hadmit).2
        have hlookup :
            ($subjectName).admitted.data.callables[$callableIdTerm]? =
              some (($subjectDataName).callables[$callableIdTerm]'(by decide)) := by
          rw [hadmittedData]
          rfl
        have hconforms :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_returned_resultConformsV1_of_lookup
            ($subjectName).admitted ($preName).logical $logicalPostName
              $invocationTerm $responsesName $vaultName
              (($subjectDataName).callables[$callableIdTerm]'(by decide))
              $referenceValueName $effectsName hlookup $stepName
        rw [hadmittedData] at hconforms
        exact $decodeResultCompleteName $referenceValueName hconforms))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every returned initializer post-state uniquely decodes as an
          initialized typed business state. The lifecycle theorem is selected
          by the exact admitted initializer row. -/
      theorem $decodeReturnedStateCompleteName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          ($logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted ($preName).logical $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ post : $stateName,
            $decodeStateName $logicalPostName = .ok post ∧
              $encodeStateName post = .ok $logicalPostName ∧
                ∀ other : $stateName,
                  $decodeStateName $logicalPostName = .ok other →
                    post = other := by
        have hadmittedData : ($subjectName).admitted.data = $subjectDataName :=
          (ProofForgeV2.Semantic.ReferenceV1.admitReferenceProgramSliceV1_ok_implies
            $subjectProgramName $subjectDataName ($subjectName).admitted
              $validateName ($subjectName).hadmit).2
        have hinitializer :
            ($subjectName).admitted.data.callables[$callableIdTerm]?.map
                (fun callable => callable.kind) =
              some ProofForgeV2.Semantic.WireV1.CallableKindV1.initializer := by
          rw [hadmittedData]
          rfl
        have hconforms :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_returned_stateConformsV1_of_initializer
            $subjectProgramName ($subjectName).admitted ($preName).logical
              $logicalPostName $invocationTerm $responsesName $vaultName
              $referenceValueName $effectsName ($subjectName).hadmit
              hinitializer $stepName
        obtain ⟨post, hdecode, hencode⟩ :=
          $encodeStateDecodeName $logicalPostName $validateName hconforms
        refine ⟨post, hdecode, hencode, ?_⟩
        intro other hother
        exact Except.ok.inj (hdecode.symm.trans hother)))
    Lean.Elab.Command.elabCommand (← `(
      /-- Typed full-outcome view specialized to this initializer result. -/
      abbrev $callableOutcomeName :=
        ProofForgeV2.Semantic.PreservationABI.TypedOutcomeV1
          $stateName $resultName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Exact initializer relation from production lifecycle state to typed
          initialized state. It is a Reference-step theorem view, not an
          executable typed initializer. -/
      def $transitionName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($typedOutcomeName : $callableOutcomeName) : Prop :=
        ProofForgeV2.Semantic.PreservationABI.TypedInitializerRelationV1
          $encodeStateName $encodeResultName $subjectName $preName
          $invocationTerm $responsesName $vaultName $typedOutcomeName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Package one exact returned initializer step as a typed transition. -/
      theorem $transitionReturnedName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          ($logicalPostName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($referenceValueName : Option
            ProofForgeV2.Semantic.ReferenceV1.ReferenceValueV1)
          ($effectsName : Array
            ProofForgeV2.Semantic.ReferenceV1.OrderedEffectV1)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted ($preName).logical $invocationTerm
                  $responsesName $vaultName =
              .returned $logicalPostName $referenceValueName $effectsName) :
          ∃ post : $stateName, ∃ value : $resultName,
            $decodeStateName $logicalPostName = .ok post ∧
              $decodeResultName $referenceValueName = .ok value ∧
                $transitionPrefixTerm (.returned post value $effectsName) := by
        obtain ⟨postWitness, hdecodePost, hencodePost, _huniquePost⟩ :=
          $returnedStateCompleteTerm
        obtain ⟨valueWitness, hdecodeValue, hencodeValue, _huniqueValue⟩ :=
          $returnedResultCompleteTerm
        refine ⟨postWitness, valueWitness, hdecodePost, hdecodeValue, ?_⟩
        unfold $transitionName
          ProofForgeV2.Semantic.PreservationABI.TypedInitializerRelationV1
        refine ⟨$logicalPostName, hencodePost, ?_⟩
        rw [hencodeValue]
        exact $stepName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Package one exact reverted initializer step; the production theorem
          proves the carried state is the lifecycle pre-state. -/
      theorem $transitionRevertedName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($reasonName :
            ProofForgeV2.Semantic.ReferenceV1.SemanticRevertV1)
          ($unchangedName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted ($preName).logical $invocationTerm
                  $responsesName $vaultName =
              .reverted $reasonName $unchangedName) :
          $unchangedName = ($preName).logical ∧
            $transitionPrefixTerm (.reverted $reasonName) := by
        have hunchanged :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_reverted_state_eq
            ($subjectName).admitted ($preName).logical $invocationTerm
              $responsesName $vaultName $reasonName $unchangedName $stepName
        subst $unchangedName
        refine ⟨rfl, ?_⟩
        unfold $transitionName
          ProofForgeV2.Semantic.PreservationABI.TypedInitializerRelationV1
        exact $stepName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Package one exact trapped initializer step; the production theorem
          proves the carried state is the lifecycle pre-state. -/
      theorem $transitionTrappedName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($faultName :
            ProofForgeV2.Semantic.ReferenceV1.SemanticFaultV1)
          ($unchangedName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          ($stepName :
            ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
                ($subjectName).admitted ($preName).logical $invocationTerm
                  $responsesName $vaultName =
              .trapped $faultName $unchangedName) :
          $unchangedName = ($preName).logical ∧
            $transitionPrefixTerm (.trapped $faultName) := by
        have hunchanged :=
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1_trapped_state_eq
            ($subjectName).admitted ($preName).logical $invocationTerm
              $responsesName $vaultName $faultName $unchangedName $stepName
        subst $unchangedName
        refine ⟨rfl, ?_⟩
        unfold $transitionName
          ProofForgeV2.Semantic.PreservationABI.TypedInitializerRelationV1
        exact $stepName))
    Lean.Elab.Command.elabCommand (← `(
      /-- Every execution of the sole Reference step from the exact lifecycle
          state has one typed initializer outcome. -/
      theorem $transitionExistsName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($validateName :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName) :
          ∃ outcome : $callableOutcomeName,
            $transitionPrefixTerm outcome := by
        generalize $stepName :
          ProofForgeV2.Semantic.ReferenceV1.stepReferenceSliceV1
              ($subjectName).admitted ($preName).logical $invocationTerm
                $responsesName $vaultName = referenceOutcome
        cases referenceOutcome with
        | returned logicalPost referenceValue effects =>
            obtain ⟨post, value, _hdecodePost, _hdecodeValue, htransition⟩ :=
              $transitionReturnedName
                (subject := $subjectName) (pre := $preName)
                (logicalPost := logicalPost) (context := $contextName)
                (responses := $responsesName) (vault := $vaultName)
                (referenceValue := referenceValue) (effects := effects)
                (hvalidate := $validateName) (hstep := $stepName)
            exact ⟨.returned post value effects, htransition⟩
        | reverted reason unchanged =>
            have htransition :=
              ($transitionRevertedName
                (subject := $subjectName) (pre := $preName)
                (context := $contextName) (responses := $responsesName)
                (vault := $vaultName) (reason := reason)
                (unchanged := unchanged) (hstep := $stepName)).2
            exact ⟨.reverted reason, htransition⟩
        | trapped fault unchanged =>
            have htransition :=
              ($transitionTrappedName
                (subject := $subjectName) (pre := $preName)
                (context := $contextName) (responses := $responsesName)
                (vault := $vaultName) (fault := fault)
                (unchanged := unchanged) (hstep := $stepName)).2
            exact ⟨.trapped fault, htransition⟩))
    Lean.Elab.Command.elabCommand (← `(
      /-- The exact initializer relation has at most one outcome for fixed
          lifecycle/input values. -/
      theorem $outcomeUniqueName
          ($subjectName : $referenceSubjectName)
          ($preName : $lifecycleStateName)
          $[($paramNames : $paramTypes)]*
          ($contextName : Array
            ProofForgeV2.Semantic.ReferenceV1.ContextInputV1)
          ($responsesName :
            ProofForgeV2.Semantic.ReferenceV1.ExternalResponsesV1)
          ($vaultName :
            ProofForgeV2.Semantic.ReferenceV1.ReferenceVaultSeedV1)
          ($leftOutcomeName $rightOutcomeName : $callableOutcomeName)
          ($leftTransitionName : $leftTransitionTerm)
          ($rightTransitionName : $rightTransitionTerm) :
          $leftOutcomeName = $rightOutcomeName := by
        exact
          ProofForgeV2.Semantic.PreservationABI.typedInitializerRelationV1_outcome_unique
            $encodeStateName $encodeResultName $encodeInjectiveName
            $encodeResultInjectiveName $subjectName $preName $invocationTerm
            $responsesName $vaultName $leftOutcomeName $rightOutcomeName
            $leftTransitionName $rightTransitionName))
    Lean.Elab.Command.elabCommand (← `(end $callableNamespace))

/-- Emit evaluator-backed typed invariant predicates. The predicate and bridge
    both delegate to `TypedInvariantV1` / `evalInvariantV1`; this phase does not
    translate or execute the DSL invariant expression independently. -/
private def elaborateInvariantModelsV1
    (subjectProgramName : TSyntax `ident)
    (subjectDataName : TSyntax `ident)
    (encodeStateName : TSyntax `ident)
    (fields : Array ModelStateFieldV1)
    (views : Array ModelInvariantViewV1) : CommandElabM Unit := do
  if views.isEmpty then
    return
  let stateName := mkIdent `State
  let typedStateName := mkIdent `typedState
  let logicalStateName := mkIdent `logicalState
  let encodeExistsName := mkIdent `encode_exists
  let invariantNamespace := mkIdent `Invariant
  let fieldNames := fields.map fun field => mkIdent (Name.mkSimple field.name)
  let encodedValues ← Lean.Elab.liftMacroM <|
    fields.zip fieldNames |>.mapM fun (field, fieldName) =>
      quoteModelStateEncodeV1 typedStateName fieldName field.scalar
  for invariantView in views do
    let predicateName := mkIdent (Name.mkSimple invariantView.name)
    let ordinalTerm : TSyntax `term :=
      ⟨Syntax.mkNumLit (toString invariantView.ordinal)⟩
    Lean.Elab.Command.elabCommand (← `(
      /-- Typed author predicate for this exact invariant ordinal. Its sole
          evaluator authority is the production `evalInvariantV1`. -/
      def $predicateName ($typedStateName : $stateName) : Prop :=
        ProofForgeV2.Semantic.PreservationABI.TypedInvariantV1
          $encodeStateName $subjectProgramName $ordinalTerm $typedStateName))
  Lean.Elab.Command.elabCommand (← `(namespace $invariantNamespace))
  for invariantView in views do
    let predicateName := mkIdent (Name.mkSimple invariantView.name)
    let bridgeName := mkIdent (Name.mkSimple (invariantView.name ++ "_iff_eval"))
    let ordinalTerm : TSyntax `term :=
      ⟨Syntax.mkNumLit (toString invariantView.ordinal)⟩
    Lean.Elab.Command.elabCommand (← `(
      /-- Exact bridge from the generated typed predicate to the production
          invariant evaluator on the same encoded logical state. -/
      theorem $bridgeName
          ($typedStateName : $stateName)
          ($logicalStateName :
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          (hencode : $encodeStateName $typedStateName = .ok $logicalStateName) :
          $predicateName $typedStateName ↔
            ProofForgeV2.Semantic.InvariantABI.evalInvariantV1
                $subjectProgramName $ordinalTerm $logicalStateName =
              .returnedTrue := by
        exact
          ProofForgeV2.Semantic.PreservationABI.typedInvariantV1_iff_eval_of_encode
            $encodeStateName $subjectProgramName $ordinalTerm $typedStateName
              $logicalStateName hencode))
    match invariantView.fieldEquality with
    | none => pure ()
    | some equality =>
      let fieldBridgeName :=
        mkIdent (Name.mkSimple (invariantView.name ++ "_iff_fields"))
      let invariantIdTerm : TSyntax `term :=
        ⟨Syntax.mkNumLit (toString equality.invariant.id.toNat)⟩
      let callableIdTerm : TSyntax `term :=
        ⟨Syntax.mkNumLit (toString equality.callable.id.toNat)⟩
      let valueTypeIdTerm : TSyntax `term :=
        ⟨Syntax.mkNumLit (toString equality.valueType.id.toNat)⟩
      let boolTypeIdTerm : TSyntax `term :=
        ⟨Syntax.mkNumLit (toString equality.boolType.id.toNat)⟩
      let leftStateIdTerm : TSyntax `term :=
        ⟨Syntax.mkNumLit (toString equality.leftState.id.toNat)⟩
      let rightStateIdTerm : TSyntax `term :=
        ⟨Syntax.mkNumLit (toString equality.rightState.id.toNat)⟩
      let leftFieldName := mkIdent (Name.mkSimple equality.leftState.name)
      let rightFieldName := mkIdent (Name.mkSimple equality.rightState.name)
      let rootNameTerm ← Lean.Elab.liftMacroM <|
        quoteModelOptionStringV1 equality.callable.name
      let rootVisibilityTerm ← Lean.Elab.liftMacroM <|
        quoteModelVisibilityV1 equality.callable.result.visibility
      let leftVisibilityTerm ← Lean.Elab.liftMacroM <|
        quoteModelVisibilityV1 equality.leftState.visibility
      let rightVisibilityTerm ← Lean.Elab.liftMacroM <|
        quoteModelVisibilityV1 equality.rightState.visibility
      Lean.Elab.Command.elabCommand (← `(
        /-- Narrow mathematical view of the exact lowered two-field equality
            invariant. Exact subject validation remains explicit; typed
            encoder success follows from the generated production-codec
            theorem, and execution remains the production invariant evaluator. -/
        theorem $fieldBridgeName
            ($typedStateName : $stateName)
            (hvalidate :
              ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                  $subjectProgramName = .ok $subjectDataName) :
            $predicateName $typedStateName ↔
              ($typedStateName).$leftFieldName =
                ($typedStateName).$rightFieldName := by
          obtain ⟨$logicalStateName, hencode⟩ :=
            $encodeExistsName $typedStateName
          rw [$bridgeName $typedStateName $logicalStateName hencode]
          have hproductionEncode :
              ProofForgeV2.Semantic.InvariantABI.encodeLogicalStateValuesV1
                  $subjectDataName true #[$encodedValues,*] =
                .ok $logicalStateName := by
            unfold $encodeStateName at hencode
            exact hencode
          have hinitialized : ($logicalStateName).initialized = true :=
            ProofForgeV2.Semantic.InvariantABI.LogicalStateV1.initialized_of_encodeLogicalStateValuesV1
              $subjectDataName true #[$encodedValues,*] $logicalStateName
                hproductionEncode
          have hdecode :
              ProofForgeV2.Semantic.InvariantABI.decodeLogicalStateValuesV1
                  $subjectDataName $logicalStateName =
                .ok #[$encodedValues,*] :=
            ProofForgeV2.Semantic.InvariantABI.decodeLogicalStateValuesV1_of_encodeLogicalStateValuesV1
              $subjectDataName true #[$encodedValues,*] $logicalStateName
                hproductionEncode
          rw [ProofForgeV2.Semantic.InvariantABI.evalInvariantV1_returnedTrue_iff_two_state_bytes_eq
            $subjectProgramName $subjectDataName $ordinalTerm $invariantIdTerm
            $(quote equality.invariant.name) $logicalStateName
            #[$encodedValues,*]
            (ProofForgeV2.Semantic.WireV1.encodeU64le
              ($typedStateName).$leftFieldName)
            (ProofForgeV2.Semantic.WireV1.encodeU64le
              ($typedStateName).$rightFieldName)
            $callableIdTerm $valueTypeIdTerm $boolTypeIdTerm
            $leftStateIdTerm $rightStateIdTerm $rootNameTerm
            $rootVisibilityTerm $leftVisibilityTerm $rightVisibilityTerm
            $(quote equality.leftState.name) $(quote equality.rightState.name)
            hvalidate hinitialized hdecode (by rfl) (by rfl) (by rfl)
            (by rfl) (by rfl) (by rfl) (by rfl)]
          constructor
          · intro hbytes
            have hvalues := congrArg
              ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1
              hbytes
            simpa only [
              ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1_encodeU64le]
              using hvalues
          · intro hvalues
            simpa only [hvalues]))
  Lean.Elab.Command.elabCommand (← `(end $invariantNamespace))

/-- Emit the author-facing business-state view. It is only a typed projection
    over `Proof.subjectDataV1`: encoding and decoding call the production
    logical-state codec, and this phase intentionally emits no step/evaluator. -/
private def elaborateStateModelV1
    (subjectProgramName : TSyntax `ident)
    (subjectDataName : TSyntax `ident)
    (data : SemanticProgramDataV1)
    (fields : Array ModelStateFieldV1) : CommandElabM Unit := do
  let modelNamespace := mkIdent `Model
  let stateName := mkIdent `State
  let typedStateName := mkIdent `typedState
  let encodeStateName := mkIdent `encodeState
  let decodeStateName := mkIdent `decodeState
  let encodeExistsName := mkIdent `encode_exists
  let decodeEncodeName := mkIdent `decode_encode
  let encodeInjectiveName := mkIdent `encode_injective_of_eq_ok
  let decodeExistsUniqueName := mkIdent `decode_existsUnique_of_conforms
  let encodeDecodeName := mkIdent `encode_decode_of_conforms
  let conformsIffEncodeName := mkIdent `conforms_iff_exists_encode
  let conformsOfEncodeName := mkIdent `conforms_of_encode
  let logicalStateName := mkIdent `logicalState
  let stateValuesName := mkIdent `stateValuesV1
  let fieldNames := fields.map fun field => mkIdent (Name.mkSimple field.name)
  let fieldCount : TSyntax `term := ⟨Syntax.mkNumLit (toString fields.size)⟩
  let fieldTypes ← Lean.Elab.liftMacroM <|
    fields.mapM fun field => quoteModelStateTypeV1 field.scalar
  let encodedValues ← Lean.Elab.liftMacroM <|
    fields.zip fieldNames |>.mapM fun (field, fieldName) =>
      quoteModelStateEncodeV1 typedStateName fieldName field.scalar
  let statePairs ← fields.zipIdx.mapM fun (_, index) => do
    let stateDecl ← match data.logicalState[index]? with
      | some value => pure value
      | none => throwError
          "generated Model field is missing its production state declaration"
    let stateDeclTerm ← Lean.Elab.liftMacroM <|
      ProofForgeV2.Language.SubjectDataQuoteV1.quoteStateDeclV1 stateDecl
    let encodedValue ← match encodedValues[index]? with
      | some value => pure value
      | none => throwError
          "generated Model field is missing its production encoded value"
    Lean.Elab.liftMacroM <| `(($stateDeclTerm, $encodedValue))
  let canonicalPairFacts ← fields.zipIdx.mapM fun (field, index) => do
    let fieldName ← match fieldNames[index]? with
      | some value => pure value
      | none => throwError "generated Model field is missing its Lean name"
    let stateDecl ← match data.logicalState[index]? with
      | some value => pure value
      | none => throwError
          "generated Model field is missing its production state declaration"
    let typeDecl ← match data.types[stateDecl.typeId.toNat]? with
      | some value => pure value
      | none => throwError
          "generated Model field is missing its production type declaration"
    let stateDeclTerm ← Lean.Elab.liftMacroM <|
      ProofForgeV2.Language.SubjectDataQuoteV1.quoteStateDeclV1 stateDecl
    let typeDeclTerm ← Lean.Elab.liftMacroM <|
      ProofForgeV2.Language.SubjectDataQuoteV1.quoteTypeDeclV1 typeDecl
    Lean.Elab.liftMacroM <| match field.scalar with
      | .bool => `(
          ((by
            constructor
            · apply
                ProofForgeV2.Semantic.WireV1.validateValueBytesV1_encodeBool
                  ($subjectDataName).types ($stateDeclTerm).typeId
                    $typeDeclTerm ($typedStateName).$fieldName
              · rfl
              · rfl
            · cases ($typedStateName).$fieldName <;> decide) :
          ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                ($subjectDataName).types ($stateDeclTerm).typeId
                (ProofForgeV2.Semantic.WireV1.encodeBool
                  ($typedStateName).$fieldName) = .ok () ∧
            (ProofForgeV2.Semantic.WireV1.encodeBool
              ($typedStateName).$fieldName).size ≤ UInt32.size - 1))
      | .uint64 => `(
          ((by
            constructor
            · apply
                ProofForgeV2.Semantic.WireV1.validateValueBytesV1_uint64_of_size
                  ($subjectDataName).types ($stateDeclTerm).typeId
                    $typeDeclTerm
              · rfl
              · rfl
              · exact ProofForgeV2.Semantic.WireV1.encodeU64le_size
                  ($typedStateName).$fieldName
            · rw [ProofForgeV2.Semantic.WireV1.encodeU64le_size]
              decide) :
          ProofForgeV2.Semantic.WireV1.validateValueBytesV1
                ($subjectDataName).types ($stateDeclTerm).typeId
                (ProofForgeV2.Semantic.WireV1.encodeU64le
                  ($typedStateName).$fieldName) = .ok () ∧
            (ProofForgeV2.Semantic.WireV1.encodeU64le
              ($typedStateName).$fieldName).size ≤ UInt32.size - 1))
  let mut canonicalPairsProof : TSyntax `term ← Lean.Elab.liftMacroM <|
    `(by
      intro pair hpair
      simp at hpair)
  for fact in canonicalPairFacts.reverse do
    canonicalPairsProof ← Lean.Elab.liftMacroM <|
      `(List.forall_mem_cons.mpr ⟨$fact, $canonicalPairsProof⟩)
  let decodedValues ← Lean.Elab.liftMacroM <|
    fields.zipIdx.mapM fun (field, index) => do
      let indexTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString index)⟩
      let valueBytes ← `($stateValuesName[$indexTerm]!)
      quoteModelStateDecodeV1 valueBytes field.scalar
  let decodedState ← Lean.Elab.liftMacroM <|
    if fields.isEmpty then
      `(())
    else
      `({ $[$fieldNames:ident := $decodedValues],* })
  let completeScalarCodecs := fields.all fun field =>
    match field.scalar with
    | .uint64 => true
    | .bool => true
  let decodedEncodedValues ← Lean.Elab.liftMacroM <|
    fields.zip decodedValues |>.mapM fun (field, value) =>
      match field.scalar with
      | .bool => `(ProofForgeV2.Semantic.WireV1.encodeBool $value)
      | .uint64 => `(ProofForgeV2.Semantic.WireV1.encodeU64le $value)
  let decodedValueRoundtrips : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ←
    fields.zipIdx.mapM fun (field, index) => do
      let indexTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString index)⟩
      let stateDecl ← match data.logicalState[index]? with
        | some value => pure value
        | none => throwError
            "generated Model field is missing its production state declaration"
      let typeDecl ← match data.types[stateDecl.typeId.toNat]? with
        | some value => pure value
        | none => throwError
            "generated Model field is missing its production type declaration"
      let stateDeclTerm ← Lean.Elab.liftMacroM <|
        ProofForgeV2.Language.SubjectDataQuoteV1.quoteStateDeclV1 stateDecl
      let typeDeclTerm ← Lean.Elab.liftMacroM <|
        ProofForgeV2.Language.SubjectDataQuoteV1.quoteTypeDeclV1 typeDecl
      let proof ← Lean.Elab.liftMacroM <| match field.scalar with
        | .bool => `(
            ProofForgeV2.Semantic.StateModelV1.encodeBool_boolOfDecodedStateValueV1
              $subjectDataName $logicalStateName $stateValuesName hdecode
              $indexTerm (by omega)
              $stateDeclTerm $typeDeclTerm
              (by rfl) (by rfl) (by rfl))
        | .uint64 => `(
            ProofForgeV2.Semantic.StateModelV1.encodeU64le_uint64OfDecodedStateValueV1
              $subjectDataName $logicalStateName $stateValuesName hdecode
              $indexTerm (by omega)
              $stateDeclTerm $typeDeclTerm
              (by rfl) (by rfl) (by rfl))
      Lean.Elab.liftMacroM <|
        `(Lean.Parser.Tactic.simpLemma| $proof:term)
  let rewriteDecodedValues ← Lean.Elab.liftMacroM <|
    if fields.isEmpty then
      `(tactic| skip)
    else
      `(tactic| simp only [$[$decodedValueRoundtrips],*])
  Lean.Elab.Command.elabCommand (← `(namespace $modelNamespace))
  if fields.isEmpty then
    Lean.Elab.Command.elabCommand (← `(
      /-- Typed initialized business state for an empty logical-state table. -/
      abbrev $stateName := Unit))
  else
    Lean.Elab.Command.elabCommand (← `(
      /-- Typed initialized business state derived in exact StateId order. -/
      structure $stateName where
        $[($fieldNames : $fieldTypes)]*
        deriving BEq, Repr))
  Lean.Elab.Command.elabCommand (← `(
    /-- Encode through the sole production logical-state codec. -/
    def $encodeStateName ($typedStateName : $stateName) :
        Except ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1
          ProofForgeV2.Semantic.InvariantABI.LogicalStateV1 :=
      ProofForgeV2.Semantic.InvariantABI.encodeLogicalStateValuesV1
        $subjectDataName true #[$encodedValues,*]))
  Lean.Elab.Command.elabCommand (← `(
    /-- Every generated typed state has a successful exact production-codec
        encoding. This is a totality theorem about `encodeState`, not a second
        state encoder. -/
    theorem $encodeExistsName ($typedStateName : $stateName) :
        ∃ logicalState : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1,
          $encodeStateName $typedStateName = .ok logicalState := by
      unfold $encodeStateName
      exact
        ProofForgeV2.Semantic.InvariantABI.encodeLogicalStateValuesV1_exists_of_pairs
          $subjectDataName true #[$encodedValues,*] [$statePairs,*]
            (by rfl) (by rfl) $canonicalPairsProof))
  Lean.Elab.Command.elabCommand (← `(
    /-- Decode only initialized carriers through the production codec, then
        project canonical scalar bytes into Lean fields. -/
    def $decodeStateName ($logicalStateName :
        ProofForgeV2.Semantic.InvariantABI.LogicalStateV1) :
        Except ProofForgeV2.Semantic.WireV1.SemanticWireErrorV1 $stateName := do
      let $stateValuesName ←
        ProofForgeV2.Semantic.StateModelV1.decodeInitializedStateValuesV1
          $subjectDataName $logicalStateName
      unless ($stateValuesName).size == $fieldCount do
        return ← ProofForgeV2.Semantic.WireV1.err .nonCanonical
      pure $decodedState))
  Lean.Elab.Command.elabCommand (← `(
    /-- Generated typed projection roundtrip. The success premise remains
        explicit because the production encoder is `Except`-valued. -/
    theorem $decodeEncodeName
        ($typedStateName : $stateName)
        ($logicalStateName : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
        (hencode : $encodeStateName $typedStateName = .ok $logicalStateName) :
        $decodeStateName $logicalStateName = .ok $typedStateName := by
      unfold $encodeStateName at hencode
      have hvalues :=
        ProofForgeV2.Semantic.StateModelV1.decodeInitializedStateValuesV1_of_encodeLogicalStateValuesV1
          $subjectDataName #[$encodedValues,*] $logicalStateName hencode
      unfold $decodeStateName
      rw [hvalues]
      cases $typedStateName:ident
      simp [ProofForgeV2.Semantic.StateModelV1.boolOfCanonicalValueBytesV1_encodeBool,
        ProofForgeV2.Semantic.StateModelV1.uint64OfCanonicalValueBytesV1_encodeU64le,
        Pure.pure, Except.pure, Bind.bind, Except.bind]))
  Lean.Elab.Command.elabCommand (← `(
    /-- Two typed states encoded successfully to the same production carrier
        are equal. This follows by decoding that carrier, not by a second
        model-side equality checker. -/
    theorem $encodeInjectiveName
        (left right : $stateName)
        ($logicalStateName : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
        (hleft : $encodeStateName left = .ok $logicalStateName)
        (hright : $encodeStateName right = .ok $logicalStateName) :
        left = right := by
      exact Except.ok.inj
        (($decodeEncodeName left $logicalStateName hleft).symm.trans
          ($decodeEncodeName right $logicalStateName hright))))
  Lean.Elab.Command.elabCommand (← `(
    /-- Every state accepted by the sole production `StateConformsV1`
        predicate has exactly one generated typed decode. Existence follows
        from production decoder success and its declaration-arity theorem;
        uniqueness follows from determinism of this generated projection. -/
    theorem $decodeExistsUniqueName
        ($logicalStateName : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
        (hvalidate :
          ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
              $subjectProgramName = .ok $subjectDataName)
        (hconforms :
          ProofForgeV2.Semantic.InvariantABI.StateConformsV1
            $subjectProgramName $logicalStateName) :
        ∃ typedState : $stateName,
          $decodeStateName $logicalStateName = .ok typedState ∧
            ∀ other : $stateName,
              $decodeStateName $logicalStateName = .ok other →
                typedState = other := by
      obtain ⟨hinitialized, $stateValuesName, hdecode⟩ :=
        ProofForgeV2.Semantic.InvariantABI.stateConformsV1_elim_of_validate_eq_ok
          $subjectProgramName $subjectDataName $logicalStateName hvalidate hconforms
      have hvalues :
          ProofForgeV2.Semantic.StateModelV1.decodeInitializedStateValuesV1
              $subjectDataName $logicalStateName = .ok $stateValuesName := by
        simp [ProofForgeV2.Semantic.StateModelV1.decodeInitializedStateValuesV1,
          hinitialized, hdecode, Pure.pure, Except.pure, Bind.bind, Except.bind]
      have hdecodedSize :=
        ProofForgeV2.Semantic.InvariantABI.decodeLogicalStateValuesV1_size
          $subjectDataName $logicalStateName $stateValuesName hdecode
      have hsubjectSize : ($subjectDataName).logicalState.size = $fieldCount := by
        rfl
      have hmodelSize : ($stateValuesName).size = $fieldCount :=
        hdecodedSize.trans hsubjectSize
      let typedState : $stateName := $decodedState
      have hsuccess :
          $decodeStateName $logicalStateName = .ok typedState := by
        unfold $decodeStateName
        rw [hvalues]
        simp [hmodelSize, typedState, Pure.pure, Except.pure, Bind.bind,
          Except.bind]
      refine ⟨typedState, hsuccess, ?_⟩
      intro other hother
      exact Except.ok.inj (hsuccess.symm.trans hother)))
  if completeScalarCodecs then
    Lean.Elab.Command.elabCommand (← `(
      /-- Every production-conforming initialized state in the generated
          scalar subset has a typed decode that re-encodes to the exact same
          production carrier. -/
      theorem $encodeDecodeName
          ($logicalStateName : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          (hvalidate :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName)
          (hconforms :
            ProofForgeV2.Semantic.InvariantABI.StateConformsV1
              $subjectProgramName $logicalStateName) :
          ∃ typedState : $stateName,
            $decodeStateName $logicalStateName = .ok typedState ∧
              $encodeStateName typedState = .ok $logicalStateName := by
        obtain ⟨hinitialized, $stateValuesName, hdecode⟩ :=
          ProofForgeV2.Semantic.InvariantABI.stateConformsV1_elim_of_validate_eq_ok
            $subjectProgramName $subjectDataName $logicalStateName hvalidate hconforms
        have hvalues :
            ProofForgeV2.Semantic.StateModelV1.decodeInitializedStateValuesV1
                $subjectDataName $logicalStateName = .ok $stateValuesName := by
          simp [ProofForgeV2.Semantic.StateModelV1.decodeInitializedStateValuesV1,
            hinitialized, hdecode, Pure.pure, Except.pure, Bind.bind, Except.bind]
        have hdecodedSize :=
          ProofForgeV2.Semantic.InvariantABI.decodeLogicalStateValuesV1_size
            $subjectDataName $logicalStateName $stateValuesName hdecode
        have hsubjectSize : ($subjectDataName).logicalState.size = $fieldCount := by
          rfl
        have hmodelSize : ($stateValuesName).size = $fieldCount :=
          hdecodedSize.trans hsubjectSize
        let typedState : $stateName := $decodedState
        have hsuccess :
            $decodeStateName $logicalStateName = .ok typedState := by
          unfold $decodeStateName
          rw [hvalues]
          simp [hmodelSize, typedState, Pure.pure, Except.pure, Bind.bind,
            Except.bind]
        have hencodedValues : #[$decodedEncodedValues,*] = $stateValuesName := by
          $rewriteDecodedValues
          let rebuilt : Array ByteArray :=
            Array.ofFn (fun i : Fin $fieldCount =>
              $stateValuesName[i.val]'(by omega))
          have hrebuilt : rebuilt = $stateValuesName := by
            apply Array.ext
            · simp [rebuilt, hmodelSize]
            · intro i hi₁ hi₂
              unfold rebuilt
              rw [Array.getElem_ofFn]
          rw [← hrebuilt]
          simp [rebuilt, Array.ofFn_succ']
        have hproduction :
            ProofForgeV2.Semantic.InvariantABI.encodeLogicalStateValuesV1
                $subjectDataName true $stateValuesName = .ok $logicalStateName :=
          ProofForgeV2.Semantic.StateModelV1.encodeLogicalStateValuesV1_of_decodeInitializedStateValuesV1
            $subjectDataName $logicalStateName $stateValuesName hvalues
        have hencode : $encodeStateName typedState = .ok $logicalStateName := by
          unfold $encodeStateName
          change
            ProofForgeV2.Semantic.InvariantABI.encodeLogicalStateValuesV1
                $subjectDataName true #[$decodedEncodedValues,*] =
              .ok $logicalStateName
          rw [hencodedValues]
          exact hproduction
        exact ⟨typedState, hsuccess, hencode⟩))
  Lean.Elab.Command.elabCommand (← `(
    /-- Successful typed encoding conforms to the sole production state
        predicate once this exact generated subject has validated. -/
    theorem $conformsOfEncodeName
        ($typedStateName : $stateName)
        ($logicalStateName : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
        (hvalidate :
          ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
              $subjectProgramName = .ok $subjectDataName)
        (hencode : $encodeStateName $typedStateName = .ok $logicalStateName) :
        ProofForgeV2.Semantic.InvariantABI.StateConformsV1
          $subjectProgramName $logicalStateName := by
      exact
        ProofForgeV2.Semantic.StateModelV1.stateConformsV1_of_encodeLogicalStateValuesV1
          $subjectProgramName $subjectDataName #[$encodedValues,*]
          $logicalStateName hvalidate hencode))
  if completeScalarCodecs then
    Lean.Elab.Command.elabCommand (← `(
      /-- On the generated typed-state scalar subset, production conformance is
          equivalent to representability by the production encoder. -/
      theorem $conformsIffEncodeName
          ($logicalStateName : ProofForgeV2.Semantic.InvariantABI.LogicalStateV1)
          (hvalidate :
            ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1
                $subjectProgramName = .ok $subjectDataName) :
          ProofForgeV2.Semantic.InvariantABI.StateConformsV1
              $subjectProgramName $logicalStateName ↔
            ∃ candidate : $stateName,
              $encodeStateName candidate = .ok $logicalStateName := by
        constructor
        · intro hconforms
          obtain ⟨candidate, _hdecode, hencode⟩ :=
            $encodeDecodeName $logicalStateName hvalidate hconforms
          exact ⟨candidate, hencode⟩
        · rintro ⟨candidate, hencode⟩
          exact $conformsOfEncodeName candidate $logicalStateName
            hvalidate hencode))
  elaborateCallableModelsV1 subjectProgramName subjectDataName encodeStateName
    decodeStateName encodeDecodeName data (modelCallableViewsV1 data)
  elaborateInitializerModelsV1 subjectProgramName subjectDataName encodeStateName
    decodeStateName encodeDecodeName data (modelInitializerViewsV1 data)
  elaborateInvariantModelsV1 subjectProgramName subjectDataName encodeStateName
    fields (modelInvariantViewsV1 data)
  Lean.Elab.Command.elabCommand (← `(end $modelNamespace))

private def proofSurfaceV1
    (source : ValidatedSourceV1) : Except String ProofSurfaceV1 := do
  let invariants := source.program.items.filterMap fun item =>
    match item with
    | .invariant declaration => some declaration.name.raw
    | _ => none
  let proofs := source.program.items.filterMap fun item =>
    match item with
    | .proof declaration => some (declaration.invariant.raw, declaration.kind)
    | _ => none
  if proofs.isEmpty then
    return { invariantNames := #[], holdsNames := #[], preservingNames := #[] }
  for invariantName in invariants do
    unless proofs.any (fun proof => proof.1 == invariantName) do
      throw s!"inline proof program is missing proof reference for invariant '{invariantName}'"
    if isReservedInlineProofSurfaceNameV1 invariantName then
      throw s!"invariant name '{invariantName}' is reserved by the inline proof surface"
  for proof in proofs do
    unless invariants.any (· == proof.1) do
      throw s!"proof reference names unknown invariant '{proof.1}'"
  let holdsNames := invariants.filter fun invariantName =>
    proofs.any fun proof => proof.1 == invariantName && proof.2 == .holds
  let preservingNames := invariants.filter fun invariantName =>
    proofs.any fun proof => proof.1 == invariantName && proof.2 == .preserving
  pure { invariantNames := invariants, holdsNames, preservingNames }

/-- Emit both the hypothesis-honest trace bridge and the premise-free
    generated theorem for the admitted literal-true simple-closure family.
    Every generated proof term is kernel checked; unsupported/non-ASCII params
    emit neither capability and therefore fail closed in the certifier. -/
private def elaborateSimpleClosureGeneratedTheoremsV1
    (paramsName subjectDataName subjectBytesName subjectStructureOkName :
      TSyntax `ident)
    (params : SimpleClosureParamsV1)
    (invariantNames holdsNames : Array String) : CommandElabM Unit := do
  unless simpleClosureParamsReadyForGeneratedProofV1 params do
    return
  let tailArray ← Lean.Elab.liftMacroM <| quoteStringArray params.qnTail
  let tailProof ← Lean.Elab.liftMacroM <|
    quoteIdentifierListLegalV1 params.qnTail.toList
  let headProof ← Lean.Elab.liftMacroM <|
    quoteAsciiIdentifierProofV1 params.qnHead
  let viewProof ← Lean.Elab.liftMacroM <|
    quoteAsciiIdentifierProofV1 params.viewName
  let invProof ← Lean.Elab.liftMacroM <|
    quoteAsciiIdentifierProofV1 params.invName
  let tailLegalIdent := mkIdent `simpleClosureQnTailLegalV1
  let paramsLegalIdent := mkIdent `simpleClosureParamsLegalV1
  Lean.Elab.Command.elabCommand (← `(
    /-- Exact source-order QN-tail legality certificate. -/
    def $tailLegalIdent :
        ProofForgeV2.Semantic.SimpleClosureStructureCertV1.IdentifierListLegalV1
          ($paramsName).qnTail.toList := by
      change
        ProofForgeV2.Semantic.SimpleClosureStructureCertV1.IdentifierListLegalV1
          ($tailArray).toList
      exact $tailProof))
  Lean.Elab.Command.elabCommand (← `(
    /-- Exact legal-parameter certificate for the generated simple closure. -/
    def $paramsLegalIdent :
        ProofForgeV2.Semantic.SimpleClosureStructureCertV1.SimpleClosureParamsLegalV1
          $paramsName := {
      hqnSize := by decide
      hqnCap := by decide
      hdistinct := by decide
      hqnHead := $headProof
      hqnTail := fun i hi =>
        ProofForgeV2.Semantic.SimpleClosureStructureCertV1.IdentifierListLegalV1.arrayGetElem
          $tailLegalIdent i hi
      hview := $viewProof
      hinv := $invProof
    }))
  Lean.Elab.Command.elabCommand (← `(
    /-- Production structure success for this exact generated subject. The
        family theorem itself composes every production structure phase. -/
    theorem $subjectStructureOkName :
        ProofForgeV2.Semantic.WireV1.validateSemanticProgramStructureV1
          $subjectDataName = .ok () := by
      change
        ProofForgeV2.Semantic.WireV1.validateSemanticProgramStructureV1
          (ProofForgeV2.Semantic.SimpleClosureTraceV1.materializeSimpleClosureDataV1
            $paramsName) = .ok ()
      exact
        ProofForgeV2.Semantic.SimpleClosureStructureCertV1.structure_of_legal
          $paramsName $paramsLegalIdent))
  for (invariantName, ordinal) in invariantNames.zipIdx do
    unless holdsNames.contains invariantName do
      continue
    -- Family soundness is fixed at ordinal 0 / invName = params.invName.
    unless invariantName == params.invName && ordinal == 0 do
      continue
    let genBase := generatedSimpleClosureTheoremNameV1 invariantName
    let nameDefStr := generatedSimpleClosureTheoremNameDefV1 invariantName
    let bridgeStr := generatedSimpleClosureTheoremBridgeNameV1 invariantName
    if isFixedInlineProofSurfaceNameV1 genBase ||
        isFixedInlineProofSurfaceNameV1 nameDefStr ||
        isFixedInlineProofSurfaceNameV1 bridgeStr then
      throwError "generated theorem name '{genBase}' collides with fixed proof surface"
    let nameDefIdent := mkIdent (Name.mkSimple nameDefStr)
    let bridgeIdent := mkIdent (Name.mkSimple bridgeStr)
    let generatedIdent := mkIdent (Name.mkSimple genBase)
    let invIdent := mkIdent (Name.mkSimple invariantName)
    Lean.Elab.Command.elabCommand (← `(
      /-- Compiler-owned generated theorem name for this invariant. -/
      def $nameDefIdent : String := $(quote genBase)))
    Lean.Elab.Command.elabCommand (← `(
      /-- Hypothesis-honest compatibility bridge for explicit wire traces. -/
      theorem $bridgeIdent
          (t : ProofForgeV2.Semantic.SimpleClosureTraceV1.SimpleClosureWireTraceV1
                 $paramsName $subjectBytesName) :
          $invIdent :=
        ProofForgeV2.Semantic.SimpleClosureTraceV1.invariantTheoremV1_of_simpleClosureWireTrace
          $paramsName $subjectBytesName t))
    Lean.Elab.Command.elabCommand (← `(
      set_option maxHeartbeats 80000000 in
      set_option maxRecDepth 400000 in
      /-- Premise-free compiler-generated theorem for the exact literal-true
          simple-closure semantic subject at ordinal zero. -/
      theorem $generatedIdent : $invIdent := by
        exact
          ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1.invariantTheoremV1_of_simpleClosure_legal
            $paramsName $paramsLegalIdent))

private def elaborateProofObligations
    (programName : TSyntax `ident)
    (source : ValidatedSourceV1)
    (surface : ProofSurfaceV1) : CommandElabM Unit := do
  if surface.invariantNames.isEmpty then
    return
  -- Export/parser fixtures may carry proof items without product Normalize
  -- success. Skip proof aliases on Normalize failure (fail closed later at
  -- certifier elab when aliases are missing); never hard-error export.
  let carrier ← match normalizeProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        -- Program export remains available for source/parser fixtures outside
        -- the current Normalize closure. Such a program cannot expose a
        -- theorem obligation alias, so an adjacent theorem still fails closed
        -- at name elaboration; product check/build will report the located
        -- Normalize diagnostic before certification.
        return
  -- Proof subjects:
  --   * `subjectDataV1` — structured SemanticProgramDataV1 spine (mig-a3-elab);
  --     preferred author surface for shape/preservation facts without large
  --     byte-spine defeq.
  --   * `subjectBytesV1` / `subjectProgramV1` — exact certifier identity.
  --     Every program receives the same transparent byte-spine representation;
  --     there is no contract registry, pin lookup, or package-owned golden hop.
  let data ← match lowerProgramDataV1 source with
    | .ok value => pure value
    | .error _ =>
        -- Normalize already encoded successfully; lower must succeed for the
        -- same ValidatedSource snapshot. Fail closed without partial aliases.
        return
  let dataExpr : TSyntax `term ←
    Lean.Elab.liftMacroM <| quoteSemanticProgramDataV1 data
  let bytesExpr : TSyntax `term ←
    Lean.Elab.liftMacroM <| quoteByteArraySpine carrier.canonicalBytes
  let proofNamespace := mkIdent `Proof
  let preservingNamespace := mkIdent `ProofPreserving
  let subjectName := mkIdent `subjectProgramV1
  let sharedSubjectName := mkIdent `Proof.subjectProgramV1
  let subjectBytesName := mkIdent `subjectBytesV1
  let subjectDataName := mkIdent `subjectDataV1
  let modelSubjectProgramName :=
    mkIdent (programName.getId ++ `Proof.subjectProgramV1)
  let modelSubjectDataName :=
    mkIdent (programName.getId ++ `Proof.subjectDataV1)
  let subjectBodyEncodeOkName := mkIdent `subjectBodyEncodeOkV1
  let subjectRootGatesOkName := mkIdent `subjectRootGatesOkV1
  let subjectStructureOkName := mkIdent `subjectStructureOkV1
  Lean.Elab.Command.elabCommand (← `(namespace $programName))
  Lean.Elab.Command.elabCommand (← `(namespace $proofNamespace))
  Lean.Elab.Command.elabCommand (← `(def $subjectDataName :
      ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1 := $dataExpr))
  Lean.Elab.Command.elabCommand (← `(def $subjectBytesName : ByteArray := $bytesExpr))
  Lean.Elab.Command.elabCommand (← `(def $subjectName :
      ProofForgeV2.Semantic.WireV1.SemanticProgramV1 :=
    { canonicalBytes := $subjectBytesName }))
  Lean.Elab.Command.elabCommand (← `(
    set_option maxHeartbeats 80000000 in
    set_option maxRecDepth 400000 in
    /-- Kernel-checked equality between the generated structured subject and
        its exact product byte spine. This is emitted uniformly for every
        proof-bearing program; it contains no contract registry or byte pin. -/
    theorem $subjectBodyEncodeOkName :
        ProofForgeV2.Semantic.WireV1.encodeSemanticProgramDataBodyV1
          $subjectDataName = .ok $subjectBytesName := by
      rfl))
  Lean.Elab.Command.elabCommand (← `(
    /-- Kernel-checked production root-gate certificate for the exact generated
        subject. This proves only the qualified-name and table-size gates; it
        does not stand in for structure validation or codec inversion. -/
    theorem $subjectRootGatesOkName :
        ProofForgeV2.Semantic.WireV1.validateProgramQualifiedNameShapeV1
            ($subjectDataName).qualifiedName = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).types.size = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).constants.size = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).logicalState.size = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).events.size = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).errors.size = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).callables.size = .ok () ∧
          ProofForgeV2.Semantic.WireV1.checkTableSize
              ($subjectDataName).invariants.size = .ok () := by
      exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩))
  for (invariantName, ordinal) in surface.invariantNames.zipIdx do
    if surface.holdsNames.contains invariantName then
      let invariantIdent := mkIdent (Name.str .anonymous invariantName)
      let ordinalTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString ordinal)⟩
      Lean.Elab.Command.elabCommand (← `(abbrev $invariantIdent : Prop :=
        ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1
          $subjectName $ordinalTerm))
  -- Structure certification is independent of proof kind. It is emitted only
  -- for an exactly recognized family with an existing production-phase proof;
  -- holds-only generated invariant helpers remain selected inside the helper.
  match extractSimpleClosureParamsFromCarrierV1 carrier with
  | none => pure ()
  | some params => do
      let paramsName := mkIdent `simpleClosureParamsV1
      let dataName := mkIdent `simpleClosureDataV1
      let paramsExpr ← Lean.Elab.liftMacroM <| quoteSimpleClosureParams params
      Lean.Elab.Command.elabCommand (← `(def $paramsName :
          ProofForgeV2.Semantic.SimpleClosureTraceV1.SimpleClosureParamsV1 :=
        $paramsExpr))
      Lean.Elab.Command.elabCommand (← `(def $dataName :
          ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1 :=
        ProofForgeV2.Semantic.SimpleClosureTraceV1.materializeSimpleClosureDataV1
          $paramsName))
      elaborateSimpleClosureGeneratedTheoremsV1
        paramsName subjectDataName subjectBytesName subjectStructureOkName params
          surface.invariantNames surface.holdsNames
  Lean.Elab.Command.elabCommand (← `(end $proofNamespace))
  match modelStateFieldsV1 data with
  | none => pure ()
  | some fields =>
      elaborateStateModelV1 modelSubjectProgramName modelSubjectDataName data fields
  unless surface.preservingNames.isEmpty do
    Lean.Elab.Command.elabCommand (← `(namespace $preservingNamespace))
    for (invariantName, ordinal) in surface.invariantNames.zipIdx do
      if surface.preservingNames.contains invariantName then
        let invariantIdent := mkIdent (Name.str .anonymous invariantName)
        let ordinalTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString ordinal)⟩
        Lean.Elab.Command.elabCommand (← `(abbrev $invariantIdent : Prop :=
          ProofForgeV2.Semantic.PreservationABI.PreservationTheoremV1
            $sharedSubjectName $ordinalTerm))
    Lean.Elab.Command.elabCommand (← `(end $preservingNamespace))
  Lean.Elab.Command.elabCommand (← `(end $programName))
elab_rules : command
  | `(program $name:ident where $items:pfItem*) => do
      let env ← getEnv
      let moduleName ← match sourceQualifiedNameV1FromLeanName env.mainModule with
        | .ok value => pure value
        | .error message => throwError message
      let currentNamespace ← getCurrNamespace
      let relativeNamespace :=
        currentNamespace.replacePrefix env.mainModule .anonymous
      let commandStx ← `(program $name:ident where $items:pfItem*)
      let source ← match decodeProgramCommandV1Checked
          moduleName (.bounded relativeNamespace) commandStx with
        | .error error => throwError error.render
        | .ok source => pure source
      let bytes ← match canonicalValidatedSourceAstBytesV1 source with
        | .error message => throwError message
        | .ok bytes => pure bytes
      let proofSurface ← match proofSurfaceV1 source with
        | .ok value => pure value
        | .error message => throwError message
      let bytesExpr ← Lean.Elab.liftMacroM <| quoteByteArray bytes
      let expanded ← `(@[proof_forge_program]
        def $name : ProgramExportPayloadV2 := {
          schema := $(Syntax.mkStrLit programExportSchemaV2),
          bytes := $bytesExpr
        })
      Lean.Elab.Command.elabCommand expanded
      elaborateProofObligations name source proofSurface

end ProofForgeV2.Language

/-!
  ## B-SC-ELAB-THM engineering status

  Shipped for the narrow literal-true/public-Bool-view family:
    * one exact generated semantic subject shared by both proof kinds;
    * kind-selected source-order aliases under `Proof` / `ProofPreserving`;
    * concrete ASCII identifier legality certificates for holds;
    * hypothesis-honest `generated…V1_of_wireTrace` holds bridge;
    * premise-free `generated…V1 : <Program>.Proof.<inv>` derived from
      `invariantTheoremV1_of_simpleClosure_legal`;
    * same-file ordinary holds theorem authoring such as
      `exact <Program>.Proof.generatedSafeV1`.

  Preserving aliases deliberately receive no simple-closure helper; program
  instances must prove the generic Reference-based preservation proposition.
  Unsupported semantic shapes and non-ASCII generated-proof parameters remain
  fail closed. This lane does not claim reachability, target refinement,
  formal TST closure, sandboxing, hermeticity, or release qualification.

  Forbidden in emitted declarations: sorry / axiom / native_decide /
  Lean.ofReduceBool / run_tac / meta / unsafe / IO proof bodies and Tests
  imports.
-/
