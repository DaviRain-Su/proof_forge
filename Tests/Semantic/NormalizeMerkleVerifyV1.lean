/-
  Tests.Semantic.NormalizeMerkleVerifyV1 — CAP-X-MERKLE-CORE shared-core pins
  for the exact `pf.crypto.merkleVerifyKeccak256(root, leaf, s0…s_{D-1}) ->
  Bool` qualified name (D ∈ 1..8 UInt256 siblings, OpenZeppelin sorted-pair
  hashing; EVM-only leaf, frozen 2026-08-19).

  The shared core change is deliberately small: the QN is registered in
  `Core.RequirementIdsV1` and covered by `isPfCryptoHostSyscallQnV1` so a
  Merkle verify never contributes `effect.synchronous-call` (a guest hash
  chain is pure computation, not a cross-contract call). Normalize needs no
  change: all-UInt256 arguments pass the existing anonymous-integer call gate
  and the Bool result passes the existing serializable-scalar gate. The exact
  typed ABI (arity 2+D, D ∈ 1..8) is target-owned; the Reference machine
  rides the generic ExternalCall response cursor and computes no hash.

  Wave-5 design freeze: `docs/plan/capability-layer-tasks.md` (2026-08-19).
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

namespace Tests.Semantic.NormalizeMerkleVerifyV1

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

private def moduleName : String := "Tests.NormalizeMerkleVerifyV1"

/-- Project-relative path accepted by SourceOrigin validation (no angle brackets). -/
private def testSourcePath (label : String) : String :=
  "tests/normalize-merkle-verify-" ++ label ++ ".pf"

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

private def findAnonTypeId
    (data : SemanticProgramDataV1) (pred : TypeShapeV1 → Bool) (hint : String) :
    IO TypeIdV1 := do
  match data.types.findIdx? fun t => t.name.isNone && pred t.shape with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError s!"missing anonymous type: {hint}"

private def merkleQn : Array String := #["pf", "crypto", "merkleVerifyKeccak256"]

/-- P1: the minimal one-sibling proof normalizes to a result-bearing
    ExternalCall with the exact QN; no `effect.synchronous-call` (or any)
    requirement is contributed. -/
private unsafe def testMinimalProofNormalizes
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MerkleMin" <|
    "  entry verify(root : UInt256, leaf : UInt256, s0 : UInt256) : Bool do\n" ++
    "    return call pf.crypto.merkleVerifyKeccak256(root, leaf, s0)\n"
  let data ← normalizeOk session "minimal" source
  let boolTid ← findAnonTypeId data
    (fun s => match s with | .bool => true | _ => false) "Bool"
  expect (data.callables.size == 1) "minimal: 1 callable"
  let some entryC := data.callables[0]? | throw <| IO.userError "minimal: missing"
  expect (entryC.kind == .entry && entryC.name == some "verify") "minimal: entry verify"
  expect (entryC.params.size == 3) "minimal: three params"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "minimal: missing block"
  expect (blk.instructions.size == 1)
    s!"minimal: 1 instr, got {blk.instructions.size}"
  let some instr := blk.instructions[0]? | throw <| IO.userError "minimal: missing instr"
  match instr.op with
  | .externalCall _ qn args =>
      expect (qn.components.toArray == merkleQn)
        s!"minimal: exact callee QN, got {repr qn.components.toArray}"
      expect (args == #[0, 1, 2])
        s!"minimal: args are the three params in order, got {repr args}"
      let some rd := instr.result |
        throw <| IO.userError "minimal: call missing result"
      expect (rd.typeId == boolTid) "minimal: result Bool"
      match blk.terminator with
      | .return_ (some vid) =>
          expect (vid == rd.valueId) "minimal: return binds call result"
      | _ => throw <| IO.userError "minimal: expected return some"
  | _ => throw <| IO.userError "minimal: expected externalCall op"
  -- `value.bool` comes from the Bool result annotation; the Merkle call must
  -- add nothing (no `effect.synchronous-call`, no `failure.atomic-rollback`).
  expect (data.requirements.items.map (·.id) == #["value.bool"])
    s!"minimal: only value.bool requirement, got {data.requirements.items.map (·.id)}"

/-- P2: the frozen maximum D=8 siblings (arity 10) normalizes. -/
private unsafe def testMaxDepthNormalizes
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MerkleMax" <|
    "  entry verify(root : UInt256, leaf : UInt256, " ++
    "s0 : UInt256, s1 : UInt256, s2 : UInt256, s3 : UInt256, " ++
    "s4 : UInt256, s5 : UInt256, s6 : UInt256, s7 : UInt256) : Bool do\n" ++
    "    return call pf.crypto.merkleVerifyKeccak256(root, leaf, s0, s1, s2, s3, s4, s5, s6, s7)\n"
  let data ← normalizeOk session "max-depth" source
  let some entryC := data.callables[0]? | throw <| IO.userError "max-depth: missing"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "max-depth: missing block"
  let some instr := blk.instructions[0]? |
    throw <| IO.userError "max-depth: missing instr"
  match instr.op with
  | .externalCall _ qn args =>
      expect (qn.components.toArray == merkleQn) "max-depth: exact QN"
      expect (args.size == 10) s!"max-depth: 10 args, got {args.size}"
  | _ => throw <| IO.userError "max-depth: expected externalCall op"

/-- P3: statement-position `call` with UInt256 arguments lowers to a void
    ExternalCall under the unchanged generic statement discipline (the
    target-side result-bearing requirement is enforced by the EVM leaf). -/
private unsafe def testStatementPositionVoidOp
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MerkleStmt" <|
    "  entry verify(root : UInt256, leaf : UInt256, s0 : UInt256) : Bool do\n" ++
    "    call pf.crypto.merkleVerifyKeccak256(root, leaf, s0)\n" ++
    "    return true\n"
  let data ← normalizeOk session "stmt-pos" source
  let some entryC := data.callables[0]? | throw <| IO.userError "stmt-pos: missing"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "stmt-pos: missing block"
  let some instr := blk.instructions[0]? |
    throw <| IO.userError "stmt-pos: missing instr"
  match instr.op with
  | .externalCall _ qn args =>
      expect (qn.components.toArray == merkleQn) "stmt-pos: exact QN"
      expect (args.size == 3) "stmt-pos: three args"
      expect instr.result.isNone "stmt-pos: statement call is void"
  | _ => throw <| IO.userError "stmt-pos: expected externalCall op"
  expect (data.requirements.items.map (·.id) == #["value.bool"])
    s!"stmt-pos: no sync-call contribution even in statement position, got {data.requirements.items.map (·.id)}"

/-- N1: view discipline — the generic `externalCallSync` effect keeps Merkle
    verification out of views (PF-EFFECT-001), same as the hash leaves. -/
private unsafe def testViewEffectFailClosed
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MerkleView" <|
    "  view verify(root : UInt256, leaf : UInt256, s0 : UInt256) : Bool do\n" ++
    "    return call pf.crypto.merkleVerifyKeccak256(root, leaf, s0)\n"
  let validated ← loadSource session "view-effect" source
  let typed := checkProgramTypedResultV1 validated
  expect (!typed.ok) "view-effect: view verification must be typed-not-ok"
  let rendered := typed.diagnostics.map (·.renderHuman)
  expect (rendered.any (fun line =>
      line.startsWith "PF-EFFECT-001: " && containsSubstr line "external.call.sync"))
    s!"view-effect: expected PF-EFFECT-001 external.call.sync, got {rendered}"

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

/-- P4: Reference admission/step rides the generic ExternalCall response
    cursor — the L1 machine computes no Merkle root; the exact
    cursor-supplied Bool is what comes back. -/
private unsafe def testReferenceResponseCursor
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "MerkleRef" <|
    "  entry verify(root : UInt256, leaf : UInt256, s0 : UInt256) : Bool do\n" ++
    "    return call pf.crypto.merkleVerifyKeccak256(root, leaf, s0)\n"
  let (carrier, data) ← normalizeOkCarrier session "reference" source
  let boolTid ← findAnonTypeId data
    (fun s => match s with | .bool => true | _ => false) "Bool"
  let u256Tid ← findAnonTypeId data
    (fun s => match s with | .uint 256 => true | _ => false) "UInt256"
  let entryId ← findCallable data (some "verify")
  let initial ← match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"reference: initial state: {repr e}"
  let word : ByteArray := ByteArray.mk (Array.replicate 32 (0 : UInt8))
  let boolTrue : ReferenceValueV1 := { typeId := boolTid, valueBytes := ⟨#[1]⟩ }
  let responses : ExternalResponsesV1 := #[{
    occurrence := { effectId := 0, occurrence := 0 }
    disposition := .returned
    returnValue? := some boolTrue }]
  let arg : ReferenceValueV1 := { typeId := u256Tid, valueBytes := word }
  let out :=
    step carrier initial
      { callableId := entryId
        args := #[arg, arg, arg]
        context := #[] }
      responses
  match out with
  | .returned _ (some v) _ =>
      expect (v.typeId == boolTid && v.valueBytes == boolTrue.valueBytes)
        "reference: merkleVerify result must equal the cursor-supplied Bool"
  | .returned _ none _ =>
      throw <| IO.userError "reference: expected some return value"
  | .reverted _ _ =>
      throw <| IO.userError "reference: unexpected reverted"
  | .trapped f _ =>
      throw <| IO.userError s!"reference: trapped {repr f}"

/-- Unit: the shared host-syscall predicate covers exactly the new QN. -/
private def testSyscallPredicateUnit : IO Unit := do
  expect (isPfCryptoHostSyscallQnV1 "pf.crypto.merkleVerifyKeccak256")
    "unit: merkleVerifyKeccak256 is a host-syscall-discipline QN"
  expect (isPfCryptoMerkleVerifyKeccak256QnV1 "pf.crypto.merkleVerifyKeccak256")
    "unit: exact merkle predicate"
  expect (!isPfCryptoMerkleVerifyKeccak256QnV1 "pf.crypto.merkleVerifyKeccak")
    "unit: truncated near-miss QN rejected"
  expect (!isPfCryptoMerkleVerifyKeccak256QnV1 "pf.crypto.merkleVerifySha256")
    "unit: sha256 variant is a separate (future) QN"
  expect (!isPfCryptoSha256QnV1 "pf.crypto.merkleVerifyKeccak256")
    "unit: merkle QN is not the legacy sha256 QN"
  expect (!isPfCryptoSha256BytesQnV1 "pf.crypto.merkleVerifyKeccak256")
    "unit: merkle QN is not the sha256Bytes QN"
  expect (!isPfCryptoHostSyscallQnV1 "pf.crypto.merkleVerify")
    "unit: family-prefix near-miss rejected"

unsafe def run : IO Unit := do
  testSyscallPredicateUnit
  let session ← Tests.Language.ParserSession.shared
  testMinimalProofNormalizes session
  testMaxDepthNormalizes session
  testStatementPositionVoidOp session
  testViewEffectFailClosed session
  testReferenceResponseCursor session
  IO.println "  ✓ NormalizeMerkleVerifyV1 (CAP-X-MERKLE-CORE shared core)"

end Tests.Semantic.NormalizeMerkleVerifyV1
