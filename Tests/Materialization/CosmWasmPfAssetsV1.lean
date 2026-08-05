/-
  Tests.Materialization.CosmWasmPfAssetsV1 — ADR-0029 Phase C1 CosmWasm binding.

  Plan-level pins for the pf.assets CosmWasm lane:
    * `pf.assets.native.deposit(amount)` lowers to `.nativeDeposit` (exact
      one-coin info.funds check at runtime; frozen denom "stake")
    * `pf.assets.native.transfer(dst, amount)` lowers to `.nativeTransfer`
      (BankMsg::Send SubMsg, reply_on=never error-propagating)
    * catalog QN requires exact `extension.pf-assets` row (declaration gate)
    * token/async QNs fail closed (Phase C scope)
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
  "  requires extension pf.assets version \"1.0.0\"\n" ++
  "    digest \"sha256:97dfde7f7df228230828db4273086224bc28a4bc88c2f25457eaf0aee22aeeed\"\n"

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

/-- Token and async QNs fail closed (Phase C scope). -/
unsafe def testTokenAndAsyncFailClosed : IO Unit := do
  let mkSource (callText : String) : String :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program Scope where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call " ++ callText ++ "\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  for (label, callSpelling, needle) in #[
      ("token", "pf.assets.token.transfer(mint, dst, amount)", "token"),
      ("async", "pf.assets.native.transferAsync(dst, amount)", "Phase C") ] do
    let compiled ← compileSource s!"<cw-pf-assets-{label}>"
      s!"Tests.CwPfAssets{label}" (mkSource callSpelling)
    let selection ← liftResult <|
      Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.cosmwasm none
    let capability ← liftResult <|
      Targets.resolveEngineeringRequirementsV1 selection compiled
    match planFromCapability capability with
    | .error (.planInvariant .cosmwasm msg) =>
        expect (msg.contains needle || msg.contains "Phase C")
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

unsafe def run : IO Unit := do
  testDepositTransferPlan
  testCatalogCallRequiresDeclaration
  testTokenAndAsyncFailClosed
  testNonCatalogSyncFailClosed
  IO.println "Tests.Materialization.CosmWasmPfAssetsV1: ok"

end Tests.Materialization.CosmWasmPfAssetsV1
