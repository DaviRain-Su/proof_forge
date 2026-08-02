import Std

namespace ProofForgeV2.Core.ProtocolStreamV1

/-- Read one frame through EOF with a one-byte over-limit probe. The caller
    owns protocol-specific fault classification. -/
def readBoundedFrameV1
    (stream : IO.FS.Stream) (maxBytes : Nat) : IO (Except Unit ByteArray) := do
  let probeLimit := maxBytes + 1
  let chunkSize := 64 * 1024
  let mut bytes := ByteArray.empty
  let mut done := false
  while !done do
    let remainingBudget := probeLimit - bytes.size
    if remainingBudget == 0 then
      return .error ()
    let wanted := Nat.min chunkSize remainingBudget
    let chunk ← stream.read (USize.ofNat wanted)
    if chunk.isEmpty then
      done := true
    else
      bytes := bytes.append chunk
      if bytes.size > maxBytes then
        return .error ()
  pure (.ok bytes)

end ProofForgeV2.Core.ProtocolStreamV1
