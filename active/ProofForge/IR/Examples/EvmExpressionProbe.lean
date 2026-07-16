import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmExpressionProbe

open ProofForge.IR

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def boolLit (value : Bool) : Expr :=
  .literal (.bool value)

def arithmeticU64 : Entrypoint := {
  name := "arithmetic_u64"
  selector? := some "139ade38"
  returns := .u64
  body := #[
    .letBind "delta" .u64 (.sub (u64 9) (u64 4)),
    .assertEq (.local "delta") (u64 5) "u64 subtraction lowers",
    .letBind "sum" .u64 (.add (.local "delta") (u64 7)),
    .assertEq (.local "sum") (u64 12) "u64 addition lowers",
    .letBind "product" .u64 (.mul (.local "sum") (u64 3)),
    .assertEq (.local "product") (u64 36) "u64 multiplication lowers",
    .letBind "quotient" .u64 (.div (.local "product") (u64 5)),
    .assertEq (.local "quotient") (u64 7) "u64 division lowers",
    .letBind "remainder" .u64 (.mod (.local "product") (u64 5)),
    .assertEq (.local "remainder") (u64 1) "u64 modulo lowers",
    .letBind "powered" .u64 (.pow (u64 2) (u64 5)),
    .assertEq (.local "powered") (u64 32) "u64 exponentiation lowers",
    .return (.add (.add (.local "powered") (.local "quotient")) (.local "remainder"))
  ]
}

def bitwiseU64 : Entrypoint := {
  name := "bitwise_u64"
  selector? := some "2e124ba8"
  returns := .u64
  body := #[
    .letBind "ored" .u64 (.bitOr (u64 20) (u64 8)),
    .assertEq (.local "ored") (u64 28) "u64 bitwise or lowers",
    .letBind "anded" .u64 (.bitAnd (.local "ored") (u64 10)),
    .assertEq (.local "anded") (u64 8) "u64 bitwise and lowers",
    .letBind "xored" .u64 (.bitXor (.local "anded") (u64 3)),
    .assertEq (.local "xored") (u64 11) "u64 bitwise xor lowers",
    .letBind "left" .u64 (.shiftLeft (.local "xored") (u64 1)),
    .assertEq (.local "left") (u64 22) "u64 shift-left lowers",
    .letBind "right" .u64 (.shiftRight (.local "left") (u64 1)),
    .assertEq (.local "right") (u64 11) "u64 shift-right lowers",
    .return (.local "right")
  ]
}

def predicateMatrix : Entrypoint := {
  name := "predicate_matrix"
  selector? := some "219a55f8"
  returns := .u64
  body := #[
    .letBind "a" .u64 (u64 7),
    .letBind "b" .u64 (u64 9),
    .letBind "a_is_seven" .bool (.eq (.local "a") (u64 7)),
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
    .letBind "bool_eq" .bool (.eq (.local "a_is_seven") (boolLit true)),
    .letBind "bool_ne" .bool (.ne (.local "a_before_b") (boolLit false)),
    .assert (.local "a_is_seven") "equality predicate works",
    .assert (.local "a_not_b") "inequality predicate works",
    .assert (.local "a_before_b") "less-than predicates compose",
    .assert (.local "b_after_a") "greater-than predicates compose",
    .assert (.local "any_ordered") "boolean or preserves true branch",
    .assert (.local "not_equal") "boolean not flips false equality",
    .assert (.local "bool_eq") "bool equality works",
    .assert (.local "bool_ne") "bool inequality works",
    .return (.add
      (.add
        (.add
          (.cast (.local "a_is_seven") .u64)
          (.cast (.local "a_not_b") .u64))
        (.add
          (.cast (.local "a_before_b") .u64)
          (.cast (.local "b_after_a") .u64)))
      (.add
        (.add
          (.cast (.local "any_ordered") .u64)
          (.cast (.local "not_equal") .u64))
        (.add
          (.cast (.local "bool_eq") .u64)
          (.cast (.local "bool_ne") .u64))))
  ]
}

def castsAndU32 : Entrypoint := {
  name := "casts_and_u32"
  selector? := some "555e000e"
  params := #[
    ("delta", .u32),
    ("flag", .bool)
  ]
  returns := .u64
  body := #[
    .letBind "delta64" .u64 (.cast (.local "delta") .u64),
    .letBind "flag32" .u32 (.cast (.local "flag") .u32),
    .letBind "flag64" .u64 (.cast (.local "flag") .u64),
    .letBind "narrowed" .u32 (.cast (u64 33) .u32),
    .letBind "u32_bool" .bool (.cast (u32 1) .bool),
    .letBind "u64_bool" .bool (.cast (u64 1) .bool),
    .letBind "word_sum" .u32 (.add (.local "delta") (u32 3)),
    .assertEq (.local "word_sum") (u32 10) "u32 addition lowers",
    .letBind "word_product" .u32 (.mul (.sub (.local "word_sum") (u32 1)) (u32 2)),
    .assertEq (.local "word_product") (u32 18) "u32 subtraction and multiplication lower",
    .letBind "word_quotient" .u32 (.div (.local "word_product") (u32 3)),
    .assertEq (.local "word_quotient") (u32 6) "u32 division lowers",
    .letBind "word_remainder" .u32 (.mod (.local "word_product") (u32 5)),
    .assertEq (.local "word_remainder") (u32 3) "u32 modulo lowers",
    .letBind "word_bits" .u32 (.shiftRight
      (.shiftLeft
        (.bitXor
          (.bitOr
            (.bitAnd (u32 12) (u32 10))
            (u32 1))
          (u32 3))
        (u32 1))
      (u32 2)),
    .assertEq (.local "word_bits") (u32 5) "u32 bitwise and shifts lower",
    .assert (.local "u32_bool") "u32 to bool cast lowers for canonical bool word",
    .assert (.local "u64_bool") "u64 to bool cast lowers for canonical bool word",
    .return (.add
      (.add
        (.add (.local "delta64") (.cast (.local "flag32") .u64))
        (.add (.local "flag64") (.cast (.local "narrowed") .u64)))
      (.add
        (.cast (.local "word_remainder") .u64)
        (.cast (.local "word_bits") .u64)))
  ]
}

def module : Module := {
  name := "EvmExpressionProbe"
  state := #[]
  entrypoints := #[
    arithmeticU64,
    bitwiseU64,
    predicateMatrix,
    castsAndU32
  ]
}

end ProofForge.IR.Examples.EvmExpressionProbe
