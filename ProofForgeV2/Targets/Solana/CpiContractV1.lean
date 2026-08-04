/-
  ProofForgeV2.Targets.Solana.CpiContractV1 — #117 pure target-owned frozen CPI contract leaf.

  Namespace: `ProofForgeV2.Targets.Solana.CpiV1`.

  Frozen projection of ADR-0028 / solana-cpi-extension-v1.json /
  solana-cpi-callee-catalog-v1.json / solana-cpi-profile-v1.json into Lean types.
  No Source/Typed/Semantic/TargetId imports. No Plan/IR/emitter/syscall surface.
-/

namespace ProofForgeV2.Targets.Solana.CpiV1

/-! ## Schema / domain / profile / extension / catalog digests -/

def extensionSchemaV1 : String := "proof-forge.solana.cpi-extension.v1"
def catalogSchemaV1 : String := "proof-forge.solana.callee-catalog.v1"
def profileSchemaV1 : String := "proof-forge.solana.cpi-profile.v1"
def planSchemaV1 : String := "proof-forge.solana.cpi-plan.v1"
def irSchemaV1 : String := "proof-forge.solana.cpi-ir.v1"
def idlSchemaV1 : String := "proof-forge.solana.cpi-idl.v1"

def extensionDigestDomainV1 : String := "pf.extension-semantics.v1"
def catalogDigestDomainV1 : String := "pf.solana.callee-catalog.v1"
def profileDigestDomainV1 : String := "pf.solana.cpi-profile.v1"

def profileIdV1 : String := "solana-sbpf-cpi-elf-v1"
def extensionIdV1 : String := "solana.cpi.accounts"
def extensionRequirementIdV1 : String := "extension.solana-cpi-accounts"
def extensionVersionV1 : String := "1.0.0"

/-- Domain-separated extension digest (`pf.extension-semantics.v1`). -/
def extensionDigestV1 : String :=
  "sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020"

/-- Domain-separated profile digest (`pf.solana.cpi-profile.v1`).
    Historical #114–#124 preactivation authority
    (`docs/specs/solana-cpi-profile-v1.json`). -/
def profileDigestV1 : String :=
  "sha256:0b306aa98b00611bd794953e6293b19e1b47937d2979d5b5cdaf1d2b221f43f1"

/-- Domain-separated callee-catalog digest (`pf.solana.callee-catalog.v1`).
    Historical #114–#124 preactivation authority
    (`docs/specs/solana-cpi-callee-catalog-v1.json`). -/
def catalogDigestV1 : String :=
  "sha256:41ace268b3bea9837e4a1fc9e456dbfbd36c98a344e51dfd095ab4ffb2086351"

/-- #125 active profile digest (`pf.solana.cpi-profile.v1` over
    `docs/specs/solana-cpi-profile-active-v1.json`). Same profileId
    `solana-sbpf-cpi-elf-v1`; binds active catalog domain digest; product
    exact sync; schedule false. -/
def activeProfileDigestV1 : String :=
  "sha256:b0f3f5bc7f3973daf176c308cc4ca310f8ad5b51ea33a33c9d1bd3e4d3e91b04"

/-- #125 active callee-catalog digest (`pf.solana.callee-catalog.v1` over
    `docs/specs/solana-cpi-callee-catalog-active-v1.json`, version 1.1.0). -/
def activeCatalogDigestV1 : String :=
  "sha256:e2c2ebac5e690b99ad50fb7f8a5f6ecfdb8295bb43f3913229c2fd48d2820419"

/-- Active catalog version spelling (historical remains `1.0.0`). -/
def activeCatalogVersionV1 : String := "1.1.0"

/-- Active profile implementation-state label (product exact sync). -/
def activeProfileImplementationStateV1 : String :=
  "product-exact-synchronous-call-active-v1"

/-! ## Product caps (fail closed before runtime upper bounds) -/

def maxOuterRolesV1 : Nat := 16
def maxCpiAccountInfosV1 : Nat := 16
def maxCpiMetasV1 : Nat := 16
def maxCpiSitesPerHandlerV1 : Nat := 32
def maxSignerGroupsPerCpiV1 : Nat := 4
def maxSeedsIncludingBumpV1 : Nat := 16
def maxSeedBytesV1 : Nat := 32
def maxInstructionDataBytesV1 : Nat := 1024
def maxPdaSpaceBytesV1 : Nat := 4096

/-- Agave v4.0.0 source commit pinned by catalog/profile runtime. -/
def agaveV400CommitV1 : String := "2a165e7a90af75c76426d1e031ed0284211d5d1e"

/-- PDA preimage marker bytes hex: ASCII `ProgramDerivedAddress`. -/
def pdaMarkerHexV1 : String := "50726f6772616d4465726976656441646472657373"

/-- Current-program tagged PDA seed[0] hex: ASCII `proof-forge:pda:v1`. -/
def currentProgramPdaTagHexV1 : String := "70726f6f662d666f7267653a7064613a7631"

/-! ## Strict 32-byte Solana pubkey carrier (no Principal conversion) -/

/-- Exact-32-byte program/account key. Private constructor; mint via `ofBytes` /
    `parseBase58` only. -/
structure SolanaPubkeyV1 where
  private mk ::
  bytes : ByteArray
  deriving BEq

instance : Repr SolanaPubkeyV1 where
  reprPrec key _ :=
    Std.Format.text "SolanaPubkeyV1.bytes["
      |>.append (repr key.bytes.size)
      |>.append (Std.Format.text "]")

namespace SolanaPubkeyV1

def toBytes (key : SolanaPubkeyV1) : ByteArray := key.bytes

/-- Accept only exact 32 raw bytes. -/
def ofBytes (raw : ByteArray) : Except String SolanaPubkeyV1 := do
  unless raw.size == 32 do
    throw "SolanaPubkeyV1 requires exact 32 bytes"
  pure ⟨raw⟩

/-- Bitcoin/Solana ASCII base58 alphabet (no `0OIl`). -/
def base58AlphabetV1 : String :=
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

private def base58AlphabetChars : List Char := base58AlphabetV1.toList

private def base58Index? (c : Char) : Option Nat :=
  let rec go (xs : List Char) (i : Nat) : Option Nat :=
    match xs with
    | [] => none
    | h :: t => if h == c then some i else go t (i + 1)
  go base58AlphabetChars 0

private def base58Char (d : Nat) : Char :=
  match base58AlphabetChars[d]? with
  | some c => c
  | none => '1'

private def bytesToNatBE (bytes : ByteArray) : Nat :=
  bytes.foldl (fun acc b => acc * 256 + b.toNat) 0

/-- Big-endian fixed-width encoding; `none` when `n` does not fit in `width` bytes. -/
private def natToExactBytesBE (n : Nat) (width : Nat) : Option ByteArray :=
  if width == 0 then
    if n == 0 then some ByteArray.empty else none
  else
    Id.run do
      let mut limbs : Array UInt8 := Array.mkEmpty width
      let mut x := n
      for _ in [0:width] do
        limbs := limbs.push (UInt8.ofNat (x % 256))
        x := x / 256
      if x != 0 then
        return none
      let mut out := ByteArray.empty
      for i in [0:width] do
        out := out.push limbs[width - 1 - i]!
      return some out

private def countLeadingZeroBytes (bytes : ByteArray) : Nat :=
  Id.run do
    let mut n := 0
    for i in [0:bytes.size] do
      if bytes[i]! == 0 then
        n := n + 1
      else
        return n
    return n

private def natToBase58Body (x : Nat) : List Char :=
  Id.run do
    let mut n := x
    let mut acc : List Char := []
    while n != 0 do
      acc := base58Char (n % 58) :: acc
      n := n / 58
    return acc

/-- Encode exact 32-byte key to canonical base58 (leading zero bytes → leading `1`). -/
def toBase58 (key : SolanaPubkeyV1) : String :=
  let bytes := key.bytes
  let zeros := countLeadingZeroBytes bytes
  let n := bytesToNatBE bytes
  let body := natToBase58Body n
  String.ofList (List.replicate zeros '1' ++ body)

private def countLeadingOnes (chars : List Char) : Nat :=
  match chars with
  | [] => 0
  | c :: rest => if c == '1' then countLeadingOnes rest + 1 else 0

/-- Strict canonical base58 → exact-32-byte key.
    Rules: ASCII alphabet only, input length ≤ 44, decoded size exact 32,
    re-encode identity (canonical form). -/
def parseBase58 (input : String) : Except String SolanaPubkeyV1 := do
  if input.isEmpty then
    throw "base58 pubkey must be non-empty"
  if input.length > 44 then
    throw "base58 pubkey length must be ≤ 44"
  let chars := input.toList
  let mut n : Nat := 0
  for c in chars do
    match base58Index? c with
    | none => throw "base58 pubkey contains non-alphabet character"
    | some d => n := n * 58 + d
  let leadingOnes := countLeadingOnes chars
  if leadingOnes > 32 then
    throw "base58 pubkey decoded size is not exact 32"
  let width := 32 - leadingOnes
  let payload ← match natToExactBytesBE n width with
    | some bs => pure bs
    | none => throw "base58 pubkey decoded size is not exact 32"
  let mut raw := ByteArray.empty
  for _ in [0:leadingOnes] do
    raw := raw.push 0
  for i in [0:payload.size] do
    raw := raw.push payload[i]!
  unless raw.size == 32 do
    throw "base58 pubkey decoded size is not exact 32"
  let key : SolanaPubkeyV1 := ⟨raw⟩
  unless toBase58 key == input do
    throw "base58 pubkey is not canonical"
  pure key

end SolanaPubkeyV1

/-! ## Closed account policy model -/

inductive OwnerPolicy where
  | currentProgram
  | fixedProgram (packageId : String)
  | catalogExecutionClass
  | any
  | closedPackages (packages : Array String)
  deriving BEq, Repr

inductive ExecutablePolicy where
  | required
  | forbidden
  deriving BEq, Repr

/-- Closed data predicates from the extension account contract. -/
inductive DataPolicy where
  | notRead
  | exactLength (bytes : Nat) (lamports : Option Nat := none)
  | proofForgeState
  | exactCounter (bytes : Nat := 8)
  | classicTokenAccount
      (bytes : Nat)
      (state : String)
      (mintEqualsArg : Option String := none)
      (ownerEqualsArg : Option String := none)
      (delegate : Option String := none)
  | classicTokenMint
      (bytes : Nat)
      (state : String)
      (decimalsEqualsArg : Option String := none)
  /-- ATA pre-state closed alternatives (uninit system OR classic token account). -/
  | ataAccount
      (mintEqualsArg : String)
      (ownerEqualsArg : String)
  | catalogProgram
  deriving BEq, Repr

inductive InitializationPolicy where
  | initializerUninitializedOtherwiseInitialized
  | initialized
  | uninitialized
  | existing
  | any
  | canonicalPda
  | catalogPackageAdmitted
  | uninitializedOrIdempotentlyInitialized
  deriving BEq, Repr

/-- How an account may be provisioned by a frozen API (static contract label). -/
inductive ProvisioningPolicy where
  | none
  | mustExist
  | systemCreateAccount
  | ataCreateIdempotent
  deriving BEq, Repr

/-- Frozen outer-role / CPI-meta alias rules (product v1). -/
structure AliasPolicy where
  outerRoleKeys : String
  cpiSiteMetaKeys : String
  sameRoleAcrossCpiSites : String
  separateRolesAcrossCpiSites : String
  deriving BEq, Repr

def frozenAliasPolicyV1 : AliasPolicy where
  outerRoleKeys := "pairwise-distinct"
  cpiSiteMetaKeys := "pairwise-distinct"
  sameRoleAcrossCpiSites := "allowed-and-reused"
  separateRolesAcrossCpiSites := "must-remain-distinct"

structure AccountConstraint where
  owner : OwnerPolicy
  executable : ExecutablePolicy
  data : DataPolicy
  initialization : InitializationPolicy
  provisioning : ProvisioningPolicy
  deriving BEq, Repr

/-! ## Frozen callee packages -/

inductive ExecutionClass where
  | loaderV3Sbpf
  | nativeSystem
  deriving BEq, Repr

/-- Historical #114–#124 artifact binding closed set.
    Active #125 product packages use `ActiveArtifactBindingV1`, which adds the
    package-owned loader-v3 ELF constructor without widening this inductive
    (so preactivation match sites stay exhaustive on absent/runtimeNative). -/
inductive ArtifactBinding where
  | absent
  | runtimeNative (agaveCommit : String)
  deriving BEq, Repr

/-- Package-owned immutable loader-v3 ELF binding for #125 active catalog. -/
structure LoaderV3ElfBindingV1 where
  relativePath : String
  sizeBytes : Nat
  contentSha256 : String
  sourceRepo : String
  sourceTag : String
  tagObject : String
  peeledCommit : String
  buildRecipeDigest : String
  deriving BEq, Repr

/-- #125 active artifact binding closed set: historical kinds plus loader-v3 ELF.
    System never fabricates an ELF (runtimeNative only). companion stays absent. -/
inductive ActiveArtifactBindingV1 where
  | absent
  | runtimeNative (agaveCommit : String)
  | loaderV3Elf (elf : LoaderV3ElfBindingV1)
  deriving BEq, Repr

structure FrozenCalleePackage where
  packageId : String
  programId : SolanaPubkeyV1
  executionClass : ExecutionClass
  admittedForMaterialization : Bool
  artifactBinding : ArtifactBinding
  /-- Closed QNs owned by this package under the extension surface. -/
  qns : Array String
  deriving BEq, Repr

/-- #125 active callee package row (parallel authority to `FrozenCalleePackage`). -/
structure ActiveCalleePackageV1 where
  packageId : String
  programId : SolanaPubkeyV1
  executionClass : ExecutionClass
  admittedForMaterialization : Bool
  artifactBinding : ActiveArtifactBindingV1
  /-- Closed QNs owned by this package under the extension surface. -/
  qns : Array String
  deriving BEq, Repr

private def hexNibble? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (10 + c.toNat - 'a'.toNat)
  else if 'A' ≤ c && c ≤ 'F' then some (10 + c.toNat - 'A'.toNat)
  else none

/-- Strict hex decoder used by frozen instruction segments and tests. -/
def decodeHexBytesV1 (hex : String) : Except String ByteArray := do
  let chars := hex.toList.toArray
  unless chars.size % 2 == 0 do
    throw "hex payload must contain complete byte pairs"
  let mut out := ByteArray.empty
  let mut i := 0
  while i + 1 < chars.size do
    let high ← match hexNibble? chars[i]! with
      | some nibble => pure nibble
      | none => throw "hex payload contains a non-hex character"
    let low ← match hexNibble? chars[i + 1]! with
      | some nibble => pure nibble
      | none => throw "hex payload contains a non-hex character"
    out := out.push (UInt8.ofNat (high * 16 + low))
    i := i + 2
  pure out

/-- Frozen companion test program id (`0x43` repeated 32 times). -/
def companionProgramIdV1 : SolanaPubkeyV1 :=
  ⟨ByteArray.mk (Array.replicate 32 (0x43 : UInt8))⟩

/-- Native System program id (32 zero bytes). -/
def systemProgramIdV1 : SolanaPubkeyV1 :=
  ⟨ByteArray.mk (Array.replicate 32 (0 : UInt8))⟩

/-- Classic SPL Token program id, raw 32-byte authority from the frozen catalog. -/
def tokenClassicProgramIdV1 : SolanaPubkeyV1 :=
  ⟨ByteArray.mk #[
    0x06, 0xdd, 0xf6, 0xe1, 0xd7, 0x65, 0xa1, 0x93,
    0xd9, 0xcb, 0xe1, 0x46, 0xce, 0xeb, 0x79, 0xac,
    0x1c, 0xb4, 0x85, 0xed, 0x5f, 0x5b, 0x37, 0x91,
    0x3a, 0x8c, 0xf5, 0x85, 0x7e, 0xff, 0x00, 0xa9]⟩

/-- Classic Associated Token Account program id, raw frozen catalog bytes. -/
def ataClassicProgramIdV1 : SolanaPubkeyV1 :=
  ⟨ByteArray.mk #[
    0x8c, 0x97, 0x25, 0x8f, 0x4e, 0x24, 0x89, 0xf1,
    0xbb, 0x3d, 0x10, 0x29, 0x14, 0x8e, 0x0d, 0x83,
    0x0b, 0x5a, 0x13, 0x99, 0xda, 0xff, 0x10, 0x84,
    0x04, 0x8e, 0x7b, 0xd8, 0xdb, 0xe9, 0xf8, 0x59]⟩

/-! ## Loader-owner pubkeys (account.owner of executable programs)

    Exact raw 32-byte authorities from the pinned canonical Solana IDs. Used by
    #118 preflight IR when resolving `OwnerPolicy.catalogExecutionClass` into
    concrete owner-byte checks (not base58 at runtime). -/

/-- Canonical base58 for BPF Loader Upgradeable (Loader V3). -/
def loaderV3OwnerBase58V1 : String :=
  "BPFLoaderUpgradeab1e11111111111111111111111"

/-- Canonical base58 for Native Loader. -/
def nativeLoaderOwnerBase58V1 : String :=
  "NativeLoader1111111111111111111111111111111"

/-- Loader V3 owner pubkey raw bytes
    (`BPFLoaderUpgradeab1e11111111111111111111111` →
    `02a8f6914e88a1b0e210153ef763ae2b00c2b93d16c124d2c0537a1004800000`). -/
def loaderV3OwnerProgramIdV1 : SolanaPubkeyV1 :=
  ⟨ByteArray.mk #[
    0x02, 0xa8, 0xf6, 0x91, 0x4e, 0x88, 0xa1, 0xb0,
    0xe2, 0x10, 0x15, 0x3e, 0xf7, 0x63, 0xae, 0x2b,
    0x00, 0xc2, 0xb9, 0x3d, 0x16, 0xc1, 0x24, 0xd2,
    0xc0, 0x53, 0x7a, 0x10, 0x04, 0x80, 0x00, 0x00]⟩

/-- Native Loader owner pubkey raw bytes
    (`NativeLoader1111111111111111111111111111111` →
    `058784bf148ba4282fb012574888a9f153a07dadf765c0455c9a970380000000`). -/
def nativeLoaderOwnerProgramIdV1 : SolanaPubkeyV1 :=
  ⟨ByteArray.mk #[
    0x05, 0x87, 0x84, 0xbf, 0x14, 0x8b, 0xa4, 0x28,
    0x2f, 0xb0, 0x12, 0x57, 0x48, 0x88, 0xa9, 0xf1,
    0x53, 0xa0, 0x7d, 0xad, 0xf7, 0x65, 0xc0, 0x45,
    0x5c, 0x9a, 0x97, 0x03, 0x80, 0x00, 0x00, 0x00]⟩

/-- Total mapping: catalog execution class → exact loader-owner pubkey bytes. -/
def executionClassOwnerPubkeyV1 : ExecutionClass → SolanaPubkeyV1
  | .loaderV3Sbpf => loaderV3OwnerProgramIdV1
  | .nativeSystem => nativeLoaderOwnerProgramIdV1

/-- Historical #114–#124 preactivation package table (all admitted=false). -/
def frozenCalleePackagesV1 : Array FrozenCalleePackage := #[
  { packageId := "companion-v1"
    programId := companionProgramIdV1
    executionClass := .loaderV3Sbpf
    admittedForMaterialization := false
    artifactBinding := .absent
    qns := #["solana.companion.invoke", "solana.companion.fail",
             "solana.companion.invokeSigned"] },
  { packageId := "system-v1"
    programId := systemProgramIdV1
    executionClass := .nativeSystem
    admittedForMaterialization := false
    artifactBinding := .runtimeNative agaveV400CommitV1
    qns := #["solana.system.transfer", "solana.system.createPdaAccount"] },
  { packageId := "token-classic-v1"
    programId := tokenClassicProgramIdV1
    executionClass := .loaderV3Sbpf
    admittedForMaterialization := false
    artifactBinding := .absent
    qns := #["solana.token.transferChecked", "solana.token.transferCheckedPda"] },
  { packageId := "ata-classic-v1"
    programId := ataClassicProgramIdV1
    executionClass := .loaderV3Sbpf
    admittedForMaterialization := false
    artifactBinding := .absent
    qns := #["solana.ata.createIdempotent"] }
]

def findCalleePackage? (packageId : String) : Option FrozenCalleePackage :=
  frozenCalleePackagesV1.find? (fun p => p.packageId == packageId)

def findCalleePackageByQn? (qn : String) : Option FrozenCalleePackage :=
  frozenCalleePackagesV1.find? (fun p => p.qns.any (· == qn))

/-! ## #125 active product callee packages

    Approved product closure: system-v1 / token-classic-v1 / ata-classic-v1.
    companion-v1 remains admitted=false / absent / test-only (three APIs).
    System is runtimeNative (Agave pin); never fabricates a System ELF.
    Token/ATA bind package-owned immutable loader-v3 ELF assets under
    `supply-chain/solana-cpi-assets/v1/`. -/

def tokenClassicActiveElfPathV1 : String :=
  "supply-chain/solana-cpi-assets/v1/token_classic_v1.so"

def ataClassicActiveElfPathV1 : String :=
  "supply-chain/solana-cpi-assets/v1/ata_classic_v1.so"

def tokenClassicActiveElfSizeV1 : Nat := 94960
def ataClassicActiveElfSizeV1 : Nat := 111136

def tokenClassicActiveElfSha256V1 : String :=
  "a19be3a2d4778533652da23b8fe31c4a341802f8e8c0c7b941b88581fc92d9d9"

def ataClassicActiveElfSha256V1 : String :=
  "d3f6df6f95f8b81c482478cc8c44b67ac3de2ca03162eaaf6c587ee8db646519"

def tokenClassicBuildRecipeDigestV1 : String :=
  "4af75b0a74ba14daa90a2d3913c71311609b3f3465728e733537dd0e34d8d063"

def ataClassicBuildRecipeDigestV1 : String :=
  "f7ebe5236730d66ad730df6348b74332eb95e2abfda3377f389a13022e4528e2"

def tokenClassicSourceRepoV1 : String := "https://github.com/solana-program/token"
def tokenClassicSourceTagV1 : String := "program@v9.0.0"
def tokenClassicTagObjectV1 : String := "5c37ac99c248567bd7d50b965af8cbd45b6ced96"
def tokenClassicPeeledCommitV1 : String :=
  "dfb260231c761be7d9c8b63728e770a102b86495"

def ataClassicSourceRepoV1 : String :=
  "https://github.com/solana-program/associated-token-account"
def ataClassicSourceTagV1 : String := "program@v8.0.0"
def ataClassicTagObjectV1 : String := "de77f367fdc0341879b1b9f0224c6b86107e1769"
def ataClassicPeeledCommitV1 : String :=
  "0b867b5340cd001e5980d8ca7928effc4e10015c"

def tokenClassicLoaderV3ElfBindingV1 : LoaderV3ElfBindingV1 where
  relativePath := tokenClassicActiveElfPathV1
  sizeBytes := tokenClassicActiveElfSizeV1
  contentSha256 := tokenClassicActiveElfSha256V1
  sourceRepo := tokenClassicSourceRepoV1
  sourceTag := tokenClassicSourceTagV1
  tagObject := tokenClassicTagObjectV1
  peeledCommit := tokenClassicPeeledCommitV1
  buildRecipeDigest := tokenClassicBuildRecipeDigestV1

def ataClassicLoaderV3ElfBindingV1 : LoaderV3ElfBindingV1 where
  relativePath := ataClassicActiveElfPathV1
  sizeBytes := ataClassicActiveElfSizeV1
  contentSha256 := ataClassicActiveElfSha256V1
  sourceRepo := ataClassicSourceRepoV1
  sourceTag := ataClassicSourceTagV1
  tagObject := ataClassicTagObjectV1
  peeledCommit := ataClassicPeeledCommitV1
  buildRecipeDigest := ataClassicBuildRecipeDigestV1

/-- #125 active package table (catalog version 1.1.0 authority). -/
def activeCalleePackagesV1 : Array ActiveCalleePackageV1 := #[
  { packageId := "companion-v1"
    programId := companionProgramIdV1
    executionClass := .loaderV3Sbpf
    admittedForMaterialization := false
    artifactBinding := .absent
    qns := #["solana.companion.invoke", "solana.companion.fail",
             "solana.companion.invokeSigned"] },
  { packageId := "system-v1"
    programId := systemProgramIdV1
    executionClass := .nativeSystem
    admittedForMaterialization := true
    artifactBinding := .runtimeNative agaveV400CommitV1
    qns := #["solana.system.transfer", "solana.system.createPdaAccount"] },
  { packageId := "token-classic-v1"
    programId := tokenClassicProgramIdV1
    executionClass := .loaderV3Sbpf
    admittedForMaterialization := true
    artifactBinding := .loaderV3Elf tokenClassicLoaderV3ElfBindingV1
    qns := #["solana.token.transferChecked", "solana.token.transferCheckedPda"] },
  { packageId := "ata-classic-v1"
    programId := ataClassicProgramIdV1
    executionClass := .loaderV3Sbpf
    admittedForMaterialization := true
    artifactBinding := .loaderV3Elf ataClassicLoaderV3ElfBindingV1
    qns := #["solana.ata.createIdempotent"] }
]

def findActiveCalleePackage? (packageId : String) : Option ActiveCalleePackageV1 :=
  activeCalleePackagesV1.find? (fun p => p.packageId == packageId)

def findActiveCalleePackageByQn? (qn : String) : Option ActiveCalleePackageV1 :=
  activeCalleePackagesV1.find? (fun p => p.qns.any (· == qn))

/-- Approved product package ids (companion excluded). -/
def activeProductPackageIdsV1 : Array String :=
  #["system-v1", "token-classic-v1", "ata-classic-v1"]

/-- Approved product QN closure (five APIs; companion three remain test-only). -/
def activeProductApiQnsV1 : Array String := #[
  "solana.system.transfer",
  "solana.system.createPdaAccount",
  "solana.token.transferChecked",
  "solana.token.transferCheckedPda",
  "solana.ata.createIdempotent"
]

/-- Exact structural validation of the #125 active package table. -/
def validateActiveCalleePackagesV1 : Except String Unit := do
  unless activeCalleePackagesV1.size == 4 do
    throw "activeCalleePackagesV1 must contain exactly four packages"
  let expectedIds := #["companion-v1", "system-v1", "token-classic-v1", "ata-classic-v1"]
  let mut i : Nat := 0
  while i < expectedIds.size do
    match activeCalleePackagesV1[i]?, expectedIds[i]? with
    | some pkg, some expectedId =>
        unless pkg.packageId == expectedId do
          throw s!"active package order mismatch at {i}"
    | _, _ => throw s!"active package index out of range at {i}"
    i := i + 1
  let companion ← match findActiveCalleePackage? "companion-v1" with
    | some p => pure p
    | none => throw "missing companion-v1"
  unless companion.admittedForMaterialization == false do
    throw "companion-v1 must remain admittedForMaterialization=false"
  match companion.artifactBinding with
  | .absent => pure ()
  | .runtimeNative _ => throw "companion-v1 must keep artifactBinding.absent"
  | .loaderV3Elf _ => throw "companion-v1 must keep artifactBinding.absent"
  unless companion.qns.size == 3 do
    throw "companion-v1 must retain three test-only APIs"
  let system ← match findActiveCalleePackage? "system-v1" with
    | some p => pure p
    | none => throw "missing system-v1"
  unless system.admittedForMaterialization == true do
    throw "system-v1 must be admitted for materialization"
  match system.artifactBinding with
  | .runtimeNative commit =>
      unless commit == agaveV400CommitV1 do
        throw "system-v1 runtimeNative must pin Agave v4.0.0 commit"
  | .absent => throw "system-v1 must be runtimeNative (no System ELF)"
  | .loaderV3Elf _ => throw "system-v1 must not fabricate a System ELF"
  unless system.executionClass == .nativeSystem do
    throw "system-v1 must remain nativeSystem"
  unless system.qns.size == 2 do
    throw "system-v1 must expose two APIs"
  let token ← match findActiveCalleePackage? "token-classic-v1" with
    | some p => pure p
    | none => throw "missing token-classic-v1"
  unless token.admittedForMaterialization == true do
    throw "token-classic-v1 must be admitted for materialization"
  match token.artifactBinding with
  | .loaderV3Elf elf =>
      unless elf == tokenClassicLoaderV3ElfBindingV1 do
        throw "token-classic-v1 loader-v3 ELF binding pin mismatch"
  | .absent => throw "token-classic-v1 must bind loader-v3 ELF"
  | .runtimeNative _ => throw "token-classic-v1 must bind loader-v3 ELF"
  unless token.qns.size == 2 do
    throw "token-classic-v1 must expose two APIs"
  let ata ← match findActiveCalleePackage? "ata-classic-v1" with
    | some p => pure p
    | none => throw "missing ata-classic-v1"
  unless ata.admittedForMaterialization == true do
    throw "ata-classic-v1 must be admitted for materialization"
  match ata.artifactBinding with
  | .loaderV3Elf elf =>
      unless elf == ataClassicLoaderV3ElfBindingV1 do
        throw "ata-classic-v1 loader-v3 ELF binding pin mismatch"
  | .absent => throw "ata-classic-v1 must bind loader-v3 ELF"
  | .runtimeNative _ => throw "ata-classic-v1 must bind loader-v3 ELF"
  unless ata.qns.size == 1 do
    throw "ata-classic-v1 must expose one API"
  -- Every product QN resolves to an admitted active package.
  for qn in activeProductApiQnsV1 do
    match findActiveCalleePackageByQn? qn with
    | none => throw s!"product QN '{qn}' missing from active packages"
    | some p =>
        unless p.admittedForMaterialization do
          throw s!"product QN '{qn}' package is not admitted"
        unless activeProductPackageIdsV1.any (· == p.packageId) do
          throw s!"product QN '{qn}' is outside approved product closure"
  -- Companion QNs remain resolvable but not product-admitted.
  for qn in #["solana.companion.invoke", "solana.companion.fail",
              "solana.companion.invokeSigned"] do
    match findActiveCalleePackageByQn? qn with
    | none => throw s!"companion QN '{qn}' missing"
    | some p =>
        unless p.packageId == "companion-v1" do
          throw s!"companion QN '{qn}' bound to wrong package"
        unless p.admittedForMaterialization == false do
          throw s!"companion QN '{qn}' must not be product-admitted"
  pure ()

/-! ## Typed frozen API projection -/

inductive FrozenValueType where
  | principal
  | uint64
  | uint8
  | unit
  deriving BEq, Repr

inductive ArgumentSource where
  | bareDirectPublicPrincipalParameter
  | typedExpression
  | literalConstantOrBareDirectPublicUInt64Parameter
  | literalConstantOrBareDirectPublicUInt8Parameter
  deriving BEq, Repr

structure FrozenArgSpec where
  name : String
  type_ : FrozenValueType
  source : ArgumentSource
  deriving BEq, Repr

inductive InstructionEncoding where
  | uint64Le
  | uint8
  deriving BEq, Repr

inductive InstructionSegment where
  /-- Lowercase hex payload bytes from the extension codec (e.g. `00`, `02000000`). -/
  | hex (hex : String)
  | arg (name : String) (encoding : InstructionEncoding)
  | fixedCurrentProgramId32
  deriving BEq, Repr

namespace InstructionSegment

/-- Decode a `.hex` segment to raw bytes; non-hex constructors are rejected
    rather than silently producing an empty payload. -/
def hexBytes : InstructionSegment → Except String ByteArray
  | .hex h => decodeHexBytesV1 h
  | .arg _ _ => throw "instruction segment is argument-derived, not hex"
  | .fixedCurrentProgramId32 =>
      throw "instruction segment is current-program-id-derived, not hex"

end InstructionSegment

structure InstructionCodec where
  length : Nat
  segments : Array InstructionSegment
  deriving BEq, Repr

inductive MetaBinding where
  | arg (name : String)
  | fixedProgram (packageId : String)
  deriving BEq, Repr

structure FrozenMetaSpec where
  binding : MetaBinding
  constraint : AccountConstraint
  cpiSigner : Bool
  cpiWritable : Bool
  outerSignerContribution : Bool
  outerWritableContribution : Bool
  signerGroupId : Option Nat := none
  deriving BEq, Repr

structure FrozenOuterOnlySpec where
  arg : String
  constraint : AccountConstraint
  outerSignerContribution : Bool
  outerWritableContribution : Bool
  deriving BEq, Repr

inductive FrozenPdaUse where
  | none
  | signer
      (rule : String)
      (targetArg : String)
      (seedAuthorityArg : String)
      (seedTagArg : String)
      (bumpArg : String)
      (signerArg : String)
  | addressCheckOnly
      (rule : String)
      (targetArg : String)
      (walletArg : String)
      (mintArg : String)
  deriving BEq, Repr

structure FrozenSignerGroup where
  id : Nat
  metaArg : String
  pdaRule : String
  deriving BEq, Repr

/-- Closed preflight predicate surface from the extension API contract. -/
inductive PreflightPredicateV1 where
  /-- `argName` as UInt64 must be ≤ `value` (exact product-cap bound). -/
  | uint64AtMost (argName : String) (value : Nat)
  deriving BEq, Repr

/-- Frozen preflight row; currently identical to the closed predicate carrier. -/
abbrev FrozenPreflightSpecV1 := PreflightPredicateV1

structure FrozenApi where
  qn : String
  args : Array FrozenArgSpec
  fixedProgram : String
  instructionCodec : InstructionCodec
  metas : Array FrozenMetaSpec
  outerOnlyAccounts : Array FrozenOuterOnlySpec
  pda : FrozenPdaUse
  signerGroups : Array FrozenSignerGroup
  preflight : Array FrozenPreflightSpecV1
  result : FrozenValueType
  deriving BEq, Repr

/-! ### Shared constraint helpers (deterministic; not product authorities) -/

private def constraintCatalogProgram : AccountConstraint where
  owner := .catalogExecutionClass
  executable := .required
  data := .catalogProgram
  initialization := .catalogPackageAdmitted
  provisioning := .mustExist

private def constraintNotReadAny : AccountConstraint where
  owner := .any
  executable := .forbidden
  data := .notRead
  initialization := .any
  provisioning := .mustExist

private def constraintCanonicalPdaAny : AccountConstraint where
  owner := .any
  executable := .forbidden
  data := .notRead
  initialization := .canonicalPda
  provisioning := .mustExist

private def constraintCompanionCounter : AccountConstraint where
  owner := .fixedProgram "companion-v1"
  executable := .forbidden
  data := .exactCounter 8
  initialization := .initialized
  provisioning := .mustExist

private def constraintSystemPayer : AccountConstraint where
  owner := .fixedProgram "system-v1"
  executable := .forbidden
  data := .exactLength 0
  initialization := .existing
  provisioning := .mustExist

private def constraintSystemCreateTarget : AccountConstraint where
  owner := .fixedProgram "system-v1"
  executable := .forbidden
  data := .exactLength 0 (lamports := some 0)
  initialization := .uninitialized
  provisioning := .systemCreateAccount

private def constraintClassicMint (decimalsArg : Option String) : AccountConstraint where
  owner := .fixedProgram "token-classic-v1"
  executable := .forbidden
  data := .classicTokenMint 82 "initialized" decimalsArg
  initialization := .initialized
  provisioning := .mustExist

private def constraintClassicTokenAccount
    (mintArg : Option String) (ownerArg : Option String) (withDelegateNone : Bool) :
    AccountConstraint where
  owner := .fixedProgram "token-classic-v1"
  executable := .forbidden
  data := .classicTokenAccount 165 "initialized-not-frozen" mintArg ownerArg
      (if withDelegateNone then some "none" else none)
  initialization := .initialized
  provisioning := .mustExist

private def constraintAtaTarget (mintArg ownerArg : String) : AccountConstraint where
  owner := .closedPackages #["system-v1", "token-classic-v1"]
  executable := .forbidden
  data := .ataAccount mintArg ownerArg
  initialization := .uninitializedOrIdempotentlyInitialized
  provisioning := .ataCreateIdempotent

private def principalArg (name : String) : FrozenArgSpec :=
  { name, type_ := .principal, source := .bareDirectPublicPrincipalParameter }

private def exprU64 (name : String) : FrozenArgSpec :=
  { name, type_ := .uint64, source := .typedExpression }

private def exprU8 (name : String) : FrozenArgSpec :=
  { name, type_ := .uint8, source := .typedExpression }

private def litOrParamU64 (name : String) : FrozenArgSpec :=
  { name, type_ := .uint64
    source := .literalConstantOrBareDirectPublicUInt64Parameter }

private def litOrParamU8 (name : String) : FrozenArgSpec :=
  { name, type_ := .uint8
    source := .literalConstantOrBareDirectPublicUInt8Parameter }

private def hexSeg (hex : String) : InstructionSegment :=
  .hex hex

private def metaArg
    (name : String) (constraint : AccountConstraint)
    (cpiSigner cpiWritable outerSigner outerWritable : Bool)
    (signerGroupId : Option Nat := none) : FrozenMetaSpec :=
  { binding := .arg name
    constraint
    cpiSigner
    cpiWritable
    outerSignerContribution := outerSigner
    outerWritableContribution := outerWritable
    signerGroupId }

private def metaFixed
    (packageId : String) (constraint : AccountConstraint) : FrozenMetaSpec :=
  { binding := .fixedProgram packageId
    constraint
    cpiSigner := false
    cpiWritable := false
    outerSignerContribution := false
    outerWritableContribution := false
    signerGroupId := none }

private def outerOnly
    (arg : String) (constraint : AccountConstraint)
    (outerSigner outerWritable : Bool) : FrozenOuterOnlySpec :=
  { arg, constraint
    outerSignerContribution := outerSigner
    outerWritableContribution := outerWritable }

private def currentProgramPdaSigner
    (targetArg seedAuthorityArg seedTagArg bumpArg signerArg : String) :
    FrozenPdaUse :=
  .signer "current-program-tagged-v1" targetArg seedAuthorityArg seedTagArg
    bumpArg signerArg

/-! ### Eight frozen APIs (extension JCS order) -/

def apiCompanionInvokeV1 : FrozenApi where
  qn := "solana.companion.invoke"
  args := #[principalArg "account", exprU64 "delta"]
  fixedProgram := "companion-v1"
  instructionCodec := { length := 9, segments := #[hexSeg "00", .arg "delta" .uint64Le] }
  metas := #[
    metaArg "account" constraintCompanionCounter false true false true
  ]
  outerOnlyAccounts := #[]
  pda := .none
  signerGroups := #[]
  preflight := #[]
  result := .unit

def apiCompanionFailV1 : FrozenApi where
  qn := "solana.companion.fail"
  args := #[principalArg "account", exprU64 "delta"]
  fixedProgram := "companion-v1"
  instructionCodec := { length := 9, segments := #[hexSeg "01", .arg "delta" .uint64Le] }
  metas := #[
    metaArg "account" constraintCompanionCounter false true false true
  ]
  outerOnlyAccounts := #[]
  pda := .none
  signerGroups := #[]
  preflight := #[]
  result := .unit

def apiCompanionInvokeSignedV1 : FrozenApi where
  qn := "solana.companion.invokeSigned"
  args := #[
    principalArg "account", principalArg "authorityPda", principalArg "seedAuthority",
    litOrParamU64 "seedTag", litOrParamU8 "bump", exprU64 "delta"
  ]
  fixedProgram := "companion-v1"
  instructionCodec := { length := 9, segments := #[hexSeg "02", .arg "delta" .uint64Le] }
  metas := #[
    metaArg "account" constraintCompanionCounter false true false true,
    metaArg "authorityPda" constraintCanonicalPdaAny true false false false (some 0)
  ]
  outerOnlyAccounts := #[
    outerOnly "seedAuthority" constraintNotReadAny true false
  ]
  pda := currentProgramPdaSigner "authorityPda" "seedAuthority" "seedTag" "bump"
    "authorityPda"
  signerGroups := #[{ id := 0, metaArg := "authorityPda",
                      pdaRule := "current-program-tagged-v1" }]
  preflight := #[]
  result := .unit

def apiSystemTransferV1 : FrozenApi where
  qn := "solana.system.transfer"
  args := #[principalArg "payer", principalArg "recipient", exprU64 "lamports"]
  fixedProgram := "system-v1"
  instructionCodec := {
    length := 12
    segments := #[hexSeg "02000000", .arg "lamports" .uint64Le]
  }
  metas := #[
    metaArg "payer" constraintSystemPayer true true true true,
    metaArg "recipient" constraintNotReadAny false true false true
  ]
  outerOnlyAccounts := #[]
  pda := .none
  signerGroups := #[]
  preflight := #[]
  result := .unit

def apiSystemCreatePdaAccountV1 : FrozenApi where
  qn := "solana.system.createPdaAccount"
  args := #[
    principalArg "payer", principalArg "pda", principalArg "seedAuthority",
    litOrParamU64 "seedTag", litOrParamU8 "bump",
    exprU64 "lamports", exprU64 "space"
  ]
  fixedProgram := "system-v1"
  instructionCodec := {
    length := 52
    segments := #[
      hexSeg "00000000",
      .arg "lamports" .uint64Le,
      .arg "space" .uint64Le,
      .fixedCurrentProgramId32
    ]
  }
  metas := #[
    metaArg "payer" constraintSystemPayer true true true true,
    metaArg "pda" constraintSystemCreateTarget true true false true (some 0)
  ]
  outerOnlyAccounts := #[
    outerOnly "seedAuthority" constraintNotReadAny false false
  ]
  pda := currentProgramPdaSigner "pda" "seedAuthority" "seedTag" "bump" "pda"
  signerGroups := #[{ id := 0, metaArg := "pda",
                      pdaRule := "current-program-tagged-v1" }]
  preflight := #[.uint64AtMost "space" maxPdaSpaceBytesV1]
  result := .unit

def apiTokenTransferCheckedV1 : FrozenApi where
  qn := "solana.token.transferChecked"
  args := #[
    principalArg "source", principalArg "mint", principalArg "destination",
    principalArg "authority", exprU64 "amount", exprU8 "decimals"
  ]
  fixedProgram := "token-classic-v1"
  instructionCodec := {
    length := 10
    segments := #[hexSeg "0c", .arg "amount" .uint64Le, .arg "decimals" .uint8]
  }
  metas := #[
    metaArg "source"
      (constraintClassicTokenAccount (some "mint") (some "authority") true)
      false true false true,
    metaArg "mint" (constraintClassicMint (some "decimals")) false false false false,
    metaArg "destination"
      (constraintClassicTokenAccount (some "mint") none false)
      false true false true,
    metaArg "authority" constraintNotReadAny true false true false
  ]
  outerOnlyAccounts := #[]
  pda := .none
  signerGroups := #[]
  preflight := #[]
  result := .unit

def apiTokenTransferCheckedPdaV1 : FrozenApi where
  qn := "solana.token.transferCheckedPda"
  args := #[
    principalArg "source", principalArg "mint", principalArg "destination",
    principalArg "authorityPda", principalArg "seedAuthority",
    litOrParamU64 "seedTag", litOrParamU8 "bump",
    exprU64 "amount", exprU8 "decimals"
  ]
  fixedProgram := "token-classic-v1"
  instructionCodec := {
    length := 10
    segments := #[hexSeg "0c", .arg "amount" .uint64Le, .arg "decimals" .uint8]
  }
  metas := #[
    metaArg "source"
      (constraintClassicTokenAccount (some "mint") (some "authorityPda") true)
      false true false true,
    metaArg "mint" (constraintClassicMint (some "decimals")) false false false false,
    metaArg "destination"
      (constraintClassicTokenAccount (some "mint") none false)
      false true false true,
    metaArg "authorityPda" constraintCanonicalPdaAny true false false false (some 0)
  ]
  outerOnlyAccounts := #[
    outerOnly "seedAuthority" constraintNotReadAny true false
  ]
  pda := currentProgramPdaSigner "authorityPda" "seedAuthority" "seedTag" "bump"
    "authorityPda"
  signerGroups := #[{ id := 0, metaArg := "authorityPda",
                      pdaRule := "current-program-tagged-v1" }]
  preflight := #[]
  result := .unit

def apiAtaCreateIdempotentV1 : FrozenApi where
  qn := "solana.ata.createIdempotent"
  args := #[
    principalArg "payer", principalArg "ata",
    principalArg "wallet", principalArg "mint"
  ]
  fixedProgram := "ata-classic-v1"
  instructionCodec := { length := 1, segments := #[hexSeg "01"] }
  metas := #[
    metaArg "payer" constraintSystemPayer true true true true,
    metaArg "ata" (constraintAtaTarget "mint" "wallet") false true false true,
    metaArg "wallet" constraintNotReadAny false false false false,
    metaArg "mint" (constraintClassicMint none) false false false false,
    metaFixed "system-v1" constraintCatalogProgram,
    metaFixed "token-classic-v1" constraintCatalogProgram
  ]
  outerOnlyAccounts := #[]
  pda := .addressCheckOnly "ata-classic-v1" "ata" "wallet" "mint"
  signerGroups := #[]
  preflight := #[]
  result := .unit

/-- Extension-order frozen API table (deterministic). -/
def frozenApisV1 : Array FrozenApi := #[
  apiCompanionInvokeV1,
  apiCompanionFailV1,
  apiCompanionInvokeSignedV1,
  apiSystemTransferV1,
  apiSystemCreatePdaAccountV1,
  apiTokenTransferCheckedV1,
  apiTokenTransferCheckedPdaV1,
  apiAtaCreateIdempotentV1
]

def findFrozenApi? (qn : String) : Option FrozenApi :=
  frozenApisV1.find? (fun api => api.qn == qn)

def frozenApiQnsV1 : Array String :=
  frozenApisV1.map (·.qn)

/-! ## Frozen PDA rule templates -/

inductive SeedTemplate where
  | literalHex (hex : String)
  | accountKey (argName : String)
  | fixedProgramId (packageId : String)
  | uint64Le (argName : String)
  | uint8 (argName : String)
  deriving BEq, Repr

inductive DerivationProgram where
  | currentProgram
  | fixedPackage (packageId : String)
  deriving BEq, Repr

inductive BumpSearchPolicy where
  /-- Caller supplies bump; must equal first off-curve result of 255..1. -/
  | providedBumpMustEqualCanonical255Through1
  /-- Derive canonical bump via 255..1 search (ATA address check). -/
  | canonical255Through1
  deriving BEq, Repr

structure FrozenPdaRule where
  ruleId : String
  derivationProgram : DerivationProgram
  seeds : Array SeedTemplate
  search : BumpSearchPolicy
  signerEligible : Bool
  deriving BEq, Repr

def frozenPdaRuleCurrentProgramTaggedV1 : FrozenPdaRule where
  ruleId := "current-program-tagged-v1"
  derivationProgram := .currentProgram
  seeds := #[
    .literalHex currentProgramPdaTagHexV1,
    .accountKey "seedAuthority",
    .uint64Le "seedTag",
    .uint8 "bump"
  ]
  search := .providedBumpMustEqualCanonical255Through1
  signerEligible := true

def frozenPdaRuleAtaClassicV1 : FrozenPdaRule where
  ruleId := "ata-classic-v1"
  derivationProgram := .fixedPackage "ata-classic-v1"
  seeds := #[
    .accountKey "wallet",
    .fixedProgramId "token-classic-v1",
    .accountKey "mint"
  ]
  search := .canonical255Through1
  signerEligible := false

/-- Exact frozen PDA rule templates (product v1). -/
def frozenPdaRulesV1 : Array FrozenPdaRule := #[
  frozenPdaRuleCurrentProgramTaggedV1,
  frozenPdaRuleAtaClassicV1
]

def findFrozenPdaRule? (ruleId : String) : Option FrozenPdaRule :=
  frozenPdaRulesV1.find? (fun r => r.ruleId == ruleId)

/-- State-role constraint template from the extension account contract. -/
def stateRoleConstraintV1 : AccountConstraint where
  owner := .currentProgram
  executable := .forbidden
  data := .proofForgeState
  initialization := .initializerUninitializedOtherwiseInitialized
  provisioning := .mustExist

/-- Generic global schema for a direct public Principal parameter that becomes
    account-bound only under this Solana profile. Site-local frozen constraints
    remain stricter and are carried by each meta/outer-only use. -/
def accountBoundRoleConstraintV1 : AccountConstraint := constraintNotReadAny

/-- Callee-role constraint shared by all eight fixed-program APIs. -/
def calleeRoleConstraintV1 : AccountConstraint := constraintCatalogProgram

end ProofForgeV2.Targets.Solana.CpiV1
