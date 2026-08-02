import ProofForgeV2.Compiler.ProofSubjectFilesV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

/-
  Canonical one-request compiler proof-worker protocol. This is an engineering
  subprocess boundary only: it does not claim containment, deadlines, resource
  enforcement, `.olean` loading, or formal proof evidence.
-/

namespace ProofForgeV2.Compiler.ProofWorkerProtocolV1

open ProofForgeV2.Compiler.ProofSubjectFilesV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Semantic.ProofSubjectV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1
open System

/-- Compiler-core request/response hard maximum. Nested frames share this one
    aggregate budget; two independently maximal frontend frames cannot be
    wrapped into an oversized proof-worker request. -/
def maxProofWorkerProtocolBytesV1 : Nat := 64 * 1024 * 1024

def proofWorkerRequestDigestDomainV1 : String :=
  "proof-forge.compiler-proof-worker-request.v1"

private def requestTag : String := "CompilerProof.Req.v1"
private def successTag : String := "CompilerProof.Ok.v1"
private def failureTag : String := "CompilerProof.Err.v1"

private def fail (detail : String) : Except String α := .error detail

private def containsNul (value : String) : Bool :=
  value.toList.any (· == '\x00')

private def encodeBoundedBytes (bytes : ByteArray) : Except String ByteArray := do
  unless bytes.size ≤ maxProofWorkerProtocolBytesV1 do
    return ← fail "proof-worker byte payload exceeds protocol limit"
  unless bytes.size ≤ UInt32.size - 1 do
    return ← fail "proof-worker byte payload length is not representable"
  pure ((encodeU32le (UInt32.ofNat bytes.size)).append bytes)

private def decodeBoundedBytes : DecoderV1 ByteArray := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  if len > maxProofWorkerProtocolBytesV1 then
    return ← fail "proof-worker byte payload exceeds protocol limit"
  unless remaining c ≥ len do
    return ← fail "truncated"
  let mut out := ByteArray.emptyWithCapacity len
  let mut c := c
  for _ in [:len] do
    let (byte, next) ← decodeU8 c
    out := out.push byte
    c := next
  pure (out, c)

private def encodeRawString (value : String) : Except String ByteArray :=
  encodeBoundedBytes value.toUTF8

private def decodeRawString : DecoderV1 String := fun c => do
  let (bytes, c) ← decodeBoundedBytes c
  match String.fromUTF8? bytes with
  | none => fail "proof-worker string is not UTF-8"
  | some value => pure (value, c)

private def encodeDigest (digest : Digest) : Except String ByteArray := do
  validateDigest digest
  unless digest.bytes.size == 32 do
    return ← fail "proof-worker digest must contain 32 bytes"
  pure digest.bytes

private def decodeDigest : DecoderV1 Digest := fun c => do
  unless remaining c ≥ 32 do
    return ← fail "truncated"
  let mut bytes := ByteArray.emptyWithCapacity 32
  let mut c := c
  for _ in [:32] do
    let (byte, next) ← decodeU8 c
    bytes := bytes.push byte
    c := next
  let digest : Digest := { algorithm := .sha256, bytes }
  validateDigest digest
  pure (digest, c)

private def checkFrameSize (bytes : ByteArray) : Except String Unit := do
  unless bytes.size ≤ maxProofWorkerProtocolBytesV1 do
    return ← fail "proof-worker frame exceeds protocol limit"

/-- Opaque request retaining the exact canonical nested frontend frames. -/
structure ProofWorkerRequestV1 where
  private mk ::
  private root_ : FilePath
  private frontendRequestBytes_ : ByteArray
  private frontendSuccessBytes_ : ByteArray
  private frontendRequest_ : FrontendRequestV1
  private frontendSuccess_ : FrontendSuccessV1

namespace ProofWorkerRequestV1

def root (request : ProofWorkerRequestV1) : FilePath := request.root_
def frontendRequestBytes (request : ProofWorkerRequestV1) : ByteArray :=
  request.frontendRequestBytes_
def frontendSuccessBytes (request : ProofWorkerRequestV1) : ByteArray :=
  request.frontendSuccessBytes_
def frontendRequest (request : ProofWorkerRequestV1) : FrontendRequestV1 :=
  request.frontendRequest_
def frontendSuccess (request : ProofWorkerRequestV1) : FrontendSuccessV1 :=
  request.frontendSuccess_

end ProofWorkerRequestV1

private def validateRequestParts
    (rootString : String) (requestBytes successBytes : ByteArray) :
    Except String ProofWorkerRequestV1 := do
  let root := FilePath.mk rootString
  unless root.isAbsolute && !rootString.isEmpty && !containsNul rootString do
    return ← fail "proof-worker root must be a nonempty absolute NUL-free path"
  let request ← decodeFrontendRequestV1 requestBytes
  let success ← decodeFrontendSuccessV1 successBytes
  -- Binding and source/span reconstruction happen before any filesystem access.
  let _ ← reconstructFrontendSourceSpansV1 request success
  pure ⟨root, requestBytes, successBytes, request, success⟩

def encodeProofWorkerRequestV1
    (request : ProofWorkerRequestV1) : Except String ByteArray := do
  let rootBytes := request.root_.toString.toUTF8
  -- tag length + tag + field count + three u32 lengths + exact payloads.
  let exactSize := 4 + requestTag.toUTF8.size + 2 + 12 + rootBytes.size +
    request.frontendRequestBytes_.size + request.frontendSuccessBytes_.size
  unless exactSize ≤ maxProofWorkerProtocolBytesV1 do
    return ← fail "proof-worker frame exceeds aggregate protocol limit"
  let root ← encodeRawString request.root_.toString
  let frontendRequest ← encodeBoundedBytes request.frontendRequestBytes_
  let frontendSuccess ← encodeBoundedBytes request.frontendSuccessBytes_
  let frame ← encodeTagged requestTag #[root, frontendRequest, frontendSuccess]
  checkFrameSize frame
  pure frame

/-- Build a request only from exact canonical frontend request/success bytes. -/
def mkProofWorkerRequestV1
    (root : FilePath) (requestBytes successBytes : ByteArray) :
    Except String ProofWorkerRequestV1 := do
  let request ← validateRequestParts root.toString requestBytes successBytes
  let _ ← encodeProofWorkerRequestV1 request
  pure request

def decodeProofWorkerRequestV1
    (input : ByteArray) : Except String ProofWorkerRequestV1 := do
  checkFrameSize input
  let (tag, cursor) ← decodeTagV1 (start input)
  unless tag == requestTag do
    return ← fail s!"expected tag '{requestTag}'"
  let ((), cursor) ← decodeFieldCountV1 requestTag 3 cursor
  let (root, cursor) ← decodeRawString cursor
  let (requestBytes, cursor) ← decodeBoundedBytes cursor
  let (successBytes, cursor) ← decodeBoundedBytes cursor
  finish cursor
  let request ← validateRequestParts root requestBytes successBytes
  let encoded ← encodeProofWorkerRequestV1 request
  unless encoded == input do
    return ← fail "CompilerProof.Req.v1 is noncanonical"
  pure request

def proofWorkerRequestDigestV1
    (request : ProofWorkerRequestV1) : Except String Digest := do
  domainSeparatedSha256 proofWorkerRequestDigestDomainV1
    (← encodeProofWorkerRequestV1 request)

/-- Successful validation result. It is request-bound and contains only
    authority-recomputed identities; it is not a serializable proof-subject
    capability and cannot substitute for the future in-worker `.olean` loader. -/
structure ProofWorkerSuccessV1 where
  private mk ::
  private requestDigest_ : Digest
  private sourceHash_ : Digest
  private semanticHash_ : Digest
  private semanticProvenanceDigest_ : Digest

namespace ProofWorkerSuccessV1

def requestDigest (value : ProofWorkerSuccessV1) : Digest := value.requestDigest_
def sourceHash (value : ProofWorkerSuccessV1) : Digest := value.sourceHash_
def semanticHash (value : ProofWorkerSuccessV1) : Digest := value.semanticHash_
def semanticProvenanceDigest (value : ProofWorkerSuccessV1) : Digest :=
  value.semanticProvenanceDigest_

end ProofWorkerSuccessV1

/-- Closed, phase-preserving validation failure. Optional native stable-file
    detail is legal only for root/semantic-program/semantic-provenance phases. -/
structure ProofWorkerFailureV1 where
  private mk ::
  private requestDigest_ : Digest
  private phase_ : String
  private fault_ : Option StableFileFaultV1

namespace ProofWorkerFailureV1

def requestDigest (value : ProofWorkerFailureV1) : Digest := value.requestDigest_
def phase (value : ProofWorkerFailureV1) : String := value.phase_
def fault (value : ProofWorkerFailureV1) : Option StableFileFaultV1 := value.fault_

end ProofWorkerFailureV1

inductive ProofWorkerResponseV1 where
  | success (value : ProofWorkerSuccessV1)
  | failure (value : ProofWorkerFailureV1)

private def failureParts : ProofSubjectFilesErrorV1 → String × Option StableFileFaultV1
  | .invalidRoot => ("invalid-root", none)
  | .root fault => ("root", some fault)
  | .file .semanticProgram fault => ("semantic-program-file", some fault)
  | .file .semanticProvenance fault => ("semantic-provenance-file", some fault)
  | .nativeProtocol => ("native-protocol", none)
  | .subject (.semanticProgramWire _) => ("semantic-program-wire", none)
  | .subject (.semanticProvenanceWire _) => ("semantic-provenance-wire", none)
  | .subject (.sourceHash _) => ("source-hash", none)
  | .subject (.authority _) => ("semantic-authority", none)

private def validFailureParts
    (phase : String) (fault : Option StableFileFaultV1) : Bool :=
  match phase, fault with
  | "root", some _ | "semantic-program-file", some _
  | "semantic-provenance-file", some _ => true
  | "invalid-root", none | "native-protocol", none
  | "semantic-program-wire", none | "semantic-provenance-wire", none
  | "source-hash", none | "semantic-authority", none => true
  | _, _ => false

def mkProofWorkerSuccessV1
    (request : ProofWorkerRequestV1) (subject : ProofSubjectV1) :
    Except String ProofWorkerSuccessV1 := do
  pure ⟨← proofWorkerRequestDigestV1 request, subject.sourceHash,
    subject.semanticHash, subject.semanticProvenanceDigest⟩

def mkProofWorkerFailureV1
    (request : ProofWorkerRequestV1) (error : ProofSubjectFilesErrorV1) :
    Except String ProofWorkerFailureV1 := do
  let (phase, fault) := failureParts error
  pure ⟨← proofWorkerRequestDigestV1 request, phase, fault⟩

private def encodeFault : Option StableFileFaultV1 → Except String ByteArray
  | none => encodeRawString ""
  | some fault => encodeRawString fault.wire

private def decodeFault : DecoderV1 (Option StableFileFaultV1) := fun c => do
  let (wire, c) ← decodeRawString c
  if wire.isEmpty then pure (none, c)
  else match StableFileFaultV1.ofWire? wire with
    | some fault => pure (some fault, c)
    | none => fail "unknown proof-worker stable-file fault"

def encodeProofWorkerResponseV1
    (response : ProofWorkerResponseV1) : Except String ByteArray := do
  let frame ← match response with
    | .success value => do
        let requestDigest ← encodeDigest value.requestDigest_
        let sourceHash ← encodeDigest value.sourceHash_
        let semanticHash ← encodeDigest value.semanticHash_
        let provenanceDigest ← encodeDigest value.semanticProvenanceDigest_
        encodeTagged successTag
          #[requestDigest, sourceHash, semanticHash, provenanceDigest]
    | .failure value => do
        unless validFailureParts value.phase_ value.fault_ do
          return ← fail "invalid proof-worker failure phase/fault combination"
        let requestDigest ← encodeDigest value.requestDigest_
        let phase ← encodeRawString value.phase_
        let fault ← encodeFault value.fault_
        encodeTagged failureTag #[requestDigest, phase, fault]
  checkFrameSize frame
  pure frame

def decodeProofWorkerResponseV1
    (input : ByteArray) : Except String ProofWorkerResponseV1 := do
  checkFrameSize input
  let (tag, cursor) ← decodeTagV1 (start input)
  let (response, cursor) ← if tag == successTag then do
      let ((), cursor) ← decodeFieldCountV1 successTag 4 cursor
      let (requestDigest, cursor) ← decodeDigest cursor
      let (sourceHash, cursor) ← decodeDigest cursor
      let (semanticHash, cursor) ← decodeDigest cursor
      let (provenanceDigest, cursor) ← decodeDigest cursor
      pure (.success ⟨requestDigest, sourceHash, semanticHash,
        provenanceDigest⟩, cursor)
    else if tag == failureTag then do
      let ((), cursor) ← decodeFieldCountV1 failureTag 3 cursor
      let (requestDigest, cursor) ← decodeDigest cursor
      let (phase, cursor) ← decodeRawString cursor
      let (fault, cursor) ← decodeFault cursor
      unless validFailureParts phase fault do
        return ← fail "invalid proof-worker failure phase/fault combination"
      pure (.failure ⟨requestDigest, phase, fault⟩, cursor)
    else
      return ← fail "unknown proof-worker response tag"
  finish cursor
  let encoded ← encodeProofWorkerResponseV1 response
  unless encoded == input do
    return ← fail "proof-worker response is noncanonical"
  pure response

/-- Correlate either response variant with one exact request and reject
    cross-request replay. This does not provide process authentication,
    freshness, same-request replay protection, or loading authority. -/
def bindProofWorkerResponseV1
    (request : ProofWorkerRequestV1) (response : ProofWorkerResponseV1) :
    Except String ProofWorkerResponseV1 := do
  let expected ← proofWorkerRequestDigestV1 request
  let actual := match response with
    | .success value => value.requestDigest_
    | .failure value => value.requestDigest_
  unless actual == expected do
    return ← fail "proof-worker response digest does not match request"
  pure response

end ProofForgeV2.Compiler.ProofWorkerProtocolV1
