import ProofForgeV2.Source.AstSpineEqV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace Tests.Language.SourceAstSpineV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (c : Bool) (m : String) : IO Unit :=
  unless c do throw <| IO.userError m

private def lift (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def name (s : String) : IO SourceNameComponentV1 :=
  lift s (parseSourceNameComponentV1 s)

private def qn (ps : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 ps)

/-- D1-PA-99 phase-neutral: complete mutual-spine construction and equality checks. -/
def run : IO Unit := do
  let x ← name "x"
  let y ← name "y"
  let total ← name "total"
  let arr ← name "arr"
  let helper ← name "helper"
  let count ← name "count"
  let denied ← name "Denied"
  let ping ← name "Ping"
  let foobar ← name "foo-bar"
  let optSome ← qn #["Option", "some"]
  let optNone ← qn #["Option", "none"]
  let mathAdd ← qn #["Math", "add"]
  let lit1 : ExprV1 := .literal (.integer 1)
  let lit2 : ExprV1 := .literal (.integer 2)
  let litT : ExprV1 := .literal (.bool true)
  let litF : ExprV1 := .literal (.bool false)
  let litH : ExprV1 := .literal (.string "hi")
  -- all 25 constructors: Place 3
  let pName : PlaceV1 := .name x
  let pField : PlaceV1 := .field pName total
  let pIndex : PlaceV1 := .index (.name arr) lit1
  -- Block
  let sRet0 : StmtV1 := .return_ none
  let sRet1 : StmtV1 := .return_ (some lit1)
  let blk1 : BlockV1 := { statements := #[sRet0] }
  let blk2 : BlockV1 := { statements := #[sRet0, sRet1] }
  -- arms
  let sArmW : StmtMatchArmV1 := { pattern := .wildcard, body := blk1 }
  let sArmB : StmtMatchArmV1 := { pattern := .bind x, body := blk2 }
  let sArmRaw : StmtMatchArmV1 := { pattern := .bind foobar, body := blk1 }
  let eArmC : ExprMatchArmV1 := { pattern := .constructor optSome #[.bind y], value := lit1 }
  let eArmW : ExprMatchArmV1 := { pattern := .wildcard, value := lit2 }
  -- ExternalCallExpr
  let ext0 : ExternalCallExprV1 := { callee := mathAdd, args := #[] }
  let ext1 : ExternalCallExprV1 := { callee := mathAdd, args := #[lit1] }
  -- Expr 7 constructors
  let ePlace : ExprV1 := .place pName
  let eCtor1 : ExprV1 := .constructor optSome #[litT]
  let eCtor0 : ExprV1 := .constructor optNone #[]
  let eUnary : ExprV1 := .unary .neg lit1
  let eBinary : ExprV1 := .binary .add lit1 lit2
  let eLocal : ExprV1 := .localCall helper #[lit1]
  let eMatch : ExprV1 := .match_ lit1 #[eArmC]
  -- Stmt 11 constructors
  let stLet0 : StmtV1 := .let_ x none lit1
  let stLet1 : StmtV1 := .let_ y (some .bool) litT
  let stAssign : StmtV1 := .assign pName lit1
  let stIf0 : StmtV1 := .if_ litT blk1 none
  let stIf1 : StmtV1 := .if_ litT blk1 (some blk2)
  let stMatch : StmtV1 := .match_ lit1 #[sArmW]
  let stFor : StmtV1 := .for_ x lit1 lit2 4096 blk1
  let stAssert0 : StmtV1 := .assert_ litT none
  let stAssert1 : StmtV1 := .assert_ litT (some denied)
  let stRevert0 : StmtV1 := .revert denied #[]
  let stRevert1 : StmtV1 := .revert denied #[lit1]
  let stEmit : StmtV1 := .emit ping #[]
  let stCall : StmtV1 := .call ext0
  let stSchedule : StmtV1 := .schedule ext0
  -- depth-3 Block→Stmt.If→Block structures
  let deep1 : BlockV1 :=
    { statements := #[.if_ litT { statements := #[.return_ (some lit1)] } none] }
  let deep2 : BlockV1 :=
    { statements := #[.if_ litT { statements := #[.return_ (some lit2)] } none] }
  -- 7 DecidableEq instances: decide equality true and decide inequality true
  expect (decide (pName = pName)) "PlaceV1 eq"
  expect (decide (pName ≠ .name y)) "PlaceV1 ne"
  expect (decide (litT = litT)) "ExprV1 eq"
  expect (decide (litT ≠ litF)) "ExprV1 ne"
  expect (decide (ePlace ≠ eCtor1)) "ExprV1 constructor ne"
  expect (decide (eMatch ≠ .match_ lit1 #[eArmC, eArmW])) "ExprV1 match arms length"
  expect (decide (sRet0 = sRet0)) "StmtV1 eq"
  expect (decide (sRet0 ≠ sRet1)) "StmtV1 ne"
  expect (decide (stLet0 ≠ stLet1)) "StmtV1 let ne"
  expect (decide (stAssign ≠ .assign pName lit2)) "StmtV1 assign ne"
  expect (decide (blk1 = blk1)) "BlockV1 eq"
  expect (decide (blk1 ≠ blk2)) "BlockV1 ne length"
  expect (decide (sArmW = sArmW)) "StmtMatchArmV1 eq"
  expect (decide (sArmW ≠ sArmB)) "StmtMatchArmV1 ne"
  expect (decide (eArmC = eArmC)) "ExprMatchArmV1 eq"
  expect (decide (eArmC ≠ eArmW)) "ExprMatchArmV1 ne"
  expect (decide (ext0 = ext0)) "ExternalCallExprV1 eq"
  expect (decide (ext0 ≠ ext1)) "ExternalCallExprV1 ne"
  -- arrays: order and length sensitivity
  expect (decide
    (ExprV1.constructor optSome #[lit1, lit2] ≠ .constructor optSome #[lit2, lit1]))
    "ctor args order"
  expect (decide (eLocal ≠ .localCall helper #[lit1, lit2])) "local args length"
  expect (decide (stMatch ≠ .match_ lit1 #[sArmW, sArmB])) "arms length"
  expect (decide
    (({ statements := #[sRet0, sRet1] } : BlockV1) ≠ { statements := #[sRet1, sRet0] }))
    "block statements order"
  expect (decide
    (({ callee := mathAdd, args := #[lit1, lit2] } : ExternalCallExprV1) ≠
      { callee := mathAdd, args := #[lit2, lit1] })) "external args order"
  -- four Option sites: none ≠ some
  expect (decide (stLet0 ≠ .let_ x (some .bool) lit1)) "let typeAnn none≠some"
  expect (decide (stIf0 ≠ stIf1)) "if elseBlock none≠some"
  expect (decide (stAssert0 ≠ stAssert1)) "assert error none≠some"
  expect (decide (sRet0 ≠ sRet1)) "return value none≠some"
  -- Call/Schedule nonalias, For bound difference
  expect (decide (stCall ≠ stSchedule)) "call≠schedule"
  expect (decide (stFor ≠ .for_ x lit1 lit2 4095 blk1)) "for bound 4096≠4095"
  -- distinct-constructor shape mismatches
  expect (decide (eUnary ≠ .unary .not lit1)) "unary op mismatch"
  expect (decide (eBinary ≠ .binary .sub lit1 lit2)) "binary op mismatch"
  expect (decide (eCtor1 ≠ eCtor0)) "ctor args mismatch"
  expect (decide (pField ≠ .field pName count)) "place field mismatch"
  expect (decide (pIndex ≠ .index (PlaceV1.name arr) lit2)) "place index mismatch"
  expect (decide (litH = litH)) "literal string eq"
  expect (decide (stEmit ≠ .emit ping #[lit1])) "emit args mismatch"
  expect (decide (stRevert0 ≠ stRevert1)) "revert args mismatch"
  expect (decide (sArmB ≠ sArmRaw)) "arm raw bind mismatch"
  -- depth-3 deep equal / deep mismatch
  expect (decide (deep1 =
    ({ statements := #[.if_ litT { statements := #[.return_ (some lit1)] } none] } : BlockV1)))
    "deep equal"
  expect (decide (deep1 ≠ deep2)) "deep mismatch"

end Tests.Language.SourceAstSpineV1
