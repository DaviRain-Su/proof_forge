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

def counterMeta : ArtifactMetadata :=
  buildArtifactMetadata Examples.Counter.module

def pureMathMeta : ArtifactMetadata :=
  buildArtifactMetadata Examples.PureMath.module

def ledgerMeta : ArtifactMetadata :=
  buildArtifactMetadata ledgerModule

/-- Counter metadata records the scalar→mapping state surface and the Counter
entrypoints. -/
def counterMetaOk : Bool :=
  counterMeta.targetId == "aleo-leo" &&
  counterMeta.moduleName == "Counter" &&
  counterMeta.entrypoints.any (fun e => e.name == "increment") &&
  counterMeta.state.size == 1 &&
  counterMeta.state[0]!.id == "count" &&
  counterMeta.state[0]!.keyType == "U64" &&
  counterMeta.state[0]!.valueType == "U64" &&
  counterMeta.capabilities.contains "storage.scalar"

theorem counter_meta_ok : counterMetaOk = true := by native_decide

/-- Map-state metadata records the real `mapping K => V` key/value types. -/
def ledgerMetaOk : Bool :=
  ledgerMeta.state.size == 1 &&
  ledgerMeta.state[0]!.id == "ledger" &&
  ledgerMeta.state[0]!.keyType == "U64" &&
  ledgerMeta.state[0]!.valueType == "U64"

theorem ledger_meta_ok : ledgerMetaOk = true := by native_decide

/-- PureMath metadata has an empty state surface. -/
def pureMathMetaOk : Bool :=
  pureMathMeta.state.isEmpty &&
  pureMathMeta.entrypoints.any (fun e => e.name == "sumFirst10")

theorem pure_math_meta_ok : pureMathMetaOk = true := by native_decide

/-- Compact JSON contains the entrypoint names and the state id. -/
def counterCompactJsonOk : Bool :=
  let s := renderArtifactMetadata counterMeta
  s.contains "\"targetId\": \"aleo-leo\"" &&
  s.contains "\"moduleName\": \"Counter\"" &&
  s.contains "\"id\": \"count\"" &&
  s.contains "\"increment\""

theorem counter_compact_json_ok : counterCompactJsonOk = true := by native_decide

/-- Pretty JSON is also well-formed and contains the same fields. -/
def pureMathPrettyJsonOk : Bool :=
  let s := renderArtifactMetadataPretty pureMathMeta
  s.contains "\"targetId\": \"aleo-leo\"" &&
  s.contains "\"state\": []" &&
  s.contains "\"sumFirst10\""

theorem pure_math_pretty_json_ok : pureMathPrettyJsonOk = true := by native_decide

example : True := by
  have _ := @counter_meta_ok
  have _ := @ledger_meta_ok
  have _ := @pure_math_meta_ok
  have _ := @counter_compact_json_ok
  have _ := @pure_math_pretty_json_ok
  exact True.intro

end ProofForge.Tests.AleoLeoMetadataSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-metadata-smoke: artifact metadata + JSON renderers checked"
  return 0
