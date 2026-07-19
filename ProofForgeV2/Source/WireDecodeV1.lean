import ProofForgeV2.Core.Unicode
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.WireDecodeV1

open ProofForgeV2.Core.Unicode
open ProofForgeV2.Source.NameComponentV1

/-- Cursor-based primitive wire decoder (SPEC-SOURCE-WIRE-001 / D1-PA-92). -/

structure CursorV1 where
  private mk ::
  private input : ByteArray
  private offset : Nat

abbrev DecoderV1 (α : Type) := CursorV1 → Except String (α × CursorV1)

def start (input : ByteArray) : CursorV1 :=
  ⟨input, 0⟩

def remaining (c : CursorV1) : Nat :=
  c.input.size - c.offset

def finish (c : CursorV1) : Except String Unit := do
  unless remaining c == 0 do
    throw "trailing bytes"
  pure ()

private def fail (detail : String) : Except String α :=
  .error detail

private def takeByte (c : CursorV1) : Except String (UInt8 × CursorV1) := do
  unless remaining c ≥ 1 do
    return ← fail "truncated"
  let b := c.input.get! c.offset
  pure (b, ⟨c.input, c.offset + 1⟩)

private def takeBytes (c : CursorV1) (n : Nat) : Except String (ByteArray × CursorV1) := do
  unless remaining c ≥ n do
    return ← fail "truncated"
  let slice := c.input.extract c.offset (c.offset + n)
  pure (slice, ⟨c.input, c.offset + n⟩)

def decodeU8 : DecoderV1 UInt8 :=
  takeByte

def decodeU16le : DecoderV1 UInt16 := fun c => do
  let (b0, c) ← takeByte c
  let (b1, c) ← takeByte c
  pure (UInt16.ofNat (b0.toNat + b1.toNat * 256), c)

def decodeU32le : DecoderV1 UInt32 := fun c => do
  let (b0, c) ← takeByte c
  let (b1, c) ← takeByte c
  let (b2, c) ← takeByte c
  let (b3, c) ← takeByte c
  let v :=
    b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat v, c)

def decodeU256le : DecoderV1 Nat := fun c => do
  unless remaining c ≥ 32 do
    return ← fail "truncated"
  let mut n : Nat := 0
  let mut c := c
  let mut place : Nat := 1
  for _ in [:32] do
    let (b, c') ← takeByte c
    c := c'
    n := n + b.toNat * place
    place := place * 256
  pure (n, c)

def decodeBool : DecoderV1 Bool := fun c => do
  let (m, c) ← decodeU8 c
  match m.toNat with
  | 0 => pure (false, c)
  | 1 => pure (true, c)
  | _ => fail "invalid bool marker"

def decodeOption (decode : DecoderV1 α) : DecoderV1 (Option α) := fun c => do
  let (m, c) ← decodeU8 c
  match m.toNat with
  | 0 => pure (none, c)
  | 1 =>
    let (v, c) ← decode c
    pure (some v, c)
  | _ => fail "invalid option marker"

def decodeArray (maxCount : Nat) (decode : DecoderV1 α) : DecoderV1 (Array α) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > maxCount then
    return ← fail "array count exceeds caller limit"
  let mut acc : Array α := Array.empty
  let mut c := c
  for _ in [:count] do
    let (v, c') ← decode c
    acc := acc.push v
    c := c'
  pure (acc, c)

def decodeString : DecoderV1 String := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  unless remaining c ≥ len do
    return ← fail "string length exceeds remaining"
  let (raw, c) ← takeBytes c len
  match String.fromUTF8? raw with
  | none => fail "invalid UTF-8"
  | some s => do
    requireNfc s
    pure (s, c)

/-- Decode raw String payload then parse as `SourceNameComponentV1` (fail closed). -/
def decodeSourceNameComponentV1 : DecoderV1 SourceNameComponentV1 := fun c => do
  let (raw, c) ← decodeString c
  match parseSourceNameComponentV1 raw with
  | .ok component => pure (component, c)
  | .error detail => fail detail

end ProofForgeV2.Source.WireDecodeV1
