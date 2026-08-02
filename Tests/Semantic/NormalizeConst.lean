/-
  Tests.Semantic.NormalizeConst — const declaration lowering slice.

  Positive pins: const UInt64 / Int64 (pos and neg) / Bool / String are
  evaluated at compile time into `constants` with canonical `valueBytes`
  (byte-identical to the `Op.Literal` encoding). Negative pins: non-literal
  const (place read, binary op) fail closed; a UInt-typed negative literal is
  rejected by CheckV1 (typedNotOk) before Normalize.
-/
import ProofForgeV2
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.ValidatedSourceV1
import Lean.Parser

namespace Tests.Semantic.NormalizeConst

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Language
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1

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

private def expect (ok : Bool) (msg : String) : IO Unit :=
  unless ok do throw <| IO.userError msg

private def expectOk {α} (label : String) (result : Except NormalizeErrorV1 α) : IO α := do
  match result with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: expected ok, got {repr e}"

/-- Normalize a const-bearing program and return its constants rows. -/
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
  -- const is declared but not referenced by the body — const *place reads*
  -- in bodies are a separate follow-on slice (lowerPlace does not yet resolve
  -- the constants table). This pin checks the constants table rows.
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

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  IO.println "Tests.Semantic.NormalizeConst: start"
  testConstPositive session
  testConstString session
  testConstNegatives session
  IO.println "Tests.Semantic.NormalizeConst: ok"

end Tests.Semantic.NormalizeConst
