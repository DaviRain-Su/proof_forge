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
    "sha256:c077b3365bf0b904be8a2bbfdbc1a64a265173b4a4385ca73d034304d0fc26d9")
    "Darwin Tool Lock v4 KAT"
  expect ((← identityWire .linuxX86_64) ==
    "sha256:b81500d18bba90d344de41b15c175f351c7c87c54c59c929a4afb641376ef191")
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
