import ProofForgeV2.Core.ToolLockV4

namespace Tests.Core.ToolLockV4

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.ToolLockV4

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def identityWire (platform : ToolLockPlatformV4) : IO String := do
  let identity ← match toolLockV4IdentityForPlatform platform with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  match renderDigest identity.digest with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

def run : IO Unit := do
  expect ((← identityWire .darwinArm64) ==
    "sha256:193d706a8b274bd708f177dec54293002abe738bd6f0934482d31938031bc495")
    "Darwin Tool Lock v4 KAT"
  expect ((← identityWire .linuxX86_64) ==
    "sha256:86b0365fa62351ee7c7022d4d4b839ec716e6447253dd290639cfc2220eee831")
    "Linux Tool Lock v4 KAT"
  for target in #["aarch64-apple-darwin", "arm64-apple-darwin",
      "aarch64-apple-darwin24.6.0", "arm64-apple-darwin24.6.0"] do
    expect (toolLockPlatformForTarget? target == some .darwinArm64)
      s!"Darwin target selection: {target}"
  expect (toolLockPlatformForTarget? "x86_64-unknown-linux-gnu" == some .linuxX86_64)
    "Linux target selection"
  for target in #["x86_64-apple-darwin", "aarch64-unknown-linux-gnu",
      "x86_64-pc-windows-msvc", "aarch64-darwin",
      "aarch64-evil-darwin-junk", "aarch64-unknown-darwin-linux",
      "arm64-apple-darwin24..6", "arm64-apple-darwin24.6.",
      "arm64-apple-darwin.24", "arm64-apple-darwin24x6",
      "x86_64-linux", "x86_64-evil-linux-darwin", "unknown"] do
    expect (toolLockPlatformForTarget? target == none) s!"unsupported target: {target}"
  let active ← match embeddedToolLockV4Identity with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let selected ← match toolLockPlatformForTarget? System.Platform.target with
    | some value => pure value
    | none => throw <| IO.userError "test host must be supported"
  expect (active.platform == selected) "active Tool Lock platform"
  let raw := embeddedToolLockV4RawDigest selected
  expect (raw.bytes != active.digest.bytes) "raw lock hash is not ToolLockV4Digest"
  IO.println "Tests.Core.ToolLockV4: ok"

end Tests.Core.ToolLockV4
