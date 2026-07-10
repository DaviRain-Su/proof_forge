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

/-- IERC721Receiver.onERC721Received selector (`cast sig "onERC721Received(address,address,uint256,bytes)"`). -/
def onErc721ReceivedSelector : Nat := 0x150b7a02

/-- PF-P2-02: ERC-721 safe transfer receiver check.
If `to` is an EOA (`extcodesize == 0`), leave. Otherwise CALL
`onERC721Received(operator, from, tokenId, "")` and require magic return. -/
def checkErc721ReceivedStatements
    (operator fromAddr toAddr tokenId : Lean.Compiler.Yul.Expr) :
    Array Lean.Compiler.Yul.Statement :=
  let isContract :=
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "extcodesize" #[toAddr]
      ]
    ]
  let magicWord :=
    Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num 224,
      Lean.Compiler.Yul.Expr.num onErc721ReceivedSelector
    ]
  let callSuccess := Lean.Compiler.Yul.Expr.id "__pf_erc721_ok"
  let retMagic := Lean.Compiler.Yul.Expr.id "__pf_erc721_magic"
  let contractBody : Array Lean.Compiler.Yul.Statement := #[
    -- ABI: selector + operator + from + tokenId + bytes offset(0x80) + length 0
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, magicWord]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 4, operator]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 36, fromAddr]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 68, tokenId]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 100, Lean.Compiler.Yul.Expr.num 0x80]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 132, Lean.Compiler.Yul.Expr.num 0]),
    .varDecl #[{ name := "__pf_erc721_ok" }] (some <|
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        toAddr,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 164,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 32
      ]),
    .ifStmt
      (Lean.Compiler.Yul.builtin "iszero" #[callSuccess])
      { statements := #[revertStatement] },
    .ifStmt
      (Lean.Compiler.Yul.builtin "lt" #[
        Lean.Compiler.Yul.builtin "returndatasize" #[],
        Lean.Compiler.Yul.Expr.num 32
      ])
      { statements := #[revertStatement] },
    .varDecl #[{ name := "__pf_erc721_magic" }] (some <|
      Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0]),
    .ifStmt
      (Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "eq" #[retMagic, magicWord]
      ])
      { statements := #[revertStatement] }
  ]
  #[
    .ifStmt isContract { statements := contractBody }
  ]

/-- IERC1155Receiver.onERC1155Received selector. -/
def onErc1155ReceivedSelector : Nat := 0xf23a6e61

/-- PF-P2-02: ERC-1155 single safe-transfer receiver check. -/
def checkErc1155ReceivedStatements
    (operator fromAddr toAddr id amount : Lean.Compiler.Yul.Expr) :
    Array Lean.Compiler.Yul.Statement :=
  let isContract :=
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "extcodesize" #[toAddr]
      ]
    ]
  let magicWord :=
    Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num 224,
      Lean.Compiler.Yul.Expr.num onErc1155ReceivedSelector
    ]
  let callSuccess := Lean.Compiler.Yul.Expr.id "__pf_erc1155_ok"
  let retMagic := Lean.Compiler.Yul.Expr.id "__pf_erc1155_magic"
  -- ABI: selector + operator + from + id + value + bytes offset(0xa0) + length 0
  -- head = 4 + 5*32 = 164; + length word = 196
  let contractBody : Array Lean.Compiler.Yul.Statement := #[
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, magicWord]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 4, operator]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 36, fromAddr]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 68, id]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 100, amount]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 132, Lean.Compiler.Yul.Expr.num 0xa0]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 164, Lean.Compiler.Yul.Expr.num 0]),
    .varDecl #[{ name := "__pf_erc1155_ok" }] (some <|
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        toAddr,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 196,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 32
      ]),
    .ifStmt
      (Lean.Compiler.Yul.builtin "iszero" #[callSuccess])
      { statements := #[revertStatement] },
    .ifStmt
      (Lean.Compiler.Yul.builtin "lt" #[
        Lean.Compiler.Yul.builtin "returndatasize" #[],
        Lean.Compiler.Yul.Expr.num 32
      ])
      { statements := #[revertStatement] },
    .varDecl #[{ name := "__pf_erc1155_magic" }] (some <|
      Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0]),
    .ifStmt
      (Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "eq" #[retMagic, magicWord]
      ])
      { statements := #[revertStatement] }
  ]
  #[
    .ifStmt isContract { statements := contractBody }
  ]

end ProofForge.Backend.Evm.ToYul
