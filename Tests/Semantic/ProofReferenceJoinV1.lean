/-
  Tests.Semantic.ProofReferenceJoinV1 — engineering INV-1 product path pins.

  Drives shipped:
    * `collectSourceProofBindingsV1` / `requireProofBundlePairGateV1`
    * `openProofBundleV1` (R-3)
    * `joinProofReferencesV1`
    * product `compileValidatedSourceV1` on a program with `invariant` + `proof`
      (Normalize skips both; no ambient Lean theorem)

  Covers:
    * positive: well-formed reference + matching opened bundle + digests
    * fail-closed: unused bundle, missing bundle, digest pin mismatch,
      sourceHash/semanticHash mismatch, unknown export invariant, theorem mismatch
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.ProofBundleV1
import ProofForgeV2.Semantic.ProofReferenceJoinV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Semantic.ProofReferenceJoinV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.ProofBundleV1
open ProofForgeV2.Semantic.ProofReferenceJoinV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def n (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def q (parts : Array String) : IO SourceQualifiedNameV1 :=
  lift "qualified name" (parseSourceQualifiedNameV1 parts)

private def qn (comps : Array String) : IO QualifiedName :=
  match parseQualifiedName comps with
  | .ok q => pure q
  | .error e => throw <| IO.userError s!"qn: {e}"

private def fixedDigest (tag : UInt8) : Digest :=
  sha256Bytes (ByteArray.mk #[tag, 1, 2, 3])

private def fixedTrustPolicyDigest : IO Digest :=
  match proofTrustPolicyDigestV1 with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"trust policy: {repr error}"

private def block (statements : Array StmtV1) : BlockV1 := { statements }
private def ret (value : ExprV1) : BlockV1 := block #[.return_ (some value)]
private def u (value : Nat) : ExprV1 := .literal (.integer value)
private def var (name : SourceNameComponentV1) : ExprV1 := .place (.name name)
private def param (name : SourceNameComponentV1) : ParamV1 :=
  { visibility := .public_, name := name, type_ := .uint 64 }

/-- Minimal Counter-shaped program with Bool invariant + one proof reference. -/
private def mkProofedCounterSource : IO ValidatedSourceV1 := do
  let mod ← q #["Tests", "ProofedCounter"]
  let id ← q #["Tests", "ProofedCounter", "ProofedCounter"]
  let pname ← n "ProofedCounter"
  let count ← n "count"
  let initial ← n "initial"
  let delta ← n "delta"
  let increment ← n "increment"
  let get ← n "get"
  let nonneg ← n "nonneg"
  let thm ← q #["Bundle", "Thm"]
  let items : Array ProgramItemV1 := #[
    .state { visibility := .public_, name := count, type_ := .uint 64 },
    .init {
      params := #[param initial]
      body := block #[.assign (.name count) (var initial)]
    },
    .entry {
      name := increment
      params := #[param delta]
      result := .uint 64
      body := block #[
        .assign (.name count)
          (.binary .add (var count) (var delta)),
        .return_ (some (var count))
      ]
    },
    .view {
      name := get
      params := #[]
      result := .uint 64
      body := ret (var count)
    },
    .invariant { name := nonneg, predicate := .literal (.bool true) },
    .proof { invariant := nonneg, theorem_ := thm }
  ]
  lift "validate" (validateSourceV1 mod id { name := pname, items })

private def encodeManifestBytes (m : ProofBundleManifestV1) : IO ByteArray := do
  match encodeProofBundleManifestV1 m with
  | .ok s => pure s.toUTF8
  | .error e => throw <| IO.userError s!"encode: {repr e}"

private def mkMatchingBundle
    (oleanPath : String) (oleanBytes : ByteArray)
    (sourceHash semanticHash : Digest)
    (invariantName : String) (theoremComps : Array String) :
    IO (ProofBundleManifestV1 × ByteArray × OpenedProofBundleV1) := do
  let abiModuleName ← qn proofAbiModuleComponentsV1
  let theoremNameAbi ← qn proofAbiTheoremComponentsV1
  let exportThm ← qn theoremComps
  let moduleName ← qn #["Bundle", "Root"]
  let trustPolicyDigest ← fixedTrustPolicyDigest
  let mod : ProofModuleV1 := {
    moduleName
    oleanPath
    oleanDigest := sha256Bytes oleanBytes
    imports := #[]
  }
  let ex : ProofExportV1 := {
    invariantName
    invariantOrdinal := 0
    theoremName := exportThm
    ownerModule := moduleName
  }
  let modules ← match NonEmptyArray.ofArray #[mod] with
    | .ok ne => pure ne
    | .error e => throw <| IO.userError e
  let exports ← match NonEmptyArray.ofArray #[ex] with
    | .ok ne => pure ne
    | .error e => throw <| IO.userError e
  let roots ← match NonEmptyArray.ofArray #[moduleName] with
    | .ok ne => pure ne
    | .error e => throw <| IO.userError e
  let m : ProofBundleManifestV1 := {
    schema := proofBundleSchemaV1
    sourceHash
    semanticHash
    semanticProvenanceDigest := fixedDigest 0x33
    toolchainLockDigest := fixedDigest 0x44
    proofAbi := {
      semanticSchema := proofAbiSemanticSchemaV1
      moduleName := abiModuleName
      theoremName := theoremNameAbi
      abiOleanDigest := fixedDigest 0x55
      trustPolicyDigest
      trustedBaseClosureDigest := fixedDigest 0x77
    }
    roots
    modules
    exports
  }
  let manBytes ← encodeManifestBytes m
  match openProofBundleV1 manBytes #[(oleanPath, oleanBytes)] with
  | .error e => throw <| IO.userError s!"open: {repr e}"
  | .ok opened => pure (m, manBytes, opened)

/-- Positive product path: compile proofed Counter → open matching bundle → join. -/
private def testPositiveProductJoin : IO Unit := do
  let source ← mkProofedCounterSource
  let bindings := collectSourceProofBindingsV1 source.program
  expect (bindings.size == 1) "one proof binding"
  expect (bindings[0]!.invariantName == "nonneg") "invariant name"
  expect (bindings[0]!.theoremComponents == #["Bundle", "Thm"]) "theorem QN"

  match requireProofBundlePairGateV1 bindings true with
  | .error e => throw <| IO.userError s!"gate: {renderProofReferenceJoinErrorV1 e}"
  | .ok () => pure ()

  let compiled ← match compileValidatedSourceV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile: {e.render}"

  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := "olean-fixture-inv1".toUTF8
  let sourceHash := CompiledSemanticV1.sourceDigestOf compiled
  let semanticHash := CompiledSemanticV1.semanticDigestOf compiled
  let (_, _, opened) ← mkMatchingBundle oleanPath oleanBytes sourceHash semanticHash
    "nonneg" #["Bundle", "Thm"]
  match joinProofReferencesV1 bindings opened opened.bundleDigest sourceHash semanticHash with
  | .error e =>
      throw <| IO.userError s!"join failed: {renderProofReferenceJoinErrorV1 e}"
  | .ok () => pure ()

/-- Missing bundle when source has proofs. -/
private def testMissingBundleGate : IO Unit := do
  let source ← mkProofedCounterSource
  let bindings := collectSourceProofBindingsV1 source.program
  match requireProofBundlePairGateV1 bindings false with
  | .ok () => throw <| IO.userError "missing bundle must fail"
  | .error .missingBundle => pure ()
  | .error e => throw <| IO.userError s!"unexpected: {renderProofReferenceJoinErrorV1 e}"

/-- Unused bundle when source has no proofs. -/
private def testUnusedBundleGate : IO Unit := do
  match requireProofBundlePairGateV1 #[] true with
  | .ok () => throw <| IO.userError "unused bundle must fail"
  | .error .unusedBundle => pure ()
  | .error e => throw <| IO.userError s!"unexpected: {renderProofReferenceJoinErrorV1 e}"
  match requireProofBundlePairGateV1 #[] false with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"empty+empty must ok: {renderProofReferenceJoinErrorV1 e}"

/-- CLI digest pin mismatch fail closed. -/
private def testDigestMismatch : IO Unit := do
  let source ← mkProofedCounterSource
  let bindings := collectSourceProofBindingsV1 source.program
  let compiled ← match compileValidatedSourceV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile: {e.render}"
  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := ByteArray.mk #[9]
  let sourceHash := CompiledSemanticV1.sourceDigestOf compiled
  let semanticHash := CompiledSemanticV1.semanticDigestOf compiled
  let (_, _, opened) ← mkMatchingBundle oleanPath oleanBytes sourceHash semanticHash
    "nonneg" #["Bundle", "Thm"]
  let wrong := fixedDigest 0xAB
  match joinProofReferencesV1 bindings opened wrong sourceHash semanticHash with
  | .ok () => throw <| IO.userError "wrong digest must fail"
  | .error (.digestMismatch _) => pure ()
  | .error e => throw <| IO.userError s!"unexpected: {renderProofReferenceJoinErrorV1 e}"

/-- sourceHash / semanticHash mismatch fail closed. -/
private def testHashMismatches : IO Unit := do
  let source ← mkProofedCounterSource
  let bindings := collectSourceProofBindingsV1 source.program
  let compiled ← match compileValidatedSourceV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile: {e.render}"
  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := ByteArray.mk #[1]
  let sourceHash := CompiledSemanticV1.sourceDigestOf compiled
  let semanticHash := CompiledSemanticV1.semanticDigestOf compiled
  let (_, _, opened) ← mkMatchingBundle oleanPath oleanBytes sourceHash semanticHash
    "nonneg" #["Bundle", "Thm"]
  match joinProofReferencesV1 bindings opened opened.bundleDigest
      (fixedDigest 0x01) semanticHash with
  | .ok () => throw <| IO.userError "sourceHash mismatch must fail"
  | .error .sourceHashMismatch => pure ()
  | .error e => throw <| IO.userError s!"src: {renderProofReferenceJoinErrorV1 e}"
  match joinProofReferencesV1 bindings opened opened.bundleDigest
      sourceHash (fixedDigest 0x02) with
  | .ok () => throw <| IO.userError "semanticHash mismatch must fail"
  | .error .semanticHashMismatch => pure ()
  | .error e => throw <| IO.userError s!"sem: {renderProofReferenceJoinErrorV1 e}"

/-- Export set mismatch: unknown invariant / wrong theorem. -/
private def testExportMismatch : IO Unit := do
  let source ← mkProofedCounterSource
  let bindings := collectSourceProofBindingsV1 source.program
  let compiled ← match compileValidatedSourceV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile: {e.render}"
  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := ByteArray.mk #[2]
  let sourceHash := CompiledSemanticV1.sourceDigestOf compiled
  let semanticHash := CompiledSemanticV1.semanticDigestOf compiled
  -- Wrong invariant name in export
  let (_, _, opened1) ← mkMatchingBundle oleanPath oleanBytes sourceHash semanticHash
    "missing" #["Bundle", "Thm"]
  match joinProofReferencesV1 bindings opened1 opened1.bundleDigest sourceHash semanticHash with
  | .ok () => throw <| IO.userError "unknown export invariant must fail"
  | .error (.exportMismatch _) => pure ()
  | .error e => throw <| IO.userError s!"inv: {renderProofReferenceJoinErrorV1 e}"
  -- Wrong theorem components
  let (_, _, opened2) ← mkMatchingBundle oleanPath oleanBytes sourceHash semanticHash
    "nonneg" #["Other", "Thm"]
  match joinProofReferencesV1 bindings opened2 opened2.bundleDigest sourceHash semanticHash with
  | .ok () => throw <| IO.userError "theorem mismatch must fail"
  | .error (.exportMismatch _) => pure ()
  | .error e => throw <| IO.userError s!"thm: {renderProofReferenceJoinErrorV1 e}"

/-- Empty bindings + join is unused (defensive). -/
private def testJoinEmptyBindings : IO Unit := do
  let oleanPath := "modules/Bundle/Root.olean"
  let oleanBytes := ByteArray.mk #[3]
  let sh := fixedDigest 0x11
  let mh := fixedDigest 0x22
  let (_, _, opened) ← mkMatchingBundle oleanPath oleanBytes sh mh
    "truth" #["Bundle", "Thm"]
  match joinProofReferencesV1 #[] opened opened.bundleDigest sh mh with
  | .ok () => throw <| IO.userError "empty join must fail"
  | .error .unusedBundle => pure ()
  | .error e => throw <| IO.userError s!"empty: {renderProofReferenceJoinErrorV1 e}"

unsafe def run : IO Unit := do
  testPositiveProductJoin
  testMissingBundleGate
  testUnusedBundleGate
  testDigestMismatch
  testHashMismatches
  testExportMismatch
  testJoinEmptyBindings
  IO.println "Tests.Semantic.ProofReferenceJoinV1: ok"

end Tests.Semantic.ProofReferenceJoinV1
