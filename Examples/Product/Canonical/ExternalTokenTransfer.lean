import ProofForge.Contract.SurfaceV2.Protocol

open ProofForge.Frontend.Surface
open ProofForge.Contract.SurfaceV2.Protocol

namespace Examples.Product.Canonical.ExternalTokenTransfer

private def token (method : String) : RemoteRef := externalToken "usdc.peer" method

def contract : SurfaceContract := {
  name := "ExternalTokenTransfer", structs := #[],
  state := #[{ name := "last_amount", kind := .scalar .u64 }], events := #[], errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c", params := #[], retType := .unit,
      body := #[.stateWrite "last_amount" (.literal (.u64Lit 0))] },
    { name := "pay", kind := .function, mutability := .call,
      selector? := some "4d0d3bb8",
      params := #[{ name := "recipient", type := .u64 }, { name := "amount", type := .u64 }],
      retType := .u64, body := #[
        .bind "ok" .u64 (invoke (token "ft_transfer") #[.local "recipient", .local "amount"]),
        .stateWrite "last_amount" (.local "amount"), .returnExpr (.local "amount")] },
    { name := "set_allowance", kind := .function, mutability := .call,
      selector? := some "8a315452",
      params := #[{ name := "spender", type := .u64 }, { name := "amount", type := .u64 }],
      retType := .u64, body := #[
        .bind "ok" .u64 (invoke (token "approve") #[.local "spender", .local "amount"]),
        .stateWrite "last_amount" (.local "amount"), .returnExpr (.local "amount")] },
    { name := "read_balance", kind := .function, mutability := .call,
      selector? := some "eb6c6aeb", params := #[{ name := "holder", type := .u64 }],
      retType := .u64,
      body := #[.returnExpr (invoke (token "ft_balance_of") #[.local "holder"])] },
    { name := "read_supply", kind := .function, mutability := .call,
      selector? := some "0d8c1c17", params := #[], retType := .u64,
      body := #[.returnExpr (invoke (token "ft_total_supply") #[])] }
  ], constructorParams := #[], constructorBindings := #[]
}

end Examples.Product.Canonical.ExternalTokenTransfer
