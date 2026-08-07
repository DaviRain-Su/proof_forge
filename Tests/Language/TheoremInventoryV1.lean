import Tests.Language.ParserSession
import ProofForgeV2.Language.TheoremInventoryV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.TheoremInventoryV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Language.Loader
open ProofForgeV2.Language.TheoremInventoryV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectReject (result : Except CompileError α) (needle message : String) : IO Unit :=
  match result with
  | .error error =>
      let rendered := error.render
      unless rendered.contains needle do
        throw <| IO.userError s!"{message}: expected '{needle}' in '{rendered}'"
  | .ok _ => throw <| IO.userError s!"{message}: unexpectedly accepted"

private def header : String :=
  "import ProofForgeV2\nopen ProofForgeV2.Language\n"

private def singleProofProgram (programName theoremName bodyExtra : String) : String :=
  header ++
  "program " ++ programName ++ " where\n" ++
  "  view alive() : Bool do\n" ++
  "    return true\n" ++
  "  invariant safe : true\n" ++
  "  proof safe using " ++ theoremName ++ "\n" ++
  bodyExtra

private def theoremBlock (name type tactics : String) : String :=
  "theorem " ++ name ++ " : " ++ type ++ " := by\n" ++ tactics

private def rflTactics : String := "  rfl\n"

private def richTactics : String :=
  "  intro\n" ++
  "  constructor\n" ++
  "  exact True.intro\n" ++
  "  apply True.intro\n" ++
  "  simp only []\n" ++
  "  rw []\n" ++
  "  cases True.intro\n" ++
  "  rfl\n"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- No proof: inventory path keeps empty inventory (old portable shape).
  let noProof :=
    header ++
    "program Bare where\n" ++
    "  view get() : UInt64 do\n" ++
    "    return 0\n"
  match ← session.selectProgramV1WithTheoremInventory noProof "<bare>" "Root" none with
  | .error error => throw <| IO.userError s!"bare program failed: {error.render}"
  | .ok (src, inv) =>
      expect (src.program.name.raw == "Bare") "bare program name"
      expect (theoremInventoryBindingsV1 inv).isEmpty "bare inventory empty"
      let hash₁ ← match sourceHashV1 src with
        | .ok h => pure h
        | .error e => throw <| IO.userError e
      match ← session.selectProgramV1 noProof "<bare-legacy>" "Root" none with
      | .error error => throw <| IO.userError s!"legacy bare failed: {error.render}"
      | .ok legacy =>
          let hash₂ ← match sourceHashV1 legacy with
            | .ok h => pure h
            | .error e => throw <| IO.userError e
          expect (hash₁ == hash₂) "inventory path must preserve sourceHash without proofs"

  -- Single proof + matching adjacent theorem (rich allowlisted tactics).
  let okSrc :=
    singleProofProgram "Proofed" "ProofedProof.safe"
      (theoremBlock "ProofedProof.safe" "Proofed.Proof.safe" richTactics)
  match ← session.selectProgramV1WithTheoremInventory okSrc "<ok>" "Root" none with
  | .error error => throw <| IO.userError s!"ok inventory failed: {error.render}"
  | .ok (src, inv) =>
      expect (src.program.name.raw == "Proofed") "ok program name"
      let bindings := theoremInventoryBindingsV1 inv
      expect (bindings.size == 1) "ok binding count"
      let b := bindings[0]!
      expect (b.invariantName == "safe") "ok invariant"
      expect (b.kind == ProofKindV1.holds) "bare proof defaults to holds"
      expect (b.theoremComponents == #["ProofedProof", "safe"]) "ok theorem components"
      expect (b.typeComponents == #["Proofed", "Proof", "safe"]) "ok type components"
      -- Legacy path still rejects adjacent theorem as outside DSL.
      expectReject (← session.selectProgramV1 okSrc "<ok-legacy>" "Root" none)
        "outside the portable program DSL"
        "legacy path must not silently accept theorems"

  -- Explicit preserving kind selects the Preservation alias namespace.
  let preserving :=
    header ++
    "program Preserving where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant safe : true\n" ++
    "  proof safe preserving using PreservingProof.safe\n" ++
    theoremBlock "PreservingProof.safe" "Preserving.ProofPreserving.safe" rflTactics
  match ← session.selectProgramV1WithTheoremInventory preserving
      "<preserving>" "Root" none with
  | .error error => throw <| IO.userError s!"preserving failed: {error.render}"
  | .ok (_, inv) =>
      let bindings := theoremInventoryBindingsV1 inv
      expect (bindings.size == 1) "preserving binding count"
      let b := bindings[0]!
      expect (b.kind == ProofKindV1.preserving) "explicit preserving kind"
      expect (b.typeComponents == #["Preserving", "ProofPreserving", "safe"])
        "preserving type components"

  -- Same invariant may bind both kinds; the sole key is (invariant, kind).
  let dualKind :=
    header ++
    "program DualKind where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant safe : true\n" ++
    "  proof safe using DualKindProof.holds\n" ++
    "  proof safe preserving using DualKindProof.keeps\n" ++
    theoremBlock "DualKindProof.holds" "DualKind.Proof.safe" rflTactics ++
    theoremBlock "DualKindProof.keeps" "DualKind.ProofPreserving.safe" rflTactics
  match ← session.selectProgramV1WithTheoremInventory dualKind
      "<dual-kind>" "Root" none with
  | .error error => throw <| IO.userError s!"dual-kind failed: {error.render}"
  | .ok (_, inv) =>
      let bindings := theoremInventoryBindingsV1 inv
      expect (bindings.size == 2) "dual-kind binding count"
      expect (bindings[0]!.kind == ProofKindV1.holds &&
          bindings[1]!.kind == ProofKindV1.preserving)
        "dual-kind source order"

  -- Multi-proof source order bijection.
  let multi :=
    header ++
    "program Multi where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant first : true\n" ++
    "  invariant second : true\n" ++
    "  proof first using MultiProof.first\n" ++
    "  proof second using MultiProof.second\n" ++
    theoremBlock "MultiProof.first" "Multi.Proof.first" rflTactics ++
    theoremBlock "MultiProof.second" "Multi.Proof.second" rflTactics
  match ← session.selectProgramV1WithTheoremInventory multi "<multi>" "Root" none with
  | .error error => throw <| IO.userError s!"multi failed: {error.render}"
  | .ok (_, inv) =>
      let bindings := theoremInventoryBindingsV1 inv
      expect (bindings.size == 2) "multi binding count"
      expect (bindings[0]!.invariantName == "first" &&
          bindings[1]!.invariantName == "second") "multi proof source order"

  -- Multi-program + namespace deterministic selection.
  let multiProg :=
    header ++
    "namespace A\n" ++
    "program One where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant safe : true\n" ++
    "  proof safe using AProof.safe\n" ++
    theoremBlock "AProof.safe" "One.Proof.safe" rflTactics ++
    "end A\n" ++
    "namespace B\n" ++
    "program Two where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant safe : true\n" ++
    "  proof safe using BProof.safe\n" ++
    theoremBlock "BProof.safe" "Two.Proof.safe" rflTactics ++
    "end B\n"
  expectReject (← session.selectProgramV1WithTheoremInventory multiProg
      "<multi-prog>" "Product.Root" none)
    "multiple programs"
    "multi-program requires explicit selection"
  match ← session.selectProgramV1WithTheoremInventory multiProg
      "<multi-prog>" "Product.Root" (some "Product.Root.B.Two") with
  | .error error => throw <| IO.userError s!"select B.Two failed: {error.render}"
  | .ok (src, inv) =>
      expect (src.program.name.raw == "Two") "selected Two"
      let b := (theoremInventoryBindingsV1 inv)[0]!
      expect (b.theoremComponents == #["BProof", "safe"]) "selected theorem"
      expect (b.typeComponents == #["Two", "Proof", "safe"]) "selected type uses local program name"

  match ← session.parseProgramsV1WithTheoremInventory multiProg
      "<multi-snap>" "Product.Root" with
  | .error error => throw <| IO.userError s!"snapshot failed: {error.render}"
  | .ok snap =>
      let units := programTheoremSnapshotUnitsV1 snap
      expect (units.size == 2) "snapshot unit count"
      match units[0]?, units[1]? with
      | some (src0, _), some (src1, _) =>
          expect (src0.program.name.raw == "One") "snapshot order One"
          expect (src1.program.name.raw == "Two") "snapshot order Two"
      | _, _ => throw <| IO.userError "snapshot units missing"

  -- Product additive API: origin join + inventory; canonical unchanged.
  match ← session.selectProgramV1ProductWithTheoremInventory okSrc
      "src/ok.lean" "Root" none with
  | .error bundle =>
      throw <| IO.userError
        s!"product inventory failed: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (src, origins, inv) =>
      expect ((theoremInventoryBindingsV1 inv).size == 1) "product inventory"
      expect ((originInventoryOriginsV1 origins).size > 0) "product origins nonempty"
      let h ← match sourceHashV1 src with
        | .ok v => pure v
        | .error e => throw <| IO.userError e
      -- Same program command without theorems has equal hash under legacy parse of
      -- a proof-only source (theorems are outside ProgramV1).
      let proofOnly := singleProofProgram "Proofed" "ProofedProof.safe" ""
      match ← session.selectProgramV1 proofOnly "<proof-only>" "Root" none with
      | .error error => throw <| IO.userError s!"proof-only legacy failed: {error.render}"
      | .ok only =>
          let hOnly ← match sourceHashV1 only with
            | .ok v => pure v
            | .error e => throw <| IO.userError e
          expect (h == hOnly)
            "adjacent theorems must not change ProgramV1 sourceHash"

  -- Reject: missing theorem when proofs present (inventory path).
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "Missing" "MissingProof.safe" "")
      "<missing>" "Root" none)
    "missing theorem"
    "missing adjacent theorem"

  -- Reject: extra theorem beyond bijection.
  let extra :=
    singleProofProgram "Extra" "ExtraProof.safe"
      (theoremBlock "ExtraProof.safe" "Extra.Proof.safe" rflTactics ++
        theoremBlock "ExtraProof.other" "Extra.Proof.safe" rflTactics)
  expectReject (← session.selectProgramV1WithTheoremInventory extra
      "<extra>" "Root" none)
    "outside the portable program DSL"
    "extra theorem after complete inventory"

  -- Reject: wrong theorem name.
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "WrongName" "Wanted.Name"
        (theoremBlock "Other.Name" "WrongName.Proof.safe" rflTactics))
      "<wrong-name>" "Root" none)
    "wrong theorem name"
    "wrong theorem name"

  -- Reject: wrong type.
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "WrongType" "WrongTypeProof.safe"
        (theoremBlock "WrongTypeProof.safe" "WrongType.Proof.other" rflTactics))
      "<wrong-type>" "Root" none)
    "wrong theorem type"
    "wrong theorem type"

  -- Reject: lemma/def/axiom (and bare non-theorem commands).
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "NotThm" "NotThmProof.safe"
        "def NotThmProof.safe : NotThm.Proof.safe := by rfl\n")
      "<def>" "Root" none)
    "invalid theorem shape"
    "def rejected"

  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "Ax" "AxProof.safe"
        "axiom AxProof.safe : Ax.Proof.safe\n")
      "<axiom>" "Root" none)
    "invalid theorem shape"
    "axiom rejected"

  -- Reject: private modifier.
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "Priv" "PrivProof.safe"
        "private theorem PrivProof.safe : Priv.Proof.safe := by rfl\n")
      "<private>" "Root" none)
    "invalid theorem shape"
    "private modifier rejected"

  -- Reject: non-by proof body.
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "BareRfl" "BareRflProof.safe"
        "theorem BareRflProof.safe : BareRfl.Proof.safe := rfl\n")
      "<bare-rfl>" "Root" none)
    "invalid theorem shape"
    "non-by body rejected"

  -- Reject: binders.
  expectReject (← session.selectProgramV1WithTheoremInventory
      (singleProofProgram "Bind" "BindProof.safe"
        "theorem BindProof.safe (h : True) : Bind.Proof.safe := by exact h\n")
      "<binders>" "Root" none)
    "invalid theorem shape"
    "binders rejected"

  -- Reject: disallowed tactics by kind (not string denylist).
  for (label, tactics) in #[
      ("sorry", "  sorry\n"),
      ("admit", "  admit\n"),
      ("native_decide", "  native_decide\n"),
      ("run_tac", "  run_tac pure ()\n"),
      ("simp-no-only", "  simp\n")
    ] do
    expectReject (← session.selectProgramV1WithTheoremInventory
        (singleProofProgram "BadTac" "BadTacProof.safe"
          (theoremBlock "BadTacProof.safe" "BadTac.Proof.safe" tactics))
        s!"<bad-{label}>" "Root" none)
      "disallowed tactic surface"
      s!"tactic '{label}' must be rejected by kind allowlist"

  -- Reject: proof without matching invariant bijection (inventory path).
  let partialProof :=
    header ++
    "program Partial where\n" ++
    "  view alive() : Bool do\n" ++
    "    return true\n" ++
    "  invariant a : true\n" ++
    "  invariant b : true\n" ++
    "  proof a using PartialProof.a\n" ++
    theoremBlock "PartialProof.a" "Partial.Proof.a" rflTactics
  expectReject (← session.selectProgramV1WithTheoremInventory partialProof
      "<partial>" "Root" none)
    "bijection"
    "partial proof set must fail inventory bijection"

  -- Proof-only source still loads on legacy selectProgramV1.
  match ← session.selectProgramV1
      (singleProofProgram "LegacyProof" "LegacyProof.safe" "")
      "<legacy-proof>" "Root" none with
  | .error error => throw <| IO.userError s!"legacy proof-only failed: {error.render}"
  | .ok src =>
      expect (src.program.items.any fun item =>
        match item with | .proof _ => true | _ => false) "legacy retains proof item"

end Tests.Language.TheoremInventoryV1
