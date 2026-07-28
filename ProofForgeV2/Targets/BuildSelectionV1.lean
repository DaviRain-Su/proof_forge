import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.BuildSelectionV1

open ProofForgeV2

/-!
# Static build-selection authority (engineering D3/S4)

Sole static index of target/profile/default membership for product build
selection. **Not** formal `TargetRegistryV1`; no `registryDigest`, no
SupportClaim, no network registry, no BuildIdentity.

`NetworkProfileId` must not appear on selection structures or the resolve API.

Product paths bind `initialStaticBuildSelectionIndexV1Result : CompileResult _`
and propagate `PF-REGISTRY-INVALID` — no empty `Inhabited` / `panic!` seed
fallback.
-/

/-- One static registration row (engineering carrier, not formal TargetRegistration). -/
structure StaticBuildRegistrationV1 where
  targetId : TargetId
  kind : TargetKind
  implemented : Bool
  profiles : Array CodegenProfileId
  defaultProfile : Option CodegenProfileId
  maturityLabel : String
  -- No Inhabited: TargetId/CodegenProfileId have no default identity.
  deriving BEq, Repr

/-- Reserved future profiles that must not appear in the shipped index. -/
def reservedFutureProfiles : Array String :=
  #["solana-sbpf-elf-v1", "noir-acir-proof-v1"]

/-- Validated static selection index. Private constructor — use
`createStaticBuildSelectionIndexV1`. -/
structure StaticBuildSelectionIndexV1 where
  private mk ::
  registrations : Array StaticBuildRegistrationV1
  deriving Repr

namespace StaticBuildSelectionIndexV1

def toArray (index : StaticBuildSelectionIndexV1) : Array StaticBuildRegistrationV1 :=
  index.registrations

end StaticBuildSelectionIndexV1

private def profileStrings (profiles : Array CodegenProfileId) : Array String :=
  profiles.map (·.toString)

private def containsProfile (profiles : Array CodegenProfileId) (p : CodegenProfileId) : Bool :=
  profiles.any (· == p)

private def findDuplicateString (values : Array String) : Option String :=
  Id.run do
    let mut seen : Array String := #[]
    for v in values do
      if seen.contains v then
        return some v
      seen := seen.push v
    return none

/-- SPEC-REG-001: per-target codegen profile IDs must be unique and strictly
ASCII-ascending. Empty/singleton arrays are vacuously ordered. -/
private def isStrictlyAscendingAscii (values : Array String) : Bool :=
  Id.run do
    let mut i : Nat := 0
    while i + 1 < values.size do
      let a := values[i]!
      let b := values[i + 1]!
      unless a < b do
        return false
      i := i + 1
    return true

/-- Validate and construct a static build-selection index.
Fails with `PF-REGISTRY-DUPLICATE` / `PF-REGISTRY-INVALID` as appropriate.
Empty input fails — never yields an empty success carrier. -/
def createStaticBuildSelectionIndexV1 (regs : Array StaticBuildRegistrationV1) :
    CompileResult StaticBuildSelectionIndexV1 := do
  if regs.isEmpty then
    throw <| .registryInvalid "static build-selection index must be non-empty"
  -- Exact unique target IDs (case-sensitive string identity).
  let targetIds := regs.map (·.targetId.toString)
  if let some dup := findDuplicateString targetIds then
    throw <| .registryDuplicate s!"duplicate target id '{dup}'"
  -- Global profile uniqueness across the index.
  let mut allProfiles : Array String := #[]
  for reg in regs do
    -- Re-validate opaque ID grammar on every row (sole fail-closed gate even if a
    -- construction helper is misused). TargetId/CodegenProfileId.parse? are the
    -- grammar authorities.
    match TargetId.parse? reg.targetId.toString with
    | none =>
        throw <| .registryInvalid
          s!"target id '{reg.targetId}' fails TargetId grammar"
    | some parsed =>
        unless parsed == reg.targetId do
          throw <| .registryInvalid
            s!"target id '{reg.targetId}' is not a canonical TargetId parse"
    for p in reg.profiles do
      match CodegenProfileId.parse? p.toString with
      | none =>
          throw <| .registryInvalid
            s!"codegen profile '{p}' fails CodegenProfileId grammar"
      | some parsed =>
          unless parsed == p do
            throw <| .registryInvalid
              s!"codegen profile '{p}' is not a canonical CodegenProfileId parse"
    if let some defP := reg.defaultProfile then
      match CodegenProfileId.parse? defP.toString with
      | none =>
          throw <| .registryInvalid
            s!"default profile '{defP}' fails CodegenProfileId grammar"
      | some parsed =>
          unless parsed == defP do
            throw <| .registryInvalid
              s!"default profile '{defP}' is not a canonical CodegenProfileId parse"
    let ps := profileStrings reg.profiles
    if let some dup := findDuplicateString ps then
      throw <| .registryDuplicate
        s!"duplicate codegen profile '{dup}' within target '{reg.targetId}'"
    -- Fail closed on non-canonical profile order (do not silently reorder).
    unless isStrictlyAscendingAscii ps do
      throw <| .registryInvalid
        s!"codegen profiles for target '{reg.targetId}' must be strictly ASCII-ascending"
    for p in ps do
      if allProfiles.contains p then
        throw <| .registryDuplicate s!"duplicate codegen profile '{p}' across targets"
      allProfiles := allProfiles.push p
    -- Reserved future profiles must never register.
    for p in ps do
      if reservedFutureProfiles.contains p then
        throw <| .registryInvalid s!"reserved future profile '{p}' cannot be registered"
    -- Implemented ⇔ nonempty profiles + default ∈ profiles.
    -- Design-only ⇔ empty profiles + default = none.
    match reg.implemented, reg.defaultProfile with
    | true, some defP =>
        if reg.profiles.isEmpty then
          throw <| .registryInvalid
            s!"implemented target '{reg.targetId}' must declare at least one profile"
        unless containsProfile reg.profiles defP do
          throw <| .registryInvalid
            s!"default profile '{defP}' is not a member of target '{reg.targetId}'"
    | true, none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' must declare an explicit default profile"
    | false, none =>
        unless reg.profiles.isEmpty do
          throw <| .registryInvalid
            s!"design-only target '{reg.targetId}' must have empty profiles"
    | false, some defP =>
        throw <| .registryInvalid
          s!"design-only target '{reg.targetId}' must not declare default '{defP}'"
    -- kind wire label must equal targetId string for the closed ten-set.
    unless reg.kind.toString == reg.targetId.toString do
      throw <| .registryInvalid
        s!"target id '{reg.targetId}' does not match kind '{reg.kind}'"
  -- Deterministic storage: sort by targetId ASCII bytes (stable for exact lookup).
  let sorted := regs.qsort (fun a b => a.targetId.toString < b.targetId.toString)
  return StaticBuildSelectionIndexV1.mk sorted

private def registration
    (kind : TargetKind) (implemented : Bool)
    (profiles : Array CodegenProfileId) (defaultProfile : Option CodegenProfileId)
    (maturityLabel : String) : StaticBuildRegistrationV1 :=
  {
    targetId := TargetId.ofKind kind
    kind
    implemented
    profiles
    defaultProfile
    maturityLabel
  }

/-- Shipped initial index rows: four implemented defaults + six design-only. -/
def initialRegistrations : Array StaticBuildRegistrationV1 :=
  #[
    registration .evm true
      #[CodegenProfileId.evmYulSolc0834V1] (some CodegenProfileId.evmYulSolc0834V1)
      "runtime-validated-alpha",
    registration .solana true
      #[CodegenProfileId.solanaSbpfPlanV1] (some CodegenProfileId.solanaSbpfPlanV1)
      "plan-only",
    registration .near true
      #[CodegenProfileId.nearWasmRawU64V1] (some CodegenProfileId.nearWasmRawU64V1)
      "wasm-validated-alpha",
    registration .noir true
      #[CodegenProfileId.noirSourceU64RelationsV1]
      (some CodegenProfileId.noirSourceU64RelationsV1)
      "source-only",
    registration .cosmwasm false #[] none "research-only",
    registration .soroban false #[] none "research-only",
    registration .icp false #[] none "research-only",
    registration .openvm false #[] none "research-only",
    registration .aleo false #[] none "research-only",
    registration .psy false #[] none "research-only"
  ]

/-- Frozen product seed as `CompileResult`. Product resolve/list/describe bind
this result and surface `PF-REGISTRY-INVALID` on seed failure — never panic or
empty success. -/
def initialStaticBuildSelectionIndexV1Result : CompileResult StaticBuildSelectionIndexV1 :=
  createStaticBuildSelectionIndexV1 initialRegistrations

/-- Private-constructor resolved build selection binding target + profile + kind. -/
structure ResolvedBuildSelectionV1 where
  private mk ::
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind
  deriving BEq, Repr

namespace ResolvedBuildSelectionV1

def targetIdOf (s : ResolvedBuildSelectionV1) : TargetId := s.targetId
def codegenProfileOf (s : ResolvedBuildSelectionV1) : CodegenProfileId := s.codegenProfile
def kindOf (s : ResolvedBuildSelectionV1) : TargetKind := s.kind

end ResolvedBuildSelectionV1

private def findRegistration (index : StaticBuildSelectionIndexV1) (target : TargetId) :
    Option StaticBuildRegistrationV1 :=
  index.registrations.find? (·.targetId == target)

/-- Inspection-only selection fields. **Not** a materialize/emit capability:
`materializeResult` / `emitProgram` require `ResolvedBuildSelectionV1`, which is
minted only by product `resolveBuildSelectionV1` (sole private-ctor call site).
Forged/alternate catalogs may produce inspections or registration rows only. -/
structure BuildSelectionInspectionV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind
  deriving BEq, Repr

/-- Dependency-injected selection inspection over an arbitrary seed Result.
Returns inspection fields or propagates seed/`PF-*` errors — **never**
`ResolvedBuildSelectionV1`. -/
def inspectBuildSelectionWithSeedV1
    (seed : CompileResult StaticBuildSelectionIndexV1)
    (target : TargetId)
    (requestedProfile? : Option CodegenProfileId) :
    CompileResult BuildSelectionInspectionV1 := do
  let index ← seed
  let reg ← match findRegistration index target with
    | some reg => pure reg
    | none => throw <| .unknownTarget target.toString
  unless reg.implemented do
    throw <| .targetNotImplemented reg.kind
  let profile ← match requestedProfile? with
    | none =>
        match reg.defaultProfile with
        | some defP => pure defP
        | none =>
            throw <| .registryInvalid
              s!"implemented target '{target}' is missing a registered default"
    | some requested =>
        unless containsProfile reg.profiles requested do
          throw <| .unknownProfile requested.toString
        pure requested
  return { targetId := target, codegenProfile := profile, kind := reg.kind }

/-- Product build selection — **sole** public mint of `ResolvedBuildSelectionV1`.
Binds frozen seed Result → inspection → private ctor. Seed failure propagates. -/
def resolveBuildSelectionV1
    (target : TargetId)
    (requestedProfile? : Option CodegenProfileId) :
    CompileResult ResolvedBuildSelectionV1 := do
  let insp ← inspectBuildSelectionWithSeedV1
    initialStaticBuildSelectionIndexV1Result target requestedProfile?
  return ResolvedBuildSelectionV1.mk insp.targetId insp.codegenProfile insp.kind

/-- Lookup in a caller-supplied validated index (row inspection only). -/
def registrationInIndex? (index : StaticBuildSelectionIndexV1) (target : TargetId) :
    Option StaticBuildRegistrationV1 :=
  findRegistration index target

/-- DI registration lookup over a seed Result (rows only, no capability). -/
def registrationWithSeedV1
    (seed : CompileResult StaticBuildSelectionIndexV1) (target : TargetId) :
    CompileResult (Option StaticBuildRegistrationV1) := do
  let index ← seed
  return findRegistration index target

/-- Product registration lookup — binds frozen seed Result. -/
def registration? (target : TargetId) :
    CompileResult (Option StaticBuildRegistrationV1) :=
  registrationWithSeedV1 initialStaticBuildSelectionIndexV1Result target

/-- Implemented rows in a supplied index (canonical TargetId order). -/
def implementedRegistrationsInIndex (index : StaticBuildSelectionIndexV1) :
    Array StaticBuildRegistrationV1 :=
  index.registrations.filter (·.implemented)

/-- Design-only rows in a supplied index (canonical TargetId order). -/
def designOnlyRegistrationsInIndex (index : StaticBuildSelectionIndexV1) :
    Array StaticBuildRegistrationV1 :=
  index.registrations.filter (fun r => !r.implemented)

/-- DI full registration array over a seed Result. -/
def registrationsWithSeedV1 (seed : CompileResult StaticBuildSelectionIndexV1) :
    CompileResult (Array StaticBuildRegistrationV1) := do
  let index ← seed
  return index.toArray

/-- DI implemented registrations over a seed Result. -/
def implementedRegistrationsWithSeedV1
    (seed : CompileResult StaticBuildSelectionIndexV1) :
    CompileResult (Array StaticBuildRegistrationV1) := do
  let index ← seed
  return implementedRegistrationsInIndex index

/-- DI design-only registrations over a seed Result. -/
def designOnlyRegistrationsWithSeedV1
    (seed : CompileResult StaticBuildSelectionIndexV1) :
    CompileResult (Array StaticBuildRegistrationV1) := do
  let index ← seed
  return designOnlyRegistrationsInIndex index

/-- Product implemented registrations — binds frozen seed Result. -/
def implementedRegistrations : CompileResult (Array StaticBuildRegistrationV1) :=
  implementedRegistrationsWithSeedV1 initialStaticBuildSelectionIndexV1Result

/-- Product design-only registrations — binds frozen seed Result. -/
def designOnlyRegistrations : CompileResult (Array StaticBuildRegistrationV1) :=
  designOnlyRegistrationsWithSeedV1 initialStaticBuildSelectionIndexV1Result

/-- Product full index array — binds frozen seed Result. -/
def productRegistrations : CompileResult (Array StaticBuildRegistrationV1) :=
  registrationsWithSeedV1 initialStaticBuildSelectionIndexV1Result

end ProofForgeV2.Targets.BuildSelectionV1
