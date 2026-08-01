import ProofForgeV2.Core.UnicodeData

namespace ProofForgeV2.Core.Unicode

open ProofForgeV2.Core.UnicodeData

/-- Unicode version that defines this module's normalization semantics. -/
def unicodeVersion : String := UnicodeData.unicodeVersion

private def canonicalCombiningClass (code : UInt32) : UInt8 := Id.run do
  let table := canonicalCombiningClassTable
  let mut low := 0
  let mut high := table.size
  while low < high do
    let middle := low + (high - low) / 2
    let row := table[middle]!
    if row.1 < code then
      low := middle + 1
    else
      high := middle
  if low < table.size then
    let row := table[low]!
    if row.1 == code then
      return row.2
  return 0

private def canonicalDecomposition? (code : UInt32) : Option (Array UInt32) := Id.run do
  let table := canonicalDecompositionTable
  let mut low := 0
  let mut high := table.size
  while low < high do
    let middle := low + (high - low) / 2
    let row := table[middle]!
    if row.code < code then
      low := middle + 1
    else
      high := middle
  if low < table.size then
    let row := table[low]!
    if row.code == code then
      return some row.mapping
  return none

private def tableComposition? (first second : UInt32) : Option UInt32 := Id.run do
  let table := compositionPairTable
  let mut low := 0
  let mut high := table.size
  while low < high do
    let middle := low + (high - low) / 2
    let row := table[middle]!
    if row.first < first || (row.first == first && row.second < second) then
      low := middle + 1
    else
      high := middle
  if low < table.size then
    let row := table[low]!
    if row.first == first && row.second == second then
      return some row.composite
  return none

private def hangulDecomposition? (code : UInt32) : Option (Array UInt32) :=
  let value := code.toNat
  let sBase := hangulSBase.toNat
  if sBase ≤ value && value < sBase + hangulSCount then
    let sIndex := value - sBase
    let leading := hangulLBase.toNat + sIndex / hangulNCount
    let vowel := hangulVBase.toNat + (sIndex % hangulNCount) / hangulTCount
    let trailingIndex := sIndex % hangulTCount
    if trailingIndex = 0 then
      some #[UInt32.ofNat leading, UInt32.ofNat vowel]
    else
      some #[
        UInt32.ofNat leading,
        UInt32.ofNat vowel,
        UInt32.ofNat (hangulTBase.toNat + trailingIndex)]
  else
    none

private def hangulComposition? (first second : UInt32) : Option UInt32 :=
  let firstValue := first.toNat
  let secondValue := second.toNat
  let lBase := hangulLBase.toNat
  let vBase := hangulVBase.toNat
  let tBase := hangulTBase.toNat
  let sBase := hangulSBase.toNat
  if lBase ≤ firstValue && firstValue < lBase + hangulLCount &&
      vBase ≤ secondValue && secondValue < vBase + hangulVCount then
    let leadingIndex := firstValue - lBase
    let vowelIndex := secondValue - vBase
    some <| UInt32.ofNat
      (sBase + (leadingIndex * hangulVCount + vowelIndex) * hangulTCount)
  else if sBase ≤ firstValue && firstValue < sBase + hangulSCount &&
      (firstValue - sBase) % hangulTCount = 0 &&
      tBase < secondValue && secondValue < tBase + hangulTCount then
    some <| UInt32.ofNat (firstValue + secondValue - tBase)
  else
    none

private def composition? (first second : UInt32) : Option UInt32 :=
  match hangulComposition? first second with
  | some composite => some composite
  | none => tableComposition? first second

private def appendAll (target source : Array UInt32) : Array UInt32 := Id.run do
  let mut result := target
  for code in source do
    result := result.push code
  return result

private def canonicalDecompose (value : String) : Array UInt32 := Id.run do
  let mut result := #[]
  for character in value.toList do
    let code := character.val
    match hangulDecomposition? code with
    | some mapping => result := appendAll result mapping
    | none =>
      match canonicalDecomposition? code with
      | some mapping => result := appendAll result mapping
      | none => result := result.push code
  return result

private structure CombiningEntry where
  combiningClass : UInt8
  sourceOrder : Nat
  code : UInt32

private def flushCombiningSegment
    (target : Array UInt32) (pending : Array CombiningEntry) : Array UInt32 := Id.run do
  if pending.isEmpty then
    return target
  let ordered := pending.mergeSort fun left right =>
    left.combiningClass < right.combiningClass ||
      (left.combiningClass == right.combiningClass && left.sourceOrder ≤ right.sourceOrder)
  let mut result := target
  for entry in ordered do
    result := result.push entry.code
  return result

private def canonicalReorder (codes : Array UInt32) : Array UInt32 := Id.run do
  let mut result := #[]
  let mut pending := #[]
  let mut sourceOrder := 0
  for code in codes do
    let codeClass := canonicalCombiningClass code
    if codeClass == 0 then
      result := flushCombiningSegment result pending
      pending := #[]
      sourceOrder := 0
      result := result.push code
    else
      pending := pending.push {
        combiningClass := codeClass
        sourceOrder
        code
      }
      sourceOrder := sourceOrder + 1
  return flushCombiningSegment result pending

private def canonicalCompose (codes : Array UInt32) : Array UInt32 := Id.run do
  if codes.isEmpty then
    return #[]
  let first := codes[0]!
  let mut result := #[first]
  let mut starterPosition : Option Nat :=
    if canonicalCombiningClass first == 0 then some 0 else none
  let mut starter := first
  let mut lastClass := canonicalCombiningClass first
  for index in [1:codes.size] do
    let code := codes[index]!
    let codeClass := canonicalCombiningClass code
    let mut wasComposed := false
    match starterPosition with
    | some position =>
      if lastClass == 0 || lastClass < codeClass then
        match composition? starter code with
        | some composite =>
          result := result.set! position composite
          starter := composite
          wasComposed := true
        | none => pure ()
    | none => pure ()
    unless wasComposed do
      if codeClass == 0 then
        starterPosition := some result.size
        starter := code
      result := result.push code
      lastClass := codeClass
  return result

private def codepointsToString (codes : Array UInt32) : Except String String := do
  let mut result := ""
  for code in codes do
    let value := code.toNat
    if h : value.isValidChar then
      result := result.push (Char.ofNatAux value h)
    else
      throw s!"generated Unicode table produced invalid scalar U+{value}"
  pure result

/-- True exactly when every scalar in the string is ASCII. ASCII has no
    canonical decomposition, nonzero combining class, or composition pair,
    so it is a fixed point of NFC normalization. -/
def isAscii (value : String) : Bool :=
  value.toList.all fun character => character.val ≤ 0x7f

/-- Normalize a Lean `String` to NFC using the pinned Unicode 17.0.0 tables. -/
def normalizeNfc (value : String) : Except String String := do
  if isAscii value then
    return value
  let decomposed := canonicalDecompose value
  let ordered := canonicalReorder decomposed
  codepointsToString (canonicalCompose ordered)

/-- ASCII strings are fixed points of the pinned NFC normalizer. -/
theorem normalizeNfc_eq_ok_of_isAscii (value : String) (hascii : isAscii value = true) :
    normalizeNfc value = .ok value := by
  simp only [normalizeNfc, hascii, ↓reduceIte, Pure.pure, Except.pure]

/-- Accept only strings that are already in the pinned NFC form. -/
def requireNfc (value : String) : Except String Unit := do
  let normalized ← normalizeNfc value
  unless normalized == value do
    throw s!"string must already be NFC under Unicode {unicodeVersion}"

/-- ASCII strings satisfy the pinned NFC requirement without expanding the
    generated Unicode tables in kernel proofs. -/
theorem requireNfc_eq_ok_of_isAscii (value : String) (hascii : isAscii value = true) :
    requireNfc value = .ok () := by
  simp only [requireNfc, normalizeNfc_eq_ok_of_isAscii value hascii, beq_self_eq_true,
    ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Test Unicode 17.0.0 `General_Category=Cc` using the generated ranges. -/
def isUnicodeCc (character : Char) : Bool :=
  let code := character.val
  generalCategoryCcRanges.any fun range =>
    range.start ≤ code && code ≤ range.endInclusive

end ProofForgeV2.Core.Unicode
