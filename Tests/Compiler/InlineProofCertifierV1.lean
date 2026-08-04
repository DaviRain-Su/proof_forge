/-
  Focused integration tests for product InlineProofCertifierV1.

  Coverage:
    * no-proof programs return explicit `noProof` (never forged success)
    * structurally legal but false theorem → elaboration failure
    * wrong subject bytes (mixed compile carrier) → subject failure
    * forged empty inventory with proof items → obligation failure (not noProof)
    * dual-invariant forged partial/reorder inventories fail closed
    * raw same-file simple-closure product-positive (strict engineering closure):
        - inventory author theorem is ordinary adjacent `SimpleProof.safe`
        - body `exact <Program>.Proof.generatedSafeV1` (generated
          helper name — never redeclared as the inventory theorem)
        - single Loader snapshot → compileProgramProductV1 → certifyInlineProofV1
        - ProgramV1 canonical AST bytes + sourceHashV1 + compiled source/semantic
          digests independent of adjacent theorem body
        - requires `.certified`, theoremCount=1, present proofCertificationDigest
        - alternate allowlisted body (`apply` vs `exact` on the same helper)
          keeps ProgramV1/source/semantic identity equal and **must** change
          proofCertificationDigest (raw source is in the certification request)
      Hard-fails on missing `.certified` (no soft skip / EXPECTED-RED).
      Never uses Tests.Semantic.ProofedClosedCertV1 or hand-minted carriers.

  Fixture programs:
    * Counter-shaped UInt64 + Bool invariant for certifier negatives
    * Literal-true simple-closure (Bool view + `invariant … : true`) for positive

  No axiom / sorry / native_decide. No CLI. No file re-read by the certifier.
-/
import ProofForgeV2.Compiler.InlineProofCertifierV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.TheoremInventoryV1
import ProofForgeV2.Source.ValidatedSourceV1

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

/-- Literal-true simple-closure family. Inventory author theorem is ordinary
    adjacent `SimpleProof.safe` (not the generated helper name). The body
    `exact`s compiler-generated helper `<Program>.Proof.generatedSafeV1`. -/
private def simpleClosureProgram
    (programName authorTheorem theoremBody : String) : String :=
  header ++
  "program " ++ programName ++ " where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ authorTheorem ++ "\n" ++
  theoremBody

/-- Same family inside an explicit namespace. This covers the elaborator case
    where the source namespace begins with the exact product module name and
    generated declarations therefore use the full ProgramV1 identity. -/
private def simpleClosureProgramInNamespace
    (namespaceName programName authorTheorem theoremBody : String) : String :=
  header ++
  "namespace " ++ namespaceName ++ "\n" ++
  "program " ++ programName ++ " where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ authorTheorem ++ "\n" ++
  theoremBody ++
  "end " ++ namespaceName ++ "\n"

/-- Primary author body: exact the compiler-generated helper (allowlisted). -/
private def simpleClosureAuthorBodyExact
    (authorTheorem programName : String) : String :=
  "theorem " ++ authorTheorem ++ " : " ++ programName ++
    ".Proof.safe := by\n" ++
  "  exact " ++ programName ++ ".Proof.generatedSafeV1\n"

/-- Alternate allowlisted body with distinct raw source (not comment-only).
    `simpa` / `simp only [lemma]` emit disallowed simpLemma syntax; use `apply`. -/
private def simpleClosureAuthorBodyApply
    (authorTheorem programName : String) : String :=
  "theorem " ++ authorTheorem ++ " : " ++ programName ++
    ".Proof.safe := by\n" ++
  "  apply " ++ programName ++ ".Proof.generatedSafeV1\n"

private def parsePath (s : String) : IO ProjectRelativePath :=
  match parseProjectRelativePath s with
  | .ok p => pure p
  | .error e => throw <| IO.userError s!"path: {e}"

private unsafe def loadProduct
    (session : ProductParserSessionV1) (src fileName moduleName : String)
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

/-- Product digests are fixed-width SHA-256; "nonempty" means a real 32-byte
    wire value is present (not Option.none / empty). -/
private def digestPresent (d : Digest) : Bool :=
  d.bytes.size == 32

/-- No proof items: certifier must return explicit `noProof`, never success. -/
private unsafe def testNoProofBypass (session : ProductParserSessionV1) : IO Unit := do
  let path ← parsePath "tests/inline-proof/bare.pf"
  let (source, origin, thmInv) ← loadProduct session bareProgram
      "tests/inline-proof/bare.pf" "Root"
  expect (theoremInventoryBindingsV1 thmInv).isEmpty "bare inventory empty"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session bareProgram source origin thmInv compiled
      path "Root" none
  expectOutcome "noProof" outcome fun
    | .noProof => true
    | _ => false

/-- Structurally legal inventory + false theorem body fails at elaboration. -/
private unsafe def testFalseTheoremElab (session : ProductParserSessionV1) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/false.pf"
  let (source, origin, thmInv) ← loadProduct session src
      "tests/inline-proof/false.pf" "Root"
  expect ((theoremInventoryBindingsV1 thmInv).size == 1) "false binding count"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin thmInv compiled
      path "Root" none
  expectOutcome "false theorem" outcome fun
    | .failed phase detail =>
        phase == .certification && detail == .elaborate
    | _ => false

/-- Trusted package module roots cannot be reused as the user main-module
    identity. Rejection happens before command elaboration/audit. -/
private unsafe def testForbiddenMainModule
    (session : ProductParserSessionV1) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/forbidden-module.pf"
  let (source, origin, thmInv) ← loadProduct session src
      "tests/inline-proof/forbidden-module.pf" "ProofForgeV2"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin thmInv compiled
      path "ProofForgeV2" none
  expectOutcome "forbidden main module" outcome fun
    | .failed phase detail =>
        phase == .certification && detail == .elaborate
    | _ => false

/-- Mix compiled carrier from another program → subject identity fails closed. -/
private unsafe def testWrongSubjectBytes (session : ProductParserSessionV1) : IO Unit := do
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
  let outcome ← certifyInlineProofV1 session src source origin thmInv otherCompiled
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
private unsafe def testEmptyInventoryWithProofs (session : ProductParserSessionV1) : IO Unit := do
  let src := proofProgram "Proofed" "ProofedProof.safe"
      (falseTheoremBody "ProofedProof.safe" "Proofed.Proof.safe")
  let path ← parsePath "tests/inline-proof/forged-empty.pf"
  let (source, origin, _) ← loadProduct session src
      "tests/inline-proof/forged-empty.pf" "Root"
  let compiled ← compileOf source origin
  let forgedEmpty := emptyTheoremInventoryV1
  let outcome ← certifyInlineProofV1 session src source origin forgedEmpty compiled
      path "Root" none
  expectOutcome "forged empty inventory" outcome fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false

/-- Dual-invariant program with two proofs; forged partial inventory (one of two
    bindings) must fail closed at obligation bijection — not noProof/certified. -/
private unsafe def testForgedPartialDualInvariant (session : ProductParserSessionV1) : IO Unit := do
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
  let outcomePartial ← certifyInlineProofV1 session src source origin partialInv compiled
      path "Root" none
  expectOutcome "forged partial dual" outcomePartial fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false
  -- Forged reordered: swap the two bindings.
  let reorderedInv :=
    mintTheoremInventoryV1 #[fullBindings[1]!, fullBindings[0]!]
  let outcomeReorder ← certifyInlineProofV1 session src source origin reorderedInv compiled
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
  let outcomeExtra ← certifyInlineProofV1 session bareProgram bareSrc bareOrigin extraOnBare
      bareCompiled pathBare "Root" none
  expectOutcome "forged extra on bare" outcomeExtra fun
    | .failed phase detail =>
        phase == .obligation && detail == .obligationMap
    | .noProof => false
    | .certified _ => false

/-- Protocol success mint is not a product capability: only the private carrier
    from `certifyInlineProofV1` is accepted. Runtime checks that noProof/fail
    paths never yield certified. -/
private unsafe def testNoForgedSuccess (session : ProductParserSessionV1) : IO Unit := do
  let path ← parsePath "tests/inline-proof/no-forge.pf"
  let (source, origin, thmInv) ← loadProduct session bareProgram
      "tests/inline-proof/no-forge.pf" "Root"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session bareProgram source origin thmInv compiled
      path "Root" none
  match outcome with
  | .certified _ =>
      throw <| IO.userError "noProof path must not mint CertifiedInlineProofV1"
  | .noProof => pure ()
  | .failed _ _ =>
      throw <| IO.userError "bare program must be noProof, not failure"

/-- Assert full certified observation on a private certifier carrier. -/
private def expectCertifiedCarrier
    (label : String) (c : CertifiedInlineProofV1) : IO Unit := do
  expect (CertifiedInlineProofV1.theoremCount c == 1)
    s!"{label}: theoremCount must be 1, got {CertifiedInlineProofV1.theoremCount c}"
  expect (digestPresent (CertifiedInlineProofV1.proofCertificationDigest c))
    s!"{label}: proofCertificationDigest must be present (32-byte)"
  expect (digestPresent (CertifiedInlineProofV1.requestDigest c))
    s!"{label}: requestDigest must be present (32-byte)"
  expect ((CertifiedInlineProofV1.audited c).size == 1)
    s!"{label}: audited theorem set size must be 1"

/-- (1) Loader → compile → certify simple-closure with ordinary author theorem
    that `exact`s compiler-generated helper `Simple.Proof.generatedSafeV1`.
    (3) Alternate allowlisted body keeps source/semantic digests and **must**
    change proofCertificationDigest (request binds raw source).
    Hard-fails unless both outcomes are `.certified`. Never hand-mints carriers. -/
private unsafe def testSimpleClosureProductPositive
    (session : ProductParserSessionV1) : IO Unit := do
  let programName := "Simple"
  let authorTheorem := "SimpleProof.safe"
  let bodyA := simpleClosureAuthorBodyExact authorTheorem programName
  let bodyB := simpleClosureAuthorBodyApply authorTheorem programName
  let srcA := simpleClosureProgram programName authorTheorem bodyA
  let srcB := simpleClosureProgram programName authorTheorem bodyB
  expect (srcA != srcB) "theorem-body rewrite must change raw source"
  let pathA ← parsePath "tests/inline-proof/simple-closure-a.pf"
  let pathB ← parsePath "tests/inline-proof/simple-closure-b.pf"
  let (sourceA, originA, thmInvA) ← loadProduct session srcA
      "tests/inline-proof/simple-closure-a.pf" "Root"
  let (sourceB, originB, thmInvB) ← loadProduct session srcB
      "tests/inline-proof/simple-closure-b.pf" "Root"
  -- Inventory: ordinary adjacent author theorem + Prop alias type components.
  let bindingsA := theoremInventoryBindingsV1 thmInvA
  expect (bindingsA.size == 1) "simple-closure inventory size"
  let b0 := bindingsA[0]!
  expect (b0.invariantName == "safe") "simple-closure invariant name"
  expect (b0.theoremComponents == #["SimpleProof", "safe"])
    s!"author theorem components: {b0.theoremComponents}"
  expect (b0.typeComponents == #[programName, "Proof", "safe"])
    s!"type components: {b0.typeComponents}"
  -- Author theorem must not collide with generated helper name components.
  expect (b0.theoremComponents !=
      #[programName, "Proof", "generatedSafeV1"])
    "inventory author theorem must not redeclare generated helper name"
  expect ((theoremInventoryBindingsV1 thmInvB).size == 1)
    "alt body inventory size"
  -- Product compile (structure-gated Normalize) for both sources.
  let compiledA ← compileOf sourceA originA
  let compiledB ← compileOf sourceB originB
  let srcDigA := CompiledSemanticV1.sourceDigestOf compiledA
  let srcDigB := CompiledSemanticV1.sourceDigestOf compiledB
  let semDigA := CompiledSemanticV1.semanticDigestOf compiledA
  let semDigB := CompiledSemanticV1.semanticDigestOf compiledB
  -- (3 partial) ProgramV1 / semantic identity ignore adjacent theorem body.
  -- Explicit ProgramV1 canonical AST bytes (not only their sourceHash digest).
  let canA ← match canonicalValidatedSourceAstBytesV1 sourceA with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"canonical A: {e}"
  let canB ← match canonicalValidatedSourceAstBytesV1 sourceB with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"canonical B: {e}"
  expect (canA == canB)
    "ProgramV1 canonical AST bytes must be independent of adjacent theorem body"
  let hashA ← match sourceHashV1 sourceA with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"sourceHash A: {e}"
  let hashB ← match sourceHashV1 sourceB with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"sourceHash B: {e}"
  expect (hashA == hashB)
    "ProgramV1 sourceHashV1 must be independent of adjacent theorem body"
  expect (hashA == srcDigA && hashB == srcDigB)
    "compiled sourceDigest must equal Loader sourceHashV1 (single-snapshot identity)"
  expect (srcDigA == srcDigB)
    "sourceDigest must be independent of adjacent theorem body"
  expect (semDigA == semDigB)
    "semanticDigest must be independent of adjacent theorem body"
  expect ((CompiledSemanticV1.semanticV1Of compiledA).canonicalBytes ==
      (CompiledSemanticV1.semanticV1Of compiledB).canonicalBytes)
    "semantic bytes must match across theorem-body rewrite"
  -- Sole product certifier on held raw source (no re-read, no forge).
  let outcomeA ← certifyInlineProofV1 session srcA sourceA originA thmInvA compiledA
      pathA "Root" none
  let outcomeB ← certifyInlineProofV1 session srcB sourceB originB thmInvB compiledB
      pathB "Root" none
  -- Strict product-positive: require `.certified` on both bodies.
  let cA ← match outcomeA with
    | .certified c => pure c
    | .noProof =>
        throw <| IO.userError
          "simple-closure with proof items must not return noProof"
    | .failed phase detail =>
        throw <| IO.userError
          ("simple-closure product-positive requires .certified; got failed " ++
            s!"phase={repr phase} detail={repr detail} " ++
            "(author SimpleProof.safe exacts generated " ++
            "Simple.Proof.generatedSafeV1)")
  expectCertifiedCarrier "simple-closure-A" cA
  let cB ← match outcomeB with
    | .certified c => pure c
    | .noProof =>
        throw <| IO.userError "alt body must not return noProof"
    | .failed phase detail =>
        throw <| IO.userError
          ("simple-closure alt body requires .certified; got failed " ++
            s!"phase={repr phase} detail={repr detail}")
  expectCertifiedCarrier "simple-closure-B" cB
  -- proofCertificationDigest binds raw source → body rewrite must change it.
  let digA := CertifiedInlineProofV1.proofCertificationDigest cA
  let digB := CertifiedInlineProofV1.proofCertificationDigest cB
  expect (digestPresent digA && digestPresent digB)
    "both certification digests present"
  expect (digA != digB)
    "proofCertificationDigest must change when adjacent theorem body changes"
  IO.println
    "Tests.Compiler.InlineProofCertifierV1: simple-closure product-positive CERTIFIED"

/-- When `namespace Root` matches `--module Root`, Loader's identity remains
    `Root.Scoped` and Lean's actual declaration is also `Root.Scoped`. The
    certifier must select the full-identity candidate (not the root-level
    module-stripped candidate) and still audit the adjacent theorem exactly. -/
private unsafe def testModulePrefixedNamespaceProductPositive
    (session : ProductParserSessionV1) : IO Unit := do
  let programName := "Scoped"
  let authorTheorem := "ScopedProof.safe"
  let body := simpleClosureAuthorBodyExact authorTheorem programName
  let src := simpleClosureProgramInNamespace
    "Root" programName authorTheorem body
  let path ← parsePath "tests/inline-proof/module-prefixed-namespace.pf"
  let (source, origin, inventory) ← loadProduct session src
    "tests/inline-proof/module-prefixed-namespace.pf" "Root"
  let identity :=
    (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
  expect (identity == #["Root", "Scoped"])
    s!"module-prefixed namespace identity: {identity}"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin inventory compiled
    path "Root" none
  match outcome with
  | .certified carrier =>
      expectCertifiedCarrier "module-prefixed-namespace" carrier
  | .noProof =>
      throw <| IO.userError "module-prefixed namespace proof returned noProof"
  | .failed phase detail =>
      throw <| IO.userError
        s!"module-prefixed namespace proof failed phase={repr phase} detail={repr detail}"

/-- A namespace unrelated to `--module Root` uses the relative declaration
    candidate (`Nested.Scoped`) while Loader retains the full product identity
    (`Root.Nested.Scoped`). This pins multi-component author theorem lookup. -/
private unsafe def testRelativeNestedNamespaceProductPositive
    (session : ProductParserSessionV1) : IO Unit := do
  let programName := "NestedScoped"
  let authorTheorem := "NestedScopedProof.safe"
  let body := simpleClosureAuthorBodyExact authorTheorem programName
  let src := simpleClosureProgramInNamespace
    "Nested" programName authorTheorem body
  let path ← parsePath "tests/inline-proof/relative-nested-namespace.pf"
  let (source, origin, inventory) ← loadProduct session src
    "tests/inline-proof/relative-nested-namespace.pf" "Root"
  let identity :=
    (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
  expect (identity == #["Root", "Nested", "NestedScoped"])
    s!"relative nested namespace identity: {identity}"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin inventory compiled
    path "Root" none
  match outcome with
  | .certified carrier =>
      expectCertifiedCarrier "relative-nested-namespace" carrier
  | .noProof =>
      throw <| IO.userError "relative nested namespace proof returned noProof"
  | .failed phase detail =>
      throw <| IO.userError
        s!"relative nested namespace proof failed phase={repr phase} detail={repr detail}"

unsafe def run : IO Unit := do
  let session ← ProductParserSessionV1.create
  testNoProofBypass session
  testFalseTheoremElab session
  testForbiddenMainModule session
  testWrongSubjectBytes session
  testEmptyInventoryWithProofs session
  testForgedPartialDualInvariant session
  testNoForgedSuccess session
  testSimpleClosureProductPositive session
  testModulePrefixedNamespaceProductPositive session
  testRelativeNestedNamespaceProductPositive session
  IO.println "Tests.Compiler.InlineProofCertifierV1: ok"

end Tests.Compiler.InlineProofCertifierV1
