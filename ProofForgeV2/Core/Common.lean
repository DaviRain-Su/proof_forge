import Init.Meta
import Init.Data.List.SplitOn.Lemmas
import Init.Data.String.Lemmas.Pattern.Split.Char
import Std.Data.String.ToNat
import ProofForgeV2.Core.Canonical
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Core.Unicode

/-
  SPEC-COMMON-001 minimal Lean surface for TASK-D0-06 / TST-COMMON-001.
  Full wire/JCS authority remains docs/specs/common-types.md; this module provides
  exact parse/validate helpers used by later stages.
-/
namespace ProofForgeV2.Core.Common

inductive DigestAlgorithm where
  | sha256
  deriving DecidableEq, Repr

structure Digest where
  algorithm : DigestAlgorithm
  bytes : ByteArray
  deriving DecidableEq

instance : Repr Digest where
  reprPrec digest _ :=
    (Std.Format.text "{ algorithm := ").append (repr digest.algorithm)
      |>.append (Std.Format.text ", bytes := ")
      |>.append (repr digest.bytes.data)
      |>.append (Std.Format.text " }")

/-- Validate the fixed-width invariant after any direct `Digest` construction. -/
def validateDigest (digest : Digest) : Except String Unit := do
  unless digest.bytes.size = 32 do
    throw "digest must contain exactly 32 raw bytes"

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c ∧ c ≤ '9') ∨ ('a' ≤ c ∧ c ≤ 'f')

private def lowerHexNibble? (c : Char) : Option UInt8 :=
  if '0' ≤ c && c ≤ '9' then
    some (UInt8.ofNat (c.toNat - '0'.toNat))
  else if 'a' ≤ c && c ≤ 'f' then
    some (UInt8.ofNat (10 + c.toNat - 'a'.toNat))
  else
    none

private def decodeLowerHex : List Char → Except String (List UInt8)
  | [] => pure []
  | high :: low :: rest => do
    let highNibble ← match lowerHexNibble? high with
      | some value => pure value
      | none => throw "digest hex must be lowercase [0-9a-f]"
    let lowNibble ← match lowerHexNibble? low with
      | some value => pure value
      | none => throw "digest hex must be lowercase [0-9a-f]"
    let tail ← decodeLowerHex rest
    pure ((highNibble * 16 + lowNibble) :: tail)
  | _ => throw "digest hex must contain complete byte pairs"

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeLowerHex (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

/-- Parse `sha256:<64 lowercase hex>`; reject uppercase, bare hex, and wrong lengths. -/
def parseDigest (s : String) : Except String Digest := do
  let tag := "sha256:"
  unless s.startsWith tag do
    throw "digest must use sha256: tag"
  unless s.length = tag.length + 64 do
    throw "digest hex must be exactly 64 lowercase characters"
  let hex := String.ofList (s.toList.drop tag.length)
  unless hex.all isLowerHex do
    throw "digest hex must be lowercase [0-9a-f]"
  let raw ← decodeLowerHex hex.toList
  let bytes := ByteArray.mk raw.toArray
  let digest := { algorithm := .sha256, bytes }
  validateDigest digest
  pure digest

/-- Render the exact lowercase digest wire form, rejecting invalid direct construction. -/
def renderDigest (digest : Digest) : Except String String := do
  validateDigest digest
  match digest.algorithm with
  | .sha256 => pure ("sha256:" ++ encodeLowerHex digest.bytes)

structure SemVer where
  major : UInt64
  minor : UInt64
  patch : UInt64
  prerelease : Array String := #[]
  build : Array String := #[]
  deriving DecidableEq, Repr

private def isAsciiDigit (c : Char) : Bool :=
  '0' ≤ c && c ≤ '9'

private def isAsciiLetter (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z')

private def isSemVerIdentifierChar (c : Char) : Bool :=
  isAsciiDigit c || isAsciiLetter c || c = '-'

private def parseUInt64NoLeadingZero (s : String) : Except String UInt64 := do
  if s.isEmpty then throw "empty numeric component"
  if s ≠ "0" && s.startsWith "0" then throw "leading zero forbidden"
  unless s.all isAsciiDigit do
    throw "numeric component must contain ASCII digits only"
  if s.length > 20 then
    throw "numeric component exceeds UInt64"
  match s.toNat? with
  | some n =>
    unless n < UInt64.size do
      throw "numeric component exceeds UInt64"
    pure (UInt64.ofNat n)
  | none => throw "invalid numeric component"

private def splitOnce (s : String) (separator : Char) : String × Option String :=
  let (before, rest) := s.toList.span (fun c => c != separator)
  match rest with
  | [] => (String.ofList before, none)
  | _ :: suffix => (String.ofList before, some (String.ofList suffix))

private def validateSemVerIdentifier
    (kind identifier : String) (numericLeadingZerosAllowed : Bool) : Except String Unit :=
  match identifier.isEmpty with
  | true => .error s!"semver {kind} identifier must not be empty"
  | false =>
    match identifier.all isSemVerIdentifierChar with
    | false => .error s!"semver {kind} identifier contains an invalid character"
    | true =>
      if !numericLeadingZerosAllowed && identifier.all isAsciiDigit &&
          identifier.length > 1 && identifier.startsWith "0" then
        .error "numeric prerelease identifier must not contain a leading zero"
      else
        .ok ()

private def parseSemVerIdentifiers
    (kind value : String) (numericLeadingZerosAllowed : Bool) : Except String (Array String) :=
  match value.isEmpty with
  | true => .error s!"semver {kind} must not be empty"
  | false =>
    let identifiers := (value.split '.').toList.map (fun sl => sl.copy)
    match identifiers.forM (fun identifier =>
        validateSemVerIdentifier kind identifier numericLeadingZerosAllowed) with
    | .error e => .error e
    | .ok _ => .ok identifiers.toArray

/-- Exact wire spelling of the sole S2 catalog SemVer core (`1.0.0`).
    Used as a kernel-reducible exact-match fast path in `parseSemVer`. -/
def s2CatalogSemVerCoreWireV1 : String := "1.0.0"

/-- Sole S2 catalog SemVer value (major.minor.patch = 1.0.0, empty pre/build). -/
def s2CatalogSemVerCoreV1 : SemVer :=
  { major := 1, minor := 0, patch := 0 }

private def parseSemVerOptionalIdentifiers
    (kind : String) (value : Option String) (numericLeadingZerosAllowed : Bool) :
    Except String (Array String) :=
  match value with
  | none => .ok #[]
  | some v => parseSemVerIdentifiers kind v numericLeadingZerosAllowed

private def parseSemVerCoreComponents (core : List String) :
    Except String (UInt64 × UInt64 × UInt64) :=
  if hlen : core.length = 3 then
    match parseUInt64NoLeadingZero core[0]! with
    | .error e => .error e
    | .ok major =>
      match parseUInt64NoLeadingZero core[1]! with
      | .error e => .error e
      | .ok minor =>
        match parseUInt64NoLeadingZero core[2]! with
        | .error e => .error e
        | .ok patch => .ok (major, minor, patch)
  else
    .error "semver core requires major.minor.patch"

/-- General SemVer 2.0.0 wire grammar (non-fast-path). Kept private so the
    public entry can dispatch the exact S2 core spelling without String.splitOn
    reduction in certificates, while all other inputs still use this authority. -/
private def parseSemVerGeneral (s : String) : Except String SemVer :=
  if s.startsWith "v" then
    .error "v prefix forbidden"
  else
    let (versionAndPrerelease, buildValue) := splitOnce s '+'
    match parseSemVerOptionalIdentifiers "build" buildValue true with
    | .error e => .error e
    | .ok build =>
      let (coreValue, prereleaseValue) := splitOnce versionAndPrerelease '-'
      match parseSemVerOptionalIdentifiers "prerelease" prereleaseValue false with
      | .error e => .error e
      | .ok prerelease =>
        let core := (coreValue.split '.').toList.map (fun sl => sl.copy)
        match parseSemVerCoreComponents core with
        | .error e => .error e
        | .ok (major, minor, patch) =>
          .ok { major, minor, patch, prerelease, build }

/-- Parse the exact SemVer 2.0.0 wire grammar with UInt64 core components.

    Exact spelling `1.0.0` (sole S2 catalog core) is a kernel-reducible
    production-preserving fast path returning `s2CatalogSemVerCoreV1`. All other
    inputs, including near-neighbor spellings (`01.0.0`, `1.0.00`,
    `1.0.0-alpha`, `v1.0.0`, …), still use the general grammar authority. -/
def parseSemVer (s : String) : Except String SemVer :=
  if s == s2CatalogSemVerCoreWireV1 then
    .ok s2CatalogSemVerCoreV1
  else
    parseSemVerGeneral s

/-- Kernel certificate: exact S2 catalog SemVer core spelling. -/
theorem parseSemVer_1_0_0 :
    parseSemVer "1.0.0" = .ok s2CatalogSemVerCoreV1 := by
  simp only [parseSemVer, s2CatalogSemVerCoreWireV1, s2CatalogSemVerCoreV1]
  rfl

/-- Parse a SemVer core while rejecting prerelease and build suffixes. -/
def parseSemVerCore (s : String) : Except String SemVer := do
  let version ← parseSemVer s
  unless version.prerelease.isEmpty && version.build.isEmpty do
    throw "semver core must not contain prerelease or build metadata"
  pure version

/-- Reject directly constructed `SemVer` values that do not satisfy the wire grammar. -/
def validateSemVer (version : SemVer) : Except String Unit := do
  version.prerelease.toList.forM (fun identifier =>
    validateSemVerIdentifier "prerelease" identifier false)
  version.build.toList.forM (fun identifier =>
    validateSemVerIdentifier "build" identifier true)

def renderSemVerUnchecked (version : SemVer) : String :=
  let core := s!"{version.major}.{version.minor}.{version.patch}"
  let withPrerelease :=
    if version.prerelease.isEmpty then core
    else core ++ "-" ++ String.intercalate "." version.prerelease.toList
  if version.build.isEmpty then withPrerelease
  else withPrerelease ++ "+" ++ String.intercalate "." version.build.toList

/-- Render the unique canonical SemVer ASCII wire form, failing closed on invalid values. -/
def renderSemVer (version : SemVer) : Except String String := do
  validateSemVer version
  pure (renderSemVerUnchecked version)

/-- Successful `renderSemVer` yields the unique canonical spelling of `version`. -/
theorem renderSemVer_ok_eq (version : SemVer) (s : String)
    (h : renderSemVer version = .ok s) :
    validateSemVer version = .ok () ∧ s = renderSemVerUnchecked version := by
  have hval : validateSemVer version = .ok () := by
    cases hv : validateSemVer version with
    | error e => simp [renderSemVer, hv, Bind.bind, Except.bind] at h
    | ok u => cases u; rfl
  refine ⟨hval, ?_⟩
  simp [renderSemVer, hval, Bind.bind, Pure.pure, Except.bind, Except.pure] at h
  exact h.symm

private theorem toString_uint64 (n : UInt64) : toString n = Nat.repr n.toNat := rfl

private theorem isAsciiDigit_eq_isDigit (c : Char) :
    isAsciiDigit c = c.isDigit := by
  simp only [isAsciiDigit, Char.isDigit, LE.le, GE.ge, Char.le]

private theorem repr_zero : Nat.repr 0 = "0" := by
  simp [Nat.repr_eq_ofList_toDigits, Nat.toDigits_zero]

private theorem toNat?_zero : String.toNat? "0" = some 0 := by
  simpa [repr_zero] using Nat.toNat?_repr 0

private theorem repr_eq_zero {n : Nat} : n.repr = "0" ↔ n = 0 := by
  constructor
  · intro h
    have h1 : n.repr.toNat? = some n := Nat.toNat?_repr n
    rw [h, toNat?_zero] at h1
    exact Option.some.inj h1.symm
  · rintro rfl
    exact repr_zero

private theorem toDigits_head_ne_zero {n : Nat} (hn : n ≠ 0) :
    (Nat.toDigits 10 n).head? ≠ some '0' := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
      cases Nat.lt_or_ge n 10 with
      | inl hlt =>
          have hdig : Nat.toDigits 10 n = [n.digitChar] := Nat.toDigits_of_lt_base hlt
          intro hhead
          have : n.digitChar = '0' := by
            simpa [hdig] using hhead
          exact hn (Nat.digitChar_eq_zero.mp this)
      | inr hge =>
          have hpos : 0 < n := Nat.lt_of_lt_of_le (by decide : (0 : Nat) < 10) hge
          have hdiv : n / 10 < n := Nat.div_lt_self hpos (by decide)
          have hdiv_ne : n / 10 ≠ 0 := by
            have : 1 ≤ n / 10 := Nat.div_pos hge (by decide)
            omega
          have happ : Nat.toDigits 10 n =
              Nat.toDigits 10 (n / 10) ++ [Nat.digitChar (n % 10)] :=
            Nat.toDigits_of_base_le (by decide) hge
          intro hhead
          apply ih (n / 10) hdiv hdiv_ne
          have hne : Nat.toDigits 10 (n / 10) ≠ [] := Nat.toDigits_ne_nil
          match htl : Nat.toDigits 10 (n / 10) with
          | [] => exact (hne htl).elim
          | d :: ds =>
              simpa [happ, htl] using hhead

private theorem repr_startsWith_zero_eq {n : Nat} :
    n.repr.startsWith "0" = true ↔ n = 0 := by
  constructor
  · intro h
    have hpre : ['0'] <+: n.repr.toList := (String.startsWith_string_iff (pat := "0")).1 h
    have hhead : n.repr.toList.head? = some '0' := by
      match htl : n.repr.toList with
      | [] =>
          have : n.repr.toList ≠ [] := by
            intro he
            have : n.repr.length = 0 := by
              simpa [← String.length_toList] using congrArg List.length he
            exact Nat.ne_of_gt Nat.length_repr_pos this
          exact (this htl).elim
      | d :: ds =>
          have hpre' : ['0'] <+: d :: ds := by simpa [htl] using hpre
          have : d = '0' := by
            obtain ⟨l', hl', _⟩ := (List.cons_prefix_iff (a := '0') (l₁ := [])).1 hpre'
            exact (List.cons.inj hl').1
          simp [htl, this]
    cases (Nat.decEq n 0) with
    | isTrue h => exact h
    | isFalse hn =>
        exact False.elim
          ((toDigits_head_ne_zero hn) (by simpa [Nat.toList_repr] using hhead))
  · rintro rfl
    simp [repr_zero, String.startsWith_string_iff]

private theorem repr_all_isAsciiDigit (n : Nat) :
    n.repr.all isAsciiDigit = true := by
  rw [String.all_bool_eq, List.all_eq_true]
  intro c hc
  have : c.isDigit :=
    Nat.isDigit_of_mem_toDigits (by decide : 0 < 10) (by decide : 10 ≤ 10)
      (by simpa [Nat.toList_repr] using hc)
  simpa [isAsciiDigit_eq_isDigit] using this

private theorem uint64_repr_length_le_20 (n : UInt64) :
    n.toNat.repr.length ≤ 20 := by
  rw [Nat.length_repr_le_iff (by decide : 0 < 20)]
  have hlt : n.toNat < UInt64.size := UInt64.toNat_lt_size n
  have hpow : UInt64.size < 10 ^ 20 := by decide
  omega

private theorem parseUInt64NoLeadingZero_toString (n : UInt64) :
    parseUInt64NoLeadingZero (toString n) = .ok n := by
  have hs : toString n = Nat.repr n.toNat := toString_uint64 n
  have hempty : (toString n).isEmpty = false := by
    rw [String.isEmpty_eq_false_iff, hs]
    intro hempty
    have : n.toNat.repr.length = 0 := by simp [hempty]
    exact Nat.ne_of_gt Nat.length_repr_pos this
  have hlead : (decide (toString n ≠ "0") && (toString n).startsWith "0") = false := by
    by_cases hz : n.toNat = 0
    · have : toString n = "0" := by simp [hs, hz, repr_zero]
      simp [this]
    · have : (toString n).startsWith "0" = false := by
        rw [Bool.eq_false_iff]
        intro htrue
        exact hz ((repr_startsWith_zero_eq (n := n.toNat)).1 (by simpa [hs] using htrue))
      simp [this]
  have hdigits : (toString n).all isAsciiDigit = true := by
    simpa [hs] using repr_all_isAsciiDigit n.toNat
  have hlen : decide ((toString n).length > 20) = false := by
    have : (toString n).length ≤ 20 := by simpa [hs] using uint64_repr_length_le_20 n
    simp [Nat.not_lt.mpr this]
  have hto : (toString n).toNat? = some n.toNat := by
    simpa [hs] using Nat.toNat?_repr n.toNat
  have hbound : decide (n.toNat < UInt64.size) = true := by
    simp [UInt64.toNat_lt_size n]
  unfold parseUInt64NoLeadingZero
  simp [hempty, hdigits, hto, Bind.bind, Pure.pure, Except.bind, Except.pure]
  split
  · next htrue =>
      have hne : decide (toString n ≠ "0") = true := by simp [htrue.1]
      have hst : (toString n).startsWith "0" = true :=
        (String.startsWith_string_iff (pat := "0")).2 htrue.2
      have hbool : (decide (toString n ≠ "0") && (toString n).startsWith "0") = true := by
        simp only [hne, hst]
        rfl
      rw [hlead] at hbool
      exact nomatch hbool
  · next hfalse =>
      split
      · next hbig =>
          have : (toString n).length ≤ 20 := by
            simpa [hs] using uint64_repr_length_le_20 n
          exact absurd hbig (Nat.not_lt.mpr this)
      · next _ =>
          have hlt : n.toNat < UInt64.size := UInt64.toNat_lt_size n
          simp [hlt, UInt64.ofNat_toNat]

private theorem list_forM_except_ok {α} (l : List α) (f : α → Except String PUnit)
    (h : l.forM f = .ok ⟨⟩) : ∀ a ∈ l, f a = .ok ⟨⟩ := by
  induction l with
  | nil =>
      intro a ha
      cases ha
  | cons x xs ih =>
      have hx : f x = .ok ⟨⟩ := by
        cases hx : f x with
        | error e =>
            simp [List.forM, hx, Bind.bind, Except.bind] at h
        | ok u =>
            cases u
            rfl
      have hxs : xs.forM f = .ok ⟨⟩ := by
        simp [List.forM, hx, Bind.bind, Except.bind, Pure.pure, Except.pure] at h
        exact h
      intro a ha
      cases ha with
      | head => exact hx
      | tail _ hmem => exact ih hxs a hmem

private theorem list_forM_except_ok_of {α} (l : List α) (f : α → Except String PUnit)
    (h : ∀ a ∈ l, f a = .ok ⟨⟩) : l.forM f = .ok ⟨⟩ := by
  induction l with
  | nil =>
      simp [List.forM, Pure.pure, Except.pure]
  | cons x xs ih =>
      have hx : f x = .ok ⟨⟩ := h x (.head _)
      have hxs : xs.forM f = .ok ⟨⟩ :=
        ih (fun a ha => h a (.tail _ ha))
      simp [List.forM, hx, hxs, Bind.bind, Except.bind, Pure.pure, Except.pure]

private theorem validateSemVer_ok_identifiers (version : SemVer)
    (h : validateSemVer version = .ok ()) :
    (∀ id ∈ version.prerelease.toList,
      validateSemVerIdentifier "prerelease" id false = .ok ⟨⟩) ∧
    (∀ id ∈ version.build.toList,
      validateSemVerIdentifier "build" id true = .ok ⟨⟩) := by
  have hpre : version.prerelease.toList.forM
      (fun identifier => validateSemVerIdentifier "prerelease" identifier false) =
      .ok ⟨⟩ := by
    cases hp : version.prerelease.toList.forM
        (fun identifier => validateSemVerIdentifier "prerelease" identifier false) with
    | error e =>
        simp [validateSemVer, hp, Bind.bind, Except.bind] at h
    | ok u =>
        cases u
        rfl
  have hbuild : version.build.toList.forM
      (fun identifier => validateSemVerIdentifier "build" identifier true) =
      .ok ⟨⟩ := by
    simp [validateSemVer, hpre, Bind.bind, Except.bind] at h
    exact h
  exact ⟨list_forM_except_ok _ _ hpre, list_forM_except_ok _ _ hbuild⟩

private theorem isSemVerIdentifierChar_dot :
    isSemVerIdentifierChar '.' = false := by
  simp only [isSemVerIdentifierChar, isAsciiDigit, isAsciiLetter, Bool.or_eq_false_iff]
  decide

private theorem isSemVerIdentifierChar_plus :
    isSemVerIdentifierChar '+' = false := by
  simp only [isSemVerIdentifierChar, isAsciiDigit, isAsciiLetter, Bool.or_eq_false_iff]
  decide

private theorem validateSemVerIdentifier_ok_chars
    (kind identifier : String) (numericLeadingZerosAllowed : Bool)
    (h : validateSemVerIdentifier kind identifier numericLeadingZerosAllowed = .ok ⟨⟩) :
    identifier.all isSemVerIdentifierChar = true := by
  match hempty : identifier.isEmpty with
  | true =>
      simp [validateSemVerIdentifier, hempty] at h
  | false =>
      match hall : identifier.all isSemVerIdentifierChar with
      | true => rfl
      | false => simp [validateSemVerIdentifier, hempty, hall] at h

private theorem identifier_not_mem_dot
    (kind identifier : String) (numericLeadingZerosAllowed : Bool)
    (h : validateSemVerIdentifier kind identifier numericLeadingZerosAllowed = .ok ⟨⟩) :
    '.' ∉ identifier.toList := by
  have hall := validateSemVerIdentifier_ok_chars kind identifier
    numericLeadingZerosAllowed h
  intro hmem
  have hall' : identifier.toList.all isSemVerIdentifierChar = true := by
    simpa [String.all_bool_eq] using hall
  have : isSemVerIdentifierChar '.' = true :=
    (List.all_eq_true.mp hall') _ hmem
  simp [isSemVerIdentifierChar_dot] at this

private theorem identifier_not_mem_plus
    (kind identifier : String) (numericLeadingZerosAllowed : Bool)
    (h : validateSemVerIdentifier kind identifier numericLeadingZerosAllowed = .ok ⟨⟩) :
    '+' ∉ identifier.toList := by
  have hall := validateSemVerIdentifier_ok_chars kind identifier
    numericLeadingZerosAllowed h
  intro hmem
  have hall' : identifier.toList.all isSemVerIdentifierChar = true := by
    simpa [String.all_bool_eq] using hall
  have : isSemVerIdentifierChar '+' = true :=
    (List.all_eq_true.mp hall') _ hmem
  simp [isSemVerIdentifierChar_plus] at this

private theorem span_loop_all (p : Char → Bool) (l acc : List Char)
    (h : ∀ a ∈ l, p a = true) :
    List.span.loop p l acc = (acc.reverse ++ l, []) := by
  induction l generalizing acc with
  | nil =>
      simp [List.span.loop]
  | cons a as ih =>
      have ha : p a = true := h a (.head _)
      simp [List.span.loop, ha]
      rw [ih (a :: acc) (fun x hx => h x (.tail _ hx))]
      simp [List.reverse_cons, List.append_assoc]

private theorem span_eq_self (p : Char → Bool) (l : List Char)
    (h : ∀ a ∈ l, p a = true) :
    l.span p = (l, []) := by
  unfold List.span
  simpa using span_loop_all p l [] h

private theorem span_loop_break (p : Char → Bool) (before after : List Char)
    (sep : Char) (acc : List Char)
    (hbefore : ∀ a ∈ before, p a = true) (hsep : p sep = false) :
    List.span.loop p (before ++ sep :: after) acc =
      (acc.reverse ++ before, sep :: after) := by
  induction before generalizing acc with
  | nil =>
      simp [List.span.loop, hsep]
  | cons a as ih =>
      have ha : p a = true := hbefore a (.head _)
      simp [List.cons_append, List.span.loop, ha]
      rw [ih (a :: acc) (fun x hx => hbefore x (.tail _ hx))]
      simp [List.reverse_cons, List.append_assoc]

private theorem span_break (p : Char → Bool) (before after : List Char) (sep : Char)
    (hbefore : ∀ a ∈ before, p a = true) (hsep : p sep = false) :
    (before ++ sep :: after).span p = (before, sep :: after) := by
  unfold List.span
  simpa using span_loop_break p before after sep [] hbefore hsep

private theorem splitOnce_of_not_mem (s : String) (sep : Char)
    (h : sep ∉ s.toList) :
    splitOnce s sep = (s, none) := by
  have hpred : ∀ c ∈ s.toList, (c != sep) = true := by
    intro c hc
    simp [bne_iff_ne]
    intro heq
    exact h (heq ▸ hc)
  have hspan := span_eq_self (fun c => c != sep) s.toList hpred
  simp [splitOnce, hspan, String.ofList_toList]

private theorem splitOnce_append (before after : String) (sep : Char)
    (h : sep ∉ before.toList) :
    splitOnce (before ++ String.singleton sep ++ after) sep =
      (before, some after) := by
  have hpred : ∀ c ∈ before.toList, (c != sep) = true := by
    intro c hc
    simp [bne_iff_ne]
    intro heq
    exact h (heq ▸ hc)
  have hsep : (sep != sep) = false := by simp
  have hlist :
      (before ++ String.singleton sep ++ after).toList =
        before.toList ++ sep :: after.toList := by
    simp [String.toList_append, String.toList_singleton]
  simp [splitOnce, hlist]
  have hspan :=
    span_break (fun c => c != sep) before.toList after.toList sep hpred hsep
  simp [hspan, String.ofList_toList]

private theorem repr_not_mem_char {n : Nat} {c : Char} (hc : c.isDigit = false) :
    c ∉ n.repr.toList := by
  intro hmem
  have : c.isDigit = true :=
    Nat.isDigit_of_mem_toDigits (by decide : 0 < 10) (by decide : 10 ≤ 10)
      (by simpa [Nat.toList_repr] using hmem)
  simp [hc] at this

private theorem uint64_repr_not_mem_dot (n : UInt64) :
    '.' ∉ (toString n).toList := by
  simpa [toString_uint64] using
    (repr_not_mem_char (c := '.') (n := n.toNat) (by decide))

private theorem uint64_repr_not_mem_plus (n : UInt64) :
    '+' ∉ (toString n).toList := by
  simpa [toString_uint64] using
    (repr_not_mem_char (c := '+') (n := n.toNat) (by decide))

private theorem uint64_repr_not_mem_dash (n : UInt64) :
    '-' ∉ (toString n).toList := by
  simpa [toString_uint64] using
    (repr_not_mem_char (c := '-') (n := n.toNat) (by decide))

private theorem uint64_repr_not_mem_v (n : UInt64) :
    'v' ∉ (toString n).toList := by
  simpa [toString_uint64] using
    (repr_not_mem_char (c := 'v') (n := n.toNat) (by decide))

private theorem renderSemVerCore_eq (maj min pat : UInt64) :
    s!"{maj}.{min}.{pat}" =
      toString maj ++ "." ++ toString min ++ "." ++ toString pat :=
  rfl

private theorem renderSemVerCore_intercalate (maj min pat : UInt64) :
    s!"{maj}.{min}.{pat}" =
      ".".intercalate [toString maj, toString min, toString pat] := by
  rw [renderSemVerCore_eq]
  simp only [String.intercalate_cons_cons, String.intercalate_singleton]
  simp [String.append_assoc]

private theorem core_not_mem_dot_list (maj min pat : UInt64) :
    ∀ s ∈ [toString maj, toString min, toString pat], '.' ∉ s.toList := by
  intro s hs
  have : s = toString maj ∨ s = toString min ∨ s = toString pat := by
    simpa using hs
  rcases this with h | h | h
  · rw [h]; exact uint64_repr_not_mem_dot maj
  · rw [h]; exact uint64_repr_not_mem_dot min
  · rw [h]; exact uint64_repr_not_mem_dot pat

private theorem core_toList_not_mem (maj min pat : UInt64) (c : Char)
    (hc : ∀ n : UInt64, c ∉ (toString n).toList) (hcDot : c ≠ '.') :
    c ∉ (s!"{maj}.{min}.{pat}").toList := by
  rw [renderSemVerCore_eq]
  simp [String.toList_append]
  exact ⟨hc maj, hcDot, hc min, hcDot, hc pat⟩

private theorem identifiers_intercalate_not_mem (l : List String) (c : Char)
    (hl : ∀ s ∈ l, c ∉ s.toList) (hcDot : c ≠ '.') :
    c ∉ (".".intercalate l).toList := by
  induction l with
  | nil =>
      simp [String.intercalate_nil]
  | cons x xs ih =>
      cases xs with
      | nil =>
          simpa [String.intercalate_singleton] using hl x (List.mem_cons.2 (Or.inl rfl))
      | cons y ys =>
          intro hmem
          rw [String.intercalate_cons_cons, String.toList_append,
            String.toList_append] at hmem
          simp [List.mem_append] at hmem
          rcases hmem with h | h | h
          · exact hl x (List.mem_cons.2 (Or.inl rfl)) h
          · exact hcDot (by simpa [String.toList_singleton] using h)
          · exact ih (fun s hs => hl s (List.mem_cons.2 (Or.inr hs)))
              (by
                have htl :
                    (".".intercalate (y :: ys)).toList =
                      ".".toList.intercalate ((y :: ys).map String.toList) :=
                  String.toList_intercalate
                simpa [htl] using h)

private theorem parseSemVerIdentifiers_intercalate
    (kind : String) (numericLeadingZerosAllowed : Bool) (l : List String)
    (hne : l ≠ [])
    (hval : ∀ id ∈ l,
      validateSemVerIdentifier kind id numericLeadingZerosAllowed = .ok ⟨⟩) :
    parseSemVerIdentifiers kind (".".intercalate l)
      numericLeadingZerosAllowed = .ok l.toArray := by
  have hdot : ∀ s ∈ l, '.' ∉ s.toList := fun s hs =>
    identifier_not_mem_dot kind s numericLeadingZerosAllowed (hval s hs)
  have hsplit :
      ((".".intercalate l).split '.').toList.map (fun sl => sl.copy) = l := by
    have h := String.toList_split_intercalate (c := '.') (l := l) hdot
    rw [if_neg hne] at h
    exact h
  have hempty : (".".intercalate l).isEmpty = false := by
    cases l with
    | nil => exact (hne rfl).elim
    | cons x xs =>
        have hx := hval x (List.mem_cons.2 (Or.inl rfl))
        have hxne : x.isEmpty = false := by
          match hxempty : x.isEmpty with
          | true => simp [validateSemVerIdentifier, hxempty] at hx
          | false => rfl
        cases xs with
        | nil =>
            simpa [String.intercalate_singleton] using hxne
        | cons y ys =>
            simp [String.intercalate_cons_cons, String.isEmpty]
  have hfor :
      l.forM (fun identifier =>
        validateSemVerIdentifier kind identifier numericLeadingZerosAllowed) =
        .ok ⟨⟩ :=
    list_forM_except_ok_of _ _ hval
  simp [parseSemVerIdentifiers, hempty, hsplit, hfor]

private theorem array_toList_ne_nil {α} (arr : Array α) (h : arr.isEmpty = false) :
    arr.toList ≠ [] := by
  intro he
  have hlen : arr.toList.length = 0 := by simp [he]
  have hsize : arr.size = 0 := by
    simpa [Array.length_toList] using hlen
  have hempty : arr.isEmpty = true := by
    simpa [Array.isEmpty] using hsize
  simp [h] at hempty

private theorem toString_uint64_inj {a b : UInt64} (h : toString a = toString b) :
    a = b := by
  have ha := parseUInt64NoLeadingZero_toString a
  have hb := parseUInt64NoLeadingZero_toString b
  rw [h] at ha
  exact Except.ok.inj (ha.symm.trans hb)

private theorem toString_uint64_zero : toString (0 : UInt64) = "0" := by
  simp [toString_uint64, repr_zero]

private theorem toString_uint64_one : toString (1 : UInt64) = "1" := by
  have hdig : Nat.toDigits 10 1 = ['1'] := Nat.toDigits_of_lt_base (by decide)
  simp [toString_uint64, Nat.repr_eq_ofList_toDigits, hdig]

private theorem startsWith_v_of_mem (s : String) (h : s.startsWith "v" = true) :
    'v' ∈ s.toList := by
  obtain ⟨rest, hrest⟩ := (String.startsWith_string_iff (pat := "v")).1 h
  have : s.toList = 'v' :: rest := by
    simpa [List.singleton_append] using hrest.symm
  simp [this]

private theorem core_not_startsWith_v (maj min pat : UInt64) :
    (s!"{maj}.{min}.{pat}").startsWith "v" = false := by
  have hv : 'v' ∉ (s!"{maj}.{min}.{pat}").toList :=
    core_toList_not_mem maj min pat 'v' uint64_repr_not_mem_v (by decide)
  cases h : (s!"{maj}.{min}.{pat}").startsWith "v" with
  | false => rfl
  | true => exact (hv (startsWith_v_of_mem _ h)).elim

private theorem append_not_startsWith_v_of_nonempty (s t : String)
    (hne : s.toList ≠ []) (hs : s.startsWith "v" = false) :
    (s ++ t).startsWith "v" = false := by
  cases h : (s ++ t).startsWith "v" with
  | false => rfl
  | true =>
      obtain ⟨rest, hrest⟩ := (String.startsWith_string_iff (pat := "v")).1 h
      have hst : (s ++ t).toList = 'v' :: rest := by
        simpa [List.singleton_append] using hrest.symm
      match hsl : s.toList with
      | [] => exact (hne hsl).elim
      | d :: ds =>
          have hd : d = 'v' := by
            have : d :: (ds ++ t.toList) = 'v' :: rest := by
              simpa [hsl, String.toList_append] using hst
            exact (List.cons.inj this).1
          have : s.startsWith "v" = true :=
            (String.startsWith_string_iff (pat := "v")).2 ⟨ds, by simp [hsl, hd]⟩
          simp [hs] at this

private theorem core_toList_ne_nil (maj min pat : UInt64) :
    (s!"{maj}.{min}.{pat}").toList ≠ [] := by
  intro he
  have hpos : (toString maj).toList ≠ [] := by
    intro hempty
    have hlen0 : (toString maj).length = 0 := by
      simpa [String.length_toList] using congrArg List.length hempty
    have hpos : 0 < (toString maj).length := by
      simpa [toString_uint64] using Nat.length_repr_pos (n := maj.toNat)
    omega
  have he' : (toString maj ++ "." ++ toString min ++ "." ++ toString pat).toList = [] := by
    simpa [renderSemVerCore_eq] using he
  simp [String.toList_append] at he'

private theorem split_core_components (maj min pat : UInt64) :
    (s!"{maj}.{min}.{pat}".split '.').toList.map (fun sl => sl.copy) =
      [toString maj, toString min, toString pat] := by
  have h := String.toList_split_intercalate (c := '.')
    (l := [toString maj, toString min, toString pat])
    (core_not_mem_dot_list maj min pat)
  rw [renderSemVerCore_intercalate]
  exact h

private theorem split_1_0_0 :
    ("1.0.0".split '.').toList.map (fun sl => sl.copy) = ["1", "0", "0"] := by
  have heq : "1.0.0" = ".".intercalate ["1", "0", "0"] := by
    simp [String.intercalate_cons_cons, String.intercalate_singleton]
  have hdot : ∀ s ∈ ["1", "0", "0"], '.' ∉ s.toList := by
    intro s hs
    have : s = "1" ∨ s = "0" ∨ s = "0" := by simpa using hs
    rcases this with h | h | h <;> simp [h]
  have h := String.toList_split_intercalate (c := '.') (l := ["1", "0", "0"]) hdot
  rw [heq]
  exact h

private theorem array_eq_empty_of_isEmpty {α} {arr : Array α}
    (h : arr.isEmpty = true) : arr = #[] := by
  have : arr.size = 0 := by simpa [Array.isEmpty] using h
  exact Array.eq_empty_of_size_eq_zero this

private theorem s2_wire_not_mem_dash : '-' ∉ s2CatalogSemVerCoreWireV1.toList := by
  simp [s2CatalogSemVerCoreWireV1]

private theorem s2_wire_not_mem_plus : '+' ∉ s2CatalogSemVerCoreWireV1.toList := by
  simp [s2CatalogSemVerCoreWireV1]

private theorem parseSemVerCoreComponents_uint64 (maj min pat : UInt64) :
    parseSemVerCoreComponents [toString maj, toString min, toString pat] =
      .ok (maj, min, pat) := by
  have hlen : [toString maj, toString min, toString pat].length = 3 := rfl
  simp [parseSemVerCoreComponents, hlen, ↓reduceDIte,
    parseUInt64NoLeadingZero_toString]

private theorem core_startsWith_v_of_eq {maj min pat : UInt64} {core : String}
    (hcore : s!"{maj}.{min}.{pat}" = core) :
    core.startsWith "v" = false := by
  rw [← hcore]
  exact core_not_startsWith_v maj min pat

private theorem core_toList_ne_nil_of_eq {maj min pat : UInt64} {core : String}
    (hcore : s!"{maj}.{min}.{pat}" = core) :
    core.toList ≠ [] := by
  rw [← hcore]
  exact core_toList_ne_nil maj min pat

private theorem core_toList_not_mem_of_eq {maj min pat : UInt64} {core : String}
    {c : Char}
    (hcore : s!"{maj}.{min}.{pat}" = core)
    (hc : ∀ n : UInt64, c ∉ (toString n).toList) (hcDot : c ≠ '.') :
    c ∉ core.toList := by
  rw [← hcore]
  exact core_toList_not_mem maj min pat c hc hcDot

private theorem split_core_components_of_eq {maj min pat : UInt64} {core : String}
    (hcore : s!"{maj}.{min}.{pat}" = core) :
    (core.split '.').toList.map (fun sl => sl.copy) =
      [toString maj, toString min, toString pat] := by
  rw [← hcore]
  exact split_core_components maj min pat

private theorem plus_not_mem_dash_string : '+' ∉ "-".toList := by decide

private theorem dash_eq_singleton : "-" = String.singleton '-' := rfl

private theorem plus_eq_singleton : "+" = String.singleton '+' := rfl

private theorem parseSemVerIdentifiers_of_array
    (kind : String) (numericLeadingZerosAllowed : Bool) (arr : Array String)
    (hne : arr.isEmpty = false)
    (hval : ∀ id ∈ arr.toList,
      validateSemVerIdentifier kind id numericLeadingZerosAllowed = .ok ⟨⟩) :
    parseSemVerIdentifiers kind (String.intercalate "." arr.toList)
      numericLeadingZerosAllowed = .ok arr := by
  have h := parseSemVerIdentifiers_intercalate kind numericLeadingZerosAllowed
    arr.toList (array_toList_ne_nil arr hne) hval
  rw [Array.toArray_toList] at h
  exact h

private theorem parseSemVerGeneral_core (maj min pat : UInt64) :
    parseSemVerGeneral (s!"{maj}.{min}.{pat}") =
      .ok { major := maj, minor := min, patch := pat } := by
  generalize hcore : s!"{maj}.{min}.{pat}" = core
  have hnotv : core.startsWith "v" = false :=
    core_startsWith_v_of_eq hcore
  have hplus : splitOnce core '+' = (core, none) :=
    splitOnce_of_not_mem core '+'
      (core_toList_not_mem_of_eq hcore uint64_repr_not_mem_plus (by decide))
  have hdash : splitOnce core '-' = (core, none) :=
    splitOnce_of_not_mem core '-'
      (core_toList_not_mem_of_eq hcore uint64_repr_not_mem_dash (by decide))
  have hsplit : (core.split '.').toList.map (fun sl => sl.copy) =
      [toString maj, toString min, toString pat] :=
    split_core_components_of_eq hcore
  unfold parseSemVerGeneral
  cases hstarts : core.startsWith "v" with
  | true =>
      simp [hstarts] at hnotv
  | false =>
      simp [hstarts]
      rw [hplus]
      simp [parseSemVerOptionalIdentifiers]
      rw [hdash]
      simp [parseSemVerOptionalIdentifiers, hsplit, parseSemVerCoreComponents_uint64]

private theorem parseSemVerGeneral_pre
    (maj min pat : UInt64) (pre : Array String)
    (hne : pre.isEmpty = false)
    (hval : ∀ id ∈ pre.toList,
      validateSemVerIdentifier "prerelease" id false = .ok ⟨⟩) :
    parseSemVerGeneral
        (s!"{maj}.{min}.{pat}" ++ "-" ++ String.intercalate "." pre.toList) =
      .ok { major := maj, minor := min, patch := pat, prerelease := pre } := by
  generalize hcore : s!"{maj}.{min}.{pat}" = core
  let preS := String.intercalate "." pre.toList
  let s := core ++ "-" ++ preS
  have hcoreNe : core.toList ≠ [] := core_toList_ne_nil_of_eq hcore
  have hcoreNotV : core.startsWith "v" = false :=
    core_startsWith_v_of_eq hcore
  have hnotv : s.startsWith "v" = false := by
    have hs : s = core ++ ("-" ++ preS) := by
      simp [s, String.append_assoc]
    rw [hs]
    exact append_not_startsWith_v_of_nonempty core ("-" ++ preS) hcoreNe hcoreNotV
  have hplus : splitOnce s '+' = (s, none) := by
    refine splitOnce_of_not_mem s '+' ?_
    intro hmem
    have hsList : s.toList = core.toList ++ "-".toList ++ preS.toList := by
      simp [s, String.toList_append]
    have hmem' : '+' ∈ core.toList ++ "-".toList ++ preS.toList := hsList ▸ hmem
    simp only [List.mem_append] at hmem'
    rcases hmem' with h | h
    · rcases h with hc | hd
      · exact core_toList_not_mem_of_eq hcore uint64_repr_not_mem_plus (by decide) hc
      · exact plus_not_mem_dash_string hd
    · exact identifiers_intercalate_not_mem pre.toList '+'
        (fun id hid => identifier_not_mem_plus "prerelease" id false (hval id hid))
        (by decide) h
  have hdash : splitOnce s '-' = (core, some preS) := by
    have hs' : s = core ++ String.singleton '-' ++ preS := by
      simp only [s, dash_eq_singleton]
    rw [hs']
    exact splitOnce_append core preS '-'
      (core_toList_not_mem_of_eq hcore uint64_repr_not_mem_dash (by decide))
  have hpreParse : parseSemVerIdentifiers "prerelease" preS false = .ok pre :=
    parseSemVerIdentifiers_of_array "prerelease" false pre hne hval
  have hsplit : (core.split '.').toList.map (fun sl => sl.copy) =
      [toString maj, toString min, toString pat] :=
    split_core_components_of_eq hcore
  change parseSemVerGeneral s =
    .ok { major := maj, minor := min, patch := pat, prerelease := pre }
  unfold parseSemVerGeneral
  cases hstarts : s.startsWith "v" with
  | true =>
      simp [hstarts] at hnotv
  | false =>
      simp [hstarts]
      rw [hplus]
      simp [parseSemVerOptionalIdentifiers]
      rw [hdash]
      simp [parseSemVerOptionalIdentifiers, hpreParse, hsplit,
        parseSemVerCoreComponents_uint64]

private theorem parseSemVerGeneral_build
    (maj min pat : UInt64) (build : Array String)
    (hne : build.isEmpty = false)
    (hval : ∀ id ∈ build.toList,
      validateSemVerIdentifier "build" id true = .ok ⟨⟩) :
    parseSemVerGeneral
        (s!"{maj}.{min}.{pat}" ++ "+" ++ String.intercalate "." build.toList) =
      .ok { major := maj, minor := min, patch := pat, build := build } := by
  generalize hcore : s!"{maj}.{min}.{pat}" = core
  let buildS := String.intercalate "." build.toList
  let s := core ++ "+" ++ buildS
  have hcoreNe : core.toList ≠ [] := core_toList_ne_nil_of_eq hcore
  have hcoreNotV : core.startsWith "v" = false :=
    core_startsWith_v_of_eq hcore
  have hnotv : s.startsWith "v" = false := by
    have hs : s = core ++ ("+" ++ buildS) := by
      simp [s, String.append_assoc]
    rw [hs]
    exact append_not_startsWith_v_of_nonempty core ("+" ++ buildS) hcoreNe hcoreNotV
  have hplus : splitOnce s '+' = (core, some buildS) := by
    have hs' : s = core ++ String.singleton '+' ++ buildS := by
      simp only [s, plus_eq_singleton]
    rw [hs']
    exact splitOnce_append core buildS '+'
      (core_toList_not_mem_of_eq hcore uint64_repr_not_mem_plus (by decide))
  have hdash : splitOnce core '-' = (core, none) :=
    splitOnce_of_not_mem core '-'
      (core_toList_not_mem_of_eq hcore uint64_repr_not_mem_dash (by decide))
  have hbuildParse : parseSemVerIdentifiers "build" buildS true = .ok build :=
    parseSemVerIdentifiers_of_array "build" true build hne hval
  have hsplit : (core.split '.').toList.map (fun sl => sl.copy) =
      [toString maj, toString min, toString pat] :=
    split_core_components_of_eq hcore
  change parseSemVerGeneral s =
    .ok { major := maj, minor := min, patch := pat, build := build }
  unfold parseSemVerGeneral
  cases hstarts : s.startsWith "v" with
  | true =>
      simp [hstarts] at hnotv
  | false =>
      simp [hstarts]
      rw [hplus]
      simp [parseSemVerOptionalIdentifiers, hbuildParse]
      rw [hdash]
      simp [parseSemVerOptionalIdentifiers, hsplit, parseSemVerCoreComponents_uint64]

private theorem parseSemVerGeneral_pre_build
    (maj min pat : UInt64) (pre build : Array String)
    (hpreNe : pre.isEmpty = false) (hbuildNe : build.isEmpty = false)
    (hpreVal : ∀ id ∈ pre.toList,
      validateSemVerIdentifier "prerelease" id false = .ok ⟨⟩)
    (hbuildVal : ∀ id ∈ build.toList,
      validateSemVerIdentifier "build" id true = .ok ⟨⟩) :
    parseSemVerGeneral
        (s!"{maj}.{min}.{pat}" ++ "-" ++ String.intercalate "." pre.toList ++
          "+" ++ String.intercalate "." build.toList) =
      .ok { major := maj, minor := min, patch := pat,
            prerelease := pre, build := build } := by
  generalize hcore : s!"{maj}.{min}.{pat}" = core
  let preS := String.intercalate "." pre.toList
  let buildS := String.intercalate "." build.toList
  let withPre := core ++ "-" ++ preS
  let s := withPre ++ "+" ++ buildS
  have hcoreNe : core.toList ≠ [] := core_toList_ne_nil_of_eq hcore
  have hcoreNotV : core.startsWith "v" = false :=
    core_startsWith_v_of_eq hcore
  have hwithEq : withPre = core ++ ("-" ++ preS) := by
    simp [withPre, String.append_assoc]
  have hwithNotV : withPre.startsWith "v" = false := by
    rw [hwithEq]
    exact append_not_startsWith_v_of_nonempty core ("-" ++ preS) hcoreNe hcoreNotV
  have hwithNe : withPre.toList ≠ [] := by
    rw [hwithEq, String.toList_append]
    intro he
    match hcl : core.toList with
    | [] => exact hcoreNe hcl
    | _ :: _ =>
        simp [hcl] at he
  have hnotv : s.startsWith "v" = false := by
    have hs : s = withPre ++ ("+" ++ buildS) := by
      simp [s, String.append_assoc]
    rw [hs]
    exact append_not_startsWith_v_of_nonempty withPre ("+" ++ buildS)
      hwithNe hwithNotV
  have hplus : splitOnce s '+' = (withPre, some buildS) := by
    have hs' : s = withPre ++ String.singleton '+' ++ buildS := by
      simp only [s, plus_eq_singleton]
    rw [hs']
    refine splitOnce_append withPre buildS '+' ?_
    intro hmem
    have hsList : withPre.toList = core.toList ++ "-".toList ++ preS.toList := by
      simp [withPre, String.toList_append]
    have hmem' : '+' ∈ core.toList ++ "-".toList ++ preS.toList := hsList ▸ hmem
    simp only [List.mem_append] at hmem'
    rcases hmem' with h | h
    · rcases h with hc | hd
      · exact core_toList_not_mem_of_eq hcore uint64_repr_not_mem_plus (by decide) hc
      · exact plus_not_mem_dash_string hd
    · exact identifiers_intercalate_not_mem pre.toList '+'
        (fun id hid => identifier_not_mem_plus "prerelease" id false
          (hpreVal id hid)) (by decide) h
  have hdash : splitOnce withPre '-' = (core, some preS) := by
    have hs' : withPre = core ++ String.singleton '-' ++ preS := by
      simp only [withPre, dash_eq_singleton]
    rw [hs']
    exact splitOnce_append core preS '-'
      (core_toList_not_mem_of_eq hcore uint64_repr_not_mem_dash (by decide))
  have hpreParse : parseSemVerIdentifiers "prerelease" preS false = .ok pre :=
    parseSemVerIdentifiers_of_array "prerelease" false pre hpreNe hpreVal
  have hbuildParse : parseSemVerIdentifiers "build" buildS true = .ok build :=
    parseSemVerIdentifiers_of_array "build" true build hbuildNe hbuildVal
  have hsplit : (core.split '.').toList.map (fun sl => sl.copy) =
      [toString maj, toString min, toString pat] :=
    split_core_components_of_eq hcore
  change parseSemVerGeneral s =
    .ok { major := maj, minor := min, patch := pat,
          prerelease := pre, build := build }
  unfold parseSemVerGeneral
  cases hstarts : s.startsWith "v" with
  | true =>
      simp [hstarts] at hnotv
  | false =>
      simp [hstarts]
      rw [hplus]
      simp [parseSemVerOptionalIdentifiers, hbuildParse]
      rw [hdash]
      simp [parseSemVerOptionalIdentifiers, hpreParse, hsplit,
        parseSemVerCoreComponents_uint64]

private theorem render_eq_s2_core (version : SemVer)
    (hpre : version.prerelease.isEmpty = true)
    (hbuild : version.build.isEmpty = true)
    (hcore : s!"{version.major}.{version.minor}.{version.patch}" = "1.0.0") :
    version = s2CatalogSemVerCoreV1 := by
  have hsplit :
      [toString version.major, toString version.minor, toString version.patch] =
        ["1", "0", "0"] := by
    have h := split_core_components version.major version.minor version.patch
    rw [hcore] at h
    exact h.symm.trans split_1_0_0
  have hmaj : version.major = 1 :=
    toString_uint64_inj (by
      have := congrArg (fun l : List String => l.head?) hsplit
      have : toString version.major = "1" := by
        simpa using Option.some.inj this
      simpa [toString_uint64_one] using this)
  have hmin : version.minor = 0 :=
    toString_uint64_inj (by
      have := congrArg (fun l : List String => l[1]?) hsplit
      have : toString version.minor = "0" := by
        simpa using Option.some.inj this
      simpa [toString_uint64_zero] using this)
  have hpat : version.patch = 0 :=
    toString_uint64_inj (by
      have := congrArg (fun l : List String => l[2]?) hsplit
      have : toString version.patch = "0" := by
        simpa using Option.some.inj this
      simpa [toString_uint64_zero] using this)
  have hpre' := array_eq_empty_of_isEmpty hpre
  have hbuild' := array_eq_empty_of_isEmpty hbuild
  cases version
  subst hmaj
  subst hmin
  subst hpat
  subst hpre'
  subst hbuild'
  rfl

private theorem render_ne_s2_of_mem_plus (s : String)
    (hin : '+' ∈ s.toList) :
    (s == s2CatalogSemVerCoreWireV1) = false := by
  cases hbeq : (s == s2CatalogSemVerCoreWireV1) with
  | false => rfl
  | true =>
      have heq : s = s2CatalogSemVerCoreWireV1 :=
        (beq_iff_eq (a := s) (b := s2CatalogSemVerCoreWireV1)).1 hbeq
      exact (s2_wire_not_mem_plus (heq ▸ hin)).elim

private theorem render_ne_s2_of_mem_dash (s : String)
    (hin : '-' ∈ s.toList) :
    (s == s2CatalogSemVerCoreWireV1) = false := by
  cases hbeq : (s == s2CatalogSemVerCoreWireV1) with
  | false => rfl
  | true =>
      have heq : s = s2CatalogSemVerCoreWireV1 :=
        (beq_iff_eq (a := s) (b := s2CatalogSemVerCoreWireV1)).1 hbeq
      exact (s2_wire_not_mem_dash (heq ▸ hin)).elim

theorem parseSemVer_renderSemVerUnchecked (version : SemVer)
    (hval : validateSemVer version = .ok ()) :
    parseSemVer (renderSemVerUnchecked version) = .ok version := by
  obtain ⟨hpreVal, hbuildVal⟩ := validateSemVer_ok_identifiers version hval
  match hpreE : version.prerelease.isEmpty, hbuildE : version.build.isEmpty with
  | false, false =>
      have hr : renderSemVerUnchecked version =
          s!"{version.major}.{version.minor}.{version.patch}" ++ "-" ++
            String.intercalate "." version.prerelease.toList ++ "+" ++
            String.intercalate "." version.build.toList := by
        simp [renderSemVerUnchecked, hpreE, hbuildE]
      have hne :
          (renderSemVerUnchecked version == s2CatalogSemVerCoreWireV1) = false :=
        render_ne_s2_of_mem_dash _
          (by simp [hr, String.toList_append])
      simp [parseSemVer, hne]
      rw [hr]
      exact parseSemVerGeneral_pre_build version.major version.minor version.patch
        version.prerelease version.build hpreE hbuildE hpreVal hbuildVal
  | false, true =>
      have hr : renderSemVerUnchecked version =
          s!"{version.major}.{version.minor}.{version.patch}" ++ "-" ++
            String.intercalate "." version.prerelease.toList := by
        simp [renderSemVerUnchecked, hpreE, hbuildE]
      have hne :
          (renderSemVerUnchecked version == s2CatalogSemVerCoreWireV1) = false :=
        render_ne_s2_of_mem_dash _
          (by simp [hr, String.toList_append])
      simp [parseSemVer, hne]
      rw [hr]
      cases version
      have hbuild' := array_eq_empty_of_isEmpty hbuildE
      subst hbuild'
      exact parseSemVerGeneral_pre _ _ _ _ hpreE hpreVal
  | true, false =>
      have hr : renderSemVerUnchecked version =
          s!"{version.major}.{version.minor}.{version.patch}" ++ "+" ++
            String.intercalate "." version.build.toList := by
        simp [renderSemVerUnchecked, hpreE, hbuildE]
      have hne :
          (renderSemVerUnchecked version == s2CatalogSemVerCoreWireV1) = false :=
        render_ne_s2_of_mem_plus _
          (by simp [hr, String.toList_append])
      simp [parseSemVer, hne]
      rw [hr]
      cases version
      have hpre' := array_eq_empty_of_isEmpty hpreE
      subst hpre'
      exact parseSemVerGeneral_build _ _ _ _ hbuildE hbuildVal
  | true, true =>
      have hr : renderSemVerUnchecked version =
          s!"{version.major}.{version.minor}.{version.patch}" := by
        simp [renderSemVerUnchecked, hpreE, hbuildE]
      by_cases h1 : s!"{version.major}.{version.minor}.{version.patch}" = "1.0.0"
      · have hv : version = s2CatalogSemVerCoreV1 :=
          render_eq_s2_core version hpreE hbuildE h1
        rw [hr, h1, hv]
        exact parseSemVer_1_0_0
      · have hne :
            (renderSemVerUnchecked version == s2CatalogSemVerCoreWireV1) = false := by
          cases hbeq : (renderSemVerUnchecked version == s2CatalogSemVerCoreWireV1) with
          | false => rfl
          | true =>
              have heq : renderSemVerUnchecked version = s2CatalogSemVerCoreWireV1 :=
                (beq_iff_eq (a := renderSemVerUnchecked version)
                  (b := s2CatalogSemVerCoreWireV1)).1 hbeq
              have : s!"{version.major}.{version.minor}.{version.patch}" = "1.0.0" := by
                rw [← hr, heq]
                rfl
              exact (h1 this).elim
        simp [parseSemVer, hne]
        rw [hr]
        cases version
        have hpre' := array_eq_empty_of_isEmpty hpreE
        have hbuild' := array_eq_empty_of_isEmpty hbuildE
        subst hpre' hbuild'
        exact parseSemVerGeneral_core _ _ _

theorem parseSemVer_of_renderSemVer_ok (version : SemVer) (s : String)
    (h : renderSemVer version = .ok s) :
    parseSemVer s = .ok version := by
  obtain ⟨hval, hs⟩ := renderSemVer_ok_eq version s h
  simpa [hs] using parseSemVer_renderSemVerUnchecked version hval

private def compareSemVerIdentifier (left right : String) : Ordering :=
  let leftNumeric := left.all isAsciiDigit
  let rightNumeric := right.all isAsciiDigit
  if leftNumeric && rightNumeric then
    match compare left.length right.length with
    | .eq => compare left right
    | order => order
  else if leftNumeric then
    .lt
  else if rightNumeric then
    .gt
  else
    compare left right

private def comparePrerelease : List String → List String → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | left :: leftRest, right :: rightRest =>
    match compareSemVerIdentifier left right with
    | .eq => comparePrerelease leftRest rightRest
    | order => order

/-- Compare validated SemVer precedence. Build metadata is intentionally ignored. -/
private def compareSemVerPrecedenceUnchecked (left right : SemVer) : Ordering :=
  match compare left.major right.major with
  | .lt => .lt
  | .gt => .gt
  | .eq =>
    match compare left.minor right.minor with
    | .lt => .lt
    | .gt => .gt
    | .eq =>
      match compare left.patch right.patch with
      | .lt => .lt
      | .gt => .gt
      | .eq =>
        if left.prerelease.isEmpty then
          if right.prerelease.isEmpty then .eq else .gt
        else if right.prerelease.isEmpty then
          .lt
        else
          comparePrerelease left.prerelease.toList right.prerelease.toList

/-- Compare SemVer precedence, failing closed on directly constructed invalid values. -/
def compareSemVerPrecedence (left right : SemVer) : Except String Ordering := do
  validateSemVer left
  validateSemVer right
  pure (compareSemVerPrecedenceUnchecked left right)

structure NonEmptyArray (α : Type u) where
  head : α
  tail : Array α
  deriving DecidableEq, Repr

namespace NonEmptyArray

def ofArray (values : Array α) : Except String (NonEmptyArray α) :=
  if h : 0 < values.size then
    .ok { head := values[0], tail := values.extract 1 values.size }
  else
    .error "array must contain at least one value"

def toArray (values : NonEmptyArray α) : Array α :=
  #[values.head] ++ values.tail

end NonEmptyArray

structure SchemaId where
  value : String
  deriving DecidableEq, Repr

structure EvidenceId where
  value : String
  deriving DecidableEq, Repr

structure AcceptanceProfileId where
  value : String
  deriving DecidableEq, Repr

structure NodeId where
  bytes : ByteArray
  deriving DecidableEq

instance : Repr NodeId where
  reprPrec nodeId _ :=
    (Std.Format.text "{ bytes := ").append (repr nodeId.bytes.data)
      |>.append (Std.Format.text " }")

structure ProjectRelativePath where
  value : String
  deriving DecidableEq, Repr

structure QualifiedName where
  components : NonEmptyArray String
  deriving DecidableEq, Repr

structure ContentRef where
  schema : SchemaId
  id : String
  version : SemVer
  digest : Digest
  deriving DecidableEq, Repr

structure SourceOrigin where
  sourcePath : ProjectRelativePath
  startByte : UInt64
  endByte : UInt64
  nodeId : NodeId
  deriving DecidableEq, Repr

structure UtcInstant where
  value : String
  deriving DecidableEq, Repr

private def isLowerAsciiLetter (c : Char) : Bool :=
  'a' ≤ c && c ≤ 'z'

private def isLowerAsciiAlphanumeric (c : Char) : Bool :=
  isLowerAsciiLetter c || isAsciiDigit c

private def validSeparatedRest
    (isSeparator : Char → Bool) : List Char → Bool → Bool
  | [], previousWasSeparator => !previousWasSeparator
  | c :: rest, previousWasSeparator =>
    if isLowerAsciiAlphanumeric c then
      validSeparatedRest isSeparator rest false
    else if isSeparator c && !previousWasSeparator then
      validSeparatedRest isSeparator rest true
    else
      false

private def validSeparatedId (value : String) (isSeparator : Char → Bool) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
    isLowerAsciiLetter first && validSeparatedRest isSeparator rest false

private def validSchemaSegment (value : String) : Bool :=
  validSeparatedId value (· == '-')

def validateSchemaId (schema : SchemaId) : Except String Unit := do
  let value := schema.value
  unless 1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 127 do
    throw "schema id must contain 1..127 UTF-8 bytes"
  unless value.toList.any (· == '.') do
    throw "schema id must contain at least one dot"
  unless (value.splitOn ".").all validSchemaSegment do
    throw "schema id has an invalid segment"

def parseSchemaId (value : String) : Except String SchemaId := do
  let schema := { value }
  validateSchemaId schema
  pure schema

def renderSchemaId (schema : SchemaId) : Except String String := do
  validateSchemaId schema
  pure schema.value

def validateProfileIdValue (value : String) : Except String Unit := do
  unless 1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 127 do
    throw "profile id must contain 1..127 UTF-8 bytes"
  unless validSeparatedId value (fun c => c == '-' || c == '.') do
    throw "profile id has an invalid spelling"

def validateAcceptanceProfileId (profile : AcceptanceProfileId) : Except String Unit :=
  validateProfileIdValue profile.value

def parseAcceptanceProfileId (value : String) : Except String AcceptanceProfileId := do
  let profile := { value }
  validateAcceptanceProfileId profile
  pure profile

def renderAcceptanceProfileId (profile : AcceptanceProfileId) : Except String String := do
  validateAcceptanceProfileId profile
  pure profile.value

private def isGregorianLeapYear (year : Nat) : Bool :=
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

private def daysInGregorianMonth (year month : Nat) : Nat :=
  match month with
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
  | 4 | 6 | 9 | 11 => 30
  | 2 => if isGregorianLeapYear year then 29 else 28
  | _ => 0

private def validateGregorianDate (year month day : Nat) : Except String Unit := do
  unless 1 ≤ month && month ≤ 12 do
    throw "Gregorian month is out of range"
  let maximumDay := daysInGregorianMonth year month
  unless 1 ≤ day && day ≤ maximumDay do
    throw "Gregorian day is out of range"

private def parseAsciiDecimalSlice
    (chars : List Char) (start count : Nat) : Except String Nat := do
  let slice := (chars.drop start).take count
  unless slice.length = count && slice.all isAsciiDigit do
    throw "expected fixed-width ASCII decimal digits"
  match (String.ofList slice).toNat? with
  | some value => pure value
  | none => throw "invalid fixed-width ASCII decimal digits"

def validateEvidenceId (evidence : EvidenceId) : Except String Unit := do
  let value := evidence.value
  unless value.utf8ByteSize = 16 && value.length = 16 do
    throw "evidence id must have exact EV-YYYYMMDD-NNNN width"
  let chars := value.toList
  unless value.startsWith "EV-" && chars[11]! == '-' do
    throw "evidence id must use EV-YYYYMMDD-NNNN spelling"
  let year ← parseAsciiDecimalSlice chars 3 4
  let month ← parseAsciiDecimalSlice chars 7 2
  let day ← parseAsciiDecimalSlice chars 9 2
  let _ ← parseAsciiDecimalSlice chars 12 4
  validateGregorianDate year month day

def parseEvidenceId (value : String) : Except String EvidenceId := do
  let evidence := { value }
  validateEvidenceId evidence
  pure evidence

def renderEvidenceId (evidence : EvidenceId) : Except String String := do
  validateEvidenceId evidence
  pure evidence.value

def validateUtcInstant (instant : UtcInstant) : Except String Unit := do
  let value := instant.value
  unless value.utf8ByteSize = 20 && value.length = 20 do
    throw "UTC instant must have exact YYYY-MM-DDTHH:MM:SSZ width"
  let chars := value.toList
  unless chars[4]! == '-' && chars[7]! == '-' && chars[10]! == 'T' &&
      chars[13]! == ':' && chars[16]! == ':' && chars[19]! == 'Z' do
    throw "UTC instant must use YYYY-MM-DDTHH:MM:SSZ spelling"
  let year ← parseAsciiDecimalSlice chars 0 4
  let month ← parseAsciiDecimalSlice chars 5 2
  let day ← parseAsciiDecimalSlice chars 8 2
  let hour ← parseAsciiDecimalSlice chars 11 2
  let minute ← parseAsciiDecimalSlice chars 14 2
  let second ← parseAsciiDecimalSlice chars 17 2
  validateGregorianDate year month day
  unless hour < 24 do throw "UTC hour is out of range"
  unless minute < 60 do throw "UTC minute is out of range"
  unless second < 60 do throw "UTC second is out of range"

def parseUtcInstant (value : String) : Except String UtcInstant := do
  let instant := { value }
  validateUtcInstant instant
  pure instant

def renderUtcInstant (instant : UtcInstant) : Except String String := do
  validateUtcInstant instant
  pure instant.value

def validateNodeId (nodeId : NodeId) : Except String Unit := do
  unless nodeId.bytes.size = 16 do
    throw "node id must contain exactly 16 raw bytes"

def parseNodeId (value : String) : Except String NodeId := do
  let tag := "nodeid:"
  unless value.startsWith tag do
    throw "node id must use nodeid: tag"
  unless value.length = tag.length + 32 do
    throw "node id hex must contain exactly 32 lowercase characters"
  let hex := String.ofList (value.toList.drop tag.length)
  unless hex.all isLowerHex do
    throw "node id hex must be lowercase [0-9a-f]"
  let raw ← decodeLowerHex hex.toList
  let nodeId := { bytes := ByteArray.mk raw.toArray }
  validateNodeId nodeId
  pure nodeId

def renderNodeId (nodeId : NodeId) : Except String String := do
  validateNodeId nodeId
  pure ("nodeid:" ++ encodeLowerHex nodeId.bytes)

private def hasAsciiDrivePrefix (value : String) : Bool :=
  match value.toList with
  | first :: ':' :: '/' :: _ => isAsciiLetter first
  | _ => false

/-- Validate a lexical, NFC project-relative path without consulting a filesystem. -/
def validateProjectRelativePath (path : ProjectRelativePath) : Except String Unit := do
  let value := path.value
  unless 1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 1024 do
    throw "project-relative path must contain 1..1024 UTF-8 bytes"
  ProofForgeV2.Core.Unicode.requireNfc value
  if value.startsWith "/" || hasAsciiDrivePrefix value then
    throw "project-relative path must not be absolute"
  if value.toList.any (· == '\\') then
    throw "project-relative path must use forward slashes"
  if value.toList.any ProofForgeV2.Core.Unicode.isUnicodeCc then
    throw "project-relative path must not contain a Cc code point"
  let segments := value.splitOn "/"
  if segments.any (fun segment => segment.isEmpty || segment == "." || segment == "..") then
    throw "project-relative path contains a forbidden segment"

def parseProjectRelativePath (value : String) : Except String ProjectRelativePath := do
  let path := { value }
  validateProjectRelativePath path
  pure path

def renderProjectRelativePath (path : ProjectRelativePath) : Except String String := do
  validateProjectRelativePath path
  pure path.value

/-- SPEC-COMMON-001 exact identifier component rule (Unicode 17 NFC, UTF-8
    length 1..240, not exact `_`, Lean.isIdFirst + Lean.isIdRest). Shared truth
    for QualifiedName components and SemanticProgramV1 declaration / field /
    parameter / invariant names (SPEC-SEM-WIRE-001 §6). Keyword reservation is
    owned by the producing syntax surface; this validator does not copy ambient
    parser keywords. -/
def validateIdentifierComponent (component : String) : Except String Unit := do
  unless 1 ≤ component.utf8ByteSize && component.utf8ByteSize ≤ 240 do
    throw "identifier component must contain 1..240 UTF-8 bytes"
  ProofForgeV2.Core.Unicode.requireNfc component
  if component == "_" then
    throw "identifier component must not be anonymous"
  match component.toList with
  | [] => throw "identifier component must not be empty"
  | first :: rest =>
    unless Lean.isIdFirst first && rest.all Lean.isIdRest do
      throw "identifier component must use Lean identifier characters"

/-- QualifiedName components use the exact shared identifier component rule. -/
private def validateQualifiedNameComponent (component : String) : Except String Unit :=
  validateIdentifierComponent component

/-- List spine for QN component validation (same order/errors as the former
    Array `for` loop; certificates induct on this sole worker). -/
def validateIdentifierComponentsListV1 : List String → Except String Unit
  | [] => pure ()
  | c :: cs => do
      validateIdentifierComponent c
      validateIdentifierComponentsListV1 cs

theorem validateIdentifierComponentsListV1_ok_of_forall
    (xs : List String)
    (h : ∀ x ∈ xs, validateIdentifierComponent x = .ok ()) :
    validateIdentifierComponentsListV1 xs = .ok () := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
      have hx := h x (List.Mem.head xs)
      have hrest : ∀ y ∈ xs, validateIdentifierComponent y = .ok () :=
        fun y hy => h y (List.Mem.tail x hy)
      simp only [validateIdentifierComponentsListV1, hx, ih hrest, Bind.bind,
        Except.bind]

def validateQualifiedName (name : QualifiedName) : Except String Unit := do
  let components := name.components.toArray
  unless components.size ≤ 256 do
    throw "qualified name must contain at most 256 components"
  validateIdentifierComponentsListV1 components.toList

def parseQualifiedName (components : Array String) : Except String QualifiedName := do
  let nonempty ← NonEmptyArray.ofArray components
  let name := { components := nonempty }
  validateQualifiedName name
  pure name

def renderQualifiedNameComponents (name : QualifiedName) : Except String (Array String) := do
  validateQualifiedName name
  pure name.components.toArray

def renderQualifiedNameJcs (name : QualifiedName) : Except String String := do
  let components ← renderQualifiedNameComponents name
  renderPfJcs (.array (components.map PfJson.string))

def parseQualifiedNameJcs (input : String) : Except String QualifiedName := do
  let value ← parsePfJcs input
  match value with
  | .array values =>
    let mut components := #[]
    for value in values do
      match value with
      | .string component => components := components.push component
      | _ => throw "qualified-name wire components must be strings"
    parseQualifiedName components
  | _ => throw "qualified-name wire must be an array"

def validateContentRef (content : ContentRef) : Except String Unit := do
  validateSchemaId content.schema
  validateProfileIdValue content.id
  validateSemVer content.version
  validateDigest content.digest

def renderContentRefJcs (content : ContentRef) : Except String String := do
  validateContentRef content
  let digest ← renderDigest content.digest
  let schema ← renderSchemaId content.schema
  let version ← renderSemVer content.version
  renderPfJcs (.object #[
    ("schema", .string schema),
    ("id", .string content.id),
    ("version", .string version),
    ("digest", .string digest)
  ])

def parseContentRefJcs (input : String) : Except String ContentRef := do
  let value ← parsePfJcs input
  match value with
  | .object fields =>
    match fields.toList with
    | [("digest", .string digestValue), ("id", .string id),
        ("schema", .string schemaValue), ("version", .string versionValue)] =>
      let schema ← parseSchemaId schemaValue
      let version ← parseSemVer versionValue
      let digest ← parseDigest digestValue
      let content := { schema, id, version, digest }
      validateContentRef content
      pure content
    | _ => throw "content-ref wire must contain exactly digest,id,schema,version"
  | _ => throw "content-ref wire must be an object"

private def maxSafeJsonNat : Nat := 9007199254740991

private def uint64ToPfInt (label : String) (value : UInt64) : Except String Int := do
  let natural := value.toNat
  unless natural ≤ maxSafeJsonNat do
    throw s!"{label} exceeds the PF-JCS safe-integer range"
  pure (Int.ofNat natural)

private def pfIntToUInt64 (label : String) (value : Int) : Except String UInt64 := do
  if value < 0 then
    throw s!"{label} must be nonnegative"
  let natural := value.toNat
  unless natural ≤ maxSafeJsonNat do
    throw s!"{label} exceeds the PF-JCS safe-integer range"
  pure (UInt64.ofNat natural)

def validateSourceOrigin (origin : SourceOrigin) : Except String Unit := do
  validateProjectRelativePath origin.sourcePath
  validateNodeId origin.nodeId
  unless origin.startByte ≤ origin.endByte do
    throw "source-origin startByte must not exceed endByte"

def sourceOriginKey
    (origin : SourceOrigin) : Except String (String × UInt64 × UInt64 × ByteArray) := do
  validateSourceOrigin origin
  pure (origin.sourcePath.value, origin.startByte, origin.endByte, origin.nodeId.bytes)

def renderSourceOriginJcs (origin : SourceOrigin) : Except String String := do
  validateSourceOrigin origin
  let sourcePath ← renderProjectRelativePath origin.sourcePath
  let startByte ← uint64ToPfInt "source-origin startByte" origin.startByte
  let endByte ← uint64ToPfInt "source-origin endByte" origin.endByte
  let nodeId ← renderNodeId origin.nodeId
  renderPfJcs (.object #[
    ("sourcePath", .string sourcePath),
    ("startByte", .int startByte),
    ("endByte", .int endByte),
    ("nodeId", .string nodeId)
  ])

def parseSourceOriginJcs (input : String) : Except String SourceOrigin := do
  let value ← parsePfJcs input
  match value with
  | .object fields =>
    match fields.toList with
    | [("endByte", .int endValue), ("nodeId", .string nodeValue),
        ("sourcePath", .string pathValue), ("startByte", .int startValue)] =>
      let sourcePath ← parseProjectRelativePath pathValue
      let startByte ← pfIntToUInt64 "source-origin startByte" startValue
      let endByte ← pfIntToUInt64 "source-origin endByte" endValue
      let nodeId ← parseNodeId nodeValue
      let origin := { sourcePath, startByte, endByte, nodeId }
      validateSourceOrigin origin
      pure origin
    | _ => throw "source-origin wire must contain exactly endByte,nodeId,sourcePath,startByte"
  | _ => throw "source-origin wire must be an object"

/-- Raw SHA-256 over exact bytes. -/
def sha256Bytes (input : ByteArray) : Digest :=
  { algorithm := .sha256, bytes := ProofForgeV2.Crypto.sha256 input }

/-- Digests minted by the sole production SHA-256 implementation satisfy the
    common fixed-width invariant without evaluating their input bytes. -/
theorem validateDigest_sha256Bytes (input : ByteArray) :
    validateDigest (sha256Bytes input) = .ok () := by
  simp [validateDigest, sha256Bytes, ProofForgeV2.Crypto.sha256_size]
  rfl

/-- SHA-256 over `UTF8(domainTag) || 0x00 || payload`. -/
def domainSeparatedSha256
    (domainTag : String) (payload : ByteArray) : Except String Digest := do
  validateProfileIdValue domainTag
  let preimage := (domainTag.toUTF8.push 0).append payload
  pure (sha256Bytes preimage)

inductive DocumentStatus where
  | notStarted
  | draft
  | proposed
  | inReview
  | accepted
  | superseded
  | archived
  deriving DecidableEq, Repr, Inhabited

def parseDocumentStatus : String → Except String DocumentStatus
  | "not_started" => pure .notStarted
  | "draft" => pure .draft
  | "proposed" => pure .proposed
  | "in_review" => pure .inReview
  | "accepted" => pure .accepted
  | "superseded" => pure .superseded
  | "archived" => pure .archived
  | _ => throw "unknown document status"

def renderDocumentStatus : DocumentStatus → String
  | .notStarted => "not_started"
  | .draft => "draft"
  | .proposed => "proposed"
  | .inReview => "in_review"
  | .accepted => "accepted"
  | .superseded => "superseded"
  | .archived => "archived"

def documentStatusRank : DocumentStatus → Nat
  | .notStarted => 0
  | .draft => 1
  | .proposed => 2
  | .inReview => 3
  | .accepted => 4
  | .superseded => 5
  | .archived => 6

inductive ArtifactDeployability where
  | deployable
  | verifiableWorkload
  | intermediateOnly
  | nonDeployable
  deriving DecidableEq, Repr, Inhabited

def parseArtifactDeployability : String → Except String ArtifactDeployability
  | "deployable" => pure .deployable
  | "verifiable-workload" => pure .verifiableWorkload
  | "intermediate-only" => pure .intermediateOnly
  | "non-deployable" => pure .nonDeployable
  | _ => throw "unknown artifact deployability"

def renderArtifactDeployability : ArtifactDeployability → String
  | .deployable => "deployable"
  | .verifiableWorkload => "verifiable-workload"
  | .intermediateOnly => "intermediate-only"
  | .nonDeployable => "non-deployable"

def artifactDeployabilityRank : ArtifactDeployability → Nat
  | .deployable => 0
  | .verifiableWorkload => 1
  | .intermediateOnly => 2
  | .nonDeployable => 3

inductive ResourceStage where
  | frontend
  | compilerCore
  | externalTool
  | artifactOutput
  deriving DecidableEq, Repr

inductive MemoryMetric where
  | darwinPhysFootprintAggregate
  | linuxProcRssAggregate
  | linuxCgroupMemoryCurrent
  | jobObjectCommitAggregate
  deriving DecidableEq, Repr

structure ResourceProfileV1 where
  schema : SchemaId
  profileId : SchemaId
  stage : ResourceStage
  maxWallMillis : UInt64
  maxAggregateMemoryBytes : UInt64
  memoryMetric : MemoryMetric
  maxProcesses : UInt32
  maxProtocolBytes : UInt64
  maxStderrBytes : UInt64
  maxPublishedBytes : UInt64
  deriving DecidableEq, Repr

def resourceProfileSchema : SchemaId :=
  { value := "proof-forge.resource-profile.v1" }

def hardFrontendProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.frontend.v1" }
    stage := .frontend
    maxWallMillis := 10000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

/-- Linux development observation uses sampled aggregate `/proc` RSS. This is
    neither cgroup accounting nor a containment claim. -/
def hardLinuxObservedFrontendProfile : ResourceProfileV1 :=
  { hardFrontendProfile with
    profileId := { value := "proof-forge.resource.frontend-linux-observed.v1" }
    memoryMetric := .linuxProcRssAggregate }

/-- Hard frontend profile matching the native development supervisor on this
    supported host. Unsupported hosts retain the canonical profile and are
    rejected by the supervisor boundary. -/
def hardFrontendProfileForHost : ResourceProfileV1 :=
  if (System.Platform.target.splitOn "-").contains "linux" then
    hardLinuxObservedFrontendProfile
  else
    hardFrontendProfile

def hardCoreProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.core.v1" }
    stage := .compilerCore
    maxWallMillis := 30000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

def hardToolProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.tool.v1" }
    stage := .externalTool
    maxWallMillis := 600000
    maxAggregateMemoryBytes := 4 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 8
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

def hardOutputProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.output.v1" }
    stage := .artifactOutput
    maxWallMillis := 60000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 256 * 1024 * 1024 }

/-- Compatibility names retained for the earlier focused Common acceptance. -/
def frontendProfile : ResourceProfileV1 := hardFrontendProfile
def coreProfile : ResourceProfileV1 := hardCoreProfile

def parseResourceStage : String → Except String ResourceStage
  | "frontend" => pure .frontend
  | "compilerCore" => pure .compilerCore
  | "externalTool" => pure .externalTool
  | "artifactOutput" => pure .artifactOutput
  | _ => throw "unknown resource stage"

def renderResourceStage : ResourceStage → String
  | .frontend => "frontend"
  | .compilerCore => "compilerCore"
  | .externalTool => "externalTool"
  | .artifactOutput => "artifactOutput"

def parseMemoryMetric : String → Except String MemoryMetric
  | "darwinPhysFootprintAggregate" => pure .darwinPhysFootprintAggregate
  | "linuxProcRssAggregate" => pure .linuxProcRssAggregate
  | "linuxCgroupMemoryCurrent" => pure .linuxCgroupMemoryCurrent
  | "jobObjectCommitAggregate" => pure .jobObjectCommitAggregate
  | _ => throw "unknown resource memory metric"

def renderMemoryMetric : MemoryMetric → String
  | .darwinPhysFootprintAggregate => "darwinPhysFootprintAggregate"
  | .linuxProcRssAggregate => "linuxProcRssAggregate"
  | .linuxCgroupMemoryCurrent => "linuxCgroupMemoryCurrent"
  | .jobObjectCommitAggregate => "jobObjectCommitAggregate"

private def ensurePositiveUInt64 (label : String) (value : UInt64) : Except String Unit := do
  unless 0 < value do throw s!"{label} must be positive"

private def ensurePositiveUInt32 (label : String) (value : UInt32) : Except String Unit := do
  unless 0 < value do throw s!"{label} must be positive"

/-- Validate a closed ResourceProfileV1 value, including its PF-JCS integer domain. -/
def validateResourceProfileV1 (profile : ResourceProfileV1) : Except String Unit := do
  validateSchemaId profile.schema
  unless profile.schema == resourceProfileSchema do
    throw "resource profile schema mismatch"
  validateProfileIdValue profile.profileId.value
  ensurePositiveUInt64 "maxWallMillis" profile.maxWallMillis
  ensurePositiveUInt64 "maxAggregateMemoryBytes" profile.maxAggregateMemoryBytes
  ensurePositiveUInt32 "maxProcesses" profile.maxProcesses
  ensurePositiveUInt64 "maxProtocolBytes" profile.maxProtocolBytes
  ensurePositiveUInt64 "maxStderrBytes" profile.maxStderrBytes
  let _ ← uint64ToPfInt "maxWallMillis" profile.maxWallMillis
  let _ ← uint64ToPfInt "maxAggregateMemoryBytes" profile.maxAggregateMemoryBytes
  let _ ← uint64ToPfInt "maxProtocolBytes" profile.maxProtocolBytes
  let _ ← uint64ToPfInt "maxStderrBytes" profile.maxStderrBytes
  let _ ← uint64ToPfInt "maxPublishedBytes" profile.maxPublishedBytes

private def validateLowerUInt64
    (label : String) (hard effective : UInt64) : Except String Unit := do
  if hard == 0 then
    unless effective == 0 do throw s!"{label} must remain zero"
  else
    unless 0 < effective && effective ≤ hard do
      throw s!"{label} must be positive and not exceed its hard maximum"

private def validateLowerUInt32
    (label : String) (hard effective : UInt32) : Except String Unit := do
  if hard == 0 then
    unless effective == 0 do throw s!"{label} must remain zero"
  else
    unless 0 < effective && effective ≤ hard do
      throw s!"{label} must be positive and not exceed its hard maximum"

/-- Effective resource budgets may only lower a fixed hard-profile identity. -/
def validateLowerOnlyResourceProfile
    (hard effective : ResourceProfileV1) : Except String Unit := do
  validateResourceProfileV1 hard
  validateResourceProfileV1 effective
  unless effective.schema == hard.schema do throw "resource profile schema mismatch"
  unless effective.profileId == hard.profileId do throw "resource profile id mismatch"
  unless effective.stage == hard.stage do throw "resource profile stage mismatch"
  unless effective.memoryMetric == hard.memoryMetric do throw "resource memory metric mismatch"
  validateLowerUInt64 "maxWallMillis" hard.maxWallMillis effective.maxWallMillis
  validateLowerUInt64 "maxAggregateMemoryBytes"
    hard.maxAggregateMemoryBytes effective.maxAggregateMemoryBytes
  validateLowerUInt32 "maxProcesses" hard.maxProcesses effective.maxProcesses
  validateLowerUInt64 "maxProtocolBytes" hard.maxProtocolBytes effective.maxProtocolBytes
  validateLowerUInt64 "maxStderrBytes" hard.maxStderrBytes effective.maxStderrBytes
  validateLowerUInt64 "maxPublishedBytes" hard.maxPublishedBytes effective.maxPublishedBytes

/-- Historical name retained as a strict lower-only compatibility alias. -/
def validateNotAboveHardMax (hard effective : ResourceProfileV1) : Except String Unit :=
  validateLowerOnlyResourceProfile hard effective

private def uint32ToPfInt (value : UInt32) : Int :=
  Int.ofNat value.toNat

private def pfIntToUInt32 (label : String) (value : Int) : Except String UInt32 := do
  if value < 0 then throw s!"{label} must be nonnegative"
  let natural := value.toNat
  unless natural ≤ 4294967295 do throw s!"{label} exceeds UInt32"
  pure (UInt32.ofNat natural)

def renderResourceProfileJcs (profile : ResourceProfileV1) : Except String String := do
  validateResourceProfileV1 profile
  let maxWallMillis ← uint64ToPfInt "maxWallMillis" profile.maxWallMillis
  let maxAggregateMemoryBytes ←
    uint64ToPfInt "maxAggregateMemoryBytes" profile.maxAggregateMemoryBytes
  let maxProtocolBytes ← uint64ToPfInt "maxProtocolBytes" profile.maxProtocolBytes
  let maxStderrBytes ← uint64ToPfInt "maxStderrBytes" profile.maxStderrBytes
  let maxPublishedBytes ← uint64ToPfInt "maxPublishedBytes" profile.maxPublishedBytes
  renderPfJcs (.object #[
    ("schema", .string profile.schema.value),
    ("profileId", .string profile.profileId.value),
    ("stage", .string (renderResourceStage profile.stage)),
    ("maxWallMillis", .int maxWallMillis),
    ("maxAggregateMemoryBytes", .int maxAggregateMemoryBytes),
    ("memoryMetric", .string (renderMemoryMetric profile.memoryMetric)),
    ("maxProcesses", .int (uint32ToPfInt profile.maxProcesses)),
    ("maxProtocolBytes", .int maxProtocolBytes),
    ("maxStderrBytes", .int maxStderrBytes),
    ("maxPublishedBytes", .int maxPublishedBytes)
  ])

def parseResourceProfileJcs (input : String) : Except String ResourceProfileV1 := do
  let value ← parsePfJcs input
  match value with
  | .object fields =>
    match fields.toList with
    | [("maxAggregateMemoryBytes", .int memoryValue),
        ("maxProcesses", .int processesValue),
        ("maxProtocolBytes", .int protocolValue),
        ("maxPublishedBytes", .int publishedValue),
        ("maxStderrBytes", .int stderrValue),
        ("maxWallMillis", .int wallValue),
        ("memoryMetric", .string metricValue),
        ("profileId", .string profileIdValue),
        ("schema", .string schemaValue),
        ("stage", .string stageValue)] =>
      let schema ← parseSchemaId schemaValue
      validateProfileIdValue profileIdValue
      let profileId : SchemaId := { value := profileIdValue }
      let stage ← parseResourceStage stageValue
      let maxWallMillis ← pfIntToUInt64 "maxWallMillis" wallValue
      let maxAggregateMemoryBytes ←
        pfIntToUInt64 "maxAggregateMemoryBytes" memoryValue
      let memoryMetric ← parseMemoryMetric metricValue
      let maxProcesses ← pfIntToUInt32 "maxProcesses" processesValue
      let maxProtocolBytes ← pfIntToUInt64 "maxProtocolBytes" protocolValue
      let maxStderrBytes ← pfIntToUInt64 "maxStderrBytes" stderrValue
      let maxPublishedBytes ← pfIntToUInt64 "maxPublishedBytes" publishedValue
      let profile :=
        { schema, profileId, stage, maxWallMillis, maxAggregateMemoryBytes,
          memoryMetric, maxProcesses, maxProtocolBytes, maxStderrBytes,
          maxPublishedBytes }
      validateResourceProfileV1 profile
      pure profile
    | _ => throw "resource-profile wire must contain exactly its ten closed fields"
  | _ => throw "resource-profile wire must be an object"

def resourceProfileDigest (profile : ResourceProfileV1) : Except String Digest := do
  let canonical ← renderResourceProfileJcs profile
  domainSeparatedSha256 resourceProfileSchema.value canonical.toUTF8

end ProofForgeV2.Core.Common
