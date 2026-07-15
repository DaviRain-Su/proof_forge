/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Artifact Contract v1 (Seam B / LR-0)

Freeze the consumer-facing identity of `proof-forge-artifact.json` so Rust
harnesses and differential scripts depend only on documented fields.

Normative prose: `docs/superpowers/specs/2026-07-15-artifact-contract-v1.md`.
Nested honesty for typed outputs lives in `ProofForge.Target.ArtifactBundle`
and is intentionally unchanged by this module.
-/

namespace ProofForge.Target.ArtifactContract

/-- Document schema identity for consumer tooling (not the nested bundle kind). -/
def documentSchemaId : String := "proof-forge-artifact"

/-- Top-level consumer `schemaVersion` major. Emitters may serialize as JSON
number `1` or string `"1"`; consumers must accept both. -/
def schemaVersion : Nat := 1

/-- Nested `artifactBundle.schemaVersion` (always a string today). -/
def bundleSchemaVersion : String := "1"

/-- Nested bundle kind identity. -/
def bundleKind : String := "proof-forge-artifact-bundle"

/-- Fields runners may rely on without treating planning metadata as ABI. -/
def consumerAllowlist : Array String := #[
  "schemaVersion",
  "target",
  "sourceModule",
  "artifactKind",
  "artifactBundle",
  "artifacts",
  "abi"
]

/-- Required top-level keys for any consumer that loads metadata. -/
def requiredTopLevelFields : Array String := #[
  "schemaVersion",
  "target",
  "artifactKind",
  "sourceModule"
]

/-- Additional required keys when a scenario/harness declares execution. -/
def requiredTopLevelForExecution : Array String := #[
  "artifacts",
  "artifactBundle"
]

/-- Nested `artifactBundle` keys that execution consumers must see. -/
def requiredBundleFields : Array String := #[
  "schemaVersion",
  "kind",
  "targetId",
  "outputs"
]

/-- Primary-triad CLI emitters that write `proof-forge-artifact.json`.
Used by LR-0 inventory gates; keep in sync when adding emit paths. -/
structure EmitterInventory where
  modulePath : String
  targets : Array String
  notes : String
  deriving Repr

def primaryTriadEmitters : Array EmitterInventory := #[
  {
    modulePath := "ProofForge/Cli/EvmArtifacts.lean"
    targets := #["evm"]
    notes := "product/fixture bytecode + Yul; full fields + artifactBundle"
  },
  {
    modulePath := "ProofForge/Cli/EmitWatArtifacts.lean"
    targets := #["wasm-near", "wasm-cosmwasm", "wasm-stellar-soroban"]
    notes := "EmitWat product/fixture; full fields + artifactBundle"
  },
  {
    modulePath := "ProofForge/Cli/ContractSourceArtifacts.lean"
    targets := #["solana-sbpf-asm"]
    notes := "contract_source assembly intermediate; artifactBundle intermediate-only"
  },
  {
    modulePath := "ProofForge/Cli/SolanaCommands.lean"
    targets := #["solana-sbpf-asm"]
    notes := "ELF + assembly package paths with artifactBundle; fixture ELF"
  }
]

/-- Known secondary/spike emitters. Inventory only; not required to match full
primary-triad consumer minimum until their harnesses opt into execution checks. -/
def secondaryEmitters : Array EmitterInventory := #[
  {
    modulePath := "ProofForge/Cli/SolanaArtifacts.lean"
    targets := #["solana-sbpf-asm"]
    notes := "legacy IR fixture assembly paths; some lack artifactBundle"
  },
  {
    modulePath := "ProofForge/Cli/LearnArtifacts.lean"
    targets := #["solana-sbpf-asm"]
    notes := "learn-source assembly; no artifactBundle yet"
  },
  {
    modulePath := "ProofForge/Cli/StylusArtifacts.lean"
    targets := #["wasm-arbitrum-stylus"]
    notes := "minimal metadata (schemaVersion/target/plan/artifactBundle)"
  },
  {
    modulePath := "ProofForge/Cli/PsyArtifacts.lean"
    targets := #["psy-dpn"]
    notes := "PSy metadata path; not primary triad"
  }
]

def hasField (fields : Array String) (name : String) : Bool :=
  fields.any (· == name)

def missingRequired (present : Array String) (required : Array String) : Array String :=
  required.filter fun name => !hasField present name

/-- Pure check: present top-level field names satisfy the consumer minimum. -/
def validatePresentFields
    (present : Array String)
    (forExecution : Bool) : Except String Unit := do
  let missing := missingRequired present requiredTopLevelFields
  if !missing.isEmpty then
    throw s!"artifact contract v1 missing required fields: {missing}"
  if forExecution then
    let missingExec := missingRequired present requiredTopLevelForExecution
    if !missingExec.isEmpty then
      throw s!"artifact contract v1 missing execution fields: {missingExec}"
  pure ()

end ProofForge.Target.ArtifactContract
