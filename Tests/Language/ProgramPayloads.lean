import Tests.Language.ProgramPayloadFixtures.Positive
import Tests.Language.ProgramPayloadFixtures.NegUnregistered
import Tests.Language.ProgramPayloadFixtures.NegConstAlias
import Tests.Language.ProgramPayloadFixtures.NegOpaque
import Tests.Language.ProgramPayloadFixtures.NegUnsafe
import Tests.Language.ProgramPayloadFixtures.NegPartial
import Tests.Language.ProgramPayloadFixtures.NegImplementedBy
import Tests.Language.ProgramPayloadFixtures.Rich
import Tests.Language.ProgramPayloadFixtures.Snapshot
import ProofForgeV2.Language.ProgramPayload
import Lean

namespace Tests.Language.ProgramPayloads
open Tests.Language.ProgramPayloadFixtures
open Tests.Language.ProgramPayloadFixtures.Rich
open ProofForgeV2.Language.ProgramPayload
open Lean

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def exactNodeExpr (nodes : Nat) : Expr := Id.run do
  let mut e := mkRawNatLit 0
  let steps := if nodes ≤ 1 then 0 else (nodes - 1) / 2
  for _ in [:steps] do e := mkApp (mkConst ``Nat.succ) e
  pure <| if nodes % 2 == 0 then mkMData MData.empty e else e

private def emptyArray (type : Expr) : Expr :=
  mkApp2 (mkConst ``List.toArray) type (mkApp (mkConst ``List.nil) type)

private def singletonArray (type value : Expr) : Expr :=
  mkApp2 (mkConst ``List.toArray) type
    (mkApp3 (mkConst ``List.cons) type value (mkApp (mkConst ``List.nil) type))

private def predicateProgram (predicate : Expr) : Expr := Id.run do
  let invariant := mkApp2 (mkConst ``ProofForgeV2.Source.InvariantDecl.mk)
    (mkStrLit "Depth") predicate
  let empty (name : Name) := emptyArray (mkConst name)
  pure <| mkAppN (mkConst ``ProofForgeV2.Source.Program.mk) #[
    mkStrLit "Depth", mkStrLit "Depth", empty ``ProofForgeV2.Source.StateDecl,
    empty ``ProofForgeV2.Source.StructDecl, empty ``ProofForgeV2.Source.EnumDecl,
    empty ``ProofForgeV2.Source.ConstDecl, empty ``ProofForgeV2.Source.EventDecl,
    empty ``ProofForgeV2.Source.ErrorDecl,
    mkApp (mkConst ``Option.none) (mkConst ``ProofForgeV2.Source.Initializer),
    empty ``ProofForgeV2.Source.Entry, empty ``ProofForgeV2.Source.FnDecl,
    singletonArray (mkConst ``ProofForgeV2.Source.InvariantDecl) invariant,
    empty ``ProofForgeV2.Source.ExtensionReq, empty ``ProofForgeV2.Source.ProofDecl]

private def depthProgram (depth : Nat) : Expr := Id.run do
  let mut predicate := mkApp (mkConst ``ProofForgeV2.Source.Expr.literal)
    (mkApp (mkConst ``UInt64.ofNat) (mkRawNatLit 0))
  for _ in [:depth.pred] do
    predicate := mkApp (mkConst ``ProofForgeV2.Source.Expr.checkedNeg) predicate
  pure (predicateProgram predicate)

private def expect004 (label msg : String) : IO Unit :=
  expect (msg.startsWith "PF-EXPORT-004") s!"{label}: {msg}"

/-- Snapshot constants only; never programPayloads on polluted main env. -/
unsafe def run : IO Unit := do
  expect richPayloadAsserted "rich asserted"
  expect (richPayloadName == RichPayload.name &&
    richPayloadQualifiedName == RichPayload.qualifiedName &&
    richPayloadSourceHash == RichPayload.sourceHash)
    "reconstructed identity must BEq elaborator name/qname/sourceHash"
  expect (richPayloadRows.size == 1) "exactly one positive export row"
  let some row := richPayloadRows[0]? | throw <| IO.userError "no row"
  expect (row.programName == "RichPayload" &&
    row.qualifiedName == RichPayload.qualifiedName &&
    row.sourceHash == RichPayload.sourceHash &&
    row.declaration.endsWith "RichPayload") "positive row"
  expect (RichPayload.state.size ≥ 8 && RichPayload.structs.size ≥ 1 &&
    RichPayload.enums.size ≥ 1 && RichPayload.consts.size ≥ 1 &&
    RichPayload.events.size ≥ 1 && RichPayload.errors.size ≥ 1 &&
    RichPayload.initializer.isSome && RichPayload.entries.size ≥ 2 &&
    RichPayload.functions.size ≥ 1 && RichPayload.invariants.size ≥ 1 &&
    RichPayload.extensionRequirements.size ≥ 1 &&
    RichPayload.proofReferences.size ≥ 1) "elaborator ctor surface"
  expect004 "unreg" NegUnregistered.unregPayloadError
  expect004 "alias" NegConstAlias.aliasPayloadError
  expect004 "table" NegConstAlias.aliasTableError
  expect004 "opaque" NegOpaque.opaquePayloadError
  expect004 "unsafe" NegUnsafe.unsafePayloadError
  expect004 "partial" NegPartial.partialPayloadError
  expect004 "impl" NegImplementedBy.implementedByPayloadError
  let stateExpr := mkApp (mkConst ``ProofForgeV2.Source.Expr.state) (mkStrLit "value")
  match decodeQuotedProgramV1 (predicateProgram stateExpr) with
  | .ok _ => pure ()
  | .error msg => throw <| IO.userError s!"direct state form: {msg}"
  match decodeQuotedProgramV1 (exactNodeExpr 100000) with
  | .ok _ => pure ()
  | .error msg =>
      expect004 "n100000" msg
      expect (!msg.contains "structural bound exceeded") "100000 passes bound"
  match decodeQuotedProgramV1 (exactNodeExpr 100001) with
  | .ok _ => throw <| IO.userError "100001 must fail"
  | .error msg =>
      expect004 "n100001" msg
      expect (msg.contains "structural bound exceeded") "100001 bound"
  match decodeQuotedProgramV1 (depthProgram 256) with
  | .ok _ => pure ()
  | .error msg =>
      expect004 "d256" msg
      expect (!msg.contains "structural bound exceeded") "256 depth ok"
  match decodeQuotedProgramV1 (depthProgram 257) with
  | .ok _ => throw <| IO.userError "257 must fail"
  | .error msg =>
      expect004 "d257" msg
      expect (msg.contains "structural bound exceeded") "257 depth bound"

end Tests.Language.ProgramPayloads
