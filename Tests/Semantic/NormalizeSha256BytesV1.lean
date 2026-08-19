/-
  Tests.Semantic.NormalizeSha256BytesV1 — CAP-X-BYTES-CORE shared-core pins for
  the exact `pf.crypto.sha256Bytes(Bytes N) -> UInt256` qualified name.

  The shared core only ADMITS the Bytes-argument shape for the exact new QN:
  `Core.RequirementIdsV1.isPfCryptoHostSyscallQnV1` covers it (env-read
  discipline: no `effect.synchronous-call` contribution), and Normalize's
  expression-position call arm accepts anonymous `Bytes N` (`N ≤
  maxTypeLengthV1`) arguments for that QN only. Every other QN keeps the
  anonymous UInt/Int (expression) / UInt/Int/Principal (statement) discipline.
  The exact typed ABI (one `Bytes N` argument, UInt256 result) stays
  target-owned; the Reference machine rides the generic ExternalCall response
  cursor and computes no hash.

  Wave-4 design freeze: `docs/plan/capability-layer-tasks.md` (2026-08-19).
-/
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Typed.CheckV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1

namespace Tests.Semantic.NormalizeSha256BytesV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Typed.CheckV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def moduleName : String := "Tests.NormalizeSha256BytesV1"

/-- Project-relative path accepted by SourceOrigin validation (no angle brackets). -/
private def testSourcePath (label : String) : String :=
  "tests/normalize-sha256bytes-" ++ label ++ ".pf"

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

private unsafe def loadSource
    (session : Language.Loader.ParserSession) (label source : String) :
    IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 source (testSourcePath label) moduleName none with
  | .ok validated => pure validated
  | .error error => throw <| IO.userError s!"{label}: load failed: {error.render}"

/-- Load → CheckV1 ok∧analysisComplete → Normalize → structure-gated data. -/
private unsafe def normalizeOkCarrier
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (SemanticProgramV1 × SemanticProgramDataV1) := do
  let validated ← loadSource session label source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok s!"{label}: CheckV1.ok required"
  expect typed.analysisComplete s!"{label}: CheckV1.analysisComplete"
  let carrier ← match normalizeProgramV1 validated with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"{label}: normalize failed: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"{label}: validate failed: {repr e}"
  pure (carrier, data)

private unsafe def normalizeOk
    (session : Language.Loader.ParserSession) (label source : String) :
    IO SemanticProgramDataV1 := do
  let (_, data) ← normalizeOkCarrier session label source
  pure data

/-- Require CheckV1 ok∧analysisComplete then normalize → .unsupported with detail pin. -/
private unsafe def expectUnsupportedAfterCheckOk
    (session : Language.Loader.ParserSession) (label source : String)
    (detailPred : String → Bool) (detailHint : String) : IO Unit := do
  let validated ← loadSource session label source
  let typed := checkProgramTypedResultV1 validated
  expect typed.ok s!"{label}: CheckV1.ok required for normalizer-boundary pin"
  expect typed.analysisComplete s!"{label}: CheckV1.analysisComplete"
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError s!"{label}: expected unsupported, got carrier"
  | .error (.unsupported detail) =>
      expect (detailPred detail)
        s!"{label}: expected unsupported detail containing {detailHint}, got {detail}"
  | .error e =>
      throw <| IO.userError s!"{label}: expected .unsupported, got {repr e}"

private def findAnonTypeId
    (data : SemanticProgramDataV1) (pred : TypeShapeV1 → Bool) (hint : String) :
    IO TypeIdV1 := do
  match data.types.findIdx? fun t => t.name.isNone && pred t.shape with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError s!"missing anonymous type: {hint}"

private def singleEntry
    (data : SemanticProgramDataV1) (label : String) : IO CallableV1 := do
  expect (data.callables.size == 1) s!"{label}: 1 callable, got {data.callables.size}"
  let some c := data.callables[0]? | throw <| IO.userError s!"{label}: missing callable"
  expect (c.kind == .entry) s!"{label}: callable kind entry"
  pure c

/-- Pin the sole instruction sequence `[argProducer…, externalCall]` of a
    single-block entry ending in `return some <callResult>`. -/
private def expectSha256BytesCall
    (label : String) (data : SemanticProgramDataV1) (entryC : CallableV1)
    (bytesTid u256Tid : TypeIdV1) (argProducerCount : Nat) : IO Unit := do
  let some blk := entryC.blocks[0]? |
    throw <| IO.userError s!"{label}: missing entry block[0]"
  expect (entryC.blocks.size == 1 && blk.id == 0) s!"{label}: single block 0"
  expect (blk.instructions.size == argProducerCount + 1)
    s!"{label}: instr count {argProducerCount + 1}, got {blk.instructions.size}"
  let some callInstr := blk.instructions[argProducerCount]? |
    throw <| IO.userError s!"{label}: missing call instr"
  let some callResult := callInstr.result |
    throw <| IO.userError s!"{label}: call missing result"
  match callInstr.op with
  | .externalCall _ qn args =>
      expect (qn.components.toArray == #["pf", "crypto", "sha256Bytes"])
        s!"{label}: exact callee QN, got {repr qn.components.toArray}"
      expect (args.size == 1) s!"{label}: one arg, got {args.size}"
      expect (callResult.typeId == u256Tid)
        s!"{label}: result UInt256 TypeId, got {callResult.typeId}"
  | _ => throw <| IO.userError s!"{label}: expected externalCall op"
  match blk.terminator with
  | .return_ (some vid) =>
      expect (vid == callResult.valueId)
        s!"{label}: return binds call result, got {vid} vs {callResult.valueId}"
  | _ => throw <| IO.userError s!"{label}: expected return some"
  -- Sanity: the pinned Bytes type really is interned anonymously.
  let some bytesDecl := data.types[bytesTid.toNat]? |
    throw <| IO.userError s!"{label}: bytes TypeId out of range"
  expect bytesDecl.name.isNone s!"{label}: bytes type anonymous"

/-- P1: state `Bytes 32` argument lowers to a result-bearing ExternalCall with
    the exact QN; crypto host-syscall discipline keeps the requirement set free
    of `effect.synchronous-call` / `failure.atomic-rollback`. -/
private unsafe def testStateArgHappyPath
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesState" <|
    "  state data : Bytes 32\n" ++
    "  entry hashIt() : UInt256 do\n" ++
    "    let h : UInt256 := call pf.crypto.sha256Bytes(data)\n" ++
    "    return h\n"
  let data ← normalizeOk session "state-arg" source
  let bytesTid ← findAnonTypeId data
    (fun s => match s with | .bytes n => n.toNat == 32 | _ => false) "Bytes 32"
  let u256Tid ← findAnonTypeId data
    (fun s => match s with | .uint 256 => true | _ => false) "UInt256"
  let entryC ← singleEntry data "state-arg"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "state-arg: block"
  -- instr[0] must be the stateLoad producing the Bytes argument.
  let some loadInstr := blk.instructions[0]? |
    throw <| IO.userError "state-arg: missing load instr"
  match loadInstr.op with
  | .stateLoad sid =>
      expect (sid == 0) s!"state-arg: load state0, got {sid}"
      let some rd := loadInstr.result |
        throw <| IO.userError "state-arg: load missing result"
      expect (rd.typeId == bytesTid) "state-arg: load result Bytes 32"
  | _ => throw <| IO.userError "state-arg: instr[0] expected stateLoad"
  expectSha256BytesCall "state-arg" data entryC bytesTid u256Tid 1
  expect (data.requirements.items.map (·.id) == #["state.persistent"])
    s!"state-arg: requirements {data.requirements.items.map (·.id)}"

/-- P2: parameter `Bytes 64` argument in direct return position; requirement
    set stays empty (no state, no sync-call contribution). -/
private unsafe def testParamArgReturnPosition
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesParam" <|
    "  entry hashParam(b : Bytes 64) : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytes(b)\n"
  let data ← normalizeOk session "param-arg" source
  let bytesTid ← findAnonTypeId data
    (fun s => match s with | .bytes n => n.toNat == 64 | _ => false) "Bytes 64"
  let u256Tid ← findAnonTypeId data
    (fun s => match s with | .uint 256 => true | _ => false) "UInt256"
  let entryC ← singleEntry data "param-arg"
  expect (entryC.params.size == 1) "param-arg: one param"
  expectSha256BytesCall "param-arg" data entryC bytesTid u256Tid 0
  expect data.requirements.items.isEmpty
    s!"param-arg: empty requirements, got {data.requirements.items.map (·.id)}"

/-- P3: `Bytes 4096` (= `maxTypeLengthV1`) argument is admitted. -/
private unsafe def testCapBoundaryAdmitted
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesMax" <|
    "  entry hashMax(b : Bytes 4096) : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytes(b)\n"
  let data ← normalizeOk session "cap-4096" source
  let bytesTid ← findAnonTypeId data
    (fun s => match s with | .bytes n => n.toNat == 4096 | _ => false) "Bytes 4096"
  let u256Tid ← findAnonTypeId data
    (fun s => match s with | .uint 256 => true | _ => false) "UInt256"
  let entryC ← singleEntry data "cap-4096"
  expectSha256BytesCall "cap-4096" data entryC bytesTid u256Tid 0

/-- N1: an integer argument to the exact QN stays fail closed — the QN-scoped
    admission replaces (not widens) the integer gate. -/
private unsafe def testIntegerArgFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesIntArg" <|
    "  entry hashInt(x : UInt64) : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytes(x)\n"
  expectUnsupportedAfterCheckOk session "int-arg" source
    (fun d => containsSubstr d "sha256Bytes" && containsSubstr d "Bytes")
    "sha256Bytes … Bytes"

/-- N2: a near-miss QN with a Bytes argument keeps the generic
    anonymous-integer discipline. -/
private unsafe def testNearMissQnFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesNearMiss" <|
    "  state data : Bytes 32\n" ++
    "  entry hashIt() : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytess(data)\n"
  expectUnsupportedAfterCheckOk session "near-miss" source
    (fun d => containsSubstr d "anonymous UInt/Int") "anonymous UInt/Int"

/-- N3: statement-position `call` of the new QN with a Bytes argument keeps the
    statement-side integer/Principal discipline. -/
private unsafe def testStatementPositionFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesStmt" <|
    "  entry hashStmt(b : Bytes 64) : UInt256 do\n" ++
    "    call pf.crypto.sha256Bytes(b)\n" ++
    "    return 0\n"
  expectUnsupportedAfterCheckOk session "stmt-pos" source
    (fun d => containsSubstr d "UInt/Int/Principal") "UInt/Int/Principal"

/-- N4: `Bytes 4097` (> `maxTypeLengthV1`) never reaches Normalize — the
    source type surface itself rejects it (PF-SRC-INVALID). The QN-scoped
    `N ≤ 4096` check at Normalize is fail-closed defense behind that gate. -/
private unsafe def testCapOverflowFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesTooBig" <|
    "  entry hashTooBig(b : Bytes 4097) : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytes(b)\n"
  match ← session.selectProgramV1 source (testSourcePath "cap-4097") moduleName none with
  | .ok _ => throw <| IO.userError "cap-4097: Bytes 4097 unexpectedly loaded"
  | .error error =>
      expect (containsSubstr error.render "PF-SRC-INVALID")
        s!"cap-4097: expected PF-SRC-INVALID, got {error.render}"

/-- P4: the legacy `pf.crypto.sha256(UInt256) -> UInt256` leaf is unchanged. -/
private unsafe def testLegacySha256Regression
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaWordLegacy" <|
    "  entry hashWord(x : UInt256) : UInt256 do\n" ++
    "    return call pf.crypto.sha256(x)\n"
  let data ← normalizeOk session "legacy-sha256" source
  let u256Tid ← findAnonTypeId data
    (fun s => match s with | .uint 256 => true | _ => false) "UInt256"
  let entryC ← singleEntry data "legacy-sha256"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "legacy-sha256: block"
  expect (blk.instructions.size == 1)
    s!"legacy-sha256: 1 instr, got {blk.instructions.size}"
  let some instr := blk.instructions[0]? |
    throw <| IO.userError "legacy-sha256: missing instr"
  match instr.op with
  | .externalCall _ qn args =>
      expect (qn.components.toArray == #["pf", "crypto", "sha256"])
        "legacy-sha256: exact legacy QN"
      expect (args.size == 1 && args[0]? == some 0) "legacy-sha256: one param arg"
      let some rd := instr.result |
        throw <| IO.userError "legacy-sha256: missing result"
      expect (rd.typeId == u256Tid) "legacy-sha256: result UInt256"
  | _ => throw <| IO.userError "legacy-sha256: expected externalCall op"
  expect data.requirements.items.isEmpty
    "legacy-sha256: empty requirements (host-syscall discipline)"

/-- P5: view discipline is identical to the legacy leaf — the generic
    `externalCallSync` effect keeps hashing out of views (PF-EFFECT-001). -/
private unsafe def testViewEffectFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesView" <|
    "  state data : Bytes 32\n" ++
    "  view hashView() : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytes(data)\n"
  let validated ← loadSource session "view-effect" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "view-effect: view hashing must be typed-not-ok"
  let rendered := typed.diagnostics.map (·.renderHuman)
  expect (rendered.any (fun line =>
      line.startsWith "PF-EFFECT-001: " && containsSubstr line "external.call.sync"))
    s!"view-effect: expected PF-EFFECT-001 external.call.sync, got {rendered}"

/-- Unit: the shared host-syscall predicate covers exactly the new QN. -/
private def testSyscallPredicateUnit : IO Unit := do
  expect (isPfCryptoHostSyscallQnV1 "pf.crypto.sha256Bytes")
    "unit: sha256Bytes is a host-syscall QN"
  expect (isPfCryptoHostSyscallQnV1 "pf.crypto.sha256")
    "unit: sha256 remains a host-syscall QN"
  expect (isPfCryptoHostSyscallQnV1 "pf.crypto.keccak256")
    "unit: keccak256 remains a host-syscall QN"
  expect (!isPfCryptoHostSyscallQnV1 "pf.crypto.sha256Bytess")
    "unit: near-miss QN rejected"
  expect (!isPfCryptoSha256QnV1 "pf.crypto.sha256Bytes")
    "unit: sha256Bytes is not the legacy sha256 QN"
  expect (isPfCryptoSha256BytesQnV1 "pf.crypto.sha256Bytes")
    "unit: exact sha256Bytes predicate"

private def findCallable (data : SemanticProgramDataV1) (name : Option String) :
    IO CallableIdV1 := do
  let mut i : Nat := 0
  for c in data.callables do
    match name, c.name with
    | none, none => return UInt32.ofNat i
    | some want, some got =>
        if got == want then return UInt32.ofNat i
    | _, _ => pure ()
    i := i + 1
  throw <| IO.userError s!"callable not found: {repr name}"

private def u256LeBytes (n : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity 32
  let mut v := n
  for _ in [:32] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

/-- P6: Reference admission/step rides the generic ExternalCall response
    cursor — the L1 machine computes no hash; the exact cursor-supplied value
    is what comes back. -/
private unsafe def testReferenceResponseCursor
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ShaBytesRef" <|
    "  entry hashParam(b : Bytes 64) : UInt256 do\n" ++
    "    return call pf.crypto.sha256Bytes(b)\n"
  let (carrier, data) ← normalizeOkCarrier session "reference" source
  let u256Tid ← findAnonTypeId data
    (fun s => match s with | .uint 256 => true | _ => false) "UInt256"
  let bytesTid ← findAnonTypeId data
    (fun s => match s with | .bytes n => n.toNat == 64 | _ => false) "Bytes 64"
  let entryId ← findCallable data (some "hashParam")
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"reference: initial state: {repr e}"
  -- Canonical `Bytes N` valueBytes = exactly N raw bytes (no length prefix).
  let argBytes : ByteArray := ByteArray.mk (Array.replicate 64 (0xAB : UInt8))
  let digestVal : ReferenceValueV1 :=
    { typeId := u256Tid, valueBytes := u256LeBytes 0xC0DE }
  let responses : ExternalResponsesV1 := #[{
    occurrence := { effectId := 0, occurrence := 0 }
    disposition := .returned
    returnValue? := some digestVal }]
  let out :=
    step carrier initial
      { callableId := entryId
        args := #[{ typeId := bytesTid, valueBytes := argBytes }]
        context := #[] }
      responses
  match out with
  | .returned _ (some v) _ =>
      expect (v.typeId == digestVal.typeId && v.valueBytes == digestVal.valueBytes)
        "reference: sha256Bytes result must equal the cursor-supplied value"
  | .returned _ none _ =>
      throw <| IO.userError "reference: expected some return value"
  | .reverted _ _ =>
      throw <| IO.userError "reference: unexpected reverted"
  | .trapped f _ =>
      throw <| IO.userError s!"reference: trapped {repr f}"

unsafe def run : IO Unit := do
  testSyscallPredicateUnit
  let session ← Tests.Language.ParserSession.shared
  testStateArgHappyPath session
  testParamArgReturnPosition session
  testCapBoundaryAdmitted session
  testIntegerArgFailClosed session
  testNearMissQnFailClosed session
  testStatementPositionFailClosed session
  testCapOverflowFailClosed session
  testLegacySha256Regression session
  testViewEffectFailClosed session
  testReferenceResponseCursor session
  IO.println "  ✓ NormalizeSha256BytesV1 (CAP-X-BYTES-CORE shared core)"

end Tests.Semantic.NormalizeSha256BytesV1
