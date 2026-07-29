/-
  ProofForgeV2.Frontend.ProtocolV1 — B9/B9R versioned frontend request/response wire.

  Closed one-frame tagged binary protocol consumed by the B10 standalone frontend
  worker. This codec module remains pure: no process spawn, file open, safe-open,
  supervisor, receipts, CLI/Loader/Compiler product cutover, or target wiring.

  Wire frames (exactly one request or one response frame to EOF; no streaming):

    Frontend.Req.v1  — request
    Frontend.Ok.v1   — success response bound to request digest
    Frontend.Err.v1  — failure response bound to request digest

  Hard bounds (frontend ResourceProfile hard maxima / source limits):
    maxProtocolBytes      = 64 MiB  (also the sole selector allocation/frame guard)
    maxSourceBytes        = 16 MiB  (sourceBytes and canonical root bytes)
    maxNodeSpanCount      = 100000
    maxSelectorBytes      = maxProtocolBytes  (compat alias; NOT a semantic QN limit)
    diagnostic array cap  = maxDiagnosticsV1 + 1 (=101) top-level PF-JCS entries
                            via O(n)/O(1) pre-scan before parsePfJcs allocation;
                            semantic/canonical authority remains parsePfJcs +
                            DiagnosticV1.fromPfJson + mkFailureBundleV1 re-encode

  Request carries:
    * exact SemVer languageVersion (NFC string wire via renderSemVer)
    * validated ProjectRelativePath logical source identity
    * raw UTF-8 moduleSelector / optional programSelector (UTF-8 ok; no NFC gate;
      no arbitrary 4096 semantic cap — exact Lean 1..256 × 1..240 component surface
      and source-diagnostic classification are deferred to Loader)
    * raw sourceBytes (no UTF-8 validation at the protocol layer)

  Success carries:
    * requestDigest = domainSeparatedSha256("proof-forge.frontend-request.v1", exact request bytes)
    * canonical ValidatedSourceV1 root bytes (decode requires
      canonicalValidatedSourceAstBytesV1(source) == carried bytes; reconstruct uses
      sole decodeCanonicalSourceAstBytesV1)
    * SourceByteSpanV1 entries only (u64 start/end) in NodeAssignmentV1 canonical preorder;
      paths are recomputed locally from the decoded source (never transmitted)

  Failure carries:
    * requestDigest
    * canonical PF-JCS diagnostic array text, rebuilt via DiagnosticV1 + mkFailureBundleV1
      with exact re-encode identity (no silent normalize of malformed input)

  Pure decoders enforce frame bounds/tag/field-count/full-consume/re-encode/canonicity.
  Request-bound checks (digest replay, foreign diagnostic sourcePath, span endByte vs
  request sourceBytes) live in bind*/mk*/reconstructFrontendSuccessV1.

  Success reconstruction uses only:
    decodeCanonicalSourceAstBytesV1 → assignNodeIdsV1 zip spans → joinOriginsV1
  There is no second ProgramV1 decoder and no caller-trusted OriginInventory constructor.

  Formal TASK-D1-08 / contained assurance remain pending; the B10 standalone worker
  is not safe-open, supervised, contained, receipt-producing, or a product cutover.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1
import ProofForgeV2.Source.WireV1

namespace ProofForgeV2.Frontend.ProtocolV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1
open ProofForgeV2.Source.WireV1

/-- Frontend protocol hard maximum (ResourceProfile frontend protocol/stdout). -/
def maxProtocolBytes : Nat := 64 * 1024 * 1024

/-- Source open / canonical ProgramV1 root hard maximum. -/
def maxSourceBytes : Nat := 16 * 1024 * 1024

/-- NodeId assignment / span table hard maximum (shared with ProgramV1 node bound). -/
def maxNodeSpanCount : Nat := 100000

/-- Compatibility allocation/frame guard for module/program selector UTF-8 payloads.
    Equal to `maxProtocolBytes`. This is **not** a semantic qualified-name limit:
    every selector frame that fits the protocol byte budget is accepted here;
    exact Lean component legality (1..256 components × 1..240 raw UTF-8 bytes) and
    source-diagnostic classification are deferred to Loader. -/
def maxSelectorBytes : Nat := maxProtocolBytes

/-- Domain tag for request-digest separation (profile-id grammar). -/
def requestDigestDomainV1 : String := "proof-forge.frontend-request.v1"

/-- Top-level PF-JCS diagnostic array entry hard maximum before parsePfJcs:
    `DiagnosticV1.maxDiagnosticsV1` retained errors + one optional `PF-DIAG-LIMIT` (101). -/
private def maxDiagnosticArrayEntriesV1 : Nat := DiagnosticV1.maxDiagnosticsV1 + 1

private def tagRequestV1 : String := "Frontend.Req.v1"
private def tagSuccessV1 : String := "Frontend.Ok.v1"
private def tagFailureV1 : String := "Frontend.Err.v1"

private def fail (detail : String) : Except String α :=
  .error detail

private def encodeU64le (value : UInt64) : ByteArray := Id.run do
  let v := value.toNat
  let mut out := ByteArray.emptyWithCapacity 8
  let mut n := v
  for _ in [:8] do
    out := out.push (UInt8.ofNat (n % 256))
    n := n / 256
  pure out

private def decodeU64le : DecoderV1 UInt64 := fun c => do
  let (b0, c) ← decodeU8 c
  let (b1, c) ← decodeU8 c
  let (b2, c) ← decodeU8 c
  let (b3, c) ← decodeU8 c
  let (b4, c) ← decodeU8 c
  let (b5, c) ← decodeU8 c
  let (b6, c) ← decodeU8 c
  let (b7, c) ← decodeU8 c
  let mut v : Nat := 0
  let mut place : Nat := 1
  for b in #[b0, b1, b2, b3, b4, b5, b6, b7] do
    v := v + b.toNat * place
    place := place * 256
  pure (UInt64.ofNat v, c)

/-- Length-prefixed raw bytes with an explicit max; count checked before copy. -/
private def encodeBoundedBytes (maxLen : Nat) (bytes : ByteArray) :
    Except String ByteArray := do
  unless bytes.size ≤ maxLen do
    return ← fail s!"byte payload exceeds limit {maxLen}"
  unless bytes.size ≤ UInt32.size - 1 do
    return ← fail "byte payload length is not representable"
  pure ((encodeU32le (UInt32.ofNat bytes.size)).append bytes)

/-- Decode length-prefixed bytes via public `decodeU8` (CursorV1 fields are private). -/
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

/-- Length-prefixed UTF-8 string without NFC gate (selectors / JSON payloads). -/
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

private def precheckProtocolSize (input : ByteArray) : Except String Unit := do
  if input.size > maxProtocolBytes then
    return ← fail s!"frontend protocol frame exceeds {maxProtocolBytes} bytes"
  pure ()

private def requireReencode (label : String) (input encoded : ByteArray) :
    Except String Unit := do
  unless input == encoded do
    return ← fail s!"{label} is noncanonical"
  pure ()

/-- Opaque frontend parse request (smart-constructor only). -/
structure FrontendRequestV1 where
  private mk ::
  private languageVersion_ : SemVer
  private sourcePath_ : ProjectRelativePath
  private moduleSelector_ : String
  private programSelector_ : Option String
  private sourceBytes_ : ByteArray

namespace FrontendRequestV1

def languageVersion (r : FrontendRequestV1) : SemVer := r.languageVersion_
def sourcePath (r : FrontendRequestV1) : ProjectRelativePath := r.sourcePath_
def moduleSelector (r : FrontendRequestV1) : String := r.moduleSelector_
def programSelector (r : FrontendRequestV1) : Option String := r.programSelector_
def sourceBytes (r : FrontendRequestV1) : ByteArray := r.sourceBytes_

end FrontendRequestV1

/-- Opaque success response: digest-bound canonical source + preorder spans. -/
structure FrontendSuccessV1 where
  private mk ::
  private requestDigest_ : Digest
  private canonicalBytes_ : ByteArray
  private spans_ : Array SourceByteSpanV1

namespace FrontendSuccessV1

def requestDigest (r : FrontendSuccessV1) : Digest := r.requestDigest_
def canonicalBytes (r : FrontendSuccessV1) : ByteArray := r.canonicalBytes_
def spans (r : FrontendSuccessV1) : Array SourceByteSpanV1 := r.spans_

end FrontendSuccessV1

/-- Opaque failure response: digest-bound canonical DiagnosticBundleV1. -/
structure FrontendFailureV1 where
  private mk ::
  private requestDigest_ : Digest
  private bundle_ : DiagnosticBundleV1

namespace FrontendFailureV1

def requestDigest (r : FrontendFailureV1) : Digest := r.requestDigest_
def diagnostics (r : FrontendFailureV1) : Array DiagnosticV1 :=
  DiagnosticBundleV1.diagnostics r.bundle_
def bundle (r : FrontendFailureV1) : DiagnosticBundleV1 := r.bundle_

end FrontendFailureV1

/-- One response frame (success or failure). -/
inductive FrontendResponseV1 where
  | success (value : FrontendSuccessV1)
  | failure (value : FrontendFailureV1)

private def validateSpanAgainstSource
    (sourceSize : Nat) (span : SourceByteSpanV1) : Except String Unit := do
  unless span.startByte ≤ span.endByte do
    return ← fail "source span startByte must not exceed endByte"
  let endN := span.endByte.toNat
  unless endN ≤ sourceSize do
    return ← fail "source span endByte exceeds sourceBytes size"
  pure ()

private def validateSpansAgainstSource
    (sourceSize : Nat) (spans : Array SourceByteSpanV1) : Except String Unit := do
  unless spans.size ≤ maxNodeSpanCount do
    return ← fail s!"span count exceeds limit {maxNodeSpanCount}"
  for span in spans do
    validateSpanAgainstSource sourceSize span
  pure ()

private def originPathOk
    (expected : ProjectRelativePath) (origin : DiagnosticOriginV1) : Bool :=
  origin.sourcePath == expected

private def diagnosticPathsMatchRequest
    (path : ProjectRelativePath) (diag : DiagnosticV1) : Bool :=
  let primaryOk :=
    match diag.primary with
    | none => true
    | some o => originPathOk path o
  let relatedOk := diag.related.all (originPathOk path)
  primaryOk && relatedOk

private def validateBundlePaths
    (path : ProjectRelativePath) (bundle : DiagnosticBundleV1) : Except String Unit := do
  for d in DiagnosticBundleV1.diagnostics bundle do
    unless diagnosticPathsMatchRequest path d do
      return ← fail "diagnostic origin sourcePath does not match request sourcePath"
  pure ()

/-- Encode request payload fields (no outer tag). -/
private def encodeRequestFields (r : FrontendRequestV1) :
    Except String (Array ByteArray) := do
  let verS ← renderSemVer r.languageVersion_
  let verB ← encodeString verS
  let pathS ← renderProjectRelativePath r.sourcePath_
  let pathB ← encodeString pathS
  let modB ← encodeRawUtf8 maxSelectorBytes r.moduleSelector_
  let progB ← encodeOption (encodeRawUtf8 maxSelectorBytes) r.programSelector_
  let srcB ← encodeBoundedBytes maxSourceBytes r.sourceBytes_
  pure #[verB, pathB, modB, progB, srcB]

/-- Encode the complete request frame (tag + fields). -/
def encodeFrontendRequestV1 (r : FrontendRequestV1) : Except String ByteArray := do
  let fields ← encodeRequestFields r
  let frame ← encodeTagged tagRequestV1 fields
  if frame.size > maxProtocolBytes then
    return ← fail s!"frontend protocol frame exceeds {maxProtocolBytes} bytes"
  pure frame

/-- Domain-separated digest of exact canonical request frame bytes. -/
def requestDigestV1 (requestBytes : ByteArray) : Except String Digest :=
  domainSeparatedSha256 requestDigestDomainV1 requestBytes

/-- Digest of the canonical encoding of `r`. -/
def requestDigestOfV1 (r : FrontendRequestV1) : Except String Digest := do
  let bytes ← encodeFrontendRequestV1 r
  requestDigestV1 bytes

/-- Smart constructor: validates bounds and path/SemVer; keeps sourceBytes raw. -/
def mkFrontendRequestV1
    (languageVersion : SemVer)
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String)
    (sourceBytes : ByteArray) :
    Except String FrontendRequestV1 := do
  let _ ← renderSemVer languageVersion
  validateProjectRelativePath sourcePath
  unless moduleSelector.toUTF8.size ≤ maxSelectorBytes do
    return ← fail s!"moduleSelector exceeds {maxSelectorBytes} UTF-8 bytes"
  match String.fromUTF8? moduleSelector.toUTF8 with
  | none => return ← fail "moduleSelector is not valid UTF-8"
  | some _ => pure ()
  match programSelector with
  | none => pure ()
  | some p =>
      unless p.toUTF8.size ≤ maxSelectorBytes do
        return ← fail s!"programSelector exceeds {maxSelectorBytes} UTF-8 bytes"
      match String.fromUTF8? p.toUTF8 with
      | none => return ← fail "programSelector is not valid UTF-8"
      | some _ => pure ()
  unless sourceBytes.size ≤ maxSourceBytes do
    return ← fail s!"sourceBytes exceed {maxSourceBytes} bytes"
  let req : FrontendRequestV1 :=
    ⟨languageVersion, sourcePath, moduleSelector, programSelector, sourceBytes⟩
  -- Ensure the request frame itself is within the protocol hard max.
  let _ ← encodeFrontendRequestV1 req
  pure req

private def decodeRequestBody : DecoderV1 FrontendRequestV1 := fun c => do
  let (verS, c) ← decodeString c
  let languageVersion ← parseSemVer verS
  let verCanon ← renderSemVer languageVersion
  unless verCanon == verS do
    return ← fail "languageVersion SemVer is noncanonical"
  let (pathS, c) ← decodeString c
  let sourcePath ← parseProjectRelativePath pathS
  let (moduleSelector, c) ← decodeRawUtf8 maxSelectorBytes c
  let (programSelector, c) ← decodeOption (decodeRawUtf8 maxSelectorBytes) c
  let (sourceBytes, c) ← decodeBoundedBytes maxSourceBytes c
  pure (⟨languageVersion, sourcePath, moduleSelector, programSelector, sourceBytes⟩, c)

/-- Full-consume decode with maxProtocolBytes precheck + re-encode identity. -/
def decodeFrontendRequestV1 (input : ByteArray) : Except String FrontendRequestV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagRequestV1 do
    return ← fail s!"expected tag '{tagRequestV1}', got '{tag}'"
  let ((), c) ← decodeFieldCountV1 tagRequestV1 5 c
  let (req, c) ← decodeRequestBody c
  finish c
  let reencoded ← encodeFrontendRequestV1 req
  requireReencode "Frontend.Req.v1" input reencoded
  pure req

private def encodeSpan (span : SourceByteSpanV1) : ByteArray :=
  (encodeU64le span.startByte).append (encodeU64le span.endByte)

private def decodeSpan : DecoderV1 SourceByteSpanV1 := fun c => do
  let (startByte, c) ← decodeU64le c
  let (endByte, c) ← decodeU64le c
  unless startByte ≤ endByte do
    return ← fail "source span startByte must not exceed endByte"
  pure ({ startByte, endByte }, c)

private def encodeSpans (spans : Array SourceByteSpanV1) : Except String ByteArray := do
  unless spans.size ≤ maxNodeSpanCount do
    return ← fail s!"span count exceeds limit {maxNodeSpanCount}"
  unless spans.size ≤ UInt32.size - 1 do
    return ← fail "span count is not representable"
  let mut out := encodeU32le (UInt32.ofNat spans.size)
  for span in spans do
    unless span.startByte ≤ span.endByte do
      return ← fail "source span startByte must not exceed endByte"
    out := out.append (encodeSpan span)
  pure out

private def decodeSpans : DecoderV1 (Array SourceByteSpanV1) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > maxNodeSpanCount then
    return ← fail s!"span count exceeds limit {maxNodeSpanCount}"
  -- Each span is 16 bytes; reject count bombs before allocation growth.
  unless remaining c ≥ count * 16 do
    return ← fail "truncated"
  let mut acc : Array SourceByteSpanV1 := Array.mkEmpty count
  let mut c := c
  for _ in [:count] do
    let (span, c') ← decodeSpan c
    acc := acc.push span
    c := c'
  pure (acc, c)

private def encodeSuccessFields (r : FrontendSuccessV1) :
    Except String (Array ByteArray) := do
  let digB ← encodeDigest32 r.requestDigest_
  let canB ← encodeBoundedBytes maxSourceBytes r.canonicalBytes_
  let spanB ← encodeSpans r.spans_
  pure #[digB, canB, spanB]

def encodeFrontendSuccessV1 (r : FrontendSuccessV1) : Except String ByteArray := do
  let fields ← encodeSuccessFields r
  let frame ← encodeTagged tagSuccessV1 fields
  if frame.size > maxProtocolBytes then
    return ← fail s!"frontend protocol frame exceeds {maxProtocolBytes} bytes"
  pure frame

private def decodeSuccessBody : DecoderV1 FrontendSuccessV1 := fun c => do
  let (requestDigest, c) ← decodeDigest32 c
  let (canonicalBytes, c) ← decodeBoundedBytes maxSourceBytes c
  let (spans, c) ← decodeSpans c
  pure (⟨requestDigest, canonicalBytes, spans⟩, c)

def decodeFrontendSuccessV1 (input : ByteArray) : Except String FrontendSuccessV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagSuccessV1 do
    return ← fail s!"expected tag '{tagSuccessV1}', got '{tag}'"
  let ((), c) ← decodeFieldCountV1 tagSuccessV1 3 c
  let (ok, c) ← decodeSuccessBody c
  finish c
  -- Structure-level validation: root must decode via sole AST decoder; carried
  -- bytes must equal the sole canonical re-encoding of the decoded AST (same
  -- contract as failure's PF-JCS re-encode identity); span count must match
  -- NodeAssignment preorder; each span range is well-formed (end bound vs
  -- request sourceBytes only when paired with a request via bind/mk).
  let source ← decodeCanonicalSourceAstBytesV1 ok.canonicalBytes_
  let canon ← canonicalValidatedSourceAstBytesV1 source
  unless canon == ok.canonicalBytes_ do
    return ← fail "ValidatedSourceV1 root bytes are noncanonical"
  let table ← assignNodeIdsV1 source.moduleName source.programIdentity source.program
  let assignments := nodeAssignmentsPreorderV1 table
  unless ok.spans_.size == assignments.size do
    return ← fail
      s!"span count {ok.spans_.size} != NodeAssignment preorder count {assignments.size}"
  for span in ok.spans_ do
    unless span.startByte ≤ span.endByte do
      return ← fail "source span startByte must not exceed endByte"
  let reencoded ← encodeFrontendSuccessV1 ok
  requireReencode "Frontend.Ok.v1" input reencoded
  pure ok

/-- Non-recursive O(n)/O(1) UTF-8-byte pre-scan of a canonical PF-JCS array text.

    Counts only top-level array entries: commas at root array depth, ignoring
    commas inside strings (with escape handling) and nested arrays/objects.
    Rejects zero or more than `maxDiagnosticArrayEntriesV1` (101) entries before
    `parsePfJcs` allocates a diagnostic array. This is a count/resource preflight
    only — `parsePfJcs` + `DiagnosticV1.fromPfJson` + `mkFailureBundleV1` + exact
    canonical re-encode remain the semantic/canonical authority. -/
private def precheckDiagnosticArrayEntryCountV1 (json : String) : Except String Unit := do
  let bytes := json.toUTF8
  if bytes.size == 0 then
    return ← fail "diagnostic bundle wire must be a JSON array"
  -- '[' = 0x5B
  unless bytes.get! 0 == 0x5B do
    return ← fail "diagnostic bundle wire must be a JSON array"
  -- Empty array "[]" → 0 entries.
  if bytes.size ≥ 2 && bytes.get! 1 == 0x5D then
    return ← fail "diagnostic array entry count is zero"
  -- Nonempty array: start at 1 entry, scan from after '['.
  let mut i : Nat := 1
  let mut depth : Nat := 1
  let mut inString : Bool := false
  let mut escape : Bool := false
  let mut entries : Nat := 1
  let mut closed : Bool := false
  while i < bytes.size do
    let b := bytes.get! i
    i := i + 1
    if inString then
      if escape then
        escape := false
      else if b == 0x5C then
        -- backslash starts a one-byte escape sequence (\" \\ \/ \b \f \n \r \t \uXXXX).
        -- Pre-scan only needs to skip the next structural byte; \u is not expanded.
        escape := true
      else if b == 0x22 then
        inString := false
    else if b == 0x22 then
      inString := true
    else if b == 0x5B || b == 0x7B then
      -- '[' or '{'
      depth := depth + 1
    else if b == 0x5D || b == 0x7D then
      -- ']' or '}'
      if depth == 0 then
        return ← fail "diagnostic array structure underflow"
      if depth == 1 then
        unless b == 0x5D do
          return ← fail "diagnostic array root must close with ']'"
        closed := true
        depth := 0
        -- Stop counting; any trailing bytes are owned by parsePfJcs / re-encode.
        break
      else
        depth := depth - 1
    else if b == 0x2C && depth == 1 then
      -- top-level comma
      entries := entries + 1
      if entries > maxDiagnosticArrayEntriesV1 then
        return ← fail
          s!"diagnostic array entry count exceeds {maxDiagnosticArrayEntriesV1}"
  if !closed then
    return ← fail "diagnostic array is unclosed"
  if inString || escape then
    return ← fail "diagnostic array has unclosed string"
  if entries == 0 then
    return ← fail "diagnostic array entry count is zero"
  if entries > maxDiagnosticArrayEntriesV1 then
    return ← fail
      s!"diagnostic array entry count exceeds {maxDiagnosticArrayEntriesV1}"
  pure ()

private def encodeFailureFields (r : FrontendFailureV1) :
    Except String (Array ByteArray) := do
  let digB ← encodeDigest32 r.requestDigest_
  let json ← DiagnosticBundleV1.renderCanonicalJsonArray r.bundle_
  let jsonB ← encodeRawUtf8 maxProtocolBytes json
  pure #[digB, jsonB]

def encodeFrontendFailureV1 (r : FrontendFailureV1) : Except String ByteArray := do
  let fields ← encodeFailureFields r
  let frame ← encodeTagged tagFailureV1 fields
  if frame.size > maxProtocolBytes then
    return ← fail s!"frontend protocol frame exceeds {maxProtocolBytes} bytes"
  pure frame

private def decodeFailureBody : DecoderV1 FrontendFailureV1 := fun c => do
  let (requestDigest, c) ← decodeDigest32 c
  let (json, c) ← decodeRawUtf8 maxProtocolBytes c
  -- Count/resource preflight before parsePfJcs allocates the array.
  precheckDiagnosticArrayEntryCountV1 json
  let value ← parsePfJcs json
  let diags ←
    match value with
    | .array arr =>
        arr.mapM fun v => do
          let diag ← DiagnosticV1.fromPfJson v
          let re ← DiagnosticV1.toCanonicalJson diag
          let value2 ← parsePfJcs re
          -- Per-diagnostic canonical identity (object-level).
          let re2 ← DiagnosticV1.toCanonicalJson (← DiagnosticV1.fromPfJson value2)
          unless re == re2 do
            throw "diagnostic JSON is noncanonical"
          pure diag
    | _ => throw "diagnostic bundle wire must be a JSON array"
  let bundle := mkFailureBundleV1 diags
  let reJson ← DiagnosticBundleV1.renderCanonicalJsonArray bundle
  unless reJson == json do
    return ← fail "diagnostic bundle JSON is noncanonical"
  pure (⟨requestDigest, bundle⟩, c)

def decodeFrontendFailureV1 (input : ByteArray) : Except String FrontendFailureV1 := do
  precheckProtocolSize input
  let c := start input
  let (tag, c) ← decodeTagV1 c
  unless tag == tagFailureV1 do
    return ← fail s!"expected tag '{tagFailureV1}', got '{tag}'"
  let ((), c) ← decodeFieldCountV1 tagFailureV1 2 c
  let (err, c) ← decodeFailureBody c
  finish c
  let reencoded ← encodeFrontendFailureV1 err
  requireReencode "Frontend.Err.v1" input reencoded
  pure err

/-- Decode one success or failure response frame (tag-dispatched). -/
def decodeFrontendResponseV1 (input : ByteArray) : Except String FrontendResponseV1 := do
  precheckProtocolSize input
  let c0 := start input
  let (tag, _) ← decodeTagV1 c0
  if tag == tagSuccessV1 then
    -- Re-run full success decoder on original input (re-encode identity).
    let ok ← decodeFrontendSuccessV1 input
    pure (.success ok)
  else if tag == tagFailureV1 then
    let err ← decodeFrontendFailureV1 input
    pure (.failure err)
  else
    fail s!"expected response tag '{tagSuccessV1}' or '{tagFailureV1}', got '{tag}'"

/-- Smart constructor for success: binds digest, validates span/node join shape. -/
def mkFrontendSuccessV1
    (request : FrontendRequestV1)
    (source : ValidatedSourceV1)
    (spans : Array SourceByteSpanV1) :
    Except String FrontendSuccessV1 := do
  let digest ← requestDigestOfV1 request
  let canonicalBytes ← canonicalValidatedSourceAstBytesV1 source
  unless canonicalBytes.size ≤ maxSourceBytes do
    return ← fail s!"canonical source bytes exceed {maxSourceBytes}"
  validateSpansAgainstSource request.sourceBytes_.size spans
  let table ← assignNodeIdsV1 source.moduleName source.programIdentity source.program
  let assignments := nodeAssignmentsPreorderV1 table
  unless spans.size == assignments.size do
    return ← fail
      s!"span count {spans.size} != NodeAssignment preorder count {assignments.size}"
  -- Prove joinOriginsV1 accepts this pairing before retaining the success frame.
  let mut paired : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1) :=
    Array.mkEmpty assignments.size
  for i in [:assignments.size] do
    match assignments[i]?, spans[i]? with
    | some a, some span => paired := paired.push (a.path, span)
    | _, _ => return ← fail "span/assignment zip incomplete"
  let _ ←
    match joinOriginsV1 source request.sourcePath_ paired with
    | .ok inv => pure inv
    | .error e => fail s!"joinOriginsV1 rejected success payload: {repr e}"
  let ok : FrontendSuccessV1 := ⟨digest, canonicalBytes, spans⟩
  let _ ← encodeFrontendSuccessV1 ok
  pure ok

/-- Smart constructor for failure: binds digest, mkFailureBundleV1, path check. -/
def mkFrontendFailureV1
    (request : FrontendRequestV1)
    (diagnostics : Array DiagnosticV1) :
    Except String FrontendFailureV1 := do
  let digest ← requestDigestOfV1 request
  let bundle := mkFailureBundleV1 diagnostics
  validateBundlePaths request.sourcePath_ bundle
  let err : FrontendFailureV1 := ⟨digest, bundle⟩
  let _ ← encodeFrontendFailureV1 err
  pure err

/-- Pair a success response with its request; reject cross-request replay and
    span range / count tampering relative to the request source snapshot. -/
def bindFrontendSuccessV1
    (request : FrontendRequestV1)
    (success : FrontendSuccessV1) :
    Except String FrontendSuccessV1 := do
  let digest ← requestDigestOfV1 request
  unless success.requestDigest_ == digest do
    return ← fail "success requestDigest does not match request (cross-request replay)"
  validateSpansAgainstSource request.sourceBytes_.size success.spans_
  pure success

/-- Pair a failure response with its request; reject cross-request replay and
    foreign diagnostic sourcePath values. -/
def bindFrontendFailureV1
    (request : FrontendRequestV1)
    (failure : FrontendFailureV1) :
    Except String FrontendFailureV1 := do
  let digest ← requestDigestOfV1 request
  unless failure.requestDigest_ == digest do
    return ← fail "failure requestDigest does not match request (cross-request replay)"
  validateBundlePaths request.sourcePath_ failure.bundle_
  pure failure

/-- Reconstruct ValidatedSourceV1 + OriginInventoryV1 from a digest-bound success.

    Sole path: decodeCanonicalSourceAstBytesV1 → assignNodeIdsV1 preorder zip
    with transmitted spans → joinOriginsV1 (request sourcePath). -/
def reconstructFrontendSuccessV1
    (request : FrontendRequestV1)
    (success : FrontendSuccessV1) :
    Except String (ValidatedSourceV1 × OriginInventoryV1) := do
  let success ← bindFrontendSuccessV1 request success
  let source ← decodeCanonicalSourceAstBytesV1 success.canonicalBytes_
  -- Defense-in-depth: success frames must carry the unique canonical root encoding.
  let canon ← canonicalValidatedSourceAstBytesV1 source
  unless canon == success.canonicalBytes_ do
    return ← fail "ValidatedSourceV1 root bytes are noncanonical"
  let table ← assignNodeIdsV1 source.moduleName source.programIdentity source.program
  let assignments := nodeAssignmentsPreorderV1 table
  unless success.spans_.size == assignments.size do
    return ← fail
      s!"span count {success.spans_.size} != NodeAssignment preorder count {assignments.size}"
  let mut paired : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1) :=
    Array.mkEmpty assignments.size
  for i in [:assignments.size] do
    match assignments[i]?, success.spans_[i]? with
    | some a, some span => paired := paired.push (a.path, span)
    | _, _ => return ← fail "span/assignment zip incomplete"
  match joinOriginsV1 source request.sourcePath_ paired with
  | .ok inv => pure (source, inv)
  | .error e => fail s!"joinOriginsV1: {repr e}"

end ProofForgeV2.Frontend.ProtocolV1
