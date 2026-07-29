/-
  Tests.Core.DiagnosticBundleV1 — B8a inert DiagnosticBundleV1 / DiagnosticResultV1 foundation.

  Covers:
    - valid multi-error normalize/sort/dedupe/100-cap via sole mkFailureBundleV1
    - nonempty + ≥1 real severity=error ≠ PF-DIAG-LIMIT
    - ≤1 PF-DIAG-LIMIT only in final position
    - every retained diagnostic encodes canonically
    - idempotent constructor
    - fail-closed fixed PF-INTERNAL for empty / limit-only / warning-note-only /
      structurally invalid / non-encodable / mixed valid+invalid (no input detail leak)
    - read-only diagnostics projection
    - deterministic human + PF-JCS array rendering
    - exit priority 70 > 7 > 6 > 5 > 4 > 3; PF-DIAG-LIMIT and non-error neutral
    - DiagnosticResultV1 ok/error without touching alpha CompileResult
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.DiagnosticBundleV1

namespace Tests.Core.DiagnosticBundleV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Core.DiagnosticBundleV1

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def mkAt (code : DiagnosticCodeV1) (i : Nat) (msg : String := "m") :
    DiagnosticV1 :=
  DiagnosticV1.make code s!"{msg}-{i}" (stableContext := some s!"ctx-{i}")

private def mkError (code : DiagnosticCodeV1) (msg : String)
    (stable? : Option String := none) : DiagnosticV1 :=
  DiagnosticV1.make code msg (stableContext := stable?)

private def mkWithSeverity (code : DiagnosticCodeV1) (msg : String)
    (sev : DiagnosticSeverityV1) : DiagnosticV1 :=
  DiagnosticV1.make code msg (severity := some sev)

private def expectBundleDiags (label : String) (bundle : DiagnosticBundleV1)
    (wantSize : Nat) : IO (Array DiagnosticV1) := do
  let diags := DiagnosticBundleV1.diagnostics bundle
  unless diags.size == wantSize do
    throw <| IO.userError s!"{label}: expected size {wantSize}, got {diags.size}"
  pure diags

private def testValidMultiErrorNormalize : IO Unit := do
  -- Unsorted / duplicate order keys; messages differ but order key collides on first two.
  let d0 := mkError .sourceInvalid "first-a" (some "k0")
  let d0dup := mkError .sourceInvalid "first-b" (some "k0")  -- same order key → dedupe
  let d1 := mkError .type001 "type" (some "k1")
  let d2 := mkError .effectDisallowed "effect" (some "k2")
  -- Reverse input order vs message-independent sort.
  let raw := #[d2, d0dup, d1, d0]
  let bundle := mkFailureBundleV1 raw
  let diags ← expectBundleDiags "multi" bundle 3
  -- Sorted by order key: sourceInvalid/k0, type001/k1, effectDisallowed/k2
  -- (path empty, start 0; code wire order: PF-EFFECT-001 < PF-SRC-INVALID < PF-TYPE-001
  --  wait — order is path, start, code.wire, stableContext)
  -- wires: PF-EFFECT-001, PF-SRC-INVALID, PF-TYPE-001 → lexical:
  --   PF-EFFECT-001 < PF-SRC-INVALID < PF-TYPE-001
  unless diags[0]!.code == .effectDisallowed do
    throw <| IO.userError s!"multi[0] code: got {diags[0]!.code.wire}"
  unless diags[1]!.code == .sourceInvalid do
    throw <| IO.userError s!"multi[1] code: got {diags[1]!.code.wire}"
  unless diags[2]!.code == .type001 do
    throw <| IO.userError s!"multi[2] code: got {diags[2]!.code.wire}"
  -- Dedupe keeps total-order minimum (message last): "first-a" < "first-b".
  unless diags[1]!.message == "first-a" do
    throw <| IO.userError
      s!"dedupe must keep total-order min message first-a, got {repr diags[1]!.message}"
  unless diags[1]!.message != "first-b" do
    throw <| IO.userError "dedupe must not keep non-minimum first-b"
  -- Exactly one survivor for k0.
  let srcCount := diags.filter (fun d => d.code == .sourceInvalid) |>.size
  unless srcCount == 1 do
    throw <| IO.userError s!"expected 1 sourceInvalid after dedupe, got {srcCount}"

private def testHundredCapNoLimit : IO Unit := do
  let hundred := (List.range 100).toArray.map (fun i => mkAt .sourceInvalid i)
  let bundle := mkFailureBundleV1 hundred
  let diags ← expectBundleDiags "100-cap" bundle 100
  unless diags.all (fun d => d.code != .diagLimit) do
    throw <| IO.userError "100-cap must not append PF-DIAG-LIMIT"
  unless diags.any (fun d => d.severity == .error && d.code != .diagLimit) do
    throw <| IO.userError "100-cap must retain a real error"

private def testHundredOneCapWithLimit : IO Unit := do
  let raw := (List.range 101).toArray.map (fun i => mkAt .sourceInvalid i)
  let bundle := mkFailureBundleV1 raw
  let diags ← expectBundleDiags "101-cap" bundle 101
  unless diags[100]!.code == .diagLimit do
    throw <| IO.userError "101-cap last must be PF-DIAG-LIMIT"
  let limits := diags.filter (fun d => d.code == .diagLimit) |>.size
  unless limits == 1 do
    throw <| IO.userError s!"expected exactly one PF-DIAG-LIMIT, got {limits}"
  -- Real errors occupy the first 100 slots.
  unless (diags.extract 0 100).all (fun d => d.code != .diagLimit) do
    throw <| IO.userError "PF-DIAG-LIMIT must not appear before final position"
  unless diags.any (fun d => d.severity == .error && d.code != .diagLimit) do
    throw <| IO.userError "truncated bundle must still have a real error"

private def testCanonicalEncodeAllRetained : IO Unit := do
  let raw := #[
    mkError .sourceInvalid "a" (some "a"),
    mkError .type001 "b" (some "b"),
    mkError .planInvariant "c" (some "c")
  ]
  let bundle := mkFailureBundleV1 raw
  for d in DiagnosticBundleV1.diagnostics bundle do
    match d.toCanonicalJson with
    | .error e => throw <| IO.userError s!"retained diagnostic not encodable: {e}"
    | .ok _ => pure ()

private def testIdempotentConstructor : IO Unit := do
  let raw := #[
    mkError .type001 "t" (some "t"),
    mkError .sourceInvalid "s" (some "s"),
    mkError .sourceInvalid "s-dup" (some "s")  -- dedupe
  ]
  let b1 := mkFailureBundleV1 raw
  let b2 := mkFailureBundleV1 (DiagnosticBundleV1.diagnostics b1)
  unless DiagnosticBundleV1.diagnostics b1 == DiagnosticBundleV1.diagnostics b2 do
    throw <| IO.userError "mkFailureBundleV1 is not idempotent on its own diagnostics"
  -- Truncated + limit also idempotent.
  let big := (List.range 150).toArray.map (fun i => mkAt .effectDisallowed i)
  let t1 := mkFailureBundleV1 big
  let t2 := mkFailureBundleV1 (DiagnosticBundleV1.diagnostics t1)
  unless DiagnosticBundleV1.diagnostics t1 == DiagnosticBundleV1.diagnostics t2 do
    throw <| IO.userError "truncated-bundle constructor is not idempotent"

private def fixedInternalMessage : String :=
  "diagnostic bundle invariant failed"

private def assertFixedInternal (label : String) (bundle : DiagnosticBundleV1)
    (forbidden : Array String) : IO Unit := do
  let diags ← expectBundleDiags label bundle 1
  let d := diags[0]!
  unless d.code == .internal do
    throw <| IO.userError s!"{label}: expected PF-INTERNAL, got {d.code.wire}"
  unless d.severity == .error do
    throw <| IO.userError s!"{label}: PF-INTERNAL severity must be error"
  unless d.message == fixedInternalMessage do
    throw <| IO.userError
      s!"{label}: PF-INTERNAL message mismatch: {repr d.message}"
  -- Must not leak any rejected-input detail.
  for leak in forbidden do
    if containsSubstr d.message leak then
      throw <| IO.userError s!"{label}: PF-INTERNAL message leaks {repr leak}"
    match d.toCanonicalJson with
    | .error e => throw <| IO.userError s!"{label}: PF-INTERNAL not encodable: {e}"
    | .ok json =>
      if containsSubstr json leak then
        throw <| IO.userError s!"{label}: PF-INTERNAL JSON leaks {repr leak}"
  -- Canonical encode required.
  match d.toCanonicalJson with
  | .error e => throw <| IO.userError s!"{label}: encode failed: {e}"
  | .ok _ => pure ()

private def testFailClosedEmpty : IO Unit := do
  let bundle := mkFailureBundleV1 #[]
  assertFixedInternal "empty" bundle #[]

private def testFailClosedLimitOnly : IO Unit := do
  let limit := DiagnosticV1.make .diagLimit
    "diagnostic limit exceeded; remaining diagnostics truncated"
  let secret := "SECRET-LIMIT-ONLY-PAYLOAD"
  let limit2 := DiagnosticV1.make .diagLimit secret
  let bundle := mkFailureBundleV1 #[limit, limit2]
  assertFixedInternal "limit-only" bundle #[secret]

private def testFailClosedWarningNoteOnly : IO Unit := do
  let secret := "SECRET-WARN-NOTE"
  let w := mkWithSeverity .sourceInvalid secret .warning
  let n := mkWithSeverity .type001 "note-only" .note
  let bundle := mkFailureBundleV1 #[w, n]
  assertFixedInternal "warning-note-only" bundle #[secret]

private def testFailClosedStructurallyInvalid : IO Unit := do
  -- Bad origin: startByte > endByte fails DiagnosticOriginV1.validate / encode.
  let badPath : ProjectRelativePath := { value := "Bad.lean" }
  let badOrigin : DiagnosticOriginV1 := {
    sourcePath := badPath
    startByte := 10
    endByte := 5
    nodeId := none
  }
  let secret := "SECRET-BAD-RANGE"
  let bad := DiagnosticV1.make .sourceInvalid secret (primary := some badOrigin)
  let bundle := mkFailureBundleV1 #[bad]
  assertFixedInternal "struct-invalid" bundle #[secret, "Bad.lean"]

private def testFailClosedNonEncodable : IO Unit := do
  -- Absolute / non project-relative path fails path validation on encode.
  let absPath : ProjectRelativePath := { value := "/tmp/SECRET-ABS-PATH.lean" }
  let origin : DiagnosticOriginV1 := {
    sourcePath := absPath
    startByte := 0
    endByte := 1
    nodeId := none
  }
  let secret := "SECRET-ABS-MSG"
  let bad := DiagnosticV1.make .type001 secret (primary := some origin)
  let bundle := mkFailureBundleV1 #[bad]
  assertFixedInternal "non-encodable" bundle #[secret, "SECRET-ABS-PATH", "/tmp"]

private def testFailClosedMixedValidAndInvalid : IO Unit := do
  -- One encodable real error plus one invalid/non-encodable → whole bundle fails
  -- closed to fixed PF-INTERNAL (does not retain the valid error or leak either).
  let validSecret := "SECRET-VALID-REAL-ERROR"
  let valid := mkError .sourceInvalid validSecret (some "valid-k")
  let badPath : ProjectRelativePath := { value := "MixedBad.lean" }
  let badOrigin : DiagnosticOriginV1 := {
    sourcePath := badPath
    startByte := 10
    endByte := 5
    nodeId := none
  }
  let invalidSecret := "SECRET-MIXED-INVALID"
  let invalid := DiagnosticV1.make .type001 invalidSecret (primary := some badOrigin)
  let bundle := mkFailureBundleV1 #[valid, invalid]
  assertFixedInternal "mixed-valid-invalid" bundle
    #[validSecret, invalidSecret, "MixedBad.lean"]
  unless DiagnosticBundleV1.selectExitCode bundle == 70 do
    throw <| IO.userError "mixed-valid-invalid fail-closed must exit 70"
  -- Also mix with non-encodable absolute path (same allEncodable fail-closed path).
  let absPath : ProjectRelativePath := { value := "/tmp/SECRET-MIXED-ABS.lean" }
  let absOrigin : DiagnosticOriginV1 := {
    sourcePath := absPath
    startByte := 0
    endByte := 1
    nodeId := none
  }
  let absSecret := "SECRET-MIXED-ABS-MSG"
  let absBad := DiagnosticV1.make .effectDisallowed absSecret (primary := some absOrigin)
  let valid2 := mkError .planInvariant "SECRET-VALID2" (some "v2")
  let bundle2 := mkFailureBundleV1 #[valid2, absBad]
  assertFixedInternal "mixed-valid-abs" bundle2
    #["SECRET-VALID2", absSecret, "SECRET-MIXED-ABS", "/tmp"]
  unless DiagnosticBundleV1.selectExitCode bundle2 == 70 do
    throw <| IO.userError "mixed-valid-abs fail-closed must exit 70"

private def testReadOnlyDiagnostics : IO Unit := do
  let raw := #[mkError .sourceInvalid "x" (some "x")]
  let bundle := mkFailureBundleV1 raw
  let a := DiagnosticBundleV1.diagnostics bundle
  let b := DiagnosticBundleV1.diagnostics bundle
  unless a == b do
    throw <| IO.userError "diagnostics projection must be deterministic"
  unless a.size == 1 do
    throw <| IO.userError "read-only projection size mismatch"

private def testHumanAndJsonRender : IO Unit := do
  let dA := mkError .sourceInvalid "alpha" (some "a")
  let dB := mkError .type001 "beta" (some "b")
  -- Input reversed; render must follow normalized order.
  let bundle := mkFailureBundleV1 #[dB, dA]
  let diags := DiagnosticBundleV1.diagnostics bundle
  let human := DiagnosticBundleV1.renderHuman bundle
  let expectedHuman := String.intercalate "\n" (diags.toList.map DiagnosticV1.renderHuman)
  unless human == expectedHuman do
    throw <| IO.userError s!"human render mismatch:\n{human}\nvs\n{expectedHuman}"
  -- Each line is CODE: message.
  unless containsSubstr human "PF-SRC-INVALID: alpha" do
    throw <| IO.userError "human missing source line"
  unless containsSubstr human "PF-TYPE-001: beta" do
    throw <| IO.userError "human missing type line"
  match DiagnosticBundleV1.renderCanonicalJsonArray bundle with
  | .error e => throw <| IO.userError s!"json array render failed: {e}"
  | .ok json =>
    unless json.startsWith "[" && json.endsWith "]" do
      throw <| IO.userError s!"json array must be [...] got {json.take 32}"
    -- Deterministic: second render equals first.
    match DiagnosticBundleV1.renderCanonicalJsonArray bundle with
    | .error e => throw <| IO.userError e
    | .ok json2 =>
      unless json == json2 do
        throw <| IO.userError "json array render is not deterministic"
    -- Contains both wires in normalized order (code.wire lexical at equal path/start).
    unless containsSubstr json "PF-SRC-INVALID" do
      throw <| IO.userError "json missing PF-SRC-INVALID"
    unless containsSubstr json "PF-TYPE-001" do
      throw <| IO.userError "json missing PF-TYPE-001"
    let findSub (haystack needle : String) : Option Nat :=
      let n := needle.toList
      let rec loop (cs : List Char) (i : Nat) : Option Nat :=
        match cs with
        | [] => none
        | _ :: rest =>
          if n.isPrefixOf cs then some i else loop rest (i + 1)
      loop haystack.toList 0
    match findSub json "PF-SRC-INVALID", findSub json "PF-TYPE-001" with
    | some s, some t =>
      unless s < t do
        throw <| IO.userError "json array order must follow normalized diagnostics"
    | _, _ => throw <| IO.userError "json missing expected wires"


private def testExitPriority : IO Unit := do
  -- Single families.
  let internalB := mkFailureBundleV1 #[mkError .internal "bug"]
  unless DiagnosticBundleV1.selectExitCode internalB == 70 do
    throw <| IO.userError "internal must exit 70"
  let deployB := mkFailureBundleV1
    #[DiagnosticV1.make .artifactInvalid "d" (phase := some .deploy)]
  unless DiagnosticBundleV1.selectExitCode deployB == 7 do
    throw <| IO.userError "deploy phase must exit 7"
  let verifyB := mkFailureBundleV1
    #[DiagnosticV1.make .settlementUnavailable "v" (phase := some .verify)]
  unless DiagnosticBundleV1.selectExitCode verifyB == 7 do
    throw <| IO.userError "verify phase must exit 7"
  let emitB := mkFailureBundleV1 #[mkError .outputAtomicity "e"]
  unless DiagnosticBundleV1.selectExitCode emitB == 6 do
    throw <| IO.userError "emit phase must exit 6"
  let toolB := mkFailureBundleV1 #[mkError .toolchainMissing "t"]
  unless DiagnosticBundleV1.selectExitCode toolB == 6 do
    throw <| IO.userError "tool phase must exit 6"
  let planB := mkFailureBundleV1 #[mkError .planInvariant "p"]
  unless DiagnosticBundleV1.selectExitCode planB == 5 do
    throw <| IO.userError "plan phase must exit 5"
  let lowerB := mkFailureBundleV1 #[mkError .lowerInvariant "l"]
  unless DiagnosticBundleV1.selectExitCode lowerB == 5 do
    throw <| IO.userError "lower phase must exit 5"
  let resolveB := mkFailureBundleV1 #[mkError .targetUnknown "r"]
  unless DiagnosticBundleV1.selectExitCode resolveB == 4 do
    throw <| IO.userError "resolve phase must exit 4"
  let sourceB := mkFailureBundleV1 #[mkError .sourceInvalid "s"]
  unless DiagnosticBundleV1.selectExitCode sourceB == 3 do
    throw <| IO.userError "source phase must exit 3"
  let typeB := mkFailureBundleV1 #[mkError .type001 "ty"]
  unless DiagnosticBundleV1.selectExitCode typeB == 3 do
    throw <| IO.userError "type phase must exit 3"
  let effectB := mkFailureBundleV1 #[mkError .effectDisallowed "ef"]
  unless DiagnosticBundleV1.selectExitCode effectB == 3 do
    throw <| IO.userError "effect phase must exit 3"
  let semB := mkFailureBundleV1 #[mkError .semanticsMismatch "sm"]
  unless DiagnosticBundleV1.selectExitCode semB == 3 do
    throw <| IO.userError "semantic phase must exit 3"

  -- Highest priority wins: mix source(3) + plan(5) + tool(6) + deploy(7) + internal(70).
  let mixed := mkFailureBundleV1 #[
    mkError .sourceInvalid "s" (some "s"),
    mkError .planInvariant "p" (some "p"),
    mkError .toolchainMissing "t" (some "t"),
    DiagnosticV1.make .artifactInvalid "d"
      (phase := some .deploy) (stableContext := some "d"),
    mkError .internal "bug" (some "i")
  ]
  unless DiagnosticBundleV1.selectExitCode mixed == 70 do
    throw <| IO.userError "mixed with internal must exit 70"
  let withoutInternal := mkFailureBundleV1 #[
    mkError .sourceInvalid "s" (some "s"),
    mkError .planInvariant "p" (some "p"),
    mkError .toolchainMissing "t" (some "t"),
    DiagnosticV1.make .artifactInvalid "d"
      (phase := some .deploy) (stableContext := some "d")
  ]
  unless DiagnosticBundleV1.selectExitCode withoutInternal == 7 do
    throw <| IO.userError "mixed without internal must exit 7 (deploy)"
  let mid := mkFailureBundleV1 #[
    mkError .sourceInvalid "s" (some "s"),
    mkError .planInvariant "p" (some "p"),
    mkError .toolchainMissing "t" (some "t")
  ]
  unless DiagnosticBundleV1.selectExitCode mid == 6 do
    throw <| IO.userError "source+plan+tool must exit 6"

  -- PF-DIAG-LIMIT is neutral: truncated bundle exit comes from real errors only.
  let truncated := mkFailureBundleV1
    ((List.range 101).toArray.map (fun i => mkAt .sourceInvalid i))
  unless DiagnosticBundleV1.selectExitCode truncated == 3 do
    throw <| IO.userError "truncated source-only must exit 3 (limit neutral)"
  -- Non-error diagnostics are neutral when a real error coexists.
  let withWarn := mkFailureBundleV1 #[
    mkWithSeverity .toolchainMissing "warn-tool" .warning,
    mkError .sourceInvalid "real" (some "r")
  ]
  unless DiagnosticBundleV1.selectExitCode withWarn == 3 do
    throw <| IO.userError "warning tool must not raise exit above source error"
  -- Fixed internal fallback exits 70.
  let emptyB := mkFailureBundleV1 #[]
  unless DiagnosticBundleV1.selectExitCode emptyB == 70 do
    throw <| IO.userError "fail-closed internal fallback must exit 70"

private def testDiagnosticResultV1 : IO Unit := do
  let okR : DiagnosticResultV1 Nat := DiagnosticResultV1.ok 42
  match okR with
  | DiagnosticResultV1.ok n =>
    unless n == 42 do throw <| IO.userError "ok value mismatch"
  | DiagnosticResultV1.error _ =>
    throw <| IO.userError "ok branch unexpected error"
  let bundle := mkFailureBundleV1 #[mkError .sourceInvalid "x"]
  let errR : DiagnosticResultV1 Nat := DiagnosticResultV1.error bundle
  match errR with
  | DiagnosticResultV1.ok _ =>
    throw <| IO.userError "error branch unexpected ok"
  | DiagnosticResultV1.error b =>
    unless (DiagnosticBundleV1.diagnostics b).size == 1 do
      throw <| IO.userError "error bundle size mismatch"
  -- CompileResult / CompileError remain untouched (type-level coexistence).
  let _cr : CompileResult Nat := Except.ok 1
  let _ce : CompileError := .invalidProgram "x"
  pure ()

def run : IO Unit := do
  testValidMultiErrorNormalize
  testHundredCapNoLimit
  testHundredOneCapWithLimit
  testCanonicalEncodeAllRetained
  testIdempotentConstructor
  testFailClosedEmpty
  testFailClosedLimitOnly
  testFailClosedWarningNoteOnly
  testFailClosedStructurallyInvalid
  testFailClosedNonEncodable
  testFailClosedMixedValidAndInvalid
  testReadOnlyDiagnostics
  testHumanAndJsonRender
  testExitPriority
  testDiagnosticResultV1
  IO.println "Tests.Core.DiagnosticBundleV1: ok"

end Tests.Core.DiagnosticBundleV1
