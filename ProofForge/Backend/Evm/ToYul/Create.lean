import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Compiler.Yul.AST
import ProofForge.Util.StringUtil

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan
open ProofForge.Util.StringUtil

def isHexChar (c : Char) : Bool :=
  ('0' <= c && c <= '9') ||
  ('a' <= c && c <= 'f') ||
  ('A' <= c && c <= 'F')

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

end ProofForge.Backend.Evm.ToYul
