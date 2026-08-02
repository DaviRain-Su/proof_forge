/-
  Tests.Semantic.NormalizeConst — const declaration + body reference slice
  (N-CONST + N-CONST-REF).

  Positive pins:
    * const UInt64 / Int64 (pos and neg) / Bool / String evaluate at compile
      time into `constants` with canonical `valueBytes` (byte-identical to
      `Op.Literal` encoding).
    * Body bare const places lower to value-producing `Op.Constant ConstantId`
      with `result.typeId == ConstantV1.typeId` (return, binary, unannotated
      let, comparison).
    * Forward reference: const declared after the reading callable still works
      (constants table complete before any body lowering).
    * Reads from entry / view / pureFn / invariant.
    * Param and let shadowing do not emit Op.Constant.
    * Independent Op.Constant per read; canonical ValueId order.
    * Provenance: `.constant id` → ConstDecl; Constant type → ConstDecl.type;
      body instruction/value → exact const place path; authority join exact.

  Negative pins: non-literal const (place read, binary op) fail closed; a
  UInt-typed negative literal is rejected by CheckV1 (typedNotOk) before
  Normalize.
-/
import ProofForgeV2
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.ProvenanceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import Lean.Parser

namespace Tests.Semantic.NormalizeConst

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProvenanceV1
open ProofForgeV2.Semantic.WireV1
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

/-- Provenance: declaration + type + body instruction/value exact join. -/
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
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 validated path spans with
    | .ok pair => pure pair
    | .error e => throw <| IO.userError s!"prov: normalize+provenance: {repr e}"
  let data ← match validateSemanticProgramV1 carrier with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"prov: validate: {repr e}"
  expect (data.constants.size == 1) "prov: one constant"
  let some constOrig := findOrigin provenance (.constant 0) |
    throw <| IO.userError "prov: missing .constant 0 origin"
  -- Instruction 0 / value 0 of entry (callable 1) bind the place path under return.
  let some instrOrig := findOrigin provenance (.instruction 1 0 0) |
    throw <| IO.userError "prov: missing instruction origin"
  let some valOrig := findOrigin provenance (.value 1 0) |
    throw <| IO.userError "prov: missing value origin"
  -- Origins must be present and instruction/value share the place origin.
  expect (instrOrig == valOrig)
    "prov: instruction and value must share const place origin"
  -- Declaration entity must differ from body place entity (different nodes).
  expect (constOrig != instrOrig)
    "prov: constant decl origin must differ from body Op.Constant place"
  -- Authority re-validation already ran inside normalizeProgramWithProvenanceV1.
  let expected := collectProgramEntityRefsV1 data
  expect (provenance.originMap.size == expected.size)
    s!"prov: originMap size {provenance.originMap.size} != expected {expected.size}"
  IO.println "  const provenance (decl + body place): ok"

/-- Unreferenced const still joins provenance (declaration entities only). -/
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
      IO.println "  const rows provenance (unreferenced): ok"
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
  testConstProvenance session
  testConstRowsProvenance session
  IO.println "Tests.Semantic.NormalizeConst: ok"

end Tests.Semantic.NormalizeConst
