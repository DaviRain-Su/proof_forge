import ProofForgeV2.Language.Syntax
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1

open Lean Parser Command
open Lean.Elab.Command
open ProofForgeV2
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Language

private def quoteByteArray (bytes : ByteArray) : MacroM (TSyntax `term) := do
  let hex := bytes.foldl (fun acc byte =>
    (acc.push (Nat.digitChar (byte.toNat / 16))).push
      (Nat.digitChar (byte.toNat % 16))) ""
  `(ProofForgeV2.Language.ProgramExport.programExportBytesFromHex $(quote hex))

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
    if invariantName == "subjectProgramV1" then
      throw "invariant name 'subjectProgramV1' is reserved by the inline proof surface"
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
  let carrier ← match normalizeProgramV1 source with
    | .ok value => pure value
    | .error error =>
        throwError
          "inline proof subject normalization failed; product normalization must accept the program before theorem elaboration ({repr error})"
  let bytesExpr ← Lean.Elab.liftMacroM <| quoteByteArray carrier.canonicalBytes
  let proofNamespace := mkIdent `Proof
  let subjectName := mkIdent `subjectProgramV1
  Lean.Elab.Command.elabCommand (← `(namespace $programName))
  Lean.Elab.Command.elabCommand (← `(namespace $proofNamespace))
  Lean.Elab.Command.elabCommand (← `(def $subjectName :
      ProofForgeV2.Semantic.WireV1.SemanticProgramV1 :=
    { canonicalBytes := $bytesExpr }))
  for (invariantName, ordinal) in invariantNames.zipIdx do
    let invariantIdent := mkIdent (Name.str .anonymous invariantName)
    let ordinalTerm : TSyntax `term := ⟨Syntax.mkNumLit (toString ordinal)⟩
    Lean.Elab.Command.elabCommand (← `(abbrev $invariantIdent : Prop :=
      ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1
        $subjectName $ordinalTerm))
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
