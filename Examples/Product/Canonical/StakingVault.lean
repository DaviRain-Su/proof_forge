import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.StakingVault

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)
private def caller : SurfaceExpr := .cast .u64 (.contextRead .sender)

def contract : SurfaceContract := {
  name := "StakingVault"
  structs := #[]
  state := #[
    { name := "totalDeposits", kind := .scalar .u64 },
    { name := "totalShares", kind := .scalar .u64 },
    { name := "shares", kind := .map .u64 .u64 (some 256) }
  ]
  events := #[
    { name := "Deposit", fields := #[
      { name := "depositor", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] },
    { name := "Withdraw", fields := #[
      { name := "depositor", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.stateWrite "totalDeposits" (u64 0), .stateWrite "totalShares" (u64 0)] },
    { name := "deposit", kind := .function, mutability := .call,
      selector? := some "d0e30db0", params := #[], retType := .unit,
      body := #[
        .bind "amount" .u64 (.cast .u64 .nativeValue),
        .assert (.compare .ne (.local "amount") (u64 0)) "zero deposit",
        .bind "depositor" .u64 caller,
        .bind "currentShares" .u64 (.mapRead "shares" (.local "depositor")),
        .mapWrite "shares" (.local "depositor")
          (.arith .add true (.local "currentShares") (.local "amount")),
        .bind "deposits" .u64 (.stateRead "totalDeposits"),
        .stateWrite "totalDeposits" (.arith .add true (.local "deposits") (.local "amount")),
        .bind "supply" .u64 (.stateRead "totalShares"),
        .stateWrite "totalShares" (.arith .add true (.local "supply") (.local "amount")),
        .emit "Deposit" #[.local "depositor", .local "amount"]] },
    { name := "withdraw", kind := .function, mutability := .call,
      selector? := some "750f0acc",
      params := #[{ name := "shareAmount", type := .u64 }], retType := .unit,
      body := #[
        .assert (.compare .ne (.local "shareAmount") (u64 0)) "zero shares",
        .bind "depositor" .u64 caller,
        .bind "currentShares" .u64 (.mapRead "shares" (.local "depositor")),
        .assert (.compare .ge (.local "currentShares") (.local "shareAmount"))
          "insufficient shares",
        .mapWrite "shares" (.local "depositor")
          (.arith .sub true (.local "currentShares") (.local "shareAmount")),
        .bind "deposits" .u64 (.stateRead "totalDeposits"),
        .stateWrite "totalDeposits" (.arith .sub true (.local "deposits") (.local "shareAmount")),
        .bind "supply" .u64 (.stateRead "totalShares"),
        .stateWrite "totalShares" (.arith .sub true (.local "supply") (.local "shareAmount")),
        .emit "Withdraw" #[.local "depositor", .local "shareAmount"]] },
    { name := "totalDeposits", kind := .function, mutability := .view,
      selector? := some "7d882097", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "totalDeposits")] },
    { name := "totalShares", kind := .function, mutability := .view,
      selector? := some "3a98ef39", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "totalShares")] },
    { name := "sharesOf", kind := .function, mutability := .view,
      selector? := some "c27fc47c", params := #[{ name := "who", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "shares" (.local "who"))] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.StakingVault
