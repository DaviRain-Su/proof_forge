/-
  Tests.Materialization.CosmWasmPfAssetsV1 — ADR-0029 Phase C1 + ADR-0030 E1-CW
  CosmWasm binding.

  Plan-level pins for the pf.assets CosmWasm lane:
    * `pf.assets.native.deposit(amount)` lowers to `.nativeDeposit` (exact
      one-coin info.funds check at runtime; frozen denom "stake")
    * `pf.assets.native.transfer(dst, amount)` lowers to `.nativeTransfer`
      (BankMsg::Send SubMsg, reply_on=never error-propagating)
    * `pf.assets.token.transfer(mint, dst, amount)` lowers to `.tokenTransfer`
      (WasmMsg::Execute SubMsg to CW20 contract at mint, reply_on=never
      error-propagating; controlled dynamic callee — catalog token family only)
    * catalog QN requires exact `extension.pf-assets` row (declaration gate)
    * `token.transferAsync` / `native.transferAsync` QNs fail closed
    * non-catalog sync calls stay fail closed (CW sync envelope)
    * depositPolicy: deposit entry → requireExactNative; others → requireZero
-/
import ProofForgeV2
import ProofForgeV2.Targets.CosmWasm
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.CosmWasmPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.CosmWasm

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

private unsafe def planCwOf (compiled : CompiledSemanticV1) : IO Plan := do
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.cosmwasm none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  liftResult <| planFromCapability capability

private def tipJarSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Tip where\n" ++
  pfAssetsRequiresBlock ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.deposit(amount)\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    tips := tips + amount\n" ++
  "    return tips\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

/-- Positive: deposit + transfer lower into the tip entry in source order with
    the right deposit policies. -/
unsafe def testDepositTransferPlan : IO Unit := do
  let compiled ← compileSource "<cw-pf-assets>" "Tests.CwPfAssetsTip" tipJarSource
  let plan ← planCwOf compiled
  let some tip := plan.entries[0]? |
    throw <| IO.userError "tip entry must exist"
  let deposits := tip.body.filter fun st => match st with
    | .nativeDeposit _ => true | _ => false
  let transfers := tip.body.filter fun st => match st with
    | .nativeTransfer .. => true | _ => false
  expect (deposits.size == 1) "tip must contain exactly one nativeDeposit"
  expect (transfers.size == 1) "tip must contain exactly one nativeTransfer"
  let depositIdx := tip.body.findIdx? fun st => match st with
    | .nativeDeposit _ => true | _ => false
  let transferIdx := tip.body.findIdx? fun st => match st with
    | .nativeTransfer .. => true | _ => false
  match depositIdx, transferIdx with
  | some d, some t => expect (d < t) "source order: deposit < transfer"
  | _, _ => throw <| IO.userError "tip body missing deposit/transfer"
  expect (tip.depositPolicy == .requireExactNative)
    "deposit entry must carry requireExactNative policy"
  -- init and view carry the non-deposit policies.
  expect (plan.initializer.depositPolicy == .requireZero)
    "init must carry requireZero (no deposit)"
  let viewMethods := plan.entries.filter fun m => m.mode == .view
  let some getView := viewMethods[0]? |
    throw <| IO.userError "get view must exist in entries"
  expect (getView.depositPolicy == .queryOnly)
    "view must carry queryOnly policy"

/-- Declaration gate: catalog QN without exact extension.pf-assets fails closed. -/
unsafe def testCatalogCallRequiresDeclaration : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NoExt where\n" ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.transfer(dst, amount)\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<cw-pf-assets-noext>" "Tests.CwPfAssetsNoExt" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.cosmwasm none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.contains "extension.pf-assets" || msg.contains "pf.assets catalog")
        s!"no-declaration must cite extension gate, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "pf.assets without extension must fail closed"

/-- ADR-0030 E1-CW: `pf.assets.token.transfer` lowers to `.tokenTransfer`
    (WasmMsg::Execute SubMsg to CW20 contract at mint). Entry is non-payable
    (requireZero — no native deposit); token transfer carries no info.funds. -/
private def tokenJarSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program TokenJar where\n" ++
  pfAssetsRequiresBlock ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  "  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.token.transfer(mint, dst, amount)\n" ++
  "    tips := tips + amount\n" ++
  "    return tips\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

unsafe def testTokenTransferPlan : IO Unit := do
  let compiled ← compileSource "<cw-pf-assets-token>"
    "Tests.CwPfAssetsToken" tokenJarSource
  let plan ← planCwOf compiled
  let some tipToken := plan.entries[0]? |
    throw <| IO.userError "tipToken entry must exist"
  let tokenTransfers := tipToken.body.filter fun st => match st with
    | .tokenTransfer .. => true | _ => false
  expect (tokenTransfers.size == 1)
    "tipToken must contain exactly one tokenTransfer"
  -- Entry is non-payable: no native deposit → requireZero funds policy.
  expect (tipToken.depositPolicy == .requireZero)
    "token.transfer entry must be non-payable (requireZero)"
  -- No nativeDeposit in the body.
  let deposits := tipToken.body.filter fun st => match st with
    | .nativeDeposit _ => true | _ => false
  expect (deposits.size == 0)
    "token.transfer entry must not contain nativeDeposit"

/-- Async QNs fail closed (token.transferAsync / native.transferAsync).
    token.transfer is now admitted (E1-CW); only the async variants stay FC. -/
unsafe def testAsyncFailClosed : IO Unit := do
  let mkSource (callText : String) (withMint : Bool) : String :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Scope where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(" ++ (if withMint then "mint : Principal, " else "") ++
    "dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call " ++ callText ++ "\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  for (label, callSpelling, needle, withMint) in #[
      ("tokenAsync", "pf.assets.token.transferAsync(mint, dst, amount)", "async", true),
      ("nativeAsync", "pf.assets.native.transferAsync(dst, amount)", "async", false) ] do
    let source := mkSource callSpelling withMint
    let compiled ← compileSource s!"<cw-pf-assets-{label}>"
      s!"Tests.CwPfAssets{label}" source
    let selection ← liftResult <|
      Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.cosmwasm none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    match planFromCapability capability with
    | .error (.planInvariant .cosmwasm msg) =>
        expect (msg.contains needle || msg.contains "admitted scope" || msg.contains "fail closed")
          s!"{label} QN must cite scope, got: {msg}"
    | .error e => throw <| IO.userError s!"{label}: expected planInvariant, got {e.render}"
    | .ok _ => throw <| IO.userError s!"{label} QN must fail closed on CosmWasm"

/-- Non-catalog sync calls stay fail closed (CW sync envelope). -/
unsafe def testNonCatalogSyncFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program OracleCall where\n" ++
    pfAssetsRequiresBlock ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(x : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(x)\n" ++
    "    count := count + x\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let compiled ← compileSource "<cw-pf-assets-oracle>" "Tests.CwPfAssetsOracle" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.cosmwasm none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.contains "sync" || msg.contains "catalog" || msg.contains "outside")
        s!"non-catalog sync must cite envelope, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "non-catalog sync call must fail closed on CosmWasm"

/-- Catalog membership: token.transfer is now admitted; the catalog advertises
    exactly native.deposit + native.transfer + token.transfer + env-read QNs. -/
unsafe def testCatalogAdmitSet : IO Unit := do
  expect (PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.native.deposit")
    "native.deposit must be admitted"
  expect (PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.native.transfer")
    "native.transfer must be admitted"
  expect (PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.token.transfer")
    "token.transfer must be admitted (E1-CW)"
  expect (PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.native.balanceOfSelf")
    "native.balanceOfSelf must be admitted (E2-4-CW)"
  expect (PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.token.balanceOfSelf")
    "token.balanceOfSelf must be admitted (E2-4-CW)"
  expect (!PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.token.transferAsync")
    "token.transferAsync must NOT be admitted"
  expect (!PfAssetsCatalogV1.isCosmWasmAdmittedPfAssetsQnV1 "pf.assets.native.transferAsync")
    "native.transferAsync must NOT be admitted"
  expect (PfAssetsCatalogV1.tokenBindingsV1.size == 1)
    "exactly one token binding (token.transfer)"
  expect (PfAssetsCatalogV1.tokenBindingsV1[0]!.qn == "pf.assets.token.transfer")
    "token binding QN is token.transfer"
  expect (PfAssetsCatalogV1.tokenBindingsV1[0]!.admittedForMaterialization)
    "token.transfer must be admitted for materialization"
  expect (PfAssetsCatalogV1.envReadBindingsV1.size == 2)
    "exactly two env-read bindings (native + token balanceOfSelf)"
  expect (PfAssetsCatalogV1.envReadBindingsV1.all (·.admittedForMaterialization))
    "env-read bindings must be admitted for materialization"
  expect (PfAssetsCatalogV1.envReadBindingsV1[0]!.qn == "pf.assets.native.balanceOfSelf")
    "first env-read binding is native.balanceOfSelf"
  expect (PfAssetsCatalogV1.envReadBindingsV1[1]!.qn == "pf.assets.token.balanceOfSelf")
    "second env-read binding is token.balanceOfSelf"
  expect (PfAssetsCatalogV1.envReadLoweringContractV1.nativeDenom == "stake")
    "env-read frozen denom is stake"

/-- E2-4-CW: native balanceOfSelf in a view lowers to nativeVaultBalance Expr
    (read-only query_chain bank balance). -/
private def envReadNativeSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CwEnvReadNative where\n" ++
  pfAssetsRequiresBlock ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

/-- E2-4-CW: token balanceOfSelf in a view lowers to tokenVaultBalance Statement
    (read-only query_chain CW20 smart-query). -/
private def envReadTokenSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CwEnvReadToken where\n" ++
  pfAssetsRequiresBlock ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view tokenBalance(mint : Principal) : UInt64 do\n" ++
  "    return pf.assets.token.balanceOfSelf(mint)\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

/-- E2-4-CW: envRead in a pureFn must fail closed at Plan (host read not pure). -/
private def envReadPureFnSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CwEnvReadPureFn where\n" ++
  pfAssetsRequiresBlock ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  fn pureBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

/-- E2-4-CW: envRead without extension.pf-assets must fail closed at Plan. -/
private def envReadNoExtSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program CwEnvReadNoExt where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

unsafe def testEnvReadNativePlan : IO Unit := do
  let compiled ← compileSource "<cw-envread-native>"
    "Tests.CwEnvReadNative" envReadNativeSource
  let plan ← planCwOf compiled
  -- view nativeBalance must contain a nativeVaultBalance Expr in its return.
  let some viewMethod := plan.entries.find? (·.mode == .view) |
    throw <| IO.userError "nativeBalance viewMethod must exist"
  let hasEnvRead := viewMethod.body.any fun st => match st with
    | .returnValue v => match v with | .nativeVaultBalance => true | _ => false
    | _ => false
  expect hasEnvRead "nativeBalance viewMethod must return .nativeVaultBalance expr"
  -- Plan validates.
  match validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"env-read native plan must validate: {e.render}"

unsafe def testEnvReadTokenPlan : IO Unit := do
  let compiled ← compileSource "<cw-envread-token>"
    "Tests.CwEnvReadToken" envReadTokenSource
  let plan ← planCwOf compiled
  let some viewMethod := plan.entries.find? (·.mode == .view) |
    throw <| IO.userError "tokenBalance viewMethod must exist"
  let hasEnvRead := viewMethod.body.any fun st => match st with
    | .tokenVaultBalance .. => true | _ => false
  expect hasEnvRead "tokenBalance viewMethod must contain .tokenVaultBalance statement"

unsafe def testEnvReadPureFnFailClosed : IO Unit := do
  let compiled ← compileSource "<cw-envread-purefn>"
    "Tests.CwEnvReadPureFn" envReadPureFnSource
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.cosmwasm none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .cosmwasm msg) =>
      expect (msg.contains "pureFn" || msg.contains "envRead" || msg.contains "pure")
        s!"pureFn envRead must cite pureFn, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "pureFn envRead must fail closed"

unsafe def testEnvReadNoExtFailClosed : IO Unit := do
  -- E2-2a typed-layer gate: env-read without the extension declaration fails
  -- at compile (before any target plan) with the exact 1.1.0 declaration
  -- requirement message.
  let session ← Tests.Language.ParserSession.shared
  let parsed ← liftResult (← session.selectProgramV1 envReadNoExtSource
    "<cw-envread-noext>" "Tests.CwEnvReadNoExt" none)
  match Compiler.compileValidatedSourceV1 parsed with
  | .error e =>
      expect (e.render.contains "requires the pf.assets@1.1.0 extension declaration")
        s!"no-extension envRead must cite the 1.1.0 declaration gate, got: {e.render}"
  | .ok _ =>
      throw <| IO.userError "envRead without extension must fail at compile"

unsafe def run : IO Unit := do
  testDepositTransferPlan
  testCatalogCallRequiresDeclaration
  testTokenTransferPlan
  testAsyncFailClosed
  testNonCatalogSyncFailClosed
  testCatalogAdmitSet
  testEnvReadNativePlan
  testEnvReadTokenPlan
  testEnvReadPureFnFailClosed
  testEnvReadNoExtFailClosed
  IO.println "Tests.Materialization.CosmWasmPfAssetsV1: ok"

end Tests.Materialization.CosmWasmPfAssetsV1
