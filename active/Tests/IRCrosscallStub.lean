/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# IR crosscall stub determinism (U2.3)

Locks the **executable IR** behavior of `crosscall.invoke*`: a deterministic
sum stub, **not** chain-native peer execution.

Product remote correctness lives in `Tests/CrosscallMaterialize.lean` and
`just portable-remote-call-multi-target` (target materialize only).
-/
import ProofForge.IR.Semantics
import ProofForge.IR.Examples.CrosscallProbe

namespace ProofForge.Tests.IRCrosscallStub

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.IR.Examples.CrosscallProbe

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

/-- `call_remote(target=3, method=5)` → stub return `3+5 = 8`. -/
theorem call_remote_stub_sum :
    (match runEntrypointWithArgs State.empty callRemote #[.u64 3, .u64 5] with
     | .ok (_, some (.u64 n)) => n == 8
     | _ => false) = true := by
  native_decide

/-- `call_with_args(1, 2, 10, 20)` → stub return `1+2+10+20 = 33`. -/
theorem call_with_args_stub_sum :
    (match runEntrypointWithArgs State.empty callWithArgs
        #[.u64 1, .u64 2, .u64 10, .u64 20] with
     | .ok (_, some (.u64 n)) => n == 33
     | _ => false) = true := by
  native_decide

/-- Typed bool return is derived from the stub sum (odd → true). -/
theorem call_remote_bool_stub_from_sum :
    (match runEntrypointWithArgs State.empty callRemoteBool
        #[.u64 1, .u64 0, .bool true] with
     -- sum = 1+0+1 = 2 → even → false after cast
     | .ok (_, some (.bool b)) => b == false
     | _ => false) = true := by
  native_decide

/-- Hash stub values are one of the three fixed sentinel hashes. -/
theorem crosscall_hash_stub_values_known :
    (match crosscallHashStubValue 0, crosscallHashStubValue 1, crosscallHashStubValue 2 with
     | .hash 1001 0 0 0, .hash 2002 0 0 0, .hash 3003 0 0 0 => true
     | _, _, _ => false) = true := by
  native_decide

def main : IO UInt32 := do
  -- Re-check theorems via runtime for `lean --run` gates.
  match runEntrypointWithArgs State.empty callRemote #[.u64 3, .u64 5] with
  | .ok (_, some (.u64 8)) => pure ()
  | other => throw (IO.userError s!"call_remote stub expected u64 8, got {repr other}")
  match runEntrypointWithArgs State.empty callWithArgs
      #[.u64 1, .u64 2, .u64 10, .u64 20] with
  | .ok (_, some (.u64 33)) => pure ()
  | other => throw (IO.userError s!"call_with_args stub expected u64 33, got {repr other}")
  require (match crosscallHashStubValue 0 with | .hash 1001 0 0 0 => true | _ => false)
    "hash stub 0"
  require (match crosscallHashStubValue 1 with | .hash 2002 0 0 0 => true | _ => false)
    "hash stub 1"
  require (match crosscallHashStubValue 2 with | .hash 3003 0 0 0 => true | _ => false)
    "hash stub 2"
  IO.println
    "ir-crosscall-stub: ok (sum stub locked; not chain peer — see CrosscallMaterialize)"
  pure 0

end ProofForge.Tests.IRCrosscallStub

def main : IO UInt32 :=
  ProofForge.Tests.IRCrosscallStub.main
