import ProofForge.Backend.Quint.Model

namespace ProofForge.Backend.Quint.GuardAst

open ProofForge.Backend.Quint

def exprIsLiteralInt (n : Int) : Expr → Bool
  | .literalInt v => v == n
  | _ => false

partial def exprReferencesLocal (name : String) : Expr → Bool
  | .local n => n == name
  | .prime e => exprReferencesLocal name e
  | .binOp _ lhs rhs =>
      exprReferencesLocal name lhs || exprReferencesLocal name rhs
  | .unOp _ e => exprReferencesLocal name e
  | .ite cond thenExpr elseExpr =>
      exprReferencesLocal name cond
        || exprReferencesLocal name thenExpr
        || exprReferencesLocal name elseExpr
  | .index list index =>
      exprReferencesLocal name list || exprReferencesLocal name index
  | .methodCall receiver _ args =>
      exprReferencesLocal name receiver
        || args.any (exprReferencesLocal name)
  | .app _ args => args.any (exprReferencesLocal name)
  | .oneOf e => exprReferencesLocal name e
  | .range lo hi => exprReferencesLocal name lo || exprReferencesLocal name hi
  | .setLit values | .listLit values => values.any (exprReferencesLocal name)
  | .mapLit entries =>
      entries.any fun (k, v) =>
        exprReferencesLocal name k || exprReferencesLocal name v
  | _ => false

partial def exprContainsIte : Expr → Bool
  | .ite _ _ _ => true
  | .binOp _ lhs rhs => exprContainsIte lhs || exprContainsIte rhs
  | .unOp _ e => exprContainsIte e
  | .prime e => exprContainsIte e
  | .index list index => exprContainsIte list || exprContainsIte index
  | .methodCall receiver _ args =>
      exprContainsIte receiver || args.any exprContainsIte
  | .app _ args => args.any exprContainsIte
  | .oneOf e => exprContainsIte e
  | .range lo hi => exprContainsIte lo || exprContainsIte hi
  | .setLit values | .listLit values => values.any exprContainsIte
  | .mapLit entries =>
      entries.any fun (k, v) => exprContainsIte k || exprContainsIte v
  | _ => false

partial def exprStructurallyEq : Expr → Expr → Bool
  | .literalInt a, .literalInt b => a == b
  | .literalBool a, .literalBool b => a == b
  | .literalStr a, .literalStr b => a == b
  | .local a, .local b => a == b
  | .binOp oa la ra, .binOp ob lb rb =>
      oa == ob && exprStructurallyEq la lb && exprStructurallyEq ra rb
  | .unOp oa a, .unOp ob b => oa == ob && exprStructurallyEq a b
  | .prime a, .prime b => exprStructurallyEq a b
  | .ite ca ta ea, .ite cb tb eb =>
      exprStructurallyEq ca cb
        && exprStructurallyEq ta tb
        && exprStructurallyEq ea eb
  | .index la ia, .index lb ib =>
      exprStructurallyEq la lb && exprStructurallyEq ia ib
  | .methodCall ra ma aa, .methodCall rb mb ab =>
      ra == rb && ma == mb && aa.size == ab.size
        && (aa.zip ab).all fun (x, y) => exprStructurallyEq x y
  | .app fa aa, .app fb ab =>
      fa == fb && aa.size == ab.size
        && (aa.zip ab).all fun (x, y) => exprStructurallyEq x y
  | .oneOf a, .oneOf b => exprStructurallyEq a b
  | .range la ha, .range lb hb =>
      exprStructurallyEq la lb && exprStructurallyEq ha hb
  | .setLit a, .setLit b =>
      a.size == b.size && (a.zip b).all fun (x, y) => exprStructurallyEq x y
  | .listLit a, .listLit b =>
      a.size == b.size && (a.zip b).all fun (x, y) => exprStructurallyEq x y
  | .mapLit a, .mapLit b =>
      a.size == b.size
        && (a.zip b).all fun ((ka, va), (kb, vb)) =>
          exprStructurallyEq ka kb && exprStructurallyEq va vb
  | _, _ => false

def exprIsSelfEq : Expr → Bool
  | .binOp .eq lhs rhs => exprStructurallyEq lhs rhs
  | _ => false

/-- Dynamic array-of-struct path reads use an index-guarded ite chain over flattened slots. -/
def exprIsDynamicArrayStructRead (e : Expr) : Bool :=
  !exprIsLiteralInt 0 e
    && exprContainsIte e
    && exprReferencesLocal "index" e
    && (exprReferencesLocal "points_0_x" e || exprReferencesLocal "points_1_x" e)

/-- Find the folded dynamic-path return guard (`read == 45`) inside lowered action clauses. -/
partial def findDynamicPathReturnGuard? : ActionClause → Option (Expr × Expr)
  | .guard (.binOp .eq lhs rhs) =>
      if exprIsLiteralInt 45 rhs && !exprStructurallyEq lhs rhs then
        some (lhs, rhs)
      else
        none
  | .all clauses => clauses.findSome? findDynamicPathReturnGuard?
  | .any clauses => clauses.findSome? findDynamicPathReturnGuard?
  | _ => none

/-- Quint source must contain a folded return guard against literal 45, not a self-equality. -/
def validateRenderedDynamicPathGuard (source : String) : Option String :=
  if !source.contains "== 45)" then
    some "rendered Quint model must contain return guard `== 45)`"
  else if source.contains "else 0) == (if" then
    some "rendered Quint model must not tautologically equate identical read expressions"
  else
    none

/-- Structural validation for the dynamic struct-path return guard pair. -/
def validateDynamicPathReturnGuard (readExpr expectedExpr : Expr) : Option String :=
  if exprIsLiteralInt 0 readExpr then
    some "read expression must not be a stubbed zero literal"
  else if !exprIsDynamicArrayStructRead readExpr then
    some "read expression must be a dynamic array-of-struct path read (ite + index + slot locals)"
  else if !exprIsLiteralInt 45 expectedExpr then
    some "expected expression must constant-fold to literal 45"
  else if exprStructurallyEq readExpr expectedExpr then
    some "read and expected must not be structurally identical (tautology)"
  else if exprIsSelfEq (.binOp .eq readExpr expectedExpr) then
    some "return guard must not be a self-equality"
  else
    none

end ProofForge.Backend.Quint.GuardAst