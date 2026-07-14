import ProofForge.Contract.SurfaceV2.Protocol

open ProofForge.Frontend.Surface
open ProofForge.Contract.SurfaceV2.Protocol

namespace Examples.Product.Canonical.ExternalVault

private def vault (method : String) : RemoteRef := externalVault "vault.peer" method

def contract : SurfaceContract := {
  name := "ExternalVault", structs := #[],
  state := #[{ name := "last_shares", kind := .scalar .u64 }], events := #[], errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c", params := #[], retType := .unit,
      body := #[.stateWrite "last_shares" (.literal (.u64Lit 0))] },
    { name := "deposit_assets", kind := .function, mutability := .call,
      selector? := some "b9361804",
      params := #[{ name := "assets", type := .u64 }, { name := "receiver", type := .u64 }],
      retType := .u64, body := #[
        .bind "shares" .u64 (invoke (vault "deposit") #[.local "assets", .local "receiver"]),
        .stateWrite "last_shares" (.local "shares"), .returnExpr (.local "shares")] },
    { name := "preview_shares", kind := .function, mutability := .call,
      selector? := some "43d0227d", params := #[{ name := "assets", type := .u64 }],
      retType := .u64,
      body := #[.returnExpr (invoke (vault "convertToShares") #[.local "assets"])] },
    { name := "read_total_assets", kind := .function, mutability := .call,
      selector? := some "b00f402d", params := #[], retType := .u64,
      body := #[.returnExpr (invoke (vault "totalAssets") #[])] }
  ], constructorParams := #[], constructorBindings := #[]
}

end Examples.Product.Canonical.ExternalVault
