/-
  Tests.Compiler.DiagnosticPipelineV1 — B8b product diagnostic pipeline.

  Covers Loader product entry → located Normalize → product Compiler:
    * multi-error located bundle (≥2 diags, primary.nodeId=some)
    * deterministic order / canonical JSON
    * selectExitCode 3 for source/type/effect
    * foreign inventory → PF-INTERNAL / exit 70
    * parser/selection bundles
    * Counter success parity
    * no first-error truncation
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Source.OriginJoinV1
import Tests.Language.ParserSession

namespace Tests.Compiler.DiagnosticPipelineV1

open ProofForgeV2
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Source.OriginJoinV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def multiErrorSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program DiagnosticMulti where\n" ++
  "  state count : UInt64\n" ++
  "  view get() : UInt64 do\n" ++
  "    count := count + 1\n" ++
  "    return true\n"

private def logicalMulti : String := "testdata/invalid/DiagnosticMultiV1.lean"
private def moduleMulti : String := "Root"

private def typeOnlySource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program TypeOnly where\n" ++
  "  entry run() : UInt64 do\n" ++
  "    return true\n"

private def foreignPeerSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program ForeignPeer where\n" ++
  "  state value : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    value := initial\n" ++
  "  entry ping(delta : UInt64) : UInt64 do\n" ++
  "    value := value + delta\n" ++
  "    return value\n" ++
  "  view get() : UInt64 do\n" ++
  "    return value\n"

private unsafe def testMultiErrorLocatedBundle
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1Product multiErrorSource logicalMulti moduleMulti none with
  | .error bundle =>
      throw <| IO.userError s!"multi-error load failed: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (source, inv) =>
      match normalizeProgramLocatedV1 source inv with
      | .ok _ => throw <| IO.userError "multi-error normalize unexpectedly succeeded"
      | .error bundle =>
          let diags := DiagnosticBundleV1.diagnostics bundle
          expect (diags.size ≥ 2)
            s!"multi-error must retain ≥2 diagnostics, got {diags.size}"
          let withNode := diags.filter fun d =>
            match d.primary with
            | some o => o.nodeId.isSome
            | none => false
          expect (withNode.size ≥ 2)
            "at least two diagnostics must carry primary.nodeId=some"
          let codes := diags.map (·.code.wire)
          expect (codes.any (· == "PF-EFFECT-001"))
            s!"expected PF-EFFECT-001 in multi-error bundle, got {repr codes}"
          expect (codes.any (· == "PF-SRC-INVALID"))
            s!"expected PF-SRC-INVALID type mismatch in multi-error bundle, got {repr codes}"
          expect (DiagnosticBundleV1.selectExitCode bundle == 3)
            s!"multi-error exit must be 3, got {DiagnosticBundleV1.selectExitCode bundle}"
          match DiagnosticBundleV1.renderCanonicalJsonArray bundle with
          | .error e => throw <| IO.userError s!"canonical JSON: {e}"
          | .ok j1 =>
              match DiagnosticBundleV1.renderCanonicalJsonArray bundle with
              | .ok j2 =>
                  expect (j1 == j2) "canonical JSON must be deterministic"
              | .error e => throw <| IO.userError s!"canonical JSON #2: {e}"
          -- Product compiler must preserve the full bundle (no [0]? truncation).
          match Compiler.compileProgramProductV1 source inv with
          | .ok _ => throw <| IO.userError "compile product unexpectedly succeeded"
          | .error cBundle =>
              let cDiags := DiagnosticBundleV1.diagnostics cBundle
              expect (cDiags.size == diags.size)
                "compiler must preserve full normalize bundle size"
              expect (cDiags.map (·.code) == diags.map (·.code))
                "compiler must preserve full diagnostic code sequence"
              expect (DiagnosticBundleV1.renderHuman cBundle ==
                  DiagnosticBundleV1.renderHuman bundle)
                "compiler human render must match normalize bundle"

private unsafe def testForeignInventoryInternal
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1Product multiErrorSource logicalMulti moduleMulti none with
  | .error bundle =>
      throw <| IO.userError s!"foreign base load: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (source, _) =>
      match ← session.selectProgramV1Product
          foreignPeerSource "tests/foreign-peer.pf" moduleMulti none with
      | .error bundle =>
          throw <| IO.userError s!"foreign peer load: {DiagnosticBundleV1.renderHuman bundle}"
      | .ok (_, foreignInv) =>
          match normalizeProgramLocatedV1 source foreignInv with
          | .ok _ => throw <| IO.userError "foreign inventory normalize unexpectedly ok"
          | .error bundle =>
              let diags := DiagnosticBundleV1.diagnostics bundle
              expect (diags.size ≥ 1) "foreign inventory must produce a diagnostic"
              expect (diags[0]!.code == .internal)
                s!"foreign inventory must be PF-INTERNAL, got {diags[0]!.code.wire}"
              expect (DiagnosticBundleV1.selectExitCode bundle == 70)
                s!"foreign inventory exit must be 70, got {DiagnosticBundleV1.selectExitCode bundle}"
              match Compiler.compileProgramProductV1 source foreignInv with
              | .ok _ => throw <| IO.userError "foreign inventory compile unexpectedly ok"
              | .error cBundle =>
                  expect (DiagnosticBundleV1.selectExitCode cBundle == 70)
                    "compiler foreign inventory exit must be 70"

private unsafe def testParserSelectionBundles
    (session : Language.Loader.ParserSession) : IO Unit := do
  let badParse :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\nprogram X where\n  view get() : UInt64 do\n    return (\n"
  match ← session.selectProgramV1Product badParse "diagnostic.lean" "Root" none with
  | .ok _ => throw <| IO.userError "parser-boundary product unexpectedly ok"
  | .error bundle =>
      let diags := DiagnosticBundleV1.diagnostics bundle
      expect (diags.size == 1) "parser-boundary bundle size"
      expect (diags[0]!.code.wire == "PF-SRC-INVALID") "parser-boundary code"
      expect (DiagnosticBundleV1.selectExitCode bundle == 3) "parser-boundary exit 3"

  let multiProg :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program A where\n  view get() : UInt64 do\n    return 0\n" ++
    "program B where\n  view get() : UInt64 do\n    return 1\n"
  match ← session.selectProgramV1Product multiProg "diagnostic.lean" "Root" none with
  | .ok _ => throw <| IO.userError "multi-program product unexpectedly ok"
  | .error bundle =>
      expect ((DiagnosticBundleV1.diagnostics bundle).size == 1)
        "multi-program selection single diagnostic"
      expect ((DiagnosticBundleV1.diagnostics bundle)[0]!.message ==
          "source contains multiple programs; pass --program <qualified-name>")
        "multi-program selection message"

private unsafe def testSuccessParity
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1Product
      Examples.counterSourceText "Examples/Counter.lean"
      Examples.counterModuleNameV1 none with
  | .error bundle =>
      throw <| IO.userError s!"counter product load: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (source, inv) =>
      match normalizeProgramLocatedV1 source inv with
      | .error bundle =>
          throw <| IO.userError s!"counter located normalize: {DiagnosticBundleV1.renderHuman bundle}"
      | .ok carrier1 =>
          match normalizeProgramV1 source with
          | .error e => throw <| IO.userError s!"counter unlocated normalize: {repr e}"
          | .ok carrier2 =>
              expect (carrier1.canonicalBytes == carrier2.canonicalBytes)
                "located vs unlocated Normalize carrier bytes must match"
      match Compiler.compileProgramProductV1 source inv with
      | .error bundle =>
          throw <| IO.userError s!"counter product compile: {DiagnosticBundleV1.renderHuman bundle}"
      | .ok semantic =>
          match Compiler.compileValidatedSourceV1 source with
          | .error e => throw <| IO.userError s!"counter non-product compile: {e.render}"
          | .ok semantic2 =>
              expect (semantic.qualifiedName == semantic2.qualifiedName)
                "product/non-product semantic identity parity"
              expect (semantic.sourceHash == semantic2.sourceHash)
                "product/non-product sourceHash parity"

private unsafe def testTypeOnlySingle
    (session : Language.Loader.ParserSession) : IO Unit := do
  match ← session.selectProgramV1Product
      typeOnlySource "tests/type-only.pf" "Root" none with
  | .error bundle =>
      throw <| IO.userError s!"type-only load: {DiagnosticBundleV1.renderHuman bundle}"
  | .ok (source, inv) =>
      match Compiler.compileProgramProductV1 source inv with
      | .ok _ => throw <| IO.userError "type-only compile unexpectedly ok"
      | .error bundle =>
          let diags := DiagnosticBundleV1.diagnostics bundle
          expect (diags.size ≥ 1) "type-only must retain diagnostics"
          expect (diags.any (fun d =>
              d.message == "type mismatch: expected UInt64, got Bool"))
            "type-only must surface type mismatch message"
          expect (diags.any (fun d =>
              match d.primary with
              | some o => o.nodeId.isSome
              | none => false))
            "type-only diagnostic must carry primary.nodeId=some"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testMultiErrorLocatedBundle session
  testForeignInventoryInternal session
  testParserSelectionBundles session
  testSuccessParity session
  testTypeOnlySingle session
  IO.println "Tests.Compiler.DiagnosticPipelineV1: ok"

end Tests.Compiler.DiagnosticPipelineV1
