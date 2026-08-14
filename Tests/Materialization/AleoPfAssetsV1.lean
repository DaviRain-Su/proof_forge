/-
  Tests.Materialization.AleoPfAssetsV1 — ADR-0029 Phase D Aleo zero-binding.

  Pins:
    * resolver does **not** advertise `extension.pf-assets`
    * each of the five catalog QNs fails at **resolve** (Aleo declines both
      extension.pf-assets and effect.synchronous-call; product path never
      reaches Plan for call)
    * disposition helpers freeze empty admit set + unbound diagnostic text
    * non-catalog call still declines at resolve (sync-call key) — no
      broadening of Aleo capability

  Plan-level unbound wording in `LowerSemanticV1` is defense-in-depth for a
  future sync-call surface; product fail point today is resolve.
-/
import ProofForgeV2
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Targets.Aleo
import ProofForgeV2.Targets.Aleo.PfAssetsDispositionV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.AleoPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Aleo.PfAssetsDispositionV1
open ProofForgeV2.Core.RequirementIdsV1

private def expect (cond : Bool) (message : String) : IO Unit :=
  unless cond do throw <| IO.userError message

private def liftResult {α : Type} : CompileResult α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError e.render

private def pfAssetsRequiresBlock : String :=
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  "    digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n"

private unsafe def compileSource (label : String) (name : String) (source : String) :
    IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1 source label name none)
  liftResult <| Compiler.compileValidatedSourceV1 parsed

private def resolveAleo (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.aleo none
  Targets.resolveEngineeringRequirementsV1 selection compiled

/-- Disposition module freezes empty admit set + full catalog membership. -/
def testDispositionHelpers : IO Unit := do
  expect (admittedBindingsV1.isEmpty) "Aleo Phase D admit set must be empty"
  expect (!isAleoAdmittedPfAssetsQnV1 "pf.assets.native.transfer")
    "no QN is Aleo-admitted"
  for qn in pfAssetsCatalogQualifiedNamesV1 do
    expect (isPfAssetsCatalogQnV1 qn) s!"catalog membership must include {qn}"
  let diag := unboundCatalogDiagV1 "pf.assets.native.transfer"
  expect (diag.contains "unbound" && diag.contains "record custody")
    "Aleo unbound diagnostic must cite unbound + record custody"

/-- Extension alone declines at resolve (no Aleo permit row). -/
unsafe def testExtensionDeclinedAtResolve : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program DeclOnly where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(amount : UInt64) : UInt64 do\n" ++
    "    tips := tips + amount\n" ++
    "    return tips\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<aleo-pf-assets-decl>" "Tests.AleoPfAssetsDecl" source
  match resolveAleo compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"Aleo must decline extension.pf-assets at resolve, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Aleo must not advertise extension.pf-assets"

/-- One catalog QN (+ extension) → resolve PF-REQ-UNSUPPORTED. -/
unsafe def expectUnsupportedAtResolve (label qn callLine : String) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    s!"program {label} where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(dst : Principal, mint : Principal, amount : UInt64) : UInt64 do\n" ++
    s!"    {callLine}\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource s!"<aleo-pf-assets-{label}>" s!"Tests.Aleo{label}" source
  match resolveAleo compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"{qn}: must fail at resolve with PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        s!"{qn}: Aleo must not resolve a program that requires pf.assets + sync call"

/-- Five catalog QNs: exact resolve failure (zero-binding + no sync-call key). -/
unsafe def testFiveCatalogQnsFailAtResolve : IO Unit := do
  expectUnsupportedAtResolve "Dep" "pf.assets.native.deposit"
    "call pf.assets.native.deposit(amount)"
  expectUnsupportedAtResolve "Xfer" "pf.assets.native.transfer"
    "call pf.assets.native.transfer(dst, amount)"
  expectUnsupportedAtResolve "XferAsync" "pf.assets.native.transferAsync"
    "call pf.assets.native.transferAsync(dst, amount)"
  expectUnsupportedAtResolve "Tok" "pf.assets.token.transfer"
    "call pf.assets.token.transfer(mint, dst, amount)"
  expectUnsupportedAtResolve "TokAsync" "pf.assets.token.transferAsync"
    "call pf.assets.token.transferAsync(mint, dst, amount)"

/-- Non-catalog call still declines (sync-call key) — Phase D must not open call. -/
unsafe def testNonCatalogCallStillDeclined : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Oracle where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    call Peer.go(x)\n" ++
    "    return count\n"
  let compiled ← compileSource "<aleo-pf-assets-oracle>" "Tests.AleoPfAssetsOracle" source
  match resolveAleo compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"non-catalog call must still decline at resolve, got {e.render}"
  | .ok _ =>
      throw <| IO.userError "Aleo must not open sync-call for non-catalog callees"

/-- SYS-S5: Aleo has no sha256 host. Exact `pf.crypto.*` stays Plan fail
    closed (no BHP/Pedersen/Poseidon fallback). Product resolve still
    declines sync-call first, so this pin uses the engineering Plan path. -/
unsafe def testCryptoSha256StayFailClosed : IO Unit := do
  let expectPlanFc (label body needle : String)
      (also : String := "") : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let compiled ← compileSource s!"<aleo-{label}>" s!"Tests.Aleo{label}" source
    match Targets.Aleo.engineeringPlanFromCompiled compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{label} Plan FC must contain '{also}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Aleo crypto host)"
  expectPlanFc "Sha256Aleo"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    call pf.crypto.sha256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Aleo host binding"
  expectPlanFc "Sha256AleoHashNoPad"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.hashNoPad(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Aleo host binding"
  expectPlanFc "Keccak256Aleo"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    call pf.crypto.keccak256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Aleo host binding"
  -- SYS-S5-ECDSA-FC-REST: keep UInt64 void ABI so the needle is the QN arm.
  expectPlanFc "EcdsaRecoverAleo"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let h : UInt64 := 0\n" ++
      "    let v : UInt64 := 0\n" ++
      "    let r : UInt64 := 0\n" ++
      "    let s : UInt64 := 0\n" ++
      "    call pf.crypto.ecdsaRecoverSecp256k1(h, v, r, s)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Aleo host binding"
    "ecdsaRecoverSecp256k1"

/-- SYS-S4: name remaining ContextRead catalog keys. unixTime stays on the
    existing generic reject (no Aleo clock). attachedValue/chainId/blockHeight
    are named no-host. caller/self are Principal — Aleo type-closure rejects
    Principal before the ContextRead arm. -/
unsafe def testContextReadStayFailClosed : IO Unit := do
  let expectPlanFc (label body needle : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let compiled ← compileSource s!"<aleo-{label}>" s!"Tests.Aleo{label}" source
    match Targets.Aleo.engineeringPlanFromCompiled compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Aleo context host)"
  let ctxBody (place : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return " ++ place ++ "\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  -- unixTime is not opened: still the generic pilot reject, not a clock host.
  expectPlanFc "UnixTimeAleo" (ctxBody "context.unixTimeSeconds")
    "ContextRead is not admitted by pilot context policy"
  expectPlanFc "AttachedValueAleo" (ctxBody "context.attachedValue")
    "has no Aleo host binding"
  expectPlanFc "ChainIdAleo" (ctxBody "context.chainId")
    "has no Aleo host binding"
  expectPlanFc "BlockHeightAleo" (ctxBody "context.blockHeight")
    "has no Aleo host binding"
  -- Principal keys: type-closure fires first (no Principal on Aleo).
  expectPlanFc "SelfAleo"
    ("  entry who() : UInt64 do\n" ++
      "    let s : Principal := context.contractId\n" ++
      "    return 0\n")
    "Principal"
  expectPlanFc "CallerAleo"
    ("  entry who(a : Principal) : Bool do\n" ++
      "    return context.caller == a\n")
    "Principal"

/-- SYS-E2: Aleo has no native vault host. `pf.assets.native.balanceOfSelf`
    stays Plan fail closed. Product resolve still declines
    `extension.pf-assets` first, so this pin uses the engineering Plan path
    (compile reaches Plan). token/U128 stay on the generic EnvRead envelope. -/
unsafe def testEnvReadNativeStayFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EnvReadBalanceAleo where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  view nativeBalance() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n" ++
    "  entry setCount(newCount : UInt64) : UInt64 do\n" ++
    "    count := newCount\n" ++
    "    return count\n"
  let compiled ← compileSource "<aleo-env-read-native>" "Tests.EnvReadBalanceAleo" source
  match Targets.Aleo.engineeringPlanFromCompiled compiled with
  | .error e =>
      expect (e.render.contains "has no Aleo host binding")
        s!"EnvReadBalanceAleo Plan FC must contain 'has no Aleo host binding', got: {e.render}"
      expect (e.render.contains "envRead" || e.render.contains "nativeVaultBalance")
        s!"EnvReadBalanceAleo Plan FC must name envRead/nativeVaultBalance, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "EnvReadBalanceAleo must Plan fail closed (no Aleo vault host)"

unsafe def run : IO Unit := do
  testDispositionHelpers
  testExtensionDeclinedAtResolve
  testFiveCatalogQnsFailAtResolve
  testNonCatalogCallStillDeclined
  testCryptoSha256StayFailClosed
  testContextReadStayFailClosed
  testEnvReadNativeStayFailClosed
  IO.println "Tests.Materialization.AleoPfAssetsV1: ok"

end Tests.Materialization.AleoPfAssetsV1
