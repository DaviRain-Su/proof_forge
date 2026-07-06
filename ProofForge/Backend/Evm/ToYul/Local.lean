import ProofForge.Backend.Evm.Names
import ProofForge.Backend.Evm.Plan
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def arrayLocalElementName (name : String) (index : Nat) : String :=
  ProofForge.Backend.Evm.Names.arrayLocalElementName name index

def natPathSuffix (path : Array Nat) : String :=
  ProofForge.Backend.Evm.Names.natPathSuffix path

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  ProofForge.Backend.Evm.Names.arrayLocalPathName name path

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.Names.arrayStructLocalFieldName name index fieldName

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  ProofForge.Backend.Evm.Names.arrayStructLocalPathFieldName name path fieldName

def structLocalFieldName (name fieldName : String) : String :=
  ProofForge.Backend.Evm.Names.structLocalFieldName name fieldName

def localArrayGetFunctionName (length : Nat) : String :=
  ProofForge.Backend.Evm.Names.localArrayGetFunctionName length

def nestedLocalArrayGetFunctionName (lengths : Array Nat) : String :=
  ProofForge.Backend.Evm.Names.nestedLocalArrayGetFunctionName lengths

def localArrayGetValueParamName (index : Nat) : String :=
  ProofForge.Backend.Evm.Names.localArrayGetValueParamName index

def localArrayGetIndexParamName (index : Nat) : String :=
  ProofForge.Backend.Evm.Names.localArrayGetIndexParamName index

def localArrayGetPathValueParamName (path : Array Nat) : String :=
  ProofForge.Backend.Evm.Names.localArrayGetPathValueParamName path

partial def nestedLocalArrayLeafPaths (lengths : Array Nat) : Array (Array Nat) :=
  ProofForge.Backend.Evm.Names.nestedLocalArrayLeafPaths lengths

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

end ProofForge.Backend.Evm.ToYul
