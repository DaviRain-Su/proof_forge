import ProofForge.Backend.Aleo.IR
import ProofForge.Contract.SdkSchema
import ProofForge.IR.Contract
import ProofForge.IR.Portability
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Target.Adapter

/-! Aleo/Leo Road 2 slice 1: record declaration + creation.

Aleo's ZK value proposition is private **records** (UTXO-like state with an
`owner: address`). Neither Psy nor the portable IR model records, so an
opt-in `StructDecl.isRecord` flag (mirroring `deriveStorage`) marks a struct
to lower as a Leo `record`. This smoke covers the first Road 2 slice:

- a `record Token { owner: address, amount: u64 }` declaration;
- a pure `fn mint(amount) -> Token` that CREATES a record from `self.caller`
  (verified against ProvableHQ/leo migration/transitions_to_fn).

Record CONSUME/transfer (the UTXO spend side) needs private input-record
parameters, which the portable IR does not express yet — that is a later slice. -/

namespace ProofForge.Tests.AleoLeoRecordLoweringSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

def tokenRecord : StructDecl :=
  { name := "Token"
    fields := #[{ id := "owner", type := .address }, { id := "amount", type := .u64 }]
    isRecord := true }

/-- `fn mint(amount: u64) -> Token { return Token { owner: self.caller, amount: amount }; }` -/
def mint : Entrypoint :=
  { name := "mint"
    params := #[("amount", .u64)]
    returns := .structType "Token"
    body := #[ .return (.structLit "Token"
        #[("owner", .effect (.contextRead .userId)), ("amount", .local "amount")]) ] }

def tokenModule : Module :=
  { name := "Tok", structs := #[tokenRecord], state := #[], entrypoints := #[mint] }

def recordLowersOk : Bool :=
  match renderModule tokenModule with
  | .ok _ => true
  | .error _ => false

theorem record_lowers_ok : recordLowersOk = true := by native_decide

/-- The lowered Leo source declares a record and mints it from `self.caller`. -/
def recordLeoHasMarkers : Bool :=
  match renderModule tokenModule with
  | .ok s =>
      s.contains "program tok.aleo" &&
      s.contains "record Token {" &&
      s.contains "owner: address" &&
      s.contains "amount: u64" &&
      s.contains "fn mint(amount: u64) -> Token" &&
      s.contains "Token { owner: self.caller, amount: amount }"
  | .error _ => false

theorem record_leo_has_markers : recordLeoHasMarkers = true := by native_decide

def missingOwnerRecord : StructDecl :=
  { name := "BrokenRecord"
    fields := #[{ id := "amount", type := .u64 }]
    isRecord := true }

def missingOwnerModule : Module :=
  { name := "Broken", structs := #[missingOwnerRecord], state := #[], entrypoints := #[] }

/-- Leo records require exactly one `owner: address` field. -/
def missingRecordOwnerFailsClosed : Bool :=
  match renderModule missingOwnerModule with
  | .error e => e.message.contains "BrokenRecord" && e.message.contains "owner: address"
  | .ok _ => false

theorem missing_record_owner_fails_closed : missingRecordOwnerFailsClosed = true := by
  native_decide

def valueStructWithOwner : StructDecl :=
  { name := "ValueWithOwner"
    fields := #[
      { id := "owner", type := .address },
      { id := "amount", type := .u64 }
    ] }

def valueStructWithOwnerModule : Module :=
  { name := "ValueOwner"
    structs := #[valueStructWithOwner]
    state := #[]
    entrypoints := #[] }

/-- Leo 4.0.2 reserves `owner` for record ownership; an ordinary value struct
cannot use that field name. The record fixture above remains the positive case. -/
def valueStructOwnerFailsClosed : Bool :=
  match renderModule valueStructWithOwnerModule with
  | .error error =>
      error.message.contains "ValueWithOwner" &&
      error.message.contains "value struct" &&
      error.message.contains "owner" &&
      error.message.contains "record"
  | .ok _ => false

theorem value_struct_owner_fails_closed : valueStructOwnerFailsClosed = true := by
  native_decide

/-- Shared SDK schema must preserve the linear-record semantic marker instead
of serializing it as an ordinary copyable struct. -/
def recordSchemaKeepsSemantics : Bool :=
  let json := ProofForge.Contract.SdkSchema.structJson tokenRecord
  json.contains "\"semantics\": \"linear_record\""

theorem record_schema_keeps_semantics : recordSchemaKeepsSemantics = true := by
  native_decide

/-- Shared adapter reporting must say whether linear records are native or
rejected; an ordinary struct fallback is never an allowed disposition. -/
def recordAdapterReportsAreExplicit : Bool :=
  let evm := ProofForge.Target.CrosscallMaterialize.linearRecordForProfile ProofForge.Target.evm
  let aleo := ProofForge.Target.CrosscallMaterialize.linearRecordForProfile ProofForge.Target.aleoLeo
  evm.disposition == .reject && aleo.disposition == .materialize

theorem record_adapter_reports_are_explicit : recordAdapterReportsAreExplicit = true := by
  native_decide

def recordCapabilityIsDeclared : Bool :=
  tokenModule.capabilities.contains ProofForge.Target.Capability.dataLinearRecord

theorem record_capability_is_declared : recordCapabilityIsDeclared = true := by
  native_decide

def evmRejectsLinearRecord : Bool :=
  match ProofForge.Target.resolveModule ProofForge.Target.evm tokenModule with
  | .error error => error.message.contains "data.linear_record"
  | .ok _ => false

theorem evm_rejects_linear_record : evmRejectsLinearRecord = true := by
  native_decide

def portabilityFlagsLinearRecordOutsideZk : Bool :=
  (ProofForge.IR.Portability.familyOnlyViolations tokenModule .evm).any fun finding =>
    finding.detail.contains "linear record"

theorem portability_flags_linear_record_outside_zk : portabilityFlagsLinearRecordOutsideZk = true := by
  native_decide

def wrapperStruct : StructDecl :=
  { name := "Wrapper", fields := #[{ id := "inner", type := .structType "Token" }] }

def nestedRecordStateModule : Module :=
  { name := "NestedRecordState"
    structs := #[tokenRecord, wrapperStruct]
    state := #[{ id := "wrapped", kind := .scalar, type := .structType "Wrapper" }]
    entrypoints := #[] }

def recordMapKeyModule : Module :=
  { name := "RecordMapKey"
    structs := #[tokenRecord]
    state := #[{ id := "ledger", kind := .map (.fixedArray (.structType "Token") 2) 8, type := .u64 }]
    entrypoints := #[] }

def recordMapValueModule : Module :=
  { name := "RecordMapValue"
    structs := #[tokenRecord]
    state := #[{ id := "ledger", kind := .map .u64 8, type := .fixedArray (.structType "Token") 2 }]
    entrypoints := #[] }

def linearRecordStateRejects (module : Module) : Bool :=
  match validateState module with
  | .error error => error.message.contains "linear record"
  | .ok _ => false

def nestedLinearRecordStateFailsClosed : Bool := linearRecordStateRejects nestedRecordStateModule
def linearRecordMapKeyFailsClosed : Bool := linearRecordStateRejects recordMapKeyModule
def linearRecordMapValueFailsClosed : Bool := linearRecordStateRejects recordMapValueModule

theorem nested_linear_record_state_fails_closed : nestedLinearRecordStateFailsClosed = true := by
  native_decide
theorem linear_record_map_key_fails_closed : linearRecordMapKeyFailsClosed = true := by
  native_decide
theorem linear_record_map_value_fails_closed : linearRecordMapValueFailsClosed = true := by
  native_decide

def recordReportUsesCapability : Bool :=
  let renamed := { ProofForge.Target.aleoLeo with id := "renamed-linear-record-target" }
  let stripped :=
    { ProofForge.Target.aleoLeo with
      capabilities := ProofForge.Target.aleoLeo.capabilities.filter (· != .dataLinearRecord) }
  let renamedReport := ProofForge.Target.CrosscallMaterialize.linearRecordForProfile renamed
  let strippedReport := ProofForge.Target.CrosscallMaterialize.linearRecordForProfile stripped
  renamedReport.disposition == .materialize && strippedReport.disposition == .reject

theorem record_report_uses_capability : recordReportUsesCapability = true := by
  native_decide

def cycleA : StructDecl :=
  { name := "CycleA", fields := #[{ id := "next", type := .structType "CycleB" }] }

def cycleB : StructDecl :=
  { name := "CycleB"
    fields := #[
      { id := "previous", type := .structType "CycleA" },
      { id := "record", type := .structType "Token" }
    ] }

def cyclicRecordModule : Module :=
  { name := "CyclicRecord", structs := #[tokenRecord, cycleA, cycleB], state := #[], entrypoints := #[] }

def cyclicRecordTraversalTerminatesAndFindsRecord : Bool :=
  containsLinearRecord cyclicRecordModule (.structType "CycleA")

theorem cyclic_record_traversal_terminates_and_finds_record :
    cyclicRecordTraversalTerminatesAndFindsRecord = true := by
  native_decide

example : True := by
  have _ := @record_lowers_ok
  have _ := @record_leo_has_markers
  have _ := @missing_record_owner_fails_closed
  have _ := @value_struct_owner_fails_closed
  have _ := @record_schema_keeps_semantics
  have _ := @record_adapter_reports_are_explicit
  have _ := @record_capability_is_declared
  have _ := @evm_rejects_linear_record
  have _ := @portability_flags_linear_record_outside_zk
  have _ := @nested_linear_record_state_fails_closed
  have _ := @linear_record_map_key_fails_closed
  have _ := @linear_record_map_value_fails_closed
  have _ := @record_report_uses_capability
  have _ := @cyclic_record_traversal_terminates_and_finds_record
  exact True.intro

end ProofForge.Tests.AleoLeoRecordLoweringSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-record-lowering-smoke: record decl + mint checked"
  return 0
