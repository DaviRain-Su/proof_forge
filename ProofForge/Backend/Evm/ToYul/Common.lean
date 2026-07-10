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
  let operatorArg := Lean.Compiler.Yul.Expr.id "__pf_erc721_operator"
  let fromArg := Lean.Compiler.Yul.Expr.id "__pf_erc721_from"
  let toArg := Lean.Compiler.Yul.Expr.id "__pf_erc721_to"
  let tokenIdArg := Lean.Compiler.Yul.Expr.id "__pf_erc721_token_id"
  let isContract :=
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "extcodesize" #[toArg]
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
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 4, operatorArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 36, fromArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 68, tokenIdArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 100, Lean.Compiler.Yul.Expr.num 0x80]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 132, Lean.Compiler.Yul.Expr.num 0]),
    .varDecl #[{ name := "__pf_erc721_ok" }] (some <|
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        toArg,
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
    .block { statements := #[
      .varDecl #[{ name := "__pf_erc721_operator" }] (some operator),
      .varDecl #[{ name := "__pf_erc721_from" }] (some fromAddr),
      .varDecl #[{ name := "__pf_erc721_to" }] (some toAddr),
      .varDecl #[{ name := "__pf_erc721_token_id" }] (some tokenId),
      .ifStmt isContract { statements := contractBody }
    ] }
  ]

/-- IERC1155Receiver.onERC1155Received selector. -/
def onErc1155ReceivedSelector : Nat := 0xf23a6e61

/-- PF-P2-02: ERC-1155 single safe-transfer receiver check. -/
def checkErc1155ReceivedStatements
    (operator fromAddr toAddr id amount : Lean.Compiler.Yul.Expr) :
    Array Lean.Compiler.Yul.Statement :=
  let operatorArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_operator"
  let fromArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_from"
  let toArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_to"
  let idArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_id"
  let amountArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_amount"
  let isContract :=
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "extcodesize" #[toArg]
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
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 4, operatorArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 36, fromArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 68, idArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 100, amountArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 132, Lean.Compiler.Yul.Expr.num 0xa0]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 164, Lean.Compiler.Yul.Expr.num 0]),
    .varDecl #[{ name := "__pf_erc1155_ok" }] (some <|
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        toArg,
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
    .block { statements := #[
      .varDecl #[{ name := "__pf_erc1155_operator" }] (some operator),
      .varDecl #[{ name := "__pf_erc1155_from" }] (some fromAddr),
      .varDecl #[{ name := "__pf_erc1155_to" }] (some toAddr),
      .varDecl #[{ name := "__pf_erc1155_id" }] (some id),
      .varDecl #[{ name := "__pf_erc1155_amount" }] (some amount),
      .ifStmt isContract { statements := contractBody }
    ] }
  ]

/-- IERC1155Receiver.onERC1155BatchReceived selector. -/
def onErc1155BatchReceivedSelector : Nat := 0xbc197c81

/-- E1.2: ERC-1155 size-2 batch safe-transfer receiver check.
    CALL `onERC1155BatchReceived(operator, from, [id0,id1], [amount0,amount1], "")`
    when `to` has code; require magic return. -/
def checkErc1155BatchReceivedStatements
    (operator fromAddr toAddr id0 amount0 id1 amount1 : Lean.Compiler.Yul.Expr) :
    Array Lean.Compiler.Yul.Statement :=
  let operatorArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_operator"
  let fromArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_from"
  let toArg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_to"
  let id0Arg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_id0"
  let amount0Arg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_amount0"
  let id1Arg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_id1"
  let amount1Arg := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_amount1"
  let isContract :=
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "extcodesize" #[toArg]
      ]
    ]
  let magicWord :=
    Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num 224,
      Lean.Compiler.Yul.Expr.num onErc1155BatchReceivedSelector
    ]
  let callSuccess := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_ok"
  let retMagic := Lean.Compiler.Yul.Expr.id "__pf_erc1155_batch_magic"
  -- ABI (args relative to head start): head = 5 words (operator, from, ids_off,
  -- amounts_off, data_off) = 0xa0.
  -- ids at 0xa0: [2, id0, id1] (96 B) → ends 0x100
  -- amounts at 0x100: [2, a0, a1] (96 B) → ends 0x160
  -- data at 0x160: [0] (32 B) → ends 0x180
  -- With 4-byte selector: total call size = 4 + 0x180 = 388.
  let contractBody : Array Lean.Compiler.Yul.Statement := #[
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 0, magicWord]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 4, operatorArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 36, fromArg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 68, Lean.Compiler.Yul.Expr.num 0xa0]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 100, Lean.Compiler.Yul.Expr.num 0x100]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 132, Lean.Compiler.Yul.Expr.num 0x160]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 164, Lean.Compiler.Yul.Expr.num 2]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 196, id0Arg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 228, id1Arg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 260, Lean.Compiler.Yul.Expr.num 2]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 292, amount0Arg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 324, amount1Arg]),
    .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[Lean.Compiler.Yul.Expr.num 356, Lean.Compiler.Yul.Expr.num 0]),
    .varDecl #[{ name := "__pf_erc1155_batch_ok" }] (some <|
      Lean.Compiler.Yul.builtin "call" #[
        Lean.Compiler.Yul.builtin "gas" #[],
        toArg,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 0,
        Lean.Compiler.Yul.Expr.num 388,
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
    .varDecl #[{ name := "__pf_erc1155_batch_magic" }] (some <|
      Lean.Compiler.Yul.builtin "mload" #[Lean.Compiler.Yul.Expr.num 0]),
    .ifStmt
      (Lean.Compiler.Yul.builtin "iszero" #[
        Lean.Compiler.Yul.builtin "eq" #[retMagic, magicWord]
      ])
      { statements := #[revertStatement] }
  ]
  #[
    .block { statements := #[
      .varDecl #[{ name := "__pf_erc1155_batch_operator" }] (some operator),
      .varDecl #[{ name := "__pf_erc1155_batch_from" }] (some fromAddr),
      .varDecl #[{ name := "__pf_erc1155_batch_to" }] (some toAddr),
      .varDecl #[{ name := "__pf_erc1155_batch_id0" }] (some id0),
      .varDecl #[{ name := "__pf_erc1155_batch_amount0" }] (some amount0),
      .varDecl #[{ name := "__pf_erc1155_batch_id1" }] (some id1),
      .varDecl #[{ name := "__pf_erc1155_batch_amount1" }] (some amount1),
      .ifStmt isContract { statements := contractBody }
    ] }
  ]

end ProofForge.Backend.Evm.ToYul
