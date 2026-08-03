import ProofForgeV2.Language.Syntax
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1

open Lean Parser Command
open Lean.Elab.Command
open ProofForgeV2
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.AstProgramItemV1
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

  **Current ship (honest prep):** naming + name-string def + hypothesis-honest
  `_of_wireTrace` bridge that packages
  `invariantTheoremV1_of_simpleClosureWireTrace` against elaborator
  `simpleClosureParamsV1` / `subjectBytesV1`. Unconditional theorem mint is
  blocked on B-SC-ENC + B-SC-DEC (exact missing lemmas listed at module end).
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

/-- Bridge declaration name reserved until encode/decode close the
    unconditional theorem: `generatedSafeV1_of_wireTrace`. -/
def generatedSimpleClosureTheoremBridgeNameV1 (invName : String) : String :=
  generatedSimpleClosureTheoremNameV1 invName ++ "_of_wireTrace"

/-- Name-string definition emitted alongside the bridge:
    `generatedSafeV1Name`. -/
def generatedSimpleClosureTheoremNameDefV1 (invName : String) : String :=
  generatedSimpleClosureTheoremNameV1 invName ++ "Name"

/-- Fixed elaborator surface names authors must not use as invariant ids. -/
private def isFixedInlineProofSurfaceNameV1 (name : String) : Bool :=
  name == "subjectProgramV1" || name == "subjectBytesV1" ||
    name == "simpleClosureParamsV1" || name == "simpleClosureDataV1"

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

private def proofInvariantNames
    (source : ValidatedSourceV1) : Except String (Array String) := do
  let invariants := source.program.items.filterMap fun item =>
    match item with
    | .invariant declaration => some declaration.name.raw
    | _ => none
  let proofs := source.program.items.filterMap fun item =>
    match item with
    | .proof declaration => some declaration.invariant.raw
    | _ => none
  if proofs.isEmpty then
    return #[]
  unless proofs.size == invariants.size do
    throw "inline proof programs require exactly one proof reference per invariant"
  for invariantName in invariants do
    unless proofs.any (· == invariantName) do
      throw s!"inline proof program is missing proof reference for invariant '{invariantName}'"
    if isReservedInlineProofSurfaceNameV1 invariantName then
      throw s!"invariant name '{invariantName}' is reserved by the inline proof surface"
  for proofName in proofs do
    unless invariants.any (· == proofName) do
      throw s!"proof reference names unknown invariant '{proofName}'"
  pure invariants

/-- Emit hypothesis-honest generated-theorem bridge for the literal-true
    simple-closure invariant at ordinal 0 (family shape). Does **not** mint
    unconditional `generated…V1` (B-SC-ENC / B-SC-DEC still open). -/
private def elaborateSimpleClosureGeneratedTheoremBridgeV1
    (paramsName subjectBytesName : TSyntax `ident)
    (params : SimpleClosureParamsV1)
    (invariantNames : Array String) : CommandElabM Unit := do
  for (invariantName, ordinal) in invariantNames.zipIdx do
    -- Family soundness is fixed at ordinal 0 / invName = params.invName.
    unless invariantName == params.invName && ordinal == 0 do
      continue
    let genBase := generatedSimpleClosureTheoremNameV1 invariantName
    let nameDefStr := generatedSimpleClosureTheoremNameDefV1 invariantName
    let bridgeStr := generatedSimpleClosureTheoremBridgeNameV1 invariantName
    -- Generated names always start with `generated` and end with `V1`; only
    -- refuse collision with the fixed subject/params surface, not the
    -- generated-* reservation pattern applied to user invariant names.
    if isFixedInlineProofSurfaceNameV1 genBase ||
        isFixedInlineProofSurfaceNameV1 nameDefStr ||
        isFixedInlineProofSurfaceNameV1 bridgeStr then
      throwError "generated theorem name '{genBase}' collides with fixed proof surface"
    let nameDefIdent := mkIdent (Name.mkSimple nameDefStr)
    let bridgeIdent := mkIdent (Name.mkSimple bridgeStr)
    let invIdent := mkIdent (Name.mkSimple invariantName)
    Lean.Elab.Command.elabCommand (← `(
      /-- Product name reserved for the future unconditional generated theorem
          (`generated…V1 : Proof.<inv>`). Unconditional mint waits on B-SC-ENC
          + B-SC-DEC; see `ProgramElaborationV1` module footer. -/
      def $nameDefIdent : String := $(quote genBase)))
    -- Bridge: wire-trace premise → Prop alias. Compiles under import
    -- ProofForgeV2 only; no Tests, no sorry/axiom/native_decide.
    Lean.Elab.Command.elabCommand (← `(
      /-- Hypothesis-honest generated-theorem bridge for the simple-closure
          family. Adjacent authors may write
          `exact generated…V1_of_wireTrace t` once they hold a
          `SimpleClosureWireTraceV1`. Unconditional `generated…V1` requires
          discharging encode/decode (B-SC-ENC / B-SC-DEC). -/
      theorem $bridgeIdent
          (t : ProofForgeV2.Semantic.SimpleClosureTraceV1.SimpleClosureWireTraceV1
                 $paramsName $subjectBytesName) :
          $invIdent :=
        ProofForgeV2.Semantic.SimpleClosureTraceV1.invariantTheoremV1_of_simpleClosureWireTrace
          $paramsName $subjectBytesName t))

private def elaborateProofObligations
    (programName : TSyntax `ident)
    (source : ValidatedSourceV1)
    (invariantNames : Array String) : CommandElabM Unit := do
  if invariantNames.isEmpty then
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
  -- Proof subjects use a transparent spine so certificate modules can link
  -- by definitional equality without hex reduction OOM.
  let bytesExpr ← Lean.Elab.liftMacroM <| quoteByteArraySpine carrier.canonicalBytes
  let proofNamespace := mkIdent `Proof
  let subjectName := mkIdent `subjectProgramV1
  let subjectBytesName := mkIdent `subjectBytesV1
  Lean.Elab.Command.elabCommand (← `(namespace $programName))
  Lean.Elab.Command.elabCommand (← `(namespace $proofNamespace))
  Lean.Elab.Command.elabCommand (← `(def $subjectBytesName : ByteArray := $bytesExpr))
  Lean.Elab.Command.elabCommand (← `(def $subjectName :
      ProofForgeV2.Semantic.WireV1.SemanticProgramV1 :=
    { canonicalBytes := $subjectBytesName }))
  for (invariantName, ordinal) in invariantNames.zipIdx do
    let invariantIdent := mkIdent (Name.str .anonymous invariantName)
    let ordinalTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString ordinal)⟩
    Lean.Elab.Command.elabCommand (← `(abbrev $invariantIdent : Prop :=
      ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1
        $subjectName $ordinalTerm))
  -- Name/module-parameterized certificate AST for the literal-true simple-
  -- closure family. Emitted only when Normalize data matches the family; does
  -- **not** mint a complete unconditional theorem (encode/decode parametric
  -- closure still open — see module footer / SimpleClosureTraceV1 blockers).
  -- Authors may reference constructors + the `_of_wireTrace` bridge from
  -- same-file theorems without hardcoding Tests FQNs/bytes.
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
      elaborateSimpleClosureGeneratedTheoremBridgeV1
        paramsName subjectBytesName params invariantNames
  Lean.Elab.Command.elabCommand (← `(end $proofNamespace))
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
      let invariantNames ← match proofInvariantNames source with
        | .ok value => pure value
        | .error message => throwError message
      let bytesExpr ← Lean.Elab.liftMacroM <| quoteByteArray bytes
      let expanded ← `(@[proof_forge_program]
        def $name : ProgramExportPayloadV2 := {
          schema := $(Syntax.mkStrLit programExportSchemaV2),
          bytes := $bytesExpr
        })
      Lean.Elab.Command.elabCommand expanded
      elaborateProofObligations name source invariantNames

end ProofForgeV2.Language

/-!
  ## B-SC-ELAB-THM status (do not forge)

  Shipped here:
    * product naming `generatedSimpleClosureTheoremNameV1` (`safe` → `generatedSafeV1`)
    * elaborator emission of `generated…V1Name : String` under `<Program>.Proof`
    * elaborator emission of hypothesis-honest
      `generated…V1_of_wireTrace (t : SimpleClosureWireTraceV1 params bytes) :
         <Program>.Proof.<inv>`
      via sole production soundness
      `invariantTheoremV1_of_simpleClosureWireTrace` (no Tests import)

  **Not** shipped (blocked; exact missing production lemmas):

  | ID | Missing lemma / witness | Why required for unconditional `generated…V1` |
  |---|---|---|
  | B-SC-ENC residual | `encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) = .ok (simpleClosureWireBytesV1 p)` for elaborator `p` without free `hfields`, **or** `= .ok subjectBytesV1` for elaborator spine | Supplies `SimpleClosureWireTraceV1.hencode` |
  | B-SC-DEC residual | `decodeSemanticProgramDataV1 (simpleClosureWireBytesV1 p) = .ok (materializeSimpleClosureDataV1 p)` / `DecodeSimpleClosureGoalV1 p`, **or** decode of elaborator `subjectBytesV1` | Supplies `SimpleClosureWireTraceV1.hdecode` |
  | B-SC-ELAB-BYTES (optional join) | `subjectBytesV1 = simpleClosureWireBytesV1 simpleClosureParamsV1` when encode path uses wire-bytes builder | Joins elaborator spine to parametric wire bytes for certifier defeq |
  | B-SC-ELAB-THM close | Unconditional `theorem generated…V1 : Proof.<inv> := …` with no free hyps | Composition of the above + already-closed structure/witness/soundness |

  Adjacent ordinary theorems may today write
  `exact <Program>.Proof.generated…V1_of_wireTrace t` only after constructing
  `t` from production encode/decode certificates (Tests-side Proofed chain is
  one such construction; product-positive path still open).

  Forbidden in this lane: sorry / axiom / native_decide / Lean.ofReduceBool /
  run_tac / meta / unsafe / IO proof bodies, Tests imports inside elaborator-
  emitted declarations.
-/
