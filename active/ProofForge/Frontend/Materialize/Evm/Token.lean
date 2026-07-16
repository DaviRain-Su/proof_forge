import ProofForge.Contract.Token
import ProofForge.Frontend.Surface

/-! Internal TokenSpec to EVM frontend materialization. The result uses
portable state, arithmetic, events, and identity reads; EVM ABI selectors are
target-owned materialization metadata. -/

namespace ProofForge.Frontend.Materialize.Evm.Token

open ProofForge.Contract.Token
open ProofForge.Frontend.Surface

private def uint256Param (name : String) : SurfaceParam :=
  { name, type := .u128, abiWord? := some "uint256" }

private def allowanceKey (owner spender : SurfaceExpr) : SurfaceExpr :=
  .hashPair (.hash owner) (.hash spender)

private def transferEvent (fromAddr toAddr amount : SurfaceExpr) : SurfaceStmt :=
  .emit "Transfer" #[fromAddr, toAddr, amount]

private def approvalEvent (owner spender amount : SurfaceExpr) : SurfaceStmt :=
  .emit "Approval" #[owner, spender, amount]

private def baseEntrypoints (token : TokenSpec) : Array SurfaceEntrypoint := #[
  { name := "initialize", kind := .function, mutability := .call,
    selector? := some "8129fc1c", params := #[], retType := .unit,
    body := #[
      .bind "already_initialized" .bool (.stateRead "initialized"),
      .assert (.unary .not (.local "already_initialized")) "already initialized",
      .bind "owner" .address (.contextRead .sender),
      .stateWrite "initialized" (.literal (.boolLit true)),
      .stateWrite "owner" (.local "owner"),
      .stateWrite "total_supply" (.literal (.u128Lit (token.initialSupply?.getD 0))),
      .mapWrite "balances" (.local "owner")
        (.literal (.u128Lit (token.initialSupply?.getD 0))),
      transferEvent (.literal (.addressLit "0")) (.local "owner")
        (.literal (.u128Lit (token.initialSupply?.getD 0))) ] },
  { name := "totalSupply", kind := .function, mutability := .view,
    selector? := some "18160ddd", params := #[], retType := .u128,
    returnAbiWord? := some "uint256",
    body := #[.returnExpr (.stateRead "total_supply")] },
  { name := "decimals", kind := .function, mutability := .view,
    selector? := some "313ce567", params := #[], retType := .u8,
    body := #[.returnExpr (.literal (.u8Lit token.decimals))] },
  { name := "balanceOf", kind := .function, mutability := .view,
    selector? := some "70a08231",
    params := #[{ name := "account", type := .address }], retType := .u128,
    returnAbiWord? := some "uint256",
    body := #[.returnExpr (.mapRead "balances" (.local "account"))] },
  { name := "allowance", kind := .function, mutability := .view,
    selector? := some "dd62ed3e",
    params := #[{ name := "owner", type := .address },
      { name := "spender", type := .address }], retType := .u128,
    returnAbiWord? := some "uint256",
    body := #[.returnExpr (.mapRead "allowances"
      (allowanceKey (.local "owner") (.local "spender")))] },
  { name := "transfer", kind := .function, mutability := .call,
    selector? := some "a9059cbb",
    params := #[{ name := "to", type := .address },
      uint256Param "amount"], retType := .bool,
    body := #[
      .bind "sender" .address (.contextRead .sender),
      .bind "from_balance" .u128 (.mapRead "balances" (.local "sender")),
      .bind "next_from" .u128 (.arith .sub true (.local "from_balance") (.local "amount")),
      .bind "to_balance" .u128 (.mapRead "balances" (.local "to")),
      .bind "next_to" .u128 (.arith .add true (.local "to_balance") (.local "amount")),
      .mapWrite "balances" (.local "sender") (.local "next_from"),
      .mapWrite "balances" (.local "to") (.local "next_to"),
      transferEvent (.local "sender") (.local "to") (.local "amount"),
      .returnExpr (.literal (.boolLit true)) ] },
  { name := "approve", kind := .function, mutability := .call,
    selector? := some "095ea7b3",
    params := #[{ name := "spender", type := .address },
      uint256Param "amount"], retType := .bool,
    body := #[
      .bind "owner" .address (.contextRead .sender),
      .bind "key" .hash (allowanceKey (.local "owner") (.local "spender")),
      .mapWrite "allowances" (.local "key") (.local "amount"),
      approvalEvent (.local "owner") (.local "spender") (.local "amount"),
      .returnExpr (.literal (.boolLit true)) ] },
  { name := "transferFrom", kind := .function, mutability := .call,
    selector? := some "23b872dd",
    params := #[{ name := "from", type := .address },
      { name := "to", type := .address }, uint256Param "amount"],
    retType := .bool,
    body := #[
      .bind "spender" .address (.contextRead .sender),
      .bind "key" .hash (allowanceKey (.local "from") (.local "spender")),
      .bind "allowed" .u128 (.mapRead "allowances" (.local "key")),
      .bind "next_allowed" .u128 (.arith .sub true (.local "allowed") (.local "amount")),
      .bind "from_balance" .u128 (.mapRead "balances" (.local "from")),
      .bind "next_from" .u128 (.arith .sub true (.local "from_balance") (.local "amount")),
      .bind "to_balance" .u128 (.mapRead "balances" (.local "to")),
      .bind "next_to" .u128 (.arith .add true (.local "to_balance") (.local "amount")),
      .mapWrite "allowances" (.local "key") (.local "next_allowed"),
      .mapWrite "balances" (.local "from") (.local "next_from"),
      .mapWrite "balances" (.local "to") (.local "next_to"),
      transferEvent (.local "from") (.local "to") (.local "amount"),
      .returnExpr (.literal (.boolLit true)) ] }
]

private def mintEntrypoint : SurfaceEntrypoint := {
  name := "mint", kind := .function, mutability := .call,
  selector? := some "40c10f19",
  params := #[{ name := "to", type := .address }, uint256Param "amount"],
  retType := .bool,
  body := #[
    .bind "caller" .address (.contextRead .sender),
    .bind "owner" .address (.stateRead "owner"),
    .assert (.compare .eq (.local "caller") (.local "owner")) "owner only",
    .bind "supply" .u128 (.stateRead "total_supply"),
    .bind "next_supply" .u128 (.arith .add true (.local "supply") (.local "amount")),
    .bind "balance" .u128 (.mapRead "balances" (.local "to")),
    .bind "next_balance" .u128 (.arith .add true (.local "balance") (.local "amount")),
    .stateWrite "total_supply" (.local "next_supply"),
    .mapWrite "balances" (.local "to") (.local "next_balance"),
    transferEvent (.literal (.addressLit "0")) (.local "to") (.local "amount"),
    .returnExpr (.literal (.boolLit true)) ]
}

private def burnEntrypoint : SurfaceEntrypoint := {
  name := "burn", kind := .function, mutability := .call,
  selector? := some "42966c68", params := #[uint256Param "amount"],
  retType := .bool,
  body := #[
    .bind "owner" .address (.contextRead .sender),
    .bind "supply" .u128 (.stateRead "total_supply"),
    .bind "next_supply" .u128 (.arith .sub true (.local "supply") (.local "amount")),
    .bind "balance" .u128 (.mapRead "balances" (.local "owner")),
    .bind "next_balance" .u128 (.arith .sub true (.local "balance") (.local "amount")),
    .stateWrite "total_supply" (.local "next_supply"),
    .mapWrite "balances" (.local "owner") (.local "next_balance"),
    transferEvent (.local "owner") (.literal (.addressLit "0")) (.local "amount"),
    .returnExpr (.literal (.boolLit true)) ]
}

def materialize (token : TokenSpec) : SurfaceContract := {
  name := token.symbol
  structs := #[]
  state := #[
    { name := "initialized", kind := .scalar .bool },
    { name := "owner", kind := .scalar .address },
    { name := "total_supply", kind := .scalar .u128 },
    { name := "balances", kind := .map .address .u128 none },
    { name := "allowances", kind := .map .hash .u128 none }
  ]
  events := #[
    { name := "Transfer", fields := #[
      { name := "from", type := .address, indexed := true },
      { name := "to", type := .address, indexed := true },
      { name := "amount", type := .u128, indexed := false, abiWord? := some "uint256" }] },
    { name := "Approval", fields := #[
      { name := "owner", type := .address, indexed := true },
      { name := "spender", type := .address, indexed := true },
      { name := "amount", type := .u128, indexed := false, abiWord? := some "uint256" }] }
  ]
  errors := #[]
  entrypoints := baseEntrypoints token ++
    (if token.hasFeature .mintable then #[mintEntrypoint] else #[]) ++
    (if token.hasFeature .burnable then #[burnEntrypoint] else #[])
  constructorParams := #[]
  constructorBindings := #[]
}

end ProofForge.Frontend.Materialize.Evm.Token
