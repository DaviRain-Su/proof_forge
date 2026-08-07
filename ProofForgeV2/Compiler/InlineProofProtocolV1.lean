import ProofForgeV2.Core.Common
import ProofForgeV2.Semantic.InlineProofPolicyV1
import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstScalarDecodeV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

/-
  ProofForgeV2.Compiler.InlineProofProtocolV1 — pure canonical one-frame
  binary protocol for the future inline proof-certifier boundary.

  Scope (engineering wire only; not a worker, Loader, Audit, CLI, or formal
  TST-PROOF-001 completion):
    * closed request / success / failure tags
    * 64 MiB aggregate frame cap
    * full-consume + re-encode identity on every decoder
    * request digest binding and cross-request replay rejection
    * private constructors; fixed trust-policy digest (caller cannot choose)

  Request binds:
    * raw source UTF-8 bytes (no NFC gate at protocol layer)
    * logical ProjectRelativePath + module/program selectors
    * exact source / semantic / provenance digests (ProofSubject identity claims)
    * ordered theorem obligations
      (invariant name, proof kind, ordinal, theorem qualified name,
       expected generated name)
    * fixed policy digest (sole authority below)

  Success carries request digest, theorem count, theorem-set digest, and
  proofCertificationDigest. Failure carries request digest and a closed phase
  enum. This module does not open files, load `.olean`, spawn workers, or mint
  ProofSubjectV1 capabilities.
-/

namespace ProofForgeV2.Compiler.InlineProofProtocolV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InlineProofPolicyV1
open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstScalarDecodeV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1

/-- Aggregate one-frame hard maximum (request or response). -/
def maxProtocolBytesV1 : Nat := 64 * 1024 * 1024

/-- Source-byte payload hard maximum (matches frontend source budget). -/
def maxSourceBytesV1 : Nat := 16 * 1024 * 1024

/-- Selector UTF-8 allocation/frame guard (= aggregate protocol budget). -/
def maxSelectorBytesV1 : Nat := maxProtocolBytesV1

/-- Ordered theorem-obligation table hard maximum. -/
def maxObligationsV1 : Nat := 4096

/-- Domain tags (profile-id grammar; domain-separated SHA-256). -/
def requestDigestDomainV1 : String := "proof-forge.inline-proof-request.v1"
def theoremSetDigestDomainV1 : String := "proof-forge.inline-proof-theorem-set.v1"
def certificationDigestDomainV1 : String := "proof-forge.inline-proof-certification.v1"

/-- Sole fixed trust-policy digest bound into every request. Policy bytes and
    digest are owned only by `Semantic.InlineProofPolicyV1`; the protocol maps
    its closed error into the wire layer's String error without re-declaring a
    second policy payload. -/
def fixedInlineProofPolicyDigestV1 : Except String Digest :=
  match inlineProofPolicyDigestV1 with
  | .ok digest => .ok digest
  | .error (.internal detail) => .error detail

private def tagRequestV1 : String := "InlineProof.Req.v1"
private def tagSuccessV1 : String := "InlineProof.Ok.v1"
private def tagFailureV1 : String := "InlineProof.Err.v1"

private def fail (detail : String) : Except String α :=
  .error detail

private def requireReencode (label : String) (input encoded : ByteArray) :
    Except String Unit := do
  unless input == encoded do
    return ← fail s!"{label} is noncanonical"
  pure ()

private def precheckProtocolSize (input : ByteArray) : Except String Unit := do
  if input.size > maxProtocolBytesV1 then
    return ← fail s!"inline-proof protocol frame exceeds {maxProtocolBytesV1} bytes"
  pure ()

private def checkFrameSize (bytes : ByteArray) : Except String Unit := do
  unless bytes.size ≤ maxProtocolBytesV1 do
    return ← fail s!"inline-proof protocol frame exceeds {maxProtocolBytesV1} bytes"
  pure ()

/-- Length-prefixed raw bytes; count checked before copy. -/
private def encodeBoundedBytes (maxLen : Nat) (bytes : ByteArray) :
    Except String ByteArray := do
  unless bytes.size ≤ maxLen do
    return ← fail s!"byte payload exceeds limit {maxLen}"
  unless bytes.size ≤ UInt32.size - 1 do
    return ← fail "byte payload length is not representable"
  pure ((encodeU32le (UInt32.ofNat bytes.size)).append bytes)

private def decodeBoundedBytes (maxLen : Nat) : DecoderV1 ByteArray := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  if len > maxLen then
    return ← fail s!"byte payload count exceeds limit {maxLen}"
  unless remaining c ≥ len do
    return ← fail "truncated"
  let mut acc := ByteArray.emptyWithCapacity len
  let mut c := c
  for _ in [:len] do
    let (b, c') ← decodeU8 c
    acc := acc.push b
    c := c'
  pure (acc, c)

private def encodeRawUtf8 (maxLen : Nat) (value : String) : Except String ByteArray :=
  encodeBoundedBytes maxLen value.toUTF8

private def decodeRawUtf8 (maxLen : Nat) : DecoderV1 String := fun c => do
  let (raw, c) ← decodeBoundedBytes maxLen c
  match String.fromUTF8? raw with
  | none => fail "invalid UTF-8"
  | some s => pure (s, c)

private def encodeDigest32 (digest : Digest) : Except String ByteArray := do
  validateDigest digest
  unless digest.bytes.size == 32 do
    return ← fail "digest must contain exactly 32 raw bytes"
  pure digest.bytes

private def decodeDigest32 : DecoderV1 Digest := fun c => do
  unless remaining c ≥ 32 do
    return ← fail "truncated"
  let mut acc := ByteArray.emptyWithCapacity 32
  let mut c := c
  for _ in [:32] do
    let (b, c') ← decodeU8 c
    acc := acc.push b
    c := c'
  let digest : Digest := { algorithm := .sha256, bytes := acc }
  validateDigest digest
  pure (digest, c)

private def encodeU32Field (value : UInt32) : ByteArray :=
  encodeU32le value

private def decodeU32Field : DecoderV1 UInt32 :=
  decodeU32le

private def encodeQualifiedNameField (name : QualifiedName) :
    Except String ByteArray :=
  encodeQualifiedName name

private def decodeQualifiedNameField : DecoderV1 QualifiedName := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  unless 1 ≤ count && count ≤ 256 do
    return ← fail "qualified name must contain 1..256 components"
  let mut components : Array String := Array.mkEmpty count
  let mut c := c
  for _ in [:count] do
    let (component, c') ← decodeSourceNameComponentV1 c
    components := components.push component.raw
    c := c'
  let name ← parseQualifiedName components
  pure (name, c)

/-- Closed failure phases for the certifier protocol. -/
inductive InlineProofFailurePhaseV1 where
  | request
  | policy
  | subject
  | obligation
  | certification
  | internal
  deriving DecidableEq, Repr, Inhabited

namespace InlineProofFailurePhaseV1

def toWire (phase : InlineProofFailurePhaseV1) : UInt8 :=
  match phase with
  | .request => 0
  | .policy => 1
  | .subject => 2
  | .obligation => 3
  | .certification => 4
  | .internal => 5

def ofWire? (wire : UInt8) : Option InlineProofFailurePhaseV1 :=
  match wire.toNat with
  | 0 => some .request
  | 1 => some .policy
  | 2 => some .subject
  | 3 => some .obligation
  | 4 => some .certification
  | 5 => some .internal
  | _ => none

end InlineProofFailurePhaseV1

/-- One ordered theorem obligation row. Constructor is private. -/
structure InlineProofObligationV1 where
  private mk ::
  private invariantName_ : String
  private kind_ : ProofKindV1
  private ordinal_ : UInt32
  private theoremName_ : QualifiedName
  private expectedGeneratedName_ : String
  deriving DecidableEq, Repr

namespace InlineProofObligationV1

def invariantName (o : InlineProofObligationV1) : String := o.invariantName_
def kind (o : InlineProofObligationV1) : ProofKindV1 := o.kind_
def ordinal (o : InlineProofObligationV1) : UInt32 := o.ordinal_
def theoremName (o : InlineProofObligationV1) : QualifiedName := o.theoremName_
def expectedGeneratedName (o : InlineProofObligationV1) : String :=
  o.expectedGeneratedName_

end InlineProofObligationV1

private def validateSelector (label value : String) : Except String Unit := do
  unless value.toUTF8.size ≤ maxSelectorBytesV1 do
    return ← fail s!"{label} exceeds {maxSelectorBytesV1} UTF-8 bytes"
  match String.fromUTF8? value.toUTF8 with
  | none => fail s!"{label} is not valid UTF-8"
  | some _ => pure ()

/-- Smart constructor for one obligation row. -/
def mkInlineProofObligationV1
    (invariantName : String)
    (kind : ProofKindV1)
    (ordinal : UInt32)
    (theoremName : QualifiedName)
    (expectedGeneratedName : String) :
    Except String InlineProofObligationV1 := do
  validateIdentifierComponent invariantName
  validateQualifiedName theoremName
  validateIdentifierComponent expectedGeneratedName
  pure ⟨invariantName, kind, ordinal, theoremName, expectedGeneratedName⟩

private def encodeObligationFields (o : InlineProofObligationV1) :
    Except String ByteArray := do
  let nameB ← encodeIdent o.invariantName_
  let kindB ← encodeProofKindV1 o.kind_
  let ordB := encodeU32Field o.ordinal_
  let thmB ← encodeQualifiedNameField o.theoremName_
  let genB ← encodeIdent o.expectedGeneratedName_
  pure ((((nameB.append kindB).append ordB).append thmB).append genB)

private def decodeObligationFields : DecoderV1 InlineProofObligationV1 := fun c => do
  let (component, c) ← decodeSourceNameComponentV1 c
  let invariantName := component.raw
  validateIdentifierComponent invariantName
  let (kind, c) ← decodeProofKindV1 c
  let (ordinal, c) ← decodeU32Field c
  let (theoremName, c) ← decodeQualifiedNameField c
  let (genComponent, c) ← decodeSourceNameComponentV1 c
  let expectedGeneratedName := genComponent.raw
  validateIdentifierComponent expectedGeneratedName
  pure (⟨invariantName, kind, ordinal, theoremName, expectedGeneratedName⟩, c)

private def encodeObligations (obligations : Array InlineProofObligationV1) :
    Except String ByteArray := do
  unless obligations.size ≤ maxObligationsV1 do
    return ← fail s!"obligation count exceeds limit {maxObligationsV1}"
  unless obligations.size ≤ UInt32.size - 1 do
    return ← fail "obligation count is not representable"
  let mut out := encodeU32le (UInt32.ofNat obligations.size)
  for obligation in obligations do
    out := out.append (← encodeObligationFields obligation)
  pure out

private def decodeObligations : DecoderV1 (Array InlineProofObligationV1) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > maxObligationsV1 then
    return ← fail s!"obligation count exceeds limit {maxObligationsV1}"
  let mut acc : Array InlineProofObligationV1 := Array.mkEmpty count
  let mut c := c
  for _ in [:count] do
    let (row, c') ← decodeObligationFields c
    acc := acc.push row
    c := c'
  pure (acc, c)

private def validateObligationUniqueness
    (obligations : Array InlineProofObligationV1) : Except String Unit := do
  let mut keys : Array (String × ProofKindV1) := #[]
  let mut invariantOrdinals : Array (String × UInt32) := #[]
  let mut ordinalInvariants : Array (UInt32 × String) := #[]
  let mut theoremNames : Array QualifiedName := #[]
  for obligation in obligations do
    let key := (obligation.invariantName_, obligation.kind_)
    if keys.any (· == key) then
      return ← fail "duplicate invariant/kind key in theorem obligations"
    if invariantOrdinals.any fun pair =>
        pair.1 == obligation.invariantName_ && pair.2 != obligation.ordinal_ then
      return ← fail "invariant name maps to multiple theorem ordinals"
    if ordinalInvariants.any fun pair =>
        pair.1 == obligation.ordinal_ && pair.2 != obligation.invariantName_ then
      return ← fail "theorem ordinal maps to multiple invariant names"
    if theoremNames.any (· == obligation.theoremName_) then
      return ← fail "duplicate theorem name in theorem obligations"
    keys := keys.push key
    invariantOrdinals := invariantOrdinals.push
      (obligation.invariantName_, obligation.ordinal_)
    ordinalInvariants := ordinalInvariants.push
      (obligation.ordinal_, obligation.invariantName_)
    theoremNames := theoremNames.push obligation.theoremName_
  pure ()

/-- Opaque request. Policy is always the fixed digest; callers cannot choose it. -/
structure InlineProofRequestV1 where
  private mk ::
  private sourcePath_ : ProjectRelativePath
  private moduleSelector_ : String
  private programSelector_ : Option String
  private sourceBytes_ : ByteArray
  private sourceHash_ : Digest
  private semanticHash_ : Digest
  private semanticProvenanceDigest_ : Digest
  private obligations_ : Array InlineProofObligationV1
  private policyDigest_ : Digest

namespace InlineProofRequestV1

def sourcePath (r : InlineProofRequestV1) : ProjectRelativePath := r.sourcePath_
def moduleSelector (r : InlineProofRequestV1) : String := r.moduleSelector_
def programSelector (r : InlineProofRequestV1) : Option String := r.programSelector_
def sourceBytes (r : InlineProofRequestV1) : ByteArray := r.sourceBytes_
def sourceHash (r : InlineProofRequestV1) : Digest := r.sourceHash_
def semanticHash (r : InlineProofRequestV1) : Digest := r.semanticHash_
def semanticProvenanceDigest (r : InlineProofRequestV1) : Digest :=
  r.semanticProvenanceDigest_
def obligations (r : InlineProofRequestV1) : Array InlineProofObligationV1 :=
  r.obligations_
def policyDigest (r : InlineProofRequestV1) : Digest := r.policyDigest_

end InlineProofRequestV1

/-- Opaque success response bound to one request digest. -/
structure InlineProofSuccessV1 where
  private mk ::
  private requestDigest_ : Digest
  private theoremCount_ : UInt32
  private theoremSetDigest_ : Digest
  private proofCertificationDigest_ : Digest

namespace InlineProofSuccessV1

def requestDigest (r : InlineProofSuccessV1) : Digest := r.requestDigest_
def theoremCount (r : InlineProofSuccessV1) : UInt32 := r.theoremCount_
def theoremSetDigest (r : InlineProofSuccessV1) : Digest := r.theoremSetDigest_
def proofCertificationDigest (r : InlineProofSuccessV1) : Digest :=
  r.proofCertificationDigest_

end InlineProofSuccessV1

/-- Opaque failure response bound to one request digest. -/
structure InlineProofFailureV1 where
  private mk ::
  private requestDigest_ : Digest
  private phase_ : InlineProofFailurePhaseV1

namespace InlineProofFailureV1

def requestDigest (r : InlineProofFailureV1) : Digest := r.requestDigest_
def phase (r : InlineProofFailureV1) : InlineProofFailurePhaseV1 := r.phase_

end InlineProofFailureV1

inductive InlineProofResponseV1 where
  | success (value : InlineProofSuccessV1)
  | failure (value : InlineProofFailureV1)

private def encodeRequestFields (r : InlineProofRequestV1) :
    Except String (Array ByteArray) := do
  let pathS ← renderProjectRelativePath r.sourcePath_
  let pathB ← encodeString pathS
  let modB ← encodeRawUtf8 maxSelectorBytesV1 r.moduleSelector_
  let progB ← encodeOption (encodeRawUtf8 maxSelectorBytesV1) r.programSelector_
  let srcB ← encodeBoundedBytes maxSourceBytesV1 r.sourceBytes_
  let sourceHashB ← encodeDigest32 r.sourceHash_
  let semanticHashB ← encodeDigest32 r.semanticHash_
  let provenanceB ← encodeDigest32 r.semanticProvenanceDigest_
  let obligationsB ← encodeObligations r.obligations_
  let policyB ← encodeDigest32 r.policyDigest_
  pure #[pathB, modB, progB, srcB, sourceHashB, semanticHashB, provenanceB,
    obligationsB, policyB]

def encodeInlineProofRequestV1 (r : InlineProofRequestV1) :
    Except String ByteArray := do
  let fields ← encodeRequestFields r
  let frame ← encodeTagged tagRequestV1 fields
  checkFrameSize frame
  pure frame

/-- Domain-separated digest of exact canonical request frame bytes. -/
def inlineProofRequestDigestV1 (requestBytes : ByteArray) : Except String Digest :=
  domainSeparatedSha256 requestDigestDomainV1 requestBytes

def inlineProofRequestDigestOfV1 (r : InlineProofRequestV1) : Except String Digest := do
  inlineProofRequestDigestV1 (← encodeInlineProofRequestV1 r)

private def theoremSetPayloadV1
    (obligations : Array InlineProofObligationV1) : Except String ByteArray :=
  encodeObligations obligations

/-- Domain-separated digest of the ordered theorem-obligation table. -/
def theoremSetDigestV1
    (obligations : Array InlineProofObligationV1) : Except String Digest := do
  domainSeparatedSha256 theoremSetDigestDomainV1 (← theoremSetPayloadV1 obligations)

/-- Certification digest binds request digest, theorem count, and theorem-set digest. -/
def proofCertificationDigestV1
    (requestDigest : Digest) (theoremCount : UInt32) (theoremSetDigest : Digest) :
    Except String Digest := do
  validateDigest requestDigest
  validateDigest theoremSetDigest
  let payload :=
    (requestDigest.bytes.append (encodeU32Field theoremCount)).append
      theoremSetDigest.bytes
  domainSeparatedSha256 certificationDigestDomainV1 payload

/-- Smart constructor: binds the fixed policy digest (caller cannot choose). -/
def mkInlineProofRequestV1
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String)
    (sourceBytes : ByteArray)
    (sourceHash semanticHash semanticProvenanceDigest : Digest)
    (obligations : Array InlineProofObligationV1) :
    Except String InlineProofRequestV1 := do
  validateProjectRelativePath sourcePath
  validateSelector "moduleSelector" moduleSelector
  match programSelector with
  | none => pure ()
  | some p => validateSelector "programSelector" p
  unless sourceBytes.size ≤ maxSourceBytesV1 do
    return ← fail s!"sourceBytes exceed {maxSourceBytesV1} bytes"
  validateDigest sourceHash
  validateDigest semanticHash
  validateDigest semanticProvenanceDigest
  unless obligations.size ≤ maxObligationsV1 do
    return ← fail s!"obligation count exceeds limit {maxObligationsV1}"
  for obligation in obligations do
    validateIdentifierComponent obligation.invariantName_
    validateQualifiedName obligation.theoremName_
    validateIdentifierComponent obligation.expectedGeneratedName_
  validateObligationUniqueness obligations
  let policyDigest ← fixedInlineProofPolicyDigestV1
  let req : InlineProofRequestV1 :=
    ⟨sourcePath, moduleSelector, programSelector, sourceBytes,
      sourceHash, semanticHash, semanticProvenanceDigest, obligations, policyDigest⟩
  let _ ← encodeInlineProofRequestV1 req
  pure req

private def decodeRequestBody : DecoderV1 InlineProofRequestV1 := fun c => do
  let (pathS, c) ← decodeString c
  let sourcePath ← parseProjectRelativePath pathS
  let pathCanon ← renderProjectRelativePath sourcePath
  unless pathCanon == pathS do
    return ← fail "sourcePath is noncanonical"
  let (moduleSelector, c) ← decodeRawUtf8 maxSelectorBytesV1 c
  let (programSelector, c) ← decodeOption (decodeRawUtf8 maxSelectorBytesV1) c
  let (sourceBytes, c) ← decodeBoundedBytes maxSourceBytesV1 c
  let (sourceHash, c) ← decodeDigest32 c
  let (semanticHash, c) ← decodeDigest32 c
  let (semanticProvenanceDigest, c) ← decodeDigest32 c
  let (obligations, c) ← decodeObligations c
  validateObligationUniqueness obligations
  let (policyDigest, c) ← decodeDigest32 c
  let expectedPolicy ← fixedInlineProofPolicyDigestV1
  unless policyDigest == expectedPolicy do
    return ← fail "inline-proof request policy digest is not the fixed authority"
  pure (⟨sourcePath, moduleSelector, programSelector, sourceBytes,
    sourceHash, semanticHash, semanticProvenanceDigest, obligations, policyDigest⟩, c)

/-- Full-consume decode with aggregate precheck + re-encode identity. -/
def decodeInlineProofRequestV1 (input : ByteArray) :
    Except String InlineProofRequestV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagRequestV1 do
    return ← fail s!"expected tag '{tagRequestV1}', got '{tag}'"
  let ((), c) ← decodeFieldCountV1 tagRequestV1 9 c
  let (req, c) ← decodeRequestBody c
  finish c
  let reencoded ← encodeInlineProofRequestV1 req
  requireReencode "InlineProof.Req.v1" input reencoded
  pure req

private def encodeSuccessFields (r : InlineProofSuccessV1) :
    Except String (Array ByteArray) := do
  let digB ← encodeDigest32 r.requestDigest_
  let countB := encodeU32Field r.theoremCount_
  let setB ← encodeDigest32 r.theoremSetDigest_
  let certB ← encodeDigest32 r.proofCertificationDigest_
  pure #[digB, countB, setB, certB]

def encodeInlineProofSuccessV1 (r : InlineProofSuccessV1) :
    Except String ByteArray := do
  let fields ← encodeSuccessFields r
  let frame ← encodeTagged tagSuccessV1 fields
  checkFrameSize frame
  pure frame

private def decodeSuccessBody : DecoderV1 InlineProofSuccessV1 := fun c => do
  let (requestDigest, c) ← decodeDigest32 c
  let (theoremCount, c) ← decodeU32Field c
  let (theoremSetDigest, c) ← decodeDigest32 c
  let (proofCertificationDigest, c) ← decodeDigest32 c
  let expectedCert ←
    proofCertificationDigestV1 requestDigest theoremCount theoremSetDigest
  unless proofCertificationDigest == expectedCert do
    return ← fail "proofCertificationDigest does not match bound fields"
  pure (⟨requestDigest, theoremCount, theoremSetDigest, proofCertificationDigest⟩, c)

def decodeInlineProofSuccessV1 (input : ByteArray) :
    Except String InlineProofSuccessV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagSuccessV1 do
    return ← fail s!"expected tag '{tagSuccessV1}', got '{tag}'"
  let ((), c) ← decodeFieldCountV1 tagSuccessV1 4 c
  let (success, c) ← decodeSuccessBody c
  finish c
  let reencoded ← encodeInlineProofSuccessV1 success
  requireReencode "InlineProof.Ok.v1" input reencoded
  pure success

private def encodeFailureFields (r : InlineProofFailureV1) :
    Except String (Array ByteArray) := do
  let digB ← encodeDigest32 r.requestDigest_
  let phaseB := encodeU8 (InlineProofFailurePhaseV1.toWire r.phase_)
  pure #[digB, phaseB]

def encodeInlineProofFailureV1 (r : InlineProofFailureV1) :
    Except String ByteArray := do
  let fields ← encodeFailureFields r
  let frame ← encodeTagged tagFailureV1 fields
  checkFrameSize frame
  pure frame

private def decodeFailureBody : DecoderV1 InlineProofFailureV1 := fun c => do
  let (requestDigest, c) ← decodeDigest32 c
  let (phaseWire, c) ← decodeU8 c
  let phase ← match InlineProofFailurePhaseV1.ofWire? phaseWire with
    | some value => pure value
    | none => fail "unknown inline-proof failure phase"
  pure (⟨requestDigest, phase⟩, c)

def decodeInlineProofFailureV1 (input : ByteArray) :
    Except String InlineProofFailureV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagFailureV1 do
    return ← fail s!"expected tag '{tagFailureV1}', got '{tag}'"
  let ((), c) ← decodeFieldCountV1 tagFailureV1 2 c
  let (failure, c) ← decodeFailureBody c
  finish c
  let reencoded ← encodeInlineProofFailureV1 failure
  requireReencode "InlineProof.Err.v1" input reencoded
  pure failure

def encodeInlineProofResponseV1 (response : InlineProofResponseV1) :
    Except String ByteArray :=
  match response with
  | .success value => encodeInlineProofSuccessV1 value
  | .failure value => encodeInlineProofFailureV1 value

def decodeInlineProofResponseV1 (input : ByteArray) :
    Except String InlineProofResponseV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  if tag == tagSuccessV1 then
    let ((), c) ← decodeFieldCountV1 tagSuccessV1 4 c
    let (success, c) ← decodeSuccessBody c
    finish c
    let response := InlineProofResponseV1.success success
    let reencoded ← encodeInlineProofResponseV1 response
    requireReencode "InlineProof.Ok.v1" input reencoded
    pure response
  else if tag == tagFailureV1 then
    let ((), c) ← decodeFieldCountV1 tagFailureV1 2 c
    let (failure, c) ← decodeFailureBody c
    finish c
    let response := InlineProofResponseV1.failure failure
    let reencoded ← encodeInlineProofResponseV1 response
    requireReencode "InlineProof.Err.v1" input reencoded
    pure response
  else
    fail s!"unknown inline-proof response tag '{tag}'"

/-- Mint success from a request: theorem count/set + certification digests. -/
def mkInlineProofSuccessV1 (request : InlineProofRequestV1) :
    Except String InlineProofSuccessV1 := do
  let requestDigest ← inlineProofRequestDigestOfV1 request
  let theoremCount := UInt32.ofNat request.obligations_.size
  let theoremSetDigest ← theoremSetDigestV1 request.obligations_
  let proofCertificationDigest ←
    proofCertificationDigestV1 requestDigest theoremCount theoremSetDigest
  let success : InlineProofSuccessV1 :=
    ⟨requestDigest, theoremCount, theoremSetDigest, proofCertificationDigest⟩
  let _ ← encodeInlineProofSuccessV1 success
  pure success

/-- Mint failure bound to the request digest and a closed phase. -/
def mkInlineProofFailureV1
    (request : InlineProofRequestV1) (phase : InlineProofFailurePhaseV1) :
    Except String InlineProofFailureV1 := do
  let requestDigest ← inlineProofRequestDigestOfV1 request
  let failure : InlineProofFailureV1 := ⟨requestDigest, phase⟩
  let _ ← encodeInlineProofFailureV1 failure
  pure failure

/-- Correlate either response variant with one exact request and reject
    cross-request replay. Does not provide process authentication or freshness. -/
def bindInlineProofResponseV1
    (request : InlineProofRequestV1) (response : InlineProofResponseV1) :
    Except String InlineProofResponseV1 := do
  let expected ← inlineProofRequestDigestOfV1 request
  let actual := match response with
    | .success value => value.requestDigest_
    | .failure value => value.requestDigest_
  unless actual == expected do
    return ← fail "inline-proof response is cross-request replay"
  pure response

end ProofForgeV2.Compiler.InlineProofProtocolV1
