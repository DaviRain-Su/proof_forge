import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Aleo/Leo generic lowering regression: finalize-context reads.

Verifies (against syntax confirmed in the ProvableHQ/leo repo) that the portable
IR `contextRead` lowers to Leo on-chain/proof-context intrinsics:

- `contextRead .checkpointId` → `block.height` (u32), used here to store the
  current block height into a scalar state (rewritten to a single-slot mapping).
- `contextRead .userId` → `self.caller` (address), used here in an assertion.

Both appear inside a stateful `fn … -> Final { return final { … }; }` body,
which is where Leo permits block/caller context access. -/

namespace ProofForge.Tests.AleoLeoContextLoweringSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

def lastHeight : StateDecl :=
  { id := "lastHeight", kind := .scalar, type := .u32 }

/-- `fn record_height() -> Final { return final {
--     Mapping::set(lastHeight, 0u64, block.height); }; }` -/
def recordHeight : Entrypoint :=
  { name := "record_height"
    body := #[ .effect (.storageScalarWrite "lastHeight" (.effect (.contextRead .checkpointId))) ] }

/-- `fn touch() -> Final { return final { assert((self.caller == self.caller)); }; }`
— exercises `self.caller` in an assertion inside a finalize block. -/
def touch : Entrypoint :=
  { name := "touch"
    body := #[ .assert (.eq (.effect (.contextRead .userId)) (.effect (.contextRead .userId))) "caller" ] }

def ctxModule : Module :=
  { name := "Ctx", state := #[lastHeight], entrypoints := #[recordHeight, touch] }

def ctxLowersOk : Bool :=
  match renderModule ctxModule with
  | .ok _ => true
  | .error _ => false

theorem ctx_lowers_ok : ctxLowersOk = true := by native_decide

/-- The lowered Leo source contains the verified context intrinsics. -/
def ctxLeoHasMarkers : Bool :=
  match renderModule ctxModule with
  | .ok s =>
      s.contains "program ctx.aleo" &&
      s.contains "mapping lastHeight: u64 => u32" &&
      s.contains "block.height" &&
      s.contains "self.caller" &&
      s.contains "Mapping::set" &&
      s.contains "fn record_height" &&
      s.contains "fn touch" &&
      s.contains "Final"
  | .error _ => false

theorem ctx_leo_has_markers : ctxLeoHasMarkers = true := by native_decide

example : True := by
  have _ := @ctx_lowers_ok
  have _ := @ctx_leo_has_markers
  exact True.intro

end ProofForge.Tests.AleoLeoContextLoweringSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-context-lowering-smoke: contextRead -> self.caller / block.height checked"
  return 0
