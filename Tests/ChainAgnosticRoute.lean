/-
Chain-agnostic gap-analysis route steps 2–7 smoke:
Identity, sync-subset crosscall + Solana account inference, TokenAuth + FixedPoint,
upgrade lifecycle, PortableMechanics honesty.
-/
import ProofForge.Target.Identity
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Target.PortableMechanics
import ProofForge.Target.HostRuntime
import ProofForge.Contract.Token
import ProofForge.Contract.TokenAuth
import ProofForge.Contract.FixedPoint
import ProofForge.Contract.UpgradePolicy
import ProofForge.Contract.UpgradePolicy.Lower
import ProofForge.Contract.Spec
import ProofForge.Contract.Intent
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Target.Preflight
import ProofForge.Target.PortableHonesty
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.Backend.Solana.PortableCrosscall
import ProofForge.Backend.Solana.Manifest

namespace ProofForge.Tests.ChainAgnosticRoute

open ProofForge.Target
open ProofForge.Target.Identity
open ProofForge.Target.CrosscallMaterialize
open ProofForge.Target.PortableMechanics
open ProofForge.Target.HostRuntime
open ProofForge.Target.PortableHonesty
open ProofForge.Target.Preflight
open ProofForge.Contract.Token
open ProofForge.Contract.TokenAuth
open ProofForge.Contract.FixedPoint
open ProofForge.Contract
open ProofForge.Contract.UpgradePolicy
open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

/-- Minimal portable module: one state scalar + empty entry (for account inference). -/
def sampleModule : Module := {
  name := "ChainAgnosticProbe"
  state := #[{ id := "vault", kind := .scalar, type := .u64 }]
  entrypoints := #[{ name := "touch", body := #[] }]
}

/-- Module that uses NEAR async escape hatch (must fail requireSyncSubset). -/
def nearAsyncModule : Module := {
  name := "NearAsyncEscape"
  state := #[]
  entrypoints := #[{
    name := "cb"
    body := #[.return (.nearPromiseResultsCount)]
  }]
}

def main : IO UInt32 := do
  ---------------------------------------------------------------------------
  -- Step 2: Identity
  ---------------------------------------------------------------------------
  require (encodingForTarget "evm" == .evmAddress20) "evm encoding"
  require (encodingForTarget "solana-sbpf-asm" == .solanaPubkey32) "sol encoding"
  require (encodingForTarget "wasm-near" == .nearAccountId) "near encoding"
  match materializeIdentity "evm" .caller with
  | .error msg => throw (IO.userError s!"evm caller: {msg}")
  | .ok m =>
      require (m.byteWidth? == some 20) "evm caller width 20"
      require (m.hostSymbol? == some "caller") "evm caller symbol"
  match materializeIdentity "solana-sbpf-asm" .caller with
  | .error msg => throw (IO.userError s!"sol caller: {msg}")
  | .ok m => require (m.byteWidth? == some 32) "sol caller width 32"
  match materializeIdentity "wasm-near" .caller with
  | .error msg => throw (IO.userError s!"near caller: {msg}")
  | .ok m =>
      require (m.byteWidth?.isNone) "near caller variable width"
      require (m.hostSymbol? == some "env.predecessor_account_id") "near caller host"
  match materializeIdentity "solana-sbpf-asm" .self with
  | .error msg => throw (IO.userError s!"sol self must ok after U1.2: {msg}")
  | .ok m =>
      require (m.byteWidth? == some 32) "sol self width 32"
      require (m.hostSymbol? == some "program_id") "sol self host program_id"
  match materializeIdentity "wasm-near" .self with
  | .error msg => throw (IO.userError s!"near self: {msg}")
  | .ok m => require (m.hostSymbol? == some "env.current_account_id") "near self"
  match materializeIdentity "unknown-target" .caller with
  | .ok _ => throw (IO.userError "unknown target must reject")
  | .error msg => require (contains msg "Identity") "unknown names Identity"
  require (portableTypeName == "Address") "portable type Address"
  require (ValueType.address.name == "Address") "IR ValueType.address"

  ---------------------------------------------------------------------------
  -- Step 3: Sync-subset crosscall + Solana account inference
  ---------------------------------------------------------------------------
  require (portableCrosscallPolicy == .syncRequestResponseOnly) "policy locked"
  match requireSyncSubset sampleModule with
  | .error msg => throw (IO.userError s!"sample should pass sync subset: {msg}")
  | .ok () => pure ()
  match requireSyncSubset nearAsyncModule with
  | .ok () => throw (IO.userError "near async module must fail requireSyncSubset")
  | .error msg =>
      require (contains msg "CrosscallMaterialize") "async reject names module"
      require (contains msg "sync-subset" || contains msg "promise") "async reject mentions policy"
  match materializeSyncRemote "evm" sampleModule "0xpeer" with
  | .error msg => throw (IO.userError s!"evm sync remote: {msg}")
  | .ok m =>
      require (m.nativeForm == .evmCall) "evm form"
      require (m.inferredAccounts?.isNone) "evm no account metas"
  match materializeSyncRemote "solana-sbpf-asm" sampleModule
      "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" with
  | .error msg => throw (IO.userError s!"sol sync remote: {msg}")
  | .ok m =>
      require (m.nativeForm == .solanaCpi) "sol form"
      match m.inferredAccounts? with
      | none => throw (IO.userError "sol must infer accounts")
      | some accs =>
          require (accs.size >= 3) s!"sol inferred ≥3 accounts, got {accs.size}"
          require (accs.any (fun a => a.name == "payer" && a.signer)) "sol payer signer"
          require (accs.any (fun a => a.name == "vault")) "sol includes state vault"
          require (accs.any (fun a => a.name == "token_program"))
            "sol token program for SPL peer"
  match inferSolanaAccounts sampleModule "" with
  | .ok _ => throw (IO.userError "empty peer must fail inference")
  | .error msg =>
      require (contains msg "infer") "empty peer diagnostic"
      require (contains msg "peer") "empty peer names peer"
  match materializeSyncRemote "wasm-near" sampleModule "alice.near" with
  | .error msg => throw (IO.userError s!"near sync remote: {msg}")
  | .ok m =>
      require (m.nativeForm == .nearPromise) "near form"
      require (contains m.asyncSupport "promise") "near promise-create-only"
  match materializeSyncRemote "wasm-near" nearAsyncModule "alice.near" with
  | .ok _ => throw (IO.userError "near async module remote must reject")
  | .error msg => require (contains msg "CrosscallMaterialize") "near async remote reject"

  ---------------------------------------------------------------------------
  -- Step 4: Token core + auth features + FixedPoint
  ---------------------------------------------------------------------------
  -- transfer/balanceOf always full on TokenSpec lanes (no feature required).
  for tid in TokenAuth.primaryTokenTargetIds do
    require (coreOpSupportOnTarget tid .transfer false false == .full)
      s!"transfer full on {tid}"
    require (coreOpSupportOnTarget tid .balanceOf false false == .full)
      s!"balanceOf full on {tid}"
    -- mint/burn capability-gated: reject without mintable/burnable features.
    require (coreOpSupportOnTarget tid .mint false false == .reject)
      s!"mint rejects without mintable on {tid}"
    require (coreOpSupportOnTarget tid .burn false false == .reject)
      s!"burn rejects without burnable on {tid}"
    require (coreOpSupportOnTarget tid .mint true false == .full)
      s!"mint full with mintable on {tid}"
    require (coreOpSupportOnTarget tid .burn false true == .full)
      s!"burn full with burnable on {tid}"
    match materializeCoreOp tid .mint false false with
    | .ok _ => throw (IO.userError s!"mint must reject without mintable on {tid}")
    | .error msg =>
        require (contains msg "TokenAuth") s!"mint reject names TokenAuth on {tid}"
        require (contains msg "mintable") s!"mint reject names mintable on {tid}"
    match materializeCoreOp tid .burn false false with
    | .ok _ => throw (IO.userError s!"burn must reject without burnable on {tid}")
    | .error msg =>
        require (contains msg "TokenAuth") s!"burn reject names TokenAuth on {tid}"
        require (contains msg "burnable") s!"burn reject names burnable on {tid}"
    match materializeCoreOp tid .mint true false with
    | .error msg => throw (IO.userError s!"mint+mintable on {tid}: {msg}")
    | .ok m => require (m.nativeOps.contains "mint") s!"mint op on {tid}"
  match materializeAuth "evm" .allowance with
  | .error msg => throw (IO.userError s!"evm allowance: {msg}")
  | .ok m => require (m.nativeOps.contains "approve") "evm approve"
  match materializeAuth "wasm-near" .allowance with
  | .ok _ => throw (IO.userError "NEAR must reject allowance (no ERC20 polyfill)")
  | .error msg =>
      require (contains msg "TokenAuth") "near allowance TokenAuth"
      require (contains msg "token.auth.allowance") "near allowance feature id"
  match materializeAuth "solana-sbpf-asm" .authority with
  | .error msg => throw (IO.userError s!"sol authority: {msg}")
  | .ok m =>
      require (m.nativeOps.any (fun s => contains s "authority" || contains s "delegate"))
        "sol authority ops"
  match materializeAuth "evm" .authority with
  | .ok _ => throw (IO.userError "EVM must reject SPL authority model")
  | .error msg => require (contains msg "TokenAuth") "evm authority reject"
  match materializeAuth "wasm-near" .storageDeposit with
  | .error msg => throw (IO.userError s!"near storage: {msg}")
  | .ok m => require (m.nativeOps.contains "storage_deposit") "near storage_deposit"
  match materializeAuth "wasm-near" .transferCall with
  | .error msg => throw (IO.userError s!"near transferCall: {msg}")
  | .ok _ => pure ()
  match materializeAuth "evm" .storageDeposit with
  | .ok _ => throw (IO.userError "EVM must reject storageDeposit")
  | .error msg => require (contains msg "TokenAuth") "evm storage reject"
  match validateDecimals 18 with
  | .error msg => throw (IO.userError msg)
  | .ok s =>
      require (s.factor == pow10 18) "scale18 factor"
      require (s.fromWhole 1 == pow10 18) "1 whole → 1e18"
      require (s.toWhole (pow10 18) == 1) "1e18 → 1 whole"
  match validateDecimals 19 with
  | .ok _ => throw (IO.userError "decimals>18 must reject")
  | .error msg => require (contains msg "FixedPoint") "decimals reject"
  require (rescale (pow10 6) scale6 scale18 == pow10 18) "rescale 6→18"
  require (mulScaled scale6 (pow10 6) (2 * pow10 6) == 2 * pow10 6)
    "mulScaled 1.0 * 2.0 @6dp = 2.0"
  match divScaled? scale6 (pow10 6) (2 * pow10 6) with
  | none => throw (IO.userError "divScaled should succeed")
  | some q => require (q == pow10 6 / 2) "divScaled 1/2 @6dp"
  match divScaled? scale6 1 0 with
  | some _ => throw (IO.userError "div by zero must be none")
  | none => pure ()

  ---------------------------------------------------------------------------
  -- Step 5: Upgrade / lifecycle
  ---------------------------------------------------------------------------
  match materializeUpgrade "evm" .immutable none with
  | .error msg => throw (IO.userError s!"evm immutable: {msg}")
  | .ok m => require (m.shape == .immutableDeploy) "evm immutable shape"
  match materializeUpgrade "evm" (.authority "deployer") (some .uups) with
  | .ok _ => throw (IO.userError "evm UUPS authority must reject until keyRef is enforced")
  | .error msg =>
      require (contains msg "authority" || contains msg "UpgradePolicy")
        "evm UUPS authority reject names unsupported policy"
  match materializeUpgrade "evm" (.authority "deployer") (some .transparent) with
  | .ok _ => throw (IO.userError "evm transparent must honest-reject (no Plan lower)")
  | .error msg =>
      require (contains msg "transparent" || contains msg "uups" || contains msg "authority" ||
          contains msg "UpgradePolicy")
        "evm transparent reject names pattern"
  match materializeUpgrade "evm" (.authority "deployer") none with
  | .ok _ => throw (IO.userError "evm authority without proxy must reject")
  | .error msg =>
      require (contains msg "proxy" || contains msg "EVM" || contains msg "uups")
        "evm no-proxy reject"
  match materializeUpgrade "solana-sbpf-asm" (.authority "upgrade_auth") none with
  | .error msg => throw (IO.userError s!"sol authority: {msg}")
  | .ok m => require (m.shape == .solanaUpgradeAuthority) "sol upgrade authority"
  match materializeUpgrade "wasm-near" (.authority "owner") none with
  | .error msg => throw (IO.userError s!"near authority: {msg}")
  | .ok m => require (m.shape == .nearRedeployMigrate) "near redeploy+migrate"
  match materializeUpgrade "evm" (.governance "dao") none with
  | .ok _ => throw (IO.userError "evm governance must reject")
  | .error msg =>
      require (contains msg "governance" || contains msg "UpgradePolicy" || contains msg "EVM")
        "evm governance reject"

  ---------------------------------------------------------------------------
  -- Step 6–7: PortableMechanics + HostEnv still honest
  ---------------------------------------------------------------------------
  let triad := HostRuntime.primaryTargetIds
  for tid in triad do
    match materializeMechanic tid .cryptoSha256 with
    | .error msg => throw (IO.userError s!"sha256 must materialize on {tid}: {msg}")
    | .ok m => require (!isNaSymbol m.binding.symbol) s!"sha256@{tid}"
  match materializeMechanic "evm" .cryptoEcrecover with
  | .error msg => throw (IO.userError s!"evm ecrecover: {msg}")
  | .ok m => require (m.binding.symbol == "ecrecover") "ecrecover symbol"
  match materializeMechanic "wasm-near" .cryptoEcrecover with
  | .ok _ => throw (IO.userError "NEAR ecrecover must reject")
  | .error msg =>
      require (contains msg "PortableMechanics") "near ecrecover names mechanics"
      require (contains msg "mech.crypto.ecrecover") "near ecrecover term id"
  match materializeMechanic "evm" .serdeAbi with
  | .error msg => throw (IO.userError s!"evm abi: {msg}")
  | .ok _ => pure ()
  match materializeMechanic "solana-sbpf-asm" .serdeAbi with
  | .ok _ => throw (IO.userError "solana abi must reject")
  | .error msg => require (contains msg "PortableMechanics") "sol abi reject"
  match materializeMechanic "solana-sbpf-asm" .serdeBorsh with
  | .error msg => throw (IO.userError s!"sol borsh: {msg}")
  | .ok _ => pure ()
  match materializeMechanic "wasm-near" .serdeJson with
  | .error msg => throw (IO.userError s!"near json: {msg}")
  | .ok _ => pure ()
  for tid in triad do
    match materializeMechanic tid .errorCode with
    | .error msg => throw (IO.userError s!"errorCode on {tid}: {msg}")
    | .ok _ => pure ()
  -- HostEnv honesty still holds (chainId not aliased)
  match materializeEnv "wasm-near" .chainId with
  | .ok _ => throw (IO.userError "NEAR chainId must still reject")
  | .error msg => require (contains msg "HostEnv") "hostenv chainId"

  ---------------------------------------------------------------------------
  -- Pipeline: resolveSpec / Preflight drive PortableHonesty (not table-only)
  ---------------------------------------------------------------------------
  -- Counter (no exotic context) resolves on triad.
  let counterSpec := ContractSpec.fromIR ProofForge.IR.Examples.Counter.module
  for profile in #[evm, solanaSbpfAsm, wasmNear] do
    match resolveSpec profile counterSpec with
    | .error d =>
        throw (IO.userError s!"Counter resolveSpec {profile.id} must ok: {d.message}")
    | .ok plan => require (plan.targetId == profile.id) s!"plan target {profile.id}"

  -- EVM-only baseFee context must fail Solana/NEAR resolveSpec via HostEnv honesty.
  let baseFeeMod : Module := {
    name := "BaseFeeOnly"
    state := #[]
    entrypoints := #[{
      name := "g"
      body := #[.return (.effect (.contextRead .baseFee))]
    }]
  }
  match resolveSpec solanaSbpfAsm (ContractSpec.fromIR baseFeeMod) with
  | .ok _ => throw (IO.userError "Solana must reject baseFee context via PortableHonesty")
  | .error d =>
      require (contains d.message "HostEnv" || contains d.message "PortableHonesty")
        s!"baseFee reject names honesty, got: {d.message}"
  match resolveSpec wasmNear (ContractSpec.fromIR baseFeeMod) with
  | .ok _ => throw (IO.userError "NEAR must reject baseFee context")
  | .error d =>
      require (contains d.message "HostEnv" || contains d.message "PortableHonesty")
        "NEAR baseFee honesty"

  -- Solana self (contractId) resolves after program-id HostEnv path (U1.2).
  let selfMod : Module := {
    name := "SelfOnly"
    state := #[]
    entrypoints := #[{
      name := "g"
      body := #[.return (.effect (.contextRead .contractId))]
    }]
  }
  match resolveSpec solanaSbpfAsm (ContractSpec.fromIR selfMod) with
  | .error d => throw (IO.userError s!"Solana self/contractId must ok: {d.message}")
  | .ok _ => pure ()
  match resolveSpec evm (ContractSpec.fromIR selfMod) with
  | .error d => throw (IO.userError s!"EVM self must ok: {d.message}")
  | .ok _ => pure ()

  -- Portable sync remote on Solana: requires declared peer; empty peer rejects.
  let remoteModEmptyPeer : Module := {
    name := "PortableRemoteEmptyPeer"
    state := #[{ id := "vault", kind := .scalar, type := .u64 }]
    entrypoints := #[{
      name := "ping"
      body := #[
        .return
          (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[.literal (.u64 0)])
      ]
    }]
    nearCrosscallStrings := #[]
  }
  match resolveSpec solanaSbpfAsm (ContractSpec.fromIR remoteModEmptyPeer) with
  | .ok _ => throw (IO.userError "Solana empty peer must reject on resolveSpec")
  | .error d =>
      require (
          contains d.message "peer" ||
          contains d.message "infer" ||
          contains d.message "PortableHonesty"
        ) s!"empty peer reject, got: {d.message}"
  -- With declared peer: resolve ok + note MUST list inferredAccounts=[...]
  let remoteMod : Module := {
    name := "PortableRemote"
    state := #[{ id := "vault", kind := .scalar, type := .u64 }]
    entrypoints := #[{
      name := "ping"
      body := #[
        .return
          (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[.literal (.u64 0)])
      ]
    }]
    nearCrosscallStrings := #["TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"]
  }
  match resolveSpec solanaSbpfAsm (ContractSpec.fromIR remoteMod) with
  | .error d => throw (IO.userError s!"Solana portable remote resolve: {d.message}")
  | .ok _ => pure ()
  let note := ProofForge.Backend.Solana.PortableCrosscall.materializationNote remoteMod
  require (contains note "inferredAccounts=[")
    s!"Solana materializationNote must list inferredAccounts=[...], got: {note}"
  require (contains note "vault" || contains note "payer" || contains note "token_program")
    s!"inferred list must include real roles, got: {note}"
  -- Manifest packing must merge inferred accounts (not note-only).
  let packed :=
    ProofForge.Backend.Solana.Manifest.ensurePortableCrosscallAccounts remoteMod #[]
  require (packed.any (fun a => a.name == "payer"))
    "ensurePortableCrosscallAccounts must include inferred payer"
  require (packed.any (fun a => a.name == "vault" || a.name == "peer_program" ||
      a.name == "token_program"))
    s!"ensurePortableCrosscallAccounts must include inferred peer/state roles, got names"

  -- NEAR async-only module still resolves on wasm-near (host-extension).
  match resolveSpec wasmNear (ContractSpec.fromIR nearAsyncModule) with
  | .error d =>
      -- Host-extension-only (no portable sync crosscall) should not hit sync-subset.
      throw (IO.userError s!"NEAR async-only host-extension should resolve: {d.message}")
  | .ok _ => pure ()
  -- Mixing portable sync remote with promise_then must fail.
  let mixMod : Module := {
    name := "MixPortableAsync"
    state := #[]
    entrypoints := #[{
      name := "bad"
      body := #[
        .letBind "p" .u64
          (.crosscallInvoke (.literal (.u64 1)) (.literal (.u64 2)) #[]),
        .return (.nearPromiseResultsCount)
      ]
    }]
  }
  match resolveSpec wasmNear (ContractSpec.fromIR mixMod) with
  | .ok _ => throw (IO.userError "mix portable+async must fail sync-subset")
  | .error d =>
      require (
          contains d.message "sync-subset" ||
          contains d.message "promise" ||
          contains d.message "PortableHonesty" ||
          contains d.message "CrosscallMaterialize"
        ) s!"mix reject, got: {d.message}"

  -- Upgrade: EVM authority policies reject until keyRef is enforced by runtime.
  let uupsSpec : ContractSpec := {
    name := "UupsProbe"
    module := {
      name := "UupsProbe"
      state := #[]
      entrypoints := #[{ name := "noop", body := #[] }]
    }
    upgradePolicy? := some (.authority "deployer")
    proxyPattern? := some .uups
  }
  match resolveSpec evm uupsSpec with
  | .ok _ => throw (IO.userError "EVM UUPS authority must reject on resolveSpec")
  | .error d =>
      require (contains d.message "authority" || contains d.message "UpgradePolicy")
        s!"UUPS authority reject, got: {d.message}"
  let transparentSpec := { uupsSpec with proxyPattern? := some .transparent }
  match resolveSpec evm transparentSpec with
  | .ok _ => throw (IO.userError "EVM transparent must reject on resolveSpec")
  | .error d =>
      require (contains d.message "transparent" || contains d.message "uups" ||
          contains d.message "Upgrade" || contains d.message "PortableHonesty")
        s!"transparent reject, got: {d.message}"

  -- Token planForTarget: FixedPoint + mint gate + authFeatures on real path.
  match planForTarget evm {
    name := "T", symbol := "T", decimals := 18, features := #[]
  } with
  | .error msg => throw (IO.userError s!"plan core token: {msg}")
  | .ok plan =>
      require (!(plan.operations.any (fun o => contains o "mint")))
        "no mint ops without mintable"
  match planForTarget evm {
    name := "T", symbol := "T", decimals := 18, features := #[.mintable]
  } with
  | .error msg => throw (IO.userError s!"plan mintable: {msg}")
  | .ok plan =>
      require (plan.operations.any (fun o => contains o "mint")) "mint with mintable"
  match planForTarget evm {
    name := "T", symbol := "T", decimals := 99, features := #[]
  } with
  | .ok _ => throw (IO.userError "decimals 99 must fail FixedPoint")
  | .error msg => require (contains msg "FixedPoint") "decimals reject FixedPoint"
  -- Auth features on planForTarget (not table-only)
  match planForTarget evm {
    name := "T", symbol := "T", decimals := 18
    features := #[]
    authFeatures := #[.allowance]
  } with
  | .error msg => throw (IO.userError s!"EVM allowance plan: {msg}")
  | .ok _ => pure ()
  match planForTarget wasmNear {
    name := "T", symbol := "T", decimals := 18
    features := #[]
    authFeatures := #[.allowance]
  } with
  | .ok _ => throw (IO.userError "NEAR plan must reject allowance authFeature")
  | .error msg =>
      require (contains msg "TokenAuth" || contains msg "allowance")
        s!"NEAR allowance reject, got: {msg}"
  match planForTarget wasmNear {
    name := "T", symbol := "T", decimals := 18
    features := #[]
    authFeatures := #[.storageDeposit]
  } with
  | .error msg => throw (IO.userError s!"NEAR storageDeposit plan: {msg}")
  | .ok _ => pure ()
  match planForTarget solanaSbpfAsm {
    name := "T", symbol := "T", decimals := 9
    features := #[]
    authFeatures := #[.authority]
  } with
  | .error msg => throw (IO.userError s!"Solana authority plan: {msg}")
  | .ok _ => pure ()

  -- Preflight ready for Counter on triad
  let reports := runPrimary ProofForge.IR.Examples.Counter.module
  require (allReady reports) "Counter preflight allReady triad"

  -- Mechanics on real resolveSpec path (crypto.ecrecover rejects on NEAR)
  let ecrecoverMod : Module := {
    name := "EcrecoverOnly"
    state := #[]
    entrypoints := #[{
      name := "r"
      body := #[
        .return (.ecrecover
          (.literal (.u64 0)) (.literal (.u64 0))
          (.literal (.u64 0)) (.literal (.u64 0)))
      ]
    }]
  }
  match resolveSpec wasmNear (ContractSpec.fromIR ecrecoverMod) with
  | .ok _ => throw (IO.userError "NEAR must reject ecrecover via PortableMechanics honesty")
  | .error d =>
      require (
          contains d.message "PortableHonesty" ||
          contains d.message "PortableMechanics" ||
          contains d.message "ecrecover" ||
          contains d.message "crypto"
        ) s!"NEAR ecrecover reject, got: {d.message}"
  match resolveSpec evm (ContractSpec.fromIR ecrecoverMod) with
  | .error d => throw (IO.userError s!"EVM ecrecover should resolve: {d.message}")
  | .ok _ => pure ()

  IO.println "chain-agnostic-route: ok (pipeline+identity+sync+token+upgrade+mechanics)"
  pure 0

end ProofForge.Tests.ChainAgnosticRoute

def main : IO UInt32 :=
  ProofForge.Tests.ChainAgnosticRoute.main
