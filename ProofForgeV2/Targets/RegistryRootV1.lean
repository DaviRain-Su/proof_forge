/-
  ProofForgeV2.Targets.RegistryRootV1 — engineering registry root codec + digest (M3a)

  Deterministic length-framed encoding of the public `TargetRegistryV1`
  membership table (canonical TargetId order) and a domain-separated SHA-256
  digest over those bytes.

  **Engineering only — not formal TASK-D3-02 / formal registry root:**
  * Domain is `pf.registry-root.engineering.v1` (engineering-only; distinct
    from the formal JCS registry-root domain string forbidden in this kernel).
  * Covers targetId + six axis wires + codegen profile ids + default profile
    marker only; does **not** encode displayName / maturity / acceptance /
    implemented / full descriptor / SupportClaim / BuildIdentity.
  * Encode-only: no decode / round-trip API in this slice.
  * Does not mint BuildIdentity, does not enter product selection /
    capability / artifacts, and is not a formal registry-root digest field
    on the registry carrier.

  Formal expansion must still grow `TargetRegistryV1` in place with the
  formal root schema; this module remains the engineering root helper.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace ProofForgeV2.Targets.RegistryRootV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.TargetRegistryV1

/-- Domain tag for the **engineering** registry root digest.
    Engineering-only; never the formal JCS registry-root domain.
    Matches the `pf.*.engineering.v1` style used by
    `pf.requirement-key.engineering.v1`. -/
def engineeringRegistryRootDomainV1 : String :=
  "pf.registry-root.engineering.v1"

/-- Canonical marker encoded when `defaultProfile = none`.
    Profile ids are SPEC-COMMON grammar; the bare token `none` is reserved
    as this root-codec sentinel and is not a shipped CodegenProfileId. -/
def engineeringRegistryRootDefaultNoneMarkerV1 : String :=
  "none"

/-- Little-endian u32 length header (portable; same layout as Wire/Source codecs). -/
private def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

private def encodeNatAsU32le (count : Nat) : Except String ByteArray := do
  unless count ≤ UInt32.size - 1 do
    throw "registry root u32 length is not representable"
  pure (encodeU32le (UInt32.ofNat count))

/-- Length-framed UTF-8 string: `u32le(len) || utf8Bytes`. -/
private def encodeString (value : String) : Except String ByteArray := do
  let raw := value.toUTF8
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

private def encodeDefaultProfile
    (defaultProfile : Option CodegenProfileId) : Except String ByteArray :=
  match defaultProfile with
  | none => encodeString engineeringRegistryRootDefaultNoneMarkerV1
  | some p => encodeString p.toString

/-- Encode one registration row in fixed field order (no kind/display/etc.). -/
private def encodeRegistration
    (reg : TargetRegistrationDataV1) : Except String ByteArray := do
  let mut out := ByteArray.empty
  out := out.append (← encodeString reg.targetId.toString)
  out := out.append (← encodeString reg.semantics.executionHost.toWire)
  out := out.append (← encodeString reg.semantics.commitModel.toWire)
  out := out.append (← encodeString reg.semantics.stateBinding.toWire)
  out := out.append (← encodeString reg.semantics.callModel.toWire)
  out := out.append (← encodeString reg.semantics.proofModel.toWire)
  out := out.append (← encodeString reg.semantics.settlementModel.toWire)
  out := out.append (← encodeNatAsU32le reg.profiles.size)
  for p in reg.profiles do
    out := out.append (← encodeString p.toString)
  out := out.append (← encodeDefaultProfile reg.defaultProfile)
  pure out

/-- Canonical engineering registry root bytes.

    Layout (deterministic, little-endian lengths, registry stored order):
    ```
    u32le(registrationCount)
    for each registration (TargetId ASCII ascending as stored):
      String(targetId)
      String(executionHost wire)
      String(commitModel wire)
      String(stateBinding wire)
      String(callModel wire)
      String(proofModel wire)
      String(settlementModel wire)
      u32le(profileCount)
      String(profileId) × profileCount   -- already strictly ASCII-ascending
      String(defaultProfileId | "none")
    String = u32le(utf8ByteLen) || utf8Bytes
    ```
    Computed only from the public registry view (`registrationsOf`); no private
    carrier field. -/
def encodeEngineeringRegistryRootBytesV1
    (registry : TargetRegistryV1) : Except String ByteArray := do
  let regs := TargetRegistryV1.registrationsOf registry
  let mut out ← encodeNatAsU32le regs.size
  for reg in regs do
    out := out.append (← encodeRegistration reg)
  pure out

/-- Engineering registry root digest:
    `domainSeparatedSha256(pf.registry-root.engineering.v1, rootBytes)`.

    Same registry ⇒ same digest; any covered field mutation ⇒ different digest.
    **Not** formal registry-root digest / SupportClaim / product selection
    authority. -/
def engineeringRegistryRootDigestV1
    (registry : TargetRegistryV1) : Except String Digest := do
  let bytes ← encodeEngineeringRegistryRootBytesV1 registry
  domainSeparatedSha256 engineeringRegistryRootDomainV1 bytes

end ProofForgeV2.Targets.RegistryRootV1
