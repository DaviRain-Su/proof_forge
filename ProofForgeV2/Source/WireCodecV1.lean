import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

namespace ProofForgeV2.Source.WireCodecV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Little-endian portable source-wire primitive codecs (SPEC-SOURCE-WIRE-001). -/

def encodeU8 (value : UInt8) : ByteArray :=
  ByteArray.empty.push value

def encodeU16le (value : UInt16) : ByteArray :=
  let v := value.toNat
  (ByteArray.empty.push (UInt8.ofNat (v % 256))).push (UInt8.ofNat ((v / 256) % 256))

def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

def encodeBool (value : Bool) : ByteArray :=
  encodeU8 (if value then 1 else 0)

private def fail (detail : String) : Except String α :=
  .error detail

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    return ← fail "u32 length is not representable"
  pure (encodeU32le (UInt32.ofNat count))

private def encodeNatAsU16le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt16.size - 1 do
    return ← fail "u16 length is not representable"
  pure (encodeU16le (UInt16.ofNat count))

def encodeU256le (value : Nat) : Except String ByteArray := do
  unless value < 2 ^ 256 do
    return ← fail "u256 magnitude exceeds 2^256-1"
  let mut bytes := ByteArray.emptyWithCapacity 32
  let mut n := value
  for _ in [:32] do
    bytes := bytes.push (UInt8.ofNat (n % 256))
    n := n / 256
  pure bytes

def encodeOption (encode : α → Except String ByteArray) :
    Option α → Except String ByteArray
  | none => pure (encodeU8 0)
  | some value => do
      let payload ← encode value
      pure ((encodeU8 1).append payload)

def encodeArray (encode : α → Except String ByteArray)
    (values : Array α) : Except String ByteArray := do
  let header ← encodeNatAsU32le values.size
  let mut payload := ByteArray.empty
  for value in values do
    let chunk ← encode value
    payload := payload.append chunk
  pure (header.append payload)

def encodeString (value : String) : Except String ByteArray := do
  requireNfc value
  let raw := value.toUTF8
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

/-- Ident wire = NFC string with Common qualified-name component validation. -/
def encodeIdent (value : String) : Except String ByteArray := do
  let _ ← parseQualifiedName #[value]
  encodeString value

def encodeQualifiedName (name : QualifiedName) : Except String ByteArray := do
  let components ← renderQualifiedNameComponents name
  encodeArray encodeIdent components

def encodeQualifiedId (name : QualifiedName) : Except String ByteArray := do
  let components ← renderQualifiedNameComponents name
  unless 2 ≤ components.size && components.size ≤ 256 do
    return ← fail "qualified-id must contain 2..256 components"
  encodeArray encodeIdent components

private def isAsciiTag (tag : String) : Bool := Id.run do
  for c in tag.toList do
    unless (c : Char).val ≤ 127 do
      return false
  return true

def encodeTagged (tag : String) (fields : Array ByteArray) :
    Except String ByteArray := do
  if tag.isEmpty then
    return ← fail "tag must be nonempty"
  unless isAsciiTag tag do
    return ← fail "tag must be ASCII"
  let tagBytes := tag.toUTF8
  let tagLen ← encodeNatAsU32le tagBytes.size
  let fieldCount ← encodeNatAsU16le fields.size
  let mut out := (tagLen.append tagBytes).append fieldCount
  for field in fields do
    out := out.append field
  pure out

end ProofForgeV2.Source.WireCodecV1
