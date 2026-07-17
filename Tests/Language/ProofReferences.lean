import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.ProofReferencesFixture

open ProofForgeV2.Language

program ProofSurface where
  proof BalanceHolds using ProofForge.Specs.BalanceHolds
  invariant BalanceHolds : 1
  proof CounterHolds using ProofForge.Specs.Counter.Holds
  invariant CounterHolds : 2

  entry ping() : UInt64 do
    return 0

end Tests.Language.ProofReferencesFixture

namespace Tests.Language.ProofReferences

open ProofForgeV2

private def proof : Nat := 1
private def «using» : Nat := 2

private def digestA : String :=
  "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

private def digestB : String :=
  "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def invariantDecl (name value : String) : String :=
  "  invariant " ++ name ++ " : " ++ value ++ "\n"

private def proofRef (invariant theoremName : String) : String :=
  "  proof " ++ invariant ++ " using " ++ theoremName ++ "\n"

private def extensionReq (version digest : String) : String :=
  "  requires extension near.promise version \"" ++ version ++ "\"\n" ++
  "    digest \"" ++ digest ++ "\"\n"

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ProofReferencesFixture\n\n" ++
  "program ProofSurface where\n" ++
  proofRef "BalanceHolds" "ProofForge.Specs.BalanceHolds" ++
  invariantDecl "BalanceHolds" "1" ++
  proofRef "CounterHolds" "ProofForge.Specs.Counter.Holds" ++
  invariantDecl "CounterHolds" "2" ++
  "\n  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.ProofReferencesFixture\n"

private def programSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private def expectInvalid (label expected : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}'"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  expect (proof + «using» == 3)
    "proof and Lean's escaped using identifier must remain legal outside the DSL"

  let elaborated := Tests.Language.ProofReferencesFixture.ProofSurface
  match elaborated.proofReferences with
  | #[balance, counter] =>
      expect (balance.invariant == "BalanceHolds" &&
          balance.«theorem» == #["ProofForge", "Specs", "BalanceHolds"])
        "proof invariant and exact theorem components must survive Lean elaboration"
      expect (counter.invariant == "CounterHolds" &&
          counter.«theorem» == #["ProofForge", "Specs", "Counter", "Holds"])
        "proof theorem component count/value/order and declaration order must survive"
  | _ => throw <| IO.userError "ProofSurface must retain two proof references"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<proof-references>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same proof-reference Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same proof-reference source hash"

  let invariants := invariantDecl "A" "1" ++ invariantDecl "B" "2"
  let base ← select session
    (programSource "CanonicalProof" invariants) "<proof-base>"
  let proofA ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "A" "Pkg.Theorem"))
    "<proof-a>"
  let proofB ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "B" "Pkg.Theorem"))
    "<proof-b>"
  let theoremCount ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "A" "Pkg.Sub.Theorem"))
    "<proof-theorem-count>"
  let theoremValue ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "A" "Pkg.Other"))
    "<proof-theorem-value>"
  let theoremOrderAB ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "A" "Pkg.Left.Right"))
    "<proof-theorem-order-ab>"
  let theoremOrderBA ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "A" "Pkg.Right.Left"))
    "<proof-theorem-order-ba>"
  let proofsAB ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "A" "Pkg.Left" ++ proofRef "B" "Pkg.Right"))
    "<proofs-ab>"
  let proofsBA ← select session
    (programSource "CanonicalProof"
      (invariants ++ proofRef "B" "Pkg.Right" ++ proofRef "A" "Pkg.Left"))
    "<proofs-ba>"

  expect (base.sourceHash != proofA.sourceHash && proofA.sourceHash != proofsAB.sourceHash)
    "proof presence and same-prefix reference count must bind the source hash"
  expect (proofA.sourceHash != proofB.sourceHash)
    "proof invariant identity must bind the source hash"
  expect (proofA.sourceHash != theoremCount.sourceHash &&
      proofA.sourceHash != theoremValue.sourceHash &&
      theoremOrderAB.sourceHash != theoremOrderBA.sourceHash)
    "theorem component count, value, and order must bind the source hash"
  expect (proofsAB.sourceHash != proofsBA.sourceHash)
    "proof declaration order must bind the source hash"

  let forward ← select session
    (programSource "ForwardProof"
      (proofRef "Later" "Pkg.Later" ++ invariantDecl "Later" "1"))
    "<forward-proof>"
  expect (forward.proofReferences.map (fun reference => reference.invariant) == #["Later"])
    "proof references must bind exact forward-declared invariants"

  expectInvalid "duplicate proof reference with identical theorem"
    "program 'DuplicateProofReference' contains duplicate proof references"
    (← session.parsePrograms
      (programSource "DuplicateProofReference"
        (invariantDecl "Holds" "1" ++ proofRef "Holds" "Pkg.Theorem" ++
          proofRef "Holds" "Pkg.Theorem"))
      "<duplicate-proof-reference>")
  expectInvalid "duplicate proof reference with conflicting theorem"
    "program 'DuplicateProofReferenceConflict' contains duplicate proof references"
    (← session.parsePrograms
      (programSource "DuplicateProofReferenceConflict"
        (invariantDecl "Holds" "1" ++ proofRef "Holds" "Pkg.First" ++
          proofRef "Holds" "Pkg.Second"))
      "<duplicate-proof-reference-conflict>")
  expectInvalid "unknown proof invariant"
    "proof reference names unknown invariant 'Missing'"
    (← session.parsePrograms
      (programSource "UnknownProofInvariant" (proofRef "Missing" "Pkg.Theorem"))
      "<unknown-proof-invariant>")
  expectInvalid "unqualified proof theorem"
    "proof theorem name must contain at least two components"
    (← session.parsePrograms
      (programSource "UnqualifiedProofTheorem"
        (invariantDecl "Holds" "1" ++ proofRef "Holds" "Theorem"))
      "<unqualified-proof-theorem>")
  expectInvalid "escaped proof keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedProofKeyword"
        (invariantDecl "Holds" "1" ++
          "  «proof» Holds using Pkg.Theorem\n"))
      "<escaped-proof-keyword>")
  expectInvalid "whole escaped dotted theorem"
    "qualified-name component must use Lean identifier characters"
    (← session.parsePrograms
      (programSource "EscapedDottedProofTheorem"
        (invariantDecl "Holds" "1" ++
          "  proof Holds using «Pkg.Theorem»\n"))
      "<escaped-dotted-proof-theorem>")
  expectInvalid "reserved proof invariant" "reserved portable identifier 'proof'"
    (← session.parsePrograms
      (programSource "ReservedProofInvariant"
        (invariantDecl "Holds" "1" ++ proofRef "proof" "Pkg.Theorem"))
      "<reserved-proof-invariant>")
  expectInvalid "extension duplicate precedes proof duplicate"
    "program 'PriorityExtensionBeforeProof' contains duplicate extension requirements"
    (← session.parsePrograms
      (programSource "PriorityExtensionBeforeProof"
        (extensionReq "1.0.0" digestA ++ extensionReq "2.0.0" digestB ++
          invariantDecl "Holds" "1" ++ proofRef "Holds" "Pkg.First" ++
          proofRef "Holds" "Pkg.Second"))
      "<priority-extension-before-proof>")
  expectInvalid "proof duplicate precedes unknown invariant"
    "program 'PriorityProofBeforeUnknown' contains duplicate proof references"
    (← session.parsePrograms
      (programSource "PriorityProofBeforeUnknown"
        (invariantDecl "Holds" "1" ++ proofRef "Holds" "Pkg.First" ++
          proofRef "Holds" "Pkg.Second" ++ proofRef "Missing" "Pkg.Missing"))
      "<priority-proof-before-unknown>")
  expectInvalid "unknown invariant precedes initializer parameter duplicate"
    "proof reference names unknown invariant 'Missing'"
    (← session.parsePrograms
      (programSource "PriorityUnknownBeforeInitializerParam"
        (proofRef "Missing" "Pkg.Missing" ++
          "  init(value : UInt64, value : Bool) do\n    return 0\n"))
      "<priority-unknown-before-initializer-param>")
  expectInvalid "proof invariant precedes theorem decoding"
    "reserved portable identifier 'proof'"
    (← session.parsePrograms
      (programSource "PriorityProofInvariantBeforeTheorem"
        "  proof proof using «Pkg.Invalid.Theorem»\n")
      "<priority-proof-invariant-before-theorem>")

  let proofOnly : Source.Program := {
    qualifiedName := "Tests.Language.ProofOnly"
    name := "ProofOnly"
    «state» := #[]
    initializer := none
    entries := #[{
      name := "ping"
      params := #[]
      result := .u64
      mode := .mutate
      body := #[.returnValue (.literal 0)]
    }]
    proofReferences := #[{
      invariant := "Holds"
      «theorem» := #["Pkg", "Theorem"]
    }]
  }
  match Typed.check proofOnly with
  | .error (.invalidProgram "proof references are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError s!"proof references reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase proof references"
  match Compiler.compile proofOnly with
  | .error (.invalidProgram "proof references are not yet supported by typed checking") =>
      pure ()
  | .error other =>
      throw <| IO.userError s!"proof references bypassed the wrong compiler boundary: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not bypass proof fail-closed checking"

end Tests.Language.ProofReferences
