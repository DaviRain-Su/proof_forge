import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmArrayValueProbe

open ProofForge.IR

def u32 (value : Nat) : Expr :=
  .literal (.u32 value)

def u64 (value : Nat) : Expr :=
  .literal (.u64 value)

def bool (value : Bool) : Expr :=
  .literal (.bool value)

def hash (a b c d : Nat) : Expr :=
  .literal (.hash4 a b c d)

def localSum : Entrypoint := {
  name := "local_sum"
  selector? := some "77bd09b1"
  returns := .u64
  body := #[
    .letBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[u64 7, u64 11, u64 13]),
    .letBind "head" .u64 (.arrayGet (.local "xs") (u64 0)),
    .return (.add (.local "head") (.arrayGet (.local "xs") (u64 2)))
  ]
}

def directLiteralIndex : Entrypoint := {
  name := "direct_literal_index"
  selector? := some "7389a736"
  returns := .u64
  body := #[
    .return (.arrayGet (.arrayLit .u64 #[u64 4, u64 6, u64 8]) (u64 1))
  ]
}

def boolGuard : Entrypoint := {
  name := "bool_guard"
  selector? := some "7c95ba13"
  returns := .bool
  body := #[
    .letBind "flags" (.fixedArray .bool 2) (.arrayLit .bool #[bool false, bool true]),
    .assert (.arrayGet (.local "flags") (u64 1)) "fixed array bool guard must be true",
    .return (.arrayGet (.local "flags") (u64 0))
  ]
}

def u32Pick : Entrypoint := {
  name := "u32_pick"
  selector? := some "a13f4ee0"
  returns := .u32
  body := #[
    .letBind "smalls" (.fixedArray .u32 2) (.arrayLit .u32 #[u32 3, u32 5]),
    .return (.arrayGet (.local "smalls") (u32 1))
  ]
}

def hashPick : Entrypoint := {
  name := "hash_pick"
  selector? := some "211a2fc4"
  returns := .hash
  body := #[
    .letBind "roots" (.fixedArray .hash 2) (.arrayLit .hash #[hash 1 2 3 4, hash 5 6 7 8]),
    .return (.arrayGet (.local "roots") (u64 0))
  ]
}

def mutableUpdate : Entrypoint := {
  name := "mutable_update"
  selector? := some "0cde63a1"
  returns := .u64
  body := #[
    .letMutBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[u64 7, u64 11, u64 13]),
    .assign (.arrayGet (.local "xs") (u64 1)) (u64 19),
    .assignOp (.arrayGet (.local "xs") (u64 2)) .add (u64 5),
    .return (.add (.arrayGet (.local "xs") (u64 1)) (.arrayGet (.local "xs") (u64 2)))
  ]
}

def mutableMixed : Entrypoint := {
  name := "mutable_mixed"
  selector? := some "70d82dc9"
  returns := .u64
  body := #[
    .letMutBind "flags" (.fixedArray .bool 2) (.arrayLit .bool #[bool false, bool false]),
    .assign (.arrayGet (.local "flags") (u64 0)) (bool true),
    .assert (.arrayGet (.local "flags") (u64 0)) "mutable bool element must be true",
    .letMutBind "smalls" (.fixedArray .u32 2) (.arrayLit .u32 #[u32 3, u32 5]),
    .assign (.arrayGet (.local "smalls") (u64 1)) (u32 9),
    .letMutBind "roots" (.fixedArray .hash 2) (.arrayLit .hash #[hash 1 2 3 4, hash 5 6 7 8]),
    .assign (.arrayGet (.local "roots") (u64 1)) (hash 9 10 11 12),
    .assertEq (.arrayGet (.local "roots") (u64 1)) (hash 9 10 11 12) "mutable hash element must update",
    .return (.add (.cast (.arrayGet (.local "flags") (u64 0)) .u64) (.cast (.arrayGet (.local "smalls") (u64 1)) .u64))
  ]
}

def dynamicPick : Entrypoint := {
  name := "dynamic_pick"
  selector? := some "17e4f54c"
  params := #[
    ("idx", .u64)
  ]
  returns := .u64
  body := #[
    .letBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[u64 7, u64 11, u64 13]),
    .return (.add
      (.arrayGet (.local "xs") (.local "idx"))
      (.arrayGet (.arrayLit .u64 #[u64 4, u64 6, u64 8]) (.local "idx")))
  ]
}

def dynamicUpdate : Entrypoint := {
  name := "dynamic_update"
  selector? := some "f45e18ed"
  params := #[
    ("idx", .u64)
  ]
  returns := .u64
  body := #[
    .letMutBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[u64 7, u64 11, u64 13]),
    .assign (.arrayGet (.local "xs") (.local "idx")) (u64 20),
    .assignOp (.arrayGet (.local "xs") (.local "idx")) .add (u64 3),
    .return (.arrayGet (.local "xs") (.local "idx"))
  ]
}

def wholeArrayAssign : Entrypoint := {
  name := "whole_array_assign"
  selector? := some "d59d3191"
  returns := .u64
  body := #[
    .letMutBind "xs" (.fixedArray .u64 3) (.arrayLit .u64 #[u64 1, u64 2, u64 3]),
    .letBind "ys" (.fixedArray .u64 3) (.arrayLit .u64 #[u64 7, u64 11, u64 13]),
    .assign (.local "xs") (.local "ys"),
    .assign (.local "xs") (.arrayLit .u64 #[
      .arrayGet (.local "xs") (u64 1),
      .arrayGet (.local "xs") (u64 0),
      .arrayGet (.local "xs") (u64 2)
    ]),
    .return (.add
      (.add (.arrayGet (.local "xs") (u64 0)) (.mul (.arrayGet (.local "xs") (u64 1)) (u64 10)))
      (.arrayGet (.local "xs") (u64 2)))
  ]
}

def nestedLocalSum : Entrypoint := {
  name := "nested_local_sum"
  selector? := some "c54814ec"
  returns := .u64
  body := #[
    .letBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 2, u64 3],
      .arrayLit .u64 #[u64 5, u64 7]
    ]),
    .return (.add
      (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 1))
      (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 0)))
  ]
}

def nestedMutableUpdate : Entrypoint := {
  name := "nested_mutable_update"
  selector? := some "69c5b925"
  returns := .u64
  body := #[
    .letMutBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 2, u64 3],
      .arrayLit .u64 #[u64 5, u64 7]
    ]),
    .assign (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 0)) (u64 17),
    .assignOp (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 1)) .add (u64 4),
    .return (.add
      (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 0))
      (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 1)))
  ]
}

def nestedWholeArrayAssign : Entrypoint := {
  name := "nested_whole_array_assign"
  selector? := some "1c21ce7e"
  returns := .u64
  body := #[
    .letMutBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 1, u64 2],
      .arrayLit .u64 #[u64 3, u64 4]
    ]),
    .letBind "other" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 5, u64 7],
      .arrayLit .u64 #[u64 11, u64 13]
    ]),
    .assign (.local "matrix") (.local "other"),
    .assign (.local "matrix") (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[
        .arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 0),
        .arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 1)
      ],
      .arrayLit .u64 #[
        .arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 0),
        .arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 1)
      ]
    ]),
    .return (.add
      (.add
        (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 0))
        (.mul (.arrayGet (.arrayGet (.local "matrix") (u64 0)) (u64 1)) (u64 10)))
      (.add
        (.mul (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 0)) (u64 100))
        (.mul (.arrayGet (.arrayGet (.local "matrix") (u64 1)) (u64 1)) (u64 1000))))
  ]
}

def nestedDynamicPick : Entrypoint := {
  name := "nested_dynamic_pick"
  selector? := some "deb5ba01"
  params := #[
    ("row", .u64),
    ("col", .u64)
  ]
  returns := .u64
  body := #[
    .letBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 2, u64 3],
      .arrayLit .u64 #[u64 5, u64 7]
    ]),
    .return (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (.local "col"))
  ]
}

def nestedDynamicRowPick : Entrypoint := {
  name := "nested_dynamic_row_pick"
  selector? := some "731f5daf"
  params := #[
    ("row", .u64)
  ]
  returns := .u64
  body := #[
    .letBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 2, u64 3],
      .arrayLit .u64 #[u64 5, u64 7]
    ]),
    .return (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (u64 1))
  ]
}

def nestedDynamicUpdate : Entrypoint := {
  name := "nested_dynamic_update"
  selector? := some "bd33c419"
  params := #[
    ("row", .u64),
    ("col", .u64)
  ]
  returns := .u64
  body := #[
    .letMutBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 2, u64 3],
      .arrayLit .u64 #[u64 5, u64 7]
    ]),
    .assign (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (.local "col")) (u64 20),
    .assignOp (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (.local "col")) .add (u64 3),
    .return (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (.local "col"))
  ]
}

def nestedDynamicRowUpdate : Entrypoint := {
  name := "nested_dynamic_row_update"
  selector? := some "69437a57"
  params := #[
    ("row", .u64)
  ]
  returns := .u64
  body := #[
    .letMutBind "matrix" (.fixedArray (.fixedArray .u64 2) 2) (.arrayLit (.fixedArray .u64 2) #[
      .arrayLit .u64 #[u64 2, u64 3],
      .arrayLit .u64 #[u64 5, u64 7]
    ]),
    .assign (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (u64 1)) (u64 20),
    .assignOp (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (u64 1)) .add (u64 3),
    .return (.arrayGet (.arrayGet (.local "matrix") (.local "row")) (u64 1))
  ]
}

def module : Module := {
  name := "EvmArrayValueProbe"
  state := #[]
  entrypoints := #[
    localSum,
    directLiteralIndex,
    boolGuard,
    u32Pick,
    hashPick,
    mutableUpdate,
    mutableMixed,
    dynamicPick,
    dynamicUpdate,
    wholeArrayAssign,
    nestedLocalSum,
    nestedMutableUpdate,
    nestedWholeArrayAssign,
    nestedDynamicPick,
    nestedDynamicRowPick,
    nestedDynamicUpdate,
    nestedDynamicRowUpdate
  ]
}

end ProofForge.IR.Examples.EvmArrayValueProbe
