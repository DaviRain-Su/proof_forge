import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmStructArrayValueProbe

open ProofForge.IR

def personStruct : StructDecl := {
  name := "Person"
  fields := #[
    { id := "age", type := .u64 },
    { id := "score", type := .u64 }
  ]
}

def mixedStruct : StructDecl := {
  name := "Mixed"
  fields := #[
    { id := "enabled", type := .bool },
    { id := "small", type := .u32 },
    { id := "root", type := .hash }
  ]
}

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def bool (value : Bool) : Expr :=
  .literal (.bool value)

def hash (a b c d : Nat) : Expr :=
  .literal (.hash4 a b c d)

def person (age score : Nat) : Expr :=
  .structLit "Person" #[
    ("age", u64 age),
    ("score", u64 score)
  ]

def mixed (enabled : Bool) (small : Nat) (root : Expr) : Expr :=
  .structLit "Mixed" #[
    ("enabled", bool enabled),
    ("small", u32 small),
    ("root", root)
  ]

def personGridType : ValueType :=
  .fixedArray (.fixedArray (.structType "Person") 2) 2

def personRow (left right : Expr) : Expr :=
  .arrayLit (.structType "Person") #[left, right]

def personGrid (topLeft topRight bottomLeft bottomRight : Expr) : Expr :=
  .arrayLit (.fixedArray (.structType "Person") 2) #[
    personRow topLeft topRight,
    personRow bottomLeft bottomRight
  ]

def personGridField (name : String) (row col : Expr) (fieldName : String) : Expr :=
  .field (.arrayGet (.arrayGet (.local name) row) col) fieldName

def localStructArraySum : Entrypoint := {
  name := "local_struct_array_sum"
  selector? := some "6dcefec0"
  returns := .u64
  body := #[
    .letBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 10 80, person 20 90]),
    .return (.add
      (.field (.arrayGet (.local "people") (u64 0)) "age")
      (.field (.arrayGet (.local "people") (u64 1)) "score"))
  ]
}

def dynamicStructArrayPick : Entrypoint := {
  name := "dynamic_struct_array_pick"
  selector? := some "0601d7ac"
  params := #[
    ("idx", .u64)
  ]
  returns := .u64
  body := #[
    .letBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 10 80, person 20 90]),
    .return (.add
      (.field (.arrayGet (.local "people") (.local "idx")) "age")
      (.field (.arrayGet (.local "people") (.local "idx")) "score"))
  ]
}

def mutableStructArrayUpdate : Entrypoint := {
  name := "mutable_struct_array_update"
  selector? := some "bfa2eef8"
  params := #[
    ("idx", .u64)
  ]
  returns := .u64
  body := #[
    .letMutBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 10 80, person 20 90]),
    .assign (.field (.arrayGet (.local "people") (.local "idx")) "age") (u64 30),
    .assignOp (.field (.arrayGet (.local "people") (.local "idx")) "score") .add (u64 7),
    .return (.add
      (.field (.arrayGet (.local "people") (.local "idx")) "age")
      (.field (.arrayGet (.local "people") (.local "idx")) "score"))
  ]
}

def staticStructArrayUpdate : Entrypoint := {
  name := "static_struct_array_update"
  selector? := some "c8c9bc70"
  returns := .u64
  body := #[
    .letMutBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 10 80, person 20 90]),
    .assign (.field (.arrayGet (.local "people") (u64 1)) "age") (u64 33),
    .assignOp (.field (.arrayGet (.local "people") (u64 0)) "score") .add (u64 5),
    .return (.add
      (.field (.arrayGet (.local "people") (u64 0)) "score")
      (.field (.arrayGet (.local "people") (u64 1)) "age"))
  ]
}

def mixedStructArrayFields : Entrypoint := {
  name := "mixed_struct_array_fields"
  selector? := some "8c32c4da"
  returns := .u64
  body := #[
    .letMutBind "rows" (.fixedArray (.structType "Mixed") 2)
      (.arrayLit (.structType "Mixed") #[
        mixed false 7 (hash 1 2 3 4),
        mixed true 9 (hash 5 6 7 8)
      ]),
    .assign (.field (.arrayGet (.local "rows") (u64 0)) "enabled") (bool true),
    .assign (.field (.arrayGet (.local "rows") (u64 1)) "small") (u32 11),
    .assign (.field (.arrayGet (.local "rows") (u64 0)) "root") (hash 9 10 11 12),
    .assert (.field (.arrayGet (.local "rows") (u64 0)) "enabled") "mutable struct-array bool field must update",
    .assertEq (.field (.arrayGet (.local "rows") (u64 0)) "root") (hash 9 10 11 12) "mutable struct-array hash field must update",
    .return (.add
      (.cast (.field (.arrayGet (.local "rows") (u64 1)) "small") .u64)
      (.cast (.field (.arrayGet (.local "rows") (u64 0)) "enabled") .u64))
  ]
}

def wholeStructArrayAssign : Entrypoint := {
  name := "whole_struct_array_assign"
  selector? := some "cd4a0dc2"
  returns := .u64
  body := #[
    .letMutBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 1 2, person 3 4]),
    .letBind "next" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 11 13, person 17 19]),
    .assign (.local "people") (.local "next"),
    .return (.add
      (.add
        (.field (.arrayGet (.local "people") (u64 0)) "age")
        (.field (.arrayGet (.local "people") (u64 0)) "score"))
      (.add
        (.field (.arrayGet (.local "people") (u64 1)) "age")
        (.field (.arrayGet (.local "people") (u64 1)) "score")))
  ]
}

def selfStructArrayAssign : Entrypoint := {
  name := "self_struct_array_assign"
  selector? := some "e5ea5747"
  returns := .u64
  body := #[
    .letMutBind "people" (.fixedArray (.structType "Person") 2)
      (.arrayLit (.structType "Person") #[person 5 7, person 11 13]),
    .assign (.local "people")
      (.arrayLit (.structType "Person") #[
        .structLit "Person" #[
          ("age", .field (.arrayGet (.local "people") (u64 1)) "age"),
          ("score", .field (.arrayGet (.local "people") (u64 0)) "score")
        ],
        .structLit "Person" #[
          ("age", .field (.arrayGet (.local "people") (u64 0)) "age"),
          ("score", .field (.arrayGet (.local "people") (u64 1)) "score")
        ]
      ]),
    .return (.add
      (.add
        (.field (.arrayGet (.local "people") (u64 0)) "age")
        (.field (.arrayGet (.local "people") (u64 0)) "score"))
      (.add
        (.field (.arrayGet (.local "people") (u64 1)) "age")
        (.field (.arrayGet (.local "people") (u64 1)) "score")))
  ]
}

def nestedStructArraySum : Entrypoint := {
  name := "nested_struct_array_sum"
  selector? := some "25daebe2"
  returns := .u64
  body := #[
    .letBind "grid" personGridType
      (personGrid
        (person 10 80)
        (person 20 90)
        (person 30 100)
        (person 40 110)),
    .return (.add
      (personGridField "grid" (u64 1) (u64 0) "age")
      (personGridField "grid" (u64 0) (u64 1) "score"))
  ]
}

def nestedStructArrayDynamicPick : Entrypoint := {
  name := "nested_struct_array_dynamic_pick"
  selector? := some "56d9da6f"
  params := #[
    ("row", .u64),
    ("col", .u64)
  ]
  returns := .u64
  body := #[
    .letBind "grid" personGridType
      (personGrid
        (person 10 80)
        (person 20 90)
        (person 30 100)
        (person 40 110)),
    .return (.add
      (personGridField "grid" (.local "row") (.local "col") "age")
      (personGridField "grid" (.local "row") (.local "col") "score"))
  ]
}

def nestedStructArrayUpdate : Entrypoint := {
  name := "nested_struct_array_update"
  selector? := some "d29b2aa1"
  params := #[
    ("row", .u64),
    ("col", .u64)
  ]
  returns := .u64
  body := #[
    .letMutBind "grid" personGridType
      (personGrid
        (person 10 80)
        (person 20 90)
        (person 30 100)
        (person 40 110)),
    .assign (personGridField "grid" (.local "row") (.local "col") "age") (u64 50),
    .assignOp (personGridField "grid" (.local "row") (.local "col") "score") .add (u64 7),
    .return (.add
      (personGridField "grid" (.local "row") (.local "col") "age")
      (personGridField "grid" (.local "row") (.local "col") "score"))
  ]
}

def nestedStructArrayWholeAssign : Entrypoint := {
  name := "nested_struct_array_whole_assign"
  selector? := some "3bd4106e"
  returns := .u64
  body := #[
    .letMutBind "grid" personGridType
      (personGrid
        (person 1 2)
        (person 3 4)
        (person 5 6)
        (person 7 8)),
    .letBind "next" personGridType
      (personGrid
        (person 11 13)
        (person 17 19)
        (person 23 29)
        (person 31 37)),
    .assign (.local "grid") (.local "next"),
    .return (.add
      (.add
        (.add
          (personGridField "grid" (u64 0) (u64 0) "age")
          (personGridField "grid" (u64 0) (u64 0) "score"))
        (.add
          (personGridField "grid" (u64 0) (u64 1) "age")
          (personGridField "grid" (u64 0) (u64 1) "score")))
      (.add
        (.add
          (personGridField "grid" (u64 1) (u64 0) "age")
          (personGridField "grid" (u64 1) (u64 0) "score"))
        (.add
          (personGridField "grid" (u64 1) (u64 1) "age")
          (personGridField "grid" (u64 1) (u64 1) "score"))))
  ]
}

def nestedStructArraySelfAssign : Entrypoint := {
  name := "nested_struct_array_self_assign"
  selector? := some "cd232639"
  returns := .u64
  body := #[
    .letMutBind "grid" personGridType
      (personGrid
        (person 1 2)
        (person 3 4)
        (person 5 6)
        (person 7 8)),
    .assign (.local "grid")
      (personGrid
        (.structLit "Person" #[
          ("age", personGridField "grid" (u64 1) (u64 1) "age"),
          ("score", u64 100)
        ])
        (.structLit "Person" #[
          ("age", personGridField "grid" (u64 0) (u64 0) "age"),
          ("score", u64 200)
        ])
        (.structLit "Person" #[
          ("age", personGridField "grid" (u64 0) (u64 1) "age"),
          ("score", u64 300)
        ])
        (.structLit "Person" #[
          ("age", personGridField "grid" (u64 1) (u64 0) "age"),
          ("score", u64 400)
        ])),
    .return (.add
      (personGridField "grid" (u64 0) (u64 0) "age")
      (personGridField "grid" (u64 0) (u64 1) "age"))
  ]
}

def module : Module := {
  name := "EvmStructArrayValueProbe"
  structs := #[personStruct, mixedStruct]
  state := #[]
  entrypoints := #[
    localStructArraySum,
    dynamicStructArrayPick,
    mutableStructArrayUpdate,
    staticStructArrayUpdate,
    mixedStructArrayFields,
    wholeStructArrayAssign,
    selfStructArrayAssign,
    nestedStructArraySum,
    nestedStructArrayDynamicPick,
    nestedStructArrayUpdate,
    nestedStructArrayWholeAssign,
    nestedStructArraySelfAssign
  ]
}

end ProofForge.IR.Examples.EvmStructArrayValueProbe
