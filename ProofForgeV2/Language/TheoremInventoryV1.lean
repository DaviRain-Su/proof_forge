/-
  ProofForgeV2.Language.TheoremInventoryV1 — same-file adjacent theorem inventory
  for inline proof programs (engineering; not formal kernel/defeq closure).

  Scope:
    * Accept ordinary `theorem QN : Program.Proof.Inv := by …` commands that are
      immediately adjacent after a program, in proof source order
    * When any proof exists on the inventory path: every invariant has at least
      one proof kind and bindings exactly follow `(invariant, kind)` source order
    * Syntax-kind recursive allowlist for a finite tactic surface
      (rfl/intro/constructor/exact/apply/simp-only/rw/cases and structural glue)
    * Reject lemma/def/axiom/modifiers/universe params/binders/non-by bodies and
      any non-allowlisted tactic kind (sorry/admit/native_decide/run_tac/meta/IO
      escape fail closed by kind, not string denylist)

  Out of scope: kernel checking, Environment defeq, Semantic/Compiler/CLI wiring,
  ambient proof-bundle join (INV-1), formal TST-PROOF-*.
-/
import Lean
import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Language.TheoremInventoryV1

open Lean
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

/-- Lean namespace containing the generated Prop alias for a proof kind. -/
def proofAliasNamespaceV1 : ProofKindV1 → String
  | .holds => "Proof"
  | .preserving => "ProofPreserving"

/-- One accepted adjacent theorem binding (source-order). -/
structure InlineTheoremBindingV1 where
  theoremComponents : Array String
  invariantName : String
  kind : ProofKindV1
  typeComponents : Array String
  deriving BEq, Repr, Inhabited

/-- Expected theorem obligation derived from a program's proof items. -/
structure ExpectedTheoremV1 where
  theoremComponents : Array String
  invariantName : String
  kind : ProofKindV1
  typeComponents : Array String
  deriving BEq, Repr, Inhabited

/-- Opaque inventory. Sole mint is `mintTheoremInventoryV1`. -/
structure TheoremInventoryV1 where
  private mk ::
  private bindings_ : Array InlineTheoremBindingV1
  deriving Inhabited

/-- Multi-program snapshot from one inventory-aware parse. Sole mint is
    `mintProgramTheoremSnapshotV1`. -/
structure ProgramTheoremSnapshotV1 where
  private mk ::
  private units_ : Array (ValidatedSourceV1 × TheoremInventoryV1)
  deriving Inhabited

/-- Closed inventory errors (engineering Loader surface maps to invalidProgram). -/
inductive TheoremInventoryErrorV1 where
  | missingTheorem (detail : String)
  | extraTheorem (detail : String)
  | wrongTheoremName (detail : String)
  | wrongTheoremType (detail : String)
  | invalidTheoremShape (detail : String)
  | disallowedTactic (detail : String)
  | bijection (detail : String)
  | unexpectedCommand (detail : String)
  deriving BEq, Repr

private def err (e : TheoremInventoryErrorV1) : Except TheoremInventoryErrorV1 α :=
  .error e

def theoremInventoryBindingsV1 (inv : TheoremInventoryV1) :
    Array InlineTheoremBindingV1 :=
  inv.bindings_

def emptyTheoremInventoryV1 : TheoremInventoryV1 :=
  ⟨#[]⟩

def mintTheoremInventoryV1 (bindings : Array InlineTheoremBindingV1) :
    TheoremInventoryV1 :=
  ⟨bindings⟩

def programTheoremSnapshotUnitsV1 (snap : ProgramTheoremSnapshotV1) :
    Array (ValidatedSourceV1 × TheoremInventoryV1) :=
  snap.units_

def mintProgramTheoremSnapshotV1
    (units : Array (ValidatedSourceV1 × TheoremInventoryV1)) :
    ProgramTheoremSnapshotV1 :=
  ⟨units⟩

def renderTheoremInventoryErrorV1 : TheoremInventoryErrorV1 → String
  | .missingTheorem d => s!"inline theorem inventory missing theorem: {d}"
  | .extraTheorem d => s!"inline theorem inventory extra theorem: {d}"
  | .wrongTheoremName d => s!"inline theorem inventory wrong theorem name: {d}"
  | .wrongTheoremType d => s!"inline theorem inventory wrong theorem type: {d}"
  | .invalidTheoremShape d => s!"inline theorem inventory invalid theorem shape: {d}"
  | .disallowedTactic d => s!"inline theorem inventory disallowed tactic surface: {d}"
  | .bijection d => s!"inline theorem inventory bijection failure: {d}"
  | .unexpectedCommand d => s!"inline theorem inventory unexpected command: {d}"

/-- Collect pure `.str` components of a Lean `Name` root→leaf. -/
def nameComponentsV1 (name : Name) : Except TheoremInventoryErrorV1 (Array String) := do
  let rec collect (n : Name) (fuel : Nat) : Except TheoremInventoryErrorV1 (Array String) :=
    match n, fuel with
    | .anonymous, _ => pure #[]
    | _, 0 => err (.invalidTheoremShape "qualified name exceeds component limit")
    | .str pre value, fuel'+1 => do
        let preRaws ← collect pre fuel'
        pure (preRaws.push value)
    | .num _ _, _ =>
        err (.invalidTheoremShape "qualified name requires pure identifier components")
  collect name 256

private def isNullish (stx : Syntax) : Bool :=
  stx.isMissing || stx.isNone || (stx.getKind == nullKind && stx.getNumArgs == 0)

private def allNullish (args : Array Syntax) : Bool :=
  args.all isNullish

/-- Empty `declModifiers` (no doc/attrs/visibility/protected/meta/noncomputable/unsafe/partial). -/
def declModifiersEmptyV1 (stx : Syntax) : Bool :=
  stx.isOfKind ``Parser.Command.declModifiers && allNullish stx.getArgs

/-- Pure identifier chain from a term syntax node (ident only). -/
def termIdentComponentsV1 (stx : Syntax) :
    Except TheoremInventoryErrorV1 (Array String) := do
  unless stx.isIdent do
    return ← err (.invalidTheoremShape "theorem type must be a dotted identifier")
  nameComponentsV1 stx.getId

/-- Structural nodes that may appear in the allowlisted tactic tree. -/
private def isStructuralKind (kind : SyntaxNodeKind) : Bool :=
  kind == nullKind ||
  kind == ``Parser.Tactic.tacticSeq ||
  kind == ``Parser.Tactic.tacticSeq1Indented ||
  kind == ``Parser.Tactic.tacticSeqBracketed ||
  kind == ``Parser.Tactic.nestedTactic ||
  kind == ``Parser.Tactic.paren ||
  kind == ``Parser.Tactic.optConfig ||
  kind == ``Parser.Tactic.rwRuleSeq ||
  kind == ``Parser.Tactic.rwRule ||
  kind == ``Parser.Tactic.elimTarget ||
  kind == ``Parser.Tactic.location ||
  kind == ``Parser.Termination.suffix ||
  kind == `token.«[» ||
  kind == `token.«]» ||
  kind == `token.«*» ||
  kind == `token.«←» ||
  kind == `token.«<-» ||
  kind == `token.«;» ||
  kind == `token.«,» ||
  kind == `token.«(» ||
  kind == `token.«)» ||
  kind == `token.«:» ||
  kind == `token.«:=» ||
  kind == `token.by ||
  kind == `token.theorem ||
  kind == `token.rfl ||
  kind == `token.intro ||
  kind == `token.constructor ||
  kind == `token.exact ||
  kind == `token.apply ||
  kind == `token.simp ||
  kind == `token.only ||
  kind == `token.rw ||
  kind == `token.cases ||
  kind == `Lean.Parser.Term.hygienicLParen ||
  kind == `Lean.Parser.Term.hygieneInfo ||
  kind == identKind ||
  kind == strLitKind ||
  kind == numLitKind ||
  kind == charLitKind ||
  kind == nameLitKind ||
  kind == scientificLitKind

/-- Finite allowed tactic heads (kind allowlist; not a string denylist). -/
private def isAllowedTacticHead (kind : SyntaxNodeKind) : Bool :=
  kind == ``Parser.Tactic.tacticRfl ||
  kind == ``Parser.Tactic.intro ||
  kind == ``Parser.Tactic.constructor ||
  kind == ``Parser.Tactic.exact ||
  kind == ``Parser.Tactic.apply ||
  kind == ``Parser.Tactic.simp ||
  kind == ``Parser.Tactic.rwSeq ||
  kind == ``Parser.Tactic.cases

/-- `simp` is only admitted as `simp only …` (explicit only clause present). -/
private def simpHasOnlyClause (stx : Syntax) : Bool :=
  Id.run do
    -- Parser.Tactic.simp args: atom, optConfig, discharger?, only?, args?, location?
    if stx.getNumArgs < 4 then
      return false
    let onlyNode := stx.getArg 3
    if onlyNode.isOfKind nullKind then
      for child in onlyNode.getArgs do
        if child.isAtom && child.getAtomVal == "only" then
          return true
      return false
    pure (onlyNode.isAtom && onlyNode.getAtomVal == "only")

/-- `cases` must be the simple form without `using` or induction alts. -/
private def casesIsSimple (stx : Syntax) : Bool :=
  stx.getNumArgs >= 4 && isNullish (stx.getArg 2) && isNullish (stx.getArg 3)

/-- Recursive syntax-kind allowlist over a theorem proof body. -/
partial def validateAllowedTacticSurfaceV1 (stx : Syntax) :
    Except TheoremInventoryErrorV1 Unit := do
  let kind := stx.getKind
  if stx.isAtom || stx.isIdent || stx.isMissing || stx.isNone then
    return
  if isStructuralKind kind then
    for child in stx.getArgs do
      validateAllowedTacticSurfaceV1 child
    return
  if isAllowedTacticHead kind then
    if kind == ``Parser.Tactic.simp && !simpHasOnlyClause stx then
      return ← err (.disallowedTactic "simp without 'only' is not admitted")
    if kind == ``Parser.Tactic.cases && !casesIsSimple stx then
      return ← err (.disallowedTactic "cases must be the simple target form without alts")
    for child in stx.getArgs do
      validateAllowedTacticSurfaceV1 child
    return
  err (.disallowedTactic s!"syntax kind '{kind}' is outside the admitted tactic surface")

/-- Match one command as the next expected ordinary theorem. -/
def matchAdjacentTheoremCommandV1
    (expected : ExpectedTheoremV1) (command : Syntax) :
    Except TheoremInventoryErrorV1 InlineTheoremBindingV1 := do
  unless command.isOfKind ``Parser.Command.declaration do
    return ← err (.unexpectedCommand "expected ordinary theorem declaration")
  if command.getNumArgs < 2 then
    return ← err (.invalidTheoremShape "declaration node truncated")
  let modifiers := command.getArg 0
  unless declModifiersEmptyV1 modifiers do
    return ← err (.invalidTheoremShape
      "theorem modifiers (doc/attrs/visibility/protected/meta/noncomputable/unsafe/partial) are not admitted")
  let body := command.getArg 1
  unless body.isOfKind ``Parser.Command.theorem do
    let label :=
      if body.isOfKind ``Parser.Command.definition then "def"
      else if body.isOfKind ``Parser.Command.axiom then "axiom"
      else if body.isOfKind ``Parser.Command.abbrev then "abbrev"
      else if body.isOfKind ``Parser.Command.opaque then "opaque"
      else if body.isOfKind ``Parser.Command.instance then "instance"
      else if body.isOfKind ``Parser.Command.example then "example"
      else toString body.getKind
    return ← err (.invalidTheoremShape
      s!"only ordinary theorem is admitted; found '{label}'")
  -- theorem: atom, declId, declSig, declVal
  if body.getNumArgs < 4 then
    return ← err (.invalidTheoremShape "theorem node truncated")
  let declId := body.getArg 1
  unless declId.isOfKind ``Parser.Command.declId do
    return ← err (.invalidTheoremShape "theorem declId missing")
  if declId.getNumArgs < 2 then
    return ← err (.invalidTheoremShape "theorem declId truncated")
  unless isNullish (declId.getArg 1) do
    return ← err (.invalidTheoremShape "theorem universe parameters are not admitted")
  let nameStx := declId.getArg 0
  unless nameStx.isIdent do
    return ← err (.invalidTheoremShape "theorem name must be an identifier")
  let theoremComponents ← nameComponentsV1 nameStx.getId
  unless theoremComponents == expected.theoremComponents do
    return ← err (.wrongTheoremName
      s!"expected {expected.theoremComponents}, got {theoremComponents}")
  let declSig := body.getArg 2
  unless declSig.isOfKind ``Parser.Command.declSig do
    return ← err (.invalidTheoremShape "theorem signature missing")
  if declSig.getNumArgs < 2 then
    return ← err (.invalidTheoremShape "theorem signature truncated")
  unless isNullish (declSig.getArg 0) do
    return ← err (.invalidTheoremShape "theorem binders are not admitted")
  let typeSpec := declSig.getArg 1
  unless typeSpec.isOfKind ``Parser.Term.typeSpec do
    return ← err (.invalidTheoremShape "theorem type specification missing")
  if typeSpec.getNumArgs < 2 then
    return ← err (.invalidTheoremShape "theorem type specification truncated")
  let typeComponents ← termIdentComponentsV1 (typeSpec.getArg 1)
  unless typeComponents == expected.typeComponents do
    return ← err (.wrongTheoremType
      s!"expected {expected.typeComponents}, got {typeComponents}")
  let declVal := body.getArg 3
  unless declVal.isOfKind ``Parser.Command.declValSimple do
    return ← err (.invalidTheoremShape "theorem value must be `:= by …`")
  if declVal.getNumArgs < 3 then
    return ← err (.invalidTheoremShape "theorem value truncated")
  let proofTerm := declVal.getArg 1
  unless proofTerm.isOfKind ``Parser.Term.byTactic do
    return ← err (.invalidTheoremShape "theorem proof must use `by` tactic block")
  -- Termination.suffix and optional whereDecls must be empty.
  if declVal.getNumArgs >= 3 then
    let suffix := declVal.getArg 2
    unless isNullish suffix ||
        (suffix.isOfKind ``Parser.Termination.suffix && allNullish suffix.getArgs) do
      return ← err (.invalidTheoremShape "theorem termination annotations are not admitted")
  if declVal.getNumArgs >= 4 then
    unless isNullish (declVal.getArg 3) do
      return ← err (.invalidTheoremShape "theorem where-clauses are not admitted")
  if proofTerm.getNumArgs < 2 then
    return ← err (.invalidTheoremShape "by-tactic truncated")
  validateAllowedTacticSurfaceV1 (proofTerm.getArg 1)
  pure {
    theoremComponents := theoremComponents
    invariantName := expected.invariantName
    kind := expected.kind
    typeComponents := typeComponents
  }

private structure ProgramProofRowV1 where
  invariantName : String
  kind : ProofKindV1
  theoremComponents : Array String

/-- Build expected theorems from a validated program (proof source order).

    When `proofs` is empty, returns `#[]` (no adjacent theorems required).
    When any proof exists, every declared invariant must bind at least one kind;
    each `(invariant, kind)` key is unique by the source validation gate. -/
def expectedTheoremsFromProgramV1
    (programName : String) (source : ValidatedSourceV1) :
    Except TheoremInventoryErrorV1 (Array ExpectedTheoremV1) := do
  let mut invariants : Array String := #[]
  let mut proofs : Array ProgramProofRowV1 := #[]
  for item in source.program.items do
    match item with
    | .invariant d => invariants := invariants.push d.name.raw
    | .proof d =>
        let thm := (NonEmptyArray.toArray d.theorem_.components).map (·.raw)
        proofs := proofs.push {
          invariantName := d.invariant.raw
          kind := d.kind
          theoremComponents := thm
        }
    | _ => pure ()
  if proofs.isEmpty then
    return #[]
  for inv in invariants do
    unless proofs.any (fun proof => proof.invariantName == inv) do
      return ← err (.bijection s!"missing proof reference for invariant '{inv}'")
  for proof in proofs do
    unless invariants.any (· == proof.invariantName) do
      return ← err (.bijection
        s!"proof reference names unknown invariant '{proof.invariantName}'")
  let mut expected : Array ExpectedTheoremV1 := #[]
  for proof in proofs do
    expected := expected.push {
      theoremComponents := proof.theoremComponents
      invariantName := proof.invariantName
      kind := proof.kind
      typeComponents :=
        #[programName, proofAliasNamespaceV1 proof.kind, proof.invariantName]
    }
  pure expected

/-- Consume adjacent theorem commands for one program.

    `commands` is the remaining command stream starting at the first candidate
    after the program. Returns accepted bindings and the unconsumed tail.

    Requires exact coverage of `expected` (empty expected ⇒ zero theorems).
    End-of-input and non-declaration commands count as missing theorems, not as
    an "outside DSL" surprise (inventory path owns the completeness gate). -/
def consumeAdjacentTheoremsV1
    (expected : Array ExpectedTheoremV1) (commands : Array Syntax) :
    Except TheoremInventoryErrorV1
      (Array InlineTheoremBindingV1 × Array Syntax) := do
  if expected.isEmpty then
    return (#[], commands)
  let mut bindings : Array InlineTheoremBindingV1 := #[]
  let mut idx : Nat := 0
  for exp in expected do
    if idx >= commands.size then
      return ← err (.missingTheorem
        s!"need theorem for invariant '{exp.invariantName}' (no remaining commands)")
    let cmd := commands[idx]!
    if cmd.isOfKind ``Parser.Command.eoi then
      return ← err (.missingTheorem
        s!"need theorem for invariant '{exp.invariantName}' (reached end of file)")
    unless cmd.isOfKind ``Parser.Command.declaration do
      return ← err (.missingTheorem
        s!"need theorem for invariant '{exp.invariantName}', found non-theorem command")
    let binding ← matchAdjacentTheoremCommandV1 exp cmd
    bindings := bindings.push binding
    idx := idx + 1
  pure (bindings, commands.extract idx commands.size)

end ProofForgeV2.Language.TheoremInventoryV1
