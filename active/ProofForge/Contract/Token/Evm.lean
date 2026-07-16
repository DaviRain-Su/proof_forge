import ProofForge.Contract.Token.Learn

namespace ProofForge.Contract.Token.Evm

open ProofForge.Contract.Token

def transferTopic0 : String :=
  "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

def approvalTopic0 : String :=
  "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"

def hasMint (spec : TokenSpec) : Bool :=
  spec.hasFeature .mintable

def hasBurn (spec : TokenSpec) : Bool :=
  spec.hasFeature .burnable

private def line (indent : Nat) (text : String) : String :=
  String.ofList (List.replicate (indent * 2) ' ') ++ text ++ "\n"

private def block (indent : Nat) (lines : Array String) : String :=
  lines.foldl (fun acc text => acc ++ line indent text) ""

private def initialSupplyLiteral (spec : TokenSpec) : String :=
  toString (spec.initialSupply?.getD 0)

private def decimalsLiteral (spec : TokenSpec) : String :=
  toString spec.decimals

private def creationCode (runtimeName : String) (spec : TokenSpec) : String :=
  block 1 #[
    "code {",
    "  function mapSlot(root, key) -> slot {",
    "    mstore(0x00, key)",
    "    mstore(0x20, root)",
    "    slot := keccak256(0x00, 0x40)",
    "  }",
    s!"  sstore(0, {initialSupplyLiteral spec})",
    s!"  sstore(mapSlot(1, caller()), {initialSupplyLiteral spec})",
    s!"  datacopy(0x00, dataoffset(\"{runtimeName}\"), datasize(\"{runtimeName}\"))",
    s!"  return(0x00, datasize(\"{runtimeName}\"))",
    "}"
  ]

private def baseRuntimeLines (spec : TokenSpec) : Array String := #[
  "code {",
  "  function revert0() {",
  "    revert(0x00, 0x00)",
  "  }",
  "  function requireArgs(words) {",
  "    if lt(calldatasize(), add(4, mul(words, 32))) { revert0() }",
  "  }",
  "  function returnWord(value) {",
  "    mstore(0x00, value)",
  "    return(0x00, 0x20)",
  "  }",
  "  function mapSlot(root, key) -> slot {",
  "    mstore(0x00, key)",
  "    mstore(0x20, root)",
  "    slot := keccak256(0x00, 0x40)",
  "  }",
  "  function balanceSlot(owner) -> slot {",
  "    slot := mapSlot(1, owner)",
  "  }",
  "  function allowanceSlot(owner, spender) -> slot {",
  "    slot := mapSlot(mapSlot(2, owner), spender)",
  "  }",
  "  function emitTransfer(from, to, amount) {",
  "    mstore(0x00, amount)",
  s!"    log3(0x00, 0x20, {transferTopic0}, from, to)",
  "  }",
  "  function emitApproval(owner, spender, amount) {",
  "    mstore(0x00, amount)",
  s!"    log3(0x00, 0x20, {approvalTopic0}, owner, spender)",
  "  }",
  "  function spend(from, to, amount) {",
  "    let fromSlot := balanceSlot(from)",
  "    let fromBalance := sload(fromSlot)",
  "    if lt(fromBalance, amount) { revert0() }",
  "    sstore(fromSlot, sub(fromBalance, amount))",
  "    let toSlot := balanceSlot(to)",
  "    sstore(toSlot, add(sload(toSlot), amount))",
  "    emitTransfer(from, to, amount)",
  "  }",
  "  let selector := shr(224, calldataload(0x00))",
  "  switch selector",
  "  case 0x18160ddd {",
  "    returnWord(sload(0))",
  "  }",
  "  case 0x70a08231 {",
  "    requireArgs(1)",
  "    returnWord(sload(balanceSlot(calldataload(4))))",
  "  }",
  "  case 0xa9059cbb {",
  "    requireArgs(2)",
  "    let to := calldataload(4)",
  "    let amount := calldataload(36)",
  "    spend(caller(), to, amount)",
  "    returnWord(1)",
  "  }",
  "  case 0x095ea7b3 {",
  "    requireArgs(2)",
  "    let spender := calldataload(4)",
  "    let amount := calldataload(36)",
  "    sstore(allowanceSlot(caller(), spender), amount)",
  "    emitApproval(caller(), spender, amount)",
  "    returnWord(1)",
  "  }",
  "  case 0xdd62ed3e {",
  "    requireArgs(2)",
  "    returnWord(sload(allowanceSlot(calldataload(4), calldataload(36))))",
  "  }",
  "  case 0x23b872dd {",
  "    requireArgs(3)",
  "    let from := calldataload(4)",
  "    let to := calldataload(36)",
  "    let amount := calldataload(68)",
  "    let slot := allowanceSlot(from, caller())",
  "    let allowed := sload(slot)",
  "    if lt(allowed, amount) { revert0() }",
  "    sstore(slot, sub(allowed, amount))",
  "    spend(from, to, amount)",
  "    returnWord(1)",
  "  }",
  "  case 0x313ce567 {",
  s!"    returnWord({decimalsLiteral spec})",
  "  }"
]

private def mintRuntimeLines (spec : TokenSpec) : Array String :=
  if hasMint spec then
    #[
      "  case 0x40c10f19 {",
      "    requireArgs(2)",
      "    let to := calldataload(4)",
      "    let amount := calldataload(36)",
      "    sstore(0, add(sload(0), amount))",
      "    let toSlot := balanceSlot(to)",
      "    sstore(toSlot, add(sload(toSlot), amount))",
      "    emitTransfer(0, to, amount)",
      "    returnWord(1)",
      "  }"
    ]
  else
    #[]

private def burnRuntimeLines (spec : TokenSpec) : Array String :=
  if hasBurn spec then
    #[
      "  case 0x42966c68 {",
      "    requireArgs(1)",
      "    let amount := calldataload(4)",
      "    let owner := caller()",
      "    let ownerSlot := balanceSlot(owner)",
      "    let ownerBalance := sload(ownerSlot)",
      "    if lt(ownerBalance, amount) { revert0() }",
      "    sstore(ownerSlot, sub(ownerBalance, amount))",
      "    sstore(0, sub(sload(0), amount))",
      "    emitTransfer(owner, 0, amount)",
      "    returnWord(1)",
      "  }"
    ]
  else
    #[]

private def runtimeCode (spec : TokenSpec) : String :=
  let lines := baseRuntimeLines spec ++ mintRuntimeLines spec ++ burnRuntimeLines spec ++ #[
    "  default {",
    "    revert0()",
    "  }",
    "}"
  ]
  block 2 lines

def renderErc20Yul (decl : Learn.TokenDecl) : String :=
  let runtimeName := decl.id ++ "Runtime"
  "object \"" ++ decl.id ++ "\" {\n" ++
    creationCode runtimeName decl.spec ++
    line 1 s!"object \"{runtimeName}\" \{" ++
    runtimeCode decl.spec ++
    line 1 "}" ++
    "}\n"

end ProofForge.Contract.Token.Evm
