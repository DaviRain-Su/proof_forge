/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Product honesty: TokenFeature × primary target support matrix.
-/
import ProofForge.Contract.Token
import ProofForge.Contract.Compliance
import ProofForge.Target.Registry

open ProofForge.Contract.Token
open ProofForge.Contract.Compliance
open ProofForge.Contract.TokenAuth
open ProofForge.Target

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def evidenceFor (adapter : AdapterRef) (artifactDigest : String)
    (requirement : Requirement) (status : RequirementStatus := .passed) :
    RequirementEvidence := {
  requirementId := requirement.id
  adapter
  artifactDigest
  oracleId := "token-feature-matrix"
  oracleVersion := "1"
  command := s!"token-feature-matrix:{requirement.id}"
  toolchains := #[{ id := "lean", version := Lean.versionString }]
  status
  runResultDigest := s!"sha256:result-{requirement.id}"
}

def exactClaim (manifest : StandardManifest) (adapter : AdapterRef)
    (artifactDigest : String) : EvidenceClaim := {
  manifest
  adapter
  artifactDigest
  scope := .full
  evidence := manifest.requirements.map (evidenceFor adapter artifactDigest)
}

def evmPermitAdapter : AdapterRef := {
  id := "proof-forge.evm.erc2612"
  version := "1"
}

def nearStorageAdapter : AdapterRef := {
  id := "proof-forge.near.nep145"
  version := "1"
}

def main : IO Unit := do
  let rows := primaryFeatureMatrix
  require (rows.size == ProofForge.Contract.Token.primaryTokenTargetIds.size * knownFeatureIds.size)
    s!"matrix size {rows.size}"

  -- No feature is `full` until requirement-bound executable evidence exists.
  -- Implemented mint/burn paths remain usable but are explicitly experimental.
  for f in #[TokenFeature.mintable, .burnable] do
    require (featureSupportOnTarget "evm" f == .experimental)
      s!"evm should mark implemented {f.id} experimental"
    require (planSucceedsForFeature evm f)
      s!"evm planForTarget should succeed for {f.id}"
  for f in #[TokenFeature.capped, .pausable] do
    require (featureSupportOnTarget "evm" f == .reject)
      s!"evm should reject unmaterialized {f.id}"
    require (!planSucceedsForFeature evm f)
      s!"evm planForTarget must fail closed for {f.id}"
  for f in solanaExtensionFeatures do
    require (featureSupportOnTarget "evm" f == .reject)
      s!"evm should reject {f.id}"
    require (!planSucceedsForFeature evm f)
      s!"evm planForTarget must fail for {f.id}"
  require (featureSupportOnTarget "evm" .permit == .experimental)
    "atomic EVM permit should remain experimental until compliance evidence is bound"
  let permitClaim := exactClaim erc2612Manifest evmPermitAdapter "sha256:permit-artifact"
  require (featureSupportOnTargetWithEvidence "evm" .permit #[permitClaim] == .full)
    "exact ERC-2612 adapter/artifact evidence should promote permit"
  let wrongPermitArtifact := {
    permitClaim with artifactDigest := "sha256:different-artifact"
  }
  require (featureSupportOnTargetWithEvidence "evm" .permit #[wrongPermitArtifact] == .experimental)
    "artifact-mismatched ERC-2612 evidence must not promote permit"
  let wrongPermitAdapter := {
    permitClaim with adapter := { id := "proof-forge.evm.other", version := "1" }
  }
  require (featureSupportOnTargetWithEvidence "evm" .permit #[wrongPermitAdapter] == .experimental)
    "adapter-mismatched ERC-2612 evidence must not promote permit"
  let forgedPermitManifest := {
    erc2612Manifest with requirements := erc2612Manifest.requirements.take 1
  }
  let forgedPermitClaim := exactClaim forgedPermitManifest evmPermitAdapter
    "sha256:permit-artifact"
  require (featureSupportOnTargetWithEvidence "evm" .permit #[forgedPermitClaim] == .experimental)
    "same-id manifest with missing canonical requirements must not promote permit"
  for feature in #[TokenFeature.capped, .pausable, .confidentialTransfer] do
    require (featureSupportOnTargetWithEvidence "evm" feature #[permitClaim] == .reject)
      s!"unrelated evidence must not promote rejected EVM feature {feature.id}"
  require (planSucceedsForFeature evm .permit)
    "atomic EVM permit should route through the executable adapter"
  match planForTarget evm {
    name := "P", symbol := "P", decimals := 18, features := #[.permit]
  } with
  | .error e => throw (IO.userError s!"atomic EVM permit should plan: {e}")
  | .ok plan =>
      require (plan.operations.contains "erc20.permit") "permit operation missing"
  match planForTarget evm {
    name := "Fee", symbol := "FEE", decimals := 9, features := #[.transferFee]
  } with
  | .ok _ => throw (IO.userError "EVM must reject transfer_fee permanently")
  | .error msg =>
      require (msg.contains "product policy" || msg.contains "rejects")
        s!"EVM reject should state product policy, got: {msg}"
      require (msg.contains "solana-sbpf-asm")
        s!"EVM reject should point to Solana: {msg}"

  -- Solana: only actually rendered feature slices may plan; evidence is pending.
  for f in #[TokenFeature.mintable, .burnable] do
    require (featureSupportOnTarget "solana-sbpf-asm" f == .experimental)
      s!"solana should mark implemented core {f.id} experimental"
    require (planSucceedsForFeature solanaSbpfAsm f)
      s!"solana plan ok for {f.id}"
  for f in #[TokenFeature.transferFee, .nonTransferable, .transferHook,
      .metadataPointer, .defaultAccountState, .immutableOwner] do
    require (featureSupportOnTarget "solana-sbpf-asm" f == .experimental)
      s!"solana should mark rendered extension {f.id} experimental"
    require (planSucceedsForFeature solanaSbpfAsm f)
      s!"solana single-feature plan ok for {f.id}"
  for f in #[TokenFeature.capped, .pausable, .permit, .confidentialTransfer] do
    require (featureSupportOnTarget "solana-sbpf-asm" f == .reject)
      s!"solana should reject unmaterialized {f.id}"
    require (!planSucceedsForFeature solanaSbpfAsm f)
      s!"solana plan must fail closed for {f.id}"

  -- NEAR mint/burn bodies exist but are not yet compliance-qualified.
  for f in #[TokenFeature.mintable, .burnable] do
    require (featureSupportOnTarget "wasm-near" f == .experimental)
      s!"wasm-near should mark implemented {f.id} experimental"
    require (planSucceedsForFeature wasmNear f)
      s!"wasm-near planForTarget should succeed for {f.id}"
  for f in #[TokenFeature.capped, .pausable, .permit] do
    require (featureSupportOnTarget "wasm-near" f == .reject)
      s!"wasm-near should reject unmaterialized {f.id}"
    require (!planSucceedsForFeature wasmNear f)
      s!"wasm-near plan must fail closed for {f.id}"
  require (authSupportOnTargetWithEvidence "wasm-near" .storageDeposit #[] == .experimental)
    "NEP-145 storage support must remain experimental without evidence"
  let storageClaim := exactClaim nep145Manifest nearStorageAdapter "sha256:near-storage-artifact"
  require (authSupportOnTargetWithEvidence "wasm-near" .storageDeposit #[storageClaim] == .full)
    "full NEP-145 evidence should promote storage deposit/unregister support"
  let partialStorageClaim := {
    storageClaim with evidence := storageClaim.evidence.take 2
  }
  require (authSupportOnTargetWithEvidence "wasm-near" .storageDeposit #[partialStorageClaim] == .experimental)
    "partial NEP-145 evidence must not promote unregister support"
  for f in solanaExtensionFeatures do
    require (featureSupportOnTarget "wasm-near" f == .reject)
      s!"wasm-near should reject extension {f.id}"
    require (!planSucceedsForFeature wasmNear f)
      s!"wasm-near plan must fail for {f.id}"
  match planForTarget wasmNear {
    name := "NearFT", symbol := "NFT", decimals := 18, features := #[.mintable, .burnable]
  } with
  | .error e => throw (IO.userError s!"NEAR mintable+burnable plan: {e}")
  | .ok p =>
      require (p.standard == .nep141) "NEAR plan standard is nep-141"
      require (p.artifactKind == .nearNep141Plan) "NEAR plan artifact kind"
  require (featureSupportOnTarget "wasm-stellar-soroban" .mintable == .noLane)
    "soroban has no TokenSpec lane yet"
  match planForTarget wasmStellarSoroban {
    name := "X", symbol := "X", decimals := 0, features := #[.mintable]
  } with
  | .ok _ => throw (IO.userError "soroban TokenSpec plan must fail")
  | .error msg =>
      require (msg.contains "no TokenSpec lane")
        s!"soroban error should name no TokenSpec lane, got: {msg}"

  -- Combined FeeToken intent: Solana ok, EVM reject.
  let fee : TokenSpec := {
    name := "Fee"
    symbol := "FEE"
    decimals := 9
    features := #[.transferFee]
  }
  match planForTarget solanaSbpfAsm fee with
  | .error e => throw (IO.userError s!"Solana FeeToken should plan: {e}")
  | .ok p =>
      require (p.standard == .splToken2022) "FeeToken → Token-2022 on Solana"
  match planForTarget evm fee with
  | .ok _ => throw (IO.userError "EVM must reject transfer_fee")
  | .error e =>
      require (e.contains "transfer_fee") "EVM reject names the feature"

  IO.println s!"token-feature-matrix: ok ({rows.size} rows · evm·solana·near honesty)"
