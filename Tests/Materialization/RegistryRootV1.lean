/-
  Engineering registry root codec + digest suite (M3a / Wave formal-identity first slice).

  Pins canonical root bytes and engineering root digest for the frozen 12-target
  seed; checks determinism and per-axis / profile / default tamper sensitivity.

  **Not** formal TASK-D3-02 / formal `registryDigest` / SupportClaim / BuildIdentity.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.RegistryRootV1
import ProofForgeV2.Targets.TargetRegistryV1

namespace Tests.Materialization.RegistryRootV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.RegistryRootV1
open ProofForgeV2.Targets.TargetRegistryV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def liftExcept (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeLowerHex (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def digestHex (d : Digest) : IO String := do
  let rendered ← liftExcept "renderDigest" (renderDigest d)
  -- renderDigest → "sha256:<64 hex>"; pin the raw 64-hex form too.
  pure rendered

/-- Frozen 12-target seed engineering root bytes (exact pin). Length 1974. -/
private def expectedRootHexV1 : String :=
  "0c00000004000000616c656f07000000616c656f2d766d1000000070726f6f662d66696e616c2d6475616c100000007265636f7264732d6d617070696e67731300000070726f6772616d2d70726f6f662d66696e616c170000006170706c69636174696f6e2d636861696e2d70726f6f660a000000616c656f2d636861696e0100000015000000616c656f2d6c656f2d342e302e322d7536342d763115000000616c656f2d6c656f2d342e302e322d7536342d763108000000636f736d7761736d08000000636f736d7761736d160000007472616e73616374696f6e2d73617665706f696e747312000000636f6e74726163742d6b65792d76616c756517000000636f736d6f732d7375626d6573736167652d7265706c79080000006e6f2d70726f6f660c000000636f736d6f732d636861696e0100000014000000636f736d7761736d2d7761736d2d7536342d763114000000636f736d7761736d2d7761736d2d7536342d76310300000065766d0300000065766d120000007472616e73616374696f6e2d61746f6d696310000000636f6e74726163742d73746f726167651300000073796e6368726f6e6f75732d6d657373616765080000006e6f2d70726f6f660900000065766d2d636861696e020000001d00000065766d2d79756c2d736f6c632d302e382e33342d63616e63756e2d76311600000065766d2d79756c2d736f6c632d302e382e33342d76311600000065766d2d79756c2d736f6c632d302e382e33342d7631030000006963700c0000006963702d63616e69737465720f00000061776169742d7365676d656e7465641400000063616e69737465722d686561702d737461626c65120000006173796e6368726f6e6f75732d6163746f72080000006e6f2d70726f6f660a0000006963702d7375626e657400000000040000006e6f6e65040000006e656172090000006e6561722d7761736d0d000000726563656970742d6c6f63616c12000000636f6e74726163742d6b65792d76616c75650b00000070726f6d6973652d646167080000006e6f2d70726f6f660a0000006e6561722d636861696e01000000140000006e6561722d7761736d2d7261772d7536342d7631140000006e6561722d7761736d2d7261772d7536342d7631040000006e6f69720c0000006e6f69722d636972637569741100000072656c6174696f6e2d65787465726e616c1800000065787465726e616c2d7075626c69632d7072652d706f73740e0000006e6f2d6e61746976652d63616c6c1000000065787465726e616c2d636972637569741100000065787465726e616c2d7665726966696572010000001c0000006e6f69722d736f757263652d7536342d72656c6174696f6e732d76311c0000006e6f69722d736f757263652d7536342d72656c6174696f6e732d7631060000006f70656e766d0c0000006f70656e766d2d67756573740e00000067756573742d65787465726e616c0f00000067756573742d6d656d6f72792d696f0e00000067756573742d696e7465726e616c0e0000007a6b766d2d657865637574696f6e1100000065787465726e616c2d766572696669657200000000040000006e6f6e6503000000707379070000007073792d64706e110000007265637572736976652d6e6574776f726b10000000757365722d706172746974696f6e6564180000007265637572736976652d70726f6f662d706970656c696e65150000007265637572736976652d6167677265676174696f6e0b0000007073792d6e6574776f726b01000000100000007073792d646172676f2d7536342d7631100000007073792d646172676f2d7536342d7631050000007175696e740b0000007175696e742d6d6f64656c1100000072656c6174696f6e2d65787465726e616c1800000065787465726e616c2d7075626c69632d7072652d706f73740e0000006e6f2d6e61746976652d63616c6c080000006e6f2d70726f6f660d0000006e6f2d736574746c656d656e7401000000190000007175696e742d736f757263652d7536342d6d6f64656c2d7631190000007175696e742d736f757263652d7536342d6d6f64656c2d763106000000736f6c616e610300000073766d12000000696e737472756374696f6e2d61746f6d6963110000006578706c696369742d6163636f756e74730f00000073796e6368726f6e6f75732d637069080000006e6f2d70726f6f660c000000736f6c616e612d636861696e0200000012000000736f6c616e612d736270662d656c662d763113000000736f6c616e612d736270662d706c616e2d763113000000736f6c616e612d736270662d706c616e2d763107000000736f726f62616e0c000000736f726f62616e2d7761736d120000007472616e73616374696f6e2d61746f6d69631200000074746c2d73636f7065642d73746f726167651500000073796e6368726f6e6f75732d617574682d74726565080000006e6f2d70726f6f660d0000007374656c6c61722d636861696e00000000040000006e6f6e6503000000746f6e0300000074766d120000007472616e73616374696f6e2d61746f6d69630c00000063656c6c2d686173686d6170120000006173796e6368726f6e6f75732d6163746f72080000006e6f2d70726f6f6609000000746f6e2d636861696e010000000f000000746f6e2d746f6c6b2d626f632d76310f000000746f6e2d746f6c6b2d626f632d7631"

/-- Engineering root digest pin: domainSeparatedSha256(domain, rootBytes). -/
private def expectedDigestWireV1 : String :=
  "sha256:a2d12042ac5b8bd10ac5e642b6487e48d087a0838d45323e71bfdf1b05f5dab6"

private def testDomainAndMarker : IO Unit := do
  expect (engineeringRegistryRootDomainV1 == "pf.registry-root.engineering.v1")
    "engineering root domain spelling"
  expect (engineeringRegistryRootDefaultNoneMarkerV1 == "none")
    "default none marker"
  match validateProfileIdValue engineeringRegistryRootDomainV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"domain must pass profile-id grammar: {e}"
  -- Engineering domain must keep the engineering.v1 suffix (not formal root domain).
  expect (engineeringRegistryRootDomainV1.endsWith ".engineering.v1")
    "engineering domain suffix"

private def testCanonicalBytesGolden : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  let bytes ← liftExcept "encode root" (encodeEngineeringRegistryRootBytesV1 registry)
  let hex := encodeLowerHex bytes
  expect (bytes.size == 1974) s!"root byte length: got {bytes.size}"
  expect (hex == expectedRootHexV1) "canonical root bytes golden pin"
  -- Count header is little-endian 12.
  expect (bytes.get! 0 == 12) "u32le registration count low byte"
  expect (bytes.get! 1 == 0 && bytes.get! 2 == 0 && bytes.get! 3 == 0)
    "u32le registration count high bytes zero"

private def testDigestGolden : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  let digest ← liftExcept "root digest" (engineeringRegistryRootDigestV1 registry)
  let wire ← digestHex digest
  expect (wire == expectedDigestWireV1) s!"digest golden: got {wire}"
  expect (digest.algorithm == .sha256) "sha256 algorithm"
  expect (digest.bytes.size == 32) "32-byte digest"

private def testDeterminism : IO Unit := do
  let r1 ← liftResult initialTargetRegistryV1Result
  let r2 ← liftResult initialTargetRegistryV1Result
  let b1 ← liftExcept "encode1" (encodeEngineeringRegistryRootBytesV1 r1)
  let b2 ← liftExcept "encode2" (encodeEngineeringRegistryRootBytesV1 r2)
  expect (b1 == b2) "two encodes of seed → identical root bytes"
  let d1 ← liftExcept "digest1" (engineeringRegistryRootDigestV1 r1)
  let d2 ← liftExcept "digest2" (engineeringRegistryRootDigestV1 r2)
  expect (d1.algorithm == d2.algorithm && d1.bytes == d2.bytes)
    "two digests of seed → identical"
  -- Re-create via createTargetRegistryV1 of the same rows (any input order).
  let r3 ← liftResult (createTargetRegistryV1 initialRegistrationRowsV1)
  let b3 ← liftExcept "encode3" (encodeEngineeringRegistryRootBytesV1 r3)
  expect (b1 == b3) "create from unsorted rows → same root bytes after canonical sort"
  let d3 ← liftExcept "digest3" (engineeringRegistryRootDigestV1 r3)
  expect (d1.bytes == d3.bytes) "create from unsorted rows → same digest"

/-- Alternate closed-enum values used only for tamper (not product policy). -/
private def flipHost : ExecutionHostV1 → ExecutionHostV1
  | .evm => .svm
  | _ => .evm

private def flipCommit : CommitModelV1 → CommitModelV1
  | .transactionAtomic => .instructionAtomic
  | _ => .transactionAtomic

private def flipState : StateBindingV1 → StateBindingV1
  | .contractStorage => .explicitAccounts
  | _ => .contractStorage

private def flipCall : CallModelV1 → CallModelV1
  | .synchronousMessage => .synchronousCpi
  | _ => .synchronousMessage

private def flipProof : ProofModelV1 → ProofModelV1
  | .noProof => .externalCircuit
  | _ => .noProof

private def flipSettle : SettlementModelV1 → SettlementModelV1
  | .evmChain => .solanaChain
  | _ => .evmChain

private def replaceAt
    (regs : Array TargetRegistrationDataV1) (idx : Nat)
    (reg : TargetRegistrationDataV1) : Array TargetRegistrationDataV1 :=
  regs.set! idx reg

private def digestOfRows (rows : Array TargetRegistrationDataV1) : IO Digest := do
  let reg ← liftResult (createTargetRegistryV1 rows)
  liftExcept "tamper digest" (engineeringRegistryRootDigestV1 reg)

private def expectDigestDiff (label : String) (base alt : Digest) : IO Unit :=
  expect (!(base.bytes == alt.bytes)) s!"{label}: digest must change"

private def uniqueAltProfile (used : Array String) (base : String) : String :=
  -- Grammar-valid alternate that is not already registered globally.
  let candidate := base ++ "-tamper"
  if used.contains candidate then base ++ "-tamper2" else candidate

private def parseProfile! (name : String) : IO CodegenProfileId :=
  match CodegenProfileId.parse? name with
  | some p => pure p
  | none => throw <| IO.userError s!"alt profile grammar fail: {name}"

private def testTamperMatrix : IO Unit := do
  let registry ← liftResult initialTargetRegistryV1Result
  let baseDigest ← liftExcept "base" (engineeringRegistryRootDigestV1 registry)
  let regs := TargetRegistryV1.registrationsOf registry
  expect (regs.size == 12) "12 registrations for tamper matrix"
  let allProfileIds : Array String :=
    regs.foldl (fun acc (r : TargetRegistrationDataV1) =>
      acc ++ r.profiles.map (·.toString)) #[]

  -- 12 registrations × 6 axes.
  for i in [:regs.size] do
    let reg : TargetRegistrationDataV1 ←
      match regs[i]? with
      | some r => pure r
      | none => throw <| IO.userError s!"missing registration at {i}"
    let tid := reg.targetId.toString
    let s0 := reg.semantics
    let axisMutations : Array (String × TargetSemanticsAxesV1) := #[
      ("executionHost", { s0 with executionHost := flipHost s0.executionHost }),
      ("commitModel", { s0 with commitModel := flipCommit s0.commitModel }),
      ("stateBinding", { s0 with stateBinding := flipState s0.stateBinding }),
      ("callModel", { s0 with callModel := flipCall s0.callModel }),
      ("proofModel", { s0 with proofModel := flipProof s0.proofModel }),
      ("settlementModel", { s0 with settlementModel := flipSettle s0.settlementModel })
    ]
    for pair in axisMutations do
      let axisName := pair.1
      let sem' := pair.2
      let mut' : TargetRegistrationDataV1 := { reg with semantics := sem' }
      let alt ← digestOfRows (replaceAt regs i mut')
      expectDigestDiff s!"{tid}.{axisName}" baseDigest alt

    -- Profile / default mutations only for implemented targets (design-only
    -- rows must keep empty profiles + none default under create policy).
    if reg.implemented then
      match reg.profiles[0]? with
      | none =>
          throw <| IO.userError s!"{tid}: implemented without profiles"
      | some p0 =>
          let altP ← parseProfile! (uniqueAltProfile allProfileIds p0.toString)
          let newProfiles : Array CodegenProfileId :=
            if reg.profiles.size == 1 then
              #[altP]
            else
              let rest := (reg.profiles.toList.drop 1).toArray
              (rest.push altP).qsort (fun a b => a.toString < b.toString)
          let newDefault : Option CodegenProfileId :=
            match reg.defaultProfile with
            | some d =>
                if d == p0 then some altP
                else if newProfiles.any (· == d) then some d
                else some altP
            | none => some altP
          let mutProfile : TargetRegistrationDataV1 :=
            { reg with profiles := newProfiles, defaultProfile := newDefault }
          let altProf ← digestOfRows (replaceAt regs i mutProfile)
          expectDigestDiff s!"{tid}.profiles" baseDigest altProf

          -- Default-profile mutation: swap among members, or add a second profile.
          match reg.profiles[0]?, reg.profiles[1]? with
          | some p1, some p2 =>
              let defP :=
                match reg.defaultProfile with
                | some d => d
                | none => p1
              let other := if defP == p1 then p2 else p1
              let mutDef : TargetRegistrationDataV1 :=
                { reg with defaultProfile := some other }
              let altDef ← digestOfRows (replaceAt regs i mutDef)
              expectDigestDiff s!"{tid}.defaultProfile" baseDigest altDef
          | some only, none =>
              let altDefP ←
                parseProfile! (uniqueAltProfile allProfileIds (only.toString ++ "-def"))
              let newProfiles2 : Array CodegenProfileId :=
                #[only, altDefP].qsort (fun a b => a.toString < b.toString)
              let mutDef : TargetRegistrationDataV1 :=
                { reg with profiles := newProfiles2, defaultProfile := some altDefP }
              let altDef ← digestOfRows (replaceAt regs i mutDef)
              expectDigestDiff s!"{tid}.defaultProfile-via-extra" baseDigest altDef
          | _, _ =>
              throw <| IO.userError s!"{tid}: unexpected profile shape"

  -- Global count sensitivity: drop one registration → different digest.
  let withoutLast := regs.pop
  expect (withoutLast.size == 11) "drop one registration"
  let altCount ← digestOfRows withoutLast
  expectDigestDiff "registrationCount" baseDigest altCount

private def testEncodeOnlySurface : IO Unit := do
  -- Encode-only honesty: no public decode API in this module (name absence).
  let out ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "decodeEngineeringRegistryRoot", "ProofForgeV2/Targets/RegistryRootV1.lean"]
  }
  -- rg exit 1 = no matches (expected for encode-only).
  if out.exitCode == 0 then
    throw <| IO.userError s!"unexpected decode API:\n{out.stdout}"
  else if out.exitCode != 1 then
    throw <| IO.userError s!"rg failed ({out.exitCode}): {out.stderr}"
  -- Engineering helper name must not collide with forbidden formal product API
  -- string `registryDigest` inside ProofForgeV2 (deletion gate of TargetRegistry suite).
  let forbid ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e", "registryDigest",
      "ProofForgeV2/Targets/RegistryRootV1.lean"]
  }
  if forbid.exitCode == 0 then
    throw <| IO.userError
      s!"RegistryRootV1 must not define formal/product registryDigest name:\n{forbid.stdout}"
  else if forbid.exitCode != 1 then
    throw <| IO.userError s!"rg failed ({forbid.exitCode}): {forbid.stderr}"

def run : IO Unit := do
  testDomainAndMarker
  testCanonicalBytesGolden
  testDigestGolden
  testDeterminism
  testTamperMatrix
  testEncodeOnlySurface
  IO.println "Tests.Materialization.RegistryRootV1: ok"

end Tests.Materialization.RegistryRootV1
