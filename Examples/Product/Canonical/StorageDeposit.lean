import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.StorageDeposit

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)

def contract : SurfaceContract := {
  name := "StorageDeposit"
  structs := #[]
  state := #[
    { name := "storageRequired", kind := .scalar .u64 },
    { name := "storageDeposits", kind := .map .hash .u64 (some 256) }
  ]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.stateWrite "storageRequired" (u64 1)] },
    { name := "storage_balance_bounds", kind := .function, mutability := .view,
      selector? := some "fa94cad1", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "storageRequired")] },
    { name := "storage_balance_of", kind := .function, mutability := .view,
      selector? := some "76e5716e", params := #[{ name := "account_id", type := .hash }],
      retType := .u64,
      body := #[.returnExpr (.mapRead "storageDeposits" (.local "account_id"))] },
    { name := "storage_deposit", kind := .function, mutability := .call,
      selector? := some "fe5c646f", params := #[{ name := "account_id", type := .hash }],
      retType := .unit,
      body := #[
        .bind "amount" .u64 (.cast .u64 .nativeValue),
        .assert (.compare .ge (.local "amount") (.stateRead "storageRequired"))
          "storage deposit too small",
        .bind "previous" .u64 (.mapRead "storageDeposits" (.local "account_id")),
        .mapWrite "storageDeposits" (.local "account_id")
          (.arith .add true (.local "previous") (.local "amount"))] },
    { name := "storage_withdraw", kind := .function, mutability := .call,
      selector? := some "9b3e24a3",
      params := #[{ name := "account_id", type := .hash }, { name := "amount", type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .eq (.hash (.contextRead .sender)) (.local "account_id"))
          "storage withdraw caller mismatch",
        .bind "previous" .u64 (.mapRead "storageDeposits" (.local "account_id")),
        .assert (.compare .ge (.local "previous") (.local "amount"))
          "insufficient storage deposit",
        .mapWrite "storageDeposits" (.local "account_id")
          (.arith .sub true (.local "previous") (.local "amount"))] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.StorageDeposit
