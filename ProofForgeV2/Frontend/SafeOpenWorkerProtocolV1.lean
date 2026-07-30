/-
  ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1 — B11b2 safe-open worker wire.

  Closed one-frame binary protocol for the standalone safe-open helper process.
  Cycle-free from Darwin supervisor / frontend parser worker:

    SafeOpen.Req.v1  — trusted absolute root + ProjectRelativePath + maxSourceBytes
    SafeOpen.Ok.v1   — requestDigest + exact source snapshot bytes (≤ maxSourceBytes)
    SafeOpen.Err.v1  — requestDigest + closed SafeOpenFault wire label

  Every response is bound to the exact canonical request to reject cross-request replay.
  Full-consume + exact re-encode identity. No ProgramV1 decoder, no receipt
  fields, no path retention beyond the request root/relative needed to open.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Frontend.SafeOpenV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.SafeOpenV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1
open System

private def tagRequestV1 : String := "SafeOpen.Req.v1"
private def tagSuccessV1 : String := "SafeOpen.Ok.v1"
private def tagFailureV1 : String := "SafeOpen.Err.v1"

/-- Protocol frame hard maximum (reuse frontend protocol cap). -/
def maxSafeOpenProtocolBytesV1 : Nat := maxProtocolBytes

/-- Domain for binding every SafeOpen.Ok/Err.v1 to its exact canonical request. -/
def safeOpenWorkerRequestDigestDomainV1 : String :=
  "proof-forge.frontend-safe-open-request.v1"

private def fail (detail : String) : Except String α :=
  .error detail

private def encodeRawUtf8 (maxLen : Nat) (value : String) : Except String ByteArray := do
  let raw := value.toUTF8
  unless raw.size ≤ maxLen do
    return ← fail s!"utf-8 payload exceeds {maxLen}"
  unless raw.size ≤ UInt32.size - 1 do
    return ← fail "utf-8 payload length is not representable"
  pure ((encodeU32le (UInt32.ofNat raw.size)).append raw)

private def decodeRawUtf8 (maxLen : Nat) : DecoderV1 String := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  if len > maxLen then
    return ← fail s!"utf-8 payload count exceeds {maxLen}"
  unless remaining c ≥ len do
    return ← fail "truncated"
  let mut acc := ByteArray.emptyWithCapacity len
  let mut c := c
  for _ in [:len] do
    let (b, c') ← decodeU8 c
    acc := acc.push b
    c := c'
  match String.fromUTF8? acc with
  | none => fail "invalid UTF-8"
  | some s => pure (s, c)

private def encodeBoundedBytes (maxLen : Nat) (bytes : ByteArray) :
    Except String ByteArray := do
  unless bytes.size ≤ maxLen do
    return ← fail s!"byte payload exceeds {maxLen}"
  unless bytes.size ≤ UInt32.size - 1 do
    return ← fail "byte payload length is not representable"
  pure ((encodeU32le (UInt32.ofNat bytes.size)).append bytes)

private def decodeBoundedBytes (maxLen : Nat) : DecoderV1 ByteArray := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  if len > maxLen then
    return ← fail s!"byte payload count exceeds {maxLen}"
  unless remaining c ≥ len do
    return ← fail "truncated"
  let mut acc := ByteArray.emptyWithCapacity len
  let mut c := c
  for _ in [:len] do
    let (b, c') ← decodeU8 c
    acc := acc.push b
    c := c'
  pure (acc, c)

private def encodeDigest32 (digest : Digest) : Except String ByteArray := do
  validateDigest digest
  pure digest.bytes

private def decodeDigest32 : DecoderV1 Digest := fun c => do
  unless remaining c ≥ 32 do
    return ← fail "truncated"
  let mut bytes := ByteArray.emptyWithCapacity 32
  let mut c := c
  for _ in [:32] do
    let (byte, c') ← decodeU8 c
    bytes := bytes.push byte
    c := c'
  let digest : Digest := { algorithm := .sha256, bytes }
  validateDigest digest
  pure (digest, c)

private def precheck (input : ByteArray) : Except String Unit := do
  if input.size > maxSafeOpenProtocolBytesV1 then
    return ← fail s!"safe-open protocol frame exceeds {maxSafeOpenProtocolBytesV1} bytes"
  pure ()

private def requireReencode (label : String) (input encoded : ByteArray) :
    Except String Unit := do
  unless input == encoded do
    return ← fail s!"{label} is noncanonical"
  pure ()

/-- Opaque request carrier. Root must be absolute; relative is validated. -/
structure SafeOpenWorkerRequestV1 where
  private mk ::
  private root_ : FilePath
  private path_ : ProjectRelativePath
  private maxSourceBytes_ : Nat

namespace SafeOpenWorkerRequestV1

def root (r : SafeOpenWorkerRequestV1) : FilePath := r.root_
def path (r : SafeOpenWorkerRequestV1) : ProjectRelativePath := r.path_
def maxSourceBytes (r : SafeOpenWorkerRequestV1) : Nat := r.maxSourceBytes_

end SafeOpenWorkerRequestV1

/-- Success payload: request binding plus exact snapshot bytes. -/
structure SafeOpenWorkerSuccessV1 where
  private mk ::
  private requestDigest_ : Digest
  private bytes_ : ByteArray

namespace SafeOpenWorkerSuccessV1

def requestDigest (s : SafeOpenWorkerSuccessV1) : Digest := s.requestDigest_
def bytes (s : SafeOpenWorkerSuccessV1) : ByteArray := s.bytes_

end SafeOpenWorkerSuccessV1

/-- Failure payload: request binding plus closed SafeOpenFault (no prose/path). -/
structure SafeOpenWorkerFailureV1 where
  private mk ::
  private requestDigest_ : Digest
  private fault_ : SafeOpenFaultV1

namespace SafeOpenWorkerFailureV1

def requestDigest (f : SafeOpenWorkerFailureV1) : Digest := f.requestDigest_
def fault (f : SafeOpenWorkerFailureV1) : SafeOpenFaultV1 := f.fault_

end SafeOpenWorkerFailureV1

inductive SafeOpenWorkerResponseV1 where
  | success (value : SafeOpenWorkerSuccessV1)
  | failure (value : SafeOpenWorkerFailureV1)

def mkSafeOpenWorkerRequestV1
    (root : FilePath) (path : ProjectRelativePath) :
    Except String SafeOpenWorkerRequestV1 := do
  let rootS := root.toString
  if !root.isAbsolute || rootS.isEmpty then
    return ← fail "safe-open request root must be absolute nonempty"
  if rootS.toList.any (· == '\x00') then
    return ← fail "safe-open request root contains NUL"
  validateProjectRelativePath path
  let relative ← renderProjectRelativePath path
  if relative.toList.any (· == '\x00') then
    return ← fail "safe-open request path contains NUL"
  pure ⟨root, path, maxSourceBytes⟩

def encodeSafeOpenWorkerRequestV1
    (r : SafeOpenWorkerRequestV1) : Except String ByteArray := do
  let rootB ← encodeRawUtf8 maxSafeOpenProtocolBytesV1 r.root_.toString
  let pathS ← renderProjectRelativePath r.path_
  let pathB ← encodeRawUtf8 maxSafeOpenProtocolBytesV1 pathS
  unless r.maxSourceBytes_ == maxSourceBytes do
    return ← fail "safe-open request maxSourceBytes must equal protocol maxSourceBytes"
  unless r.maxSourceBytes_ ≤ UInt32.size - 1 do
    return ← fail "safe-open maxSourceBytes not representable"
  let maxB := encodeU32le (UInt32.ofNat r.maxSourceBytes_)
  let frame ← encodeTagged tagRequestV1 #[rootB, pathB, maxB]
  if frame.size > maxSafeOpenProtocolBytesV1 then
    return ← fail s!"safe-open protocol frame exceeds {maxSafeOpenProtocolBytesV1} bytes"
  pure frame

/-- Digest of the exact canonical SafeOpen.Req.v1 frame. -/
def safeOpenWorkerRequestDigestOfV1
    (request : SafeOpenWorkerRequestV1) : Except String Digest := do
  domainSeparatedSha256 safeOpenWorkerRequestDigestDomainV1
    (← encodeSafeOpenWorkerRequestV1 request)

def decodeSafeOpenWorkerRequestV1
    (input : ByteArray) : Except String SafeOpenWorkerRequestV1 := do
  precheck input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagRequestV1 do
    return ← fail s!"expected tag '{tagRequestV1}'"
  let ((), c) ← decodeFieldCountV1 tagRequestV1 3 c
  let (rootS, c) ← decodeRawUtf8 maxSafeOpenProtocolBytesV1 c
  let (pathS, c) ← decodeRawUtf8 maxSafeOpenProtocolBytesV1 c
  let (maxU, c) ← decodeU32le c
  finish c
  let maxN := maxU.toNat
  unless maxN == maxSourceBytes do
    return ← fail "safe-open request maxSourceBytes mismatch"
  if rootS.isEmpty || !(FilePath.mk rootS).isAbsolute then
    return ← fail "safe-open request root must be absolute nonempty"
  if rootS.toList.any (· == '\x00') then
    return ← fail "safe-open request root contains NUL"
  let path ← parseProjectRelativePath pathS
  let req : SafeOpenWorkerRequestV1 := ⟨FilePath.mk rootS, path, maxN⟩
  let reencoded ← encodeSafeOpenWorkerRequestV1 req
  requireReencode tagRequestV1 input reencoded
  pure req

private def makeSafeOpenWorkerSuccessFromDigestV1
    (requestDigest : Digest) (bytes : ByteArray) :
    Except String SafeOpenWorkerSuccessV1 := do
  validateDigest requestDigest
  unless bytes.size ≤ maxSourceBytes do
    return ← fail "safe-open success exceeds maxSourceBytes"
  pure ⟨requestDigest, bytes⟩

def mkSafeOpenWorkerSuccessV1
    (request : SafeOpenWorkerRequestV1) (bytes : ByteArray) :
    Except String SafeOpenWorkerSuccessV1 := do
  makeSafeOpenWorkerSuccessFromDigestV1
    (← safeOpenWorkerRequestDigestOfV1 request) bytes

def encodeSafeOpenWorkerSuccessV1
    (s : SafeOpenWorkerSuccessV1) : Except String ByteArray := do
  let digestB ← encodeDigest32 s.requestDigest_
  let srcB ← encodeBoundedBytes maxSourceBytes s.bytes_
  let frame ← encodeTagged tagSuccessV1 #[digestB, srcB]
  if frame.size > maxSafeOpenProtocolBytesV1 then
    return ← fail s!"safe-open protocol frame exceeds {maxSafeOpenProtocolBytesV1} bytes"
  pure frame

def decodeSafeOpenWorkerSuccessV1
    (input : ByteArray) : Except String SafeOpenWorkerSuccessV1 := do
  precheck input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagSuccessV1 do
    return ← fail s!"expected tag '{tagSuccessV1}'"
  let ((), c) ← decodeFieldCountV1 tagSuccessV1 2 c
  let (requestDigest, c) ← decodeDigest32 c
  let (bytes, c) ← decodeBoundedBytes maxSourceBytes c
  finish c
  let success ← makeSafeOpenWorkerSuccessFromDigestV1 requestDigest bytes
  let reencoded ← encodeSafeOpenWorkerSuccessV1 success
  requireReencode tagSuccessV1 input reencoded
  pure success

private def makeSafeOpenWorkerFailureFromDigestV1
    (requestDigest : Digest) (fault : SafeOpenFaultV1) :
    Except String SafeOpenWorkerFailureV1 := do
  validateDigest requestDigest
  pure ⟨requestDigest, fault⟩

def mkSafeOpenWorkerFailureV1
    (request : SafeOpenWorkerRequestV1) (fault : SafeOpenFaultV1) :
    Except String SafeOpenWorkerFailureV1 := do
  makeSafeOpenWorkerFailureFromDigestV1
    (← safeOpenWorkerRequestDigestOfV1 request) fault

def encodeSafeOpenWorkerFailureV1
    (f : SafeOpenWorkerFailureV1) : Except String ByteArray := do
  let digestB ← encodeDigest32 f.requestDigest_
  let wireB ← encodeRawUtf8 64 f.fault_.wire
  let frame ← encodeTagged tagFailureV1 #[digestB, wireB]
  if frame.size > maxSafeOpenProtocolBytesV1 then
    return ← fail s!"safe-open protocol frame exceeds {maxSafeOpenProtocolBytesV1} bytes"
  pure frame

def decodeSafeOpenWorkerFailureV1
    (input : ByteArray) : Except String SafeOpenWorkerFailureV1 := do
  precheck input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagFailureV1 do
    return ← fail s!"expected tag '{tagFailureV1}'"
  let ((), c) ← decodeFieldCountV1 tagFailureV1 2 c
  let (requestDigest, c) ← decodeDigest32 c
  let (wire, c) ← decodeRawUtf8 64 c
  finish c
  -- Unknown fault wire is a decoder error — never silently canonicalize.
  let fault ←
    match SafeOpenFaultV1.ofWire? wire with
    | some f => pure f
    | none => fail s!"unknown safe-open fault wire '{wire}'"
  let failure ← makeSafeOpenWorkerFailureFromDigestV1 requestDigest fault
  let reencoded ← encodeSafeOpenWorkerFailureV1 failure
  requireReencode tagFailureV1 input reencoded
  pure failure

def encodeSafeOpenWorkerResponseV1
    (r : SafeOpenWorkerResponseV1) : Except String ByteArray :=
  match r with
  | .success s => encodeSafeOpenWorkerSuccessV1 s
  | .failure f => encodeSafeOpenWorkerFailureV1 f

def decodeSafeOpenWorkerResponseV1
    (input : ByteArray) : Except String SafeOpenWorkerResponseV1 := do
  precheck input
  let c0 := start input
  let (tag, _) ← decodeTagV1 c0
  if tag == tagSuccessV1 then
    pure (.success (← decodeSafeOpenWorkerSuccessV1 input))
  else if tag == tagFailureV1 then
    pure (.failure (← decodeSafeOpenWorkerFailureV1 input))
  else
    fail s!"expected SafeOpen.Ok.v1 or SafeOpen.Err.v1, got '{tag}'"

/-- Bind a canonical response to the exact SafeOpen.Req.v1 that produced it. -/
def bindSafeOpenWorkerResponseV1
    (request : SafeOpenWorkerRequestV1)
    (response : SafeOpenWorkerResponseV1) :
    Except String SafeOpenWorkerResponseV1 := do
  let expected ← safeOpenWorkerRequestDigestOfV1 request
  let actual := match response with
    | .success success => SafeOpenWorkerSuccessV1.requestDigest success
    | .failure failure => SafeOpenWorkerFailureV1.requestDigest failure
  unless actual == expected do
    throw "safe-open response requestDigest mismatch (cross-request replay)"
  pure response

end ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1
