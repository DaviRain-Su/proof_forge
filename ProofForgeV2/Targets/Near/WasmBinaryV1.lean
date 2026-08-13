/-
  Bounded structural consumer for finalized NEAR Wasm binaries.

  This module validates the core Wasm header and canonical section envelope
  emitted by the locked WABT path. It deliberately does not decode section
  payloads, execute Wasm, or assert that `wat2wasm` preserves typed-WAT
  semantics.
-/

namespace ProofForgeV2.Targets.Near

/-- Closed structural errors for the bounded core-Wasm binary envelope. -/
inductive WasmBinaryErrorV1 where
  | truncated
  | invalidMagic
  | unsupportedVersion
  | invalidSectionId (id : UInt8)
  | sectionOrder (id : UInt8)
  | lebOverflow
  | noncanonicalLeb
  | sectionPayloadOutOfBounds
  deriving BEq, Repr

/-- Exact source position and payload extent of one decoded section. Payloads
    remain bytes until a semantics-bearing external backend is selected. -/
structure WasmSectionEnvelopeV1 where
  id : UInt8
  headerOffset : Nat
  payloadOffset : Nat
  payloadSize : Nat
  deriving BEq, Repr, Inhabited

private def byteAt (bytes : ByteArray) (offset : Nat) :
    Except WasmBinaryErrorV1 UInt8 :=
  match bytes.data[offset]? with
  | some byte => .ok byte
  | none => .error .truncated

private def decodeU32LebLoop
    (bytes : ByteArray)
    (offset shift remainingBytes : Nat)
    (value : Nat) : Except WasmBinaryErrorV1 (Nat × Nat) :=
  match remainingBytes with
  | 0 => .error .lebOverflow
  | nextRemaining + 1 => do
    let byte ← byteAt bytes offset
    let payload := byte.toNat % 128
    if shift = 28 && payload > 15 then
      throw .lebOverflow
    let value := value + payload * 2 ^ shift
    if byte.toNat < 128 then
      if shift > 0 && payload = 0 then
        throw .noncanonicalLeb
      pure (value, offset + 1)
    else if shift = 28 then
      throw .lebOverflow
    else
      decodeU32LebLoop bytes (offset + 1) (shift + 7) nextRemaining value
termination_by remainingBytes

/-- Canonical unsigned LEB128 decoder for Wasm `u32` section lengths. -/
def decodeWasmU32LebV1 (bytes : ByteArray) (offset : Nat) :
    Except WasmBinaryErrorV1 (Nat × Nat) :=
  decodeU32LebLoop bytes offset 0 5 0

/-- Core section rank. DataCount (id 12) is ordered immediately before Code,
    as required by the Wasm binary format rather than by numeric id order. -/
private def coreSectionRankV1 (id : UInt8) : Option Nat :=
  match id.toNat with
  | 1 => some 1
  | 2 => some 2
  | 3 => some 3
  | 4 => some 4
  | 5 => some 5
  | 6 => some 6
  | 7 => some 7
  | 8 => some 8
  | 9 => some 9
  | 12 => some 10
  | 10 => some 11
  | 11 => some 12
  | _ => none

private def decodeWasmSectionsLoopV1
    (bytes : ByteArray)
    (offset lastRank fuel : Nat)
    (sections : Array WasmSectionEnvelopeV1) :
    Except WasmBinaryErrorV1 (Array WasmSectionEnvelopeV1) := do
  if offset = bytes.size then
    pure sections
  else
    match fuel with
    | 0 => throw .sectionPayloadOutOfBounds
    | nextFuel + 1 =>
      let id ← byteAt bytes offset
      let (payloadSize, payloadOffset) ← decodeWasmU32LebV1 bytes (offset + 1)
      let payloadEnd := payloadOffset + payloadSize
      if payloadEnd > bytes.size then
        throw .sectionPayloadOutOfBounds
      let nextRank ←
        if id = 0 then
          pure lastRank
        else
          match coreSectionRankV1 id with
          | none => throw (.invalidSectionId id)
          | some rank =>
            if rank ≤ lastRank then
              throw (.sectionOrder id)
            else
              pure rank
      let entry : WasmSectionEnvelopeV1 := {
        id
        headerOffset := offset
        payloadOffset
        payloadSize
      }
      decodeWasmSectionsLoopV1 bytes payloadEnd nextRank nextFuel
        (sections.push entry)
termination_by fuel

private def hasCoreWasmHeaderV1 (bytes : ByteArray) : Bool :=
  bytes.size ≥ 8 &&
    bytes[0]! == 0x00 && bytes[1]! == 0x61 && bytes[2]! == 0x73 &&
    bytes[3]! == 0x6d

private def hasCoreWasmVersionV1 (bytes : ByteArray) : Bool :=
  bytes.size ≥ 8 &&
    bytes[4]! == 0x01 && bytes[5]! == 0x00 && bytes[6]! == 0x00 &&
    bytes[7]! == 0x00

/-- Decode the exact bounded core-Wasm module envelope. Every byte belongs to
    the header or one size-delimited section; non-custom sections are unique
    and canonically ordered, and section lengths use minimal u32 LEB128. -/
def decodeWasmBinaryModuleV1 (bytes : ByteArray) :
    Except WasmBinaryErrorV1 (Array WasmSectionEnvelopeV1) := do
  unless hasCoreWasmHeaderV1 bytes do
    throw .invalidMagic
  unless hasCoreWasmVersionV1 bytes do
    throw .unsupportedVersion
  decodeWasmSectionsLoopV1 bytes 8 0 (bytes.size - 8) #[]

end ProofForgeV2.Targets.Near
