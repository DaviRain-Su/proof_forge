import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target

/-- Open semantic capability identity. Builtins below preserve the public API,
while target extensions can introduce stable IDs without editing a shared
inductive or every exhaustive consumer. -/
structure Capability where
  id : String
  deriving BEq, DecidableEq

instance : Repr Capability where
  reprPrec capability _ := repr capability.id

def Capability.ofId (id : String) : Capability := { id }

def Capability.storageScalar := Capability.ofId "storage.scalar"
def Capability.storageMap := Capability.ofId "storage.map"
def Capability.storageArray := Capability.ofId "storage.array"
def Capability.callerSender := Capability.ofId "caller.sender"
def Capability.valueNative := Capability.ofId "value.native"
def Capability.eventsEmit := Capability.ofId "events.emit"
def Capability.crosscallInvoke := Capability.ofId "crosscall.invoke"
def Capability.crosscallNamed := Capability.ofId "crosscall.named"
def Capability.crosscallContinue := Capability.ofId "crosscall.continue"
def Capability.nearPromise := Capability.ofId "near.promise"
def Capability.envBlock := Capability.ofId "env.block"
def Capability.controlConditional := Capability.ofId "control.conditional"
def Capability.controlBoundedLoop := Capability.ofId "control.bounded_loop"
def Capability.controlUnboundedLoop := Capability.ofId "control.unbounded_loop"
def Capability.dataDynamicBytes := Capability.ofId "data.dynamic_bytes"
def Capability.dataFixedArray := Capability.ofId "data.fixed_array"
def Capability.dataDynamicArray := Capability.ofId "data.dynamic_array"
def Capability.dataStruct := Capability.ofId "data.struct"
/-- Consumable, owner-bound record value. Targets without native linear
ownership semantics must reject rather than lower it as a copyable struct. -/
def Capability.dataLinearRecord := Capability.ofId "data.linear_record"
def Capability.cryptoHash := Capability.ofId "crypto.hash"
def Capability.cryptoEcrecover := Capability.ofId "crypto.ecrecover"
def Capability.assertions := Capability.ofId "assertions.check"
def Capability.accountExplicit := Capability.ofId "account.explicit"
def Capability.runtimeAllocator := Capability.ofId "runtime.allocator"
def Capability.runtimeMemory := Capability.ofId "runtime.memory"
def Capability.runtimeReturnData := Capability.ofId "runtime.return_data"
def Capability.runtimeComputeUnits := Capability.ofId "runtime.compute_units"
def Capability.storagePda := Capability.ofId "storage.pda"
def Capability.crosscallCpi := Capability.ofId "crosscall.cpi"
def Capability.checkedArithmetic := Capability.ofId "arith.checked"
def Capability.zkCircuit := Capability.ofId "zk.circuit"
def Capability.zkProof := Capability.ofId "zk.proof"

instance : ToString Capability where
  toString c := c.id

abbrev CapabilitySet := Array Capability

def CapabilitySet.contains (set : CapabilitySet) (capability : Capability) : Bool :=
  set.any (fun c => c == capability)

def CapabilitySet.ids (set : CapabilitySet) : Array String :=
  set.map Capability.id

end ProofForge.Target
