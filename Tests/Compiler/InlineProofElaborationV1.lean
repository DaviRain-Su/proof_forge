/-
  Focused engineering tests for in-process fixed-import Lean elaboration.
  All cases feed the same in-memory source String API (no file re-read).
  Not a containment or hostile-code sandbox claim.
-/
import ProofForgeV2.Compiler.InlineProofElaborationV1
import ProofForgeV2.Language.Loader

namespace Tests.Compiler.InlineProofElaborationV1

open Lean
open ProofForgeV2.Compiler.InlineProofElaborationV1
open ProofForgeV2.Language.Loader

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectPhase (fault : InlineProofElabFaultV1)
    (expected : InlineProofElabPhaseV1) (label : String) : IO Unit :=
  expect (InlineProofElabFaultV1.phase fault == expected)
    s!"{label}: expected {repr expected}, got {repr (InlineProofElabFaultV1.phase fault)}"

/-- Legal fixed-import ordinary theorem (no axiom/sorry/native_decide). -/
private def successSource : String :=
  "import ProofForgeV2\n\n" ++
  "theorem inlineOk : True := trivial\n"

/-- False proof must fail closed at the commands phase. -/
private def falseProofSource : String :=
  "import ProofForgeV2\n\n" ++
  "theorem inlineBad : False := trivial\n"

/-- Extra import must fail closed at the header gate. -/
private def extraImportSource : String :=
  "import ProofForgeV2\n" ++
  "import Init\n\n" ++
  "theorem inlineOk : True := trivial\n"

/-- Malformed command body must fail closed at the commands phase. -/
private def malformedCommandSource : String :=
  "import ProofForgeV2\n\n" ++
  "theorem inlineBroken : True :=\n"

/-- Compiler-owned subject certificate names cannot be reused as invariant
    aliases in the generated `Proof` namespace. -/
private def reservedRootGateInvariantSource : String :=
  "import ProofForgeV2\n\n" ++
  "program ReservedRootGateInvariant where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant subjectRootGatesOkV1 : true\n" ++
  "  proof subjectRootGatesOkV1 using ReservedRootGateInvariantProof.safe\n"

private def reservedStructureInvariantSource : String :=
  "import ProofForgeV2\n\n" ++
  "program ReservedStructureInvariant where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant subjectStructureOkV1 : true\n" ++
  "  proof subjectStructureOkV1 using ReservedStructureInvariantProof.safe\n"

private def reservedValidationInvariantSource : String :=
  "import ProofForgeV2\n\n" ++
  "program ReservedValidationInvariant where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant subjectValidationOkV1 : true\n" ++
  "  proof subjectValidationOkV1 using ReservedValidationInvariantProof.safe\n"

private unsafe def expectSuccessDecl (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base successSource with
  | .error fault =>
      throw <| IO.userError
        s!"success source failed: {repr (InlineProofElabFaultV1.phase fault)}"
  | .ok carrier =>
      let env := InlineProofElabEnvV1.environment carrier
      expect (env.contains `inlineOk) "success env missing declaration inlineOk"
      expect (not (InlineProofElabEnvV1.messages carrier).hasErrors)
        "success must not retain error messages"

private unsafe def expectFalseProofFails (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base falseProofSource with
  | .ok _ => throw <| IO.userError "false proof unexpectedly succeeded"
  | .error fault => expectPhase fault .commands "false proof"

private unsafe def expectExtraImportFails (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base extraImportSource with
  | .ok _ => throw <| IO.userError "extra import unexpectedly succeeded"
  | .error fault => expectPhase fault .headerGate "extra import"

private unsafe def expectMalformedFails (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base malformedCommandSource with
  | .ok _ => throw <| IO.userError "malformed command unexpectedly succeeded"
  | .error fault => expectPhase fault .commands "malformed command"

private unsafe def expectReservedRootGateInvariantFails
    (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base reservedRootGateInvariantSource with
  | .ok _ =>
      throw <| IO.userError
        "compiler-owned root-gate certificate name unexpectedly accepted"
  | .error fault => expectPhase fault .commands "reserved root-gate invariant"

private unsafe def expectReservedStructureInvariantFails
    (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base reservedStructureInvariantSource with
  | .ok _ =>
      throw <| IO.userError
        "compiler-owned structure certificate name unexpectedly accepted"
  | .error fault => expectPhase fault .commands "reserved structure invariant"

private unsafe def expectReservedValidationInvariantFails
    (base : Environment) : IO Unit := do
  match ← elaborateInlineProofSourceV1 base reservedValidationInvariantSource with
  | .ok _ =>
      throw <| IO.userError
        "compiler-owned validation certificate name unexpectedly accepted"
  | .error fault => expectPhase fault .commands "reserved validation invariant"

/-- Same in-memory String surface for every case (no disk re-read path). -/
unsafe def run : IO Unit := do
  let productSession ← ProductParserSessionV1.create
  let base := ProductParserSessionV1.sessionEnvironment productSession
  expectSuccessDecl base
  expectFalseProofFails base
  expectExtraImportFails base
  expectMalformedFails base
  expectReservedRootGateInvariantFails base
  expectReservedStructureInvariantFails base
  expectReservedValidationInvariantFails base
  IO.println "Tests.Compiler.InlineProofElaborationV1: ok"

end Tests.Compiler.InlineProofElaborationV1
