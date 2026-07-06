import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Backend.Evm.ToYul.Create
import ProofForge.Backend.Evm.ToYul.Crosscall
import ProofForge.Backend.Evm.ToYul.Helpers
import ProofForge.Backend.Evm.ToYul.Local
import ProofForge.Backend.Evm.ToYul.Abi
import ProofForge.Backend.Evm.ToYul.Event
import ProofForge.Backend.Evm.ToYul.Effect
import ProofForge.Backend.Evm.ToYul.Storage
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def entrypointFunctionName (moduleName entrypointName : String) : String :=
  s!"f_{moduleName}_{entrypointName}"

def entrypointPlanFunctionName (moduleName : String) (entrypoint : EntrypointPlan) : String :=
  entrypointFunctionName moduleName entrypoint.name

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
