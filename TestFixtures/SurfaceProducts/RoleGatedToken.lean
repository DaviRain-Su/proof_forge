import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace TestFixtures.SurfaceProducts.RoleGatedToken

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)
private def caller : SurfaceExpr := .cast .u64 (.contextRead .sender)
private def roleKey (role account : SurfaceExpr) : SurfaceExpr :=
  .hashPair (.hash role) (.hash account)
private def member (role account : SurfaceExpr) : SurfaceExpr :=
  .mapRead "roleMembers" (roleKey role account)

def contract : SurfaceContract := {
  name := "RoleGatedToken"
  structs := #[]
  state := #[
    { name := "totalSupply", kind := .scalar .u64 },
    { name := "tokenDecimals", kind := .scalar .u64 },
    { name := "balances", kind := .map .u64 .u64 (some 256) },
    { name := "roleMembers", kind := .map .hash .u64 (some 256) }
  ]
  events := #[
    { name := "Transfer", fields := #[
      { name := "from", type := .u64, indexed := true },
      { name := "to", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] },
    { name := "Approval", fields := #[] },
    { name := "RoleGranted", fields := #[
      { name := "role", type := .u64, indexed := true },
      { name := "who", type := .u64, indexed := true }] },
    { name := "RoleRevoked", fields := #[
      { name := "role", type := .u64, indexed := true },
      { name := "who", type := .u64, indexed := true }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[
        .stateWrite "totalSupply" (u64 0), .stateWrite "tokenDecimals" (u64 18),
        .bind "admin" .u64 caller,
        .mapWrite "roleMembers" (roleKey (u64 0) (.local "admin")) (u64 1)] },
    { name := "totalSupply", kind := .function, mutability := .view,
      selector? := some "18160ddd", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "totalSupply")] },
    { name := "balanceOf", kind := .function, mutability := .view,
      selector? := some "c67243a1", params := #[{ name := "who", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "balances" (.local "who"))] },
    { name := "hasRole", kind := .function, mutability := .view,
      selector? := some "f22801c6",
      params := #[{ name := "role", type := .u64 }, { name := "who", type := .u64 }],
      retType := .bool,
      body := #[.returnExpr (.compare .ne (member (.local "role") (.local "who")) (u64 0))] },
    { name := "transfer", kind := .function, mutability := .call,
      selector? := some "85558f8f",
      params := #[{ name := "recipient", type := .u64 }, { name := "amount", type := .u64 }],
      retType := .unit, body := #[
        .assert (.compare .ne (.local "amount") (u64 0)) "zero amount",
        .bind "sender" .u64 caller,
        .bind "sourceBalance" .u64 (.mapRead "balances" (.local "sender")),
        .assert (.compare .ge (.local "sourceBalance") (.local "amount")) "insufficient balance",
        .mapWrite "balances" (.local "sender")
          (.arith .sub true (.local "sourceBalance") (.local "amount")),
        .bind "destinationBalance" .u64 (.mapRead "balances" (.local "recipient")),
        .mapWrite "balances" (.local "recipient")
          (.arith .add true (.local "destinationBalance") (.local "amount")),
        .emit "Transfer" #[.local "sender", .local "recipient", .local "amount"]] },
    { name := "grantRole", kind := .function, mutability := .call,
      selector? := some "41046d3b",
      params := #[{ name := "role", type := .u64 }, { name := "who", type := .u64 }],
      retType := .unit, body := #[
        .bind "caller" .u64 caller,
        .assert (.compare .ne (member (u64 0) (.local "caller")) (u64 0)) "missing admin role",
        .mapWrite "roleMembers" (roleKey (.local "role") (.local "who")) (u64 1),
        .emit "RoleGranted" #[.local "role", .local "who"]] },
    { name := "revokeRole", kind := .function, mutability := .call,
      selector? := some "403dd0a5",
      params := #[{ name := "role", type := .u64 }, { name := "who", type := .u64 }],
      retType := .unit, body := #[
        .bind "caller" .u64 caller,
        .assert (.compare .ne (member (u64 0) (.local "caller")) (u64 0)) "missing admin role",
        .mapWrite "roleMembers" (roleKey (.local "role") (.local "who")) (u64 0),
        .emit "RoleRevoked" #[.local "role", .local "who"]] },
    { name := "mint", kind := .function, mutability := .call,
      selector? := some "6a400d54",
      params := #[{ name := "recipient", type := .u64 }, { name := "amount", type := .u64 }],
      retType := .unit, body := #[
        .bind "caller" .u64 caller,
        .assert (.compare .ne (member (u64 1) (.local "caller")) (u64 0)) "missing minter role",
        .bind "supply" .u64 (.stateRead "totalSupply"),
        .stateWrite "totalSupply" (.arith .add true (.local "supply") (.local "amount")),
        .bind "balance" .u64 (.mapRead "balances" (.local "recipient")),
        .mapWrite "balances" (.local "recipient")
          (.arith .add true (.local "balance") (.local "amount")),
        .emit "Transfer" #[u64 0, .local "recipient", .local "amount"]] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end TestFixtures.SurfaceProducts.RoleGatedToken
