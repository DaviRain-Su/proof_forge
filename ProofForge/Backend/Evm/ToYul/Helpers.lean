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
def checkedWidthName : String := "__pf_checked_width"

/-- Arithmetic lowering for an `AssignOp`. When `overflowChecked` is true,
add/sub/mul lower to checked-revert helpers (Solidity 0.8 semantics); when
false they lower to wrapping Yul builtins (matching Solana sBPF and NEAR Wasm
native behavior). This is the single point that honors `Module.overflowChecked`
in the EVM lowering — see `docs/formal-verification.md` FV-5 and
Track 0.1 in `docs/zh/execution-plan-2026-07.md`. -/
def arithExpr (overflowChecked : Bool) (op : AssignOp)
    (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  match op with
  | .add => if overflowChecked then Lean.Compiler.Yul.call checkedAddName #[lhs, rhs]
           else Lean.Compiler.Yul.builtin "add" #[lhs, rhs]
  | .sub => if overflowChecked then Lean.Compiler.Yul.call checkedSubName #[lhs, rhs]
           else Lean.Compiler.Yul.builtin "sub" #[lhs, rhs]
  | .mul => if overflowChecked then Lean.Compiler.Yul.call checkedMulName #[lhs, rhs]
           else Lean.Compiler.Yul.builtin "mul" #[lhs, rhs]
  | .div => Lean.Compiler.Yul.builtin "div" #[lhs, rhs]
  | .mod => Lean.Compiler.Yul.builtin "mod" #[lhs, rhs]
  | .bitAnd => Lean.Compiler.Yul.builtin "and" #[lhs, rhs]
  | .bitOr => Lean.Compiler.Yul.builtin "or" #[lhs, rhs]
  | .bitXor => Lean.Compiler.Yul.builtin "xor" #[lhs, rhs]
  | .shiftLeft => Lean.Compiler.Yul.builtin "shl" #[rhs, lhs]
  | .shiftRight => Lean.Compiler.Yul.builtin "shr" #[rhs, lhs]

/-- Legacy checked-only alias; prefer `arithExpr` so the overflow mode is explicit. -/
def checkedArithExpr (op : AssignOp) (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  arithExpr true op lhs rhs

/-- Arithmetic for a typed narrow integer node inside a packed scalar write.

Checked nodes validate both operands and the result at the node's own width.
Wrapping nodes reduce the result modulo that width. -/
def narrowArithExpr
    (overflowChecked : Bool)
    (op : AssignOp)
    (byteWidth : Nat)
    (lhs rhs : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  match op with
  | .add | .sub | .mul =>
      let mask := Lean.Compiler.Yul.Expr.num ((2 ^ (byteWidth * 8)) - 1)
      if overflowChecked then
        let bound (value : Lean.Compiler.Yul.Expr) :=
          Lean.Compiler.Yul.call checkedWidthName #[value, mask]
        bound (arithExpr true op (bound lhs) (bound rhs))
      else
        Lean.Compiler.Yul.builtin "and" #[arithExpr false op lhs rhs, mask]
  | .div | .mod | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight =>
      arithExpr overflowChecked op lhs rhs

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

/-- Runtime width assertion shared by typed narrow checked-arithmetic nodes. -/
def checkedWidthHelperFunction : Lean.Compiler.Yul.Statement :=
  let tn (n : String) := { name := n : Lean.Compiler.Yul.TypedName }
  Lean.Compiler.Yul.Statement.funcDef checkedWidthName
    #[tn "value", tn "maxValue"]
    #[tn "result"]
    { statements := #[
        revertIfStatement (Lean.Compiler.Yul.builtin "gt" #[
          Lean.Compiler.Yul.Expr.id "value",
          Lean.Compiler.Yul.Expr.id "maxValue"
        ]),
        Lean.Compiler.Yul.Statement.assignment #["result"]
          (Lean.Compiler.Yul.Expr.id "value")
      ] }

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
        Lean.Compiler.Yul.Statement.ifStmt (Lean.Compiler.Yul.builtin "or" #[
          Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "a"],
          Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "b"]
        ])
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

/-- secp256k1 recovery via precompile address 1 (portable across solc dialects
that omit the `ecrecover` Yul builtin). Returns address word, or 0 on failure. -/
def ecrecoverHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.ecrecover).name
    #[{ name := "digest" }, { name := "v" }, { name := "r" }, { name := "s" }]
    #[{ name := "result" }]
    {
      statements := #[
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.id "digest"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "v"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.id "r"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 96, Lean.Compiler.Yul.Expr.id "s"]),
        .varDecl #[{ name := "_ok" }] (some <|
          Lean.Compiler.Yul.builtin "staticcall" #[
            Lean.Compiler.Yul.builtin "gas" #[],
            Lean.Compiler.Yul.Expr.num 1,
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.Expr.num 128,
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.Expr.num 32
          ]),
        .assignment #["result"]
          (Lean.Compiler.Yul.builtin "mul" #[
            Lean.Compiler.Yul.Expr.id "_ok",
            Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0]
          ])
      ]
    }

/-- EIP-712 permit digest (domainSeparator + Permit typehash struct).
Scratch memory at 0..192; free-memory pointer left unchanged (callers must not
rely on MSIZE between helper calls). -/
def eip712PermitDigestHelperFunction : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.eip712PermitDigest).name
    #[{ name := "owner" }, { name := "spender" }, { name := "value" },
      { name := "nonce" }, { name := "deadline" }, { name := "domainSeparator" }]
    #[{ name := "digest" }]
    {
      statements := #[
        -- PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "owner"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.id "spender"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 96, Lean.Compiler.Yul.Expr.id "value"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 128, Lean.Compiler.Yul.Expr.id "nonce"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 160, Lean.Compiler.Yul.Expr.id "deadline"]),
        .assignment #["digest"]
          (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 192]),
        -- "\x19\x01" ‖ domainSeparator ‖ structHash
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num 0x1901000000000000000000000000000000000000000000000000000000000000
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "domainSeparator"]),
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.id "digest"]),
        .assignment #["digest"]
          (Lean.Compiler.Yul.builtin "keccak256" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 66])
      ]
    }

def hashHelperFunctions : Array Lean.Compiler.Yul.Statement := #[
  hashWordHelperFunction,
  hashPairHelperFunction,
  ecrecoverHelperFunction,
  eip712PermitDigestHelperFunction
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

def mapAssignHelperFunction (overflowChecked : Bool) (op : AssignOp) : Lean.Compiler.Yul.Statement :=
  .funcDef (Helper.mapAssign op).name
    #[{ name := "slot" }, { name := "key" }, { name := "value" }]
    #[]
    {
      statements := #[
        .varDecl #[{ name := "_slot" }] (some (helperCall Helper.mapSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          Lean.Compiler.Yul.Expr.id "_slot",
          arithExpr overflowChecked op (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"]) (Lean.Compiler.Yul.Expr.id "value")
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.mapPresenceSlot #[Lean.Compiler.Yul.Expr.id "slot", Lean.Compiler.Yul.Expr.id "key"],
          Lean.Compiler.Yul.Expr.num 1
        ])
      ]
    }

def mapHelperFunctions (overflowChecked : Bool) (assignOps : Array AssignOp) : Array Lean.Compiler.Yul.Statement :=
  mapBaseHelperFunctions ++ assignOps.map (mapAssignHelperFunction overflowChecked)

end ProofForge.Backend.Evm.ToYul
