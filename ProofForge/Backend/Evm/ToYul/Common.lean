import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.ToYul

def slotExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.Expr.num slot

def calldataWordExpr (paramIndex : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "calldataload" #[Lean.Compiler.Yul.Expr.num (4 + paramIndex * 32)]

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

end ProofForge.Backend.Evm.ToYul
