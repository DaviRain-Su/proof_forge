import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.EvmStructValueProbe

open ProofForge.IR

def pointStruct : StructDecl := {
  name := "Point"
  fields := #[
    { id := "x", type := .u64 },
    { id := "y", type := .u64 }
  ]
}

def flagsStruct : StructDecl := {
  name := "Flags"
  fields := #[
    { id := "enabled", type := .bool },
    { id := "archived", type := .bool }
  ]
}

def smallStruct : StructDecl := {
  name := "Small"
  fields := #[
    { id := "a", type := .u32 },
    { id := "b", type := .u32 }
  ]
}

def rootsStruct : StructDecl := {
  name := "Roots"
  fields := #[
    { id := "root", type := .hash },
    { id := "next", type := .hash }
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

def point (x y : Nat) : Expr :=
  .structLit "Point" #[
    ("x", u64 x),
    ("y", u64 y)
  ]

def flags (enabled archived : Bool) : Expr :=
  .structLit "Flags" #[
    ("enabled", bool enabled),
    ("archived", bool archived)
  ]

def small (a b : Nat) : Expr :=
  .structLit "Small" #[
    ("a", u32 a),
    ("b", u32 b)
  ]

def roots (root next : Expr) : Expr :=
  .structLit "Roots" #[
    ("root", root),
    ("next", next)
  ]

def localSum : Entrypoint := {
  name := "local_sum"
  selector? := some "77bd09b1"
  returns := .u64
  body := #[
    .letBind "p" (.structType "Point") (point 7 13),
    .letBind "head" .u64 (.field (.local "p") "x"),
    .return (.add (.local "head") (.field (.local "p") "y"))
  ]
}

def directLiteralField : Entrypoint := {
  name := "direct_literal_field"
  selector? := some "25e7fc3e"
  returns := .u64
  body := #[
    .return (.field (point 4 6) "y")
  ]
}

def boolGuard : Entrypoint := {
  name := "bool_guard"
  selector? := some "7c95ba13"
  returns := .bool
  body := #[
    .letBind "flags" (.structType "Flags") (flags true false),
    .assert (.field (.local "flags") "enabled") "struct bool guard must be true",
    .return (.field (.local "flags") "archived")
  ]
}

def u32Pick : Entrypoint := {
  name := "u32_pick"
  selector? := some "a13f4ee0"
  returns := .u32
  body := #[
    .letBind "small" (.structType "Small") (small 3 5),
    .return (.field (.local "small") "b")
  ]
}

def hashPick : Entrypoint := {
  name := "hash_pick"
  selector? := some "211a2fc4"
  returns := .hash
  body := #[
    .letBind "roots" (.structType "Roots") (roots (hash 1 2 3 4) (hash 5 6 7 8)),
    .return (.field (.local "roots") "root")
  ]
}

def mutablePointUpdate : Entrypoint := {
  name := "mutable_point_update"
  selector? := some "c7096012"
  returns := .u64
  body := #[
    .letMutBind "p" (.structType "Point") (point 7 13),
    .assign (.field (.local "p") "x") (u64 9),
    .assignOp (.field (.local "p") "y") .add (u64 5),
    .return (.add (.field (.local "p") "x") (.field (.local "p") "y"))
  ]
}

def mutableMixedFields : Entrypoint := {
  name := "mutable_mixed_fields"
  selector? := some "b18f76a4"
  returns := .u64
  body := #[
    .letMutBind "flags" (.structType "Flags") (flags false false),
    .assign (.field (.local "flags") "enabled") (bool true),
    .assert (.field (.local "flags") "enabled") "mutable bool field must be true",
    .letMutBind "small" (.structType "Small") (small 3 5),
    .assign (.field (.local "small") "b") (u32 9),
    .letMutBind "roots" (.structType "Roots") (roots (hash 1 2 3 4) (hash 5 6 7 8)),
    .assign (.field (.local "roots") "next") (hash 9 10 11 12),
    .assertEq (.field (.local "roots") "next") (hash 9 10 11 12) "mutable hash field must update",
    .return (.add (.cast (.field (.local "flags") "enabled") .u64) (.cast (.field (.local "small") "b") .u64))
  ]
}

def wholeStructAssign : Entrypoint := {
  name := "whole_struct_assign"
  selector? := some "b416b147"
  returns := .u64
  body := #[
    .letMutBind "p" (.structType "Point") (point 1 2),
    .letBind "q" (.structType "Point") (point 7 11),
    .assign (.local "p") (.local "q"),
    .assign (.local "p") (.structLit "Point" #[
      ("x", .field (.local "p") "y"),
      ("y", .field (.local "p") "x")
    ]),
    .return (.add (.field (.local "p") "x") (.mul (.field (.local "p") "y") (u64 10)))
  ]
}

def module : Module := {
  name := "EvmStructValueProbe"
  structs := #[pointStruct, flagsStruct, smallStruct, rootsStruct]
  state := #[]
  entrypoints := #[localSum, directLiteralField, boolGuard, u32Pick, hashPick, mutablePointUpdate, mutableMixedFields, wholeStructAssign]
}

end ProofForge.IR.Examples.EvmStructValueProbe
