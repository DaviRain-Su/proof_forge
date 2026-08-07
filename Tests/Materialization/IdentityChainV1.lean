/-
  M3b engineering SupportClaim + BuildIdentity identity-chain suite.

  Pins:
  * bulk claim mint over frozen support index (canonical order, determinism)
  * claimDigest sensitivity to support-row and registry-root mutations
  * product-path BuildIdentity mint (compile Counter → resolve → materialize)
  * identity field binding + digest determinism / profile sensitivity
  * sole-mint / private-ctor surface (no formal BuildIdentity mint; no
    registryDigest identifier)

  **Not** formal TASK-D3-02/03 / formal SupportClaim / formal BuildIdentity /
  OutputSetV1 / on-disk manifest identity.
-/
import ProofForgeV2
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.RequirementsV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.Evm.PlanSchemaV1
import ProofForgeV2.Targets.Solana.PlanSchemaV1
import ProofForgeV2.Targets.Solana.MaterializationV1
import ProofForgeV2.Targets.Near.PlanSchemaV1
import ProofForgeV2.Targets.Noir.PlanSchemaV1
import ProofForgeV2.Targets.CosmWasm.PlanSchemaV1
import ProofForgeV2.Targets.Quint.PlanSchemaV1
import ProofForgeV2.Targets.Ton.PlanSchemaV1
import ProofForgeV2.Targets.Aleo.PlanSchemaV1
import ProofForgeV2.Targets.RegistryRootV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.TargetRegistryV1
import Tests.Language.ParserSession

namespace Tests.Materialization.IdentityChainV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.RegistryRootV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Targets.TargetRegistryV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def liftExcept (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def digestWire (d : Digest) : IO String :=
  liftExcept "renderDigest" (renderDigest d)

private def expectDigestDiff (label : String) (base alt : Digest) : IO Unit :=
  expect (!(base.bytes == alt.bytes)) s!"{label}: digest must change"

private def mintProductClaims : IO (Array EngineeringSupportClaimV1) := do
  let registry ← liftResult "registry" initialTargetRegistryV1Result
  let index ← liftResult "support index" initialStaticRequirementSupportIndexV1Result
  liftExcept "mint claims" (mintEngineeringSupportClaimsV1 registry index)

private def testDomains : IO Unit := do
  expect (engineeringSupportClaimDomainV1 == "pf.support-claim.engineering.v1")
    "support claim domain"
  expect (engineeringBuildIdentityDomainV1 == "pf.build-identity.engineering.v1")
    "build identity domain"
  expect (engineeringSupportClaimDomainV1.endsWith ".engineering.v1")
    "support claim engineering suffix"
  expect (engineeringBuildIdentityDomainV1.endsWith ".engineering.v1")
    "build identity engineering suffix"
  match validateProfileIdValue engineeringSupportClaimDomainV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"support claim domain grammar: {e}"
  match validateProfileIdValue engineeringBuildIdentityDomainV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"build identity domain grammar: {e}"

private def testClaimMintCanonicalOrder : IO Unit := do
  let claims ← mintProductClaims
  let index ← liftResult "support index" initialStaticRequirementSupportIndexV1Result
  let rows : Array StaticRequirementSupportRowV1 :=
    StaticRequirementSupportIndexV1.toArray index
  expect (claims.size == rows.size)
    s!"one claim per support row: got {claims.size} want {rows.size}"
  -- Aleo dual + Psy dual + ADR-0032 U1 sole Solana cpi-elf → 12 support rows
  -- (aleo×2/cosmwasm/evm×2/near/noir/psy×2/quint/solana×1/ton).
  expect (claims.size == 12)
    s!"implemented profile count is 12 (aleo×2/cosmwasm/evm×2/near/noir/psy×2/quint/solana×1/ton), got {claims.size}"
  let root ← liftExcept "root" (engineeringRegistryRootDigestV1
    (← liftResult "registry" initialTargetRegistryV1Result))
  let mut i : Nat := 0
  while i < claims.size do
    match claims[i]?, rows[i]? with
    | some claim, some row =>
        expect (EngineeringSupportClaimV1.targetIdOf claim == row.targetId)
          s!"claim {i} targetId"
        expect (EngineeringSupportClaimV1.codegenProfileOf claim == row.codegenProfile)
          s!"claim {i} profile"
        expect (EngineeringSupportClaimV1.supportedOf claim == row.supported)
          s!"claim {i} supported row"
        expect (EngineeringSupportClaimV1.supportedIdsOf claim == row.supported.map (·.id))
          s!"claim {i} supported ids"
        expect (EngineeringSupportClaimV1.engineeringRegistryRootDigestOf claim == root)
          s!"claim {i} registry root anchor"
        let recomputed ← liftExcept "recompute claim digest"
          (engineeringSupportClaimDigestV1
            row.targetId row.codegenProfile (row.supported.map (·.id)) root)
        expect (EngineeringSupportClaimV1.claimDigestOf claim == recomputed)
          s!"claim {i} digest recomputes from preimage"
    | _, _ => throw <| IO.userError s!"claim/row index out of range at {i}"
    i := i + 1
  -- Canonical (targetId, profile) ascending order.
  let keys := claims.map (fun c =>
    s!"{EngineeringSupportClaimV1.targetIdOf c}\t{EngineeringSupportClaimV1.codegenProfileOf c}")
  let mut j : Nat := 0
  while j + 1 < keys.size do
    match keys[j]?, keys[j + 1]? with
    | some a, some b =>
        expect (a < b) s!"claim order strictly ascending at {j}: {a} !< {b}"
    | _, _ => throw <| IO.userError s!"key index out of range at {j}"
    j := j + 1

private def testClaimDeterminism : IO Unit := do
  let a ← mintProductClaims
  let b ← mintProductClaims
  expect (a.size == b.size) "claim count stable"
  let mut i : Nat := 0
  while i < a.size do
    match a[i]?, b[i]? with
    | some ca, some cb =>
        expect (EngineeringSupportClaimV1.beq ca cb)
          s!"claim {i} deterministic mint"
    | _, _ => throw <| IO.userError s!"claim index out of range at {i}"
    i := i + 1

private def testClaimDigestSupportRowSensitivity : IO Unit := do
  let registry ← liftResult "registry" initialTargetRegistryV1Result
  let index ← liftResult "support index" initialStaticRequirementSupportIndexV1Result
  let baseClaims ← liftExcept "base claims"
    (mintEngineeringSupportClaimsV1 registry index)
  let baseEvm ← match
      findEngineeringSupportClaimV1 baseClaims TargetId.evm CodegenProfileId.evmYulSolc0834V1 with
    | some c => pure c
    | none => throw <| IO.userError "missing base evm claim"
  let baseDigest := EngineeringSupportClaimV1.claimDigestOf baseEvm
  -- Drop one supported id from the EVM row (still a legal S2 subset in wire order).
  let rows := StaticRequirementSupportIndexV1.toArray index
  let mut altRows : Array StaticRequirementSupportRowV1 := #[]
  for row in rows do
    if row.targetId == TargetId.evm &&
        row.codegenProfile == CodegenProfileId.evmYulSolc0834V1 then
      expect (row.supported.size ≥ 2) "evm support row must have ≥2 requirements to drop one"
      let shrunk := row.supported.pop
      altRows := altRows.push { row with supported := shrunk }
    else
      altRows := altRows.push row
  let altIndex ← liftResult "alt index" (createStaticRequirementSupportIndexV1 altRows)
  let altClaims ← liftExcept "alt claims"
    (mintEngineeringSupportClaimsV1 registry altIndex)
  let altEvm ← match
      findEngineeringSupportClaimV1 altClaims TargetId.evm CodegenProfileId.evmYulSolc0834V1 with
    | some c => pure c
    | none => throw <| IO.userError "missing alt evm claim"
  expectDigestDiff "support-row shrink" baseDigest
    (EngineeringSupportClaimV1.claimDigestOf altEvm)
  -- Other targets' digests stay stable when only EVM row mutates.
  let nearProfile := CodegenProfileId.nearWasmRawU64V1
  let noirProfile := CodegenProfileId.noirSourceU64RelationsV1
  for pair in #[(TargetId.near, nearProfile), (TargetId.noir, noirProfile)] do
    let tid := pair.1
    let profile := pair.2
    let baseC ← match findEngineeringSupportClaimV1 baseClaims tid profile with
      | some c => pure c
      | none => throw <| IO.userError s!"missing base {tid}"
    let altC ← match findEngineeringSupportClaimV1 altClaims tid profile with
      | some c => pure c
      | none => throw <| IO.userError s!"missing alt {tid}"
    expect (EngineeringSupportClaimV1.claimDigestOf baseC ==
        EngineeringSupportClaimV1.claimDigestOf altC)
      s!"{tid} claim digest stable when only EVM row mutates"

private def testClaimDigestRegistryRootSensitivity : IO Unit := do
  let registry ← liftResult "registry" initialTargetRegistryV1Result
  let index ← liftResult "support index" initialStaticRequirementSupportIndexV1Result
  let baseClaims ← liftExcept "base claims"
    (mintEngineeringSupportClaimsV1 registry index)
  let baseRoot ← liftExcept "base root" (engineeringRegistryRootDigestV1 registry)
  -- Flip EVM execution host axis → different engineering registry root.
  let regs := TargetRegistryV1.registrationsOf registry
  let mut flipped : Array TargetRegistrationDataV1 := #[]
  for reg in regs do
    if reg.targetId == TargetId.evm then
      let s0 := reg.semantics
      let host' : ExecutionHostV1 :=
        if s0.executionHost == .evm then .svm else .evm
      flipped := flipped.push { reg with semantics := { s0 with executionHost := host' } }
    else
      flipped := flipped.push reg
  let altRegistry ← liftResult "alt registry" (createTargetRegistryV1 flipped)
  let altRoot ← liftExcept "alt root" (engineeringRegistryRootDigestV1 altRegistry)
  expectDigestDiff "registry root" baseRoot altRoot
  let altClaims ← liftExcept "alt claims"
    (mintEngineeringSupportClaimsV1 altRegistry index)
  expect (altClaims.size == baseClaims.size) "claim count under alt registry"
  let mut i : Nat := 0
  while i < baseClaims.size do
    match baseClaims[i]?, altClaims[i]? with
    | some baseC, some altC =>
        expectDigestDiff s!"claim {i} under registry tamper"
          (EngineeringSupportClaimV1.claimDigestOf baseC)
          (EngineeringSupportClaimV1.claimDigestOf altC)
        expect (EngineeringSupportClaimV1.engineeringRegistryRootDigestOf altC == altRoot)
          s!"claim {i} anchors alt root"
    | _, _ => throw <| IO.userError s!"claim index out of range at {i}"
    i := i + 1

private unsafe def compileCounter : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<identity-chain-counter>"
    Examples.counterModuleNameV1 none)
  liftResult "compile Counter" (Compiler.compileValidatedSourceV1 source)

private unsafe def materializeTarget
    (compiled : CompiledSemanticV1) (tid : TargetId)
    (profile? : Option CodegenProfileId := none) :
    IO (Targets.ResolvedEngineeringBuildV1 × MaterializedArtifactsV1) := do
  let selection ← liftResult s!"select {tid}" (resolveBuildSelectionV1 tid profile?)
  let capability ← liftResult s!"resolve {tid}"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← liftResult s!"materialize {tid}"
    (Targets.materializeResult capability)
  pure (capability, artifacts)

private unsafe def testBuildIdentityProductPath : IO Unit := do
  let compiled ← compileCounter
  let artifactName := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  let root ← liftExcept "root" (engineeringRegistryRootDigestV1
    (← liftResult "registry" initialTargetRegistryV1Result))
  -- All nine materializing targets: eight real Plan schema digests (Registry
  -- `planDigestForCapabilityV1`, including Aleo ALEO-I1) + Psy engineering-
  -- absent plan slot.
  for tid in #[
      TargetId.evm, TargetId.solana, TargetId.near, TargetId.noir,
      TargetId.cosmwasm, TargetId.quint, TargetId.ton, TargetId.aleo, TargetId.psy] do
    let (cap, artifacts) ← materializeTarget compiled tid
    let claim := Targets.ResolvedEngineeringBuildV1.supportClaimOf cap
    expect (EngineeringSupportClaimV1.targetIdOf claim == tid)
      s!"{tid} capability claim target"
    expect (EngineeringSupportClaimV1.codegenProfileOf claim ==
        Targets.ResolvedEngineeringBuildV1.codegenProfileOf cap)
      s!"{tid} capability claim profile"
    let identity := MaterializedArtifactsV1.buildIdentityOf artifacts
    expect (EngineeringBuildIdentityV1.targetIdOf identity == tid)
      s!"{tid} identity target"
    expect (EngineeringBuildIdentityV1.codegenProfileOf identity ==
        MaterializedArtifactsV1.codegenProfileIdOf artifacts)
      s!"{tid} identity profile"
    expect (EngineeringBuildIdentityV1.artifactNameOf identity == artifactName)
      s!"{tid} identity artifact name"
    expect (EngineeringBuildIdentityV1.sourceDigestOf identity == sourceDigest)
      s!"{tid} identity source digest"
    expect (EngineeringBuildIdentityV1.semanticDigestOf identity == semanticDigest)
      s!"{tid} identity semantic digest"
    expect (EngineeringBuildIdentityV1.engineeringRegistryRootDigestOf identity == root)
      s!"{tid} identity registry root"
    expect (EngineeringBuildIdentityV1.supportClaimDigestOf identity ==
        EngineeringSupportClaimV1.claimDigestOf claim)
      s!"{tid} identity support claim digest"
    -- Recompute identity digest from fields.
    let recomputed ← liftExcept s!"recompute identity {tid}"
      (engineeringBuildIdentityDigestV1
        (EngineeringBuildIdentityV1.targetIdOf identity)
        (EngineeringBuildIdentityV1.codegenProfileOf identity)
        (EngineeringBuildIdentityV1.artifactNameOf identity)
        (EngineeringBuildIdentityV1.sourceDigestOf identity)
        (EngineeringBuildIdentityV1.semanticDigestOf identity)
        (EngineeringBuildIdentityV1.engineeringRegistryRootDigestOf identity)
        (EngineeringBuildIdentityV1.supportClaimDigestOf identity)
        (EngineeringBuildIdentityV1.planDigestOf identity))
    expect (EngineeringBuildIdentityV1.identityDigestOf identity == recomputed)
      s!"{tid} identity digest recomputes"
    -- Registry planDigestForCapabilityV1: EVM/Solana/NEAR/Noir/CosmWasm/Quint/
    -- TON/Aleo recompute target Plan schema digests; Psy binds engineering-
    -- absent plan slot (no Plan schema digest in identity).
    let selection ← liftResult s!"select {tid}"
      (resolveBuildSelectionV1 tid none)
    let cap ← liftResult s!"resolve {tid}"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    if tid == TargetId.evm then
      let plan ← liftResult s!"plan {tid}" (Targets.Evm.planFromCapability cap)
      let expected ← liftExcept s!"evm plan digest {tid}"
        (Targets.Evm.engineeringEvmPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringEvmPlanDigestV1"
    else if tid == TargetId.solana then
      -- ADR-0032 U1: sole default is solana-sbpf-cpi-elf-v1 → .cpi tagged sum.
      -- Digest authority is materialization plan digest over the tagged sum.
      let planSum ← liftResult s!"plan {tid}" (Targets.Solana.planFromCapability cap)
      match planSum with
      | Targets.Solana.SolanaPlanFromCapabilityV1.cpi _ => pure ()
      | Targets.Solana.SolanaPlanFromCapabilityV1.legacy _ =>
          throw <| IO.userError
            s!"{tid} default profile planFromCapability must be .cpi, got .legacy"
      let expected ← liftExcept s!"solana plan digest {tid}"
        (Targets.Solana.engineeringSolanaMaterializationPlanDigestV1 planSum)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringSolanaMaterializationPlanDigestV1"
    else if tid == TargetId.near then
      let plan ← liftResult s!"plan {tid}" (Targets.Near.planFromCapability cap)
      let expected ← liftExcept s!"near plan digest {tid}"
        (Targets.Near.engineeringNearPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringNearPlanDigestV1"
    else if tid == TargetId.noir then
      let plan ← liftResult s!"plan {tid}" (Targets.Noir.planFromCapability cap)
      let expected ← liftExcept s!"noir plan digest {tid}"
        (Targets.Noir.engineeringNoirPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringNoirPlanDigestV1"
    else if tid == TargetId.cosmwasm then
      let plan ← liftResult s!"plan {tid}" (Targets.CosmWasm.planFromCapability cap)
      let expected ← liftExcept s!"cosmwasm plan digest {tid}"
        (Targets.CosmWasm.engineeringCosmWasmPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringCosmWasmPlanDigestV1"
    else if tid == TargetId.quint then
      let plan ← liftResult s!"plan {tid}" (Targets.Quint.planFromCapability cap)
      let expected ← liftExcept s!"quint plan digest {tid}"
        (Targets.Quint.engineeringQuintPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringQuintPlanDigestV1"
    else if tid == TargetId.ton then
      let plan ← liftResult s!"plan {tid}" (Targets.Ton.planFromCapability cap)
      let expected ← liftExcept s!"ton plan digest {tid}"
        (Targets.Ton.engineeringTonPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringTonPlanDigestV1"
    else if tid == TargetId.aleo then
      let plan ← liftResult s!"plan {tid}" (Targets.Aleo.planFromCapability cap)
      let expected ← liftExcept s!"aleo plan digest {tid}"
        (Targets.Aleo.engineeringAleoPlanDigestV1 plan)
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest matches engineeringAleoPlanDigestV1"
    else if tid == TargetId.psy then
      let expected ← liftExcept s!"absent plan {tid}"
        (engineeringAbsentPlanDigestV1 tid
          (EngineeringBuildIdentityV1.codegenProfileOf identity))
      expect (EngineeringBuildIdentityV1.planDigestOf identity == expected)
        s!"{tid} planDigest is engineering-absent slot"
    else
      throw <| IO.userError s!"unexpected target in identity planDigest pin: {tid}"
    -- Determinism across two full product paths.
    let (_, artifacts2) ← materializeTarget compiled tid
    expect (MaterializedArtifactsV1.beq artifacts artifacts2)
      s!"{tid} materialize+identity deterministic"
    expect (EngineeringBuildIdentityV1.beq identity
        (MaterializedArtifactsV1.buildIdentityOf artifacts2))
      s!"{tid} identity deterministic"

private unsafe def testBuildIdentityProfileSensitivity : IO Unit := do
  -- ADR-0032 U1: Solana sole rail only — profile sensitivity vs EVM default.
  let compiled ← compileCounter
  let (_, solArts) ← materializeTarget compiled TargetId.solana none
  let (_, evmArts) ← materializeTarget compiled TargetId.evm none
  let solId := MaterializedArtifactsV1.buildIdentityOf solArts
  let evmId := MaterializedArtifactsV1.buildIdentityOf evmArts
  expect (EngineeringBuildIdentityV1.codegenProfileOf solId ==
      CodegenProfileId.solanaSbpfCpiElfV1)
    "solana sole rail profile bound"
  expect (EngineeringBuildIdentityV1.codegenProfileOf evmId ==
      CodegenProfileId.evmYulSolc0834V1)
    "evm default profile bound"
  expectDigestDiff "cross-target identityDigest"
    (EngineeringBuildIdentityV1.identityDigestOf solId)
    (EngineeringBuildIdentityV1.identityDigestOf evmId)
  expectDigestDiff "cross-target supportClaimDigest"
    (EngineeringBuildIdentityV1.supportClaimDigestOf solId)
    (EngineeringBuildIdentityV1.supportClaimDigestOf evmId)
  -- Aleo dual profiles: same Plan/planDigest, distinct supportClaim/BuildIdentity.
  let (srcCap, srcArts) ← materializeTarget compiled TargetId.aleo none
  let (cmpCap, cmpArts) ← materializeTarget compiled TargetId.aleo
    (some CodegenProfileId.aleoLeoU64CompileV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf srcCap ==
      CodegenProfileId.aleoLeoU64V1)
    "aleo default capability binds source profile"
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf cmpCap ==
      CodegenProfileId.aleoLeoU64CompileV1)
    "aleo compile capability binds compile profile"
  let srcId := MaterializedArtifactsV1.buildIdentityOf srcArts
  let cmpId := MaterializedArtifactsV1.buildIdentityOf cmpArts
  expect (EngineeringBuildIdentityV1.planDigestOf srcId ==
      EngineeringBuildIdentityV1.planDigestOf cmpId)
    "aleo dual profiles share planDigest"
  expectDigestDiff "aleo dual supportClaimDigest"
    (EngineeringBuildIdentityV1.supportClaimDigestOf srcId)
    (EngineeringBuildIdentityV1.supportClaimDigestOf cmpId)
  expectDigestDiff "aleo dual identityDigest"
    (EngineeringBuildIdentityV1.identityDigestOf srcId)
    (EngineeringBuildIdentityV1.identityDigestOf cmpId)
  expect (EngineeringBuildIdentityV1.codegenProfileOf srcId ==
      CodegenProfileId.aleoLeoU64V1)
    "aleo source identity profile"
  expect (EngineeringBuildIdentityV1.codegenProfileOf cmpId ==
      CodegenProfileId.aleoLeoU64CompileV1)
    "aleo compile identity profile"

/-- Minimal S1 Accumulator source text (distinct name/body from Counter). -/
private def accumulatorSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

private unsafe def testBuildIdentitySourceSensitivity : IO Unit := do
  let counter ← compileCounter
  let session ← Tests.Language.ParserSession.shared
  -- Accumulator is a different ProgramV1 product source with a different name/hash.
  let accSource ← liftResult "load Accumulator" (← session.selectProgramV1
    accumulatorSourceTextV1 "<identity-chain-accumulator>"
    "Examples.Accumulator" none)
  let accumulator ← liftResult "compile Accumulator"
    (Compiler.compileValidatedSourceV1 accSource)
  expect (!(CompiledSemanticV1.sourceDigestOf counter ==
      CompiledSemanticV1.sourceDigestOf accumulator))
    "Counter and Accumulator source digests differ"
  let (_, cArts) ← materializeTarget counter TargetId.evm
  let (_, aArts) ← materializeTarget accumulator TargetId.evm
  let cId := MaterializedArtifactsV1.buildIdentityOf cArts
  let aId := MaterializedArtifactsV1.buildIdentityOf aArts
  expectDigestDiff "source/semantic identityDigest"
    (EngineeringBuildIdentityV1.identityDigestOf cId)
    (EngineeringBuildIdentityV1.identityDigestOf aId)
  expectDigestDiff "source digest field"
    (EngineeringBuildIdentityV1.sourceDigestOf cId)
    (EngineeringBuildIdentityV1.sourceDigestOf aId)
  expect (EngineeringBuildIdentityV1.artifactNameOf cId == "Counter")
    "Counter artifact name"
  expect (EngineeringBuildIdentityV1.artifactNameOf aId == "Accumulator")
    "Accumulator artifact name"

/-- Sole-mint / forbidden-name surface (reflection via rg, matching other
    private-ctor suites). Formal BuildIdentity remains mint-less. -/
private def testSoleMintAndForbiddenNames : IO Unit := do
  -- Forbidden formal/product identifiers must not reappear under ProofForgeV2.
  let forbid : Array (String × String) := #[
    ("registryDigest", "no formal/product root-digest API name"),
    ("mintBuildIdentityV1", "no formal BuildIdentity mint"),
    ("mintBuildIdentityFromInitialV1", "no formal BuildIdentity initial mint")
  ]
  for (pat, label) in forbid do
    let out ← IO.Process.output {
      cmd := "rg"
      args := #["-n", "--glob", "*.lean", "-e", pat, "ProofForgeV2"]
    }
    if out.exitCode == 0 then
      -- Allow only comments that mention formal absence? Gate is strict: any match fails.
      throw <| IO.userError s!"{label}: residual matches:\n{out.stdout}"
    else if out.exitCode != 1 then
      throw <| IO.userError s!"{label}: rg failed ({out.exitCode}): {out.stderr}"
  -- Sole EngineeringSupportClaimV1.mk in SupportClaimV1.lean.
  let claimMk ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "EngineeringSupportClaimV1\\.mk", "ProofForgeV2"]
  }
  unless claimMk.exitCode == 0 do
    throw <| IO.userError
      s!"expected EngineeringSupportClaimV1.mk, rg exit {claimMk.exitCode}: {claimMk.stderr}"
  let claimLines := (claimMk.stdout.splitOn "\n").filter (fun s => !s.isEmpty)
  for line in claimLines do
    unless line.startsWith "ProofForgeV2/Targets/SupportClaimV1.lean:" do
      throw <| IO.userError
        s!"EngineeringSupportClaimV1.mk only allowed in SupportClaimV1.lean, got: {line}"
  -- Sole EngineeringBuildIdentityV1.mk in EngineeringBuildIdentityV1.lean.
  let idMk ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "EngineeringBuildIdentityV1\\.mk", "ProofForgeV2"]
  }
  unless idMk.exitCode == 0 do
    throw <| IO.userError
      s!"expected EngineeringBuildIdentityV1.mk, rg exit {idMk.exitCode}: {idMk.stderr}"
  let idLines := (idMk.stdout.splitOn "\n").filter (fun s => !s.isEmpty)
  for line in idLines do
    unless line.startsWith "ProofForgeV2/Targets/EngineeringBuildIdentityV1.lean:" do
      throw <| IO.userError
        s!"EngineeringBuildIdentityV1.mk only allowed in EngineeringBuildIdentityV1.lean, got: {line}"
  -- Sole mint entry points by name.
  let mintClaim ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "^def mintEngineeringSupportClaimsV1\\b", "ProofForgeV2"]
  }
  unless mintClaim.exitCode == 0 do
    throw <| IO.userError "missing mintEngineeringSupportClaimsV1"
  let mintId ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "^def mintEngineeringBuildIdentityV1\\b", "ProofForgeV2"]
  }
  unless mintId.exitCode == 0 do
    throw <| IO.userError "missing mintEngineeringBuildIdentityV1"
  -- Accessors exist (type ascriptions prove public surface without public ctors).
  let _claimTarget : EngineeringSupportClaimV1 → TargetId :=
    EngineeringSupportClaimV1.targetIdOf
  let _claimDigest : EngineeringSupportClaimV1 → Digest :=
    EngineeringSupportClaimV1.claimDigestOf
  let _idDigest : EngineeringBuildIdentityV1 → Digest :=
    EngineeringBuildIdentityV1.identityDigestOf
  let _idSupport : EngineeringBuildIdentityV1 → Digest :=
    EngineeringBuildIdentityV1.supportClaimDigestOf
  let _ := _claimTarget
  let _ := _claimDigest
  let _ := _idDigest
  let _ := _idSupport
  pure ()

unsafe def run : IO Unit := do
  testDomains
  testClaimMintCanonicalOrder
  testClaimDeterminism
  testClaimDigestSupportRowSensitivity
  testClaimDigestRegistryRootSensitivity
  testBuildIdentityProductPath
  testBuildIdentityProfileSensitivity
  testBuildIdentitySourceSensitivity
  testSoleMintAndForbiddenNames
  IO.println "Tests.Materialization.IdentityChainV1: ok"

end Tests.Materialization.IdentityChainV1
