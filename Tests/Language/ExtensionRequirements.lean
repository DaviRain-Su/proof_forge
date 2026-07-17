import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.ExtensionRequirementsFixture

open ProofForgeV2.Language

program ExtensionSurface where
  requires extension near.promise version "1.0.0-alpha.1+build.7"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  requires extension state.map version "2.3.4"
    digest "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

  entry ping() : UInt64 do
    return 0

end Tests.Language.ExtensionRequirementsFixture

namespace Tests.Language.ExtensionRequirements

open ProofForgeV2

private def requires : Nat := 1
private def extension : Nat := 2
private def version : Nat := 4
private def digest : Nat := 8

private def digestA : String :=
  "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

private def digestB : String :=
  "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def requirement (id version digest : String) : String :=
  "  requires extension " ++ id ++ " version \"" ++ version ++ "\"\n" ++
  "    digest \"" ++ digest ++ "\"\n"

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.ExtensionRequirementsFixture\n\n" ++
  "program ExtensionSurface where\n" ++
  requirement "near.promise" "1.0.0-alpha.1+build.7" digestA ++
  requirement "state.map" "2.3.4" digestB ++
  "\n  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.ExtensionRequirementsFixture\n"

private def programSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private def programWithoutEntrySource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations

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
  expect (requires + extension + version + digest == 15)
    "extension requirement words must remain legal host Lean identifiers"

  let elaborated := Tests.Language.ExtensionRequirementsFixture.ExtensionSurface
  match elaborated.extensionRequirements with
  | #[promise, stateMap] =>
      expect (promise.id == "near.promise" &&
          promise.version == "1.0.0-alpha.1+build.7" && promise.digest == digestA)
        "extension id, full SemVer identity, and digest must survive Lean elaboration"
      expect (stateMap.id == "state.map" && stateMap.version == "2.3.4" &&
          stateMap.digest == digestB)
        "multiple extension requirements must retain their source order"
  | _ => throw <| IO.userError "ExtensionSurface must retain two extension requirements"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<extension-requirements>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same extension Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same extension source hash"

  let base ← select session
    (programSource "CanonicalExtension" "") "<extension-base>"
  let extensionOne ← select session
    (programSource "CanonicalExtension"
      (requirement "near.promise" "1.0.0-alpha.1+build.7" digestA))
    "<extension-one>"
  let extensionId ← select session
    (programSource "CanonicalExtension"
      (requirement "near.workflow" "1.0.0-alpha.1+build.7" digestA))
    "<extension-id>"
  let extensionVersion ← select session
    (programSource "CanonicalExtension"
      (requirement "near.promise" "1.0.1-alpha.1+build.7" digestA))
    "<extension-version>"
  let extensionBuild ← select session
    (programSource "CanonicalExtension"
      (requirement "near.promise" "1.0.0-alpha.1+build.8" digestA))
    "<extension-build>"
  let extensionDigest ← select session
    (programSource "CanonicalExtension"
      (requirement "near.promise" "1.0.0-alpha.1+build.7" digestB))
    "<extension-digest>"
  let extensionsAB ← select session
    (programSource "CanonicalExtension"
      (requirement "near.promise" "1.0.0-alpha.1+build.7" digestA ++
        requirement "state.map" "2.3.4" digestB))
    "<extensions-ab>"
  let extensionsBA ← select session
    (programSource "CanonicalExtension"
      (requirement "state.map" "2.3.4" digestB ++
        requirement "near.promise" "1.0.0-alpha.1+build.7" digestA))
    "<extensions-ba>"

  expect (base.sourceHash != extensionOne.sourceHash &&
      extensionOne.sourceHash != extensionsAB.sourceHash)
    "extension presence and same-prefix declaration count must bind the source hash"
  expect (extensionOne.sourceHash != extensionId.sourceHash &&
      extensionOne.sourceHash != extensionVersion.sourceHash &&
      extensionOne.sourceHash != extensionBuild.sourceHash &&
      extensionOne.sourceHash != extensionDigest.sourceHash)
    "extension id, full version including build metadata, and digest must bind independently"
  expect (extensionsAB.sourceHash != extensionsBA.sourceHash)
    "extension declaration order must bind the source hash"

  expectInvalid "extension does not satisfy the entry/view requirement"
    "program 'ExtensionOnly' must declare at least one entry or view"
    (← session.parsePrograms
      (programWithoutEntrySource "ExtensionOnly"
        (requirement "near.promise" "1.0.0" digestA))
      "<extension-only>")
  expectInvalid "duplicate extension id with identical identity"
    "program 'DuplicateExtensionSame' contains duplicate extension requirements"
    (← session.parsePrograms
      (programSource "DuplicateExtensionSame"
        (requirement "near.promise" "1.0.0" digestA ++
          requirement "near.promise" "1.0.0" digestA))
      "<duplicate-extension-same>")
  expectInvalid "duplicate extension id with conflicting identity"
    "program 'DuplicateExtensionConflict' contains duplicate extension requirements"
    (← session.parsePrograms
      (programSource "DuplicateExtensionConflict"
        (requirement "near.promise" "1.0.0" digestA ++
          requirement "near.promise" "2.0.0" digestB))
      "<duplicate-extension-conflict>")
  expectInvalid "invariant duplicate precedes extension duplicate"
    "program 'PriorityInvariantBeforeExtension' contains duplicate invariant declarations"
    (← session.parsePrograms
      (programSource "PriorityInvariantBeforeExtension"
        ("  invariant Holds : 1\n  invariant Holds : 2\n" ++
          requirement "near.promise" "1.0.0" digestA ++
          requirement "near.promise" "2.0.0" digestB))
      "<priority-invariant-before-extension>")
  expectInvalid "extension duplicate precedes initializer parameter duplicate"
    "program 'PriorityExtensionBeforeInitializerParam' contains duplicate extension requirements"
    (← session.parsePrograms
      (programSource "PriorityExtensionBeforeInitializerParam"
        (requirement "near.promise" "1.0.0" digestA ++
          requirement "near.promise" "2.0.0" digestB ++
          "  init(value : UInt64, value : Bool) do\n    return 0\n"))
      "<priority-extension-before-initializer-param>")
  expectInvalid "escaped requires keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedRequiresKeyword"
        "  «requires» extension near.promise version \"1.0.0\"\n    digest \"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"\n")
      "<escaped-requires-keyword>")
  expectInvalid "malformed extension id" "extension id has an invalid segment"
    (← session.parsePrograms
      (programSource "MalformedExtensionId"
        (requirement "near.promise_bad" "1.0.0" digestA))
      "<malformed-extension-id>")
  expectInvalid "uppercase extension id" "extension id has an invalid segment"
    (← session.parsePrograms
      (programSource "UppercaseExtensionId"
        (requirement "Near.promise" "1.0.0" digestA))
      "<uppercase-extension-id>")
  expectInvalid "single-segment extension id"
    "extension id must contain at least one dot"
    (← session.parsePrograms
      (programSource "SingleSegmentExtensionId"
        (requirement "promise" "1.0.0" digestA))
      "<single-segment-extension-id>")
  expectInvalid "malformed extension SemVer" "semver core requires major.minor.patch"
    (← session.parsePrograms
      (programSource "MalformedExtensionSemver"
        (requirement "near.promise" "1.0" digestA))
      "<malformed-extension-semver>")
  expectInvalid "v-prefixed extension SemVer" "v prefix forbidden"
    (← session.parsePrograms
      (programSource "VPrefixExtensionSemver"
        (requirement "near.promise" "v1.0.0" digestA))
      "<vprefix-extension-semver>")
  expectInvalid "range extension SemVer" "numeric component must contain ASCII digits only"
    (← session.parsePrograms
      (programSource "RangeExtensionSemver"
        (requirement "near.promise" "^1.0.0" digestA))
      "<range-extension-semver>")
  expectInvalid "latest extension SemVer" "semver core requires major.minor.patch"
    (← session.parsePrograms
      (programSource "LatestExtensionSemver"
        (requirement "near.promise" "latest" digestA))
      "<latest-extension-semver>")
  expectInvalid "wildcard extension SemVer" "numeric component must contain ASCII digits only"
    (← session.parsePrograms
      (programSource "WildcardExtensionSemver"
        (requirement "near.promise" "1.*.0" digestA))
      "<wildcard-extension-semver>")
  expectInvalid "leading-zero extension SemVer" "leading zero forbidden"
    (← session.parsePrograms
      (programSource "LeadingZeroExtensionSemver"
        (requirement "near.promise" "01.0.0" digestA))
      "<leading-zero-extension-semver>")
  expectInvalid "overflowing extension SemVer" "numeric component exceeds UInt64"
    (← session.parsePrograms
      (programSource "OverflowExtensionSemver"
        (requirement "near.promise" "18446744073709551616.0.0" digestA))
      "<overflow-extension-semver>")
  expectInvalid "bare extension digest" "digest must use sha256: tag"
    (← session.parsePrograms
      (programSource "BareExtensionDigest"
        (requirement "near.promise" "1.0.0"
          "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"))
      "<bare-extension-digest>")
  expectInvalid "uppercase extension digest"
    "digest hex must be lowercase [0-9a-f]"
    (← session.parsePrograms
      (programSource "UppercaseExtensionDigest"
        (requirement "near.promise" "1.0.0"
          "sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
      "<uppercase-extension-digest>")
  expectInvalid "wrong-length extension digest"
    "digest hex must be exactly 64 lowercase characters"
    (← session.parsePrograms
      (programSource "WrongLengthExtensionDigest"
        (requirement "near.promise" "1.0.0" "sha256:00"))
      "<wrong-length-extension-digest>")
  expectInvalid "extension id precedes version and digest decoding"
    "extension id has an invalid segment"
    (← session.parsePrograms
      (programSource "PriorityExtensionIdBeforeVersionDigest"
        (requirement "Near.promise" "v1.0.0" "bad"))
      "<priority-extension-id-before-version-digest>")
  expectInvalid "extension version precedes digest decoding" "v prefix forbidden"
    (← session.parsePrograms
      (programSource "PriorityExtensionVersionBeforeDigest"
        (requirement "near.promise" "v1.0.0" "bad"))
      "<priority-extension-version-before-digest>")

  match Typed.check elaborated with
  | .error (.invalidProgram
      "extension requirements are not yet supported by typed checking") => pure ()
  | .error other =>
      throw <| IO.userError s!"extension requirements reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase extension requirements"
  match Compiler.compile elaborated with
  | .error (.invalidProgram
      "extension requirements are not yet supported by typed checking") => pure ()
  | .error other =>
      throw <| IO.userError s!"extension requirements bypassed the wrong compiler boundary: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not bypass extension fail-closed checking"

end Tests.Language.ExtensionRequirements
