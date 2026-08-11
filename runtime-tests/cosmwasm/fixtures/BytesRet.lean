import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Anonymous Bytes 4 entry/view return → 4×u8 tight value_return (N-ANON-RESULT).
-- Engineering sandbox fixture only; not formal Reference↔sandbox.
program BytesRet where
  state buf : Bytes 4

  init(a : UInt8, b : UInt8, c : UInt8, d : UInt8) do
    buf[0] := a
    buf[1] := b
    buf[2] := c
    buf[3] := d

  entry setBuf(a : UInt8, b : UInt8, c : UInt8, d : UInt8) : Bytes 4 do
    buf[0] := a
    buf[1] := b
    buf[2] := c
    buf[3] := d
    return buf

  view getBuf() : Bytes 4 do
    return buf

end Examples
