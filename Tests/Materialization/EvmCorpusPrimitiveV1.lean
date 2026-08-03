/-
  Tests.Materialization.EvmCorpusPrimitiveV1 — engineering Reference leg for
  EVMOZ-004 primitive corpus cases (Counter / Accumulator / ArithOps / EventFlow).

  Top-level `main` harness (not a lake import root — avoids global main clash).
  EVMOZ-006 wires ordinary CI via `just evm-corpus-reference` /
  `just evm-corpus-static` (not Tests.lean import). Invoke via:
    lake env lean --run Tests/Materialization/EvmCorpusPrimitiveV1.lean -- <out-dir>


  Real path: Loader → NormalizeV1 → admitReferenceProgramSliceV1 →
  stepReferenceSliceV1. Writes intermediate shared JSON (not PF-JCS); Python
  `scripts/evm_corpus_reference.sh` canonicalizes into proof-forge.evm-observation.v1.

  Not formal Reference↔Anvil / C-3 / OZ credit.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ReferenceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Materialization.EvmCorpusPrimitiveV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def leBytesFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

private def leBytesToNat (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  let mut place : Nat := 1
  for b in bytes do
    n := n + b.toNat * place
    place := place * 256
  pure n

private def u64Bytes (n : Nat) : ByteArray := leBytesFromNat n 8

private def refU64 (typeId : TypeIdV1) (n : Nat) : ReferenceValueV1 :=
  { typeId, valueBytes := u64Bytes n }

private def emptyResponses : ExternalResponsesV1 := #[]

private def inv (callableId : CallableIdV1) (args : Array ReferenceValueV1) :
    InvocationV1 :=
  { callableId, args, context := #[] }

private def hexLower (bytes : ByteArray) : String := Id.run do
  let mut s := ""
  for b in bytes do
    let hi := b.toNat / 16
    let lo := b.toNat % 16
    let d (x : Nat) : Char :=
      if x < 10 then Char.ofNat (x + '0'.toNat) else Char.ofNat (x - 10 + 'a'.toNat)
    s := s.push (d hi) |>.push (d lo)
  pure s

private def digestHex (d : Digest) : IO String :=
  match renderDigest d with
  | .ok s =>
      -- renderDigest → "sha256:<64hex>"; strip prefix for pin compare.
      match s.dropPrefix? "sha256:" with
      | some rest => pure rest.toString
      | none => pure s
  | .error e => throw <| IO.userError e

/-- Decode sole UInt64 state slot: u32le(len=8) || LE8. -/
private def decodeSoleU64 (logical : LogicalStateV1) : IO Nat := do
  let cv := logical.canonicalValues
  if cv.size < 12 then
    throw <| IO.userError s!"state slot too short: {cv.size}"
  let data := cv.data
  let byteAt (i : Nat) : Nat :=
    match data[i]? with
    | some b => b.toNat
    | none => 0
  let len := byteAt 0 + byteAt 1 * 256 + byteAt 2 * 65536 + byteAt 3 * 16777216
  unless len == 8 do
    throw <| IO.userError s!"expected u64 value length 8, got {len}"
  let mut payload := ByteArray.emptyWithCapacity 8
  for i in [4:12] do
    match data[i]? with
    | some b => payload := payload.push b
    | none => pure ()
  pure (leBytesToNat payload)

private def findU64TypeId (data : SemanticProgramDataV1) : IO TypeIdV1 :=
  match data.types.findIdx? fun t =>
      t.name.isNone && match t.shape with | .uint 64 => true | _ => false with
  | some i => pure (UInt32.ofNat i)
  | none => throw <| IO.userError "missing anonymous UInt64 TypeId"

private def findCallableId (data : SemanticProgramDataV1) (name : Option String) :
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

private def jsonEscape (s : String) : String := Id.run do
  let mut out := "\""
  for c in s.toList do
    if c == '"' then out := out ++ "\\\""
    else if c == '\\' then out := out ++ "\\\\"
    else if c == '\n' then out := out ++ "\\n"
    else out := out.push c
  pure (out ++ "\"")

private def jsonStr (s : String) : String := jsonEscape s

private def jsonNat (n : Nat) : String := toString n

/-- Intermediate shared observation (Python mints PF-JCS). -/
private def writeSharedStep
    (outDir : System.FilePath) (caseId : String) (stepIndex : Nat)
    (status : String) (returnValue : Option String)
    (stateKey : String) (stateVal : Nat)
    (effectsJson : String) (rollbackEqual : Bool) : IO Unit := do
  let dir := outDir / caseId
  IO.FS.createDirAll dir
  let path := dir / s!"reference-step-{stepIndex}.raw.json"
  let ret :=
    match returnValue with
    | none => "null"
    | some v => jsonStr v
  let rb := if rollbackEqual then "true" else "false"
  let body :=
    "{" ++
    "\"caseId\":" ++ jsonStr caseId ++ "," ++
    "\"leg\":\"reference\"," ++
    "\"stepIndex\":" ++ jsonNat stepIndex ++ "," ++
    "\"status\":" ++ jsonStr status ++ "," ++
    "\"returnValue\":" ++ ret ++ "," ++
    "\"logicalState\":{" ++ jsonStr stateKey ++ ":" ++ jsonStr (toString stateVal) ++ "}," ++
    "\"effects\":" ++ effectsJson ++ "," ++
    "\"rollbackEqual\":" ++ rb ++
    "}"
  IO.FS.writeFile path body

private def effectsEmpty : String := "[]"

private def effectsMoved (src dst : Nat) : String :=
  "[{\"kind\":\"event\",\"eventId\":0,\"args\":[" ++
    jsonStr (toString src) ++ "," ++ jsonStr (toString dst) ++ "]}]"

private def joinComma (parts : Array String) : String := Id.run do
  let mut acc := ""
  let mut first := true
  for p in parts do
    if first then
      acc := p
      first := false
    else
      acc := acc ++ "," ++ p
  pure acc

private def outcomeShared
    (outcome : OutcomeV1) (_pre : LogicalStateV1) :
    IO (String × Option String × LogicalStateV1 × String × Bool) := do
  match outcome with
  | .returned post value effects =>
      let ret ←
        match value with
        | none => pure none
        | some v => pure (some (toString (leBytesToNat v.valueBytes)))
      let mut effParts : Array String := #[]
      for e in effects do
        match e.payload with
        | .event eid args =>
            let mut argStrs : Array String := #[]
            for a in args do
              argStrs := argStrs.push (jsonStr (toString (leBytesToNat a.valueBytes)))
            let joined := joinComma argStrs
            effParts := effParts.push <|
              "{\"kind\":\"event\",\"eventId\":" ++ toString eid.toNat ++
              ",\"args\":[" ++ joined ++ "]}"
        | .externalCall _ _ =>
            effParts := effParts.push "{\"kind\":\"externalCall\"}"
        | .schedule _ _ =>
            effParts := effParts.push "{\"kind\":\"schedule\"}"
      let effectsJson := "[" ++ joinComma effParts ++ "]"
      pure ("success", ret, post, effectsJson, true)
  | .reverted _ st =>
      pure ("revert", none, st, effectsEmpty, true)
  | .trapped _ st =>
      pure ("trap", none, st, effectsEmpty, true)

private structure ProgramSpec where
  caseId : String
  sourcePath : String
  moduleName : String
  stateKey : String
  expectedSourceHash : String
  expectedSemanticHash : String

private unsafe def loadNormalizeAdmit
    (session : Language.Loader.ParserSession) (repoRoot : System.FilePath)
    (spec : ProgramSpec) :
    IO (SemanticProgramV1 × SemanticProgramDataV1 × AdmittedReferenceSliceV1 ×
        TypeIdV1 × String × String) := do
  let absPath := repoRoot / spec.sourcePath
  let src ← IO.FS.readFile absPath
  match ← session.selectProgramV1 src spec.sourcePath spec.moduleName none with
  | .error e => throw <| IO.userError s!"{spec.caseId}: load: {e.render}"
  | .ok validated =>
    let srcHash ←
      match sourceHashV1 validated with
      | .ok d => digestHex d
      | .error e => throw <| IO.userError s!"{spec.caseId}: sourceHash: {e}"
    expect (srcHash == spec.expectedSourceHash)
      s!"{spec.caseId}: sourceHash pin mismatch (got {srcHash})"
    let carrier ←
      match normalizeProgramV1 validated with
      | .ok c => pure c
      | .error e => throw <| IO.userError s!"{spec.caseId}: normalize: {repr e}"
    let semHash ←
      match semanticHashV1 carrier with
      | .ok d => digestHex d
      | .error e => throw <| IO.userError s!"{spec.caseId}: semanticHash: {repr e}"
    expect (semHash == spec.expectedSemanticHash)
      s!"{spec.caseId}: semanticHash pin mismatch (got {semHash})"
    let data ←
      match validateSemanticProgramV1 carrier with
      | .ok d => pure d
      | .error e => throw <| IO.userError s!"{spec.caseId}: validate: {repr e}"
    let admitted ←
      match admitReferenceProgramSliceV1 carrier with
      | .ok a => pure a
      | .error e => throw <| IO.userError s!"{spec.caseId}: admit: {repr e}"
    let u64 ← findU64TypeId data
    pure (carrier, data, admitted, u64, srcHash, semHash)

private def stepOnce
    (admitted : AdmittedReferenceSliceV1) (pre : LogicalStateV1)
    (callable : CallableIdV1) (args : Array Nat) (u64 : TypeIdV1) :
    OutcomeV1 :=
  let refArgs := args.map (fun n => refU64 u64 n)
  stepReferenceSliceV1 admitted pre (inv callable refArgs) emptyResponses

private unsafe def runCounter
    (session : Language.Loader.ParserSession) (repoRoot outDir : System.FilePath) :
    IO Unit := do
  let caseId := "pf.primitive.counter.overflow-hold.v1"
  let spec : ProgramSpec := {
    caseId
    sourcePath := "Examples/Counter.lean"
    moduleName := "Examples.Counter"
    stateKey := "count"
    expectedSourceHash :=
      "276462ae16de0dd9d70e0e007a06669be9f2c996aa745e8b541b8a57f78208ae"
    expectedSemanticHash :=
      "111d486138fb36a21d6c8996b8fd100f5d4a5bb5a16e1f82009af97ce4985d6d"
  }
  let (carrier, data, admitted, u64, _, _) ← loadNormalizeAdmit session repoRoot spec
  let initId ← findCallableId data none
  let incId ← findCallableId data (some "increment")
  let getId ← findCallableId data (some "get")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"counter initial: {repr e}"
  -- step 0: deploy 7
  let o0 := stepOnce admitted initial initId #[7] u64
  let (st0, ret0, post0, eff0, rb0) ← outcomeShared o0 initial
  expect (st0 == "success") "counter step0 status"
  let v0 ← decodeSoleU64 post0
  expect (v0 == 7) "counter step0 state"
  writeSharedStep outDir caseId 0 st0 ret0 "count" v0 eff0 rb0
  -- step 1: increment 5 → 12
  let o1 := stepOnce admitted post0 incId #[5] u64
  let (st1, ret1, post1, eff1, rb1) ← outcomeShared o1 post0
  expect (st1 == "success") "counter step1 status"
  let v1 ← decodeSoleU64 post1
  expect (v1 == 12) "counter step1 state"
  writeSharedStep outDir caseId 1 st1 ret1 "count" v1 eff1 rb1
  -- step 2: view get
  let o2 := stepOnce admitted post1 getId #[] u64
  let (st2, ret2, post2, eff2, rb2) ← outcomeShared o2 post1
  expect (st2 == "success") "counter step2 status"
  let v2 ← decodeSoleU64 post2
  writeSharedStep outDir caseId 2 st2 ret2 "count" v2 eff2 rb2
  -- step 3: redeploy max (fresh initial)
  let maxN : Nat := (2 ^ 64) - 1
  let o3 := stepOnce admitted initial initId #[maxN] u64
  let (st3, ret3, post3, eff3, rb3) ← outcomeShared o3 initial
  expect (st3 == "success") "counter step3 status"
  let v3 ← decodeSoleU64 post3
  expect (v3 == maxN) "counter step3 state"
  writeSharedStep outDir caseId 3 st3 ret3 "count" v3 eff3 rb3
  -- step 4: overflow increment → revert
  let o4 := stepOnce admitted post3 incId #[1] u64
  let (st4, ret4, post4, eff4, rb4) ← outcomeShared o4 post3
  expect (st4 == "revert") "counter step4 status"
  let v4 ← decodeSoleU64 post4
  expect (v4 == maxN) "counter step4 rollback"
  writeSharedStep outDir caseId 4 st4 ret4 "count" v4 eff4 rb4
  -- step 5: view get still max
  let o5 := stepOnce admitted post4 getId #[] u64
  let (st5, ret5, post5, eff5, rb5) ← outcomeShared o5 post4
  expect (st5 == "success") "counter step5 status"
  let v5 ← decodeSoleU64 post5
  writeSharedStep outDir caseId 5 st5 ret5 "count" v5 eff5 rb5
  IO.println s!"reference-leg ok {caseId}"

private unsafe def runAccumulator
    (session : Language.Loader.ParserSession) (repoRoot outDir : System.FilePath) :
    IO Unit := do
  let caseId := "pf.primitive.accumulator.overflow-hold.v1"
  let spec : ProgramSpec := {
    caseId
    sourcePath := "Examples/Accumulator.lean"
    moduleName := "Examples.Accumulator"
    stateKey := "total"
    expectedSourceHash :=
      "85a384930ddea2e385226174f04f804d3cd2702bee28178b74de9c055c953280"
    expectedSemanticHash :=
      "c9c62dfe57d9f09f2b47f4dbb78d99c07edff7663036acc4df439e7311b7902a"
  }
  let (carrier, data, admitted, u64, _, _) ← loadNormalizeAdmit session repoRoot spec
  let initId ← findCallableId data none
  let addId ← findCallableId data (some "add")
  let curId ← findCallableId data (some "current")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"accumulator initial: {repr e}"
  let o0 := stepOnce admitted initial initId #[7] u64
  let (st0, ret0, post0, eff0, rb0) ← outcomeShared o0 initial
  let v0 ← decodeSoleU64 post0
  writeSharedStep outDir caseId 0 st0 ret0 "total" v0 eff0 rb0
  let o1 := stepOnce admitted post0 addId #[5] u64
  let (st1, ret1, post1, eff1, rb1) ← outcomeShared o1 post0
  let v1 ← decodeSoleU64 post1
  expect (v1 == 12) "accumulator step1"
  writeSharedStep outDir caseId 1 st1 ret1 "total" v1 eff1 rb1
  let o2 := stepOnce admitted post1 curId #[] u64
  let (st2, ret2, post2, eff2, rb2) ← outcomeShared o2 post1
  let v2 ← decodeSoleU64 post2
  writeSharedStep outDir caseId 2 st2 ret2 "total" v2 eff2 rb2
  let maxN : Nat := (2 ^ 64) - 1
  let o3 := stepOnce admitted initial initId #[maxN] u64
  let (st3, ret3, post3, eff3, rb3) ← outcomeShared o3 initial
  let v3 ← decodeSoleU64 post3
  writeSharedStep outDir caseId 3 st3 ret3 "total" v3 eff3 rb3
  let o4 := stepOnce admitted post3 addId #[1] u64
  let (st4, ret4, post4, eff4, rb4) ← outcomeShared o4 post3
  expect (st4 == "revert") "accumulator overflow"
  let v4 ← decodeSoleU64 post4
  writeSharedStep outDir caseId 4 st4 ret4 "total" v4 eff4 rb4
  let o5 := stepOnce admitted post4 curId #[] u64
  let (st5, ret5, post5, eff5, rb5) ← outcomeShared o5 post4
  let v5 ← decodeSoleU64 post5
  writeSharedStep outDir caseId 5 st5 ret5 "total" v5 eff5 rb5
  IO.println s!"reference-leg ok {caseId}"

private unsafe def runArithOps
    (session : Language.Loader.ParserSession) (repoRoot outDir : System.FilePath) :
    IO Unit := do
  let caseId := "pf.primitive.arithops.bitnot-scale.v1"
  let spec : ProgramSpec := {
    caseId
    sourcePath := "testdata/valid/ArithOps.lean"
    moduleName := "ArithOps"
    stateKey := "count"
    expectedSourceHash :=
      "cc56c3f25eb5668d862a969067cbde469cbf005dd1a6a8f27e7781499eb8103e"
    expectedSemanticHash :=
      "9a275ab1c9bc09a6571280ca41a52d4dfb8c9d31ba36af5b0562bf06f816b0cb"
  }
  let (carrier, data, admitted, u64, _, _) ← loadNormalizeAdmit session repoRoot spec
  let initId ← findCallableId data none
  let scaleId ← findCallableId data (some "scale")
  let bitsId ← findCallableId data (some "bits")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"arithops initial: {repr e}"
  let maxN : Nat := (2 ^ 64) - 1
  let o0 := stepOnce admitted initial initId #[7] u64
  let (st0, ret0, post0, eff0, rb0) ← outcomeShared o0 initial
  let v0 ← decodeSoleU64 post0
  writeSharedStep outDir caseId 0 st0 ret0 "count" v0 eff0 rb0
  -- bits(0) → max; does not write storage
  let o1 := stepOnce admitted post0 bitsId #[0] u64
  let (st1, ret1, post1, eff1, rb1) ← outcomeShared o1 post0
  expect (st1 == "success") "bits0"
  expect (ret1 == some (toString maxN)) "bits0 return"
  let v1 ← decodeSoleU64 post1
  expect (v1 == 7) "bits does not store"
  writeSharedStep outDir caseId 1 st1 ret1 "count" v1 eff1 rb1
  let o2 := stepOnce admitted post1 bitsId #[5] u64
  let (st2, ret2, post2, eff2, rb2) ← outcomeShared o2 post1
  expect (ret2 == some (toString (maxN - 5))) "bits5 return"
  let v2 ← decodeSoleU64 post2
  writeSharedStep outDir caseId 2 st2 ret2 "count" v2 eff2 rb2
  -- scale(3,2): count := 7*3/2 + 7%2 = 10 + 1 = 11
  let o3 := stepOnce admitted post2 scaleId #[3, 2] u64
  let (st3, ret3, post3, eff3, rb3) ← outcomeShared o3 post2
  let v3 ← decodeSoleU64 post3
  expect (v3 == 11) "scale state"
  writeSharedStep outDir caseId 3 st3 ret3 "count" v3 eff3 rb3
  let o4 := stepOnce admitted initial initId #[maxN] u64
  let (st4, ret4, post4, eff4, rb4) ← outcomeShared o4 initial
  let v4 ← decodeSoleU64 post4
  writeSharedStep outDir caseId 4 st4 ret4 "count" v4 eff4 rb4
  let o5 := stepOnce admitted post4 scaleId #[2, 1] u64
  let (st5, ret5, post5, eff5, rb5) ← outcomeShared o5 post4
  expect (st5 == "revert") "scale overflow"
  let v5 ← decodeSoleU64 post5
  writeSharedStep outDir caseId 5 st5 ret5 "count" v5 eff5 rb5
  IO.println s!"reference-leg ok {caseId}"

private unsafe def runEventFlow
    (session : Language.Loader.ParserSession) (repoRoot outDir : System.FilePath) :
    IO Unit := do
  let caseId := "pf.primitive.eventflow.emit-cap.v1"
  let spec : ProgramSpec := {
    caseId
    sourcePath := "testdata/evm-corpus/v1/programs/EventFlow.lean"
    moduleName := "EventFlow"
    stateKey := "count"
    expectedSourceHash :=
      "ee6d74460f772b8b309517e9d5c6d27f43dc3eaa869a598f945ba67e25d7d723"
    expectedSemanticHash :=
      "3332b207ff7c04c815f8ad6e17c30b21680ce1bb18c88df46d753f3c049232d6"
  }
  let (carrier, data, admitted, u64, _, _) ← loadNormalizeAdmit session repoRoot spec
  let initId ← findCallableId data none
  let bumpId ← findCallableId data (some "bump")
  let getId ← findCallableId data (some "get")
  let initial ←
    match initialLogicalStateV1 carrier with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"eventflow initial: {repr e}"
  let o0 := stepOnce admitted initial initId #[0] u64
  let (st0, ret0, post0, eff0, rb0) ← outcomeShared o0 initial
  let v0 ← decodeSoleU64 post0
  expect (v0 == 0) "eventflow deploy0"
  writeSharedStep outDir caseId 0 st0 ret0 "count" v0 eff0 rb0
  -- bump(5): emit Moved(0,5), count := 5
  let o1 := stepOnce admitted post0 bumpId #[5] u64
  let (st1, ret1, post1, eff1, rb1) ← outcomeShared o1 post0
  expect (st1 == "success") "eventflow bump success"
  let v1 ← decodeSoleU64 post1
  expect (v1 == 5) "eventflow count after bump"
  expect (eff1 != effectsEmpty) "eventflow must carry Moved effect"
  writeSharedStep outDir caseId 1 st1 ret1 "count" v1 eff1 rb1
  let o2 := stepOnce admitted post1 getId #[] u64
  let (st2, ret2, post2, eff2, rb2) ← outcomeShared o2 post1
  let v2 ← decodeSoleU64 post2
  writeSharedStep outDir caseId 2 st2 ret2 "count" v2 eff2 rb2
  -- bump(3) with count=5 → Cap revert; effects empty; state holds 5
  let o3 := stepOnce admitted post2 bumpId #[3] u64
  let (st3, ret3, post3, eff3, rb3) ← outcomeShared o3 post2
  expect (st3 == "revert") "eventflow Cap"
  expect (eff3 == effectsEmpty) "eventflow revert discards emit"
  let v3 ← decodeSoleU64 post3
  expect (v3 == 5) "eventflow Cap holds state"
  writeSharedStep outDir caseId 3 st3 ret3 "count" v3 eff3 rb3
  let o4 := stepOnce admitted post3 getId #[] u64
  let (st4, ret4, post4, eff4, rb4) ← outcomeShared o4 post3
  let v4 ← decodeSoleU64 post4
  writeSharedStep outDir caseId 4 st4 ret4 "count" v4 eff4 rb4
  IO.println s!"reference-leg ok {caseId}"

/-- Adapter Token pin recheck only (no Reference observations for Map adapter).
    Loader → Normalize → sourceHash/semanticHash; does not admit/step Reference. -/
private unsafe def runTokenPinCheck
    (session : Language.Loader.ParserSession) (repoRoot : System.FilePath) : IO Unit := do
  let caseId := "pf.adapter.token.conservation.v1"
  let sourcePath := "Examples/Token.lean"
  let moduleName := "Examples.Token"
  let expectedSourceHash :=
    "3b60c7a05865886dc4eae7ce1898577c4dc718f10080c36ac8a9c9dcb04eca23"
  let expectedSemanticHash :=
    "667f76924ca4554e18cfcd1aa51d26cf8cb584ea1abbc50ff7720e1ada6bc17a"
  let absPath := repoRoot / sourcePath
  let src ← IO.FS.readFile absPath
  match ← session.selectProgramV1 src sourcePath moduleName none with
  | .error e => throw <| IO.userError s!"{caseId}: load: {e.render}"
  | .ok validated =>
    let srcHash ←
      match sourceHashV1 validated with
      | .ok d => digestHex d
      | .error e => throw <| IO.userError s!"{caseId}: sourceHash: {e}"
    expect (srcHash == expectedSourceHash)
      s!"{caseId}: sourceHash pin mismatch (got {srcHash})"
    let carrier ←
      match normalizeProgramV1 validated with
      | .ok c => pure c
      | .error e => throw <| IO.userError s!"{caseId}: normalize: {repr e}"
    let semHash ←
      match semanticHashV1 carrier with
      | .ok d => digestHex d
      | .error e => throw <| IO.userError s!"{caseId}: semanticHash: {repr e}"
    expect (semHash == expectedSemanticHash)
      s!"{caseId}: semanticHash pin mismatch (got {semHash})"
    IO.println s!"token-pin-ok {caseId} sourceHash={srcHash} semanticHash={semHash}"

/-- Entry:
  `lake env lean --run Tests/Materialization/EvmCorpusPrimitiveV1.lean -- <repo-root> <out-dir>`
-/
unsafe def runAll (args : List String) : IO UInt32 := do
  -- `lean --run file.lean -- a b` may leave a leading "--" in args.
  let args :=
    match args with
    | "--" :: rest => rest
    | other => other
  let (repoRoot, outDir) :=
    match args with
    | root :: out :: _ => (System.FilePath.mk root, System.FilePath.mk out)
    | root :: [] => (System.FilePath.mk root, System.FilePath.mk "build/v2/evm-corpus-obs")
    | [] => (System.FilePath.mk ".", System.FilePath.mk "build/v2/evm-corpus-obs")
  IO.FS.createDirAll outDir
  let session ← Language.Loader.ParserSession.create
  runCounter session repoRoot outDir
  runAccumulator session repoRoot outDir
  runArithOps session repoRoot outDir
  runEventFlow session repoRoot outDir
  runTokenPinCheck session repoRoot
  IO.println s!"EvmCorpusPrimitiveV1: reference legs written under {outDir}"
  pure 0

end Tests.Materialization.EvmCorpusPrimitiveV1

/-- Top-level `main` required by `lean --run` (outside namespace). -/
unsafe def main (args : List String) : IO UInt32 :=
  Tests.Materialization.EvmCorpusPrimitiveV1.runAll args
