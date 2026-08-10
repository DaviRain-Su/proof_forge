/-
  TargetRegistryV1 product membership + BuildIdentity layout/deletion suite
  (D3 repair B). Not formal TASK-D3-02/03.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.BuildIdentityV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.DescriptorDataV1

namespace Tests.Materialization.TargetRegistryV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.BuildIdentityV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.DescriptorDataV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def expectErrorCode (result : CompileResult α) (code : String) (message : String) :
    IO Unit :=
  match result with
  | .error error =>
      expect (error.code == code) s!"{message}: got {error.code}: {error.message}"
  | .ok _ => throw <| IO.userError s!"{message}: expected error {code}"

private def digestBytesEq (a b : Digest) : Bool :=
  a.algorithm == b.algorithm && a.bytes == b.bytes

private def testSoleMembershipSource : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  let regs := TargetRegistryV1.registrationsOf registry
  expect (regs.size == 12) "12 registrations"
  let impl := implementedRegistrationsV1 registry
  let design := designOnlyRegistrationsV1 registry
  expect (impl.size == 9) "9 implemented"
  expect (design.size == 3) "3 design-only"
  let expectedIds :=
    #["aleo", "cosmwasm", "evm", "icp", "near", "noir", "openvm", "psy", "quint", "solana", "soroban", "ton"]
  expect (regs.map (·.targetId.toString) == expectedIds) "canonical TargetId order"
  -- Product selection binds the same frozen seed.
  for reg in impl do
    let sel ← liftResult <| resolveBuildSelectionV1 reg.targetId none
    expect (sel.kind == reg.kind) s!"selection kind join {reg.targetId}"
    match reg.defaultProfile with
    | some defP => expect (sel.codegenProfile == defP) s!"selection default {reg.targetId}"
    | none => throw <| IO.userError "impl without default"
  for reg in design do
    expectErrorCode (resolveBuildSelectionV1 reg.targetId none)
      "PF-TARGET-NOT-IMPLEMENTED" s!"design-only {reg.targetId}"
  match findRegistrationV1 registry TargetId.psy with
  | some psyReg =>
      expect (psyReg.profiles == #[CodegenProfileId.psyDpnV1])
        "Psy has exactly one DPN profile"
      expect (psyReg.defaultProfile == some CodegenProfileId.psyDpnV1)
        "Psy DPN profile is the default"
      let psyDefault ← liftResult <| resolveBuildSelectionV1 TargetId.psy none
      expect (psyDefault.codegenProfile == CodegenProfileId.psyDpnV1)
        "Psy omitted profile resolves to DPN"
  | none => throw <| IO.userError "missing Psy registration"

private def testClosedAxesWires : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  let expectAxes (tid : TargetId) (host commit state call proof settle : String) : IO Unit := do
    match findRegistrationV1 registry tid with
    | none => throw <| IO.userError s!"missing {tid}"
    | some reg =>
        expect (reg.semantics.executionHost.toWire == host) s!"{tid} host"
        expect (reg.semantics.commitModel.toWire == commit) s!"{tid} commit"
        expect (reg.semantics.stateBinding.toWire == state) s!"{tid} state"
        expect (reg.semantics.callModel.toWire == call) s!"{tid} call"
        expect (reg.semantics.proofModel.toWire == proof) s!"{tid} proof"
        expect (reg.semantics.settlementModel.toWire == settle) s!"{tid} settle"
  expectAxes TargetId.evm "evm" "transaction-atomic" "contract-storage"
    "synchronous-message" "no-proof" "evm-chain"
  expectAxes TargetId.solana "svm" "instruction-atomic" "explicit-accounts"
    "synchronous-cpi" "no-proof" "solana-chain"
  expectAxes TargetId.near "near-wasm" "receipt-local" "contract-key-value"
    "promise-dag" "no-proof" "near-chain"
  expectAxes TargetId.noir "noir-circuit" "relation-external" "external-public-pre-post"
    "no-native-call" "external-circuit" "external-verifier"
  expectAxes TargetId.cosmwasm "cosmwasm" "transaction-savepoints" "contract-key-value"
    "cosmos-submessage-reply" "no-proof" "cosmos-chain"
  expectAxes TargetId.soroban "soroban-wasm" "transaction-atomic" "ttl-scoped-storage"
    "synchronous-auth-tree" "no-proof" "stellar-chain"
  expectAxes TargetId.icp "icp-canister" "await-segmented" "canister-heap-stable"
    "asynchronous-actor" "no-proof" "icp-subnet"
  expectAxes TargetId.openvm "openvm-guest" "guest-external" "guest-memory-io"
    "guest-internal" "zkvm-execution" "external-verifier"
  expectAxes TargetId.aleo "aleo-vm" "proof-final-dual" "records-mappings"
    "program-proof-final" "application-chain-proof" "aleo-chain"
  expectAxes TargetId.psy "psy-dpn" "recursive-network" "user-partitioned"
    "recursive-proof-pipeline" "recursive-aggregation" "psy-network"
  expectAxes TargetId.quint "quint-model" "relation-external" "external-public-pre-post"
    "no-native-call" "no-proof" "no-settlement"
  -- Closed enum constructors are the only construction path (no String parse API).
  expect (ExecutionHostV1.evm.toWire == "evm") "ExecutionHostV1.evm wire"
  expect (ProofModelV1.noProof.toWire == "no-proof") "ProofModelV1.noProof wire"
  expect (SettlementModelV1.evmChain.toWire == "evm-chain") "SettlementModelV1.evmChain wire"

private def testDescriptorAxesSoleAuthority : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  for reg in TargetRegistryV1.registrationsOf registry do
    match ProofForgeV2.Targets.DescriptorDataV1.descriptorForKind? reg.kind with
    | some descriptor =>
        expect reg.implemented s!"descriptor only for implemented target {reg.targetId}"
        let _ ← liftResult (validateDescriptorAxesJoinV1 reg descriptor)
        expect (descriptor.targetId == reg.semantics.targetId)
          s!"{reg.targetId} descriptor target joins registry semantics"
        expect (descriptor.executionHost == reg.semantics.executionHost)
          s!"{reg.targetId} executionHost joins registry"
        expect (descriptor.commitModel == reg.semantics.commitModel)
          s!"{reg.targetId} commitModel joins registry"
        expect (descriptor.stateBinding == reg.semantics.stateBinding)
          s!"{reg.targetId} stateBinding joins registry"
        expect (descriptor.callModel == reg.semantics.callModel)
          s!"{reg.targetId} callModel joins registry"
        expect (descriptor.proofModel == reg.semantics.proofModel)
          s!"{reg.targetId} proofModel joins registry"
        expect (descriptor.settlementModel == reg.semantics.settlementModel)
          s!"{reg.targetId} settlementModel joins registry"
    | none =>
        expect (!reg.implemented)
          s!"implemented target {reg.targetId} must have descriptor"
  let evmReg ← match findRegistrationV1 registry TargetId.evm with
    | some reg => pure reg
    | none => throw <| IO.userError "missing EVM registration"
  let base := ProofForgeV2.Targets.DescriptorDataV1.evm
  let mutations : Array (String × TargetDescriptor) := #[
    ("executionHost", { base with executionHost := .nearWasm }),
    ("commitModel", { base with commitModel := .receiptLocal }),
    ("stateBinding", { base with stateBinding := .contractKeyValue }),
    ("callModel", { base with callModel := .promiseDag }),
    ("proofModel", { base with proofModel := .externalCircuit }),
    ("settlementModel", { base with settlementModel := .nearChain })
  ]
  for (axis, descriptor) in mutations do
    expectErrorCode (validateDescriptorAxesJoinV1 evmReg descriptor)
      "PF-REGISTRY-INVALID" s!"descriptor {axis} drift"

private def testValidationAndLookup : IO Unit := do
  expectErrorCode (createTargetRegistryV1 #[]) "PF-REGISTRY-INVALID" "empty"
  let rows := initialRegistrationRowsV1
  match rows[0]? with
  | some first =>
      expectErrorCode (createTargetRegistryV1 (rows.push first))
        "PF-REGISTRY-DUPLICATE" "duplicate target"
  | none => throw <| IO.userError "empty rows"
  let registry ← liftResult initialTargetRegistryV1Result
  match findRegistrationV1 registry TargetId.evm with
  | some reg =>
      expect reg.implemented "evm implemented"
      expect (reg.displayName == "EVM") "displayName NFC closed"
      expect (reg.acceptanceProfileId == "phase1.evm-u64.v1") "acceptance id"
  | none => throw <| IO.userError "missing evm"
  let insp ← liftResult (inspectTargetV1 registry TargetId.evm)
  expect insp.implemented "inspect implemented"
  expect (insp.profiles ==
      #[CodegenProfileId.evmYulSolc0834CancunV1, CodegenProfileId.evmYulSolc0834V1])
    "inspect profiles (cancun < v1; default v1 hashed)"
  expect (insp.defaultProfile == some CodegenProfileId.evmYulSolc0834V1)
    "inspect default profile is v1"
  let aleoInsp ← liftResult (inspectTargetV1 registry TargetId.aleo)
  expect (aleoInsp.profiles == #[CodegenProfileId.aleoInstructionsV1])
    "inspect aleo exposes only the direct Instructions profile"
  expect (aleoInsp.defaultProfile == some CodegenProfileId.aleoInstructionsV1)
    "inspect aleo defaults to direct Instructions"
  -- Inspection-only engineering digest is deterministic and non-product.
  let dig1 ← match findRegistrationV1 registry TargetId.evm with
    | none => throw <| IO.userError "missing evm for dig"
    | some reg =>
        match engineeringSemanticsDigestV1 reg.semantics with
        | .ok d => pure d
        | .error e => throw <| IO.userError e
  expect (digestBytesEq insp.engineeringSemanticsDigest dig1)
    "inspect engineering digest join"
  let dig2 ← match findRegistrationV1 registry TargetId.near with
    | none => throw <| IO.userError "missing near for dig"
    | some reg =>
        match engineeringSemanticsDigestV1 reg.semantics with
        | .ok d => pure d
        | .error e => throw <| IO.userError e
  expect (!digestBytesEq dig1 dig2) "engineering digests non-alias across targets"

private def testDefaultProfileFailClosed : IO Unit := do
  let base := {
    targetId := TargetId.evm
    kind := TargetKind.evm
    implemented := true
    displayName := "EVM"
    acceptanceProfileId := "phase1.evm-u64.v1"
    maturityLabel := "runtime-validated-alpha"
    semantics := {
      targetId := TargetId.evm
      executionHost := .evm
      commitModel := .transactionAtomic
      stateBinding := .contractStorage
      callModel := .synchronousMessage
      proofModel := .noProof
      settlementModel := .evmChain
    }
    profiles := #[CodegenProfileId.evmYulSolc0834V1]
    defaultProfile := none
  }
  expectErrorCode (createTargetRegistryV1 #[base]) "PF-REGISTRY-INVALID"
    "implemented missing default"
  let foreign := { base with
    defaultProfile := some CodegenProfileId.nearWasmRawU64V1 }
  expectErrorCode (createTargetRegistryV1 #[foreign]) "PF-REGISTRY-INVALID"
    "foreign default"

private def testNoFormalRootDigestExposure : IO Unit := do
  -- Type surface: TargetRegistryV1 has registrations only (no digest field).
  let registry ← liftResult initialTargetRegistryV1Result
  let _ := TargetRegistryV1.registrationsOf registry
  -- Domain constants: engineering semantics only; no formal registry root string in module API.
  expect (engineeringSemanticsDigestDomainV1 ==
      "proof-forge.target-semantics.engineering.v1")
    "engineering domain"
  match validateProfileIdValue engineeringSemanticsDigestDomainV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError e

private def testBuildIdentityLayoutNoMint : IO Unit := do
  let expectedNames := #["codegenProfileDigest", "codegenProfileId", "targetId",
    "targetSemanticsDigest", "targetSemanticsVersion"]
  expect (BuildIdentityV1.wireFieldNamesV1 == expectedNames)
    "exact five BuildIdentity wire fields"
  expect (BuildIdentityV1.wireFieldCountV1 == BuildIdentityV1.wireFieldNamesV1.size)
    "wire field count derived from renderer key table"
  -- Type ascriptions prove the complete inspection/equality/render surface
  -- exists without adding any way to construct a BuildIdentity value.
  let _targetIdOf : BuildIdentityV1 → TargetId := BuildIdentityV1.targetIdOf
  let _semVerOf : BuildIdentityV1 → SemVer := BuildIdentityV1.targetSemanticsVersionOf
  let _semDigestOf : BuildIdentityV1 → Digest := BuildIdentityV1.targetSemanticsDigestOf
  let _profileIdOf : BuildIdentityV1 → CodegenProfileId := BuildIdentityV1.codegenProfileIdOf
  let _profileDigestOf : BuildIdentityV1 → Digest := BuildIdentityV1.codegenProfileDigestOf
  let _beq : BuildIdentityV1 → BuildIdentityV1 → Bool := BuildIdentityV1.beq
  let _beqInstance : BEq BuildIdentityV1 := inferInstance
  let _render : BuildIdentityV1 → Except String String := BuildIdentityV1.renderJcsV1
  let _ := _targetIdOf
  let _ := _semVerOf
  let _ := _semDigestOf
  let _ := _profileIdOf
  let _ := _profileDigestOf
  let _ := _beq
  let _ := _beqInstance
  let _ := _render
  pure ()

/-- Durable deletion / reflection gate over ProofForgeV2 sources. -/
private def testDeletionGate : IO Unit := do
  let patterns : Array (String × String) := #[
    ("StaticBuildRegistrationV1", "deleted static registration type"),
    ("StaticBuildSelectionIndexV1", "deleted static selection index"),
    ("initialStaticBuildSelectionIndexV1Result", "deleted independent selection seed Result"),
    ("createStaticBuildSelectionIndexV1", "deleted independent selection validator"),
    ("registrationInIndex\\?", "deleted index-only lookup alias"),
    ("implementedRegistrationsInIndex", "deleted index filter alias"),
    ("designOnlyRegistrationsInIndex", "deleted index filter alias"),
    ("listTargetLinesInIndex", "deleted index list body"),
    ("registryDigest", "no formal/product registryDigest API"),
    ("proof-forge\\.target-registry\\.v1", "no formal registry root domain"),
    ("mintBuildIdentityV1", "no BuildIdentity mint"),
    ("mintBuildIdentityFromInitialV1", "no BuildIdentity initial mint")
  ]
  for (pat, label) in patterns do
    let out ← IO.Process.output {
      cmd := "rg"
      args := #["-n", "--glob", "*.lean", "-e", pat, "ProofForgeV2"]
    }
    -- rg exits 0 when matches exist; 1 when none (success for forbid gate).
    if out.exitCode == 0 then
      throw <| IO.userError s!"{label}: residual matches:\n{out.stdout}"
    else if out.exitCode != 1 then
      throw <| IO.userError s!"{label}: rg failed ({out.exitCode}): {out.stderr}"
  -- Sole product mint of ResolvedBuildSelectionV1 is resolveBuildSelectionV1.
  let mintOut ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "ResolvedBuildSelectionV1\\.mk", "ProofForgeV2"]
  }
  unless mintOut.exitCode == 0 do
    throw <| IO.userError
      s!"expected sole ResolvedBuildSelectionV1.mk, rg exit {mintOut.exitCode}: {mintOut.stderr}"
  let lines := (mintOut.stdout.splitOn "\n").filter (fun s => !s.isEmpty)
  match lines with
  | [line] =>
      unless line.startsWith "ProofForgeV2/Targets/BuildSelectionV1.lean:" do
        throw <| IO.userError
          s!"ResolvedBuildSelectionV1.mk only allowed in BuildSelectionV1, got: {line}"
  | _ =>
      throw <| IO.userError
        s!"exactly one ResolvedBuildSelectionV1.mk expected, got {lines.length}:\n{mintOut.stdout}"
  -- Seed axes are closed enums, not raw String fields.
  let rawAxis ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "-e", "executionHost\\s*:\\s*String",
      "ProofForgeV2/Targets/TargetRegistryV1.lean"]
  }
  if rawAxis.exitCode == 0 then
    throw <| IO.userError s!"raw String executionHost residual:\n{rawAxis.stdout}"
  else if rawAxis.exitCode != 1 then
    throw <| IO.userError s!"raw-axis rg failed: {rawAxis.stderr}"
  -- Independent seed array name must not reappear as a public def.
  let initRegs ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "^def initialRegistrations\\b", "ProofForgeV2"]
  }
  if initRegs.exitCode == 0 then
    throw <| IO.userError s!"deleted initialRegistrations def residual:\n{initRegs.stdout}"
  else if initRegs.exitCode != 1 then
    throw <| IO.userError s!"initialRegistrations rg failed: {initRegs.stderr}"
  -- Protocol-owned duplicate axis types must remain physically deleted.
  let oldAxes ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "-e",
      "^inductive (ExecutionHost|CommitModel|StateBinding|CallModel|ProofModel|SettlementModel) where$",
      "ProofForgeV2/Materialization/Protocol.lean"]
  }
  if oldAxes.exitCode == 0 then
    throw <| IO.userError s!"Protocol duplicate axis types reappeared:\n{oldAxes.stdout}"
  else if oldAxes.exitCode != 1 then
    throw <| IO.userError s!"old-axis rg failed: {oldAxes.stderr}"
  -- Exact product defenses: capability resolve, artifact mint, target inspect.
  let joinCalls ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "^\\s*(Targets\\.DescriptorDataV1\\.)?validateDescriptorAxesJoinV1\\b",
      "ProofForgeV2"]
  }
  unless joinCalls.exitCode == 0 do
    throw <| IO.userError s!"missing descriptor axes join calls: {joinCalls.stderr}"
  let joinLines := (joinCalls.stdout.splitOn "\n").filter (fun s => !s.isEmpty)
  expect (joinLines.length == 3)
    s!"exactly three descriptor axes product joins expected:\n{joinCalls.stdout}"
  for path in #[
      "ProofForgeV2/Targets/EngineeringBuildV1.lean:",
      "ProofForgeV2/Materialization/MaterializedArtifactsV1.lean:",
      "ProofForgeV2/CLI/Emit.lean:"] do
    expect (joinLines.any (·.startsWith path))
      s!"missing descriptor axes join in {path}\n{joinCalls.stdout}"
  pure ()

def run : IO Unit := do
  testSoleMembershipSource
  testClosedAxesWires
  testDescriptorAxesSoleAuthority
  testValidationAndLookup
  testDefaultProfileFailClosed
  testNoFormalRootDigestExposure
  testBuildIdentityLayoutNoMint
  testDeletionGate
  IO.println "Tests.Materialization.TargetRegistryV1: ok"

end Tests.Materialization.TargetRegistryV1
