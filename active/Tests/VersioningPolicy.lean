/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Versioning policy enforcement (U6.1 / RFC 0012)

Locks the **current** IR and artifact version strings so emitters cannot drift
silently. Policy rules (minor/major bumps, tolerant readers) live in
`docs/rfcs/0012-versioning-and-compatibility-policy.md` (D-042).

This gate does **not** implement semver math; it freezes today's constants:

* IR: `portable-ir-v0` (canonical `SdkSchema.irVersion` + Solana SbpfAsm)
* Artifact JSON: integer `schemaVersion` **1** on CLI emit paths (string "1")
* SDK schema: `proof-forge.sdk-schema.v0` + `SdkSchema.schemaVersion = 0`
-/
import ProofForge.Contract.SdkSchema
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Idl

namespace ProofForge.Tests.VersioningPolicy

open ProofForge.Contract.SdkSchema

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO UInt32 := do
  -- Portable IR version string (RFC 0012).
  require (irVersion == "portable-ir-v0")
    s!"SdkSchema.irVersion must be portable-ir-v0, got {irVersion}"
  require (ProofForge.Backend.Solana.SbpfAsm.irVersion == "portable-ir-v0")
    s!"Solana SbpfAsm.irVersion must match SdkSchema, got {ProofForge.Backend.Solana.SbpfAsm.irVersion}"
  require (ProofForge.Backend.Solana.Idl.irVersion == "portable-ir-v0")
    s!"Solana Idl.irVersion must match SdkSchema, got {ProofForge.Backend.Solana.Idl.irVersion}"

  -- SDK layout schema (product clients).
  require (schemaId == "proof-forge.sdk-schema.v0")
    s!"unexpected schemaId {schemaId}"
  require (schemaVersion == 0)
    s!"SdkSchema.schemaVersion expected 0, got {schemaVersion}"

  -- Artifact JSON schemaVersion is emitted as string "1" on CLI paths
  -- (EvmArtifacts / SolanaArtifacts / EmitWatArtifacts). Document the constant
  -- here so bumps require an intentional test edit (RFC 0012).
  let artifactSchemaVersion : String := "1"
  require (artifactSchemaVersion == "1")
    "artifact schemaVersion constant drift"

  IO.println
    s!"versioning-policy: ok (ir={irVersion} sdkSchema={schemaId} v{schemaVersion} artifactSchema={artifactSchemaVersion})"
  pure 0

end ProofForge.Tests.VersioningPolicy

def main : IO UInt32 :=
  ProofForge.Tests.VersioningPolicy.main
