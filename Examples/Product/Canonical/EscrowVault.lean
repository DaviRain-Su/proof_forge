import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.EscrowVault

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)

private def state (name : String) : SurfaceStateDecl :=
  { name, kind := .scalar .u64 }

private def view (name selector stateName : String) : SurfaceEntrypoint := {
  name, kind := .function, mutability := .view, selector? := some selector,
  params := #[], retType := .u64, body := #[.returnExpr (.stateRead stateName)] }

def contract : SurfaceContract := {
  name := "EscrowVault"
  structs := #[]
  state := #[state "buyer", state "seller", state "amount", state "status",
    state "sellerClaim", state "buyerClaim"]
  events := #[
    { name := "Funded", fields := #[
      { name := "buyer", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] },
    { name := "Released", fields := #[
      { name := "seller", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] },
    { name := "Refunded", fields := #[
      { name := "buyer", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "752633ea",
      params := #[{ name := "buyerId", type := .u64 }, { name := "sellerId", type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .ne (.local "buyerId") (u64 0)) "zero buyer",
        .assert (.compare .ne (.local "sellerId") (u64 0)) "zero seller",
        .assert (.compare .ne (.local "buyerId") (.local "sellerId")) "same party",
        .stateWrite "buyer" (.local "buyerId"),
        .stateWrite "seller" (.local "sellerId"),
        .stateWrite "amount" (u64 0), .stateWrite "status" (u64 0),
        .stateWrite "sellerClaim" (u64 0), .stateWrite "buyerClaim" (u64 0)] },
    { name := "fund", kind := .function, mutability := .call,
      selector? := some "4f9c09cc", params := #[{ name := "amount", type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "status") (u64 0)) "not empty",
        .assert (.compare .ne (.local "amount") (u64 0)) "zero amount",
        .stateWrite "amount" (.local "amount"), .stateWrite "status" (u64 1),
        .emit "Funded" #[.stateRead "buyer", .local "amount"]] },
    { name := "release", kind := .function, mutability := .call,
      selector? := some "86d1a69f", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "status") (u64 1)) "not funded",
        .bind "amount" .u64 (.stateRead "amount"),
        .stateWrite "status" (u64 2), .stateWrite "sellerClaim" (.local "amount"),
        .emit "Released" #[.stateRead "seller", .local "amount"]] },
    { name := "refund", kind := .function, mutability := .call,
      selector? := some "590e1ae3", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "status") (u64 1)) "not funded",
        .bind "amount" .u64 (.stateRead "amount"),
        .stateWrite "status" (u64 3), .stateWrite "buyerClaim" (.local "amount"),
        .emit "Refunded" #[.stateRead "buyer", .local "amount"]] },
    view "get_status" "39aaba25" "status",
    view "get_amount" "b9e6f1d9" "amount",
    view "seller_claim" "7709c00a" "sellerClaim",
    view "buyer_claim" "f770290c" "buyerClaim",
    view "get_buyer" "12be97a1" "buyer",
    view "get_seller" "723182f2" "seller"
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.EscrowVault
