import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.SoulboundTokenBody

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)
private def caller : SurfaceExpr := .cast .u64 (.contextRead .sender)

def contract : SurfaceContract := {
  name := "SoulboundTokenBody", structs := #[],
  state := #[
    { name := "totalSupply", kind := .scalar .u64 },
    { name := "balances", kind := .map .u64 .u64 (some 256) }
  ],
  events := #[
    { name := "Mint", fields := #[
      { name := "to", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] },
    { name := "Burn", fields := #[
      { name := "from", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] }
  ], errors := #[],
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.stateWrite "totalSupply" (u64 0)] },
    { name := "mint", kind := .function, mutability := .call,
      selector? := some "6a400d54",
      params := #[{ name := "recipient", type := .u64 }, { name := "amount", type := .u64 }],
      retType := .unit, body := #[
        .assert (.compare .ne (.local "amount") (u64 0)) "zero amount",
        .bind "balance" .u64 (.mapRead "balances" (.local "recipient")),
        .mapWrite "balances" (.local "recipient")
          (.arith .add true (.local "balance") (.local "amount")),
        .bind "supply" .u64 (.stateRead "totalSupply"),
        .stateWrite "totalSupply" (.arith .add true (.local "supply") (.local "amount")),
        .emit "Mint" #[.local "recipient", .local "amount"]] },
    { name := "burn", kind := .function, mutability := .call,
      selector? := some "9dbead42", params := #[{ name := "amount", type := .u64 }],
      retType := .unit, body := #[
        .assert (.compare .ne (.local "amount") (u64 0)) "zero amount",
        .bind "holder" .u64 caller,
        .bind "balance" .u64 (.mapRead "balances" (.local "holder")),
        .assert (.compare .ge (.local "balance") (.local "amount")) "insufficient balance",
        .mapWrite "balances" (.local "holder")
          (.arith .sub true (.local "balance") (.local "amount")),
        .bind "supply" .u64 (.stateRead "totalSupply"),
        .stateWrite "totalSupply" (.arith .sub true (.local "supply") (.local "amount")),
        .emit "Burn" #[.local "holder", .local "amount"]] },
    { name := "balance_of", kind := .function, mutability := .view,
      selector? := some "c19e9ab6", params := #[{ name := "who", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "balances" (.local "who"))] },
    { name := "total_supply", kind := .function, mutability := .view,
      selector? := some "3940e9ee", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "totalSupply")] }
  ], constructorParams := #[], constructorBindings := #[]
}

end Examples.Product.Canonical.SoulboundTokenBody
