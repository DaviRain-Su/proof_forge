/-
  Tests.Semantic.NormalizeConst — const declaration + body reference slice
  (N-CONST + N-CONST-REF).

  Positive pins:
    * const UInt64 / Int64 (pos and neg) / Bool / String evaluate at compile
      time into `constants` with canonical `valueBytes` (byte-identical to
      `Op.Literal` encoding).
    * Body bare const places lower to value-producing `Op.Constant ConstantId`
      with `result.typeId == ConstantV1.typeId` (return, binary, comparison).
    * Expected-type synthesis: `1 + NARROW` / comparison with const place on
      either side keep exact UInt32 (not default UInt64) when TypeCheck accepts.
    * For endpoints: endExclusive const UInt32 width when start is place/let.
    * Forward reference: const declared after the reading callable still works
      (constants table complete after fn signatures, before body lowering).
    * Reads from entry / view / pureFn / invariant.
    * Param and let shadowing do not emit Op.Constant.
    * Independent Op.Constant per read; canonical ValueId order.
    * Provenance: `.constant id` → ConstDecl; `.typeRef` → exact ConstDecl.type
      origin via inventory; Bool const `value.bool` requirement origin on
      ConstDecl.type; body instruction/value → place path; authority join exact.

  Pass order note: fn signature types intern before const types (2a then 2b);
  post-declared novel const shapes may still cut over body-only type order
  (N-CONST-REF engineering identity, not full hash stability).

  Negative pins: non-literal const (place read, binary op) fail closed; a
  UInt-typed negative literal is rejected by CheckV1 (typedNotOk) before
  Normalize. Const type/value grammar authority remains TypeCheck +
  evalConstDeclValueV1 (no second Normalize allowlist).
-/
import ProofForgeV2
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ProvenanceV1
import ProofForgeV2.Semantic.RequirementIdsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import Lean.Parser

namespace Tests.Semantic.NormalizeConst

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProvenanceV1
open ProofForgeV2.Semantic.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def moduleName : String := "Tests.NormalizeConst"

private def testSourcePath (label : String) : String :=
  "tests/normalize-const-" ++ label ++ ".pf"

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

private unsafe def loadSourceWithSpans
    (session : Language.Loader.ParserSession) (label source : String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans source (testSourcePath label) moduleName none with
  | .ok pair => pure pair
  | .error error => throw <| IO.userError s!"{label}: load+spans failed: {error.render}"

private def parseTestPath (label : String) : IO ProjectRelativePath := do
  match parseProjectRelativePath (testSourcePath label) with
  | .ok p => pure p
  | .error e => throw <| IO.userError s!"{label}: path: {e}"

private def expect (ok : Bool) (msg : String) : IO Unit :=
  unless ok do throw <| IO.userError msg

private def expectOk {α} (label : String) (result : Except NormalizeErrorV1 α) : IO α := do
  match result with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: expected ok, got {repr e}"

private def findOrigin
    (provenance : SemanticProvenanceV1) (entity : SemanticEntityRefV1) :
    Option SourceOrigin :=
  provenance.originMap.findSome? fun b =>
    if b.entity == entity then b.origins[0]? else none

private def findOrigins
    (provenance : SemanticProvenanceV1) (entity : SemanticEntityRefV1) :
    Array SourceOrigin :=
  match provenance.originMap.findSome? fun b =>
    if b.entity == entity then some b.origins else none with
  | some os => os
  | none => #[]

private def childPathT (parent : NormalizedSyntacticPathV1) (tag field : String)
    (index : Nat) : NormalizedSyntacticPathV1 :=
  parent.push {
    parentTag := tag
    fieldTag := field
    index := UInt32.ofNat index
  }

private def directChildT (parent : NormalizedSyntacticPathV1) (tag field : String) :
    NormalizedSyntacticPathV1 :=
  childPathT parent tag field 0

/-- Independent origin at an explicit syntactic path via assignNodeIdsV1 + inventory. -/
private def originAtExplicitPath
    (source : ValidatedSourceV1)
    (inventory : SourceNodeInventoryV1)
    (path : NormalizedSyntacticPathV1) :
    IO SourceOrigin := do
  let table ← match assignNodeIdsV1
      source.moduleName source.programIdentity source.program with
    | .ok t => pure t
    | .error e => throw <| IO.userError s!"assignNodeIdsV1: {e}"
  let assignments := nodeAssignmentsPreorderV1 table
  let mut nodeId? : Option NodeId := none
  for a in assignments do
    if a.path == path then
      nodeId? := some a.nodeId
  let some nid := nodeId? |
    throw <| IO.userError s!"no NodeId for path key={pathLookupKeyV1 path}"
  let mut origin? : Option SourceOrigin := none
  for o in inventory.nodes do
    if o.nodeId == nid then
      origin? := some o
  let some origin := origin? |
    throw <| IO.userError "NodeId not present in inventory"
  pure origin

private def isUInt32 (t : TypeDeclV1) : Bool :=
  t.name.isNone && (match t.shape with | .uint 32 => true | _ => false)

private unsafe def constRowsOf
    (session : Language.Loader.ParserSession) (label name body : String) :
    IO (Array ConstantV1) := do
  let validated ← loadSource session label (wrap name body)
  let carrier ← expectOk label (normalizeProgramV1 validated)
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"{label}: validate failed: {repr e}"
  pure data.constants

private unsafe def constTypesOf
    (session : Language.Loader.ParserSession) (label name body : String) :
    IO (Array TypeDeclV1) := do
  let validated ← loadSource session label (wrap name body)
  let carrier ← expectOk label (normalizeProgramV1 validated)
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d | .error e => throw <| IO.userError s!"{label}: {repr e}"
  pure data.types

private unsafe def dataOf
    (session : Language.Loader.ParserSession) (label name body : String) :
    IO (SemanticProgramV1 × SemanticProgramDataV1) := do
  let validated ← loadSource session label (wrap name body)
  let carrier ← expectOk label (normalizeProgramV1 validated)
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"{label}: validate failed: {repr e}"
  pure (carrier, data)

private unsafe def expectNormalizeFails
    (session : Language.Loader.ParserSession) (label name body hint : String) :
    IO Unit := do
  let validated ← loadSource session label (wrap name body)
  match normalizeProgramV1 validated with
  | .ok _ => throw <| IO.userError s!"{label}: expected normalize failure, got ok"
  | .error (.unsupported detail) =>
      expect (detail.contains hint)
        s!"{label}: unsupported detail should mention '{hint}', got: {detail}"
  | .error (.typedNotOk diags) =>
      expect (diags.size > 0)
        s!"{label}: typedNotOk with no diagnostics"
  | .error e =>
      throw <| IO.userError s!"{label}: expected .unsupported/.typedNotOk, got {repr e}"

private def leBytesFromNat (n : Nat) (len : Nat) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity len
  let mut v := n
  for _ in [:len] do
    out := out.push (UInt8.ofNat (v % 256))
    v := v / 256
  pure out

/-- two's-complement LE of a signed Int at `width` bits. -/
private def intLeBytes (value : Int) (width : Nat) : ByteArray :=
  let bits : Nat :=
    if value < 0 then (value + Int.ofNat (Nat.pow 2 width)).toNat else value.toNat
  leBytesFromNat bits (width / 8)

private def isUInt64 (t : TypeDeclV1) : Bool :=
  t.name.isNone && (match t.shape with | .uint 64 => true | _ => false)
private def isInt64 (t : TypeDeclV1) : Bool :=
  t.name.isNone && (match t.shape with | .int 64 => true | _ => false)
private def isBoolTy (t : TypeDeclV1) : Bool :=
  t.name.isNone && (match t.shape with | .bool => true | _ => false)

private unsafe def testConstPositive (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const ANSWER : UInt64 := 42\n" ++
    "  const NEG : Int64 := -7\n" ++
    "  const POS : Int64 := 7\n" ++
    "  const FLAG : Bool := true\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 42\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let rows ← constRowsOf session "pos" "ConstPos" body
  let types ← constTypesOf session "pos2" "ConstPos" body
  expect (rows.size == 4) s!"pos: expected 4 constants, got {rows.size}"
  let expectRow (idx : Nat) (nm : String) (tyPred : TypeDeclV1 → Bool)
      (wantBytes : ByteArray) : IO Unit := do
    match rows[idx]? with
    | some c =>
        expect (c.id == UInt32.ofNat idx) s!"pos[{idx}]: id"
        expect (c.name == nm) s!"pos[{idx}]: name '{c.name}' != '{nm}'"
        match types[c.typeId.toNat]? with
        | some t => expect (tyPred t) s!"pos[{idx}]: type mismatch for {nm}"
        | none => throw <| IO.userError s!"pos[{idx}]: typeId OOR"
        expect (c.valueBytes == wantBytes)
          s!"pos[{idx}]: valueBytes {c.valueBytes} != {wantBytes}"
    | none => throw <| IO.userError s!"pos[{idx}]: missing"
  expectRow 0 "ANSWER" isUInt64 (leBytesFromNat 42 8)
  expectRow 1 "NEG" isInt64 (intLeBytes (-7) 64)
  expectRow 2 "POS" isInt64 (intLeBytes 7 64)
  expectRow 3 "FLAG" isBoolTy (ByteArray.mk #[1])
  IO.println "  const positive rows: ok"

private unsafe def testConstString (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const GREETING : String := \"hi\"\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let rows ← constRowsOf session "str" "ConstStr" body
  expect (rows.size == 1) s!"str: expected 1 constant, got {rows.size}"
  match rows[0]? with
  | some c =>
      expect (c.name == "GREETING") "str: name"
      let want := leBytesFromNat 2 4 ++ ByteArray.mk #[104, 105]
      expect (c.valueBytes == want) s!"str: valueBytes {c.valueBytes} != {want}"
      IO.println "  const string row: ok"
  | none => throw <| IO.userError "str: missing row"

private unsafe def testConstNegatives (session : Language.Loader.ParserSession) : IO Unit := do
  expectNormalizeFails session "neg-state" "ConstNegState"
    ("  state count : UInt64\n" ++
     "  const C : UInt64 := count\n" ++
     "  init() do\n    count := 0\n  view get() : UInt64 do\n    return count\n")
    "const value"
  expectNormalizeFails session "neg-binary" "ConstNegBin"
    ("  const C : UInt64 := 1 + 2\n" ++
     "  state count : UInt64\n  init() do\n    count := 0\n  view get() : UInt64 do\n    return count\n")
    "const value"
  expectNormalizeFails session "neg-uint-neg" "ConstNegUIntNeg"
    ("  const C : UInt64 := -1\n" ++
     "  state count : UInt64\n  init() do\n    count := 0\n  view get() : UInt64 do\n    return count\n")
    "Int expected type"
  IO.println "  const negatives fail closed: ok"

/-- Entry return of a pre-declared const → sole Op.Constant. -/
private unsafe def testConstBodyReturn (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const ANSWER : UInt64 := 42\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry answer() : UInt64 do\n" ++
    "    return ANSWER\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, data) ← dataOf session "ret" "ConstRet" body
  expect (data.constants.size == 1) "ret: one constant"
  let some c0 := data.constants[0]? | throw <| IO.userError "ret: missing const"
  expect (c0.name == "ANSWER" && c0.id == 0) "ret: ANSWER id 0"
  -- callables: init=0, entry=1, view=2
  let some entryC := data.callables[1]? | throw <| IO.userError "ret: missing entry"
  expect (entryC.kind == .entry) "ret: entry kind"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "ret: missing block"
  expect (blk.instructions.size == 1) s!"ret: expected 1 instr, got {blk.instructions.size}"
  match blk.instructions[0]? with
  | some instr =>
      match instr.op, instr.result with
      | .constant cid, some r =>
          expect (cid == 0) "ret: ConstantId 0"
          expect (r.typeId == c0.typeId) "ret: result.typeId == Constant.typeId"
          expect (r.valueId == 0) "ret: ValueId 0 (no params)"
      | _, _ => throw <| IO.userError "ret: expected Op.Constant"
  | none => throw <| IO.userError "ret: empty instr"
  IO.println "  const body return Op.Constant: ok"

/-- Forward reference: const after the reading entry. -/
private unsafe def testConstForwardRef (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry answer() : UInt64 do\n" ++
    "    return LATER\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n" ++
    "  const LATER : UInt64 := 99\n"
  let (_, data) ← dataOf session "fwd" "ConstFwd" body
  expect (data.constants.size == 1) "fwd: one constant"
  let some c0 := data.constants[0]? | throw <| IO.userError "fwd: missing const"
  expect (c0.name == "LATER" && c0.id == 0) "fwd: LATER id 0"
  expect (c0.valueBytes == leBytesFromNat 99 8) "fwd: valueBytes"
  let some entryC := data.callables[1]? | throw <| IO.userError "fwd: missing entry"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "fwd: missing block"
  match blk.instructions[0]? with
  | some instr =>
      match instr.op, instr.result with
      | .constant 0, some r => expect (r.typeId == c0.typeId) "fwd: typeId"
      | _, _ => throw <| IO.userError "fwd: expected Op.Constant 0"
  | none => throw <| IO.userError "fwd: no instr"
  IO.println "  const forward reference: ok"

/-- View / pureFn / invariant body reads. -/
private unsafe def testConstInViewFnInvariant
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const K : UInt64 := 7\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  fn scale(x : UInt64) : UInt64 do\n" ++
    "    return x + K\n" ++
    "  entry use(x : UInt64) : UInt64 do\n" ++
    "    return scale(x)\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return K\n" ++
    "  invariant alwaysK : K == 7\n"
  let (_, data) ← dataOf session "vfi" "ConstVFI" body
  expect (data.constants.size == 1) "vfi: one constant"
  let some c0 := data.constants[0]? | throw <| IO.userError "vfi: missing const"
  -- callables source order: init, fn scale, entry use, view peek, invariant
  let some fnC := data.callables[1]? | throw <| IO.userError "vfi: missing fn"
  expect (fnC.kind == .pureFn) "vfi: pureFn"
  let some fnBlk := fnC.blocks[0]? | throw <| IO.userError "vfi: fn block"
  -- param x = valueId 0; Op.Constant K; binary add
  let mut sawConst := false
  for instr in fnBlk.instructions do
    match instr.op with
    | .constant cid =>
        expect (cid == 0) "vfi: fn ConstantId"
        match instr.result with
        | some r => expect (r.typeId == c0.typeId) "vfi: fn result type"
        | none => throw <| IO.userError "vfi: fn constant missing result"
        sawConst := true
    | _ => pure ()
  expect sawConst "vfi: fn body must emit Op.Constant"
  let some viewC := data.callables[3]? | throw <| IO.userError "vfi: missing view"
  expect (viewC.kind == .view) "vfi: view kind"
  let some vBlk := viewC.blocks[0]? | throw <| IO.userError "vfi: view block"
  match vBlk.instructions[0]? with
  | some instr =>
      match instr.op, instr.result with
      | .constant 0, some _ => pure ()
      | _, _ => throw <| IO.userError "vfi: view expected Op.Constant 0"
  | none => throw <| IO.userError "vfi: view empty"
  let some invC := data.callables[4]? | throw <| IO.userError "vfi: missing inv"
  expect (invC.kind == .invariant) "vfi: invariant kind"
  let some iBlk := invC.blocks[0]? | throw <| IO.userError "vfi: inv block"
  let mut invSaw := false
  for instr in iBlk.instructions do
    match instr.op with
    | .constant 0 => invSaw := true
    | _ => pure ()
  expect invSaw "vfi: invariant must read K via Op.Constant"
  IO.println "  const in view/fn/invariant: ok"

/-- Binary + unannotated let + comparison synthesize from const place type. -/
private unsafe def testConstTypeSynthesis
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const BASE : UInt64 := 10\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry math() : UInt64 do\n" ++
    "    let doubled := BASE + BASE\n" ++
    "    assert BASE == 10\n" ++
    "    return doubled\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, data) ← dataOf session "syn" "ConstSyn" body
  let some c0 := data.constants[0]? | throw <| IO.userError "syn: missing const"
  let some entryC := data.callables[1]? | throw <| IO.userError "syn: missing entry"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "syn: missing block"
  -- Expected ops: Constant, Constant, add, Constant, literal 10, eq, assert
  let mut constCount : Nat := 0
  for instr in blk.instructions do
    match instr.op with
    | .constant cid =>
        expect (cid == 0) "syn: ConstantId"
        match instr.result with
        | some r =>
            expect (r.typeId == c0.typeId) "syn: result typeId"
        | none => throw <| IO.userError "syn: constant missing result"
        constCount := constCount + 1
    | _ => pure ()
  -- BASE+BASE → 2; BASE==10 → 1; total 3 independent Op.Constant
  expect (constCount == 3) s!"syn: expected 3 Op.Constant, got {constCount}"
  IO.println "  const type synthesis (let/binary/cmp): ok"

/-- Param and let shadowing must not emit Op.Constant for the shadowed name. -/
private unsafe def testConstShadowing (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const C : UInt64 := 42\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry withParam(C : UInt64) : UInt64 do\n" ++
    "    return C\n" ++
    "  entry withLet() : UInt64 do\n" ++
    "    let C : UInt64 := 1\n" ++
    "    return C\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, data) ← dataOf session "sh" "ConstShadow" body
  -- callables: init=0, withParam=1, withLet=2, view=3
  let some withParam := data.callables[1]? | throw <| IO.userError "sh: withParam"
  let some pBlk := withParam.blocks[0]? | throw <| IO.userError "sh: param block"
  expect (pBlk.instructions.isEmpty)
    s!"sh: param return must not emit instrs (env reuse), got {pBlk.instructions.size}"
  let some withLet := data.callables[2]? | throw <| IO.userError "sh: withLet"
  let some lBlk := withLet.blocks[0]? | throw <| IO.userError "sh: let block"
  for instr in lBlk.instructions do
    match instr.op with
    | .constant _ => throw <| IO.userError "sh: let shadow must not emit Op.Constant"
    | _ => pure ()
  -- Positive control: unshadowed read still emits Constant
  let body2 :=
    "  const C : UInt64 := 42\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry bare() : UInt64 do\n" ++
    "    return C\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, data2) ← dataOf session "sh2" "ConstShadow2" body2
  let some bare := data2.callables[1]? | throw <| IO.userError "sh2: bare"
  let some bBlk := bare.blocks[0]? | throw <| IO.userError "sh2: block"
  match bBlk.instructions[0]? with
  | some instr =>
      match instr.op, instr.result with
      | .constant 0, some _ => pure ()
      | _, _ => throw <| IO.userError "sh2: bare return must be Op.Constant"
  | none => throw <| IO.userError "sh2: bare return must be Op.Constant"
  IO.println "  const shadowing (param/let): ok"

/-- ValueId order: each const read allocates a fresh result ValueId. -/
private unsafe def testConstValueIdOrder
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body :=
    "  const A : UInt64 := 1\n" ++
    "  const B : UInt64 := 2\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry sum() : UInt64 do\n" ++
    "    return A + B\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, data) ← dataOf session "vid" "ConstVid" body
  let some entryC := data.callables[1]? | throw <| IO.userError "vid: entry"
  let some blk := entryC.blocks[0]? | throw <| IO.userError "vid: block"
  -- instr0 Constant A → valueId 0; instr1 Constant B → valueId 1; instr2 add → valueId 2
  expect (blk.instructions.size == 3) s!"vid: expected 3 instrs, got {blk.instructions.size}"
  let some i0 := blk.instructions[0]? | throw <| IO.userError "vid: i0"
  let some i1 := blk.instructions[1]? | throw <| IO.userError "vid: i1"
  let some i2 := blk.instructions[2]? | throw <| IO.userError "vid: i2"
  let some ca := data.constants[0]? | throw <| IO.userError "vid: missing A"
  let some cb := data.constants[1]? | throw <| IO.userError "vid: missing B"
  match i0.op, i0.result, i1.op, i1.result, i2.op, i2.result with
  | .constant 0, some r0, .constant 1, some r1, .binary .add _ _, some r2 =>
      expect (r0.valueId == 0 && r1.valueId == 1 && r2.valueId == 2)
        s!"vid: valueIds {r0.valueId},{r1.valueId},{r2.valueId}"
      expect (r0.typeId == ca.typeId) "vid: A type"
      expect (r1.typeId == cb.typeId) "vid: B type"
  | _, _, _, _, _, _ => throw <| IO.userError "vid: unexpected instruction sequence"
  IO.println "  const ValueId / ConstantId order: ok"

/-- UInt32 exact synthesis: `return 1 + NARROW` and comparison with const place.
    Typed rejects bare integer lhs without expected type (`10 == N`); accepted
    forms use enclosing UInt32 result or place-first comparison. -/
private unsafe def testConstNarrowRhsSynthesis
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- `1 + NARROW` under UInt32 return: both operands lower at UInt32; Op.Constant
  -- result.typeId == Constant.typeId; binary result UInt32 (not UInt64).
  let bodyAdd :=
    "  const NARROW : UInt32 := 5\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry addOne() : UInt32 do\n" ++
    "    return 1 + NARROW\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, dataAdd) ← dataOf session "narrow-add" "ConstNarrowAdd" bodyAdd
  let some cN := dataAdd.constants[0]? | throw <| IO.userError "narrow-add: const"
  expect (cN.name == "NARROW") "narrow-add: name"
  match dataAdd.types[cN.typeId.toNat]? with
  | some t => expect (isUInt32 t) "narrow-add: const type UInt32"
  | none => throw <| IO.userError "narrow-add: type OOR"
  let some entryAdd := dataAdd.callables[1]? |
    throw <| IO.userError "narrow-add: entry"
  let some blkAdd := entryAdd.blocks[0]? | throw <| IO.userError "narrow-add: block"
  -- literal 1, Op.Constant NARROW, binary add — all UInt32
  expect (blkAdd.instructions.size == 3)
    s!"narrow-add: expected 3 instrs, got {blkAdd.instructions.size}"
  let some iLit := blkAdd.instructions[0]? | throw <| IO.userError "narrow-add: lit"
  let some iC := blkAdd.instructions[1]? | throw <| IO.userError "narrow-add: const"
  let some iAdd := blkAdd.instructions[2]? | throw <| IO.userError "narrow-add: add"
  match iLit.op, iLit.result, iC.op, iC.result, iAdd.op, iAdd.result with
  | .literal tidL _, some rL, .constant 0, some rC, .binary .add _ _, some rA =>
      expect (tidL == cN.typeId && rL.typeId == cN.typeId) "narrow-add: lit UInt32"
      expect (rC.typeId == cN.typeId) "narrow-add: Constant result UInt32"
      expect (rA.typeId == cN.typeId) "narrow-add: add result UInt32"
  | _, _, _, _, _, _ => throw <| IO.userError "narrow-add: unexpected ops"

  -- Annotated let supplies UInt32 directly (it does not call
  -- `synthLetExpectedV1`); this still pins Op.Constant + add at UInt32.
  let bodyLet :=
    "  const NARROW : UInt32 := 5\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry viaLet() : UInt32 do\n" ++
    "    let x : UInt32 := 1 + NARROW\n" ++
    "    return x\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, dataLet) ← dataOf session "narrow-let" "ConstNarrowLet" bodyLet
  let some cL := dataLet.constants[0]? | throw <| IO.userError "narrow-let: const"
  let some entryL := dataLet.callables[1]? | throw <| IO.userError "narrow-let: entry"
  let some blkL := entryL.blocks[0]? | throw <| IO.userError "narrow-let: block"
  let mut sawC := false
  for instr in blkL.instructions do
    match instr.op, instr.result with
    | .constant 0, some r =>
        expect (r.typeId == cL.typeId) "narrow-let: Constant UInt32"
        sawC := true
    | .binary .add _ _, some r =>
        expect (r.typeId == cL.typeId) "narrow-let: add UInt32"
    | _, _ => pure ()
  expect sawC "narrow-let: must emit Op.Constant"

  -- Comparison: TypeCheck rejects `10 == NARROW` (integer lhs without expected).
  -- Accepted form `NARROW == 10` keeps exact UInt32 on Constant + literal.
  let bodyCmp :=
    "  const NARROW : UInt32 := 10\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry check() : UInt64 do\n" ++
    "    assert NARROW == 10\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, dataCmp) ← dataOf session "narrow-cmp" "ConstNarrowCmp" bodyCmp
  let some cCmp := dataCmp.constants[0]? | throw <| IO.userError "narrow-cmp: const"
  let some entryCmp := dataCmp.callables[1]? |
    throw <| IO.userError "narrow-cmp: entry"
  let some blkCmp := entryCmp.blocks[0]? | throw <| IO.userError "narrow-cmp: block"
  let mut sawConstCmp := false
  let mut sawLitU32 := false
  for instr in blkCmp.instructions do
    match instr.op, instr.result with
    | .constant 0, some r =>
        expect (r.typeId == cCmp.typeId) "narrow-cmp: Constant UInt32"
        sawConstCmp := true
    | .literal tid _, some r =>
        if tid == cCmp.typeId && r.typeId == cCmp.typeId then
          sawLitU32 := true
    | _, _ => pure ()
  expect sawConstCmp "narrow-cmp: Op.Constant"
  expect sawLitU32 "narrow-cmp: literal 10 at UInt32 (not UInt64)"

  -- Document Typed rejection of literal-lhs equality without expected width.
  expectNormalizeFails session "narrow-cmp-lit-lhs" "ConstNarrowCmpLit"
    ("  const NARROW : UInt32 := 10\n" ++
     "  state count : UInt64\n" ++
     "  init() do\n    count := 0\n" ++
     "  entry check() : UInt64 do\n" ++
     "    assert 10 == NARROW\n" ++
     "    return count\n" ++
     "  view get() : UInt64 do\n    return count\n")
    "integer"
  IO.println "  const narrow UInt32 rhs/synthesis: ok"

/-- For endpoint width from endExclusive const when start is typed place. -/
private unsafe def testConstForEndpoint
    (session : Language.Loader.ParserSession) : IO Unit := do
  -- Typed rejects bare `for i in 0 ..< LIMIT` (integer start without expected).
  -- Accepted: let-bound zero UInt32 + LIMIT const; startTid from start place,
  -- end lowers at that width; LIMIT emits Op.Constant UInt32.
  let body :=
    "  const LIMIT : UInt32 := 4\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry loopSum() : UInt64 do\n" ++
    "    let zero : UInt32 := 0\n" ++
    "    for i in zero ..< LIMIT bounded 4 do\n" ++
    "      count := count + 1\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (_, data) ← dataOf session "for-end" "ConstForEnd" body
  let some cLim := data.constants[0]? | throw <| IO.userError "for-end: const"
  match data.types[cLim.typeId.toNat]? with
  | some t => expect (isUInt32 t) "for-end: LIMIT UInt32"
  | none => throw <| IO.userError "for-end: type OOR"
  let some entryC := data.callables[1]? | throw <| IO.userError "for-end: entry"
  let mut sawLimit := false
  for blk in entryC.blocks do
    for instr in blk.instructions do
      match instr.op, instr.result with
      | .constant 0, some r =>
          expect (r.typeId == cLim.typeId) "for-end: Constant result UInt32"
          sawLimit := true
      | _, _ => pure ()
  expect sawLimit "for-end: LIMIT must emit Op.Constant"
  -- End-fallback path: start non-place + end place (Normalize-side). Typed
  -- still rejects bare integer start; pin that surface.
  expectNormalizeFails session "for-lit-start" "ConstForLitStart"
    ("  const LIMIT : UInt32 := 4\n" ++
     "  state count : UInt64\n" ++
     "  init() do\n    count := 0\n" ++
     "  entry loopSum() : UInt64 do\n" ++
     "    for i in 0 ..< LIMIT bounded 4 do\n" ++
     "      count := count + 1\n" ++
     "    return count\n" ++
     "  view get() : UInt64 do\n    return count\n")
    "integer"
  IO.println "  const for endpoint UInt32: ok"

/-- Provenance: declaration + typeRef from ConstDecl.type + body place. -/
private unsafe def testConstProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ConstProv" <|
    "  const ANSWER : UInt64 := 42\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry answer() : UInt64 do\n" ++
    "    return ANSWER\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "prov" source
  let path ← parseTestPath "prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"prov: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"prov: normalize+provenance: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov: validate: {repr e}"
  expect (data.constants.size == 1) "prov: one constant"
  let some c0 := data.constants[0]? | throw <| IO.userError "prov: row"
  let some constOrig := findOrigin provenance (.constant 0) |
    throw <| IO.userError "prov: missing .constant 0 origin"
  let constItemPath := childPathT #[] "Program" "items" 0
  let expConstDecl ← originAtExplicitPath validated inventory constItemPath
  expect (constOrig == expConstDecl)
    "prov: .constant origin must equal ConstDecl item origin"
  -- UInt64 may already be bound by state; novel-width const pins typeRef below.
  -- Body place: instruction 0 / value 0 of entry (callable 1).
  let some instrOrig := findOrigin provenance (.instruction 1 0 0) |
    throw <| IO.userError "prov: missing instruction origin"
  let some valOrig := findOrigin provenance (.value 1 0) |
    throw <| IO.userError "prov: missing value origin"
  expect (instrOrig == valOrig)
    "prov: instruction and value must share const place origin"
  expect (constOrig != instrOrig)
    "prov: constant decl origin must differ from body Op.Constant place"
  let expected := collectProgramEntityRefsV1 data
  expect (provenance.originMap.size == expected.size)
    s!"prov: originMap size {provenance.originMap.size} != expected {expected.size}"
  let _ := c0
  IO.println "  const provenance (decl + body place): ok"

/-- Novel UInt32 const: `.typeRef` origin is exactly ConstDecl.type path. -/
private unsafe def testConstTypeRefProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ConstTypeRef" <|
    "  const NARROW : UInt32 := 3\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  entry use() : UInt32 do\n" ++
    "    return NARROW\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "type-ref" source
  let path ← parseTestPath "type-ref"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"type-ref: inventory: {repr e}"
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"type-ref: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"type-ref: validate: {repr e}"
  let some c0 := data.constants[0]? | throw <| IO.userError "type-ref: row"
  let typePath := directChildT (childPathT #[] "Program" "items" 0) "ConstDecl" "type"
  let expTypeOrigin ← originAtExplicitPath validated inventory typePath
  let some typeOrig := findOrigin provenance (.typeRef c0.typeId) |
    throw <| IO.userError "type-ref: missing .typeRef origin"
  expect (typeOrig == expTypeOrigin)
    "type-ref: .typeRef must equal ConstDecl.type inventory origin"
  IO.println "  const typeRef → ConstDecl.type: ok"

/-- Unreferenced Bool const: declaration entities + value.bool req on ConstDecl.type. -/
private unsafe def testConstRowsProvenance
    (session : Language.Loader.ParserSession) : IO Unit := do
  let source := wrap "ConstRowsProv" <|
    "  const ANSWER : UInt64 := 42\n" ++
    "  const FLAG : Bool := false\n" ++
    "  state count : UInt64\n" ++
    "  init() do\n" ++
    "    count := 0\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let (validated, spans) ← loadSourceWithSpans session "rows-prov" source
  let path ← parseTestPath "rows-prov"
  let inventory ← match buildSourceNodeInventoryV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"rows-prov: inventory: {repr e}"
  match normalizeProgramWithProvenanceV1 validated path spans with
  | .ok (carrier, provenance) =>
      let data ← match validateSemanticProgramV1 carrier with
        | .ok d => pure d
        | .error e => throw <| IO.userError s!"rows-prov: validate: {repr e}"
      expect (data.constants.size == 2) "rows-prov: 2 constants"
      let some o0 := findOrigin provenance (.constant 0) |
        throw <| IO.userError "rows-prov: missing constant 0"
      let some o1 := findOrigin provenance (.constant 1) |
        throw <| IO.userError "rows-prov: missing constant 1"
      expect (o0 != o1) "rows-prov: distinct origins per const"
      -- FLAG is items[1]; ConstDecl.type is value.bool producing site.
      let flagTypePath :=
        directChildT (childPathT #[] "Program" "items" 1) "ConstDecl" "type"
      let expBoolType ← originAtExplicitPath validated inventory flagTypePath
      let mut foundBoolReq := false
      let mut ri : Nat := 0
      for req in data.requirements.items do
        if req.id == s2ValueBoolIdV1 then
          let orgs := findOrigins provenance (.requirement (UInt32.ofNat ri))
          expect (orgs.any (· == expBoolType))
            "rows-prov: value.bool origin must include ConstDecl.type"
          foundBoolReq := true
        ri := ri + 1
      expect foundBoolReq "rows-prov: value.bool requirement present"
      -- Bool typeRef from FLAG const type path.
      let some flagRow := data.constants[1]? |
        throw <| IO.userError "rows-prov: FLAG row"
      let some boolTypeOrig := findOrigin provenance (.typeRef flagRow.typeId) |
        throw <| IO.userError "rows-prov: missing Bool typeRef"
      expect (boolTypeOrig == expBoolType)
        "rows-prov: Bool typeRef origin == ConstDecl.type"
      IO.println "  const rows provenance (unreferenced + value.bool): ok"
  | .error e => throw <| IO.userError s!"rows-prov: {repr e}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  IO.println "Tests.Semantic.NormalizeConst: start"
  testConstPositive session
  testConstString session
  testConstNegatives session
  testConstBodyReturn session
  testConstForwardRef session
  testConstInViewFnInvariant session
  testConstTypeSynthesis session
  testConstShadowing session
  testConstValueIdOrder session
  testConstNarrowRhsSynthesis session
  testConstForEndpoint session
  testConstProvenance session
  testConstTypeRefProvenance session
  testConstRowsProvenance session
  IO.println "Tests.Semantic.NormalizeConst: ok"

end Tests.Semantic.NormalizeConst
