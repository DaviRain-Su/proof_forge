import ProofForgeV2.CLI.Emit
import ProofForgeV2.CLI.ProductVersionV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.CLI.Emit

open ProofForgeV2 System
open ProofForgeV2.CLI.ProductVersionV1
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

unsafe def run : IO Unit := do
  -- REL-CLI-0: version / --version parse (engineering-dist; not formal Stage-0).
  match ProofForgeV2.CLI.parseProductCliCommandV1 ["version"] with
  | .ok (.version false) => pure ()
  | other => throw <| IO.userError s!"expected version command, got {repr other}"
  match ProofForgeV2.CLI.parseProductCliCommandV1 ["version", "--json"] with
  | .ok (.version true) => pure ()
  | other => throw <| IO.userError s!"expected version --json, got {repr other}"
  match ProofForgeV2.CLI.parseProductCliCommandV1 ["--version"] with
  | .ok (.version false) => pure ()
  | other => throw <| IO.userError s!"expected --version, got {repr other}"
  expect (productVersionV1 == "0.1.0")
    "productVersionV1 must match repo VERSION (0.1.0)"
  expect (productChannelV1 == "engineering-dist")
    "productChannelV1 must be engineering-dist"
  expect (renderVersionJsonV1.contains "proof-forge.cli.version.v1")
    "version JSON must carry schema id"

  -- Path-safety pure seam (package-visible). Forged artifact names cannot mint
  -- private-ctor CompiledSemanticV1, so PF-OUTPUT-PATH on emitProgram is unreachable
  -- without a public carrier factory; emitProgram still validates the compiled
  -- semantic-derived artifact name before materialization.
  expect (!ProofForgeV2.CLI.validProgramArtifactNameV1 "../escaped")
    "artifact names must not escape the staging root"
  expect (!ProofForgeV2.CLI.validProgramArtifactNameV1 "")
    "empty artifact names are unsafe"
  expect (ProofForgeV2.CLI.validProgramArtifactNameV1 "Counter")
    "legal Counter artifact name must pass path safety"

  -- Host-heavy JSON must never echo signer material or its filesystem path.
  let syntheticKey := "synthetic-private-key-value"
  let syntheticKeyPath := "/tmp/synthetic-account.key"
  let syntheticRecord := "synthetic-record-value"
  let syntheticInlineRecord := "synthetic-inline-record-value"
  let syntheticFeeRecord := "synthetic-fee-record-value"
  let syntheticInlineFeeRecord := "synthetic-inline-fee-record-value"
  let rawArgs := #[
    "--network", "testnet",
    "--private-key", syntheticKey,
    s!"--private-key-file={syntheticKeyPath}",
    "--priv-key", "abbrev-private-key-value",
    "--record", syntheticRecord,
    s!"--record={syntheticInlineRecord}",
    "--fee-record", syntheticFeeRecord,
    s!"--fee-record={syntheticInlineFeeRecord}",
    "--signer-fd", "7"
  ]
  let publicArgs := ProofForgeV2.CLI.redactHostHeavyArgsV1 rawArgs
  expect (!publicArgs.contains syntheticKey)
    "host-heavy JSON argv projection must redact raw private keys"
  expect (!publicArgs.contains s!"--private-key-file={syntheticKeyPath}")
    "host-heavy JSON argv projection must redact private-key paths"
  expect (!publicArgs.contains "abbrev-private-key-value")
    "host-heavy JSON argv projection must redact private-key-like abbreviated flag values"
  expect (!publicArgs.contains syntheticRecord)
    "host-heavy JSON argv projection must redact split record values"
  expect (!publicArgs.contains s!"--record={syntheticInlineRecord}")
    "host-heavy JSON argv projection must redact inline record values"
  expect (!publicArgs.contains syntheticFeeRecord)
    "host-heavy JSON argv projection must redact split fee-record values"
  expect (!publicArgs.contains s!"--fee-record={syntheticInlineFeeRecord}")
    "host-heavy JSON argv projection must redact inline fee-record values"
  expect (publicArgs.contains "--private-key-file=<redacted>")
    "host-heavy JSON argv projection must retain a redacted flag shape"
  expect (publicArgs.contains "--priv-key")
    "host-heavy JSON argv projection must retain a redacted abbreviated flag shape"
  expect (publicArgs.contains "--record=<redacted>")
    "host-heavy JSON argv projection must retain inline record flag shape"
  expect (publicArgs.contains "--fee-record")
    "host-heavy JSON argv projection must retain split fee-record flag shape"
  expect (publicArgs.contains "--fee-record=<redacted>")
    "host-heavy JSON argv projection must retain inline fee-record flag shape"
  expect (publicArgs.contains "7")
    "signer FD numbers are not signer material and remain observable"
  expect (ProofForgeV2.CLI.containsSensitiveHostHeavyArgsV1 rawArgs)
    "host-heavy argv classifier must detect signer-bearing values"
  expect (!ProofForgeV2.CLI.containsSensitiveHostHeavyArgsV1 #["--signer-fd", "7"])
    "descriptor numbers remain public-safe even when command policy rejects their capability"
  let rawText := s!"failed key={syntheticKey} path={syntheticKeyPath} abbrev=abbrev-private-key-value record={syntheticRecord} inlineRecord={syntheticInlineRecord} fee={syntheticFeeRecord} inlineFee={syntheticInlineFeeRecord} fd=7"
  let publicText := ProofForgeV2.CLI.redactHostHeavyTextV1 rawArgs rawText
  expect (!((publicText.splitOn syntheticKey).length > 1))
    "host-heavy JSON stream projection must redact raw private keys"
  expect (!((publicText.splitOn syntheticKeyPath).length > 1))
    "host-heavy JSON stream projection must redact private-key paths"
  expect (!((publicText.splitOn "abbrev-private-key-value").length > 1))
    "host-heavy JSON stream projection must redact abbreviated private-key-like values"
  expect (!((publicText.splitOn syntheticRecord).length > 1))
    "host-heavy JSON stream projection must redact split record values"
  expect (!((publicText.splitOn syntheticInlineRecord).length > 1))
    "host-heavy JSON stream projection must redact inline record values"
  expect (!((publicText.splitOn syntheticFeeRecord).length > 1))
    "host-heavy JSON stream projection must redact split fee-record values"
  expect (!((publicText.splitOn syntheticInlineFeeRecord).length > 1))
    "host-heavy JSON stream projection must redact inline fee-record values"
  expect ((publicText.splitOn "fd=7").length > 1)
    "host-heavy stream projection must not redact signer FD numbers"
  let shortSecretText := ProofForgeV2.CLI.redactHostHeavyTextV1
    #["--private-key", "abc"] "short=abc"
  expect (!((shortSecretText.splitOn "abc").length > 1))
    "host-heavy stream projection must redact even short signer values"

  let session ← Tests.Language.ParserSession.shared
  let source ← match ← session.selectProgramV1
      Examples.counterSourceText "<cli-emit-counter>" Examples.counterModuleNameV1 none with
    | .ok s => pure s
    | .error e => throw <| IO.userError e.render
  let compiled ← match Compiler.compileValidatedSourceV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError e.render
  -- Real product carrier: the semantic-derived artifact name is the identity
  -- emitProgram gates. Counter must be accepted so later PF-OUTPUT-COLLISION is
  -- not masked by a path-safety failure.
  let artifactName := CompiledSemanticV1.artifactProgramNameOf compiled
  expect (artifactName == "Counter")
    "Counter semantic suffix must be the product artifact identity"
  expect (ProofForgeV2.CLI.validProgramArtifactNameV1 artifactName)
    "emitProgram artifact name must pass the same path-safety predicate"

  let collision := FilePath.mk "build/v2/existing-output"
  if ← collision.pathExists then IO.FS.removeDirAll collision
  IO.FS.createDirAll collision
  IO.FS.writeFile (collision / "important.txt") "preserve-me\n"
  let collisionRejected ←
    try
      let sel ← match resolveBuildSelectionV1 TargetId.solana none with
        | .ok s => pure s
        | .error e => throw <| IO.userError e.render
      let capability ← match Targets.resolveEngineeringRequirementsV1 sel compiled with
        | .ok c => pure c
        | .error e => throw <| IO.userError e.render
      let _ ← ProofForgeV2.CLI.emitProgram capability collision
      pure false
    catch error =>
      pure (decide (((toString error).splitOn "PF-OUTPUT-COLLISION").length > 1))
  expect collisionRejected "an existing output directory must be rejected without replacement"
  expect ((← IO.FS.readFile (collision / "important.txt")) == "preserve-me\n")
    "output collision must preserve pre-existing files"

  -- Host-locked env isolation pins darwin-arm64 system tool digests
  -- (host:stat / env). Portable Linux CI and unprofiled hosts must not run it.
  -- Full local gate: `PROOF_FORGE_HOST_ISOLATION_TEST=1 just test` or `just check`.
  match ← IO.getEnv "PROOF_FORGE_HOST_ISOLATION_TEST" with
  | some "1" =>
      ProofForgeV2.Materialization.LockedToolchainV1.environmentIsolationSelfTest
  | _ => pure ()

end Tests.CLI.Emit
