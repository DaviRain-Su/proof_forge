import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.ExpressionPredicateProbe

open ProofForge.IR

def stateMarker : StateDecl := {
  id := "_proof_forge_marker"
  kind := .scalar
  type := .u64
}

def felt (value : Nat) : Expr :=
  .literal (.u64 value)

def bool (value : Bool) : Expr :=
  .literal (.bool value)

def predicateSum : Entrypoint := {
  name := "predicate_sum"
  returns := .u64
  body := #[
    .letBind "a" .u64 (felt 7),
    .letBind "b" .u64 (felt 9),
    .letBind "a_is_seven" .bool (.eq (.local "a") (felt 7)),
    .letBind "a_not_b" .bool (.ne (.local "a") (.local "b")),
    .letBind "a_before_b" .bool (.boolAnd
      (.lt (.local "a") (.local "b"))
      (.le (.local "a") (.local "b"))),
    .letBind "b_after_a" .bool (.boolAnd
      (.gt (.local "b") (.local "a"))
      (.ge (.local "b") (.local "b"))),
    .letBind "any_ordered" .bool (.boolOr
      (.eq (.local "a") (.local "b"))
      (.local "a_before_b")),
    .letBind "not_equal" .bool (.boolNot (.eq (.local "a") (.local "b"))),
    .assert (.local "a_is_seven") "equality predicate works",
    .assert (.local "a_not_b") "inequality predicate works",
    .assert (.local "a_before_b") "less-than predicates compose",
    .assert (.local "b_after_a") "greater-than predicates compose",
    .assert (.local "any_ordered") "boolean or preserves true branch",
    .assert (.local "not_equal") "boolean not flips false equality",
    .assert (.eq (.local "a_is_seven") (bool true)) "bool equality works",
    .assert (.ne (.local "a_before_b") (bool false)) "bool inequality works",
    .return (.add (.local "a") (.local "b"))
  ]
}

def module : Module := {
  name := "ExpressionPredicateProbe"
  state := #[stateMarker]
  entrypoints := #[predicateSum]
}

end ProofForge.IR.Examples.ExpressionPredicateProbe
