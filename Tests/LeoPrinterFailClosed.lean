import ProofForge.Compiler.Leo.AST
import ProofForge.Compiler.Leo.Printer

namespace ProofForge.Tests.LeoPrinterFailClosed

open ProofForge.Compiler.Leo.AST
open ProofForge.Compiler.Leo.Printer

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure ()
  else throw <| IO.userError message

def requireErr (result : Except LowerError String) (needle : String) : IO Unit :=
  match result with
  | .ok s => throw <| IO.userError s!"expected Leo printer error containing `{needle}`, got ok: {s}"
  | .error e =>
      require (e.message.contains needle)
        s!"error `{e.message}` missing `{needle}`"

/-- PF-P1-06: unsupported Leo AST ops must not print comment placeholders. -/
def main : IO UInt32 := do
  let litTrue : Expression := .literal (.boolean true)
  let litFalse : Expression := .literal (.boolean false)
  let nandExpr : Expression := .binary {
    left := litTrue
    op := .nand
    right := litFalse
  }
  requireErr (printExpression nandExpr) "nand"
  requireErr (printBinaryOp .nand) "nand"
  requireErr (printBinaryOp .nor) "nor"
  requireErr (printBinaryOp .rem) "rem"

  let absExpr : Expression := .unary {
    op := .abs
    receiver := .literal (.integer .u64 1)
  }
  requireErr (printExpression absExpr) "unary"
  requireErr (printUnaryOp .abs) "unary"
  requireErr (printUnaryOp .square) "unary"

  -- Supported ops still print.
  match printBinaryOp .add, printUnaryOp .not with
  | .ok "+", .ok "!" => pure ()
  | a, b => throw <| IO.userError s!"supported ops failed: {repr a} {repr b}"

  IO.println "LeoPrinterFailClosed: ok"
  return 0

end ProofForge.Tests.LeoPrinterFailClosed

def main : IO UInt32 :=
  ProofForge.Tests.LeoPrinterFailClosed.main
