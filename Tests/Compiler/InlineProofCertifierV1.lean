/-
  Focused integration tests for product InlineProofCertifierV1.

  Coverage:
    * no-proof programs return explicit `noProof` (never forged success)
    * structurally legal but false theorem → elaboration failure
    * wrong subject bytes (mixed compile carrier) → subject failure
    * forged empty inventory with proof items → obligation failure (not noProof)
    * dual-invariant forged partial/reorder inventories fail closed
    * proof-kind source/semantic identity boundary
    * dual-kind missing/reordered/kind-forged inventories fail closed
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
    * UInt64 + Bool invariant surfaces for certifier negatives
    * Literal-true simple-closure (Bool view + `invariant … : true`) for holds positive
    * Real same-file `Examples/Counter.lean` for preserving product-positive
      (no closed golden / pin / contract-specific module)

  No axiom / sorry / native_decide. No CLI. No file re-read by the certifier.
-/
import ProofForgeV2.Compiler.InlineProofCertifierV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Language.TheoremInventoryV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Near

namespace Tests.Compiler.InlineProofCertifierV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Compiler.InlineProofCertifierV1
open ProofForgeV2.Compiler.InlineProofProtocolV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Near

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

/-- Preserve the successful equation when an integration test must instantiate
    a proposition-only graph theorem for the exact production result. -/
private def liftResultWithProof (result : CompileResult α) :
    IO { value : α // result = .ok value } :=
  match result with
  | .ok value => pure ⟨value, rfl⟩
  | .error error => throw <| IO.userError error.render

/-- Preserve an exact successful optional lookup without using unchecked array
    indexing in production-provenance fixtures. -/
private def liftOptionWithProof (result : Option α) (message : String) :
    IO { value : α // result = some value } :=
  match result with
  | some value => pure ⟨value, rfl⟩
  | none => throw <| IO.userError message

private theorem stateDeclV1_eq_of_fields
    (decl : StateDeclV1)
    (hid : decl.id = 0)
    (hname : decl.name = "reserves")
    (htype : decl.typeId = 0)
    (hvisibility : decl.visibility = .public_) :
    decl = {
      id := 0
      name := "reserves"
      typeId := 0
      visibility := .public_
    } := by
  cases decl
  simp_all

private theorem typeDeclV1_eq_uint64_of_fields
    (decl : TypeDeclV1)
    (hid : decl.id = 0)
    (hname : decl.name = none)
    (hshape : decl.shape = .uint 64) :
    decl = {
      id := 0
      name := none
      shape := .uint 64
    } := by
  cases decl
  simp_all

private theorem storageField_eq_reserves_of_fields
    (field : StorageField)
    (key : String)
    (hsource : field.sourceId = 0)
    (hname : field.name = "reserves")
    (hkey : field.key = key)
    (hwidth : field.byteWidth = 8)
    (hendianness : field.endianness = .little) :
    field = {
      sourceId := 0
      name := "reserves"
      key := key
      byteWidth := 8
      endianness := .little
    } := by
  cases field
  simp_all

private theorem nearEndianness_eq_little (endianness : Endianness) :
    endianness = .little := by
  cases endianness
  rfl

private def productionReservesBinding (physicalKey : String) :
    UInt64StateBindingV1 := {
  semanticStateId := 0
  semanticTypeId := 0
  semanticName := "reserves"
  physicalFieldIndex := 0
  physicalKey
}

/-- Turn public scalar/lookup checks on the dynamically decoded production
    values into the exact proposition consumed by static alignment. -/
private def checkProductionReservesBinding
    (data : SemanticProgramDataV1)
    (storage : StorageLayout)
    (physicalKey : String) :
    IO (Subtype fun _ : Unit =>
      UInt64StateBindingRelV1 data storage
        (productionReservesBinding physicalKey)) := do
  match hstate : data.logicalState[0]? with
  | none =>
      throw <| IO.userError
        "VerifiedVaultPF production semantic data is missing state 0"
  | some stateDecl =>
      if hstateFields :
          stateDecl.id = 0 ∧ stateDecl.name = "reserves" ∧
          stateDecl.typeId = 0 ∧ stateDecl.visibility = .public_ then
        match htype : data.types[0]? with
        | none =>
            throw <| IO.userError
              "VerifiedVaultPF production semantic data is missing type 0"
        | some typeDecl =>
            match hshape : typeDecl.shape with
            | .uint width =>
                if htypeFields :
                    typeDecl.id = 0 ∧ typeDecl.name = none ∧ width = 64 then
                  match hleaves : storage.stateLeaves[0]? with
                  | none =>
                      throw <| IO.userError
                        "VerifiedVaultPF production storage is missing state leaves 0"
                  | some leaves =>
                      if hleavesExact : leaves = #[0] then
                        match hfield : storage.fields[0]? with
                        | none =>
                            throw <| IO.userError
                              "VerifiedVaultPF production storage is missing field 0"
                        | some field =>
                            if hfieldFields :
                                field.sourceId = 0 ∧
                                field.name = "reserves" ∧
                                field.key = physicalKey ∧
                                field.byteWidth = 8 then
                              have hstateExact := stateDeclV1_eq_of_fields stateDecl
                                hstateFields.1 hstateFields.2.1
                                hstateFields.2.2.1 hstateFields.2.2.2
                              have hshapeExact : typeDecl.shape = .uint 64 := by
                                rw [hshape, htypeFields.2.2]
                              have htypeExact := typeDeclV1_eq_uint64_of_fields
                                typeDecl htypeFields.1 htypeFields.2.1 hshapeExact
                              have hendianness :
                                  StorageField.endianness field = .little :=
                                nearEndianness_eq_little
                                  (StorageField.endianness field)
                              have hfieldExact := storageField_eq_reserves_of_fields
                                field physicalKey hfieldFields.1
                                hfieldFields.2.1 hfieldFields.2.2.1
                                hfieldFields.2.2.2 hendianness
                              pure ⟨(), by
                                refine ⟨?_, ?_, ?_, ?_⟩
                                · exact hstate.trans (congrArg some hstateExact)
                                · exact htype.trans (congrArg some htypeExact)
                                · exact hleaves.trans (congrArg some hleavesExact)
                                · exact hfield.trans (congrArg some hfieldExact)
                              ⟩
                            else
                                throw <| IO.userError
                                  "VerifiedVaultPF production reserves field is not canonical"
                      else
                        throw <| IO.userError
                          "VerifiedVaultPF production reserves leaves are not singleton field 0"
                else
                  throw <| IO.userError
                    "VerifiedVaultPF production type 0 is not canonical UInt64"
            | _ =>
                throw <| IO.userError
                  "VerifiedVaultPF production type 0 is not UInt64"
      else
        throw <| IO.userError
          "VerifiedVaultPF production state 0 is not public UInt64 reserves"

private def expectNearPlanRejected
    (label : String) (plan : ProofForgeV2.Targets.Near.Plan) : IO Unit :=
  match ProofForgeV2.Targets.Near.validatePlan plan with
  | .error (.planInvariant .near _) => pure ()
  | .error error =>
      throw <| IO.userError s!"{label}: wrong failure: {error.render}"
  | .ok () =>
      throw <| IO.userError s!"{label}: malformed NEAR Plan was accepted"

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

/-- Literal-true simple-closure with an explicit preservation obligation.
    No compiler-generated holds helper is emitted for this kind. -/
private def preservingSimpleClosureProgram
    (programName authorTheorem theoremBody : String) : String :=
  header ++
  "program " ++ programName ++ " where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant safe : true\n" ++
  "  proof safe preserving using " ++ authorTheorem ++ "\n" ++
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
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    ProofForgeV2.Targets.resolveEngineeringRequirementsV1 selection compiled
  expect (ProofForgeV2.Targets.ResolvedEngineeringBuildV1.nearInvariantErasureAuthorization?
      capability |>.isNone)
    "no-invariant program must not carry NEAR invariant-erasure authorization"

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

/-- Preserving aliases are audited against `PreservationTheoremV1` and do not
    require the holds-only simple-closure helper. The structurally accepted `rfl`
    body still cannot prove preservation, so failure must reach elaboration. -/
private unsafe def testPreservingFalseTheoremElab
    (session : ProductParserSessionV1) : IO Unit := do
  let src := preservingSimpleClosureProgram "PreservingFalse" "PreservingFalseProof.safe"
    (falseTheoremBody "PreservingFalseProof.safe"
      "PreservingFalse.ProofPreserving.safe")
  let path ← parsePath "tests/inline-proof/preserving-false.pf"
  let (source, origin, inventory) ← loadProduct session src
    "tests/inline-proof/preserving-false.pf" "Root"
  let bindings := theoremInventoryBindingsV1 inventory
  expect (bindings.size == 1 && bindings[0]!.kind == .preserving)
    "preserving false binding"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin inventory compiled
    path "Root" none
  expectOutcome "preserving false theorem" outcome fun
    | .failed phase detail =>
        phase == .certification && detail == .elaborate
    | _ => false

/-- Strict product-positive for the sole same-file preserving example.
    Reads the real `Examples/Counter.lean` authority: business program +
    invariant + proof binding + ordinary Lean theorem in one file. Uses only
    contract-agnostic generated subject surface and generic shape lemmas; no
    closed byte golden, pin, or contract-specific preservation module. -/
private unsafe def testSameFileCounterPreservingProductPositive
    (session : ProductParserSessionV1) : IO Unit := do
  let src ← IO.FS.readFile "Examples/Counter.lean"
  let path ← parsePath "Examples/Counter.lean"
  let (source, origin, inventory) ← loadProduct session src
    "Examples/Counter.lean" "Examples.Counter"
  let bindings := theoremInventoryBindingsV1 inventory
  expect (bindings.size == 1) "Counter preserving inventory size"
  let binding := bindings[0]!
  expect (binding.invariantName == "even" && binding.kind == .preserving)
    "Counter preserving composite key"
  expect (binding.theoremComponents == #["CounterProof", "even"])
    s!"Counter author theorem components: {binding.theoremComponents}"
  expect (binding.typeComponents == #["Counter", "ProofPreserving", "even"])
    s!"Counter preserving alias components: {binding.typeComponents}"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin inventory compiled
    path "Examples.Counter" none
  match outcome with
  | .certified carrier =>
      expect (CertifiedInlineProofV1.theoremCount carrier == 1)
        "Counter preserving theoremCount must be 1"
      expect (digestPresent (CertifiedInlineProofV1.proofCertificationDigest carrier))
        "Counter preserving certification digest must be present"
      expect ((CertifiedInlineProofV1.audited carrier).size == 1)
        "Counter preserving audited theorem set must contain one theorem"
  | .noProof =>
      throw <| IO.userError
        "Counter preserving proof surface must not return noProof"
  | .failed phase detail =>
      throw <| IO.userError
        s!"Counter preserving product-positive requires .certified; got phase={repr phase} detail={repr detail}"

/-- Strict product certification of the shipped state-changing equality family. -/
private unsafe def testSameFileStatefulEqualityPreservingProductPositive
    (session : ProductParserSessionV1) : IO Unit := do
  let src ← IO.FS.readFile "Examples/StatefulEquality.lean"
  let path ← parsePath "Examples/StatefulEquality.lean"
  let (source, origin, inventory) ← loadProduct session src
    "Examples/StatefulEquality.lean" "Examples.StatefulEquality"
  let bindings := theoremInventoryBindingsV1 inventory
  expect (bindings.size == 1) "StatefulEquality preserving inventory size"
  let binding := bindings[0]!
  expect (binding.invariantName == "solvent" && binding.kind == .preserving)
    "StatefulEquality preserving composite key"
  expect (binding.theoremComponents == #["StatefulEqualityProof", "solvent"])
    "StatefulEquality author theorem components"
  expect (binding.typeComponents == #["StatefulEquality", "ProofPreserving", "solvent"])
    "StatefulEquality preserving type components"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin inventory compiled
    path "Examples.StatefulEquality" none
  match outcome with
  | .certified carrier =>
      expect (CertifiedInlineProofV1.theoremCount carrier == 1)
        "StatefulEquality theoremCount must be 1"
      expect (digestPresent (CertifiedInlineProofV1.proofCertificationDigest carrier))
        "StatefulEquality certification digest must be present"
      expect ((CertifiedInlineProofV1.audited carrier).size == 1)
        "StatefulEquality audited theorem set must contain one theorem"
  | .noProof => throw <| IO.userError "StatefulEquality proof returned noProof"
  | .failed phase detail =>
      throw <| IO.userError
        s!"StatefulEquality requires .certified; got phase={repr phase} detail={repr detail}"

/-- Strict product certification of the first initializer/view business slice. -/
private unsafe def testSameFileVerifiedVaultPFPreservingProductPositive
    (session : ProductParserSessionV1) : IO Unit := do
  let src ← IO.FS.readFile "Examples/VerifiedVaultPF.lean"
  let path ← parsePath "Examples/VerifiedVaultPF.lean"
  let (source, origin, inventory) ← loadProduct session src
    "Examples/VerifiedVaultPF.lean" "Examples.VerifiedVaultPF"
  let bindings := theoremInventoryBindingsV1 inventory
  expect (bindings.size == 1) "VerifiedVaultPF preserving inventory size"
  let binding := bindings[0]!
  expect (binding.invariantName == "solvent" && binding.kind == .preserving)
    "VerifiedVaultPF preserving composite key"
  expect (binding.theoremComponents == #["VerifiedVaultPFProof", "solvent"])
    "VerifiedVaultPF author theorem components"
  expect (binding.typeComponents == #["VerifiedVaultPF", "ProofPreserving", "solvent"])
    "VerifiedVaultPF preserving type components"
  let compiled ← compileOf source origin
  let outcome ← certifyInlineProofV1 session src source origin inventory compiled
    path "Examples.VerifiedVaultPF" none
  match outcome with
  | .certified carrier =>
      expect (CertifiedInlineProofV1.theoremCount carrier == 1)
        "VerifiedVaultPF theoremCount must be 1"
      expect (digestPresent (CertifiedInlineProofV1.proofCertificationDigest carrier))
        "VerifiedVaultPF certification digest must be present"
      expect ((CertifiedInlineProofV1.audited carrier).size == 1)
        "VerifiedVaultPF audited theorem set must contain one theorem"
      expect (CertifiedInlineProofV1.sourceDigest carrier ==
          CompiledSemanticV1.sourceDigestOf compiled)
        "VerifiedVaultPF certificate must bind the exact source digest"
      expect (CertifiedInlineProofV1.semanticDigest carrier ==
          CompiledSemanticV1.semanticDigestOf compiled)
        "VerifiedVaultPF certificate must bind the exact semantic digest"
      expect (CertifiedInlineProofV1.hasCompletePreservingInvariantCoverage carrier)
        "VerifiedVaultPF certificate must cover every invariant with preserving proof"

      -- A valid private certificate is not transferable to another compiled
      -- subject. The target capability mint rechecks both bound digests.
      let (foreignSource, foreignOrigin, _) ← loadProduct session bareProgram
        "tests/inline-proof/verified-vault-foreign-subject.pf" "Root"
      let foreignCompiled ← compileOf foreignSource foreignOrigin
      let nearSelection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
      let foreignCapability ← liftResult <|
        ProofForgeV2.Targets.resolveEngineeringRequirementsV1
          nearSelection foreignCompiled
      match ProofForgeV2.Targets.authorizeCertifiedNearInvariantErasureV1
          foreignCapability carrier with
      | .error (.registryInvalid _) => pure ()
      | .error error =>
          throw <| IO.userError
            s!"VerifiedVaultPF foreign certificate reuse failed with wrong error: {error.render}"
      | .ok _ =>
          throw <| IO.userError
            "VerifiedVaultPF certificate must not authorize a foreign compiled subject"

      -- The ordinary capability remains fail-closed for nonempty invariants.
      let selection := nearSelection
      let ordinary ← liftResult <|
        ProofForgeV2.Targets.resolveEngineeringRequirementsV1 selection compiled
      match ProofForgeV2.Targets.Near.planFromCapability ordinary with
      | .error (.planInvariant .near _) => pure ()
      | .error error =>
          throw <| IO.userError
            s!"VerifiedVaultPF ordinary NEAR path failed with wrong error: {error.render}"
      | .ok _ =>
          throw <| IO.userError
            "VerifiedVaultPF ordinary NEAR path must not erase invariant roots"

      -- Only the private audited carrier opens the proof-bearing NEAR path.
      let capability ← liftResult <|
        ProofForgeV2.Targets.authorizeCertifiedNearInvariantErasureV1
          ordinary carrier
      let semantic := CompiledSemanticV1.semanticV1Of
        (ProofForgeV2.Targets.ResolvedEngineeringBuildV1.compiledOf capability)
      let semanticDataResult :=
        ProofForgeV2.Semantic.WireV1.validateSemanticProgramV1 semantic
      let semanticDataWithProof : IO {
          value : ProofForgeV2.Semantic.WireV1.SemanticProgramDataV1 //
          semanticDataResult = .ok value
        } :=
        match h : semanticDataResult with
        | .ok value => pure ⟨value, rfl⟩
        | .error _ =>
            throw <| IO.userError
              "VerifiedVaultPF production semantic carrier failed validation"
      let ⟨semanticData, hsemanticData⟩ ← semanticDataWithProof
      let planResult := ProofForgeV2.Targets.Near.planFromCapability capability
      let ⟨plan, hplanResult⟩ ← liftResultWithProof planResult
      expect (plan.initializer.name == "init" &&
          plan.entries.map (·.name) == #["deposit", "withdraw", "status"] &&
          plan.entries.map (·.resultKind) ==
            #[.uint64, .unit, .uint64] && plan.fns.isEmpty)
        "VerifiedVaultPF NEAR Plan must retain only the four business callables"
      let decision ← match plan.invariantErasure? with
        | some value => pure value
        | none =>
            throw <| IO.userError
              "VerifiedVaultPF NEAR Plan is missing invariant-erasure attestation"
      expect (decision.version ==
          ProofForgeV2.Targets.Near.invariantErasurePlanVersionV1 &&
          decision.sourceDigest == CertifiedInlineProofV1.sourceDigest carrier &&
          decision.semanticDigest == CertifiedInlineProofV1.semanticDigest carrier &&
          decision.proofCertificationDigest ==
            CertifiedInlineProofV1.proofCertificationDigest carrier &&
          decision.semanticCallableCount == 5 &&
          decision.retainedInitializerCallableId == 0 &&
          decision.retainedMethodCallableIds == #[1, 2, 3] &&
          decision.retainedPureFnCallableIds.isEmpty &&
          decision.erasedInvariantCallableIds == #[4])
        "VerifiedVaultPF NEAR erasure attestation must be the exact callable partition"
      let digest ← match ProofForgeV2.Targets.Near.engineeringNearPlanDigestV1 plan with
        | .ok value => pure value
        | .error error =>
            throw <| IO.userError s!"VerifiedVaultPF NEAR Plan digest failed: {error}"
      let unerasedDigest ← match ProofForgeV2.Targets.Near.engineeringNearPlanDigestV1
          { plan with invariantErasure? := none } with
        | .ok value => pure value
        | .error error =>
            throw <| IO.userError s!"VerifiedVaultPF unerased NEAR Plan digest failed: {error}"
      expect (digest != unerasedDigest)
        "NEAR Plan digest must distinguish an invariant-erasure decision from none"
      let alteredDecision := {
        decision with
        proofCertificationDigest := CertifiedInlineProofV1.sourceDigest carrier
      }
      let alteredDigest ← match ProofForgeV2.Targets.Near.engineeringNearPlanDigestV1
          { plan with invariantErasure? := some alteredDecision } with
        | .ok value => pure value
        | .error error =>
            throw <| IO.userError s!"VerifiedVaultPF altered NEAR Plan digest failed: {error}"
      expect (digest != alteredDigest)
        "NEAR Plan digest must bind the proof certification digest"

      -- Continue through the same capability-gated production path. The
      -- equations retained above and below instantiate the proposition-only
      -- full-Plan graph; no test Plan, key constructor, lowering, or renderer
      -- is used.
      let irResult := ProofForgeV2.Targets.Near.irFromCapability capability
      let ⟨ir, hirResult⟩ ← liftResultWithProof irResult
      have hplanCapability :
          ProofForgeV2.Targets.Near.planFromCapability capability = .ok plan := by
        simpa [planResult] using hplanResult
      have hirCapability :
          ProofForgeV2.Targets.Near.irFromCapability capability = .ok ir := by
        simpa [irResult] using hirResult
      have hgraphs :=
        ProofForgeV2.Targets.Near.planAndIRFromCapability_eq_ok_graphsV1
          capability plan ir hplanCapability hirCapability
      let filesResult :=
        ProofForgeV2.Targets.Near.buildFromCapability capability
      let ⟨baseFiles, hfilesResult⟩ ← liftResultWithProof filesResult
      have hbuildCapability :
          ProofForgeV2.Targets.Near.buildFromCapability capability =
            .ok baseFiles := by
        simpa [filesResult] using hfilesResult
      have hemissions :
          ProofForgeV2.Targets.Near.IREmissionV1 ir baseFiles := by
        rcases ProofForgeV2.Targets.Near.buildFromCapability_eq_ok_graphsV1
            capability baseFiles hbuildCapability with
          ⟨emittedPlan, emittedIR, _, hemittedIR, hemittedLowering, hemissions⟩
        have hemittedIREq : emittedIR = ir :=
          Except.ok.inj (hemittedIR.symm.trans hirCapability)
        subst emittedIR
        have hemittedPlanEq : emittedPlan = plan :=
          (ProofForgeV2.Targets.Near.planIRLoweringV1_sourcePlan
            emittedPlan ir hemittedLowering).symm.trans hgraphs.1
        subst emittedPlan
        exact hemissions
      have _ : ProofForgeV2.Targets.Near.validateIR ir = .ok () :=
        ProofForgeV2.Targets.Near.irEmissionV1_validateIR
          ir baseFiles hemissions
      let ⟨watFile, hwatFile⟩ ← liftOptionWithProof baseFiles[0]?
        "VerifiedVaultPF production emission is missing its WAT file"
      let ⟨abiFile, habiFile⟩ ← liftOptionWithProof baseFiles[1]?
        "VerifiedVaultPF production emission is missing its ABI file"
      have hbaseSize : baseFiles.size = 2 := by
        rcases ProofForgeV2.Targets.Near.irEmissionV1_output_shape
            ir baseFiles hemissions with ⟨watText, abiJson, hbaseFiles⟩
        simp [hbaseFiles]
      have hwatMediaType :
          OutputFile.mediaType watFile = "application/wasm-text" := by
        rcases ProofForgeV2.Targets.Near.irEmissionV1_output_shape
            ir baseFiles hemissions with ⟨watText, abiJson, hbaseFiles⟩
        rw [hbaseFiles] at hwatFile
        simpa using congrArg (fun file : OutputFile => file.mediaType)
          (Option.some.inj (by simpa using hwatFile)).symm
      have habiMediaType :
          OutputFile.mediaType abiFile = "application/json" := by
        rcases ProofForgeV2.Targets.Near.irEmissionV1_output_shape
            ir baseFiles hemissions with ⟨watText, abiJson, hbaseFiles⟩
        rw [hbaseFiles] at habiFile
        simpa using congrArg (fun file : OutputFile => file.mediaType)
          (Option.some.inj (by simpa using habiFile)).symm
      have hfilesDistinct : watFile ≠ abiFile := by
        intro heq
        have hmedia := congrArg (fun file : OutputFile => file.mediaType) heq
        rw [hwatMediaType, habiMediaType] at hmedia
        simp at hmedia
      expect (baseFiles.size == 2 &&
          watFile.path == "VerifiedVaultPF.wat" &&
          watFile.mediaType == "application/wasm-text" &&
          abiFile.path == "VerifiedVaultPF.near-abi.json" &&
          abiFile.mediaType == "application/json")
        "VerifiedVaultPF production emission must have the exact WAT/ABI envelope"
      have rejectDifferent
          (candidate : Array OutputFile)
          (hne : candidate ≠ baseFiles) :
          ¬ ProofForgeV2.Targets.Near.IREmissionV1 ir candidate := by
        intro hcandidate
        exact hne (ProofForgeV2.Targets.Near.irEmissionV1_unique
          ir candidate baseFiles hcandidate hemissions)
      let forgedMediaFiles : Array OutputFile := #[
        {
          path := s!"{ir.name}.wat"
          mediaType := "text/plain"
          contents := watFile.contents
        },
        {
          path := s!"{ir.name}.near-abi.json"
          mediaType := "application/json"
          contents := abiFile.contents
        }
      ]
      have _ : ¬ ProofForgeV2.Targets.Near.IREmissionV1 ir forgedMediaFiles := by
        apply rejectDifferent
        intro heq
        have hfirst := congrArg (fun files : Array OutputFile => files[0]?) heq
        have hfile : ({
            path := s!"{ir.name}.wat"
            mediaType := "text/plain"
            contents := watFile.contents
          } : OutputFile) = watFile :=
          Option.some.inj (by simpa [forgedMediaFiles, hwatFile] using hfirst)
        have hmedia := congrArg (fun file : OutputFile => file.mediaType) hfile
        rw [hwatMediaType] at hmedia
        simp at hmedia
      let missingFiles : Array OutputFile := #[watFile]
      have _ : ¬ ProofForgeV2.Targets.Near.IREmissionV1 ir missingFiles := by
        apply rejectDifferent
        intro heq
        have hsize := congrArg Array.size heq
        simp [missingFiles, hbaseSize] at hsize
      let reorderedFiles : Array OutputFile := #[abiFile, watFile]
      have _ : ¬ ProofForgeV2.Targets.Near.IREmissionV1 ir reorderedFiles := by
        apply rejectDifferent
        intro heq
        have hfirst := congrArg (fun files : Array OutputFile => files[0]?) heq
        have habiEqWat : abiFile = watFile :=
          Option.some.inj (by simpa [reorderedFiles, hwatFile] using hfirst)
        exact hfilesDistinct habiEqWat.symm
      let duplicateFiles : Array OutputFile := #[watFile, watFile]
      have _ : ¬ ProofForgeV2.Targets.Near.IREmissionV1 ir duplicateFiles := by
        apply rejectDifferent
        intro heq
        have hsecond := congrArg (fun files : Array OutputFile => files[1]?) heq
        have hwatEqAbi : watFile = abiFile :=
          Option.some.inj (by simpa [duplicateFiles, habiFile] using hsecond)
        exact hfilesDistinct hwatEqAbi
      let extraFiles := baseFiles.push {
        path := "forged.extra"
        mediaType := "application/octet-stream"
        contents := "forged"
      }
      have _ : ¬ ProofForgeV2.Targets.Near.IREmissionV1 ir extraFiles := by
        apply rejectDifferent
        intro heq
        have hsize := congrArg Array.size heq
        simp [extraFiles, hbaseSize] at hsize
      expect (ir.sourcePlan == plan)
        "VerifiedVaultPF IR must retain the exact production Plan"
      expect (ir.keys.size == 3 && plan.storage.fields.size == 2 &&
          plan.storage.stateLeaves == #[#[0], #[1]] &&
          plan.storage.fields.map (·.key) ==
            #["pf:v1:state:0", "pf:v1:state:1"] &&
          plan.storage.fields.map (fun field =>
            (field.sourceId, field.name, field.byteWidth, field.endianness)) == #[
              (0, "reserves", 8, .little),
              (1, "shares", 8, .little)
            ])
        "VerifiedVaultPF canonical storage/key shape"
      let markerRegion := ir.keys[0]!
      let reservesRegion := ir.keys[1]!
      let sharesRegion := ir.keys[2]!
      expect (markerRegion.key == plan.storage.markerKey &&
          markerRegion.offset == 0 &&
          markerRegion.length == plan.storage.markerKey.toUTF8.size &&
          reservesRegion.key == plan.storage.fields[0]!.key &&
          reservesRegion.offset == markerRegion.length &&
          reservesRegion.length == plan.storage.fields[0]!.key.toUTF8.size &&
          sharesRegion.key == plan.storage.fields[1]!.key &&
          sharesRegion.offset == markerRegion.length + reservesRegion.length &&
          sharesRegion.length == plan.storage.fields[1]!.key.toUTF8.size)
        "VerifiedVaultPF IR keys must be the canonical production regions"
      match hstatus : plan.entries[2]? with
      | none =>
          throw <| IO.userError "VerifiedVaultPF production Plan is missing status at entry 2"
      | some statusMethod =>
          match hstatusIR : ir.methods[3]? with
          | none =>
              throw <| IO.userError "VerifiedVaultPF production IR is missing status at method 3"
          | some statusIR =>
              have hstatusBaseEmission :
                  ∃ watMethodText abiMethodText,
                    ProofForgeV2.Targets.Near.EntryBaseEmissionV1
                      plan ir baseFiles 2 statusMethod statusIR watFile abiFile
                        watMethodText abiMethodText :=
                ProofForgeV2.Targets.Near.irEmissionV1_entryBaseEmissionV1
                  plan ir baseFiles 2 statusMethod statusIR watFile abiFile
                    hgraphs.2.2 hemissions hwatFile habiFile hstatus hstatusIR
              let forgedAbiFile : OutputFile := {
                abiFile with
                contents := abiFile.contents ++ "\n{\"forged\":true}"
              }
              let forgedStatusBaseFiles : Array OutputFile :=
                #[watFile, forgedAbiFile]
              have hforgedStatusBaseFilesDifferent :
                  forgedStatusBaseFiles ≠ baseFiles := by
                intro heq
                have hsecond :=
                  congrArg (fun files : Array OutputFile => files[1]?) heq
                have hforgedAbiEq : forgedAbiFile = abiFile :=
                  Option.some.inj
                    (by simpa [forgedStatusBaseFiles, habiFile] using hsecond)
                have hcontents := congrArg
                  (fun file : OutputFile => file.contents) hforgedAbiEq
                have hlength := congrArg String.length hcontents
                simp [forgedAbiFile] at hlength
              have hforgedStatusBaseNoEmission :
                  ¬ ProofForgeV2.Targets.Near.IREmissionV1
                    ir forgedStatusBaseFiles :=
                rejectDifferent forgedStatusBaseFiles
                  hforgedStatusBaseFilesDifferent
              have _ :
                  ∀ watMethodText abiMethodText,
                    ¬ ProofForgeV2.Targets.Near.EntryBaseEmissionV1
                      plan ir forgedStatusBaseFiles 2 statusMethod statusIR
                        watFile forgedAbiFile watMethodText abiMethodText := by
                intro watMethodText abiMethodText hforged
                exact hforgedStatusBaseNoEmission hforged.irEmission
              have hstatusMethodWAT :
                  ∃ methodText,
                    ProofForgeV2.Targets.Near.MethodWATEmissionV1
                      ir 3 statusIR watFile.contents methodText :=
                by
                  obtain ⟨watMethodText, _, hbase⟩ := hstatusBaseEmission
                  exact ⟨watMethodText, hbase.watMethodEmission⟩
              have _ :
                  ∀ methodText,
                    ¬ ProofForgeV2.Targets.Near.MethodWATEmissionV1
                      ir 3 statusIR (watFile.contents ++ "\n;; forged")
                        methodText := by
                intro methodText
                intro hforged
                rcases hstatusMethodWAT with ⟨_, hstatusMethodWAT⟩
                rcases hstatusMethodWAT with
                  ⟨_, _, hwatTextExact, _, _⟩
                rcases hforged with
                  ⟨_, _, hforgedTextExact, _, _⟩
                have hsame :
                    watFile.contents ++ "\n;; forged" = watFile.contents :=
                  hforgedTextExact.trans hwatTextExact.symm
                have hlength := congrArg String.length hsame
                simp at hlength
              have hstatusMethodABI :
                  ∃ methodText,
                    ProofForgeV2.Targets.Near.MethodABIEmissionV1
                      ir 3 statusMethod abiFile.contents methodText :=
                by
                  obtain ⟨_, abiMethodText, hbase⟩ := hstatusBaseEmission
                  exact ⟨abiMethodText, hbase.abiMethodEmission⟩
              have _ :
                  ∀ methodText,
                    ¬ ProofForgeV2.Targets.Near.MethodABIEmissionV1
                      ir 3 statusMethod (abiFile.contents ++ "\n{\"forged\":true}")
                        methodText := by
                intro methodText
                intro hforged
                rcases hstatusMethodABI with ⟨_, hstatusMethodABI⟩
                rcases hstatusMethodABI with
                  ⟨_, _, habiTextExact, _, _⟩
                rcases hforged with
                  ⟨_, _, hforgedTextExact, _, _⟩
                have hsame :
                    abiFile.contents ++ "\n{\"forged\":true}" =
                      abiFile.contents :=
                  hforgedTextExact.trans habiTextExact.symm
                have hlength := congrArg String.length hsame
                simp at hlength
              have hstatusLowering :
                  ProofForgeV2.Targets.Near.MethodIRLoweringV1
                    plan ir.keys statusMethod statusIR :=
                by
                  obtain ⟨_, _, hbase⟩ := hstatusBaseEmission
                  exact hbase.methodIRLowering
              have _ : statusIR.name = statusMethod.name :=
                by
                  obtain ⟨_, _, hbase⟩ := hstatusBaseEmission
                  exact hbase.methodName
              have _ :
                  ∀ watMethodText abiMethodText,
                    ¬ ProofForgeV2.Targets.Near.EntryBaseEmissionV1
                      plan ir baseFiles 2 statusMethod statusIR abiFile abiFile
                        watMethodText abiMethodText := by
                intro watMethodText abiMethodText hwrong
                have habiEqWat : abiFile = watFile :=
                  Option.some.inj
                    (hwrong.watFileLookup.symm.trans hwatFile)
                exact hfilesDistinct habiEqWat.symm
              expect (statusMethod.name == "status" &&
                  statusMethod.params.isEmpty &&
                  statusMethod.exactInputLen == 0 &&
                  statusMethod.mode == .view &&
                  statusMethod.depositPolicy == .queryOnly &&
                  statusMethod.resultKind == .uint64 &&
                  statusMethod.body ==
                    #[ProofForgeV2.Targets.Near.Statement.returnValue
                      (.stateLoad 0)])
                "VerifiedVaultPF production status Method shape"
              expect (statusIR.name == "status" &&
                  statusIR.params.isEmpty &&
                  statusIR.mode == .view &&
                  statusIR.tempCount == 1 &&
                  statusIR.operations == #[
                    .checkInputLen 0,
                    .requireLayout markerRegion plan.storage.markerValue,
                    .loadState 0 reservesRegion,
                    .setReturnData 8 0
                  ])
                "VerifiedVaultPF production status MethodIR static alignment"
              match hmarkerLookup : ir.keys[0]? with
              | none =>
                  throw <| IO.userError
                    "VerifiedVaultPF production IR is missing its marker key region"
              | some alignedMarkerRegion =>
                  match hreservesLookup : ir.keys[1]? with
                  | none =>
                      throw <| IO.userError
                        "VerifiedVaultPF production IR is missing its reserves key region"
                  | some alignedReservesRegion =>
                      let statusBinding :=
                        productionReservesBinding alignedReservesRegion.key
                      let ⟨_, hbinding⟩ ← checkProductionReservesBinding
                        semanticData plan.storage alignedReservesRegion.key
                      if hmarkerCanonical :
                          alignedMarkerRegion.key = plan.storage.markerKey ∧
                          alignedMarkerRegion.length =
                            plan.storage.markerKey.toUTF8.size then
                        if hfieldCanonical :
                            alignedReservesRegion.length =
                              alignedReservesRegion.key.toUTF8.size then
                          match hmethodRecognize :
                              recognizeNullaryUInt64ViewMethodV1 statusMethod with
                          | none =>
                              throw <| IO.userError
                                "VerifiedVaultPF production status Method was not structurally recognized"
                          | some methodShape =>
                              if hmethodFields :
                                  methodShape.viewName = "status" ∧
                                  methodShape.physicalFieldIndex = 0 then
                                match hmethodIRRecognize :
                                    recognizeNullaryUInt64ViewMethodIRV1 statusIR with
                                | none =>
                                    throw <| IO.userError
                                      "VerifiedVaultPF production status MethodIR was not structurally recognized"
                                | some methodIRShape =>
                                    if hirScalars :
                                        methodIRShape.viewName = "status" ∧
                                        methodIRShape.markerValue =
                                          plan.storage.markerValue then
                                      if hirMarkerFields :
                                          methodIRShape.markerRegion.key =
                                              alignedMarkerRegion.key ∧
                                          methodIRShape.markerRegion.offset =
                                              alignedMarkerRegion.offset ∧
                                          methodIRShape.markerRegion.length =
                                              alignedMarkerRegion.length then
                                        if hirFieldFields :
                                            methodIRShape.fieldRegion.key =
                                                alignedReservesRegion.key ∧
                                            methodIRShape.fieldRegion.offset =
                                                alignedReservesRegion.offset ∧
                                            methodIRShape.fieldRegion.length =
                                                alignedReservesRegion.length then
                                          have hmethodShapeExact :
                                              methodShape = {
                                                viewName := "status"
                                                physicalFieldIndex := 0
                                              } := by
                                            cases methodShape
                                            simp_all
                                          have hirMarkerExact := keyRegion_eq_of_fields
                                            methodIRShape.markerRegion alignedMarkerRegion
                                            hirMarkerFields.1 hirMarkerFields.2.1
                                            hirMarkerFields.2.2
                                          have hirFieldExact := keyRegion_eq_of_fields
                                            methodIRShape.fieldRegion alignedReservesRegion
                                            hirFieldFields.1 hirFieldFields.2.1
                                            hirFieldFields.2.2
                                          have hmethodIRShapeExact :
                                              methodIRShape = {
                                                viewName := "status"
                                                markerRegion := alignedMarkerRegion
                                                markerValue := plan.storage.markerValue
                                                fieldRegion := alignedReservesRegion
                                              } := by
                                            cases methodIRShape
                                            simp_all
                                          have hrecognizedMethod :
                                              recognizeNullaryUInt64ViewMethodV1
                                                  statusMethod = some {
                                                viewName := "status"
                                                physicalFieldIndex := 0
                                              } :=
                                            hmethodRecognize.trans
                                              (congrArg some hmethodShapeExact)
                                          have hrecognizedMethodIR :
                                              recognizeNullaryUInt64ViewMethodIRV1
                                                  statusIR = some {
                                                viewName := "status"
                                                markerRegion := alignedMarkerRegion
                                                markerValue := plan.storage.markerValue
                                                fieldRegion := alignedReservesRegion
                                              } :=
                                            hmethodIRRecognize.trans
                                              (congrArg some hmethodIRShapeExact)
                                          have hvalidate :
                                              validateSemanticProgramV1 semantic =
                                                .ok semanticData := by
                                            simpa [semanticDataResult] using hsemanticData
                                          have hstatusStaticAlignment :
                                              ProductionNullaryUInt64ViewStaticAlignmentV1
                                                semantic semanticData plan ir.keys
                                                statusBinding "status" statusMethod
                                                alignedMarkerRegion alignedReservesRegion
                                                statusIR :=
                                            productionNullaryUInt64ViewStaticAlignmentV1_of_recognized
                                              semantic semanticData plan ir.keys
                                              statusBinding "status" statusMethod
                                              alignedMarkerRegion alignedReservesRegion
                                              statusIR hvalidate hgraphs.2.1
                                              hmarkerLookup
                                              (by simpa [statusBinding,
                                                productionReservesBinding] using
                                                hreservesLookup)
                                              hstatusLowering hbinding
                                              hmarkerCanonical.1
                                              hmarkerCanonical.2 rfl
                                              hfieldCanonical hrecognizedMethod
                                              hrecognizedMethodIR
                                          have _ :
                                              ∃ watMethodText abiMethodText,
                                                CapabilityEntryStaticEmissionV1
                                                  capability semantic semanticData plan ir
                                                  baseFiles 2 statusBinding "status"
                                                  statusMethod alignedMarkerRegion
                                                  alignedReservesRegion statusIR watFile
                                                  abiFile watMethodText abiMethodText :=
                                            capabilityEntryStaticEmissionV1_of_graphs
                                              capability semantic semanticData plan ir
                                              baseFiles 2 statusBinding "status"
                                              statusMethod alignedMarkerRegion
                                              alignedReservesRegion statusIR watFile
                                              abiFile (by rfl) hplanCapability
                                              hirCapability hbuildCapability
                                              hstatusStaticAlignment hstatus hstatusIR
                                              hwatFile habiFile
                                          have _ :
                                              ∀ watMethodText abiMethodText,
                                                ¬ CapabilityEntryStaticEmissionV1
                                                  capability semantic semanticData plan ir
                                                  forgedStatusBaseFiles 2 statusBinding
                                                  "status" statusMethod alignedMarkerRegion
                                                  alignedReservesRegion statusIR watFile
                                                  forgedAbiFile watMethodText
                                                  abiMethodText := by
                                            intro watMethodText abiMethodText hforged
                                            exact hforgedStatusBaseFilesDifferent <|
                                              Except.ok.inj
                                                (hforged.buildResult.symm.trans
                                                  hbuildCapability)
                                          pure ()
                                        else
                                          throw <| IO.userError
                                            "VerifiedVaultPF recognized status field region diverges from production keys"
                                      else
                                        throw <| IO.userError
                                          "VerifiedVaultPF recognized status marker region diverges from production keys"
                                    else
                                      throw <| IO.userError
                                        "VerifiedVaultPF recognized status MethodIR has wrong name or marker"
                              else
                                throw <| IO.userError
                                  "VerifiedVaultPF recognized status Method has wrong name or state index"
                        else
                          throw <| IO.userError
                            "VerifiedVaultPF production reserves key region has wrong length"
                      else
                        throw <| IO.userError
                          "VerifiedVaultPF production marker key region is not canonical"

      -- Public Plan tampering remains fail-closed at the target validator.
      expectNearPlanRejected "erasure decision removed" {
        plan with invariantErasure? := none
      }
      expectNearPlanRejected "erasure wrong version" {
        plan with invariantErasure? := some {
          decision with version := decision.version ++ ".forged"
        }
      }
      expectNearPlanRejected "erasure invalid digest" {
        plan with invariantErasure? := some {
          decision with sourceDigest := {
            decision.sourceDigest with bytes := ByteArray.empty
          }
        }
      }
      expectNearPlanRejected "erasure empty roots" {
        plan with invariantErasure? := some {
          decision with erasedInvariantCallableIds := #[]
        }
      }
      expectNearPlanRejected "erasure unsorted methods" {
        plan with invariantErasure? := some {
          decision with retainedMethodCallableIds := #[2, 1, 3]
        }
      }
      expectNearPlanRejected "erasure out-of-range root" {
        plan with invariantErasure? := some {
          decision with erasedInvariantCallableIds := #[5]
        }
      }
      expectNearPlanRejected "erasure retained/root overlap" {
        plan with invariantErasure? := some {
          decision with
            retainedMethodCallableIds := #[1, 2, 4]
            erasedInvariantCallableIds := #[4]
        }
      }
      -- Dense, ordered and count-preserving, but semantically transposes the
      -- status view and invariant root. The private whole-Plan binding must
      -- reject this mutation even though the structural partition alone looks
      -- valid.
      expectNearPlanRejected "erasure semantic repartition" {
        plan with invariantErasure? := some {
          decision with
            retainedMethodCallableIds := #[1, 2, 4]
            erasedInvariantCallableIds := #[3]
        }
      }
      expectNearPlanRejected "erasure missing callable" {
        plan with invariantErasure? := some {
          decision with semanticCallableCount := 6
        }
      }
      expectNearPlanRejected "erasure wrong callable count" {
        plan with invariantErasure? := some {
          decision with semanticCallableCount := 4
        }
      }
  | .noProof => throw <| IO.userError "VerifiedVaultPF proof returned noProof"
  | .failed phase detail =>
      throw <| IO.userError
        s!"VerifiedVaultPF requires .certified; got phase={repr phase} detail={repr detail}"

private def initializerViewEqualitySource
    (programName leftState rightState viewName invariantName initBody callableBody : String) :
    String :=
  let proofName := programName ++ "Proof." ++ invariantName
  header ++
  "program " ++ programName ++ " where\n" ++
  "  state " ++ leftState ++ " : UInt64\n" ++
  "  state " ++ rightState ++ " : UInt64\n" ++
  initBody ++ callableBody ++
  "  invariant " ++ invariantName ++ " : " ++ leftState ++ " == " ++ rightState ++ "\n" ++
  "  proof " ++ invariantName ++ " preserving using " ++ proofName ++ "\n" ++
  "theorem " ++ proofName ++ " : " ++ programName ++
    ".ProofPreserving." ++ invariantName ++ " := by\n" ++
  "  exact ProofForgeV2.Semantic.InitializerViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1\n" ++
  "    " ++ programName ++ ".Proof.subjectDataV1.qualifiedName\n" ++
  "    \"" ++ leftState ++ "\" \"" ++ rightState ++ "\" \"" ++ viewName ++
    "\" \"" ++ invariantName ++ "\"\n" ++
  "    " ++ programName ++ ".Proof.subjectDataV1 " ++ programName ++
    ".Proof.subjectBytesV1\n" ++
  "    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)\n" ++
  "    (by decide) (by decide) (by rfl)\n" ++
  "    " ++ programName ++ ".Proof.subjectBodyEncodeOkV1\n"

/-- The family is genuinely name-parameterized. Near misses remain valid DSL
    programs and reach certification, but cannot reuse its exact theorem after
    changing initializer shape or only the state slot loaded by the view. -/
private unsafe def testInitializerViewEqualityFamilyProductCoverage
    (session : ProductParserSessionV1) : IO Unit := do
  let renamed := initializerViewEqualitySource
    "AlphaRenamedInitializerViewEquality"
    "assets" "liabilities" "readAssets" "balanced"
    "  init() do\n    assets := 0\n    liabilities := 0\n"
    "  view readAssets() : UInt64 do\n    return assets\n"
  let renamedPath ← parsePath "tests/inline-proof/AlphaRenamedInitializerViewEquality.lean"
  let (renamedSource, renamedOrigin, renamedInventory) ← loadProduct session renamed
    "tests/inline-proof/AlphaRenamedInitializerViewEquality.lean" "Root"
  let renamedCompiled ← compileOf renamedSource renamedOrigin
  let renamedOutcome ← certifyInlineProofV1 session renamed renamedSource renamedOrigin
    renamedInventory renamedCompiled renamedPath "Root" none
  expectOutcome "alpha-renamed initializer/view equality" renamedOutcome fun
    | .certified carrier =>
        CertifiedInlineProofV1.theoremCount carrier == 1 &&
        digestPresent (CertifiedInlineProofV1.proofCertificationDigest carrier)
    | _ => false

  let cases := #[
    ("InitializerStoreNearMiss",
      "  init() do\n    reserves := 0\n",
      "  view status() : UInt64 do\n    return reserves\n"),
    ("StatusLoadedSlotNearMiss",
      "  init() do\n    reserves := 0\n    shares := 0\n",
      "  view status() : UInt64 do\n    return shares\n")
  ]
  for (programName, initBody, callableBody) in cases do
    let src := initializerViewEqualitySource programName
      "reserves" "shares" "status" "solvent" initBody callableBody
    let fileName := s!"tests/inline-proof/{programName}.lean"
    let path ← parsePath fileName
    let (source, origin, inventory) ← loadProduct session src fileName "Root"
    let compiled ← compileOf source origin
    let outcome ← certifyInlineProofV1 session src source origin inventory compiled
      path "Root" none
    expectOutcome programName outcome fun
      | .failed phase detail =>
          phase == .certification && detail == .elaborate
      | _ => false

private def initializerDepositViewEqualitySource
    (programName leftState rightState depositName parameterName viewName
      invariantName initBody depositBody viewBody : String) : String :=
  let proofName := programName ++ "Proof." ++ invariantName
  header ++
  "program " ++ programName ++ " where\n" ++
  "  state " ++ leftState ++ " : UInt64\n" ++
  "  state " ++ rightState ++ " : UInt64\n" ++
  initBody ++ depositBody ++ viewBody ++
  "  invariant " ++ invariantName ++ " : " ++ leftState ++ " == " ++ rightState ++ "\n" ++
  "  proof " ++ invariantName ++ " preserving using " ++ proofName ++ "\n" ++
  "theorem " ++ proofName ++ " : " ++ programName ++
    ".ProofPreserving." ++ invariantName ++ " := by\n" ++
  "  exact ProofForgeV2.Semantic.InitializerDepositViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1\n" ++
  "    " ++ programName ++ ".Proof.subjectDataV1.qualifiedName\n" ++
  "    \"" ++ leftState ++ "\" \"" ++ rightState ++ "\" \"" ++ depositName ++
    "\" \"" ++ parameterName ++ "\" \"" ++ viewName ++ "\" \"" ++
    invariantName ++ "\"\n" ++
  "    " ++ programName ++ ".Proof.subjectDataV1 " ++ programName ++
    ".Proof.subjectBytesV1\n" ++
  "    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)\n" ++
  "    (by decide) (by decide) (by decide) (by decide) (by rfl)\n" ++
  "    " ++ programName ++ ".Proof.subjectBodyEncodeOkV1\n"

/-- The additive business family is name-parameterized but shape-exact. The
    alpha-renamed program certifies; typed-valid changes to either update,
    checked-add data flow, result, or callable order fail during theorem
    elaboration rather than inheriting an unrelated preservation theorem. -/
private unsafe def testInitializerDepositViewEqualityFamilyProductCoverage
    (session : ProductParserSessionV1) : IO Unit := do
  let renamed := initializerDepositViewEqualitySource
    "AlphaRenamedInitializerDepositViewEquality"
    "assets" "liabilities" "contribute" "quantity" "readAssets" "balanced"
    "  init() do\n    assets := 0\n    liabilities := 0\n"
    ("  entry contribute(quantity : UInt64) : UInt64 do\n" ++
      "    assets := assets + quantity\n" ++
      "    liabilities := liabilities + quantity\n" ++
      "    return liabilities\n")
    "  view readAssets() : UInt64 do\n    return assets\n"
  let renamedPath ← parsePath
    "tests/inline-proof/AlphaRenamedInitializerDepositViewEquality.lean"
  let (renamedSource, renamedOrigin, renamedInventory) ← loadProduct session renamed
    "tests/inline-proof/AlphaRenamedInitializerDepositViewEquality.lean" "Root"
  let renamedCompiled ← compileOf renamedSource renamedOrigin
  let renamedOutcome ← certifyInlineProofV1 session renamed renamedSource renamedOrigin
    renamedInventory renamedCompiled renamedPath "Root" none
  expectOutcome "alpha-renamed initializer/deposit/view equality" renamedOutcome fun
    | .certified carrier =>
        CertifiedInlineProofV1.theoremCount carrier == 1 &&
        digestPresent (CertifiedInlineProofV1.proofCertificationDigest carrier) &&
        (CertifiedInlineProofV1.audited carrier).size == 1
    | _ => false

  let initBody := "  init() do\n    assets := 0\n    liabilities := 0\n"
  let viewBody := "  view readAssets() : UInt64 do\n    return assets\n"
  let cases := #[
    ("DepositSecondStoreMissing",
      ("  entry contribute(quantity : UInt64) : UInt64 do\n" ++
        "    assets := assets + quantity\n" ++
        "    return liabilities\n"),
      viewBody),
    ("DepositSecondLoadWrong",
      ("  entry contribute(quantity : UInt64) : UInt64 do\n" ++
        "    assets := assets + quantity\n" ++
        "    liabilities := assets + quantity\n" ++
        "    return liabilities\n"),
      viewBody),
    ("DepositOverwriteInsteadOfAdd",
      ("  entry contribute(quantity : UInt64) : UInt64 do\n" ++
        "    assets := quantity\n" ++
        "    liabilities := quantity\n" ++
        "    return liabilities\n"),
      viewBody),
    ("DepositWrongReturnSlot",
      ("  entry contribute(quantity : UInt64) : UInt64 do\n" ++
        "    assets := assets + quantity\n" ++
        "    liabilities := liabilities + quantity\n" ++
        "    return assets\n"),
      viewBody),
    ("DepositBoolResult",
      ("  entry contribute(quantity : UInt64) : Bool do\n" ++
        "    assets := assets + quantity\n" ++
        "    liabilities := liabilities + quantity\n" ++
        "    return true\n"),
      viewBody),
    ("DepositCallableOrder",
      ("  view readAssets() : UInt64 do\n" ++
        "    return assets\n" ++
        "  entry contribute(quantity : UInt64) : UInt64 do\n" ++
        "    assets := assets + quantity\n" ++
        "    liabilities := liabilities + quantity\n" ++
        "    return liabilities\n"),
      "")
  ]
  for (programName, depositBody, trailingViewBody) in cases do
    let src := initializerDepositViewEqualitySource programName
      "assets" "liabilities" "contribute" "quantity" "readAssets" "balanced"
      initBody depositBody trailingViewBody
    let fileName := s!"tests/inline-proof/{programName}.lean"
    let path ← parsePath fileName
    let (source, origin, inventory) ← loadProduct session src fileName "Root"
    let compiled ← compileOf source origin
    let outcome ← certifyInlineProofV1 session src source origin inventory compiled
      path "Root" none
    expectOutcome programName outcome fun
      | .failed phase detail =>
          phase == .certification && detail == .elaborate
      | _ => false

private def initializerDepositWithdrawViewEqualitySource
    (programName withdrawBody viewAndWithdrawBody : String) : String :=
  let proofName := programName ++ "Proof.balanced"
  header ++ "program " ++ programName ++ " where\n" ++
  "  state assets : UInt64\n  state liabilities : UInt64\n" ++
  "  init() do\n    assets := 0\n    liabilities := 0\n" ++
  "  entry contribute(quantity : UInt64) : UInt64 do\n" ++
  "    assets := assets + quantity\n    liabilities := liabilities + quantity\n    return liabilities\n" ++
  withdrawBody ++ viewAndWithdrawBody ++
  "  invariant balanced : assets == liabilities\n" ++
  "  proof balanced preserving using " ++ proofName ++ "\n" ++
  "theorem " ++ proofName ++ " : " ++ programName ++ ".ProofPreserving.balanced := by\n" ++
  "  exact ProofForgeV2.Semantic.InitializerDepositWithdrawViewEqualityPreservationV1.preservationTheorem_of_subjectBodyV1\n" ++
  "    " ++ programName ++ ".Proof.subjectDataV1.qualifiedName\n" ++
  "    \"assets\" \"liabilities\" \"contribute\" \"quantity\" \"redeem\" \"quantity\"\n" ++
  "    \"readAssets\" \"balanced\"\n" ++
  "    " ++ programName ++ ".Proof.subjectDataV1 " ++ programName ++ ".Proof.subjectBytesV1\n" ++
  "    (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)\n" ++
  "    (by decide) (by decide) (by decide) (by decide) (by decide) (by decide) (by decide) (by rfl)\n" ++
  "    " ++ programName ++ ".Proof.subjectBodyEncodeOkV1\n"

private unsafe def testInitializerDepositWithdrawViewEqualityFamilyProductCoverage
    (session : ProductParserSessionV1) : IO Unit := do
  let exactWithdraw := "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= assets\n    assert quantity <= liabilities\n    assets := assets - quantity\n    liabilities := liabilities - quantity\n"
  let viewBody := "  view readAssets() : UInt64 do\n    return assets\n"
  let cases := #[
    ("AlphaRenamedFiveCallable", exactWithdraw, viewBody, true),
    ("WithdrawMissingSecondSubtractStore", "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= assets\n    assert quantity <= liabilities\n    assets := assets - quantity\n", viewBody, false),
    ("WithdrawWrongSubtractSource", "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= assets\n    assert quantity <= liabilities\n    assets := liabilities - quantity\n    liabilities := liabilities - quantity\n", viewBody, false),
    ("WithdrawWrongStateSlot", "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= assets\n    assert quantity <= liabilities\n    assets := assets - quantity\n    assets := assets - quantity\n", viewBody, false),
    ("WithdrawMissingFirstAssert", "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= liabilities\n    assets := assets - quantity\n    liabilities := liabilities - quantity\n", viewBody, false),
    ("WithdrawMissingSecondAssert", "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= assets\n    assets := assets - quantity\n    liabilities := liabilities - quantity\n", viewBody, false),
    ("WithdrawReversedAssert", "  entry redeem(quantity : UInt64) : Unit do\n    assert assets <= quantity\n    assert quantity <= liabilities\n    assets := assets - quantity\n    liabilities := liabilities - quantity\n", viewBody, false),
    ("WithdrawOverwrite", "  entry redeem(quantity : UInt64) : Unit do\n    assert quantity <= assets\n    assert quantity <= liabilities\n    assets := quantity\n    liabilities := quantity\n", viewBody, false),
    ("WithdrawWrongResultShape", "  entry redeem(quantity : UInt64) : UInt64 do\n    assert quantity <= assets\n    assert quantity <= liabilities\n    assets := assets - quantity\n    liabilities := liabilities - quantity\n    return liabilities\n", viewBody, false),
    ("WithdrawWrongCallableOrder", "", viewBody ++ exactWithdraw, false)
  ]
  for (programName, withdrawBody, trailingBody, shouldCertify) in cases do
    let src := initializerDepositWithdrawViewEqualitySource programName withdrawBody trailingBody
    let fileName := s!"tests/inline-proof/{programName}.lean"
    let path ← parsePath fileName
    let (source, origin, inventory) ← loadProduct session src fileName "Root"
    let compiled ← compileOf source origin
    let outcome ← certifyInlineProofV1 session src source origin inventory compiled path "Root" none
    expectOutcome programName outcome fun
      | .certified carrier => shouldCertify && CertifiedInlineProofV1.theoremCount carrier == 1
      | .failed phase detail => !shouldCertify && phase == .certification && detail == .elaborate
      | _ => false

/-- Proof kind is source certification metadata: changing only holds ↔ preserving
    changes canonical ProgramV1/source identity, while Normalize emits the same
    business SemanticProgramV1 bytes and digest. -/
private unsafe def testProofKindIdentityBoundary
    (session : ProductParserSessionV1) : IO Unit := do
  let programName := "Kinded"
  let authorTheorem := "KindedProof.safe"
  let holdsSrc := simpleClosureProgram programName authorTheorem
    (falseTheoremBody authorTheorem "Kinded.Proof.safe")
  let preservingSrc := preservingSimpleClosureProgram programName authorTheorem
    (falseTheoremBody authorTheorem "Kinded.ProofPreserving.safe")
  let (holdsSource, holdsOrigin, holdsInventory) ← loadProduct session holdsSrc
    "tests/inline-proof/kind-holds.pf" "Root"
  let (preservingSource, preservingOrigin, preservingInventory) ← loadProduct session
    preservingSrc "tests/inline-proof/kind-preserving.pf" "Root"
  let holdsBindings := theoremInventoryBindingsV1 holdsInventory
  let preservingBindings := theoremInventoryBindingsV1 preservingInventory
  expect (holdsBindings.size == 1 && preservingBindings.size == 1)
    "kind identity inventories"
  expect (holdsBindings[0]!.kind == .holds &&
      preservingBindings[0]!.kind == .preserving)
    "bare proof is holds; explicit preserving is preserving"
  expect (holdsBindings[0]!.theoremComponents ==
      preservingBindings[0]!.theoremComponents)
    "kind identity uses the same theorem FQN"
  let holdsCanonical ← match canonicalValidatedSourceAstBytesV1 holdsSource with
    | .ok value => pure value
    | .error detail => throw <| IO.userError s!"holds canonical: {detail}"
  let preservingCanonical ← match canonicalValidatedSourceAstBytesV1 preservingSource with
    | .ok value => pure value
    | .error detail => throw <| IO.userError s!"preserving canonical: {detail}"
  expect (holdsCanonical != preservingCanonical)
    "proof kind must change canonical ProgramV1 bytes"
  let holdsHash ← match sourceHashV1 holdsSource with
    | .ok value => pure value
    | .error detail => throw <| IO.userError s!"holds sourceHash: {detail}"
  let preservingHash ← match sourceHashV1 preservingSource with
    | .ok value => pure value
    | .error detail => throw <| IO.userError s!"preserving sourceHash: {detail}"
  expect (holdsHash != preservingHash) "proof kind must change sourceHash"
  let holdsCompiled ← compileOf holdsSource holdsOrigin
  let preservingCompiled ← compileOf preservingSource preservingOrigin
  expect ((CompiledSemanticV1.semanticV1Of holdsCompiled).canonicalBytes ==
      (CompiledSemanticV1.semanticV1Of preservingCompiled).canonicalBytes)
    "proof kind must not change SemanticProgramV1 bytes"
  expect (CompiledSemanticV1.semanticDigestOf holdsCompiled ==
      CompiledSemanticV1.semanticDigestOf preservingCompiled)
    "proof kind must not change semantic digest"

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

/-- One invariant may carry both kinds, but the certifier inventory comparison is
    exact in source order and kind. Missing, reordered, or kind-forged rows fail
    before elaboration. -/
private unsafe def testForgedDualKindInventory
    (session : ProductParserSessionV1) : IO Unit := do
  let src :=
    header ++
    "program DualKindCert where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant safe : true\n" ++
    "  proof safe using DualKindCertProof.holds\n" ++
    "  proof safe preserving using DualKindCertProof.keeps\n" ++
    falseTheoremBody "DualKindCertProof.holds" "DualKindCert.Proof.safe" ++
    falseTheoremBody "DualKindCertProof.keeps" "DualKindCert.ProofPreserving.safe"
  let path ← parsePath "tests/inline-proof/dual-kind-forge.pf"
  let (source, origin, inventory) ← loadProduct session src
    "tests/inline-proof/dual-kind-forge.pf" "Root"
  let bindings := theoremInventoryBindingsV1 inventory
  expect (bindings.size == 2) "dual-kind certifier binding count"
  expect (bindings[0]!.invariantName == "safe" &&
      bindings[1]!.invariantName == "safe" &&
      bindings[0]!.kind == .holds && bindings[1]!.kind == .preserving)
    "dual-kind certifier keys"
  let compiled ← compileOf source origin
  let partialInventory := mintTheoremInventoryV1 #[bindings[0]!]
  let partialOutcome ← certifyInlineProofV1 session src source origin partialInventory compiled
    path "Root" none
  expectOutcome "dual-kind partial" partialOutcome fun
    | .failed phase detail => phase == .obligation && detail == .obligationMap
    | _ => false
  let reordered := mintTheoremInventoryV1 #[bindings[1]!, bindings[0]!]
  let reorderedOutcome ← certifyInlineProofV1 session src source origin reordered compiled
    path "Root" none
  expectOutcome "dual-kind reordered" reorderedOutcome fun
    | .failed phase detail => phase == .obligation && detail == .obligationMap
    | _ => false
  let forgedFirst := { bindings[0]! with kind := .preserving }
  let forged := mintTheoremInventoryV1 #[forgedFirst, bindings[1]!]
  let forgedOutcome ← certifyInlineProofV1 session src source origin forged compiled
    path "Root" none
  expectOutcome "dual-kind kind-forged" forgedOutcome fun
    | .failed phase detail => phase == .obligation && detail == .obligationMap
    | _ => false

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
  expect (!CertifiedInlineProofV1.hasCompletePreservingInvariantCoverage cA)
    "holds-only certificate must not claim preserving invariant coverage"
  let selection ← liftResult <| resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    ProofForgeV2.Targets.resolveEngineeringRequirementsV1 selection compiledA
  match ProofForgeV2.Targets.authorizeCertifiedNearInvariantErasureV1
      capability cA with
  | .error (.planInvariant .near _) => pure ()
  | .error error =>
      throw <| IO.userError
        s!"holds-only NEAR authorization failed with wrong error: {error.render}"
  | .ok _ =>
      throw <| IO.userError
        "holds-only certificate must not authorize NEAR invariant erasure"
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
    candidate (`Nested.NestedScoped`) while Loader retains the full product
    identity (`Root.Nested.NestedScoped`). This pins multi-component author
    theorem lookup. -/
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
  testPreservingFalseTheoremElab session
  testSameFileCounterPreservingProductPositive session
  testSameFileStatefulEqualityPreservingProductPositive session
  testSameFileVerifiedVaultPFPreservingProductPositive session
  testInitializerViewEqualityFamilyProductCoverage session
  testInitializerDepositViewEqualityFamilyProductCoverage session
  testInitializerDepositWithdrawViewEqualityFamilyProductCoverage session
  testProofKindIdentityBoundary session
  testForbiddenMainModule session
  testWrongSubjectBytes session
  testEmptyInventoryWithProofs session
  testForgedPartialDualInvariant session
  testForgedDualKindInventory session
  testNoForgedSuccess session
  testSimpleClosureProductPositive session
  testModulePrefixedNamespaceProductPositive session
  testRelativeNestedNamespaceProductPositive session
  IO.println "Tests.Compiler.InlineProofCertifierV1: ok"

end Tests.Compiler.InlineProofCertifierV1
