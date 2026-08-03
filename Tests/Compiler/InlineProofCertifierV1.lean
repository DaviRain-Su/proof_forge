/-
  Focused integration tests for product InlineProofCertifierV1.

  Coverage:
    * no-proof programs return explicit `noProof` (never forged success)
    * structurally legal but false theorem → elaboration failure
    * wrong subject bytes (mixed compile carrier) → subject failure
    * forged empty inventory with proof items → obligation failure (not noProof)
    * product-invariant positive remains open: exact bridge still lacks a
      general `InvariantTheoremV1` authoring theorem. Controlled `True`
      theorem orchestration is covered by InlineProofElaborationV1 /
      InlineProofAuditV1 only — **not** product invariant certification.

  Fixture programs use Counter-shaped UInt64 state + Bool invariant (stable
  product surface for certifier obligation/subject identity negatives).
  Bool-only view+invariant proof-subject mint is covered by
  Tests.Semantic.ProofSubjectV1 (anonymous Bool + envelope UInt64 TypeId join).

  No axiom / sorry / native_decide. No CLI. No file re-read by the certifier.
-/
import ProofForgeV2.Compiler.InlineProofCertifierV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.TheoremInventoryV1
import Tests.Language.ParserSession

namespace Tests.Compiler.InlineProofCertifierV1

open ProofForgeV2.Compiler
open ProofForgeV2.Compiler.InlineProofCertifierV1
open ProofForgeV2.Compiler.InlineProofProtocolV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOutcome
    (label : String)
    (outcome : InlineProofCertifierOutcomeV1)
    (pred : InlineProofCertifierOutcomeV1 → Bool) : IO Unit :=
  unless pred outcome do
    throw <| IO.userError s!"{label}: unexpected outcome {repr outcome}"

private def header : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n"

/-- UInt64 Counter surface (proven subject mint) without proofs. -/
private def bareProgram : String :=
  header ++
  "program Bare where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- Counter + invariant + adjacent theorem (allowlisted tactics only). -/
private def proofProgram (programName theoremName theoremBody : String) : String :=
  header ++
  "program " ++ programName ++ " where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ theoremName ++ "\n" ++
  theoremBody

/-- Allowlisted `rfl` cannot close `InvariantTheoremV1` — inventory admits
    the syntax; kernel elaboration fails closed. -/
private def falseTheoremBody (theoremName typeName : String) : String :=
  "theorem " ++ theoremName ++ " : " ++ typeName ++ " := by\n" ++
  "  rfl\n"

private def parsePath (s : String) : IO ProjectRelativePath :=
  match parseProjectRelativePath s with
  | .ok p => pure p
  | .error e => throw <| IO.userError s!"path: {e}"

private unsafe def loadProduct
    (session : ParserSession) (src fileName moduleName : String)
    (requested : Option String := none) :
    IO (ValidatedSourceV1 ×
        ProofForgeV2.Source.OriginJoinV1.OriginInventoryV1 ×
        TheoremInventoryV1) := do
  match ← session.selectProgramV1ProductWithTheoremInventory
      src fileName moduleName requested with
  | .ok triple => pure triple
  | .error err =>
      throw <| IO.userError
        s!"load {fileName}: {DiagnosticBundleV1.renderHuman err}"

private unsafe def compileOf
    (source : ValidatedSourceV1)
    (origin : ProofForgeV2.Source.OriginJoinV1.OriginInventoryV1) :
    IO CompiledSemanticV1 :=
  match compileProgramProductV1 source origin with
  | .ok c => pure c
  | .error bundle =>
      throw <| IO.userError
        s!"product compile failed: {DiagnosticBundleV1.renderHuman bundle}"

/-- No proof items: certifier must return explicit `noProof`, never success. -/
private unsafe def testNoProofBypass (session : ParserSession) : IO Unit := do
  let path ← parsePath "tests/inline-proof/bare.pf"
  let (source, origin, thmInv) ← loadProduct session bareProgram
      "tests/inline-proof/bare.pf" "Root"
  expect (theoremInventoryBindingsV1 thmInv).isEmpty "bare inventory empty"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 bareProgram source origin thmInv compiled
      path "Root" none
  expectOutcome "noProof" outcome fun
    | .noProof => true
    | _ => false

/-- Structurally legal inventory + false theorem body fails at elaboration. -/
private unsafe def testFalseTheoremElab (session : ParserSession) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/false.pf"
  let (source, origin, thmInv) ← loadProduct session src
      "tests/inline-proof/false.pf" "Root"
  expect ((theoremInventoryBindingsV1 thmInv).size == 1) "false binding count"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 src source origin thmInv compiled
      path "Root" none
  expectOutcome "false theorem" outcome fun
    | .failed phase detail =>
        phase == .certification && detail == .elaborate
    | _ => false

/-- Mix compiled carrier from another program → subject identity fails closed. -/
private unsafe def testWrongSubjectBytes (session : ParserSession) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let other := proofProgram "Other" "OtherProof.safe"
      (falseTheoremBody "OtherProof.safe" "Other.Proof.safe")
  let path ← parsePath "tests/inline-proof/mixed.pf"
  let (source, origin, thmInv) ← loadProduct session src
      "tests/inline-proof/mixed.pf" "Root"
  let (otherSource, otherOrigin, _) ← loadProduct session other
      "tests/inline-proof/other.pf" "Root"
  let otherCompiled ← compileOf otherSource otherOrigin
  let outcome ← certifyInlineProofV1 src source origin thmInv otherCompiled
      path "Root" none
  expectOutcome "wrong subject" outcome fun
    | .failed phase detail =>
        (phase == .subject &&
          (detail == .subjectBuild || detail == .subjectBytes ||
            detail == .missingSubjectDecl)) ||
        (phase == .certification && detail == .elaborate)
    | _ => false

/-- Empty inventory with proof items still present (forged empty inventory)
    must not skip as noProof. -/
private unsafe def testEmptyInventoryWithProofs (session : ParserSession) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/forged-empty.pf"
  let (source, origin, _) ← loadProduct session src
      "tests/inline-proof/forged-empty.pf" "Root"
  let compiled ← compileOf source origin
  let forgedEmpty := emptyTheoremInventoryV1
  let outcome ← certifyInlineProofV1 src source origin forgedEmpty compiled
      path "Root" none
  expectOutcome "forged empty inventory" outcome fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false

/-- Dual-invariant program with two proofs; forged partial inventory (one of two
    bindings) must fail closed at obligation bijection — not noProof/certified. -/
private unsafe def testForgedPartialDualInvariant (session : ParserSession) : IO Unit := do
  let src :=
    header ++
    "program Dual where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry increment(delta : UInt64) : UInt64 do\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n" ++
    "  invariant first : true\n" ++
    "  invariant second : true\n" ++
    "  proof first using DualProof.first\n" ++
    "  proof second using DualProof.second\n" ++
    falseTheoremBody "DualProof.first" "Dual.Proof.first" ++
    falseTheoremBody "DualProof.second" "Dual.Proof.second"
  let path ← parsePath "tests/inline-proof/dual-partial.pf"
  let (source, origin, fullInv) ← loadProduct session src
      "tests/inline-proof/dual-partial.pf" "Root"
  let fullBindings := theoremInventoryBindingsV1 fullInv
  expect (fullBindings.size == 2) "dual full binding count"
  let compiled ← compileOf source origin
  -- Forged partial: keep only the first binding.
  let partialInv := mintTheoremInventoryV1 #[fullBindings[0]!]
  let outcomePartial ← certifyInlineProofV1 src source origin partialInv compiled
      path "Root" none
  expectOutcome "forged partial dual" outcomePartial fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false
  -- Forged reordered: swap the two bindings.
  let reorderedInv :=
    mintTheoremInventoryV1 #[fullBindings[1]!, fullBindings[0]!]
  let outcomeReorder ← certifyInlineProofV1 src source origin reorderedInv compiled
      path "Root" none
  expectOutcome "forged reorder dual" outcomeReorder fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false
  -- Forged extra on bare program (no proofs expected).
  let extraOnBare := mintTheoremInventoryV1 #[fullBindings[0]!]
  let pathBare ← parsePath "tests/inline-proof/bare-extra.pf"
  let (bareSrc, bareOrigin, _) ← loadProduct session bareProgram
      "tests/inline-proof/bare-extra.pf" "Root"
  let bareCompiled ← compileOf bareSrc bareOrigin
  let outcomeExtra ← certifyInlineProofV1 bareProgram bareSrc bareOrigin extraOnBare
      bareCompiled pathBare "Root" none
  expectOutcome "forged extra on bare" outcomeExtra fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false

/-- Protocol success mint is not a product capability: only the private carrier
    from `certifyInlineProofV1` is accepted. Runtime checks that noProof/fail
    paths never yield certified. -/
private unsafe def testNoForgedSuccess (session : ParserSession) : IO Unit := do
  let path ← parsePath "tests/inline-proof/no-forge.pf"
  let (source, origin, thmInv) ← loadProduct session bareProgram
      "tests/inline-proof/no-forge.pf" "Root"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 bareProgram source origin thmInv compiled
      path "Root" none
  match outcome with
  | .certified _ =>
      throw <| IO.userError "noProof path must not mint CertifiedInlineProofV1"
  | .noProof => pure ()
  | .failed _ _ =>
      throw <| IO.userError "bare program must be noProof, not failure"

/-- Note (open gap): product-invariant positive certification requires a kernel-
    checked theorem of type `Program.Proof.<inv>` (`InvariantTheoremV1`).
    The parametric bridge does not yet ship a general authoring theorem for
    arbitrary Normalize carriers. Controlled `True` theorems exercise
    elaboration/audit orchestration in sibling suites only — **not** product
    invariant positive. Prefer bridge-lane theorems when available. -/
private def documentOpenGaps : IO Unit :=
  pure ()

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testNoProofBypass session
  testFalseTheoremElab session
  testWrongSubjectBytes session
  testEmptyInventoryWithProofs session
  testForgedPartialDualInvariant session
  testNoForgedSuccess session
  documentOpenGaps
  IO.println "Tests.Compiler.InlineProofCertifierV1: ok"
  IO.println
    "  note: product invariant-theorem positive still open (bridge authoring gap);"
  IO.println
    "  True-theorem orchestration remains in Elaboration/Audit suites only."

end Tests.Compiler.InlineProofCertifierV1
