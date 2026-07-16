import ProofForge.IR.Contract
import ProofForge.Target.HostOps.Near

namespace ProofForge.IR.Examples.U128PromiseResultProbe

open ProofForge.IR

/-! Probe for `nearPromiseResultU128`: read promise result index 0 as a u128
    and return it. Run with one injected `Successful` promise result; the u128
    read stages 16 bytes (zero-extended when the result is < 16 bytes) and the
    caller reloads (lo, hi). -/

def readResult : Entrypoint := {
  name := "read_result"
  returns := .u128
  body := #[
    .return (.hostCall ProofForge.Target.HostOps.Near.promiseResultU128Sig.id
      #[.literal (.u64 0)] .u128 #[.nearPromise])
  ]
}

def module : Module := {
  name := "U128PromiseResultProbe"
  state := #[]
  entrypoints := #[readResult]
}

end ProofForge.IR.Examples.U128PromiseResultProbe
