/-
  ProofForgeV2.Targets.BuildSelectionV1 — product selection over TargetRegistryV1

  Sole product mint of private-ctor `ResolvedBuildSelectionV1`. Membership,
  defaults, and profile tables come **only** from frozen
  `TargetRegistryV1.initialTargetRegistryV1Result`.

  Independent static selection index / seed carriers are deleted; membership is
  only the frozen TargetRegistry seed.

  **Not** formal SupportClaim / BuildIdentity product binding / formal registry root digest.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2.Targets.BuildSelectionV1

open ProofForgeV2
open ProofForgeV2.Targets.TargetRegistryV1

/-- Re-export reserved list for CLI/tests that historically imported from here. -/
def reservedFutureProfiles : Array String :=
  ProofForgeV2.Targets.TargetRegistryV1.reservedFutureProfiles

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

private def containsProfile (profiles : Array CodegenProfileId) (p : CodegenProfileId) : Bool :=
  profiles.any (· == p)

/-- Inspection-only selection fields. **Not** a materialize/emit capability.
    Sole public mint of `ResolvedBuildSelectionV1` is product
    `resolveBuildSelectionV1` (private ctor). -/
structure BuildSelectionInspectionV1 where
  targetId : TargetId
  codegenProfile : CodegenProfileId
  kind : TargetKind
  deriving BEq, Repr

/-- DI selection inspection over an arbitrary registry seed Result.
    Returns inspection fields or propagates seed/`PF-*` errors — **never**
    `ResolvedBuildSelectionV1`. -/
def inspectBuildSelectionWithSeedV1
    (seed : CompileResult TargetRegistryV1)
    (target : TargetId)
    (requestedProfile? : Option CodegenProfileId) :
    CompileResult BuildSelectionInspectionV1 := do
  let registry ← seed
  let reg ← match findRegistrationV1 registry target with
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
    Binds frozen registry seed → inspection → private ctor. -/
def resolveBuildSelectionV1
    (target : TargetId)
    (requestedProfile? : Option CodegenProfileId) :
    CompileResult ResolvedBuildSelectionV1 := do
  let insp ← inspectBuildSelectionWithSeedV1
    initialTargetRegistryV1Result target requestedProfile?
  return ResolvedBuildSelectionV1.mk insp.targetId insp.codegenProfile insp.kind

/-- Lookup in a caller-supplied validated registry (row inspection only). -/
def registrationInRegistry?
    (registry : TargetRegistryV1) (target : TargetId) :
    Option TargetRegistrationDataV1 :=
  findRegistrationV1 registry target

/-- DI registration lookup over a seed Result (rows only, no capability). -/
def registrationWithSeedV1
    (seed : CompileResult TargetRegistryV1) (target : TargetId) :
    CompileResult (Option TargetRegistrationDataV1) := do
  let registry ← seed
  return findRegistrationV1 registry target

/-- Product registration lookup — binds frozen registry seed. -/
def registration? (target : TargetId) :
    CompileResult (Option TargetRegistrationDataV1) :=
  registrationWithSeedV1 initialTargetRegistryV1Result target

/-- Implemented rows in a supplied registry (canonical TargetId order). -/
def implementedRegistrationsInRegistry (registry : TargetRegistryV1) :
    Array TargetRegistrationDataV1 :=
  implementedRegistrationsV1 registry

/-- Design-only rows in a supplied registry (canonical TargetId order). -/
def designOnlyRegistrationsInRegistry (registry : TargetRegistryV1) :
    Array TargetRegistrationDataV1 :=
  designOnlyRegistrationsV1 registry

/-- DI full registration array over a seed Result. -/
def registrationsWithSeedV1 (seed : CompileResult TargetRegistryV1) :
    CompileResult (Array TargetRegistrationDataV1) := do
  let registry ← seed
  return TargetRegistryV1.registrationsOf registry

/-- DI implemented registrations over a seed Result. -/
def implementedRegistrationsWithSeedV1
    (seed : CompileResult TargetRegistryV1) :
    CompileResult (Array TargetRegistrationDataV1) := do
  let registry ← seed
  return implementedRegistrationsInRegistry registry

/-- DI design-only registrations over a seed Result. -/
def designOnlyRegistrationsWithSeedV1
    (seed : CompileResult TargetRegistryV1) :
    CompileResult (Array TargetRegistrationDataV1) := do
  let registry ← seed
  return designOnlyRegistrationsInRegistry registry

/-- Product implemented registrations — binds frozen registry seed. -/
def implementedRegistrations : CompileResult (Array TargetRegistrationDataV1) :=
  implementedRegistrationsWithSeedV1 initialTargetRegistryV1Result

/-- Product design-only registrations — binds frozen registry seed. -/
def designOnlyRegistrations : CompileResult (Array TargetRegistrationDataV1) :=
  designOnlyRegistrationsWithSeedV1 initialTargetRegistryV1Result

/-- Product full registration array — binds frozen registry seed. -/
def productRegistrations : CompileResult (Array TargetRegistrationDataV1) :=
  registrationsWithSeedV1 initialTargetRegistryV1Result

end ProofForgeV2.Targets.BuildSelectionV1
