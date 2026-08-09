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

/-- Emit the author-facing business-state view. It is only a typed projection
    over `Proof.subjectDataV1`: encoding and decoding call the production
    logical-state codec, and this phase intentionally emits no step/evaluator. -/
private def elaborateStateModelV1
    (subjectProgramName : TSyntax `ident)
    (subjectDataName : TSyntax `ident)
    (fields : Array ModelStateFieldV1) : CommandElabM Unit := do
  let modelNamespace := mkIdent `Model
  let stateName := mkIdent `State
  let typedStateName := mkIdent `typedState
  let encodeStateName := mkIdent `encodeState
  let decodeStateName := mkIdent `decodeState
  let decodeEncodeName := mkIdent `decode_encode
  let decodeExistsUniqueName := mkIdent `decode_existsUnique_of_conforms
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
    (paramsName subjectBytesName : TSyntax `ident)
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
    let tailLegalIdent := mkIdent `simpleClosureQnTailLegalV1
    let paramsLegalIdent := mkIdent `simpleClosureParamsLegalV1
    Lean.Elab.Command.elabCommand (← `(
      /-- Compiler-owned generated theorem name for this invariant. -/
      def $nameDefIdent : String := $(quote genBase)))
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
  for (invariantName, ordinal) in surface.invariantNames.zipIdx do
    if surface.holdsNames.contains invariantName then
      let invariantIdent := mkIdent (Name.str .anonymous invariantName)
      let ordinalTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString ordinal)⟩
      Lean.Elab.Command.elabCommand (← `(abbrev $invariantIdent : Prop :=
        ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1
          $subjectName $ordinalTerm))
  -- Name/module-parameterized certificate AST for the literal-true simple-
  -- closure family remains holds-only. Preserving proofs never receive a
  -- generated helper that could masquerade as a step-preservation proof.
  unless surface.holdsNames.isEmpty do
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
          paramsName subjectBytesName params surface.invariantNames surface.holdsNames
  Lean.Elab.Command.elabCommand (← `(end $proofNamespace))
  match modelStateFieldsV1 data with
  | none => pure ()
  | some fields =>
      elaborateStateModelV1 modelSubjectProgramName modelSubjectDataName fields
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
