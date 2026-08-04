import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Source.AstSpineV1

open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

mutual
  private def decEqPlace (a b : PlaceV1) : Decidable (a = b) :=
    match a, b with
    | .name x, .name y =>
        match decEq x y with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .field xb xf, .field yb yf =>
        match decEqPlace xb yb with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hb =>
            match decEq xf yf with
            | isTrue hf => isTrue (by cases hb; cases hf; rfl)
            | isFalse hf => isFalse (by intro e; injection e with _ e; exact hf e)
    | .index xb xi, .index yb yi =>
        match decEqPlace xb yb with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hb =>
            match decEqExpr xi yi with
            | isTrue hi => isTrue (by cases hb; cases hi; rfl)
            | isFalse hi => isFalse (by intro e; injection e with _ e; exact hi e)
    | .name _, .field _ _ | .name _, .index _ _
    | .field _ _, .name _ | .field _ _, .index _ _
    | .index _ _, .name _ | .index _ _, .field _ _ =>
        isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqExpr (a b : ExprV1) : Decidable (a = b) :=
    match a, b with
    | .literal x, .literal y =>
        match decEq x y with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .place x, .place y =>
        match decEqPlace x y with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .constructor cx ax, .constructor cy ay =>
        match decEq cx cy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hc =>
            match decEqExprArray ax ay with
            | isTrue ha => isTrue (by cases hc; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)
    | .unary ox ex, .unary oy ey =>
        match decEq ox oy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue ho =>
            match decEqExpr ex ey with
            | isTrue he => isTrue (by cases ho; cases he; rfl)
            | isFalse he => isFalse (by intro e; injection e with _ e; exact he e)
    | .binary ox lx rx, .binary oy ly ry =>
        match decEq ox oy with
        | isFalse h => isFalse (by intro e; injection e with e _ _; exact h e)
        | isTrue ho =>
            match decEqExpr lx ly with
            | isFalse hl => isFalse (by intro e; injection e with _ e _; exact hl e)
            | isTrue hl =>
                match decEqExpr rx ry with
                | isTrue hr => isTrue (by cases ho; cases hl; cases hr; rfl)
                | isFalse hr => isFalse (by intro e; injection e with _ _ e; exact hr e)
    | .localCall cx ax, .localCall cy ay =>
        match decEq cx cy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hc =>
            match decEqExprArray ax ay with
            | isTrue ha => isTrue (by cases hc; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)
    | .match_ sx ax, .match_ sy ay =>
        match decEqExpr sx sy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hs =>
            match decEqExprMatchArmArray ax ay with
            | isTrue ha => isTrue (by cases hs; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)
    | .externalCall cx, .externalCall cy =>
        match decEqExternalCall cx cy with
        | isTrue hc => isTrue (by cases hc; rfl)
        | isFalse hc => isFalse (by intro e; injection e with e; exact hc e)
    | .literal _, .place _ | .literal _, .constructor _ _ | .literal _, .unary _ _
    | .literal _, .binary _ _ _ | .literal _, .localCall _ _ | .literal _, .match_ _ _
    | .literal _, .externalCall _
    | .place _, .literal _ | .place _, .constructor _ _ | .place _, .unary _ _
    | .place _, .binary _ _ _ | .place _, .localCall _ _ | .place _, .match_ _ _
    | .place _, .externalCall _
    | .constructor _ _, .literal _ | .constructor _ _, .place _ | .constructor _ _, .unary _ _
    | .constructor _ _, .binary _ _ _ | .constructor _ _, .localCall _ _
    | .constructor _ _, .match_ _ _ | .constructor _ _, .externalCall _
    | .unary _ _, .literal _ | .unary _ _, .place _ | .unary _ _, .constructor _ _
    | .unary _ _, .binary _ _ _ | .unary _ _, .localCall _ _ | .unary _ _, .match_ _ _
    | .unary _ _, .externalCall _
    | .binary _ _ _, .literal _ | .binary _ _ _, .place _ | .binary _ _ _, .constructor _ _
    | .binary _ _ _, .unary _ _ | .binary _ _ _, .localCall _ _ | .binary _ _ _, .match_ _ _
    | .binary _ _ _, .externalCall _
    | .localCall _ _, .literal _ | .localCall _ _, .place _ | .localCall _ _, .constructor _ _
    | .localCall _ _, .unary _ _ | .localCall _ _, .binary _ _ _ | .localCall _ _, .match_ _ _
    | .localCall _ _, .externalCall _
    | .match_ _ _, .literal _ | .match_ _ _, .place _ | .match_ _ _, .constructor _ _
    | .match_ _ _, .unary _ _ | .match_ _ _, .binary _ _ _ | .match_ _ _, .localCall _ _
    | .match_ _ _, .externalCall _
    | .externalCall _, .literal _ | .externalCall _, .place _ | .externalCall _, .constructor _ _
    | .externalCall _, .unary _ _ | .externalCall _, .binary _ _ _ | .externalCall _, .localCall _ _
    | .externalCall _, .match_ _ _ =>
        isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqExprArray (a b : Array ExprV1) : Decidable (a = b) :=
    match a, b with
    | ⟨xs⟩, ⟨ys⟩ =>
        match decEqExprList xs ys with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    termination_by structural a

  private def decEqExprList (a b : List ExprV1) : Decidable (a = b) :=
    match a, b with
    | [], [] => isTrue rfl
    | x :: xs, y :: ys =>
        match decEqExpr x y with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue h =>
            match decEqExprList xs ys with
            | isTrue ht => isTrue (by cases h; cases ht; rfl)
            | isFalse ht => isFalse (by intro e; injection e with _ e; exact ht e)
    | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqExprMatchArm (a b : ExprMatchArmV1) : Decidable (a = b) :=
    match a, b with
    | ⟨px, vx⟩, ⟨py, vy⟩ =>
        match decEq px py with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hp =>
            match decEqExpr vx vy with
            | isTrue hv => isTrue (by cases hp; cases hv; rfl)
            | isFalse hv => isFalse (by intro e; injection e with _ e; exact hv e)
    termination_by structural a

  private def decEqExprMatchArmArray (a b : Array ExprMatchArmV1) : Decidable (a = b) :=
    match a, b with
    | ⟨xs⟩, ⟨ys⟩ =>
        match decEqExprMatchArmList xs ys with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    termination_by structural a

  private def decEqExprMatchArmList (a b : List ExprMatchArmV1) : Decidable (a = b) :=
    match a, b with
    | [], [] => isTrue rfl
    | x :: xs, y :: ys =>
        match decEqExprMatchArm x y with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue h =>
            match decEqExprMatchArmList xs ys with
            | isTrue ht => isTrue (by cases h; cases ht; rfl)
            | isFalse ht => isFalse (by intro e; injection e with _ e; exact ht e)
    | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqExternalCall (a b : ExternalCallExprV1) : Decidable (a = b) :=
    match a, b with
    | ⟨cx, ax⟩, ⟨cy, ay⟩ =>
        match decEq cx cy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hc =>
            match decEqExprArray ax ay with
            | isTrue ha => isTrue (by cases hc; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)

  private def decEqBlock (a b : BlockV1) : Decidable (a = b) :=
    match a, b with
    | ⟨sx⟩, ⟨sy⟩ =>
        match decEqStmtArray sx sy with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    termination_by structural a

  private def decEqOptionBlock (a b : Option BlockV1) : Decidable (a = b) :=
    match a, b with
    | none, none => isTrue rfl
    | some x, some y =>
        match decEqBlock x y with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | none, some _ | some _, none => isFalse (by intro h; cases h)

  private def decEqOptionExpr (a b : Option ExprV1) : Decidable (a = b) :=
    match a, b with
    | none, none => isTrue rfl
    | some x, some y =>
        match decEqExpr x y with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | none, some _ | some _, none => isFalse (by intro h; cases h)

  private def decEqStmtMatchArm (a b : StmtMatchArmV1) : Decidable (a = b) :=
    match a, b with
    | ⟨px, bx⟩, ⟨py, bodyY⟩ =>
        match decEq px py with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hp =>
            match decEqBlock bx bodyY with
            | isTrue hb => isTrue (by cases hp; cases hb; rfl)
            | isFalse hb => isFalse (by intro e; injection e with _ e; exact hb e)
    termination_by structural a

  private def decEqStmtMatchArmArray (a b : Array StmtMatchArmV1) : Decidable (a = b) :=
    match a, b with
    | ⟨xs⟩, ⟨ys⟩ =>
        match decEqStmtMatchArmList xs ys with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    termination_by structural a

  private def decEqStmtMatchArmList (a b : List StmtMatchArmV1) : Decidable (a = b) :=
    match a, b with
    | [], [] => isTrue rfl
    | x :: xs, y :: ys =>
        match decEqStmtMatchArm x y with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue h =>
            match decEqStmtMatchArmList xs ys with
            | isTrue ht => isTrue (by cases h; cases ht; rfl)
            | isFalse ht => isFalse (by intro e; injection e with _ e; exact ht e)
    | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqStmt (a b : StmtV1) : Decidable (a = b) :=
    match a, b with
    | .let_ nx tx vx, .let_ ny ty vy =>
        match decEq nx ny with
        | isFalse h => isFalse (by intro e; injection e with e _ _; exact h e)
        | isTrue hn =>
            match decEq tx ty with
            | isFalse ht => isFalse (by intro e; injection e with _ e _; exact ht e)
            | isTrue ht =>
                match decEqExpr vx vy with
                | isTrue hv => isTrue (by cases hn; cases ht; cases hv; rfl)
                | isFalse hv => isFalse (by intro e; injection e with _ _ e; exact hv e)
    | .assign tx vx, .assign ty vy =>
        match decEqPlace tx ty with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue ht =>
            match decEqExpr vx vy with
            | isTrue hv => isTrue (by cases ht; cases hv; rfl)
            | isFalse hv => isFalse (by intro e; injection e with _ e; exact hv e)
    | .if_ cx thx elx, .if_ cy thy ely =>
        match decEqExpr cx cy with
        | isFalse h => isFalse (by intro e; injection e with e _ _; exact h e)
        | isTrue hc =>
            match decEqBlock thx thy with
            | isFalse ht => isFalse (by intro e; injection e with _ e _; exact ht e)
            | isTrue ht =>
                match decEqOptionBlock elx ely with
                | isTrue he => isTrue (by cases hc; cases ht; cases he; rfl)
                | isFalse he => isFalse (by intro e; injection e with _ _ e; exact he e)
    | .match_ sx ax, .match_ sy ay =>
        match decEqExpr sx sy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hs =>
            match decEqStmtMatchArmArray ax ay with
            | isTrue ha => isTrue (by cases hs; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)
    | .for_ bx stx enx bdx bodyx, .for_ byy sty eny bdy bodyy =>
        match decEq bx byy with
        | isFalse h => isFalse (by intro e; injection e with e _ _ _ _; exact h e)
        | isTrue hb =>
            match decEqExpr stx sty with
            | isFalse hs => isFalse (by intro e; injection e with _ e _ _ _; exact hs e)
            | isTrue hs =>
                match decEqExpr enx eny with
                | isFalse he => isFalse (by intro e; injection e with _ _ e _ _; exact he e)
                | isTrue he =>
                    match decEq bdx bdy with
                    | isFalse hd => isFalse (by intro e; injection e with _ _ _ e _; exact hd e)
                    | isTrue hd =>
                        match decEqBlock bodyx bodyy with
                        | isTrue hbody =>
                            isTrue (by cases hb; cases hs; cases he; cases hd; cases hbody; rfl)
                        | isFalse hbody =>
                            isFalse (by intro e; injection e with _ _ _ _ e; exact hbody e)
    | .assert_ cx ex, .assert_ cy ey =>
        match decEqExpr cx cy with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue hc =>
            match decEq ex ey with
            | isTrue he => isTrue (by cases hc; cases he; rfl)
            | isFalse he => isFalse (by intro e; injection e with _ e; exact he e)
    | .revert ex ax, .revert ey ay =>
        match decEq ex ey with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue he =>
            match decEqExprArray ax ay with
            | isTrue ha => isTrue (by cases he; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)
    | .emit ex ax, .emit ey ay =>
        match decEq ex ey with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue he =>
            match decEqExprArray ax ay with
            | isTrue ha => isTrue (by cases he; cases ha; rfl)
            | isFalse ha => isFalse (by intro e; injection e with _ e; exact ha e)
    | .return_ vx, .return_ vy =>
        match decEqOptionExpr vx vy with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .call cx, .call cy =>
        match decEqExternalCall cx cy with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .schedule cx, .schedule cy =>
        match decEqExternalCall cx cy with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    | .let_ _ _ _, .assign _ _ | .let_ _ _ _, .if_ _ _ _ | .let_ _ _ _, .match_ _ _
    | .let_ _ _ _, .for_ _ _ _ _ _ | .let_ _ _ _, .assert_ _ _ | .let_ _ _ _, .revert _ _
    | .let_ _ _ _, .emit _ _ | .let_ _ _ _, .return_ _ | .let_ _ _ _, .call _
    | .let_ _ _ _, .schedule _
    | .assign _ _, .let_ _ _ _ | .assign _ _, .if_ _ _ _ | .assign _ _, .match_ _ _
    | .assign _ _, .for_ _ _ _ _ _ | .assign _ _, .assert_ _ _ | .assign _ _, .revert _ _
    | .assign _ _, .emit _ _ | .assign _ _, .return_ _ | .assign _ _, .call _
    | .assign _ _, .schedule _
    | .if_ _ _ _, .let_ _ _ _ | .if_ _ _ _, .assign _ _ | .if_ _ _ _, .match_ _ _
    | .if_ _ _ _, .for_ _ _ _ _ _ | .if_ _ _ _, .assert_ _ _ | .if_ _ _ _, .revert _ _
    | .if_ _ _ _, .emit _ _ | .if_ _ _ _, .return_ _ | .if_ _ _ _, .call _
    | .if_ _ _ _, .schedule _
    | .match_ _ _, .let_ _ _ _ | .match_ _ _, .assign _ _ | .match_ _ _, .if_ _ _ _
    | .match_ _ _, .for_ _ _ _ _ _ | .match_ _ _, .assert_ _ _ | .match_ _ _, .revert _ _
    | .match_ _ _, .emit _ _ | .match_ _ _, .return_ _ | .match_ _ _, .call _
    | .match_ _ _, .schedule _
    | .for_ _ _ _ _ _, .let_ _ _ _ | .for_ _ _ _ _ _, .assign _ _
    | .for_ _ _ _ _ _, .if_ _ _ _ | .for_ _ _ _ _ _, .match_ _ _
    | .for_ _ _ _ _ _, .assert_ _ _ | .for_ _ _ _ _ _, .revert _ _
    | .for_ _ _ _ _ _, .emit _ _ | .for_ _ _ _ _ _, .return_ _
    | .for_ _ _ _ _ _, .call _ | .for_ _ _ _ _ _, .schedule _
    | .assert_ _ _, .let_ _ _ _ | .assert_ _ _, .assign _ _ | .assert_ _ _, .if_ _ _ _
    | .assert_ _ _, .match_ _ _ | .assert_ _ _, .for_ _ _ _ _ _ | .assert_ _ _, .revert _ _
    | .assert_ _ _, .emit _ _ | .assert_ _ _, .return_ _ | .assert_ _ _, .call _
    | .assert_ _ _, .schedule _
    | .revert _ _, .let_ _ _ _ | .revert _ _, .assign _ _ | .revert _ _, .if_ _ _ _
    | .revert _ _, .match_ _ _ | .revert _ _, .for_ _ _ _ _ _ | .revert _ _, .assert_ _ _
    | .revert _ _, .emit _ _ | .revert _ _, .return_ _ | .revert _ _, .call _
    | .revert _ _, .schedule _
    | .emit _ _, .let_ _ _ _ | .emit _ _, .assign _ _ | .emit _ _, .if_ _ _ _
    | .emit _ _, .match_ _ _ | .emit _ _, .for_ _ _ _ _ _ | .emit _ _, .assert_ _ _
    | .emit _ _, .revert _ _ | .emit _ _, .return_ _ | .emit _ _, .call _
    | .emit _ _, .schedule _
    | .return_ _, .let_ _ _ _ | .return_ _, .assign _ _ | .return_ _, .if_ _ _ _
    | .return_ _, .match_ _ _ | .return_ _, .for_ _ _ _ _ _ | .return_ _, .assert_ _ _
    | .return_ _, .revert _ _ | .return_ _, .emit _ _ | .return_ _, .call _
    | .return_ _, .schedule _
    | .call _, .let_ _ _ _ | .call _, .assign _ _ | .call _, .if_ _ _ _
    | .call _, .match_ _ _ | .call _, .for_ _ _ _ _ _ | .call _, .assert_ _ _
    | .call _, .revert _ _ | .call _, .emit _ _ | .call _, .return_ _ | .call _, .schedule _
    | .schedule _, .let_ _ _ _ | .schedule _, .assign _ _ | .schedule _, .if_ _ _ _
    | .schedule _, .match_ _ _ | .schedule _, .for_ _ _ _ _ _ | .schedule _, .assert_ _ _
    | .schedule _, .revert _ _ | .schedule _, .emit _ _ | .schedule _, .return_ _
    | .schedule _, .call _ =>
        isFalse (by intro h; cases h)
    termination_by structural a

  private def decEqStmtArray (a b : Array StmtV1) : Decidable (a = b) :=
    match a, b with
    | ⟨xs⟩, ⟨ys⟩ =>
        match decEqStmtList xs ys with
        | isTrue h => isTrue (by cases h; rfl)
        | isFalse h => isFalse (by intro e; injection e with e; exact h e)
    termination_by structural a

  private def decEqStmtList (a b : List StmtV1) : Decidable (a = b) :=
    match a, b with
    | [], [] => isTrue rfl
    | x :: xs, y :: ys =>
        match decEqStmt x y with
        | isFalse h => isFalse (by intro e; injection e with e _; exact h e)
        | isTrue h =>
            match decEqStmtList xs ys with
            | isTrue ht => isTrue (by cases h; cases ht; rfl)
            | isFalse ht => isFalse (by intro e; injection e with _ e; exact ht e)
    | [], _ :: _ | _ :: _, [] => isFalse (by intro h; cases h)
    termination_by structural a
end

instance : DecidableEq PlaceV1 := decEqPlace
instance : DecidableEq ExprV1 := decEqExpr
instance : DecidableEq ExprMatchArmV1 := decEqExprMatchArm
instance : DecidableEq ExternalCallExprV1 := decEqExternalCall
instance : DecidableEq StmtV1 := decEqStmt
instance : DecidableEq StmtMatchArmV1 := decEqStmtMatchArm
instance : DecidableEq BlockV1 := decEqBlock

end ProofForgeV2.Source.AstSpineV1
