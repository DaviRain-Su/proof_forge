/-
  Sole JSON encode/decode for Psy DPN Schema V1, shaped like dargo package
  `target/<pkg>.json` (array of `DPNFunctionCircuitDefinition`).
-/
import Lean.Data.Json
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1

namespace ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

open Lean
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1

private def u64ToJson (n : UInt64) : Json :=
  Json.num (JsonNumber.fromNat n.toNat)

private def natToJson (n : Nat) : Json :=
  Json.num (JsonNumber.fromNat n)

private def exceptToOption {α} : Except String α → Option α
  | .ok a => some a
  | .error _ => none

private def jsonAsNat? : Json → Option Nat
  | .num n =>
      -- Integer-only package JSON from dargo.
      n.toString.toNat?
  | _ => none

private def jsonAsUInt64? (j : Json) : Option UInt64 :=
  jsonAsNat? j |>.map UInt64.ofNat

private def jsonAsUInt32? (j : Json) : Option UInt32 :=
  match jsonAsNat? j with
  | some n => if n < UInt32.size then some (UInt32.ofNat n) else none
  | none => none

private def jsonAsString? : Json → Option String
  | .str s => some s
  | _ => none

private def field? (j : Json) (k : String) : Option Json :=
  exceptToOption (j.getObjVal? k)

private def arr? (j : Json) : Option (Array Json) :=
  exceptToOption j.getArr?

def encodeVarDef (d : IndexedVarDefV1) : Json :=
  Json.mkObj [
    ("data_type", natToJson d.dataType.toUInt8.toNat),
    ("index", natToJson d.index),
    ("op_type", natToJson d.opType.toUInt16.toNat),
    ("inputs", Json.arr (d.inputs.map u64ToJson))
  ]

def encodeAssert (a : AssertEqV1) : Json :=
  Json.mkObj [
    ("left", u64ToJson a.left),
    ("right", u64ToJson a.right),
    ("message", Json.str a.message)
  ]

def encodeStateCmd : StateCmdV1 → Json
  | .getSelfUserCurrentContractStateSlotSingle sub =>
      Json.mkObj [
        ("type", Json.str "GetSelfUserCurrentContractStateSlotSingle"),
        ("sub_slot_index", u64ToJson sub)
      ]
  | .setContractStateSlotSingle cond sub val =>
      Json.mkObj [
        ("type", Json.str "SetContractStateSlotSingle"),
        ("condition", u64ToJson cond),
        ("sub_slot_index", u64ToJson sub),
        ("value", u64ToJson val)
      ]
  | .getSelfUserCurrentContractStateSlotHash slot =>
      Json.mkObj [
        ("type", Json.str "GetSelfUserCurrentContractStateSlotHash"),
        ("slot_index", u64ToJson slot)
      ]
  | .setContractStateSlotHash cond slot value =>
      Json.mkObj [
        ("type", Json.str "SetContractStateSlotHash"),
        ("condition", u64ToJson cond),
        ("slot_index", u64ToJson slot),
        ("value", Json.arr (value.map u64ToJson))
      ]
  | .invokeExternalContractFunctionSync cond cid mid args nOut =>
      Json.mkObj [
        ("type", Json.str "InvokeExternalContractFunctionSync"),
        ("condition", u64ToJson cond),
        ("contract_id", u64ToJson cid),
        ("method_id", u64ToJson mid),
        ("input_args", Json.arr (args.map u64ToJson)),
        ("num_outputs", natToJson nOut.toNat)
      ]

def encodeEvent (e : EventRecordV1) : Json :=
  Json.mkObj [
    ("condition", u64ToJson e.condition),
    ("checkpoint_id", u64ToJson e.checkpointId),
    ("user_id", u64ToJson e.userId),
    ("contract_id", u64ToJson e.contractId),
    ("data", Json.arr (e.data.map u64ToJson))
  ]

def encodeFunction (f : FunctionCircuitDefV1) : Json :=
  Json.mkObj [
    ("name", Json.str f.name),
    ("method_id", natToJson f.methodId.toNat),
    ("circuit_inputs", Json.arr (f.circuitInputs.map u64ToJson)),
    ("circuit_outputs", Json.arr (f.circuitOutputs.map u64ToJson)),
    ("state_commands", Json.arr (f.stateCommands.map encodeStateCmd)),
    ("state_command_resolution_indices",
      Json.arr (f.stateCommandResolutionIndices.map natToJson)),
    ("assertions", Json.arr (f.assertions.map encodeAssert)),
    ("definitions", Json.arr (f.definitions.map encodeVarDef)),
    ("events", Json.arr (f.events.map encodeEvent))
  ]

def encodePackage (pkg : PackageV1) : Json :=
  Json.arr (pkg.map encodeFunction)

/-- Compact UTF-8 package JSON (no spaces), matching typical dargo write style. -/
def encodePackageCompact (pkg : PackageV1) : String :=
  (encodePackage pkg).compress

private def decodeVarDef? (j : Json) : Option IndexedVarDefV1 := do
  let dataType ← DataTypeV1.ofUInt8? (UInt8.ofNat (← jsonAsNat? (← field? j "data_type")))
  let index ← jsonAsNat? (← field? j "index")
  let opType ← OpTypeV1.ofUInt16? (UInt16.ofNat (← jsonAsNat? (← field? j "op_type")))
  let inputsJ ← arr? (← field? j "inputs")
  let inputs ← inputsJ.mapM jsonAsUInt64?
  pure { dataType, index, opType, inputs }

private def decodeAssert? (j : Json) : Option AssertEqV1 := do
  let left ← jsonAsUInt64? (← field? j "left")
  let right ← jsonAsUInt64? (← field? j "right")
  let message ← jsonAsString? (← field? j "message")
  pure { left, right, message }

private def decodeStateCmd? (j : Json) : Option StateCmdV1 := do
  let tag ← jsonAsString? (← field? j "type")
  match tag with
  | "GetSelfUserCurrentContractStateSlotSingle" =>
      pure (.getSelfUserCurrentContractStateSlotSingle (← jsonAsUInt64? (← field? j "sub_slot_index")))
  | "SetContractStateSlotSingle" =>
      pure (.setContractStateSlotSingle
        (← jsonAsUInt64? (← field? j "condition"))
        (← jsonAsUInt64? (← field? j "sub_slot_index"))
        (← jsonAsUInt64? (← field? j "value")))
  | "GetSelfUserCurrentContractStateSlotHash" =>
      pure (.getSelfUserCurrentContractStateSlotHash (← jsonAsUInt64? (← field? j "slot_index")))
  | "SetContractStateSlotHash" =>
      let valueJ ← arr? (← field? j "value")
      pure (.setContractStateSlotHash
        (← jsonAsUInt64? (← field? j "condition"))
        (← jsonAsUInt64? (← field? j "slot_index"))
        (← valueJ.mapM jsonAsUInt64?))
  | "InvokeExternalContractFunctionSync" =>
      let argsJ ← arr? (← field? j "input_args")
      pure (.invokeExternalContractFunctionSync
        (← jsonAsUInt64? (← field? j "condition"))
        (← jsonAsUInt64? (← field? j "contract_id"))
        (← jsonAsUInt64? (← field? j "method_id"))
        (← argsJ.mapM jsonAsUInt64?)
        (← jsonAsUInt32? (← field? j "num_outputs")))
  | _ => none

private def decodeEvent? (j : Json) : Option EventRecordV1 := do
  let condition ← jsonAsUInt64? (← field? j "condition")
  let checkpointId ← jsonAsUInt64? (← field? j "checkpoint_id")
  let userId ← jsonAsUInt64? (← field? j "user_id")
  let contractId ← jsonAsUInt64? (← field? j "contract_id")
  let data ← (← arr? (← field? j "data")).mapM jsonAsUInt64?
  pure { condition, checkpointId, userId, contractId, data }

private def decodeFunction? (j : Json) : Option FunctionCircuitDefV1 := do
  let name ← jsonAsString? (← field? j "name")
  let methodId ← jsonAsUInt32? (← field? j "method_id")
  let circuitInputs ← (← arr? (← field? j "circuit_inputs")).mapM jsonAsUInt64?
  let circuitOutputs ← (← arr? (← field? j "circuit_outputs")).mapM jsonAsUInt64?
  let stateCommands ← (← arr? (← field? j "state_commands")).mapM decodeStateCmd?
  let resIdx ← (← arr? (← field? j "state_command_resolution_indices")).mapM jsonAsNat?
  let assertions ← (← arr? (← field? j "assertions")).mapM decodeAssert?
  let definitions ← (← arr? (← field? j "definitions")).mapM decodeVarDef?
  let events ← (← arr? (← field? j "events")).mapM decodeEvent?
  pure {
    name, methodId, circuitInputs, circuitOutputs, stateCommands
    stateCommandResolutionIndices := resIdx
    assertions, definitions, events
  }

def decodePackage? (j : Json) : Option PackageV1 := do
  let arr ← arr? j
  arr.mapM decodeFunction?

def parsePackage? (s : String) : Option PackageV1 :=
  match Json.parse s with
  | .error _ => none
  | .ok j => decodePackage? j

end ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1
