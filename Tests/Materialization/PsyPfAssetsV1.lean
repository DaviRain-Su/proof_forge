/-
  Tests.Materialization.PsyPfAssetsV1 — ADR-0029 Phase D + PSY-ASYNC-ASSETS.

  Evidence fail-closed closure (no capability open):
    * resolver does **not** advertise `extension.pf-assets`
    * each of the five catalog QNs with extension declaration fails at
      **resolve** (`PF-REQ-UNSUPPORTED`)
    * without extension, catalog QNs reach Plan and fail with explicit
      **unbound** diagnostic — deposit, sync transfer, and transferAsync
      (must not alias a generic DPN sync invoke as vault/async value move)
    * non-catalog L0 sync call still lowers (Phase D must not broaden FC)

  Note: transfer* QNs need Principal args. PSY-SCALAR-ABI opens Principal
  wire-identity leaves, so without extension those programs reach Plan and
  hit unbound catalog disposition (not Principal type-closure). Resolve-with-
  extension remains the product pin for all five. Schedule/async is pinned
  separately in PsyDpnV1 (`testScheduleFailClosedAtDpn`); never rename sync.
-/
import ProofForgeV2
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Targets.Psy
import ProofForgeV2.Targets.Psy.PfAssetsDispositionV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.PsyPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Psy.PfAssetsDispositionV1
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

private def resolvePsy (compiled : CompiledSemanticV1) :
    CompileResult Targets.ResolvedEngineeringBuildV1 := do
  let selection ← resolveBuildSelectionV1 TargetId.psy none
  Targets.resolveEngineeringRequirementsV1 selection compiled

private def planPsyOf (compiled : CompiledSemanticV1) : CompileResult Targets.Psy.Plan := do
  let capability ← resolvePsy compiled
  Targets.Psy.planFromCapability capability

/-- Disposition module freezes empty admit set + full catalog membership. -/
def testDispositionHelpers : IO Unit := do
  expect (admittedBindingsV1.isEmpty) "Psy Phase D admit set must be empty"
  expect (!isPsyAdmittedPfAssetsQnV1 "pf.assets.native.deposit")
    "no QN is Psy-admitted"
  for qn in pfAssetsCatalogQualifiedNamesV1 do
    expect (isPfAssetsCatalogQnV1 qn) s!"catalog membership must include {qn}"
  expect (!isPfAssetsCatalogQnV1 "Peer.go") "non-catalog must not match"
  expect ((unboundCatalogDiagV1 "pf.assets.native.deposit").contains "unbound")
    "unbound diagnostic must cite unbound"

/-- One catalog QN (+ extension) → resolve PF-REQ-UNSUPPORTED. -/
unsafe def expectUnsupportedAtResolve (label qn callLine extraParams : String) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    s!"program {label} where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    s!"  entry tip({extraParams}) : UInt64 do\n" ++
    s!"    {callLine}\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource s!"<psy-pf-assets-{label}>" s!"Tests.Psy{label}" source
  match resolvePsy compiled with
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"{qn}: must fail at resolve with PF-REQ-UNSUPPORTED, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        s!"{qn}: Psy must not resolve a program that requires extension.pf-assets"

/-- Five catalog QNs: exact resolve failure (zero-binding — no Psy permit). -/
unsafe def testFiveCatalogQnsFailAtResolve : IO Unit := do
  expectUnsupportedAtResolve "Dep" "pf.assets.native.deposit"
    "call pf.assets.native.deposit(amount)" "amount : UInt64"
  expectUnsupportedAtResolve "Xfer" "pf.assets.native.transfer"
    "call pf.assets.native.transfer(dst, amount)"
    "dst : Principal, amount : UInt64"
  expectUnsupportedAtResolve "XferAsync" "pf.assets.native.transferAsync"
    "call pf.assets.native.transferAsync(dst, amount)"
    "dst : Principal, amount : UInt64"
  expectUnsupportedAtResolve "Tok" "pf.assets.token.transfer"
    "call pf.assets.token.transfer(mint, dst, amount)"
    "mint : Principal, dst : Principal, amount : UInt64"
  expectUnsupportedAtResolve "TokAsync" "pf.assets.token.transferAsync"
    "call pf.assets.token.transferAsync(mint, dst, amount)"
    "mint : Principal, dst : Principal, amount : UInt64"

/-- Shared Plan unbound pin: resolve OK (sync-call advertised; no extension),
    Plan fails with explicit unbound + QN (must not lower to a generic DPN invoke). -/
unsafe def expectCatalogUnboundAtPlan (label qn callLine extraParams : String) : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    s!"program {label} where\n" ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    s!"  entry tip({extraParams}) : UInt64 do\n" ++
    s!"    {callLine}\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource s!"<psy-pf-assets-{label}-noext>" s!"Tests.Psy{label}NoExt" source
  -- Resolve must succeed (Psy advertises sync-call; no extension row required).
  let _capability ← liftResult <| resolvePsy compiled
  match planPsyOf compiled with
  | .error (.planInvariant .psy msg) =>
      expect (msg.contains "unbound" && msg.contains qn)
        s!"{qn}: Plan must cite unbound+QN, got: {msg}"
      expect (!msg.contains "must have at least two components")
        s!"{qn}: unbound path must be distinct from callee arity gate"
      -- Honesty: diagnostic must not claim a deferred/async alias path.
      expect (!msg.contains "deferred form")
        s!"{qn}: unbound is not a schedule-deferred diagnostic"
  | .error e =>
      throw <| IO.userError s!"{qn}: expected planInvariant .psy, got {e.render}"
  | .ok _ =>
      throw <| IO.userError
        s!"{qn}: catalog QN must fail closed at Psy Plan (unbound; no fake vault)"

/-- Deposit without extension: Plan unbound FC (no fake vault deposit). -/
unsafe def testDepositUnboundAtPlan : IO Unit :=
  expectCatalogUnboundAtPlan "Dep" "pf.assets.native.deposit"
    "call pf.assets.native.deposit(amount)" "amount : UInt64"

/-- Sync transfer without extension: Plan unbound (no honest vault debit/credit). -/
unsafe def testTransferUnboundAtPlan : IO Unit :=
  expectCatalogUnboundAtPlan "Xfer" "pf.assets.native.transfer"
    "call pf.assets.native.transfer(dst, amount)"
    "dst : Principal, amount : UInt64"

/-- transferAsync without extension: Plan unbound — must not become schedule or
    sync alias; async asset QNs share the same zero-binding disposition. -/
unsafe def testTransferAsyncUnboundAtPlan : IO Unit :=
  expectCatalogUnboundAtPlan "XferAsync" "pf.assets.native.transferAsync"
    "call pf.assets.native.transferAsync(dst, amount)"
    "dst : Principal, amount : UInt64"

/-- Token transferAsync without extension: same unbound (no CW20/NEP-141 surface). -/
unsafe def testTokenTransferAsyncUnboundAtPlan : IO Unit :=
  expectCatalogUnboundAtPlan "TokAsync" "pf.assets.token.transferAsync"
    "call pf.assets.token.transferAsync(mint, dst, amount)"
    "mint : Principal, dst : Principal, amount : UInt64"

/-- Non-catalog L0 call still materializes (Phase D must not broaden FC). -/
unsafe def testNonCatalogCallStillLowers : IO Unit := do
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
  let compiled ← compileSource "<psy-pf-assets-oracle>" "Tests.PsyPfAssetsOracle" source
  let plan ← liftResult <| planPsyOf compiled
  liftResult <| Targets.Psy.validatePlan plan

/-- SYS-S5: Psy has no SHA-2 host. Exact `pf.crypto.sha256` stays Plan fail
    closed (Poseidon/keccak gadgets are not a sha256 binding). -/
unsafe def testCryptoSha256StayFailClosed : IO Unit := do
  let expectPlanFc (label body needle : String)
      (also : String := "") : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let compiled ← compileSource s!"<psy-{label}>" s!"Tests.Psy{label}" source
    match planPsyOf compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
        unless also.isEmpty do
          expect (e.render.contains also)
            s!"{label} Plan FC must contain '{also}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Psy sha256 host)"
  expectPlanFc "Sha256Psy"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : UInt64 := call pf.crypto.sha256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Psy host binding"
  expectPlanFc "Sha256PsyVoid"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    call pf.crypto.sha256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "has no Psy host binding"
  -- SYS-S5-ECDSA-FC-REST: void sibling so the QN is named. Result-bearing
  -- ecdsa hits the generic "result-bearing external call is not admitted"
  -- list (hash*|keccak256 only) and does not interpolate the QN.
  expectPlanFc "EcdsaRecoverPsy"
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
    "ecdsaRecoverSecp256k1"
    "value-producing"

/-- SYS-S5: Psy `pf.crypto.keccak256` is an ADR-0039 circuit gadget
    (UInt64 first-limb ABI), not the unified UInt256→UInt256 host leaf.
    Exact UInt256 host shape stays fail closed. -/
unsafe def testCryptoKeccak256IsGadgetNotHost : IO Unit := do
  let expectPlanFc (label body needle : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let compiled ← compileSource s!"<psy-{label}>" s!"Tests.Psy{label}" source
    match planPsyOf compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (Psy keccak256 is not a UInt256 host)"
  -- Unified-host shape: UInt256→UInt256 is not admitted on Psy.
  expectPlanFc "Keccak256PsyU256"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.keccak256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto/context scalar result must be UInt64/Felt"
  -- Circuit gadget still admits the historical UInt64 first-limb ABI.
  let gadgetSrc :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Keccak256PsyGadget where\n" ++
    "  state pad : UInt64\n" ++
    "  init() do\n" ++
    "    pad := 0\n" ++
    "  entry probe() : UInt64 do\n" ++
    "    let w : UInt64 := 0\n" ++
    "    let h : UInt64 := call pf.crypto.keccak256(w)\n" ++
    "    pad := h\n" ++
    "    return pad\n" ++
    "  view get() : UInt64 do\n" ++
    "    return pad\n"
  let compiled ← compileSource "<psy-keccak-gadget>" "Tests.PsyKeccak256Gadget" gadgetSrc
  let plan ← liftResult <| planPsyOf compiled
  liftResult <| Targets.Psy.validatePlan plan

/-- SYS-S5: remaining Psy ADR-0039 gadgets stay first-limb / HashOut
    shapes. Official software eval does not fill keccak/hashPad as a
    unified UInt256 host; Array4 HashOut is only hashNoPad|hashTwoToOne. -/
unsafe def testCryptoGadgetShapesStayHonest : IO Unit := do
  let expectPlanFc (label body needle : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let compiled ← compileSource s!"<psy-{label}>" s!"Tests.Psy{label}" source
    match planPsyOf compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (Psy gadget ABI is not a UInt256 host)"
  expectPlanFc "HashPadPsyU256"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.hashPad(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto/context scalar result must be UInt64/Felt"
  expectPlanFc "HashTwoToOnePsyU256"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt256 := 0\n" ++
      "    let h : UInt256 := call pf.crypto.hashTwoToOne(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "pf.crypto.hashTwoToOne requires exactly 8 limbs"
  expectPlanFc "Keccak256PsyArray4"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : Array UInt64 4 := call pf.crypto.keccak256(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "Array UInt64 4 HashOut full ABI is only admitted for pf.crypto.hashNoPad|hashTwoToOne"
  expectPlanFc "HashPadPsyArray4"
    ("  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      "    let h : Array UInt64 4 := call pf.crypto.hashPad(w)\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n")
    "Array UInt64 4 HashOut full ABI is only admitted for pf.crypto.hashNoPad|hashTwoToOne"
  let admitScalar (label qn : String) : IO Unit := do
    let src :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++
      "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    let w : UInt64 := 0\n" ++
      s!"    let h : UInt64 := call {qn}(w)\n" ++
      "    pad := h\n" ++
      "    return pad\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
    let compiled ← compileSource s!"<psy-{label}>" s!"Tests.Psy{label}" src
    let plan ← liftResult <| planPsyOf compiled
    liftResult <| Targets.Psy.validatePlan plan
  admitScalar "HashPadPsyGadget" "pf.crypto.hashPad"
  admitScalar "HashNoPadPsyGadget" "pf.crypto.hashNoPad"

/-- SYS-S4: name remaining ContextRead catalog keys. unixTime/caller/
    blockHeight keep their existing messages. attachedValue/chainId are
    named no-host. self is named like caller (Principal ≠ Psy address). -/
unsafe def testContextReadStayFailClosed : IO Unit := do
  let expectPlanFc (label body needle : String) : IO Unit := do
    let source :=
      "import ProofForgeV2\n" ++
      "open ProofForgeV2.Language\n" ++
      s!"program {label} where\n" ++ body
    let compiled ← compileSource s!"<psy-{label}>" s!"Tests.Psy{label}" source
    match planPsyOf compiled with
    | .error e =>
        expect (e.render.contains needle)
          s!"{label} Plan FC must contain '{needle}', got: {e.render}"
    | .ok _ =>
        throw <| IO.userError
          s!"{label} must Plan fail closed (no Psy context host)"
  let ctxBody (place : String) : String :=
    "  state pad : UInt64\n" ++
      "  init() do\n" ++
      "    pad := 0\n" ++
      "  entry probe() : UInt64 do\n" ++
      "    return " ++ place ++ "\n" ++
      "  view get() : UInt64 do\n" ++
      "    return pad\n"
  -- unixTime is not opened: existing DPN wall-clock reject.
  expectPlanFc "UnixTimePsy" (ctxBody "context.unixTimeSeconds")
    "no DPN wall-clock binding"
  expectPlanFc "AttachedValuePsy" (ctxBody "context.attachedValue")
    "has no Psy host binding"
  expectPlanFc "ChainIdPsy" (ctxBody "context.chainId")
    "has no Psy host binding"
  expectPlanFc "SelfPsy"
    ("  entry same() : Bool do\n" ++
      "    return context.contractId == context.contractId\n")
    "context.self"

/-- SYS-E2: Psy has no native vault host. `pf.assets.native.balanceOfSelf`
    stays Plan fail closed. Product resolve still declines
    `extension.pf-assets` first, so this pin uses the engineering Plan path
    (compile reaches Plan). token/U128 stay on the generic EnvRead envelope. -/
unsafe def testEnvReadNativeStayFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program EnvReadBalancePsy where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  view nativeBalance() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n" ++
    "  entry setCount(newCount : UInt64) : UInt64 do\n" ++
    "    count := newCount\n" ++
    "    return count\n"
  let compiled ← compileSource "<psy-env-read-native>" "Tests.EnvReadBalancePsy" source
  match Targets.Psy.planFromCompiledSemanticV1 compiled with
  | .error e =>
      expect (e.render.contains "has no Psy host binding")
        s!"EnvReadBalancePsy Plan FC must contain 'has no Psy host binding', got: {e.render}"
      expect (e.render.contains "envRead" || e.render.contains "nativeVaultBalance")
        s!"EnvReadBalancePsy Plan FC must name envRead/nativeVaultBalance, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError
        "EnvReadBalancePsy must Plan fail closed (no Psy vault host)"

unsafe def run : IO Unit := do
  testDispositionHelpers
  testFiveCatalogQnsFailAtResolve
  testDepositUnboundAtPlan
  testTransferUnboundAtPlan
  testTransferAsyncUnboundAtPlan
  testTokenTransferAsyncUnboundAtPlan
  testNonCatalogCallStillLowers
  testCryptoSha256StayFailClosed
  testCryptoKeccak256IsGadgetNotHost
  testCryptoGadgetShapesStayHonest
  testContextReadStayFailClosed
  testEnvReadNativeStayFailClosed
  IO.println "Tests.Materialization.PsyPfAssetsV1: ok"

end Tests.Materialization.PsyPfAssetsV1
