import ProofForge.Backend.Aleo.Metadata
import ProofForge.Backend.Aleo.MetadataJson
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.PureMath

/-! Aleo/Leo artifact metadata smoke.

The `aleo-leo` counterpart of `Tests/PsyMetadataExport`: builds artifact
metadata directly from portable IR modules (Counter = scalar state, PureMath =
no state) and checks the compact + pretty JSON renderers emit the expected
`proof-forge-artifact.json` shape (target id, module name, entrypoint ABI
surface, on-chain state surface, capability list). -/

namespace ProofForge.Tests.AleoLeoMetadataSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.Metadata
open ProofForge.Backend.Aleo.MetadataJson

/-- A map-state module so the metadata covers all three state shapes
(scalar / map / none) across the test set. -/
def ledgerState : StateDecl :=
  { id := "ledger", kind := .map .u64 8, type := .u64 }

def ledgerModule : Module :=
  { name := "Ledger"
    state := #[ledgerState]
    entrypoints := #[] }

def counterWriteModule : Module :=
  { Examples.Counter.module with
    entrypoints := #[Examples.Counter.initializeEntrypoint, Examples.Counter.increment] }

def counterMeta :=
  buildArtifactMetadata counterWriteModule

def pureMathMeta :=
  buildArtifactMetadata Examples.PureMath.module

def ledgerMeta :=
  buildArtifactMetadata ledgerModule

/-- Invalid codegen surfaces do not get misleading metadata. -/
def counterGetterMetadataFailsClosed : Bool :=
  match buildArtifactMetadata Examples.Counter.module with
  | .error e => e.message.contains "get" && e.message.contains "non-Unit return"
  | .ok _ => false

theorem counter_getter_metadata_fails_closed : counterGetterMetadataFailsClosed = true := by
  native_decide

/-- Counter metadata records the scalar→mapping state surface and the Counter
entrypoints. -/
def counterMetaOk : Bool :=
  match counterMeta with
  | .ok metadata =>
      metadata.targetId == "aleo-leo" &&
      metadata.moduleName == "Counter" &&
      metadata.entrypoints.any (fun e => e.name == "increment" && e.returnType == "Final") &&
      metadata.state.size == 1 &&
      metadata.state[0]!.id == "count" &&
      metadata.state[0]!.keyType == "u64" &&
      metadata.state[0]!.valueType == "u64" &&
      metadata.capabilities.contains "storage.scalar"
  | .error _ => false

theorem counter_meta_ok : counterMetaOk = true := by native_decide

/-- Map-state metadata records the real `mapping K => V` key/value types. -/
def ledgerMetaOk : Bool :=
  match ledgerMeta with
  | .ok metadata =>
      metadata.state.size == 1 &&
      metadata.state[0]!.id == "ledger" &&
      metadata.state[0]!.keyType == "u64" &&
      metadata.state[0]!.valueType == "u64"
  | .error _ => false

theorem ledger_meta_ok : ledgerMetaOk = true := by native_decide

/-- PureMath metadata has an empty state surface. -/
def pureMathMetaOk : Bool :=
  match pureMathMeta with
  | .ok metadata =>
      metadata.state.isEmpty &&
      metadata.entrypoints.any (fun e =>
        e.name == "sumFirst10" && e.portableReturnType == "U64" && e.returnType == "u64")
  | .error _ => false

theorem pure_math_meta_ok : pureMathMetaOk = true := by native_decide

/-- Compact JSON contains the entrypoint names and the state id. -/
def counterCompactJsonOk : Bool :=
  match counterMeta with
  | .ok metadata =>
      let s := renderArtifactMetadata metadata
      s.contains "\"targetId\": \"aleo-leo\"" &&
      s.contains "\"moduleName\": \"Counter\"" &&
      s.contains "\"id\": \"count\"" &&
      s.contains "\"portableReturnType\": \"Unit\"" &&
      s.contains "\"returnType\": \"Final\"" &&
      s.contains "\"increment\""
  | .error _ => false

theorem counter_compact_json_ok : counterCompactJsonOk = true := by native_decide

/-- Pretty JSON is also well-formed and contains the same fields. -/
def pureMathPrettyJsonOk : Bool :=
  match pureMathMeta with
  | .ok metadata =>
      let s := renderArtifactMetadataPretty metadata
      s.contains "\"targetId\": \"aleo-leo\"" &&
      s.contains "\"state\": []" &&
      s.contains "\"sumFirst10\""
  | .error _ => false

theorem pure_math_pretty_json_ok : pureMathPrettyJsonOk = true := by native_decide

example : True := by
  have _ := @counter_meta_ok
  have _ := @counter_getter_metadata_fails_closed
  have _ := @ledger_meta_ok
  have _ := @pure_math_meta_ok
  have _ := @counter_compact_json_ok
  have _ := @pure_math_pretty_json_ok
  exact True.intro

end ProofForge.Tests.AleoLeoMetadataSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-metadata-smoke: artifact metadata + JSON renderers checked"
  return 0
