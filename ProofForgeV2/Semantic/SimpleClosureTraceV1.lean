import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.AuthorWireCertV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.SimpleClosureCertV1
import ProofForgeV2.Semantic.WireV1

/-
  ProofForgeV2.Semantic.SimpleClosureTraceV1 — production certificate-trace
  foundation for the Normalize literal-true simple-closure family:

    view <viewName>() : Bool do return true
    invariant <invName> : true

  Purpose: replace per-program 1k-line encode/decode byte scripts with a
  name/module-parameterized certificate AST. ProgramElaboration can emit
  `SimpleClosureParamsV1` constructors from Normalize data; authors (or a
  later generator) close `InvariantTheoremV1` via the soundness theorem once
  the wire encode/decode premises are discharged for the materialization.

  Current shipped slice (engineering; not formal TST-PROOF-001):
    * single nullary public Bool view + single nullary literal-true invariant
    * anonymous Bool + UInt64 type table (Normalize target envelope)
    * sole S2 `value.bool` requirement row
    * empty constants/state/events/errors
    * invariant ordinal 0, callableId 1, invariantSteps = some 3

  Composition path (no second model):

    SimpleClosureParamsV1
      ── materializeSimpleClosureDataV1
      ──► SemanticProgramDataV1
      ── LiteralTrueInvariantWitnessV1 (parametric, closed)
      ── + encode/decode of exact product bytes
      ──► AuthorWireCertV1
      ──► InvariantTheoremV1 ⟨bytes⟩ 0

  Hard boundaries:
    * no axiom / sorry / native_decide / ofReduceBool / run_tac / unsafe / meta / IO
    * no hardcoded Tests FQN / fixture bytes
    * theorem bodies never enter ProgramV1 / sourceHash / semanticHash
    * does not trust user .olean
    * structure under `SimpleClosureParamsLegalV1` is closed by
      `SimpleClosureStructureCertV1` (B-SC-STRUCT); encode/decode remain open
      (exact blockers documented at module end)

  Not yet product-positive: raw-source certifier still needs unconditional
  encode+decode witnesses for materialize(params) vs elaborator subjectBytes.
-/

namespace ProofForgeV2.Semantic.SimpleClosureTraceV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.AuthorWireCertV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.SimpleClosureCertV1
open ProofForgeV2.Semantic.WireV1

/-! ### Name/module-parameterized certificate AST -/

/-- Free parameters of the literal-true simple-closure family.
    Fully name/module parameterized: no Tests FQN, no fixture bytes. -/
structure SimpleClosureParamsV1 where
  /-- Program identity head component (QualifiedName.head). -/
  qnHead : String
  /-- Remaining QualifiedName components (may be empty when head alone would
      violate the ≥2 component shape; well-formedness requires total ≥2). -/
  qnTail : Array String
  /-- Nullary Bool view name (callable 0). -/
  viewName : String
  /-- Nullary literal-true invariant name (callable 1, InvariantDecl 0). -/
  invName : String
  deriving BEq, Repr, Inhabited

/-- Total qualified-name component count. -/
def SimpleClosureParamsV1.qnSize (p : SimpleClosureParamsV1) : Nat :=
  p.qnTail.size + 1

/-- Build a production `QualifiedName` from free name parameters.
    Always succeeds: `qnHead` is the NonEmptyArray head. -/
def SimpleClosureParamsV1.toQualifiedName (p : SimpleClosureParamsV1) :
    QualifiedName :=
  { components := { head := p.qnHead, tail := p.qnTail } }

/-- Engineering well-formedness for the certificate AST (not full Unicode NFC
    grammar — that remains the structure gate's authority). Requires:
      * ≥2 QN components
      * nonempty view/inv names
      * viewName ≠ invName
    Identifier grammar is re-checked by structure validation of the
    materialized data; this predicate is only the parametric certificate gate. -/
structure SimpleClosureParamsWellFormedV1 (p : SimpleClosureParamsV1) : Prop where
  hqnSize : 2 ≤ p.qnSize
  hview : p.viewName.length ≠ 0
  hinv : p.invName.length ≠ 0
  hdistinct : p.viewName ≠ p.invName

/-! ### Fixed family micro-shapes (name holes only) -/

/-- Anonymous Bool type at TypeId 0. -/
def simpleClosureBoolTypeV1 : TypeDeclV1 :=
  { id := 0, name := none, shape := .bool }

/-- Anonymous UInt64 type at TypeId 1 (Normalize target envelope). -/
def simpleClosureUInt64TypeV1 : TypeDeclV1 :=
  { id := 1, name := none, shape := .uint 64 }

/-- Sole Bool-true instruction used by both view and invariant bodies. -/
def simpleClosureLitTrueV1 : InstructionV1 :=
  { result := some { valueId := 0, typeId := 0 }, op := .literal 0 (encodeU8 1) }

/-- Single-block CFG: literal true; return valueId 0. -/
def simpleClosureBlockV1 : BlockV1 :=
  {
    id := 0
    params := #[]
    instructions := #[simpleClosureLitTrueV1]
    terminator := .return_ (some 0)
  }

/-- Closed S2 `value.bool` requirement row (transparent digest spine). -/
def simpleClosureBoolRequirementV1 : RequirementRequestV1 :=
  {
    id := "value.bool"
    version := s2RequirementVersionV1
    digest := { algorithm := .sha256, bytes := s2ValueBoolDigestBytesV1 }
    predicates := #[]
  }

/-- Nullary public Bool view callable (id 0). -/
def simpleClosureViewCallableV1 (viewName : String) : CallableV1 :=
  {
    id := 0
    kind := .view
    name := some viewName
    params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[simpleClosureBlockV1]
    loopBounds := #[]
    invariantSteps := none
  }

/-- Nullary public Bool invariant callable (id 1, steps 3). -/
def simpleClosureInvCallableV1 (invName : String) : CallableV1 :=
  {
    id := 1
    kind := .invariant
    name := some invName
    params := #[]
    result := { typeId := 0, visibility := .public_ }
    entryBlock := 0
    blocks := #[simpleClosureBlockV1]
    loopBounds := #[]
    invariantSteps := some 3
  }

/-- Dense InvariantDecl row at ordinal 0 → callable 1. -/
def simpleClosureInvariantDeclV1 (invName : String) : InvariantDeclV1 :=
  { id := 0, name := invName, callableId := 1 }

/-! ### Materialize production SemanticProgramDataV1 -/

/-- Materialize the exact Normalize simple-closure data shape from free name
    parameters. Total: QN head is always present. -/
def materializeSimpleClosureDataV1 (p : SimpleClosureParamsV1) :
    SemanticProgramDataV1 :=
  {
    qualifiedName := p.toQualifiedName
    types := #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1]
    constants := #[]
    logicalState := #[]
    events := #[]
    errors := #[]
    callables :=
      #[simpleClosureViewCallableV1 p.viewName,
        simpleClosureInvCallableV1 p.invName]
    invariants := #[simpleClosureInvariantDeclV1 p.invName]
    requirements := { items := #[simpleClosureBoolRequirementV1] }
  }

/-- Compatibility alias: materialize is total, so Option is always `some`. -/
def materializeSimpleClosureDataV1? (p : SimpleClosureParamsV1) :
    Option SemanticProgramDataV1 :=
  some (materializeSimpleClosureDataV1 p)

theorem materializeSimpleClosureDataV1?_eq (p : SimpleClosureParamsV1) :
    materializeSimpleClosureDataV1? p = some (materializeSimpleClosureDataV1 p) :=
  rfl

/-! ### Family recognition (Normalize data → params) -/

/-- Recognize a single-view + single-literal-true-invariant Normalize carrier
    and recover its free name parameters. Fail closed on any other shape. -/
def extractSimpleClosureParamsV1
    (data : SemanticProgramDataV1) : Option SimpleClosureParamsV1 :=
  -- Types: anonymous Bool + anonymous UInt64 only.
  if data.types.size != 2 then none
  else
    match data.types[0]?, data.types[1]? with
    | some t0, some t1 =>
        if !(t0 == simpleClosureBoolTypeV1) then none
        else if !(t1 == simpleClosureUInt64TypeV1) then none
        else if !data.constants.isEmpty then none
        else if !data.logicalState.isEmpty then none
        else if !data.events.isEmpty then none
        else if !data.errors.isEmpty then none
        else if data.requirements.items.size != 1 then none
        else
          match data.requirements.items[0]? with
          | none => none
          | some req =>
              if !(req == simpleClosureBoolRequirementV1) then none
              else if data.callables.size != 2 then none
              else if data.invariants.size != 1 then none
              else
                match data.callables[0]?, data.callables[1]?, data.invariants[0]? with
                | some viewC, some invC, some invDecl =>
                    match viewC.name, invC.name with
                    | some viewName, some invName =>
                        if viewC.kind != .view then none
                        else if invC.kind != .invariant then none
                        else if !(viewC == simpleClosureViewCallableV1 viewName) then none
                        else if !(invC == simpleClosureInvCallableV1 invName) then none
                        else if !(invDecl == simpleClosureInvariantDeclV1 invName) then none
                        else
                          let comps :=
                            NonEmptyArray.toArray data.qualifiedName.components
                          if comps.size < 2 then none
                          else
                            match comps[0]? with
                            | none => none
                            | some head =>
                                some {
                                  qnHead := head
                                  qnTail := comps.extract 1 comps.size
                                  viewName := viewName
                                  invName := invName
                                }
                    | _, _ => none
                | _, _, _ => none
    | _, _ => none

/-! ### Parametric literal-true witness -/

/-- Bool-true valueBytes are canonical under the fixed family type table.
    Mirrors Tests.Semantic.ProofedCertV1.boolLiteralTrue_canonical — no
    native_decide / ofReduceBool. -/
theorem simpleClosure_boolLiteralTrue_canonical :
    validateValueBytesV1
      #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1]
      0 (encodeU8 1) = .ok () := by
  simp [simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1, encodeU8,
    validateValueBytesV1, Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

/-- Materialized data always carries the production literal-true witness at
    ordinal 0 (parametric in free names). -/
theorem literalTrueWitness_of_materialize (p : SimpleClosureParamsV1) :
    LiteralTrueInvariantWitnessV1 (materializeSimpleClosureDataV1 p) 0
      (simpleClosureInvariantDeclV1 p.invName)
      0 (some p.invName) .public_ none := by
  refine {
    hselection := rfl
    htype := rfl
    hroot := ?_
    hcanonical := simpleClosure_boolLiteralTrue_canonical
  }
  -- callables[UInt32.toNat 1]? with callableId = 1.
  change
    (#[simpleClosureViewCallableV1 p.viewName,
        simpleClosureInvCallableV1 p.invName] : Array CallableV1)[1]? =
      some (simpleClosureInvCallableV1 p.invName)
  rfl

/-! ### Wire trace certificate (encode/decode still free premises) -/

/-- Kernel-checked wire certificate for a name-parameterized simple-closure
    carrier. Structure is implied by successful encode; shape is closed by
    materialize. Encode/decode remain explicit production premises — the
    parametric codec closure is the remaining blocker (see module footer). -/
structure SimpleClosureWireTraceV1
    (p : SimpleClosureParamsV1)
    (bytes : ByteArray) : Prop where
  /-- Params are certificate-well-formed. -/
  hwf : SimpleClosureParamsWellFormedV1 p
  /-- Sole product encoder success for these exact bytes. -/
  hencode :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) = .ok bytes
  /-- Transport decode recovers the same materialized data. -/
  hdecode :
    decodeSemanticProgramDataV1 bytes = .ok (materializeSimpleClosureDataV1 p)

/-- Assemble a wire trace from the production premises. -/
def SimpleClosureWireTraceV1.ofParts
    (p : SimpleClosureParamsV1)
    (bytes : ByteArray)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hencode :
      encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) = .ok bytes)
    (hdecode :
      decodeSemanticProgramDataV1 bytes = .ok (materializeSimpleClosureDataV1 p)) :
    SimpleClosureWireTraceV1 p bytes :=
  ⟨hwf, hencode, hdecode⟩

/-- Soundness: wire trace ⇒ ordinal-0 `InvariantTheoremV1` on exact product
    bytes. Reuses AuthorWireCert + SimpleClosureCert; no second evaluator. -/
theorem invariantTheoremV1_of_simpleClosureWireTrace
    (p : SimpleClosureParamsV1)
    (bytes : ByteArray)
    (t : SimpleClosureWireTraceV1 p bytes) :
    InvariantTheoremV1 { canonicalBytes := bytes } 0 := by
  let data := materializeSimpleClosureDataV1 p
  have hwitness :
      LiteralTrueInvariantWitnessV1 data 0
        (simpleClosureInvariantDeclV1 p.invName)
        0 (some p.invName) .public_ none :=
    literalTrueWitness_of_materialize p
  have c :=
    LiteralTrueAuthorWireCertV1.ofParts data bytes 0
      (simpleClosureInvariantDeclV1 p.invName)
      0 (some p.invName) .public_ none
      t.hencode t.hdecode hwitness
  exact invariantTheoremV1_of_literalTrueAuthorWireCert data bytes 0
    (simpleClosureInvariantDeclV1 p.invName)
    0 (some p.invName) .public_ none c

/-- Bridge from Normalize encode witness + decode + params identity. -/
theorem invariantTheoremV1_of_normalize_simpleClosure
    (p : SimpleClosureParamsV1)
    (w : NormalizeEncodeWitnessV1)
    (hwf : SimpleClosureParamsWellFormedV1 p)
    (hdata : w.data = materializeSimpleClosureDataV1 p)
    (hdecode : decodeSemanticProgramDataV1 w.bytes = .ok w.data) :
    InvariantTheoremV1 w.program 0 := by
  have hencode' :
      encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) = .ok w.bytes := by
    simpa [hdata] using w.hencode
  have hdecode' :
      decodeSemanticProgramDataV1 w.bytes =
        .ok (materializeSimpleClosureDataV1 p) := by
    simpa [hdata] using hdecode
  have t :=
    SimpleClosureWireTraceV1.ofParts p w.bytes hwf hencode' hdecode'
  have hclosed := invariantTheoremV1_of_simpleClosureWireTrace p w.bytes t
  simpa [NormalizeEncodeWitnessV1.program] using hclosed

/-! ### Elaboration helpers (pure data only; no Meta/IO proofs) -/

/-- Build params from an already-validated program identity + names.
    Used by ProgramElaboration when Normalize data matches the family. -/
def mkSimpleClosureParamsV1
    (qnComponents : Array String)
    (viewName invName : String) : Option SimpleClosureParamsV1 :=
  if h : qnComponents.size ≥ 1 then
    some {
      qnHead := qnComponents[0]
      qnTail := qnComponents.extract 1 qnComponents.size
      viewName
      invName
    }
  else
    none

/-- True when extracted params materialize back to the same data (family fixpoint). -/
def isSimpleClosureFamilyDataV1 (data : SemanticProgramDataV1) : Bool :=
  match extractSimpleClosureParamsV1 data with
  | none => false
  | some p => data == materializeSimpleClosureDataV1 p

end ProofForgeV2.Semantic.SimpleClosureTraceV1

/-!
  ## Exact remaining blockers (do not forge)

  For unconditional product-positive
  `InvariantTheoremV1 subjectProgramV1 0` under certifier re-elaboration
  (`import ProofForgeV2` only):

  | ID | Blocker | Why not closed here |
  |---|---|---|
  | B-SC-STRUCT | Parametric `validateSemanticProgramStructureV1 (materialize p) = ok` under `SimpleClosureParamsLegalV1` | **Closed** in `SimpleClosureStructureCertV1` (identifier/NFC + distinct names + fixed CFG/signature/fuel/requirement phases) |
  | B-SC-ENC | Parametric `encode (materialize p) = ok (simpleClosureWireBytesV1 p)` | **Partial** in `SimpleClosureEncodeV1`: transparent production-field builder + string/empty/QN-size lemmas + root equality under legality/structure/field-ok; residual = discharge field-ok from legal params without a duplicate encoder authority |
  | B-SC-DEC | Parametric `decode (simpleClosureWireBytesV1 p) = ok (materialize p)` | **Partial** in `Wire.CodecRoundtripV1` + `SimpleClosureDecodeV1`: sole Encode builder (`canonicalWireBytesV1`); production mid-offset NFC UTF-8 string / u32 / option / empty-array; QN component-list induction + array decode under `SimpleClosureParamsLegalV1`; framing/WireTrace packaging; residual = nested fixed-shape TypeDecl/Callable/Block/Requirements encode→decode + nine-field root + finish for unconditional Legal close. |
  | B-SC-ELAB-THM | ProgramElaboration mint of a complete theorem value | Depends on B-SC-ENC + B-SC-DEC (or equivalent) so generated `exact` terms typecheck without free hyps |
  | B-SC-PRODUCT | Raw-source certifier + CLI check positive | Depends on B-SC-ELAB-THM (or same-file author theorem using closed production lemmas) |

  This module closes: parametric AST, materialize, extract, witness, wire-trace
  soundness composition. Structure is closed by `SimpleClosureStructureCertV1`.
  It does **not** claim product-positive certification.
-/
