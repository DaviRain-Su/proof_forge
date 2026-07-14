import ProofForge.Frontend.Surface.Protocol

open ProofForge.Frontend.Surface
open ProofForge.Frontend.Surface.Protocol

namespace TestFixtures.SurfaceProducts.AuthRemoteCall

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)
private def callee : RemoteRef := { peerId := "peer.callee", method := "receive" }

def contract : SurfaceContract := {
  name := "AuthRemoteCall", structs := #[],
  state := #[{ name := "balance", kind := .scalar .u64 }], events := #[], errors := #[],
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c", params := #[], retType := .unit,
      body := #[.stateWrite "balance" (u64 100)] },
    { name := "debit_and_forward", kind := .function, mutability := .call,
      selector? := some "1d3e875b", params := #[{ name := "amount", type := .u64 }],
      retType := .u64, body := #[
        .bind "sender" .u64 (.cast .u64 (.contextRead .sender)),
        .bind "balance" .u64 (.stateRead "balance"),
        .assert (.compare .ge (.local "balance") (.local "amount")) "insufficient balance",
        .stateWrite "balance" (.arith .sub true (.local "balance") (.local "amount")),
        .returnExpr (invoke callee #[.local "amount"])] }
  ], constructorParams := #[], constructorBindings := #[]
}

end TestFixtures.SurfaceProducts.AuthRemoteCall
