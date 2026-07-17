/-
  Tests.Core.Unicode — RED acceptance tests for the pinned pure-Lean NFC layer.

  Authority: ADR-0014 (pin Unicode 17.0.0, UAX #15 revision 57, NFC executed in
  pure Lean) and SPEC-COMMON-001 (`ProjectRelativePath` / `QualifiedName` /
  canonical string fields must already be NFC, fail closed on non-canonical
  spellings, reject `General_Category=Cc`; TST-COMMON-001).

  Production API under test:

    normalizeNfc : String -> Except String String
    requireNfc   : String -> Except String Unit
    isUnicodeCc  : Char -> Bool

  Every vector is a fixed golden derived independently from UAX #15 revision 57
  semantics for Unicode 17.0.0 (canonical decomposition, canonical combining
  class stable ordering, blocking, Hangul algorithmic mapping, composition
  exclusions). They are not transcribed from, and the production side must not
  be tuned against, any candidate implementation's tables or algorithm.

  Inputs are built directly as `String` values from explicit scalar values via
  `Char.ofNat`, so the API is exercised on direct `String` construction rather
  than only through JSON/decoder paths, and so this file is immune to editor-
  or host-level normalization of its own source bytes.

  The production slice wires this module into `ProofForgeV2Tests` and the
  aggregate `Tests.lean` runner.
-/
import ProofForgeV2.Core.Unicode

namespace Tests.Core.Unicode

open ProofForgeV2.Core.Unicode

private def expectOk {α} [BEq α] [Repr α]
    (label : String) (got : Except String α) (want : α) : IO Unit := do
  match got with
  | .ok value =>
    unless value == want do
      throw <| IO.userError s!"{label}: expected {repr want}, got {repr value}"
  | .error e => throw <| IO.userError s!"{label}: unexpected error {e}"

private def expectErr {α} (label : String) (got : Except String α) : IO Unit := do
  match got with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

-- Build a `String` directly from Unicode scalar values; deterministic by
-- construction and independent of this file's own encoding.
private def ofScalars (codePoints : List Nat) : String :=
  codePoints.foldl (fun acc cp => acc.push (Char.ofNat cp)) ""

-- Fixed UAX #15 golden: exact code-point equality for `normalizeNfc`, plus
-- idempotence — NFC applied to its own output must be a fixed point.
private def expectNfc (label : String) (input output : List Nat) : IO Unit := do
  expectOk label (normalizeNfc (ofScalars input)) (ofScalars output)
  expectOk s!"{label} (idempotent)" (normalizeNfc (ofScalars output)) (ofScalars output)

private def testLatin : IO Unit := do
  -- Composed form is stable; the decomposed spelling composes to the same NFC.
  expectNfc "latin composed e-acute stable"
    [0x00E9] [0x00E9]
  expectNfc "latin e + combining acute composes"
    [0x0065, 0x0301] [0x00E9]
  expectNfc "latin D + combining dot above composes"
    [0x0044, 0x0307] [0x1E0A]
  expectNfc "latin A + combining ring above composes"
    [0x0041, 0x030A] [0x00C5]
  -- Singleton canonical decomposition: ANGSTROM SIGN maps to the composed Å.
  expectNfc "angstrom singleton maps to A-ring"
    [0x212B] [0x00C5]
  -- ASCII and empty are trivially NFC.
  expectNfc "ascii unchanged"
    [0x61, 0x62, 0x63] [0x61, 0x62, 0x63]
  expectNfc "empty unchanged"
    [] []

private def testCombiningOrder : IO Unit := do
  -- Canonical ordering: marks are stably sorted by ascending canonical
  -- combining class. ccc(0315)=232 must move after ccc(0300)=230, after which
  -- a+grave composes to à.
  expectNfc "reorder ccc 232 past 230 then compose"
    [0x0061, 0x0315, 0x0300] [0x00E0, 0x0315]
  -- Reorder across classes (acute 230 vs dot below 220); a+dot below then
  -- composes to ạ and the acute has no further composite.
  expectNfc "reorder ccc 230 past 220 then compose"
    [0x0061, 0x0301, 0x0323] [0x1EA1, 0x0301]
  -- Equal combining classes keep their original relative order (stable sort).
  expectNfc "equal ccc stable order"
    [0x0061, 0x0301, 0x0300] [0x00E1, 0x0300]

private def testLongAdversarialOrder : IO Unit := do
  -- A single starter followed by alternating ccc=232/220 marks is the
  -- adversarial shape for insertion-based canonical reordering. Keep this long
  -- enough to catch a quadratic implementation while retaining an exact
  -- independent golden: the first dot-below composes with `a`, the remaining
  -- ccc=220 marks precede every ccc=232 mark, and equal classes stay stable.
  let pairCount := 2000
  let inputTail := (List.range pairCount).flatMap fun _ => [0x0315, 0x0323]
  let expectedTail :=
    List.replicate (pairCount - 1) 0x0323 ++ List.replicate pairCount 0x0315
  expectNfc "long alternating combining classes"
    (0x0061 :: inputTail) (0x1EA1 :: expectedTail)

private def testBlocking : IO Unit := do
  -- Blocking: an intervening mark with ccc >= the candidate's ccc blocks
  -- composition. COMBINING COMMA ABOVE (230) does not compose with `a` and
  -- blocks COMBINING GRAVE (230 >= 230): already NFC, must NOT collapse to
  -- à + comma above.
  expectNfc "equal ccc blocks composition"
    [0x0061, 0x0313, 0x0300] [0x0061, 0x0313, 0x0300]
  -- A lower-ccc intervening mark does NOT block: COMBINING CEDILLA (202)
  -- stays put, but a+acute (230) still composes past it.
  expectNfc "lower ccc does not block composition"
    [0x0061, 0x0327, 0x0301] [0x00E1, 0x0327]

private def testHangul : IO Unit := do
  -- Algorithmic Hangul: S = SBase + (L*VCount + V)*TCount + T.
  expectNfc "hangul L+V composes to GA"
    [0x1100, 0x1161] [0xAC00]
  expectNfc "hangul L+V+T composes to GAG"
    [0x1100, 0x1161, 0x11A8] [0xAC01]
  -- An already-composed LV syllable absorbs a following trailing jamo.
  expectNfc "hangul LV syllable + T composes"
    [0xAC00, 0x11A8] [0xAC01]
  expectNfc "hangul composed syllable stable"
    [0xAC01] [0xAC01]
  -- Last syllable boundary: L=18, V=20, T=27 gives SIndex 11171 = U+D7A3.
  expectNfc "hangul max syllable composes"
    [0x1112, 0x1175, 0x11C2] [0xD7A3]
  -- V+T without a leading L has no algorithmic composition; already NFC.
  expectNfc "hangul V+T without L unchanged"
    [0x1161, 0x11A8] [0x1161, 0x11A8]

private def testCompositionExclusion : IO Unit := do
  -- Composition exclusions: DEVANAGARI LETTER QA decomposes canonically but
  -- must never be recomposed from its decomposition.
  expectNfc "excluded QA decomposes"
    [0x0958] [0x0915, 0x093C]
  expectNfc "excluded QA never recomposed"
    [0x0915, 0x093C] [0x0915, 0x093C]

private def testRequireNfc : IO Unit := do
  -- `requireNfc` accepts exactly the strings that are already NFC and fails
  -- closed on everything else — including on direct String construction.
  expectOk "requireNfc empty" (requireNfc (ofScalars [])) ()
  expectOk "requireNfc ascii" (requireNfc (ofScalars [0x61, 0x62, 0x63])) ()
  expectOk "requireNfc composed e-acute" (requireNfc (ofScalars [0x00E9])) ()
  expectOk "requireNfc a-grave + comma above right"
    (requireNfc (ofScalars [0x00E0, 0x0315])) ()
  expectOk "requireNfc blocked sequence is NFC"
    (requireNfc (ofScalars [0x0061, 0x0313, 0x0300])) ()
  expectOk "requireNfc hangul composed syllable"
    (requireNfc (ofScalars [0xAC01])) ()
  expectOk "requireNfc hangul V+T without L"
    (requireNfc (ofScalars [0x1161, 0x11A8])) ()
  expectOk "requireNfc excluded decomposition is NFC"
    (requireNfc (ofScalars [0x0915, 0x093C])) ()
  expectErr "requireNfc rejects decomposed e-acute"
    (requireNfc (ofScalars [0x0065, 0x0301]))
  expectErr "requireNfc rejects angstrom singleton"
    (requireNfc (ofScalars [0x212B]))
  expectErr "requireNfc rejects unordered marks"
    (requireNfc (ofScalars [0x0061, 0x0315, 0x0300]))
  expectErr "requireNfc rejects reorder-plus-compose"
    (requireNfc (ofScalars [0x0061, 0x0301, 0x0323]))
  expectErr "requireNfc rejects hangul L+V jamo"
    (requireNfc (ofScalars [0x1100, 0x1161]))
  expectErr "requireNfc rejects hangul L+V+T jamo"
    (requireNfc (ofScalars [0x1100, 0x1161, 0x11A8]))
  expectErr "requireNfc rejects excluded QA"
    (requireNfc (ofScalars [0x0958]))

private def testCcBoundaries : IO Unit := do
  -- General_Category=Cc is exactly U+0000..U+001F and U+007F..U+009F; pin both
  -- boundaries and adjacent non-Cc scalars.
  let ccTrue := [0x0000, 0x0009, 0x001F, 0x007F, 0x0080, 0x0085, 0x009F]
  let ccFalse := [0x0020, 0x007E, 0x00A0, 0x0301, 0x0061, 0xAC00]
  for cp in ccTrue do
    unless isUnicodeCc (Char.ofNat cp) do
      throw <| IO.userError s!"isUnicodeCc: expected true for scalar {cp}"
  for cp in ccFalse do
    if isUnicodeCc (Char.ofNat cp) then
      throw <| IO.userError s!"isUnicodeCc: expected false for scalar {cp}"

def run : IO Unit := do
  testLatin
  testCombiningOrder
  testLongAdversarialOrder
  testBlocking
  testHangul
  testCompositionExclusion
  testRequireNfc
  testCcBoundaries
  IO.println "Tests.Core.Unicode: ok"

end Tests.Core.Unicode
