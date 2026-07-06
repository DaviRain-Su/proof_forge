import ProofForge.Backend.Evm.Plan
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def slotExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.num slot

def helperCall (helper : Helper) (args : Array Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call helper.name args

def entrypointFunctionName (moduleName entrypointName : String) : String :=
  s!"f_{moduleName}_{entrypointName}"

def entrypointPlanFunctionName (moduleName : String) (entrypoint : EntrypointPlan) : String :=
  entrypointFunctionName moduleName entrypoint.name

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

def contextFieldExpr
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    ContextField → Except ε Lean.Compiler.Yul.Expr
  | .userId => .ok (Lean.Compiler.Yul.builtin "caller" #[])
  | .contractId => .ok (Lean.Compiler.Yul.builtin "address" #[])
  | .checkpointId => .ok (Lean.Compiler.Yul.builtin "number" #[])
  | .timestamp => .ok (Lean.Compiler.Yul.builtin "timestamp" #[])
  | .chainId => .ok (Lean.Compiler.Yul.builtin "chainid" #[])
  | .gasPrice => .ok (Lean.Compiler.Yul.builtin "gasprice" #[])
  | .gasLeft => .ok (Lean.Compiler.Yul.builtin "gas" #[])
  | .baseFee => .ok (Lean.Compiler.Yul.builtin "basefee" #[])
  | .prevRandao => .ok (Lean.Compiler.Yul.builtin "prevrandao" #[])
  | .origin => .ok (Lean.Compiler.Yul.builtin "origin" #[])
  | .coinbase => .ok (Lean.Compiler.Yul.builtin "coinbase" #[])
  | .blockHash blockNumber => do
      .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerExpr blockNumber])

partial def contextExprPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    ContextExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .userId => .ok (Lean.Compiler.Yul.builtin "caller" #[])
  | .contractId => .ok (Lean.Compiler.Yul.builtin "address" #[])
  | .checkpointId => .ok (Lean.Compiler.Yul.builtin "number" #[])
  | .timestamp => .ok (Lean.Compiler.Yul.builtin "timestamp" #[])
  | .chainId => .ok (Lean.Compiler.Yul.builtin "chainid" #[])
  | .gasPrice => .ok (Lean.Compiler.Yul.builtin "gasprice" #[])
  | .gasLeft => .ok (Lean.Compiler.Yul.builtin "gas" #[])
  | .baseFee => .ok (Lean.Compiler.Yul.builtin "basefee" #[])
  | .prevRandao => .ok (Lean.Compiler.Yul.builtin "prevrandao" #[])
  | .origin => .ok (Lean.Compiler.Yul.builtin "origin" #[])
  | .coinbase => .ok (Lean.Compiler.Yul.builtin "coinbase" #[])
  | .blockHash blockNumber => do
      .ok (Lean.Compiler.Yul.builtin "blockhash" #[← lowerPlanExpr blockNumber])

def calldataWordExpr (paramIndex : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num (4 + paramIndex * 32)]

def arrayLocalElementName (name : String) (index : Nat) : String :=
  s!"__proof_forge_array_{name}_{index}"

def natPathSuffix (path : Array Nat) : String :=
  Id.run do
    let mut suffix := ""
    for h : idx in [0:path.size] do
      let part := toString path[idx]
      suffix := if idx == 0 then part else s!"{suffix}_{part}"
    suffix

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  match path.toList with
  | [index] => arrayLocalElementName name index
  | _ => s!"__proof_forge_array_{name}_{natPathSuffix path}"

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_array_struct_{name}_{index}_{fieldName}"

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  match path.toList with
  | [index] => arrayStructLocalFieldName name index fieldName
  | _ => s!"__proof_forge_array_struct_{name}_{natPathSuffix path}_{fieldName}"

def structLocalFieldName (name fieldName : String) : String :=
  s!"__proof_forge_struct_{name}_{fieldName}"

def localArrayGetFunctionName (length : Nat) : String :=
  s!"__proof_forge_local_array_get_{length}"

def nestedLocalArrayGetFunctionName (lengths : Array Nat) : String :=
  s!"__proof_forge_local_array_get_nested_{natPathSuffix lengths}"

def localArrayGetValueParamName (index : Nat) : String :=
  s!"value_{index}"

def localArrayGetIndexParamName (index : Nat) : String :=
  s!"index_{index}"

def localArrayGetPathValueParamName (path : Array Nat) : String :=
  s!"value_{natPathSuffix path}"

partial def nestedLocalArrayLeafPaths (lengths : Array Nat) : Array (Array Nat) :=
  match lengths.toList with
  | [] => #[#[]]
  | length :: rest =>
      let nested := nestedLocalArrayLeafPaths rest.toArray
      Id.run do
        let mut paths : Array (Array Nat) := #[]
        for _h : idx in [0:length] do
          for tail in nested do
            paths := paths.push (#[idx] ++ tail)
        paths

def localArrayGetFunctionParams (length : Nat) : Array Lean.Compiler.Yul.TypedName :=
  Id.run do
    let mut params : Array Lean.Compiler.Yul.TypedName := #[{ name := "index" }]
    for _h : idx in [0:length] do
      params := params.push { name := localArrayGetValueParamName idx }
    params

def localArrayGetSwitchCases (length : Nat) : Array Lean.Compiler.Yul.Case :=
  Id.run do
    let mut cases : Array Lean.Compiler.Yul.Case := #[]
    for _h : idx in [0:length] do
      cases := cases.push {
        value := some (Lean.Compiler.Yul.Literal.natLit idx)
        body := {
          statements := #[
            .assignment #["result"] (Lean.Compiler.Yul.Expr.id (localArrayGetValueParamName idx))
          ]
        }
      }
    cases.push {
      value := none
      body := {
        statements := #[
          .exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
        ]
      }
    }

def localArrayGetHelperFunction (length : Nat) : Lean.Compiler.Yul.Statement :=
  .funcDef (localArrayGetFunctionName length)
    (localArrayGetFunctionParams length)
    #[{ name := "result" }]
    {
      statements := #[
        .switchStmt (Lean.Compiler.Yul.Expr.id "index") (localArrayGetSwitchCases length)
      ]
    }

def localArrayGetHelperFunctions (lengths : Array Nat) : Array Lean.Compiler.Yul.Statement :=
  lengths.map localArrayGetHelperFunction

def nestedLocalArrayGetFunctionParams (lengths : Array Nat) : Array Lean.Compiler.Yul.TypedName :=
  Id.run do
    let mut params : Array Lean.Compiler.Yul.TypedName := #[]
    for _h : idx in [0:lengths.size] do
      params := params.push { name := localArrayGetIndexParamName idx }
    for path in nestedLocalArrayLeafPaths lengths do
      params := params.push { name := localArrayGetPathValueParamName path }
    params

partial def nestedLocalArrayGetSwitchStatements
    (lengths : Array Nat)
    (depth : Nat)
    (path : Array Nat) : Array Lean.Compiler.Yul.Statement :=
  match lengths.toList with
  | [] =>
      #[.assignment #["result"] (Lean.Compiler.Yul.Expr.id (localArrayGetPathValueParamName path))]
  | length :: rest =>
      let cases := Id.run do
        let mut cases : Array Lean.Compiler.Yul.Case := #[]
        for _h : idx in [0:length] do
          cases := cases.push {
            value := some (Lean.Compiler.Yul.Literal.natLit idx)
            body := {
              statements := nestedLocalArrayGetSwitchStatements rest.toArray (depth + 1) (path.push idx)
            }
          }
        cases.push {
          value := none
          body := {
            statements := #[
              .exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
            ]
          }
        }
      #[.switchStmt (Lean.Compiler.Yul.Expr.id (localArrayGetIndexParamName depth)) cases]

def nestedLocalArrayGetHelperFunction (lengths : Array Nat) : Lean.Compiler.Yul.Statement :=
  .funcDef (nestedLocalArrayGetFunctionName lengths)
    (nestedLocalArrayGetFunctionParams lengths)
    #[{ name := "result" }]
    { statements := nestedLocalArrayGetSwitchStatements lengths 0 #[] }

def nestedLocalArrayGetHelperFunctions (lengths : Array (Array Nat)) : Array Lean.Compiler.Yul.Statement :=
  lengths.map nestedLocalArrayGetHelperFunction

def localArrayStaticPath? (path : Array ExprPlan) : Option (Array Nat) :=
  path.foldl
    (init := some #[])
    (fun acc part =>
      match acc, part with
      | some values, .literalWord value => some (values.push value)
      | _, _ => none)

def validateLocalArrayStaticPath
    {ε : Type}
    (mkError : String → ε)
    (name : String)
    (path lengths : Array Nat) : Except ε Unit := do
  if path.size != lengths.size then
    .error (mkError s!"EVM ExprPlan-to-Yul local array get `{name}` expected path rank {lengths.size}, got {path.size}")
  for h : idx in [0:path.size] do
    let index := path[idx]
    let some length := lengths[idx]?
      | .error (mkError s!"EVM ExprPlan-to-Yul local array get `{name}` missing length for path index {idx}")
    if index < length then
      pure ()
    else
      .error (mkError s!"EVM ExprPlan-to-Yul local array get `{name}` index {index} is out of bounds for length {length}")

def localArrayGetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerPlan : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (path : Array ExprPlan)
    (lengths : Array Nat) : Except ε Lean.Compiler.Yul.Expr := do
  if lengths.isEmpty then
    .error (mkError s!"EVM ExprPlan-to-Yul local array get `{name}` requires at least one dimension")
  if path.size != lengths.size then
    .error (mkError s!"EVM ExprPlan-to-Yul local array get `{name}` expected path rank {lengths.size}, got {path.size}")
  match localArrayStaticPath? path with
  | some staticPath => do
      validateLocalArrayStaticPath mkError name staticPath lengths
      .ok (Lean.Compiler.Yul.Expr.id (arrayLocalPathName name staticPath))
  | none => do
      let pathArgs ← path.mapM lowerPlan
      match lengths.toList with
      | [length] =>
          let mut valueArgs : Array Lean.Compiler.Yul.Expr := #[]
          for _h : idx in [0:length] do
            valueArgs := valueArgs.push (Lean.Compiler.Yul.Expr.id (arrayLocalElementName name idx))
          .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName length) (pathArgs ++ valueArgs))
      | _ =>
          let mut valueArgs : Array Lean.Compiler.Yul.Expr := #[]
          for leafPath in nestedLocalArrayLeafPaths lengths do
            valueArgs := valueArgs.push (Lean.Compiler.Yul.Expr.id (arrayLocalPathName name leafPath))
          .ok (Lean.Compiler.Yul.call (nestedLocalArrayGetFunctionName lengths) (pathArgs ++ valueArgs))

def localStructFieldExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerPlan : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (base : ExprPlan)
    (fieldName : String) : Except ε Lean.Compiler.Yul.Expr := do
  match base with
  | .local name =>
      .ok (Lean.Compiler.Yul.Expr.id (structLocalFieldName name fieldName))
  | .structLit _ fields => do
      let some field := fields.find? fun field => field.fst == fieldName
        | .error (mkError s!"struct literal has no field `{fieldName}`")
      lowerPlan field.snd
  | .localArrayGet name path lengths => do
      if lengths.isEmpty then
        .error (mkError s!"EVM ExprPlan-to-Yul local struct-array field get `{name}.{fieldName}` requires at least one dimension")
      if path.size != lengths.size then
        .error (mkError s!"EVM ExprPlan-to-Yul local struct-array field get `{name}.{fieldName}` expected path rank {lengths.size}, got {path.size}")
      match localArrayStaticPath? path with
      | some staticPath => do
          validateLocalArrayStaticPath mkError name staticPath lengths
          .ok (Lean.Compiler.Yul.Expr.id (arrayStructLocalPathFieldName name staticPath fieldName))
      | none => do
          let pathArgs ← path.mapM lowerPlan
          match lengths.toList with
          | [length] =>
              let mut valueArgs : Array Lean.Compiler.Yul.Expr := #[]
              for _h : idx in [0:length] do
                valueArgs := valueArgs.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalFieldName name idx fieldName))
              .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName length) (pathArgs ++ valueArgs))
          | _ =>
              let mut valueArgs : Array Lean.Compiler.Yul.Expr := #[]
              for leafPath in nestedLocalArrayLeafPaths lengths do
                valueArgs := valueArgs.push (Lean.Compiler.Yul.Expr.id (arrayStructLocalPathFieldName name leafPath fieldName))
              .ok (Lean.Compiler.Yul.call (nestedLocalArrayGetFunctionName lengths) (pathArgs ++ valueArgs))
  | _ =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering supports local struct field, struct literal field, and local struct-array field plans only")

def arrayGetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerPlan : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (array index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  match array with
  | .arrayLit _ values =>
      if values.isEmpty then
        .error (mkError "EVM ExprPlan-to-Yul array literal get requires at least one value")
      match index with
      | .literalWord indexValue =>
          if h : indexValue < values.size then
            lowerPlan values[indexValue]
          else
            .error (mkError s!"fixed array literal index {indexValue} is out of bounds for length {values.size}")
      | _ =>
          let indexExpr ← lowerPlan index
          let valueExprs ← values.mapM lowerPlan
          .ok (Lean.Compiler.Yul.call (localArrayGetFunctionName values.size) (#[indexExpr] ++ valueExprs))
  | _ =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering supports array literal get plans only")

def revertStatement : Lean.Compiler.Yul.Statement :=
  Lean.Compiler.Yul.Statement.exprStmt
    (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])

/-- Revert with a string message using Solidity's Error(string) ABI encoding:
   `revert(0, 100)` preceded by:
   - offset (0x60 = 96 bytes to string data)
   - length (message.length)
   - padded message bytes
   This matches Solidity's `revert("message")` encoding. -/
def revertWithMessageStatements (message : String) : Array Lean.Compiler.Yul.Statement :=
  let msgBytes := message.toUTF8
  let msgLen := msgBytes.size
  let paddedLen := ((msgLen + 31) / 32) * 32
  let totalSize := 100 + paddedLen  -- 4 selector + 32 offset + 32 length + padded message
  #[
    -- mstore selector (Error(string) = 0x08c379a0)
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0x08c379a0]),
    -- mstore offset = 0x20 (32 bytes from start of string data area)
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 4, Lean.Compiler.Yul.Expr.num 0x20]),
    -- mstore string length
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 36, Lean.Compiler.Yul.Expr.num msgLen]),
    -- store message bytes
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 68, Lean.Compiler.Yul.Expr.num 0]),
    -- revert from offset 0 with total size
    .exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num totalSize])
  ]

def isHexChar (c : Char) : Bool :=
  ('0' <= c && c <= '9') ||
  ('a' <= c && c <= 'f') ||
  ('A' <= c && c <= 'F')

def stripHexPrefix (s : String) : String :=
  if s.startsWith "0x" || s.startsWith "0X" then
    (s.drop 2).toString
  else
    s

def normalizeInitCodeHex {ε : Type} (mkError : String → ε) (context initCodeHex : String) : Except ε String := do
  let raw := stripHexPrefix initCodeHex
  if raw.isEmpty then
    .error (mkError s!"{context} init code must be non-empty hex")
  else if raw.length % 2 != 0 then
    .error (mkError s!"{context} init code hex must have an even number of digits")
  else if !(raw.all isHexChar) then
    .error (mkError s!"{context} init code must contain only hex digits")
  else
    .ok raw

def repeatString : Nat → String → String
  | 0, _ => ""
  | n+1, s => s ++ repeatString n s

def rightPadHex64 (chunk : String) : String :=
  chunk ++ repeatString (64 - chunk.length) "0"

partial def hexChunks64 (hex : String) : Array String :=
  if hex.isEmpty then
    #[]
  else
    let chunk := (hex.take 64).toString
    let rest := (hex.drop 64).toString
    #[chunk] ++ hexChunks64 rest

def createModeFunctionPrefix : CreateMode → String
  | .create => "__proof_forge_create_"
  | .create2 => "__proof_forge_create2_"

def createModeOpcode : CreateMode → String
  | .create => "create"
  | .create2 => "create2"

def createHelperFunctionName
    {ε : Type}
    (mkError : String → ε)
    (mode : CreateMode)
    (initCodeHex : String) : Except ε String := do
  let hex ← normalizeInitCodeHex mkError "contract creation" initCodeHex
  .ok s!"{createModeFunctionPrefix mode}{hex}"

def createCallValueParamName : String := "call_value"
def createSaltParamName : String := "salt"

def createHelperParams : CreateMode → Array Lean.Compiler.Yul.TypedName
  | .create => #[{ name := createCallValueParamName }]
  | .create2 => #[{ name := createCallValueParamName }, { name := createSaltParamName }]

def createInitCodeStoreStatements
    {ε : Type}
    (mkError : String → ε)
    (initCodeHex : String) : Except ε (Array Lean.Compiler.Yul.Statement × Nat) := do
  let hex ← normalizeInitCodeHex mkError "contract creation" initCodeHex
  let chunks := hexChunks64 hex
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:chunks.size] do
    let chunk := chunks[idx]
    statements := statements.push <| .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
      Lean.Compiler.Yul.Expr.num (idx * 32),
      Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex ("0x" ++ rightPadHex64 chunk))
    ])
  .ok (statements, hex.length / 2)

def createHelperFunction
    {ε : Type}
    (mkError : String → ε)
    (spec : CreateHelperSpec) : Except ε Lean.Compiler.Yul.Statement := do
  let functionName ← createHelperFunctionName mkError spec.mode spec.initCodeHex
  let (storeStatements, byteLength) ← createInitCodeStoreStatements mkError spec.initCodeHex
  let createArgs :=
    match spec.mode with
    | .create =>
        #[
          Lean.Compiler.Yul.Expr.id createCallValueParamName,
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num byteLength
        ]
    | .create2 =>
        #[
          Lean.Compiler.Yul.Expr.id createCallValueParamName,
          Lean.Compiler.Yul.Expr.num 0,
          Lean.Compiler.Yul.Expr.num byteLength,
          Lean.Compiler.Yul.Expr.id createSaltParamName
        ]
  .ok <| .funcDef functionName
    (createHelperParams spec.mode)
    #[{ name := "result" }]
    {
      statements := storeStatements ++ #[
        .assignment #["result"] (Lean.Compiler.Yul.builtin (createModeOpcode spec.mode) createArgs),
        .ifStmt
          (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "result"])
          { statements := #[revertStatement] }
      ]
    }

def maxU32 : Nat := 4294967295

def crosscallReturnTypeSuffix {ε : Type} (mkError : String → ε) : ValueType → Except ε String
  | .u64 => .ok ""
  | .u32 => .ok "_u32"
  | .bool => .ok "_bool"
  | .hash => .ok "_hash"
  | .u8 => .ok "_u8"
  | .u128 => .ok "_u128"
  | .address => .ok "_address"
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error (mkError "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0")

def crosscallFunctionName {ε : Type} (mkError : String → ε) (arity : Nat) (returnType : ValueType) :
    Except ε String := do
  .ok s!"__proof_forge_crosscall_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallValueFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (returnType : ValueType)
    (plainTransfer : Bool := false) : Except ε String := do
  if plainTransfer then
    .ok s!"__proof_forge_native_transfer{← crosscallReturnTypeSuffix mkError returnType}"
  else
    .ok s!"__proof_forge_crosscall_value_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallStaticFunctionName {ε : Type} (mkError : String → ε) (arity : Nat) (returnType : ValueType) :
    Except ε String := do
  .ok s!"__proof_forge_crosscall_static_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallDelegateFunctionName {ε : Type} (mkError : String → ε) (arity : Nat) (returnType : ValueType) :
    Except ε String := do
  .ok s!"__proof_forge_crosscall_delegate_{arity}{← crosscallReturnTypeSuffix mkError returnType}"

def crosscallReturnWordTag {ε : Type} (mkError : String → ε) : ValueType → Except ε String
  | .u64 => .ok "u64"
  | .u32 => .ok "u32"
  | .bool => .ok "bool"
  | .hash => .ok "hash"
  | .u8 => .ok "u8"
  | .u128 => .ok "u128"
  | .address => .ok "address"
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error (mkError "crosscall aggregate return words must be U32, U64, Bool, or Hash in IR EVM v0")

def crosscallReturnWordTagsSuffix
    {ε : Type}
    (mkError : String → ε)
    (wordTypes : Array ValueType) : Except ε String := do
  let mut suffix := ""
  for wordType in wordTypes do
    suffix := suffix ++ "_" ++ (← crosscallReturnWordTag mkError wordType)
  .ok suffix

def crosscallAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType) : Except ε String := do
  .ok s!"__proof_forge_crosscall_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallValueAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType)
    (plainTransfer : Bool := false) : Except ε String := do
  if plainTransfer then
    .error (mkError "plain native transfer does not support aggregate crosscall returns in IR EVM v0")
  else
    .ok s!"__proof_forge_crosscall_value_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallStaticAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType) : Except ε String := do
  .ok s!"__proof_forge_crosscall_static_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallDelegateAggregateFunctionName
    {ε : Type}
    (mkError : String → ε)
    (arity : Nat)
    (wordTypes : Array ValueType) : Except ε String := do
  .ok s!"__proof_forge_crosscall_delegate_{arity}_abi{← crosscallReturnWordTagsSuffix mkError wordTypes}"

def crosscallReturnIsScalarWord : ValueType → Bool
  | .u8 | .u64 | .u32 | .u128 | .bool | .hash | .address => true
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ => false

def crosscallModeForwardsValue : CrosscallMode → Bool
  | .callValue => true
  | .call | .staticcall | .delegatecall => false

def crosscallArgName (idx : Nat) : String :=
  s!"arg{idx}"

def crosscallCallValueName : String := "call_value"

def crosscallCalldataSize (arity : Nat) : Nat :=
  4 + arity * 32

def crosscallFunctionParams
    (arity : Nat)
    (mode : CrosscallMode)
    (plainTransfer : Bool := false) : Array Lean.Compiler.Yul.TypedName :=
  if plainTransfer then
    #[
      ({ name := "target" } : Lean.Compiler.Yul.TypedName),
      ({ name := crosscallCallValueName } : Lean.Compiler.Yul.TypedName)
    ]
  else
    let base := #[
      ({ name := "target" } : Lean.Compiler.Yul.TypedName),
      ({ name := "selector" } : Lean.Compiler.Yul.TypedName)
    ]
    let base :=
      if crosscallModeForwardsValue mode then
        base.push ({ name := crosscallCallValueName } : Lean.Compiler.Yul.TypedName)
      else
        base
    go 0 base
  where
    go (idx : Nat) (acc : Array Lean.Compiler.Yul.TypedName) : Array Lean.Compiler.Yul.TypedName :=
      if h : idx < arity then
        go (idx + 1) (acc.push ({ name := crosscallArgName idx } : Lean.Compiler.Yul.TypedName))
      else
        acc

def crosscallArgStoreStatements (arity : Nat) : Array Lean.Compiler.Yul.Statement :=
  go 0 #[]
where
  go (idx : Nat) (acc : Array Lean.Compiler.Yul.Statement) : Array Lean.Compiler.Yul.Statement :=
    if h : idx < arity then
      let store := Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "mstore" #[
          Lean.Compiler.Yul.Expr.num (4 + idx * 32),
          Lean.Compiler.Yul.Expr.id (crosscallArgName idx)
        ])
      go (idx + 1) (acc.push store)
    else
      acc

def crosscallReturnGuardStatementsForName
    {ε : Type}
    (mkError : String → ε)
    (resultName : String)
    (returnType : ValueType) : Except ε (Array Lean.Compiler.Yul.Statement) :=
  match returnType with
  | .u32 =>
      .ok #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id resultName, Lean.Compiler.Yul.Expr.num maxU32])
          { statements := #[revertStatement] }
      ]
  | .bool =>
      .ok #[
        .ifStmt
          (Lean.Compiler.Yul.builtin "gt" #[Lean.Compiler.Yul.Expr.id resultName, Lean.Compiler.Yul.Expr.num 1])
          { statements := #[revertStatement] }
      ]
  | .u8 | .u64 | .u128 | .hash | .address => .ok #[]
  | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      .error (mkError "crosscall return type must be U32, U64, Bool, or Hash in IR EVM v0")

def crosscallHelperReturnNames (wordCount : Nat) : Array Lean.Compiler.Yul.TypedName :=
  if wordCount == 1 then
    #[{ name := "result" }]
  else
    Id.run do
      let mut names : Array Lean.Compiler.Yul.TypedName := #[]
      for _h : idx in [0:wordCount] do
        names := names.push ({ name := s!"result{idx}" } : Lean.Compiler.Yul.TypedName)
      names

def crosscallHelperReturnNameStrings (wordCount : Nat) : Array String :=
  (crosscallHelperReturnNames wordCount).map fun name => name.name

def crosscallHelperFunctionName
    {ε : Type}
    (mkError : String → ε)
    (spec : CrosscallHelperSpec) : Except ε String := do
  match spec.mode, crosscallReturnIsScalarWord spec.returnType with
  | .call, true => crosscallFunctionName mkError spec.arity spec.returnType
  | .call, false => crosscallAggregateFunctionName mkError spec.arity spec.wordTypes
  | .callValue, true =>
      crosscallValueFunctionName mkError spec.arity spec.returnType spec.plainTransfer
  | .callValue, false =>
      crosscallValueAggregateFunctionName mkError spec.arity spec.wordTypes spec.plainTransfer
  | .staticcall, true => crosscallStaticFunctionName mkError spec.arity spec.returnType
  | .staticcall, false => crosscallStaticAggregateFunctionName mkError spec.arity spec.wordTypes
  | .delegatecall, true => crosscallDelegateFunctionName mkError spec.arity spec.returnType
  | .delegatecall, false => crosscallDelegateAggregateFunctionName mkError spec.arity spec.wordTypes

def crosscallCallExpr (spec : CrosscallHelperSpec) (outputSize : Nat) : Lean.Compiler.Yul.Expr :=
  let callValue :=
    if crosscallModeForwardsValue spec.mode then
      Lean.Compiler.Yul.Expr.id crosscallCallValueName
    else
      Lean.Compiler.Yul.Expr.num 0
  match spec.mode with
  | .call | .callValue =>
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        Lean.Compiler.Yul.Expr.id "target",
        callValue,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num outputSize
      ]
  | .staticcall =>
      Lean.Compiler.Yul.builtin "staticcall" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        Lean.Compiler.Yul.Expr.id "target",
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num outputSize
      ]
  | .delegatecall =>
      Lean.Compiler.Yul.builtin "delegatecall" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        Lean.Compiler.Yul.Expr.id "target",
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num (crosscallCalldataSize spec.arity),
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num outputSize
      ]

def crosscallPlainTransferHelperFunction
    {ε : Type}
    (mkError : String → ε)
    (spec : CrosscallHelperSpec)
    (functionName : String) : Except ε Lean.Compiler.Yul.Statement := do
  if spec.wordTypes.size != 1 then
    .error (mkError "plain native transfer expects a single-word return type in IR EVM v0")
  else
    let returnName := (crosscallHelperReturnNameStrings 1)[0]!
    .ok <| .funcDef functionName
      (crosscallFunctionParams spec.arity spec.mode true)
      (crosscallHelperReturnNames 1)
      {
        statements := #[
          .varDecl #[{ name := "_success" }] (some <|
            Lean.Compiler.Yul.builtin "call" #[
              Lean.Compiler.Yul.builtin "gas" #[],
              Lean.Compiler.Yul.Expr.id "target",
              Lean.Compiler.Yul.Expr.id crosscallCallValueName,
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num 0
            ]),
          .ifStmt
            (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_success"])
            { statements := #[revertStatement] },
          .assignment #[returnName] (Lean.Compiler.Yul.Expr.num 0)
        ]
      }

def crosscallHelperFunction
    {ε : Type}
    (mkError : String → ε)
    (spec : CrosscallHelperSpec) : Except ε Lean.Compiler.Yul.Statement := do
  if spec.wordTypes.isEmpty then
    .error (mkError s!"EVM CrosscallHelperSpec for `{spec.returnType.name}` has no return word layout")
  else
    let functionName ← crosscallHelperFunctionName mkError spec
    if spec.plainTransfer then
      crosscallPlainTransferHelperFunction mkError spec functionName
    else
      let outputSize := spec.wordTypes.size * 32
      let callExpr := crosscallCallExpr spec outputSize
      let returnNameStrings := crosscallHelperReturnNameStrings spec.wordTypes.size
      let mut copyAssignments : Array Lean.Compiler.Yul.Statement := #[]
      for h : idx in [0:spec.wordTypes.size] do
        copyAssignments := copyAssignments.push <|
          .assignment #[returnNameStrings[idx]!]
            (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num (idx * 32)])
      let mut guardStatements : Array Lean.Compiler.Yul.Statement := #[]
      for h : idx in [0:spec.wordTypes.size] do
        guardStatements := guardStatements ++
          (← crosscallReturnGuardStatementsForName mkError returnNameStrings[idx]! spec.wordTypes[idx])
      .ok <| .funcDef functionName
        (crosscallFunctionParams spec.arity spec.mode spec.plainTransfer)
        (crosscallHelperReturnNames spec.wordTypes.size)
        {
          statements :=
            #[
              .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.builtin "shl" #[
                  Lean.Compiler.Yul.Expr.num 224,
                  Lean.Compiler.Yul.Expr.id "selector"
                ]
              ])
            ] ++
            crosscallArgStoreStatements spec.arity ++
            #[
              .varDecl #[{ name := "_success" }] (some callExpr),
              .ifStmt
                (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_success"])
                { statements := #[revertStatement] },
              .ifStmt
                (Lean.Compiler.Yul.builtin "lt" #[
                  Lean.Compiler.Yul.builtin "returndatasize" #[],
                  Lean.Compiler.Yul.Expr.num outputSize
                ])
                { statements := #[revertStatement] },
              .exprStmt (Lean.Compiler.Yul.builtin "returndatacopy" #[
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num 0,
                Lean.Compiler.Yul.Expr.num outputSize
              ])
            ] ++
            copyAssignments ++
            guardStatements
        }

def crosscallScalarHelperSpec
    (mode : CrosscallMode)
    (arity : Nat)
    (returnType : ValueType)
    (plainTransfer : Bool := false) : CrosscallHelperSpec := {
  arity
  returnType
  wordTypes := #[returnType]
  mode
  plainTransfer
}

def crosscallAggregateHelperSpec
    (mode : CrosscallMode)
    (arity : Nat)
    (returnType : ValueType)
    (wordTypes : Array ValueType) : CrosscallHelperSpec := {
  arity
  returnType
  wordTypes
  mode
  plainTransfer := false
}

def crosscallScalarHelperCallExpr
    {ε : Type}
    (mkError : String → ε)
    (mode : CrosscallMode)
    (target methodId : Lean.Compiler.Yul.Expr)
    (callValue? : Option Lean.Compiler.Yul.Expr)
    (args : Array Lean.Compiler.Yul.Expr)
    (returnType : ValueType)
    (plainTransfer : Bool := false) : Except ε Lean.Compiler.Yul.Expr := do
  if !crosscallReturnIsScalarWord returnType then
    .error (mkError s!"EVM scalar crosscall helper call does not support aggregate return type `{returnType.name}`")
  else if plainTransfer && mode != .callValue then
    .error (mkError "plain native transfer helper calls must use callValue mode")
  else if plainTransfer && !args.isEmpty then
    .error (mkError "plain native transfer helper calls cannot include calldata arguments")
  else
    let functionName ←
      crosscallHelperFunctionName mkError
        (crosscallScalarHelperSpec mode args.size returnType plainTransfer)
    match mode, callValue? with
    | .callValue, some callValue =>
        if plainTransfer then
          .ok (Lean.Compiler.Yul.call functionName #[target, callValue])
        else
          .ok (Lean.Compiler.Yul.call functionName (#[target, methodId, callValue] ++ args))
    | .callValue, none =>
        .error (mkError "value-bearing crosscall helper calls require call value")
    | .call, none
    | .staticcall, none
    | .delegatecall, none =>
        .ok (Lean.Compiler.Yul.call functionName (#[target, methodId] ++ args))
    | .call, some _
    | .staticcall, some _
    | .delegatecall, some _ =>
        .error (mkError "non-value crosscall helper calls cannot include call value")

def crosscallAggregateHelperCallExpr
    {ε : Type}
    (mkError : String → ε)
    (mode : CrosscallMode)
    (target methodId : Lean.Compiler.Yul.Expr)
    (callValue? : Option Lean.Compiler.Yul.Expr)
    (args : Array Lean.Compiler.Yul.Expr)
    (returnType : ValueType)
    (wordTypes : Array ValueType) : Except ε Lean.Compiler.Yul.Expr := do
  if crosscallReturnIsScalarWord returnType then
    .error (mkError s!"EVM aggregate crosscall helper call requires an aggregate return type, got `{returnType.name}`")
  else if wordTypes.isEmpty then
    .error (mkError s!"EVM aggregate crosscall helper call for `{returnType.name}` has no return word layout")
  else
    let functionName ←
      crosscallHelperFunctionName mkError
        (crosscallAggregateHelperSpec mode args.size returnType wordTypes)
    match mode, callValue? with
    | .callValue, some callValue =>
        .ok (Lean.Compiler.Yul.call functionName (#[target, methodId, callValue] ++ args))
    | .callValue, none =>
        .error (mkError "value-bearing aggregate crosscall helper calls require call value")
    | .call, none
    | .staticcall, none
    | .delegatecall, none =>
        .ok (Lean.Compiler.Yul.call functionName (#[target, methodId] ++ args))
    | .call, some _
    | .staticcall, some _
    | .delegatecall, some _ =>
        .error (mkError "non-value aggregate crosscall helper calls cannot include call value")

def crosscallAggregateReturnAssignment
    {ε : Type}
    (mkError : String → ε)
    (returnNames : Array String)
    (mode : CrosscallMode)
    (target methodId : Lean.Compiler.Yul.Expr)
    (callValue? : Option Lean.Compiler.Yul.Expr)
    (args : Array Lean.Compiler.Yul.Expr)
    (returnType : ValueType)
    (wordTypes : Array ValueType) : Except ε Lean.Compiler.Yul.Statement := do
  if returnNames.size != wordTypes.size then
    .error (mkError s!"aggregate crosscall return assignment has {returnNames.size} target(s), expected {wordTypes.size}")
  else
    .ok <| .assignment returnNames
      (← crosscallAggregateHelperCallExpr
        mkError
        mode
        target
        methodId
        callValue?
        args
        returnType
        wordTypes)

def createHelperCallExpr
    {ε : Type}
    (mkError : String → ε)
    (mode : CreateMode)
    (callValue : Lean.Compiler.Yul.Expr)
    (salt? : Option Lean.Compiler.Yul.Expr)
    (initCodeHex : String) : Except ε Lean.Compiler.Yul.Expr := do
  let functionName ← createHelperFunctionName mkError mode initCodeHex
  match mode, salt? with
  | .create, none =>
      .ok (Lean.Compiler.Yul.call functionName #[callValue])
  | .create2, some salt =>
      .ok (Lean.Compiler.Yul.call functionName #[callValue, salt])
  | .create, some _ =>
      .error (mkError "create helper calls cannot include a salt")
  | .create2, none =>
      .error (mkError "create2 helper calls require a salt")

def calldataloadAt (offset : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[offset]

def dynamicParamLengthName (name : String) : String :=
  ProofForge.Backend.Evm.Plan.dynamicParamLengthName name

def dynamicParamDataPtrName (name : String) : String :=
  ProofForge.Backend.Evm.Plan.dynamicParamDataPtrName name

partial def localAbiWordsAt
    {ε : Type}
    (mkError : String → ε)
    (structFieldIds : String → Except ε (Array String))
    (context name : String)
    (path : Array Nat) : ValueType → Except ε (Array Lean.Compiler.Yul.Expr)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      if path.isEmpty then
        .ok #[Lean.Compiler.Yul.Expr.id name]
      else
        .ok #[Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path)]
  | .unit =>
      .error (mkError s!"{context} uses Unit; IR EVM v0 ABI values must use U32, U64, Bool, Hash, Address, Bytes, String, fixed arrays, or structs")
  | .bytes | .string | .array _ =>
      if path.isEmpty then
        .ok #[Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName name)]
      else
        .error (mkError s!"{context} dynamic type cannot be nested in fixed arrays")
  | .fixedArray elementType length => do
      if length == 0 then
        .error (mkError s!"{context} uses Array<{elementType.name},0>; IR EVM v0 ABI fixed arrays must have non-zero length")
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for _h : idx in [0:length] do
        words := words ++ (← localAbiWordsAt mkError structFieldIds context name (path.push idx) elementType)
      .ok words
  | .structType typeName => do
      let fieldIds ← structFieldIds typeName
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for fieldId in fieldIds do
        let fieldName :=
          if path.isEmpty then
            structLocalFieldName name fieldId
          else
            arrayStructLocalPathFieldName name path fieldId
        words := words.push (Lean.Compiler.Yul.Expr.id fieldName)
      .ok words

def localAbiWords
    {ε : Type}
    (mkError : String → ε)
    (structFieldIds : String → Except ε (Array String))
    (context name : String)
    (type : ValueType) : Except ε (Array Lean.Compiler.Yul.Expr) :=
  localAbiWordsAt mkError structFieldIds context name #[] type

def storageAbiWords
    {ε : Type}
    (mkError : String → ε)
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context stateId : String)
    (type : ValueType) : Except ε (Array Lean.Compiler.Yul.Expr) := do
  match type with
  | .structType typeName =>
      storageStructWords context typeName stateId
  | .fixedArray elementType length =>
      storageArrayWords context stateId elementType length
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address | .unit
  | .bytes | .string | .array _ =>
      .error (mkError s!"{context} storage-backed ABI word expansion supports struct scalar storage or fixed storage arrays only, got `{type.name}`")

partial def abiValueWordsFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context : String)
    (type : ValueType)
    (value : AbiValuePlan) :
    Except ε (Array Lean.Compiler.Yul.Expr) := do
  match type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      match value with
      | .expr plan => .ok #[← lowerPlanExpr plan]
      | _ => .error (mkError s!"{context} scalar ABI value requires an expression plan")
  | .fixedArray elementType length =>
      match value with
      | .local name plannedType =>
          if plannedType == type then
            localAbiWords mkError (fun typeName => do
              let fields ← structFields typeName
              .ok (fields.map fun field => field.fst)) context name type
          else
            .error (mkError s!"{context} local ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .storage stateId plannedType =>
          if plannedType == type then
            storageAbiWords mkError storageStructWords storageArrayWords context stateId type
          else
            .error (mkError s!"{context} storage ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .arrayLit literalElementType values => do
          if literalElementType != elementType then
            .error (mkError s!"{context} fixed-array literal element type mismatch: expected `{elementType.name}`, got `{literalElementType.name}`")
          if values.size != length then
            .error (mkError s!"{context} fixed-array expected length {length}, got {values.size}")
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for h : idx in [0:values.size] do
            words := words ++
              (← abiValueWordsFromPlan
                mkError
                lowerPlanExpr
                structFields
                storageStructWords
                storageArrayWords
                s!"{context} fixed-array element {idx}"
                elementType
                values[idx])
          .ok words
      | _ =>
          .error (mkError s!"{context} aggregate field requires an ABI word expansion plan")
  | .structType typeName =>
      match value with
      | .local name plannedType =>
          if plannedType == type then
            localAbiWords mkError (fun typeName => do
              let fields ← structFields typeName
              .ok (fields.map fun field => field.fst)) context name type
          else
            .error (mkError s!"{context} local ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .storage stateId plannedType =>
          if plannedType == type then
            storageAbiWords mkError storageStructWords storageArrayWords context stateId type
          else
            .error (mkError s!"{context} storage ABI word plan type mismatch: expected `{type.name}`, got `{plannedType.name}`")
      | .structLit literalTypeName fields => do
          if literalTypeName != typeName then
            .error (mkError s!"{context} expected struct `{typeName}`, got `{literalTypeName}`")
          let fieldDecls ← structFields typeName
          let mut words : Array Lean.Compiler.Yul.Expr := #[]
          for fieldDecl in fieldDecls do
            let some field := fields.find? fun field => field.fst == fieldDecl.fst
              | .error (mkError s!"{context} struct literal `{typeName}` is missing field `{fieldDecl.fst}`")
            words := words ++
              (← abiValueWordsFromPlan
                mkError
                lowerPlanExpr
                structFields
                storageStructWords
                storageArrayWords
                s!"{context} struct field `{fieldDecl.fst}`"
                fieldDecl.snd
                field.snd)
          .ok words
      | _ =>
          .error (mkError s!"{context} aggregate field requires an ABI word expansion plan")
  | .unit | .bytes | .string | .array _ =>
      .error (mkError s!"{context} has unsupported ABI word type `{type.name}`")

def returnValueWordPlanWords
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context : String)
    (plan : ReturnValueWordPlan) : Except ε (Array Lean.Compiler.Yul.Expr) :=
  abiValueWordsFromPlan
    mkError
    lowerPlanExpr
    structFields
    storageStructWords
    storageArrayWords
    context
    plan.returns.returnType
    plan.source

def returnValueWordAssignments
    {ε : Type}
    (mkError : String → ε)
    (context : String)
    (returns : ReturnPlan)
    (words : Array Lean.Compiler.Yul.Expr) : Except ε (Array Lean.Compiler.Yul.Statement) := do
  if returns.localNames.size != words.size then
    .error (mkError s!"{context} return lowering produced {words.size} word(s), expected {returns.localNames.size}")
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:returns.localNames.size] do
    let some word := words[idx]?
      | .error (mkError s!"{context} return lowering is missing word {idx}")
    statements := statements.push (.assignment #[returns.localNames[idx]] word)
  .ok statements

def returnValueWordPlanAssignments
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (context : String)
    (plan : ReturnValueWordPlan) : Except ε (Array Lean.Compiler.Yul.Statement) := do
  let words ← returnValueWordPlanWords
    mkError
    lowerPlanExpr
    structFields
    storageStructWords
    storageArrayWords
    context
    plan
  returnValueWordAssignments mkError context plan.returns words

partial def localCrosscallWordsAt
    {ε : Type}
    (mkError : String → ε)
    (structFieldIds : String → Except ε (Array String))
    (context name : String)
    (path : Array Nat) : ValueType → Except ε (Array Lean.Compiler.Yul.Expr)
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      if path.isEmpty then
        .ok #[Lean.Compiler.Yul.Expr.id name]
      else
        .ok #[Lean.Compiler.Yul.Expr.id (arrayLocalPathName name path)]
  | .unit | .bytes | .string | .array _ =>
      .error (mkError s!"{context} uses Unit; IR EVM v0 crosscall values must use U32, U64, Bool, Hash, fixed arrays, or structs")
  | .fixedArray elementType length => do
      if length == 0 then
        .error (mkError s!"{context} uses Array<{elementType.name},0>; IR EVM v0 crosscall fixed arrays must have non-zero length")
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for _h : idx in [0:length] do
        words := words ++ (← localCrosscallWordsAt mkError structFieldIds context name (path.push idx) elementType)
      .ok words
  | .structType typeName => do
      let fieldIds ← structFieldIds typeName
      let mut words : Array Lean.Compiler.Yul.Expr := #[]
      for fieldId in fieldIds do
        let fieldName :=
          if path.isEmpty then
            structLocalFieldName name fieldId
          else
            arrayStructLocalPathFieldName name path fieldId
        words := words.push (Lean.Compiler.Yul.Expr.id fieldName)
      .ok words

def localCrosscallWords
    {ε : Type}
    (mkError : String → ε)
    (structFieldIds : String → Except ε (Array String))
    (context name : String)
    (type : ValueType) : Except ε (Array Lean.Compiler.Yul.Expr) :=
  localCrosscallWordsAt mkError structFieldIds context name #[] type

partial def crosscallArgWordPlanExprs
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (localWords : String → ValueType → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageWords : String → ValueType → Except ε (Array Lean.Compiler.Yul.Expr))
    (plans : Array CrosscallArgWordPlan) : Except ε (Array Lean.Compiler.Yul.Expr) := do
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for plan in plans do
    match plan with
    | .local name type =>
        words := words ++ (← localWords name type)
    | .storage stateId type =>
        words := words ++ (← storageWords stateId type)
    | .expr exprPlan =>
        words := words.push (← lowerPlanExpr exprPlan)
  .ok words

def crosscallAggregateReturnAssignmentPlanStatement
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (localWords : String → ValueType → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageWords : String → ValueType → Except ε (Array Lean.Compiler.Yul.Expr))
    (plan : CrosscallReturnAssignmentPlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  let target ← lowerPlanExpr plan.target
  let methodId ← lowerPlanExpr plan.methodId
  let callValue? ← plan.callValue?.mapM lowerPlanExpr
  let argWords ← crosscallArgWordPlanExprs lowerPlanExpr localWords storageWords plan.args
  crosscallAggregateReturnAssignment
    mkError
    plan.returns.localNames
    plan.mode
    target
    methodId
    callValue?
    argWords
    plan.returns.returnType
    plan.returns.wordTypes

partial def crosscallExprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (localWords : String → ValueType → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageWords : String → ValueType → Except ε (Array Lean.Compiler.Yul.Expr))
    (mode : CrosscallMode)
    (target methodId : ExprPlan)
    (callValue? : Option ExprPlan)
    (args : Array CrosscallArgWordPlan)
    (returnType : ValueType) : Except ε Lean.Compiler.Yul.Expr := do
  let targetExpr ← lowerPlanExpr target
  let methodIdExpr ← lowerPlanExpr methodId
  let callValueExpr? ← callValue?.mapM lowerPlanExpr
  let argExprs ← crosscallArgWordPlanExprs lowerPlanExpr localWords storageWords args
  let plainTransfer :=
    mode == .callValue && argExprs.isEmpty &&
      match methodId with
      | .literalWord 0 => true
      | _ => false
  crosscallScalarHelperCallExpr
    mkError
    mode
    targetExpr
    methodIdExpr
    callValueExpr?
    argExprs
    returnType
    plainTransfer

def abiParamsHeadWordCount (params : Array AbiParamPlan) : Nat :=
  params.foldl (fun acc param => acc + param.headWordCount) 0

def abiParamsMinSizeValidationStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  let headWordCount := abiParamsHeadWordCount params
  let minSize := 4 + headWordCount * 32
  if headWordCount == 0 then
    #[]
  else
    #[
      Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "lt" #[
          Lean.Compiler.Yul.builtin "calldatasize" #[],
          Lean.Compiler.Yul.Expr.num minSize
        ])
        { statements := #[revertStatement] }
    ]

def abiWordValidationStatement?
    (word : Lean.Compiler.Yul.Expr)
    (type : ValueType) : Option Lean.Compiler.Yul.Statement :=
  match type with
  | .u32 =>
      some <| Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "gt" #[word, Lean.Compiler.Yul.Expr.num 4294967295])
        { statements := #[revertStatement] }
  | .bool =>
      some <| Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "gt" #[word, Lean.Compiler.Yul.Expr.num 1])
        { statements := #[revertStatement] }
  | .u8 | .u64 | .u128 | .hash | .address | .unit | .fixedArray _ _ | .structType _ | .bytes | .string | .array _ =>
      none

def abiParamHeadValidationStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for h : i in [0:params.size] do
      let param := params[i]
      if param.isDynamic then
        let offsetExpr := calldataWordExpr param.headWordIndex
        let baseOffset := Lean.Compiler.Yul.Expr.num (4 + param.headWordIndex * 32)
        let offsetPlusBase := Lean.Compiler.Yul.builtin "add" #[baseOffset, offsetExpr]
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.ifStmt
            (Lean.Compiler.Yul.builtin "gt" #[
              offsetPlusBase,
              Lean.Compiler.Yul.builtin "calldatasize" #[]
            ])
            { statements := #[revertStatement] }
      else
        for h : j in [0:param.wordTypes.size] do
          let wordIndex := param.headWordIndex + j
          match abiWordValidationStatement? (calldataWordExpr wordIndex) param.wordTypes[j] with
          | some statement => statements := statements.push statement
          | none => pure ()
    statements

def dynamicBytesStringParamDecodeStatements (param : AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  let offsetExpr := calldataWordExpr param.headWordIndex
  let dataOffset := Lean.Compiler.Yul.builtin "add" #[
    Lean.Compiler.Yul.Expr.num (4 + param.headWordIndex * 32),
    offsetExpr
  ]
  let lengthExpr := calldataloadAt dataOffset
  let memPtrName := s!"__pf_dyn_ptr_{param.name}"
  let memPtr := Lean.Compiler.Yul.Expr.id memPtrName
  let dataStart := Lean.Compiler.Yul.builtin "add" #[memPtr, Lean.Compiler.Yul.Expr.num 32]
  let wordCount := Lean.Compiler.Yul.builtin "div" #[
    Lean.Compiler.Yul.builtin "add" #[lengthExpr, Lean.Compiler.Yul.Expr.num 31],
    Lean.Compiler.Yul.Expr.num 32
  ]
  let memSize := Lean.Compiler.Yul.builtin "mul" #[wordCount, Lean.Compiler.Yul.Expr.num 32]
  let totalSize := Lean.Compiler.Yul.builtin "add" #[memSize, Lean.Compiler.Yul.Expr.num 32]
  let tailEnd := Lean.Compiler.Yul.builtin "add" #[
    dataOffset,
    Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.num 32, memSize]
  ]
  #[
    .ifStmt
      (Lean.Compiler.Yul.builtin "gt" #[tailEnd, Lean.Compiler.Yul.builtin "calldatasize" #[]])
      { statements := #[revertStatement] },
    .varDecl #[{ name := memPtrName }]
      (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0x40])),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[memPtr, lengthExpr]),
    .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
      dataStart,
      Lean.Compiler.Yul.builtin "add" #[dataOffset, Lean.Compiler.Yul.Expr.num 32],
      memSize
    ]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
      Lean.Compiler.Yul.Expr.num 0x40,
      Lean.Compiler.Yul.builtin "add" #[memPtr, totalSize]
    ]),
    .varDecl #[{ name := dynamicParamLengthName param.name }] (some lengthExpr),
    .varDecl #[{ name := dynamicParamDataPtrName param.name }] (some memPtr)
  ]

def dynamicArrayParamDecodeStatements (param : AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  match param.type with
  | .array _ =>
    let offsetExpr := calldataWordExpr param.headWordIndex
    let dataOffset := Lean.Compiler.Yul.builtin "add" #[
      Lean.Compiler.Yul.Expr.num (4 + param.headWordIndex * 32),
      offsetExpr
    ]
    let lengthExpr := calldataloadAt dataOffset
    let memPtrName := s!"__pf_dyn_ptr_{param.name}"
    let memPtr := Lean.Compiler.Yul.Expr.id memPtrName
    let memSize := Lean.Compiler.Yul.builtin "mul" #[lengthExpr, Lean.Compiler.Yul.Expr.num 32]
    let totalSize := Lean.Compiler.Yul.builtin "add" #[memSize, Lean.Compiler.Yul.Expr.num 32]
    let tailEnd := Lean.Compiler.Yul.builtin "add" #[
      dataOffset,
      Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.num 32, memSize]
    ]
    #[
      .ifStmt
        (Lean.Compiler.Yul.builtin "gt" #[tailEnd, Lean.Compiler.Yul.builtin "calldatasize" #[]])
        { statements := #[revertStatement] },
      .varDecl #[{ name := memPtrName }]
        (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0x40])),
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[memPtr, lengthExpr]),
      .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
        Lean.Compiler.Yul.builtin "add" #[memPtr, Lean.Compiler.Yul.Expr.num 32],
        Lean.Compiler.Yul.builtin "add" #[dataOffset, Lean.Compiler.Yul.Expr.num 32],
        memSize
      ]),
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num 0x40,
        Lean.Compiler.Yul.builtin "add" #[memPtr, totalSize]
      ]),
      .varDecl #[{ name := dynamicParamLengthName param.name }] (some lengthExpr),
      .varDecl #[{ name := dynamicParamDataPtrName param.name }] (some memPtr)
    ]
  | _ => #[]

def dynamicAbiParamDecodeStatements (param : AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  if param.isDynamic then
    match param.type with
    | .array _ => dynamicArrayParamDecodeStatements param
    | _ => dynamicBytesStringParamDecodeStatements param
  else
    #[]

def abiParamDecodeStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  params.foldl (fun acc param => acc ++ dynamicAbiParamDecodeStatements param) #[]

def abiParamValidationAndDecodeStatements (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Statement :=
  abiParamsMinSizeValidationStatements params ++
    abiParamHeadValidationStatements params ++
    abiParamDecodeStatements params

def entrypointCallArgs (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.Expr :=
  Id.run do
    let mut args : Array Lean.Compiler.Yul.Expr := #[]
    for h : i in [0:params.size] do
      let param := params[i]
      if param.isDynamic then
        args := args.push (Lean.Compiler.Yul.Expr.id (dynamicParamLengthName param.name))
        args := args.push (Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName param.name))
      else
        for h : j in [0:param.wordTypes.size] do
          args := args.push (calldataWordExpr (param.headWordIndex + j))
    args

def entrypointParamTypedNames (params : Array AbiParamPlan) :
    Array Lean.Compiler.Yul.TypedName :=
  params.foldl
    (fun acc param =>
      acc ++ param.localNames.map (fun name => ({ name := name } : Lean.Compiler.Yul.TypedName)))
    #[]

def returnTypedNames (returns : ReturnPlan) : Array Lean.Compiler.Yul.TypedName :=
  returns.localNames.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName)

def entrypointCallExpr
    (moduleName : String)
    (entrypoint : EntrypointPlan) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.call (entrypointPlanFunctionName moduleName entrypoint) (entrypointCallArgs entrypoint.params)

def entrypointFunctionDefinition
    (moduleName : String)
    (entrypoint : EntrypointPlan)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Statement :=
  .funcDef
    (entrypointPlanFunctionName moduleName entrypoint)
    (entrypointParamTypedNames entrypoint.params)
    (returnTypedNames entrypoint.returns)
    { statements := bodyStatements }

/-- Build a fallback or receive function definition. These have no params,
   no return value, and use a fixed name (`__pf_fallback` or `__pf_receive`). -/
def fallbackReceiveFunctionDefinition
    (funcName : String)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Statement :=
  .funcDef funcName #[] #[] { statements := bodyStatements }

/-- Function name for a fallback or receive entrypoint. -/
def fallbackReceiveFunctionName (kind : ProofForge.IR.EntrypointKind) : String :=
  match kind with
  | .fallback => "__pf_fallback"
  | .receive => "__pf_receive"
  | .function => "__pf_fallback"  -- shouldn't happen, but provide a default

def dispatchSelectorExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "shr" #[
    Lean.Compiler.Yul.Expr.num 224,
    Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num 0]
  ]

def eip1967ImplementationSlotExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.lit
    (Lean.Compiler.Yul.Literal.hex "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc")

def uupsProxyFallbackBody : Array Lean.Compiler.Yul.Statement := #[
  .varDecl #[{ name := "_impl" }] (some (Lean.Compiler.Yul.builtin "sload" #[eip1967ImplementationSlotExpr])),
  .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_impl"]) { statements := #[revertStatement] },
  .exprStmt (Lean.Compiler.Yul.builtin "calldatacopy" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "calldatasize" #[]
  ]),
  .varDecl #[{ name := "_ok" }] (some (Lean.Compiler.Yul.builtin "delegatecall" #[
    Lean.Compiler.Yul.builtin "gas" #[],
    Lean.Compiler.Yul.Expr.id "_impl",
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "calldatasize" #[],
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0
  ])),
  .exprStmt (Lean.Compiler.Yul.builtin "returndatacopy" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "returndatasize" #[]
  ]),
  .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.Expr.id "_ok"]) {
    statements := #[
      .exprStmt (Lean.Compiler.Yul.builtin "revert" #[
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.builtin "returndatasize" #[]
      ])
    ]
  },
  .exprStmt (Lean.Compiler.Yul.builtin "return" #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.builtin "returndatasize" #[]
  ])
]

def dispatchDefaultCase (defaultPlan : DispatchDefaultPlan) : Lean.Compiler.Yul.Case :=
  match defaultPlan with
  | .revert => {
      value := none
      body := { statements := #[revertStatement] }
    }
  | .uupsProxy => {
      value := none
      body := { statements := uupsProxyFallbackBody }
    }
  | .fallback => {
      value := none
      body := { statements := #[
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "calldatasize" #[]])
          { statements := #[
            .exprStmt (Lean.Compiler.Yul.call "__pf_receive" #[]),
            .exprStmt (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
          ] },
        .exprStmt (Lean.Compiler.Yul.call "__pf_fallback" #[])
      ] }
    }
  | .receive => {
      value := none
      body := { statements := #[
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[Lean.Compiler.Yul.builtin "calldatasize" #[]])
          { statements := #[
            .exprStmt (Lean.Compiler.Yul.call "__pf_receive" #[]),
            .exprStmt (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
          ] },
        .exprStmt (Lean.Compiler.Yul.call "__pf_fallback" #[])
      ] }
    }

def entrypointDispatchCase
    {ε : Type}
    (mkError : String → ε)
    (entrypoint : EntrypointPlan)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) :
    Except ε Lean.Compiler.Yul.Case := do
  if entrypoint.selector.isEmpty then
    .error (mkError s!"EVM EntrypointPlan dispatch case for `{entrypoint.name}` requires a selector")
  else
    .ok {
      value := some (Lean.Compiler.Yul.Literal.hex ("0x" ++ entrypoint.selector))
      body := { statements := bodyStatements }
    }

def dispatchSwitchStatement
    (cases : Array Lean.Compiler.Yul.Case)
    (defaultCase : Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  .switchStmt dispatchSelectorExpr (cases.push defaultCase)

def abiParamPlanIsDynamic (param : AbiParamPlan) : Bool :=
  param.isDynamic

def entrypointPlanHasDynamicParams (entrypoint : EntrypointPlan) : Bool :=
  entrypoint.params.any abiParamPlanIsDynamic

def dispatchBlockStatement
    (entrypoints : Array EntrypointPlan)
    (cases : Array Lean.Compiler.Yul.Case)
    (defaultCase : Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  let switchStmt := dispatchSwitchStatement cases defaultCase
  if entrypoints.any entrypointPlanHasDynamicParams then
    .block { statements := #[
      Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 64, Lean.Compiler.Yul.Expr.num 128]),
      switchStmt
    ] }
  else
    switchStmt

def dispatchPlanStatement
    (dispatch : DispatchPlan)
    (cases : Array Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  dispatchBlockStatement dispatch.entrypoints cases (dispatchDefaultCase dispatch.default)

def dispatchResultName (index : Nat) : String :=
  s!"_r{index}"

def dispatchResultNames (wordCount : Nat) : Array String :=
  if wordCount == 1 then
    #["_r"]
  else
    Id.run do
      let mut names : Array String := #[]
      for _h : idx in [0:wordCount] do
        names := names.push (dispatchResultName idx)
      names

def staticDispatchReturnStatements
    {ε : Type}
    (mkError : String → ε)
    (validationStatements : Array Lean.Compiler.Yul.Statement)
    (returns : ReturnPlan)
    (callExpr : Lean.Compiler.Yul.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  match returns.returnType with
  | .unit =>
    .ok (validationStatements ++ #[
      Lean.Compiler.Yul.Statement.exprStmt callExpr,
      Lean.Compiler.Yul.Statement.exprStmt
        (Lean.Compiler.Yul.builtin "return" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])
    ])
  | .bytes | .string | .array _ =>
      .error (mkError s!"EVM static dispatch return plan does not support dynamic `{returns.returnType.name}`")
  | _ =>
      if returns.wordTypes.isEmpty then
        .error (mkError s!"EVM dispatch return plan for `{returns.returnType.name}` has no ABI words")
      else
        let resultNames := dispatchResultNames returns.wordTypes.size
        let mut statements : Array Lean.Compiler.Yul.Statement :=
          validationStatements ++ #[
            Lean.Compiler.Yul.Statement.varDecl
              (resultNames.map fun name => ({ name := name } : Lean.Compiler.Yul.TypedName))
              (some callExpr)
          ]
        for h : idx in [0:resultNames.size] do
          statements := statements.push <|
            Lean.Compiler.Yul.Statement.exprStmt
              (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.Expr.num (idx * 32),
                Lean.Compiler.Yul.Expr.id resultNames[idx]
              ])
        statements := statements.push <|
          Lean.Compiler.Yul.Statement.exprStmt
            (Lean.Compiler.Yul.builtin "return" #[
              Lean.Compiler.Yul.Expr.num 0,
              Lean.Compiler.Yul.Expr.num (returns.wordTypes.size * 32)
            ])
        .ok statements

def dynamicDispatchReturnStatements
    {ε : Type}
    (mkError : String → ε)
    (validationStatements : Array Lean.Compiler.Yul.Statement)
    (returns : ReturnPlan)
    (callExpr : Lean.Compiler.Yul.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  match returns.returnType with
  | .bytes | .string | .array _ =>
      let retWordCountExpr :=
        match returns.returnType with
        | .array _ => Lean.Compiler.Yul.Expr.id "_ret_len"
        | _ => Lean.Compiler.Yul.builtin "div" #[
            Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_ret_len", Lean.Compiler.Yul.Expr.num 31],
            Lean.Compiler.Yul.Expr.num 32
          ]
      .ok (validationStatements ++ #[
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_r" }] (some callExpr),
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_ret_len" }]
          (some (Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.id "_r"])),
        Lean.Compiler.Yul.Statement.varDecl #[{ name := "_ret_word_count" }]
          (some retWordCountExpr),
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 32]),
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 32, Lean.Compiler.Yul.Expr.id "_ret_len"]),
        Lean.Compiler.Yul.Statement.forLoop
          { statements := #[
            Lean.Compiler.Yul.Statement.varDecl #[{ name := "_i" }]
              (some (Lean.Compiler.Yul.Expr.num 0))
          ] }
          (Lean.Compiler.Yul.builtin "lt" #[
            Lean.Compiler.Yul.Expr.id "_i",
            Lean.Compiler.Yul.Expr.id "_ret_word_count"
          ])
          { statements := #[
            Lean.Compiler.Yul.Statement.assignment #["_i"]
              (Lean.Compiler.Yul.builtin "add" #[
                Lean.Compiler.Yul.Expr.id "_i",
                Lean.Compiler.Yul.Expr.num 1
              ])
          ] }
          { statements := #[
            Lean.Compiler.Yul.Statement.exprStmt
              (Lean.Compiler.Yul.builtin "mstore" #[
                Lean.Compiler.Yul.builtin "add" #[
                  Lean.Compiler.Yul.Expr.num 64,
                  Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 32]
                ],
                Lean.Compiler.Yul.builtin "mload" #[
                  Lean.Compiler.Yul.builtin "add" #[
                    Lean.Compiler.Yul.builtin "add" #[Lean.Compiler.Yul.Expr.id "_r", Lean.Compiler.Yul.Expr.num 32],
                    Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_i", Lean.Compiler.Yul.Expr.num 32]
                  ]
                ]
              ])
          ] },
        Lean.Compiler.Yul.Statement.exprStmt
          (Lean.Compiler.Yul.builtin "return" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.builtin "add" #[
              Lean.Compiler.Yul.Expr.num 64,
              Lean.Compiler.Yul.builtin "mul" #[Lean.Compiler.Yul.Expr.id "_ret_word_count", Lean.Compiler.Yul.Expr.num 32]
            ]
          ])
      ])
  | _ =>
      .error (mkError s!"EVM dynamic dispatch return plan expected a dynamic type, got `{returns.returnType.name}`")

def hashPackExpr
    (a b c d : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "or" #[
    Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 192, a],
    Lean.Compiler.Yul.builtin "or" #[
      Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 128, b],
      Lean.Compiler.Yul.builtin "or" #[
        Lean.Compiler.Yul.builtin "shl" #[Lean.Compiler.Yul.Expr.num 64, c],
        d
      ]
    ]
  ]

def packedUtf8Words (value : String) : Array Nat × Nat := Id.run do
  let bytes := value.toUTF8
  let wordCount := (bytes.size + 31) / 32
  let mut words := #[]
  for _h : wordIdx in [0:wordCount] do
    let mut wordVal := 0
    for _h : byteIdx in [0:32] do
      let pos := wordIdx * 32 + byteIdx
      if pos < bytes.size then
        let b := (bytes.get! pos).toNat
        let shift := (31 - byteIdx) * 8
        wordVal := wordVal + (b * (2 ^ shift))
    words := words.push wordVal
  pure (words, bytes.size)

def eventIndexedTopicName (index : Nat) : String :=
  s!"_indexed_topic{index}"

def eventIndexedFieldCount (event : EventPlan) : Nat :=
  event.indexedFields.size

def eventLogBuiltinName
    {ε : Type}
    (mkError : String → ε)
    (indexedFieldCount : Nat) : Except ε String :=
  if indexedFieldCount <= 3 then
    .ok s!"log{indexedFieldCount + 1}"
  else
    .error (mkError "EVM IR v0 supports at most 3 indexed event fields")

def eventSignatureTopicStatements (event : EventPlan) : Array Lean.Compiler.Yul.Statement := Id.run do
  let (words, length) := packedUtf8Words event.signature
  let mut statements := #[]
  for _h : idx in [0:words.size] do
    statements := statements.push <|
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num (idx * 32),
        Lean.Compiler.Yul.Expr.num words[idx]
      ])
  pure <| statements.push <|
    .varDecl #[{ name := "_topic0" }]
      (some (Lean.Compiler.Yul.builtin "keccak256" #[
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num length
      ]))

def eventDataStoreStatements (words : Array Lean.Compiler.Yul.Expr) : Array Lean.Compiler.Yul.Statement := Id.run do
  let mut statements := #[]
  for _h : idx in [0:words.size] do
    statements := statements.push <|
      .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[
        Lean.Compiler.Yul.Expr.num (idx * 32),
        words[idx]
      ])
  pure statements

def eventIndexedTopicStatements
    {ε : Type}
    (mkError : String → ε)
    (field : EventFieldPlan)
    (index : Nat)
    (words : Array Lean.Compiler.Yul.Expr) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  let topicName := eventIndexedTopicName index
  match field.type with
  | .u8 | .u32 | .u64 | .u128 | .bool | .hash | .address =>
      match words[0]? with
      | some word =>
          if words.size == 1 then
            .ok #[.varDecl #[{ name := topicName }] (some word)]
          else
            .error (mkError s!"EVM indexed scalar event field `{field.name}` expected one data word, got {words.size}")
      | none =>
          .error (mkError s!"EVM indexed scalar event field `{field.name}` expected one data word, got 0")
  | .fixedArray _ _ | .structType _ | .array _ =>
      .ok <| eventDataStoreStatements words |>.push
        (.varDecl #[{ name := topicName }]
          (some (Lean.Compiler.Yul.builtin "keccak256" #[
            Lean.Compiler.Yul.Expr.num 0,
            Lean.Compiler.Yul.Expr.num (words.size * 32)
          ])))
  | .unit | .bytes | .string =>
      .error (mkError s!"EVM indexed event field `{field.name}` has unsupported type `{field.type.name}`")

def eventFieldDataWordsFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (eventName : String)
    (field : EventFieldPlan)
    (value : AbiValuePlan) :
    Except ε (Array Lean.Compiler.Yul.Expr) := do
  abiValueWordsFromPlan
    mkError
    lowerPlanExpr
    structFields
    storageStructWords
    storageArrayWords
    s!"planned event `{eventName}` field `{field.name}`"
    field.type
    value

def eventFieldsDataWordsFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (eventName : String)
    (fields : Array EventFieldPlan)
    (values : Array AbiValuePlan) :
    Except ε (Array Lean.Compiler.Yul.Expr) := do
  if fields.size != values.size then
    .error (mkError s!"planned scalar control-flow event `{eventName}` field/value count mismatch")
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for h : idx in [0:fields.size] do
    let some value := values[idx]?
      | .error (mkError s!"planned scalar control-flow event `{eventName}` missing field value at index {idx}")
    words := words ++
      (← eventFieldDataWordsFromPlan
        mkError
        lowerPlanExpr
        structFields
        storageStructWords
        storageArrayWords
        eventName
        fields[idx]
        value)
  .ok words

def eventIndexedTopicStatementsFromPlans
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFields : String → Except ε (Array (String × ValueType)))
    (storageStructWords : String → String → String → Except ε (Array Lean.Compiler.Yul.Expr))
    (storageArrayWords : String → String → ValueType → Nat → Except ε (Array Lean.Compiler.Yul.Expr))
    (event : EventPlan)
    (values : Array AbiValuePlan) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  let fields := event.indexedFields
  if fields.size != values.size then
    .error (mkError s!"planned scalar control-flow event `{event.name}` indexed field/value count mismatch")
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:fields.size] do
    let some value := values[idx]?
      | .error (mkError s!"planned scalar control-flow event `{event.name}` missing indexed field value at index {idx}")
    let words ←
      eventFieldDataWordsFromPlan
        mkError
        lowerPlanExpr
        structFields
        storageStructWords
        storageArrayWords
        event.name
        fields[idx]
        value
    statements := statements ++ (← eventIndexedTopicStatements mkError fields[idx] idx words)
  .ok statements

def eventLogStatement
    {ε : Type}
    (mkError : String → ε)
    (event : EventPlan)
    (dataWordCount : Nat) : Except ε Lean.Compiler.Yul.Statement := do
  let indexedFieldCount := eventIndexedFieldCount event
  let mut logArgs : Array Lean.Compiler.Yul.Expr := #[
    Lean.Compiler.Yul.Expr.num 0,
    Lean.Compiler.Yul.Expr.num (dataWordCount * 32),
    Lean.Compiler.Yul.Expr.id "_topic0"
  ]
  for _h : idx in [0:indexedFieldCount] do
    logArgs := logArgs.push (Lean.Compiler.Yul.Expr.id (eventIndexedTopicName idx))
  .ok (.exprStmt (Lean.Compiler.Yul.builtin (← eventLogBuiltinName mkError indexedFieldCount) logArgs))

def eventEmitCoreStatement
    {ε : Type}
    (mkError : String → ε)
    (event : EventPlan)
    (indexedTopicStatements : Array Lean.Compiler.Yul.Statement)
    (dataWords : Array Lean.Compiler.Yul.Expr) :
    Except ε Lean.Compiler.Yul.Statement := do
  let mut statements := eventSignatureTopicStatements event
  statements := statements ++ indexedTopicStatements
  statements := statements ++ eventDataStoreStatements dataWords
  statements := statements.push (← eventLogStatement mkError event dataWords.size)
  .ok (.block { statements := statements })

def eventFieldWordPlanExprs
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (event : EventPlan)
    (fields : Array EventFieldPlan)
    (fieldWords : Array (Array ExprPlan)) :
    Except ε (Array Lean.Compiler.Yul.Expr) := do
  if fields.size != fieldWords.size then
    .error (mkError s!"planned scalar control-flow event `{event.name}` field/word-plan count mismatch")
  let mut words : Array Lean.Compiler.Yul.Expr := #[]
  for _h : idx in [0:fields.size] do
    let some fieldWordPlans := fieldWords[idx]?
      | .error (mkError s!"planned scalar control-flow event `{event.name}` missing field word plans at index {idx}")
    words := words ++ (← fieldWordPlans.mapM lowerPlanExpr)
  .ok words

def eventIndexedTopicStatementsFromWordPlans
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (event : EventPlan)
    (fieldWords : Array (Array ExprPlan)) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  let fields := event.indexedFields
  if fields.size != fieldWords.size then
    .error (mkError s!"planned scalar control-flow event `{event.name}` indexed field/word-plan count mismatch")
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  for h : idx in [0:fields.size] do
    let some fieldWordPlans := fieldWords[idx]?
      | .error (mkError s!"planned scalar control-flow event `{event.name}` missing indexed field word plans at index {idx}")
    let words ← fieldWordPlans.mapM lowerPlanExpr
    statements := statements ++ (← eventIndexedTopicStatements mkError fields[idx] idx words)
  .ok statements

def eventEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect (.eventEmitWords event dataFieldWords) => do
      let dataWords ← eventFieldWordPlanExprs
        mkError
        lowerPlanExpr
        event
        event.dataFields
        dataFieldWords
      .ok #[← eventEmitCoreStatement mkError event #[] dataWords]
  | .effect (.eventEmitIndexedWords event indexedFieldWords dataFieldWords) => do
      let indexedTopicStatements ← eventIndexedTopicStatementsFromWordPlans
        mkError
        lowerPlanExpr
        event
        indexedFieldWords
      let dataWords ← eventFieldWordPlanExprs
        mkError
        lowerPlanExpr
        event
        event.dataFields
        dataFieldWords
      .ok #[← eventEmitCoreStatement mkError event indexedTopicStatements dataWords]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul event effect lowering expected eventEmitWords/eventEmitIndexedWords")

def lowerValuePlan
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    ValuePlan → Except ε Lean.Compiler.Yul.Expr
  | .irExpr expr => lowerExpr expr

def lowerMapValueSlotExpr
    {ε : Type}
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ValuePlan) : Except ε Lean.Compiler.Yul.Expr := do
  let mut current := slotExpr rootSlot
  for key in keys do
    current := helperCall Helper.mapSlot #[current, ← lowerValuePlan lowerExpr key]
  .ok current

def lowerMapPresenceSlotExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ValuePlan) : Except ε Lean.Compiler.Yul.Expr := do
  match keys.toList.reverse with
  | [] => .error (mkError "EVM map presence slot plan requires at least one key")
  | last :: parentKeysReversed =>
      let mut parent := slotExpr rootSlot
      for key in parentKeysReversed.reverse do
        parent := helperCall Helper.mapSlot #[parent, ← lowerValuePlan lowerExpr key]
      .ok (helperCall Helper.mapPresenceSlot #[parent, ← lowerValuePlan lowerExpr last])

def storageSlotExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    StorageSlotPlan → Except ε Lean.Compiler.Yul.Expr
  | .scalarSlot slot => .ok (slotExpr slot)
  | .fixedSlot slotHex => .ok (Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex slotHex))
  | .mapValueSlot rootSlot keys =>
      if keys.isEmpty then
        .error (mkError "EVM map value slot plan requires at least one key")
      else
        lowerMapValueSlotExpr lowerExpr rootSlot keys
  | .mapPresenceSlot rootSlot keys =>
      lowerMapPresenceSlotExpr mkError lowerExpr rootSlot keys
  | .arraySlot rootSlot length index => do
      .ok (helperCall Helper.arraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        ← lowerValuePlan lowerExpr index
      ])
  | .structArrayFieldSlot rootSlot length fieldCount fieldOffset index => do
      .ok (helperCall Helper.structArraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        Lean.Compiler.Yul.Expr.num fieldCount,
        Lean.Compiler.Yul.Expr.num fieldOffset,
        ← lowerValuePlan lowerExpr index
      ])
  | .dynamicArraySlot rootSlot index => do
      .ok (helperCall Helper.dynamicArraySlot #[
        slotExpr rootSlot,
        ← lowerValuePlan lowerExpr index
      ])

def lowerMapValueSlotExprPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let mut current := slotExpr rootSlot
  for key in keys do
    current := helperCall Helper.mapSlot #[current, ← lowerPlanExpr key]
  .ok current

def lowerMapPresenceSlotExprPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (keys : Array ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  match keys.toList.reverse with
  | [] => .error (mkError "EVM map presence slot plan requires at least one key")
  | last :: parentKeysReversed =>
      let mut parent := slotExpr rootSlot
      for key in parentKeysReversed.reverse do
        parent := helperCall Helper.mapSlot #[parent, ← lowerPlanExpr key]
      .ok (helperCall Helper.mapPresenceSlot #[parent, ← lowerPlanExpr last])

def storageSlotExprPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StorageSlotExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .scalarSlot slot => .ok (slotExpr slot)
  | .fixedSlot slotHex => .ok (Lean.Compiler.Yul.Expr.lit (Lean.Compiler.Yul.Literal.hex slotHex))
  | .mapValueSlot rootSlot keys =>
      if keys.isEmpty then
        .error (mkError "EVM map value slot plan requires at least one key")
      else
        lowerMapValueSlotExprPlan lowerPlanExpr rootSlot keys
  | .mapPresenceSlot rootSlot keys =>
      lowerMapPresenceSlotExprPlan mkError lowerPlanExpr rootSlot keys
  | .arraySlot rootSlot length index => do
      .ok (helperCall Helper.arraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        ← lowerPlanExpr index
      ])
  | .structArrayFieldSlot rootSlot length fieldCount fieldOffset index => do
      .ok (helperCall Helper.structArraySlot #[
        slotExpr rootSlot,
        Lean.Compiler.Yul.Expr.num length,
        Lean.Compiler.Yul.Expr.num fieldCount,
        Lean.Compiler.Yul.Expr.num fieldOffset,
        ← lowerPlanExpr index
      ])
  | .dynamicArraySlot rootSlot index => do
      .ok (helperCall Helper.dynamicArraySlot #[
        slotExpr rootSlot,
        ← lowerPlanExpr index
      ])

def storagePathReadExprFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (slot : StorageSlotPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr slot])

def storagePathReadExprFromExprPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (slot : StorageSlotExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExprPlan mkError lowerPlanExpr slot])

partial def exprPlanExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    ExprPlan → Except ε Lean.Compiler.Yul.Expr
  | .literalWord value => .ok (Lean.Compiler.Yul.Expr.num value)
  | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
  | .calldataWord paramIndex => .ok (calldataWordExpr paramIndex)
  | .storageLoad slot => do
      .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr slot])
  | .builtin name args => do
      .ok (Lean.Compiler.Yul.builtin name (← args.mapM (exprPlanExpr mkError lowerExpr lowerEffect)))
  | .helperCall helper args => do
      .ok (helperCall helper (← args.mapM (exprPlanExpr mkError lowerExpr lowerEffect)))
  | .checkedArith op lhs rhs => do
      .ok (checkedArithExpr op
        (← exprPlanExpr mkError lowerExpr lowerEffect lhs)
        (← exprPlanExpr mkError lowerExpr lowerEffect rhs))
  | .hashPack a b c d => do
      .ok (hashPackExpr
        (← exprPlanExpr mkError lowerExpr lowerEffect a)
        (← exprPlanExpr mkError lowerExpr lowerEffect b)
        (← exprPlanExpr mkError lowerExpr lowerEffect c)
        (← exprPlanExpr mkError lowerExpr lowerEffect d))
  | .context field =>
      contextExprPlan (exprPlanExpr mkError lowerExpr lowerEffect) field
  | .crosscall mode target methodId callValue? args returnType =>
      crosscallExprPlanExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        (fun _ _ =>
          .error (mkError "generic ExprPlan-to-Yul crosscall lowering requires pre-expanded argument word plans"))
        (fun _ _ =>
          .error (mkError "generic ExprPlan-to-Yul crosscall lowering requires pre-expanded argument word plans"))
        mode
        target
        methodId
        callValue?
        args
        returnType
  | .create mode callValue salt? initCodeHex => do
      createHelperCallExpr
        mkError
        mode
        (← exprPlanExpr mkError lowerExpr lowerEffect callValue)
        (← salt?.mapM (exprPlanExpr mkError lowerExpr lowerEffect))
        initCodeHex
  | .cast source _ =>
      exprPlanExpr mkError lowerExpr lowerEffect source
  | .structField base fieldName =>
      localStructFieldExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        base
        fieldName
  | .arrayGet array index =>
      arrayGetExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        array
        index
  | .memoryArrayNew _ length => do
      .ok (helperCall Helper.memoryArrayNew #[← exprPlanExpr mkError lowerExpr lowerEffect length])
  | .memoryArrayLength array => do
      .ok (Lean.Compiler.Yul.builtin "mload" #[← exprPlanExpr mkError lowerExpr lowerEffect array])
  | .memoryArrayGet array index => do
      .ok (helperCall Helper.memoryArrayGet #[
        ← exprPlanExpr mkError lowerExpr lowerEffect array,
        ← exprPlanExpr mkError lowerExpr lowerEffect index
      ])
  | .localArrayGet name path lengths =>
      localArrayGetExpr
        mkError
        (exprPlanExpr mkError lowerExpr lowerEffect)
        name
        path
        lengths
  | .arrayLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support array literal plans yet")
  | .structLit .. =>
      .error (mkError "EVM ExprPlan-to-Yul scalar lowering does not support struct literal plans yet")
  | .hashValue a b c d => do
      .ok (hashPackExpr
        (← exprPlanExpr mkError lowerExpr lowerEffect a)
        (← exprPlanExpr mkError lowerExpr lowerEffect b)
        (← exprPlanExpr mkError lowerExpr lowerEffect c)
        (← exprPlanExpr mkError lowerExpr lowerEffect d))
  | .hash preimage => do
      .ok (helperCall Helper.hashWord #[← exprPlanExpr mkError lowerExpr lowerEffect preimage])
  | .hashTwoToOne lhs rhs => do
      .ok (helperCall Helper.hashPair #[
        ← exprPlanExpr mkError lowerExpr lowerEffect lhs,
        ← exprPlanExpr mkError lowerExpr lowerEffect rhs
      ])
  | .nativeValue =>
      .ok (Lean.Compiler.Yul.builtin "callvalue" #[])
  | .effect effect =>
      lowerEffect effect

/-! ## StmtPlan-to-Yul helpers -/

def stmtPlanBodyStatements
    {err state : Type}
    (plans : Array StmtPlan)
    (initialState : state)
    (leaveAfterReturn : Bool)
    (lowerStmt : state → Bool → StmtPlan → Except err (Array Lean.Compiler.Yul.Statement × state)) :
    Except err (Array Lean.Compiler.Yul.Statement × state) := do
  let mut statements : Array Lean.Compiler.Yul.Statement := #[]
  let mut currentState := initialState
  for h : idx in [0:plans.size] do
    let stmtLeaveAfterReturn := leaveAfterReturn || decide (idx + 1 < plans.size)
    let (lowered, nextState) ← lowerStmt currentState stmtLeaveAfterReturn plans[idx]
    statements := statements ++ lowered
    currentState := nextState
  .ok (statements, currentState)

def scalarBindingStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .letBind name _ value
  | .letMutBind name _ value => do
      .ok #[
        .varDecl
          #[({ name := name } : Lean.Compiler.Yul.TypedName)]
          (some (← exprPlanExpr mkError lowerExpr lowerEffect value))
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar binding lowering expected a let binding")

def assertStatementFromCondition
    (condition : Lean.Compiler.Yul.Expr)
    (revertStatements : Array Lean.Compiler.Yul.Statement) :
    Lean.Compiler.Yul.Statement :=
  Lean.Compiler.Yul.Statement.ifStmt
    (Lean.Compiler.Yul.builtin "iszero" #[condition])
    { statements := revertStatements }

def scalarAssertStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (revertStatementsFor : Option ProofForge.IR.ErrorRef → Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .assert condition _ errorRef? => do
      .ok #[
        assertStatementFromCondition
          (← exprPlanExpr mkError lowerExpr lowerEffect condition)
          (revertStatementsFor errorRef?)
      ]
  | .assertEq lhs rhs _ errorRef? => do
      let lhsExpr ← exprPlanExpr mkError lowerExpr lowerEffect lhs
      let rhsExpr ← exprPlanExpr mkError lowerExpr lowerEffect rhs
      .ok #[
        assertStatementFromCondition
          (Lean.Compiler.Yul.builtin "eq" #[lhsExpr, rhsExpr])
          (revertStatementsFor errorRef?)
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assertion lowering expected assert/assertEq")

def revertStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (revertStatementsFor : ProofForge.IR.ErrorRef → Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .revert message =>
      if message.isEmpty then
        .ok #[revertStatement]
      else
        .ok (revertWithMessageStatements message)
  | .revertWithError errorRef =>
      .ok (revertStatementsFor errorRef)
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul revert lowering expected revert/revertWithError")

def scalarReturnStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (returnNames : Array String)
    (leaveAfterReturn : Bool) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .return value => do
      let some returnName := returnNames[0]?
        | .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected one return name, got 0")
      if returnNames.size != 1 then
        .error (mkError s!"EVM StmtPlan-to-Yul scalar return lowering expected one return name, got {returnNames.size}")
      else
        let statements := #[
          Lean.Compiler.Yul.Statement.assignment
            #[returnName]
            (← exprPlanExpr mkError lowerExpr lowerEffect value)
        ]
        .ok <| if leaveAfterReturn then statements.push .leave else statements
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected return")

def scalarReturnExprPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (returnNames : Array String)
    (leaveAfterReturn : Bool) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .return value => do
      let some returnName := returnNames[0]?
        | .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected one return name, got 0")
      if returnNames.size != 1 then
        .error (mkError s!"EVM StmtPlan-to-Yul scalar return lowering expected one return name, got {returnNames.size}")
      else
        let statements := #[
          Lean.Compiler.Yul.Statement.assignment
            #[returnName]
            (← lowerPlanExpr value)
        ]
        .ok <| if leaveAfterReturn then statements.push .leave else statements
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar return lowering expected return")

def dynamicReturnStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (returns : ReturnPlan)
    (leaveAfterReturn : Bool) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .return (.local name) => do
      match returns.returnType with
      | .bytes | .string | .array _ =>
          let some returnName := returns.localNames[0]?
            | .error (mkError "EVM StmtPlan-to-Yul dynamic return lowering expected one return name, got 0")
          if returns.localNames.size != 1 then
            .error (mkError s!"EVM StmtPlan-to-Yul dynamic return lowering expected one return name, got {returns.localNames.size}")
          else
            let statements := #[
              Lean.Compiler.Yul.Statement.assignment
                #[returnName]
                (Lean.Compiler.Yul.Expr.id (dynamicParamDataPtrName name))
            ]
            .ok <| if leaveAfterReturn then statements.push .leave else statements
      | _ =>
          .error (mkError s!"EVM StmtPlan-to-Yul dynamic return lowering expected a dynamic return type, got `{returns.returnType.name}`")
  | .return _ =>
      .error (mkError "EVM StmtPlan-to-Yul dynamic return lowering supports local dynamic values only")
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul dynamic return lowering expected return")

def scalarAssignmentTargetName
    {ε : Type}
    (mkError : String → ε) : ExprPlan → Except ε String
  | .local targetName =>
      .ok targetName
  | .localArrayGet name path lengths => do
      let some staticPath := localArrayStaticPath? path
        | .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected a static local-array target")
      validateLocalArrayStaticPath mkError name staticPath lengths
      .ok (arrayLocalPathName name staticPath)
  | .structField (.local name) fieldName =>
      .ok (structLocalFieldName name fieldName)
  | .structField (.localArrayGet name path lengths) fieldName => do
      let some staticPath := localArrayStaticPath? path
        | .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected a static local-array struct-field target")
      validateLocalArrayStaticPath mkError name staticPath lengths
      .ok (arrayStructLocalPathFieldName name staticPath fieldName)
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected a local, static local-array, or static struct-field target")

def scalarAssignmentStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .assign target value => do
      let targetName ← scalarAssignmentTargetName mkError target
      .ok #[
        Lean.Compiler.Yul.Statement.assignment
          #[targetName]
          (← exprPlanExpr mkError lowerExpr lowerEffect value)
      ]
  | .assignOp target op value => do
      let targetName ← scalarAssignmentTargetName mkError target
      .ok #[
        Lean.Compiler.Yul.Statement.assignment
          #[targetName]
          (checkedArithExpr op
            (Lean.Compiler.Yul.Expr.id targetName)
            (← exprPlanExpr mkError lowerExpr lowerEffect value))
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar assignment lowering expected assign/assignOp")

structure FixedArrayAssignmentSource where
  index : Nat
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

structure StructArrayAssignmentSource where
  index : Nat
  fieldName : String
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

structure NestedFixedArrayAssignmentSource where
  path : Array Nat
  fieldName? : Option String
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

structure StructAssignmentSource where
  fieldName : String
  expr : Lean.Compiler.Yul.Expr
  deriving Inhabited

def aggregateAssignArrayTempName (name : String) (index : Nat) : String :=
  s!"__proof_forge_assign_array_{name}_{index}"

def aggregateAssignArrayPathTempName (name : String) (path : Array Nat) : String :=
  s!"__proof_forge_assign_array_{name}_{natPathSuffix path}"

def aggregateAssignStructTempName (name fieldName : String) : String :=
  s!"__proof_forge_assign_struct_{name}_{fieldName}"

def aggregateAssignStructArrayTempName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_assign_array_struct_{name}_{index}_{fieldName}"

def nestedFixedArrayTargetName (name : String) (path : Array Nat) (fieldName? : Option String) : String :=
  match fieldName? with
  | none => arrayLocalPathName name path
  | some fieldName => arrayStructLocalPathFieldName name path fieldName

def aggregateAssignNestedFixedArrayTempName (name : String) (path : Array Nat) (fieldName? : Option String) : String :=
  match fieldName? with
  | none => aggregateAssignArrayPathTempName name path
  | some fieldName => s!"__proof_forge_assign_array_struct_{name}_{natPathSuffix path}_{fieldName}"

def fixedArrayAssignmentStatements
    (name : String)
    (sources : Array FixedArrayAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl #[{ name := aggregateAssignArrayTempName name source.index }] (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[arrayLocalElementName name source.index]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignArrayTempName name source.index))
    statements

def wholeFixedArrayAssignStmt
    (name : String)
    (sources : Array FixedArrayAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := fixedArrayAssignmentStatements name sources }

def fixedArrayAssignmentSourceFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (source : FixedArrayAssignmentSourcePlan) :
    Except ε FixedArrayAssignmentSource := do
  .ok {
    index := source.index
    expr := ← lowerPlanExpr source.expr
  }

def wholeFixedArrayAssignStmtFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (sources : Array FixedArrayAssignmentSourcePlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  .ok <| wholeFixedArrayAssignStmt name (← sources.mapM (fixedArrayAssignmentSourceFromPlan lowerPlanExpr))

def structArrayAssignmentStatements
    (name : String)
    (sources : Array StructArrayAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl #[{ name := aggregateAssignStructArrayTempName name source.index source.fieldName }] (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[arrayStructLocalFieldName name source.index source.fieldName]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignStructArrayTempName name source.index source.fieldName))
    statements

def wholeStructArrayAssignStmt
    (name : String)
    (sources : Array StructArrayAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := structArrayAssignmentStatements name sources }

def nestedFixedArrayAssignmentStatements
    (name : String)
    (sources : Array NestedFixedArrayAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl
          #[{ name := aggregateAssignNestedFixedArrayTempName name source.path source.fieldName? }]
          (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[nestedFixedArrayTargetName name source.path source.fieldName?]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignNestedFixedArrayTempName name source.path source.fieldName?))
    statements

def wholeNestedFixedArrayAssignStmt
    (name : String)
    (sources : Array NestedFixedArrayAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := nestedFixedArrayAssignmentStatements name sources }

def structAssignmentStatements
    (name : String)
    (sources : Array StructAssignmentSource) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for source in sources do
      statements := statements.push <|
        .varDecl #[{ name := aggregateAssignStructTempName name source.fieldName }] (some source.expr)
    for source in sources do
      statements := statements.push <|
        .assignment
          #[structLocalFieldName name source.fieldName]
          (Lean.Compiler.Yul.Expr.id (aggregateAssignStructTempName name source.fieldName))
    statements

def wholeStructAssignStmt
    (name : String)
    (sources : Array StructAssignmentSource) : Lean.Compiler.Yul.Statement :=
  .block { statements := structAssignmentStatements name sources }

def structAssignmentSourceFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (source : StructAssignmentSourcePlan) :
    Except ε StructAssignmentSource := do
  .ok {
    fieldName := source.fieldName
    expr := ← lowerPlanExpr source.expr
  }

def wholeStructAssignStmtFromPlan
    {ε : Type}
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr)
    (name : String)
    (sources : Array StructAssignmentSourcePlan) :
    Except ε Lean.Compiler.Yul.Statement := do
  .ok <| wholeStructAssignStmt name (← sources.mapM (structAssignmentSourceFromPlan lowerPlanExpr))

def dynamicArrayIndexLocalName : String := "__proof_forge_array_index"

def dynamicArrayValueLocalName : String := "__proof_forge_array_value"

def dynamicArrayIndexPathLocalName (depth : Nat) : String :=
  s!"__proof_forge_array_index_{depth}"

def dynamicArrayValueExpr : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.id dynamicArrayValueLocalName

def dynamicAssignmentRhs
    (targetName : String)
    (op? : Option AssignOp) : Lean.Compiler.Yul.Expr :=
  match op? with
  | some op => checkedArithExpr op (Lean.Compiler.Yul.Expr.id targetName) dynamicArrayValueExpr
  | none => dynamicArrayValueExpr

def dynamicAssignmentStatement
    (targetName : String)
    (op? : Option AssignOp) : Lean.Compiler.Yul.Statement :=
  .assignment #[targetName] (dynamicAssignmentRhs targetName op?)

def dynamicLocalSwitchCase
    (index : Nat)
    (statements : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Case := {
  value := some (Lean.Compiler.Yul.Literal.natLit index)
  body := { statements }
}

def dynamicLocalSwitchDefaultCase : Lean.Compiler.Yul.Case := {
  value := none
  body := { statements := #[revertStatement] }
}

def dynamicLocalFixedArraySwitchCases
    (length : Nat)
    (bodyForIndex : Nat → Array Lean.Compiler.Yul.Statement) : Array Lean.Compiler.Yul.Case :=
  Id.run do
    let mut cases : Array Lean.Compiler.Yul.Case := #[]
    for _h : idx in [0:length] do
      cases := cases.push (dynamicLocalSwitchCase idx (bodyForIndex idx))
    cases.push dynamicLocalSwitchDefaultCase

def dynamicLocalValueSwitchBlock
    (indexExpr valueExpr : Lean.Compiler.Yul.Expr)
    (length : Nat)
    (bodyForIndex : Nat → Array Lean.Compiler.Yul.Statement) :
    Lean.Compiler.Yul.Statement :=
  .block {
    statements := #[
      .varDecl #[{ name := dynamicArrayIndexLocalName }] (some indexExpr),
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr),
      .switchStmt
        (Lean.Compiler.Yul.Expr.id dynamicArrayIndexLocalName)
        (dynamicLocalFixedArraySwitchCases length bodyForIndex)
    ]
  }

def dynamicLocalPathSwitchBlock
    (depth : Nat)
    (indexExpr : Lean.Compiler.Yul.Expr)
    (cases : Array Lean.Compiler.Yul.Case) : Lean.Compiler.Yul.Statement :=
  let indexName := dynamicArrayIndexPathLocalName depth
  .block {
    statements := #[
      .varDecl #[{ name := indexName }] (some indexExpr),
      .switchStmt (Lean.Compiler.Yul.Expr.id indexName) cases
    ]
  }

def dynamicLocalValueBlock
    (valueExpr : Lean.Compiler.Yul.Expr)
    (body : Array Lean.Compiler.Yul.Statement) : Lean.Compiler.Yul.Statement :=
  .block {
    statements := #[
      .varDecl #[{ name := dynamicArrayValueLocalName }] (some valueExpr)
    ] ++ body
  }

def ifElseStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (thenStatements elseStatements : Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .ifElse condition _ _ => do
      .ok #[
        .switchStmt
          (← exprPlanExpr mkError lowerExpr lowerEffect condition)
          #[
            {
              value := some (Lean.Compiler.Yul.Literal.natLit 0)
              body := { statements := elseStatements }
            },
            {
              value := none
              body := { statements := thenStatements }
            }
          ]
      ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul ifElse lowering expected ifElse")

def boundedForConditionPlan (indexName : String) (stopExclusive : Nat) : ExprPlan :=
  .builtin "lt" #[.local indexName, .literalWord stopExclusive]

def boundedForStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (bodyStatements : Array Lean.Compiler.Yul.Statement) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .boundedFor indexName start stopExclusive _ => do
      if stopExclusive <= start then
        .error (mkError s!"bounded loop `{indexName}` must have stop greater than start")
      else
        .ok #[
          .forLoop
            { statements := #[
              .varDecl #[{ name := indexName }] (some (Lean.Compiler.Yul.Expr.num start))
            ] }
            (← exprPlanExpr mkError lowerExpr lowerEffect
              (boundedForConditionPlan indexName stopExclusive))
            { statements := #[
              .assignment #[indexName]
                (Lean.Compiler.Yul.builtin "add" #[
                  Lean.Compiler.Yul.Expr.id indexName,
                  Lean.Compiler.Yul.Expr.num 1
                ])
            ] }
            { statements := bodyStatements }
        ]
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul boundedFor lowering expected boundedFor")

def scalarStorageWriteStatements
    (storageSlot valueExpr : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Array Lean.Compiler.Yul.Statement :=
  if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
    #[
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[storageSlot, valueExpr])
    ]
  else
    let shiftBits := (32 - (byteOffset + byteWidth)) * 8
    let mask := (2^(byteWidth * 8 : Nat)) - 1
    let shiftedMask := Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num shiftBits,
      Lean.Compiler.Yul.Expr.num mask
    ]
    #[
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
        storageSlot,
        Lean.Compiler.Yul.builtin "or" #[
          Lean.Compiler.Yul.builtin "and" #[
            Lean.Compiler.Yul.builtin "sload" #[storageSlot],
            Lean.Compiler.Yul.builtin "not" #[shiftedMask]
          ],
          Lean.Compiler.Yul.builtin "shl" #[
            Lean.Compiler.Yul.Expr.num shiftBits,
            valueExpr
          ]
        ]
      ])
    ]

def scalarStoragePackedReadExpr
    (storageSlot : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Lean.Compiler.Yul.Expr :=
  if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
    Lean.Compiler.Yul.builtin "sload" #[storageSlot]
  else
    let shiftBits := (32 - (byteOffset + byteWidth)) * 8
    let mask := (2^(byteWidth * 8 : Nat)) - 1
    Lean.Compiler.Yul.builtin "and" #[
      Lean.Compiler.Yul.builtin "shr" #[
        Lean.Compiler.Yul.Expr.num shiftBits,
        Lean.Compiler.Yul.builtin "sload" #[storageSlot]
      ],
      Lean.Compiler.Yul.Expr.num mask
    ]

def scalarStorageTargetReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (target : ScalarStorageTargetPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok <| scalarStoragePackedReadExpr
    (← storageSlotExpr mkError lowerExpr target.slot)
    target.byteOffset
    target.byteWidth

def scalarStorageAssignOpStatements
    (op : AssignOp)
    (storageSlot valueExpr : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Array Lean.Compiler.Yul.Statement :=
  let packedRead := scalarStoragePackedReadExpr storageSlot byteOffset byteWidth
  let computedValue := checkedArithExpr op packedRead valueExpr
  scalarStorageWriteStatements storageSlot computedValue byteOffset byteWidth

def scalarStorageEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (storageSlotFor : String → Except ε Lean.Compiler.Yul.Expr)
    (packingFor : String → Except ε (Nat × Nat)) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWrite stateId value => do
      let storageSlot ← storageSlotFor stateId
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      let (byteOffset, byteWidth) ← packingFor stateId
      .ok <| scalarStorageWriteStatements storageSlot valueExpr byteOffset byteWidth
  | .storageScalarAssignOp stateId op value => do
      let storageSlot ← storageSlotFor stateId
      let (byteOffset, byteWidth) ← packingFor stateId
      let rhs ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageAssignOpStatements op storageSlot rhs byteOffset byteWidth
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul scalar storage effect lowering expected storageScalarWrite/storageScalarAssignOp")

def scalarStorageEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (storageSlotFor : String → Except ε Lean.Compiler.Yul.Expr)
    (packingFor : String → Except ε (Nat × Nat)) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      scalarStorageEffectPlanStatements mkError lowerExpr lowerEffect storageSlotFor packingFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar storage effect lowering expected effect")

def scalarStorageTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWriteTarget target value => do
      let targetSlot ← storageSlotExpr mkError lowerExpr target.slot
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageWriteStatements targetSlot valueExpr target.byteOffset target.byteWidth
  | .storageScalarAssignOpTarget target op value => do
      let targetSlot ← storageSlotExpr mkError lowerExpr target.slot
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageAssignOpStatements op targetSlot valueExpr target.byteOffset target.byteWidth
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned scalar storage lowering expected storageScalarWriteTarget/storageScalarAssignOpTarget")

def scalarStorageTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      scalarStorageTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned scalar storage lowering expected effect")

def mapWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (mapRootSlotFor : String → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageMapInsert stateId key value
  | .storageMapSet stateId key value => do
      .ok #[
        .exprStmt (helperCall Helper.mapWrite #[
          ← mapRootSlotFor stateId,
          ← exprPlanExpr mkError lowerExpr lowerEffect key,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul map write lowering expected storageMapInsert/storageMapSet")

def mapWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (mapRootSlotFor : String → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      mapWriteEffectPlanStatements mkError lowerExpr lowerEffect mapRootSlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul map write lowering expected effect")

def mapSetReturnTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapWriteTargetPlan)
    (key value : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (helperCall Helper.mapSetReturn #[
    slotExpr target.rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key,
    ← exprPlanExpr mkError lowerExpr lowerEffect value
  ])

def mapContainsExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let presenceSlot := helperCall Helper.mapPresenceSlot #[
    slotExpr rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key
  ]
  .ok (Lean.Compiler.Yul.builtin "iszero" #[
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "sload" #[presenceSlot]
    ]
  ])

def mapContainsTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapReadTargetPlan)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  mapContainsExpr mkError lowerExpr lowerEffect target.rootSlot key

def mapGetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let valueSlot := helperCall Helper.mapSlot #[
    slotExpr rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[valueSlot])

def mapGetTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapReadTargetPlan)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  mapGetExpr mkError lowerExpr lowerEffect target.rootSlot key

def mapWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageMapInsertTarget target key value
  | .storageMapSetTarget target key value => do
      .ok #[
        .exprStmt (helperCall Helper.mapWrite #[
          slotExpr target.rootSlot,
          ← exprPlanExpr mkError lowerExpr lowerEffect key,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned map write lowering expected storageMapInsertTarget/storageMapSetTarget")

def mapWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      mapWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned map write lowering expected effect")

def arrayWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (arraySlotFor : String → ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayWrite stateId index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← arraySlotFor stateId index,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul array write lowering expected storageArrayWrite")

def arrayWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (arraySlotFor : String → ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      arrayWriteEffectPlanStatements mkError lowerExpr lowerEffect arraySlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul array write lowering expected effect")

def arrayReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot length : Nat)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let elementSlot := helperCall Helper.arraySlot #[
    slotExpr rootSlot,
    Lean.Compiler.Yul.Expr.num length,
    ← exprPlanExpr mkError lowerExpr lowerEffect index
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[elementSlot])

def arrayReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : ArrayReadTargetPlan)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  arrayReadExpr mkError lowerExpr lowerEffect target.rootSlot target.length index

def arrayWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayWriteTarget target index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.arraySlot #[
            slotExpr target.rootSlot,
            Lean.Compiler.Yul.Expr.num target.length,
            ← exprPlanExpr mkError lowerExpr lowerEffect index
          ],
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned array write lowering expected storageArrayWriteTarget")

def arrayWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      arrayWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned array write lowering expected effect")

def dynamicArraySlotTargetExpr
    (target : DynamicArrayTargetPlan)
    (index : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  helperCall Helper.dynamicArraySlot #[slotExpr target.rootSlot, index]

def dynamicArrayPushTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageDynamicArrayPushTarget target value => do
      let baseSlot := slotExpr target.rootSlot
      let lenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_len"
      let newLenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_new_len"
      .ok #[
        .varDecl #[{ name := "__proof_forge_dyn_array_len" }] (some (Lean.Compiler.Yul.builtin "sload" #[baseSlot])),
        .varDecl #[{ name := "__proof_forge_dyn_array_new_len" }]
          (some (Lean.Compiler.Yul.builtin "add" #[lenExpr, Lean.Compiler.Yul.Expr.num 1])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          dynamicArraySlotTargetExpr target lenExpr,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[baseSlot, newLenExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned dynamic array push lowering expected storageDynamicArrayPushTarget")

def dynamicArrayPushTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      dynamicArrayPushTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned dynamic array push lowering expected effect")

def dynamicArrayPopTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageDynamicArrayPopTarget target => do
      let baseSlot := slotExpr target.rootSlot
      let lenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_len"
      let newLenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_new_len"
      .ok #[
        .varDecl #[{ name := "__proof_forge_dyn_array_len" }] (some (Lean.Compiler.Yul.builtin "sload" #[baseSlot])),
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[lenExpr])
          { statements := #[.exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])] },
        .varDecl #[{ name := "__proof_forge_dyn_array_new_len" }]
          (some (Lean.Compiler.Yul.builtin "sub" #[lenExpr, Lean.Compiler.Yul.Expr.num 1])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[baseSlot, newLenExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned dynamic array pop lowering expected storageDynamicArrayPopTarget")

def dynamicArrayPopTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      dynamicArrayPopTargetEffectPlanStatements mkError effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned dynamic array pop lowering expected effect")

def structFieldWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFieldSlotFor : String → String → Except ε Lean.Compiler.Yul.Expr)
    (structArrayFieldSlotFor : String → ExprPlan → String → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageStructFieldWrite stateId fieldName value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← structFieldSlotFor stateId fieldName,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← structArrayFieldSlotFor stateId index fieldName,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul struct field write lowering expected storageStructFieldWrite/storageArrayStructFieldWrite")

def structFieldWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFieldSlotFor : String → String → Except ε Lean.Compiler.Yul.Expr)
    (structArrayFieldSlotFor : String → ExprPlan → String → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structFieldWriteEffectPlanStatements mkError lowerExpr lowerEffect structFieldSlotFor structArrayFieldSlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul struct field write lowering expected effect")

def structFieldWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageStructFieldWriteTarget target value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← storageSlotExpr mkError lowerExpr target.slot,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned struct field write lowering expected storageStructFieldWriteTarget")

def structFieldWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structFieldWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned struct field write lowering expected effect")

def structArrayFieldWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayStructFieldWriteTarget target index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.structArraySlot #[
            slotExpr target.rootSlot,
            Lean.Compiler.Yul.Expr.num target.length,
            Lean.Compiler.Yul.Expr.num target.fieldCount,
            Lean.Compiler.Yul.Expr.num target.fieldOffset,
            ← exprPlanExpr mkError lowerExpr lowerEffect index
          ],
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned struct-array field write lowering expected storageArrayStructFieldWriteTarget")

def structArrayFieldWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structArrayFieldWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned struct-array field write lowering expected effect")

def structFieldReadExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "sload" #[slotExpr slot]

def structFieldReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (target : StructFieldReadTargetPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr target.slot])

def structArrayFieldReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot length fieldCount fieldOffset : Nat)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let fieldSlot := helperCall Helper.structArraySlot #[
    slotExpr rootSlot,
    Lean.Compiler.Yul.Expr.num length,
    Lean.Compiler.Yul.Expr.num fieldCount,
    Lean.Compiler.Yul.Expr.num fieldOffset,
    ← exprPlanExpr mkError lowerExpr lowerEffect index
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[fieldSlot])

def structArrayFieldReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : StructArrayFieldReadTargetPlan)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  structArrayFieldReadExpr
    mkError lowerExpr lowerEffect
    target.rootSlot target.length target.fieldCount target.fieldOffset
    index

structure StorageStructWriteField where
  slot : Lean.Compiler.Yul.Expr
  fieldName : String
  value : Lean.Compiler.Yul.Expr
  deriving Inhabited

def storageStructAssignTempName (stateId fieldName : String) : String :=
  s!"__proof_forge_assign_storage_struct_{stateId}_{fieldName}"

def storageStructWriteStatements
    (stateId : String)
    (fields : Array StorageStructWriteField) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for field in fields do
      statements := statements.push <|
        .varDecl #[{ name := storageStructAssignTempName stateId field.fieldName }] (some field.value)
    for field in fields do
      statements := statements.push <|
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          field.slot,
          Lean.Compiler.Yul.Expr.id (storageStructAssignTempName stateId field.fieldName)
        ])
    pure statements

def storageStructWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (storageStructFieldsFor : String → ExprPlan → Except ε (Array StorageStructWriteField)) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWrite stateId value => do
      .ok #[
        .block { statements := storageStructWriteStatements stateId (← storageStructFieldsFor stateId value) }
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul storage struct write lowering expected storageScalarWrite")

def storageStructWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (storageStructFieldsFor : String → ExprPlan → Except ε (Array StorageStructWriteField)) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storageStructWriteEffectPlanStatements mkError storageStructFieldsFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul storage struct write lowering expected effect")

inductive StoragePathWriteTarget where
  | mapWrite (rootSlot key : Lean.Compiler.Yul.Expr)
  | singleSlot (slot : Lean.Compiler.Yul.Expr)
  | mapValuePresence (valueSlot presenceSlot : Lean.Compiler.Yul.Expr)
  deriving Inhabited

def storagePathWriteTargetFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    StoragePathWriteTargetPlan → Except ε StoragePathWriteTarget
  | .mapWrite rootSlot key => do
      .ok (.mapWrite (slotExpr rootSlot) (← lowerValuePlan lowerExpr key))
  | .singleSlot slot => do
      .ok (.singleSlot (← storageSlotExpr mkError lowerExpr slot))
  | .mapValuePresence valueSlot presenceSlot => do
      .ok (.mapValuePresence
        (← storageSlotExpr mkError lowerExpr valueSlot)
        (← storageSlotExpr mkError lowerExpr presenceSlot))

def storagePathWriteExprTargetFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StoragePathWriteExprTargetPlan → Except ε StoragePathWriteTarget
  | .mapWrite rootSlot key => do
      .ok (.mapWrite (slotExpr rootSlot) (← lowerPlanExpr key))
  | .singleSlot slot => do
      .ok (.singleSlot (← storageSlotExprPlan mkError lowerPlanExpr slot))
  | .mapValuePresence valueSlot presenceSlot => do
      .ok (.mapValuePresence
        (← storageSlotExprPlan mkError lowerPlanExpr valueSlot)
        (← storageSlotExprPlan mkError lowerPlanExpr presenceSlot))

def storagePathWriteTargetStatements
    (value : Lean.Compiler.Yul.Expr) :
    StoragePathWriteTarget → Array Lean.Compiler.Yul.Statement
  | .mapWrite rootSlot key =>
      #[
        .exprStmt (helperCall Helper.mapWrite #[rootSlot, key, value])
      ]
  | .singleSlot slot =>
      #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[slot, value])
      ]
  | .mapValuePresence valueSlot presenceSlot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some valueSlot),
          .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            value
          ]),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_presence_slot",
            Lean.Compiler.Yul.Expr.num 1
          ])
        ]}
      ]

def storagePathWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathWriteTarget target value => do
      .ok <| storagePathWriteTargetStatements
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteTargetFromPlan mkError lowerExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path write lowering expected storagePathWriteTarget")

def storagePathWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path write lowering expected effect")

def storagePathWriteExprTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathWriteExprTarget target value => do
      .ok <| storagePathWriteTargetStatements
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteExprTargetFromPlan mkError lowerPlanExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path write expr lowering expected storagePathWriteExprTarget")

def storagePathWriteExprTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathWriteExprTargetEffectPlanStatements mkError lowerExpr lowerEffect lowerPlanExpr effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path write expr lowering expected effect")

def storagePathAssignOpTargetStatements
    (op : AssignOp)
    (value : Lean.Compiler.Yul.Expr) :
    StoragePathWriteTarget → Array Lean.Compiler.Yul.Statement
  | .mapWrite rootSlot key =>
      #[
        .exprStmt (helperCall (Helper.mapAssign op) #[rootSlot, key, value])
      ]
  | .singleSlot slot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some slot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            checkedArithExpr op
              (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"])
              value
          ])
        ]}
      ]
  | .mapValuePresence valueSlot presenceSlot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some valueSlot),
          .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            checkedArithExpr op
              (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"])
              value
          ]),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_presence_slot",
            Lean.Compiler.Yul.Expr.num 1
          ])
        ]}
      ]

def storagePathAssignOpTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathAssignOpTarget target op value => do
      .ok <| storagePathAssignOpTargetStatements op
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteTargetFromPlan mkError lowerExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path assign_op lowering expected storagePathAssignOpTarget")

def storagePathAssignOpTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathAssignOpTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path assign_op lowering expected effect")

def storagePathAssignOpExprTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathAssignOpExprTarget target op value => do
      .ok <| storagePathAssignOpTargetStatements
        op
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteExprTargetFromPlan mkError lowerPlanExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path assign_op expr lowering expected storagePathAssignOpExprTarget")

def storagePathAssignOpExprTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathAssignOpExprTargetEffectPlanStatements mkError lowerExpr lowerEffect lowerPlanExpr effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path assign_op expr lowering expected effect")
def memoryArraySetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .memoryArraySet array index value => do
      let arrayExpr ← exprPlanExpr mkError lowerExpr lowerEffect array
      let indexExpr ← exprPlanExpr mkError lowerExpr lowerEffect index
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      let lengthExpr := Lean.Compiler.Yul.builtin "mload" #[arrayExpr]
      let inBounds := Lean.Compiler.Yul.builtin "lt" #[indexExpr, lengthExpr]
      let revertGuard := Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "iszero" #[inBounds])
        { statements := #[revertStatement] }
      let elementPtr := Lean.Compiler.Yul.builtin "add" #[
        Lean.Compiler.Yul.builtin "add" #[arrayExpr, Lean.Compiler.Yul.Expr.num 32],
        Lean.Compiler.Yul.builtin "mul" #[indexExpr, Lean.Compiler.Yul.Expr.num 32]
      ]
      .ok #[
        revertGuard,
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[elementPtr, valueExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul memory array set lowering expected memoryArraySet")

def memoryArraySetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      memoryArraySetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul memory array set lowering expected effect")

/-! ## Plan-driven helper requirements

`StorageSlotPlan.requiredHelpers` lets the plan declare which EVM helper functions
a given slot plan needs, without `ToYul` re-discovering them from Yul text. -/

def slotHelperRequirements (slot : StorageSlotPlan) : HelperSet :=
  slot.requiredHelpers

def storageLayoutHelpers (layout : StorageLayout) : HelperSet :=
  layout.states.foldl (init := #[]) fun acc state =>
    match state.kind with
    | .map _ _ => HelperSet.insert (HelperSet.insert acc Helper.mapSlot) Helper.mapPresenceSlot
    | _ => acc

end ProofForge.Backend.Evm.ToYul
