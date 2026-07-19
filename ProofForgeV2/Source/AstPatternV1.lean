import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.AstPatternV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

/-- Portable source patterns (SPEC-SOURCE-WIRE-001 complete 4-tag table). -/
inductive PatternV1 where
  | wildcard
  | bind (name : SourceNameComponentV1)
  | literal (value : LiteralV1)
  | constructor (ctor : SourceQualifiedNameV1) (args : Array PatternV1)
  deriving Repr

mutual
  private def decEqPattern (a b : PatternV1) : Decidable (a = b) :=
    match a, b with
    | .wildcard, .wildcard => isTrue rfl
    | .bind x, .bind y | .literal x, .literal y =>
        match decEq x y with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .constructor x xs, .constructor y ys =>
        match decEq x y with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue h =>
            match decEqPatternArray xs ys with
            | isTrue ht => isTrue (by cases h; cases ht; rfl)
            | isFalse ht => isFalse (by intro e; injection e with _ e; exact ht e)
    | .wildcard, .bind _ | .wildcard, .literal _ | .wildcard, .constructor _ _ |
      .bind _, .wildcard | .bind _, .literal _ | .bind _, .constructor _ _ |
      .literal _, .wildcard | .literal _, .bind _ | .literal _, .constructor _ _ |
      .constructor _ _, .wildcard | .constructor _ _, .bind _ |
      .constructor _ _, .literal _ => isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqPatternArray (a b : Array PatternV1) : Decidable (a = b) :=
    match a, b with
    | ⟨xs⟩, ⟨ys⟩ =>
        match decEqPatternList xs ys with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    termination_by structural a

  private def decEqPatternList (a b : List PatternV1) : Decidable (a = b) :=
    match a, b with
    | [], [] => isTrue rfl
    | x :: xs, y :: ys =>
        match decEqPattern x y with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue h =>
            match decEqPatternList xs ys with
            | isTrue ht => isTrue (by cases h; cases ht; rfl)
            | isFalse ht => isFalse (by intro e; injection e with _ e; exact ht e)
    | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
    termination_by structural a
end

instance : DecidableEq PatternV1 := decEqPattern

end ProofForgeV2.Source.AstPatternV1
