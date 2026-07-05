import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target

inductive Capability where
  | storageScalar
  | storageMap
  | storageArray
  | callerSender
  | valueNative
  | eventsEmit
  | crosscallInvoke
  | envBlock
  | controlConditional
  | controlBoundedLoop
  | controlUnboundedLoop
  | dataDynamicBytes
  | dataFixedArray
  | dataDynamicArray
  | dataStruct
  | cryptoHash
  | assertions
  | accountExplicit
  | runtimeAllocator
  | runtimeMemory
  | runtimeReturnData
  | runtimeComputeUnits
  | storagePda
  | crosscallCpi
  | zkCircuit
  | zkProof
  deriving BEq, DecidableEq, Repr

def Capability.id : Capability → String
  | .storageScalar => "storage.scalar"
  | .storageMap => "storage.map"
  | .storageArray => "storage.array"
  | .callerSender => "caller.sender"
  | .valueNative => "value.native"
  | .eventsEmit => "events.emit"
  | .crosscallInvoke => "crosscall.invoke"
  | .envBlock => "env.block"
  | .controlConditional => "control.conditional"
  | .controlBoundedLoop => "control.bounded_loop"
  | .controlUnboundedLoop => "control.unbounded_loop"
  | .dataFixedArray => "data.fixed_array"
  | .dataDynamicArray => "data.dynamic_array"
  | .dataDynamicBytes => "data.dynamic_bytes"
  | .dataStruct => "data.struct"
  | .cryptoHash => "crypto.hash"
  | .assertions => "assertions.check"
  | .accountExplicit => "account.explicit"
  | .runtimeAllocator => "runtime.allocator"
  | .runtimeMemory => "runtime.memory"
  | .runtimeReturnData => "runtime.return_data"
  | .runtimeComputeUnits => "runtime.compute_units"
  | .storagePda => "storage.pda"
  | .crosscallCpi => "crosscall.cpi"
  | .zkCircuit => "zk.circuit"
  | .zkProof => "zk.proof"

instance : ToString Capability where
  toString c := c.id

abbrev CapabilitySet := Array Capability

def CapabilitySet.contains (set : CapabilitySet) (capability : Capability) : Bool :=
  set.any (fun c => c == capability)

def CapabilitySet.ids (set : CapabilitySet) : Array String :=
  set.map Capability.id

end ProofForge.Target
