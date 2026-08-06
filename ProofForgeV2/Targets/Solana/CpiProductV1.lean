/-
  ProofForgeV2.Targets.Solana.CpiProductV1 — #125 product CPI integration API.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Stable entry points for the materializer / Finalize lane:
  * `productPlanFromCapabilityV1` → `SolanaCpiProductPlanV1`
  * `productIrFromCapabilityV1` → `ResolvedSolanaCpiProductIRV1`
  * `productPlanDigestFromCapabilityV1` → `Digest`
  * `productBaseFilesFromCapabilityV1` → ordered `OutputFile` array

  Chain: `ResolvedEngineeringBuildV1` → private product capability → private
  product Plan → private product IR → assembly. OutputFile only via this path.

  Base file order (Finalize join):
    `{name}.cpi-plan.json`
    `{name}.cpi-ir.json`
    `{name}.idl.json`
    `{name}.s`
    `{name}.cpi-bindings.json`

  Plan JSON is active-snapshot PF-JCS. IR JSON is composite product IR
  canonical text. IDL is Plan projection. `.s` is product assembly.
  Bindings bind active profile/catalog, referenced package pins, Plan/IR digests.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Materialization.Protocol
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiIRV1
import ProofForgeV2.Targets.Solana.CpiIdlV1
import ProofForgeV2.Targets.Solana.CpiProductCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1

namespace ProofForgeV2.Targets.Solana.CpiV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
private def productFail (detail : String) : CompileResult α :=
  throw (.planInvariant .solana detail)

private def mapExcept (e : Except String α) (ctx : String) : CompileResult α :=
  match e with
  | .ok v => pure v
  | .error msg => productFail s!"{ctx}: {msg}"

private def utf8Of (bytes : ByteArray) : CompileResult String :=
  match String.fromUTF8? bytes with
  | some s => pure s
  | none => productFail "canonical bytes are not valid UTF-8"

private def encodeLowerHex (bytes : ByteArray) : String :=
  let lowerHexDigit (n : Nat) : Char :=
    if n < 10 then Char.ofNat ('0'.toNat + n)
    else Char.ofNat ('a'.toNat + n - 10)
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def renderActiveArtifactBinding : ActiveArtifactBindingV1 → String
  | .absent => "absent"
  | .runtimeNative commit => s!"runtimeNative:{commit}"
  | .loaderV3Elf elf =>
      s!"loaderV3Elf:{elf.contentSha256}:size{elf.sizeBytes}:{elf.relativePath}"

/-- Product Plan carrier from ordinary engineering capability. -/
def productPlanFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult SolanaCpiProductPlanV1 := do
  let cap ← resolveSolanaCpiProductCapabilityV1 capability
  deriveSolanaCpiPlanFromProductCapabilityV1 cap

/-- Product composite IR from ordinary engineering capability. -/
def productIrFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult ResolvedSolanaCpiProductIRV1 := do
  let plan ← productPlanFromCapabilityV1 capability
  resolveSolanaCpiProductIRV1 plan

/-- Product Plan digest (active-snapshot-bound). -/
def productPlanDigestFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult Digest := do
  let plan ← productPlanFromCapabilityV1 capability
  pure (SolanaCpiProductPlanV1.digestOf plan)

private def collectReferencedActivePackages
    (plan : ValidatedSolanaCpiPlanV1) : CompileResult (Array ActiveCalleePackageV1) := do
  let c := plan.candidate
  let mut ids : Array String := #[]
  for role in c.accountRoles do
    match role.keyPolicy with
    | .fixedProgram packageId =>
        if !(ids.any (· == packageId)) then
          ids := ids.push packageId
    | _ => pure ()
  for site in c.cpiSites do
    if !(ids.any (· == site.packageId)) then
      ids := ids.push site.packageId
    for metaSlot in site.metas do
      match metaSlot.spec.binding with
      | .fixedProgram packageId =>
          if !(ids.any (· == packageId)) then
            ids := ids.push packageId
      | _ => pure ()
  let mut out : Array ActiveCalleePackageV1 := #[]
  for packageId in ids do
    match findActiveCalleePackage? packageId with
    | none =>
        productFail
          s!"product bindings reject package '{packageId}' not in active catalog"
    | some pkg =>
        unless pkg.admittedForMaterialization do
          productFail
            s!"product bindings reject package '{packageId}' with admitted=false"
        match pkg.artifactBinding with
        | .absent =>
            productFail
              s!"product bindings reject package '{packageId}' with artifactBinding=absent"
        | .runtimeNative _ | .loaderV3Elf _ => pure ()
        out := out.push pkg
  pure out

private def encodeProductBindingsJson
    (plan : SolanaCpiProductPlanV1)
    (ir : ResolvedSolanaCpiProductIRV1) :
    CompileResult String := do
  let validated := SolanaCpiProductPlanV1.planOf plan
  let planDig ← mapExcept (renderDigest (SolanaCpiProductPlanV1.digestOf plan))
    "planDigest"
  let irDig ← mapExcept (renderDigest (ResolvedSolanaCpiProductIRV1.digestOf ir))
    "irDigest"
  let profileDig ←
    mapExcept (renderDigest validated.candidate.profileDigest) "profileDigest"
  let catalogDig ←
    mapExcept (renderDigest validated.candidate.calleeCatalogDigest) "catalogDigest"
  let packages ← collectReferencedActivePackages validated
  let mut packageFields : Array PfJson := #[]
  for pkg in packages do
    let programHex := encodeLowerHex (SolanaPubkeyV1.toBytes pkg.programId)
    packageFields := packageFields.push (.object #[
      ("packageId", .string pkg.packageId),
      ("programIdHex", .string programHex),
      ("admittedForMaterialization", .bool pkg.admittedForMaterialization),
      ("artifactBinding", .string (renderActiveArtifactBinding pkg.artifactBinding)),
      ("executionClass", .string (match pkg.executionClass with
        | .loaderV3Sbpf => "loader-v3-sbpf"
        | .nativeSystem => "native-system"))
    ])
  let json : PfJson := .object #[
    ("schema", .string "proof-forge.solana.cpi-bindings.v1"),
    ("profileId", .string validated.candidate.profileId),
    ("profileDigest", .string profileDig),
    ("calleeCatalogDigest", .string catalogDig),
    ("planDigest", .string planDig),
    ("irDigest", .string irDig),
    ("implementationState",
      .string validated.candidate.computeAssumptions.implementationState),
    ("referencedPackages", .array packageFields)
  ]
  mapExcept (renderPfJcs json) "product bindings PF-JCS"

/-- Product base files from engineering capability.

    Exact order:
      `{name}.cpi-plan.json`
      `{name}.cpi-ir.json`
      `{name}.idl.json`
      `{name}.s`
      `{name}.cpi-bindings.json`

    ADR-0032 full-body hybrid (multi-block/Map + zero CPI sites) is dispatched
    from `EmitSbpfAsmV1.buildFromCapability` to avoid import cycles.
-/
def productBaseFilesFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let plan ← productPlanFromCapabilityV1 capability
  let ir ← resolveSolanaCpiProductIRV1 plan
  let assembly ← emitCpiProductSbpfV1 ir
  let validated := SolanaCpiProductPlanV1.planOf plan
  let idl ← deriveSolanaCpiIdlV1 validated
  let name := validated.candidate.programName
  let planText ← utf8Of (SolanaCpiProductPlanV1.canonicalBytesOf plan)
  let irText ← utf8Of (ResolvedSolanaCpiProductIRV1.canonicalBytesOf ir)
  let bindingsText ← encodeProductBindingsJson plan ir
  pure #[
    { path := s!"{name}.cpi-plan.json"
      mediaType := "application/json"
      contents := planText },
    { path := s!"{name}.cpi-ir.json"
      mediaType := "application/json"
      contents := irText },
    { path := s!"{name}.idl.json"
      mediaType := "application/json"
      contents := idl.canonicalText },
    { path := s!"{name}.s"
      mediaType := "text/x-asm"
      contents := SolanaCpiProductAssemblyV1.textOf assembly },
    { path := s!"{name}.cpi-bindings.json"
      mediaType := "application/json"
      contents := bindingsText }
  ]

end ProofForgeV2.Targets.Solana.CpiV1
