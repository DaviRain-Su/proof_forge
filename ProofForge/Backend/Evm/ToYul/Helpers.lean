import ProofForge.Backend.Evm.Names
import ProofForge.Backend.Evm.Plan
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def helperCall (helper : Helper) (args : Array Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call helper.name args

def checkedAddName : String := "__pf_checked_add"
def checkedSubName : String := "__pf_checked_sub"
def checkedMulName : String := "__pf_checked_mul"

def checkedArithExpr (op : AssignOp) (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  match op with
  | .add => Lean.Compiler.Yul.call checkedAddName #[lhs, rhs]
  | .sub => Lean.Compiler.Yul.call checkedSubName #[lhs, rhs]
  | .mul => Lean.Compiler.Yul.call checkedMulName #[lhs, rhs]
  | .div => Lean.Compiler.Yul.builtin "div" #[lhs, rhs]
  | .mod => Lean.Compiler.Yul.builtin "mod" #[lhs, rhs]
  | .bitAnd => Lean.Compiler.Yul.builtin "and" #[lhs, rhs]
  | .bitOr => Lean.Compiler.Yul.builtin "or" #[lhs, rhs]
  | .bitXor => Lean.Compiler.Yul.builtin "xor" #[lhs, rhs]
  | .shiftLeft => Lean.Compiler.Yul.builtin "shl" #[rhs, lhs]
  | .shiftRight => Lean.Compiler.Yul.builtin "shr" #[rhs, lhs]

/-- The 2^256 - 1 max word value, used for overflow checks. -/
def maxUint256 : Nat := 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

-- ASCII "PROOF_FORGE_MAP_PRESENCE" packed as one EVM word.
def mapPresenceDomain : Nat := 1969478005224772198022937154314036040895674356107534287685

/-- Statement that reverts if `cond` is nonzero (truthy). -/
def revertIfStatement (cond : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Statement :=
  Lean.Compiler.Yul.Statement.ifStmt cond {
    statements := #[
      Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
    ]
  }

/-- Checked-arithmetic Yul helper definitions emitted once per module.
    Mirrors Solidity 0.8 semantics: add/mul revert on U256 overflow and sub
    reverts on underflow. -/
def checkedArithmeticHelperFunctions : Array Lean.Compiler.Yul.Statement :=
  let tn (n : String) := { name := n : Lean.Compiler.Yul.TypedName }
  #[
    Lean.Compiler.Yul.Statement.funcDef checkedAddName #[tn "a", tn "b"] #[tn "r"]
      { statements := #[
        revertIfStatement (Lean.Compiler.Yul.builtin "gt" #[
          Lean.Compiler.Yul.Expr.id "a",
          Lean.Compiler.Yul.builtin "sub" #[Lean.Compiler.Yul.Expr.num maxUint256, Lean.Compiler.Yul.Expr.id "b"]
        ]),
        Lean.Compiler.Yul.Statement.assignment #["r"]
          (Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "a", Lean.Compiler.Yul.Expr.id "b"])
      ] },
    Lean.Compiler.Yul.Statement.funcDef checkedSubName #[tn "a", tn "b"] #[tn "r"]
      { statements := #[
        revertIfStatement (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id "b", Lean.Compiler.Yul.Expr.id "a"]),
        Lean.Compiler.Yul.Statement.assignment #["r"]
          (Lean.Compiler.Yul.builtin "sub" #[Lean.Compiler.Yul.Expr.id "a", Lean.Compiler.Yul.Expr.id "b"])
      ] },
    Lean.Compiler.Yul.Statement.funcDef checkedMulName #[tn "a", tn "b"] #[tn "r"]
      { statements := #[
        Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "a"])
          { statements := #[
            Lean.Compiler.Yul.Statement.assignment #["r"] (Lean.Compiler.Yul.Expr.num 0),
            Lean.Compiler.Yul.Statement.leave
          ] },
        revertIfStatement (Lean.Compiler.Yul.builtin "gt" #[
          Lean.Compiler.Yul.Expr.id "a",
          Lean.Compiler.Yul.builtin "div" #[Lean.Compiler.Yul.Expr.num maxUint256, Lean.Compiler.Yul.Expr.id "b"]
        ]),
        Lean.Compiler.Yul.Statement.assignment #["r"]
          (Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "a", Lean.Compiler.Yul.Expr.id "b"])
      ] }
  ]

def hashWordHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.hashWord).name
    #[{ name := "value" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "value"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 32])
      ]
    }

def hashPairHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.hashPair).name
    #[{ name := "left" }, { name := "right" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "left"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "right"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])
      ]
    }

def hashHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  hashWordHelperFunction,
  hashPairHelperFunction
]

def arrayHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef (Helper.arraySlot).name
    #[{ name := "slot" }, { name := "length" }, { name := "index" }]
    #[{ name := "result" }]
    {
      statements := #[
        revertIfStatement
          (Lean.Compiler.Yul.builtin "iszero" #[
            Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.id "length"]
          ]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "index"])
      ]
    }
]

def dynamicArrayHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef (Helper.dynamicArraySlot).name
    #[{ name := "slot" }, { name := "index" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "slot"]),
        .assignment #["result"]
          (Lean.Compiler.Yul.builtin "add" #[
            Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 32],
            Lean.Compiler.Yul.Expr.id "index"
          ])
      ]
    }
]

def memoryArrayNewHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.memoryArrayNew).name
    #[{ name := "length" }]
    #[{ name := "ptr" }]
    {
      statements := #[
        .assignment #["ptr"] (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 64]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.id "ptr", Lean.Compiler.Yul.Expr.id "length"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 64,
          Lean.Compiler.Yul.builtin "add" #[
            Lean.Compiler.Yul.Expr.id "ptr",
            Lean.Compiler.Yul.builtin "mul" #[
              Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "length", Lean.Compiler.Yul.Expr.num 1],
              Lean.Compiler.Yul.Expr.num 32
            ]
          ]
        ])
      ]
    }

def memoryArrayGetHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.memoryArrayGet).name
    #[{ name := "array" }, { name := "index" }]
    #[{ name := "value" }]
    {
      statements := #[
        revertIfStatement
          (Lean.Compiler.Yul.builtin "iszero" #[
            Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.id "array"]]
          ]),
        .assignment #["value"]
          (Lean.Compiler.Yul.builtin "mload" #[
            Lean.Compiler.Yul.builtin "add" #[
              Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "array", Lean.Compiler.Yul.Expr.num 32],
              Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.num 32]
            ]
          ])
      ]
    }

def memoryArrayHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  memoryArrayNewHelperFunction,
  memoryArrayGetHelperFunction
]

def structArrayHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  .funcDef (Helper.structArraySlot).name
    #[
      { name := "slot" },
      { name := "length" },
      { name := "field_count" },
      { name := "field_offset" },
      { name := "index" }
    ]
    #[{ name := "result" }]
    {
      statements := #[
        revertIfStatement
          (Lean.Compiler.Yul.builtin "iszero" #[
            Lean.Compiler.Yul.builtin "lt" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.id "length"]
          ]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "add" #[
          Lean.Compiler.Yul.builtin "add" #[
            Lean.Compiler.Yul.Expr.id "slot",
            Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "index", Lean.Compiler.Yul.Expr.id "field_count"]
          ],
          Lean.Compiler.Yul.Expr.id "field_offset"
        ])
      ]
    }
]

def mapSlotHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.mapSlot).name
    #[{ name := "slot" }, { name := "key" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "key"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "slot"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])
      ]
    }

def mapPresenceSlotHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.mapPresenceSlot).name
    #[{ name := "slot" }, { name := "key" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "slot"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.num mapPresenceDomain]),
        .varDecl #[{ name := "_presence_slot" }]
          (some (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "key"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "_presence_slot"]),
        .assignment #["result"] (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 64])
      ]
    }

def mapWriteHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.mapWrite).name
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (helperCall Helper.mapSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[Lean.Compiler.Yul.Expr.id "_slot", Lean.Compiler.Yul.Expr.id "value"]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.mapPresenceSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    }

def mapSetReturnHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.mapSetReturn).name
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[{ name := "old" }]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (helperCall Helper.mapSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .assignment #["old"] (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[Lean.Compiler.Yul.Expr.id "_slot", Lean.Compiler.Yul.Expr.id "value"]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.mapPresenceSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    }

def mapBaseHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  mapSlotHelperFunction,
  mapPresenceSlotHelperFunction,
  mapWriteHelperFunction,
  mapSetReturnHelperFunction
]

def mapAssignHelperFunction (op : AssignOp) : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.mapAssign op).name
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (helperCall Helper.mapSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.Expr.id "_slot",
          checkedArithExpr op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (Lean.Compiler.Yul.Expr.id "value")
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.mapPresenceSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    }

def mapHelperFunctions (assignOps : Array AssignOp) : Array Lean.Compiler.Yul.Statement :=
  mapBaseHelperFunctions ++ assignOps.map mapAssignHelperFunction

end ProofForge.Backend.Evm.ToYul
