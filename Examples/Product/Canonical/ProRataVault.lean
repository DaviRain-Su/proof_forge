import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.ProRataVault

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)
private def caller : SurfaceExpr := .cast .u64 (.contextRead .sender)

private def convert (amount : SurfaceExpr) (toShares : Bool) : Array SurfaceStmt :=
  let numeratorFactor := if toShares then "totalSupply" else "totalAssets"
  let denominator := if toShares then "totalAssets" else "totalSupply"
  #[
    .stateWrite "convertScratch" amount,
    .bind "conversionSupply" .u64 (.stateRead "totalSupply"),
    .branch (.compare .gt (.local "conversionSupply") (u64 0)) #[
      .bind "conversionDenominator" .u64 (.stateRead denominator),
      .assert (.compare .ne (.local "conversionDenominator") (u64 0)) "zero denominator",
      .bind "conversionFactor" .u64 (.stateRead numeratorFactor),
      .stateWrite "convertScratch" (.arith .div true
        (.arith .mul true amount (.local "conversionFactor")) (.local "conversionDenominator"))
    ] #[]
  ]

def contract : SurfaceContract := {
  name := "ProRataVault"
  structs := #[]
  state := #[
    { name := "totalAssets", kind := .scalar .u64 },
    { name := "totalSupply", kind := .scalar .u64 },
    { name := "convertScratch", kind := .scalar .u64 },
    { name := "shareBalances", kind := .map .u64 .u64 (some 256) }
  ]
  events := #[
    { name := "Deposit", fields := #[
      { name := "caller", type := .u64, indexed := true },
      { name := "assets", type := .u64, indexed := false },
      { name := "shares", type := .u64, indexed := false }] },
    { name := "Withdraw", fields := #[
      { name := "caller", type := .u64, indexed := true },
      { name := "assets", type := .u64, indexed := false },
      { name := "shares", type := .u64, indexed := false }] },
    { name := "Donate", fields := #[
      { name := "assets", type := .u64, indexed := false }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.stateWrite "totalAssets" (u64 0), .stateWrite "totalSupply" (u64 0),
        .stateWrite "convertScratch" (u64 0)] },
    { name := "total_assets", kind := .function, mutability := .view,
      selector? := some "0b3d0470", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "totalAssets")] },
    { name := "total_supply", kind := .function, mutability := .view,
      selector? := some "3940e9ee", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "totalSupply")] },
    { name := "balance_of", kind := .function, mutability := .view,
      selector? := some "c19e9ab6", params := #[{ name := "who", type := .u64 }],
      retType := .u64, body := #[.returnExpr (.mapRead "shareBalances" (.local "who"))] },
    { name := "convert_to_shares", kind := .function, mutability := .call,
      selector? := some "ac68dbfe", params := #[{ name := "assets", type := .u64 }],
      retType := .u64,
      body := convert (.local "assets") true ++ #[.returnExpr (.stateRead "convertScratch")] },
    { name := "convert_to_assets", kind := .function, mutability := .call,
      selector? := some "efc3b714", params := #[{ name := "shares", type := .u64 }],
      retType := .u64,
      body := convert (.local "shares") false ++ #[.returnExpr (.stateRead "convertScratch")] },
    { name := "donate", kind := .function, mutability := .call,
      selector? := some "75f391cf", params := #[{ name := "assets", type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .ne (.local "assets") (u64 0)) "zero assets",
        .bind "assetsBefore" .u64 (.stateRead "totalAssets"),
        .stateWrite "totalAssets" (.arith .add true (.local "assetsBefore") (.local "assets")),
        .emit "Donate" #[.local "assets"]] },
    { name := "deposit", kind := .function, mutability := .call,
      selector? := some "13765838", params := #[{ name := "assets", type := .u64 }],
      retType := .unit,
      body := #[.assert (.compare .ne (.local "assets") (u64 0)) "zero assets"] ++
        convert (.local "assets") true ++ #[
        .bind "shares" .u64 (.stateRead "convertScratch"),
        .assert (.compare .ne (.local "shares") (u64 0)) "zero shares",
        .bind "caller" .u64 caller,
        .bind "balance" .u64 (.mapRead "shareBalances" (.local "caller")),
        .mapWrite "shareBalances" (.local "caller")
          (.arith .add true (.local "balance") (.local "shares")),
        .bind "assetsBefore" .u64 (.stateRead "totalAssets"),
        .stateWrite "totalAssets" (.arith .add true (.local "assetsBefore") (.local "assets")),
        .bind "supplyBefore" .u64 (.stateRead "totalSupply"),
        .stateWrite "totalSupply" (.arith .add true (.local "supplyBefore") (.local "shares")),
        .emit "Deposit" #[.local "caller", .local "assets", .local "shares"]] },
    { name := "withdraw", kind := .function, mutability := .call,
      selector? := some "750f0acc", params := #[{ name := "shares", type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .ne (.local "shares") (u64 0)) "zero shares",
        .bind "caller" .u64 caller,
        .bind "balance" .u64 (.mapRead "shareBalances" (.local "caller")),
        .assert (.compare .ge (.local "balance") (.local "shares")) "insufficient shares"
      ] ++ convert (.local "shares") false ++ #[
        .bind "assets" .u64 (.stateRead "convertScratch"),
        .mapWrite "shareBalances" (.local "caller")
          (.arith .sub true (.local "balance") (.local "shares")),
        .bind "supplyBefore" .u64 (.stateRead "totalSupply"),
        .stateWrite "totalSupply" (.arith .sub true (.local "supplyBefore") (.local "shares")),
        .bind "assetsBefore" .u64 (.stateRead "totalAssets"),
        .stateWrite "totalAssets" (.arith .sub true (.local "assetsBefore") (.local "assets")),
        .emit "Withdraw" #[.local "caller", .local "assets", .local "shares"]] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.ProRataVault
