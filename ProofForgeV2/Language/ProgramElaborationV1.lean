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
    if invariantName == "subjectProgramV1" || invariantName == "subjectBytesV1" ||
        invariantName == "simpleClosureParamsV1" ||
        invariantName == "simpleClosureDataV1" then
      throw s!"invariant name '{invariantName}' is reserved by the inline proof surface"
  for proofName in proofs do
    unless invariants.any (· == proofName) do
      throw s!"proof reference names unknown invariant '{proofName}'"
  pure invariants

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
  -- **not** mint a complete theorem (encode/decode parametric closure still
  -- open — see SimpleClosureTraceV1 blockers). Authors may reference these
  -- constructors from same-file theorems without hardcoding Tests FQNs/bytes.
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
