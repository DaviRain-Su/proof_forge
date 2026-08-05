/-
  Tests.Materialization.NearPfAssetsV1 — ADR-0029 Phase C2 + ADR-0030 E1/E2-NEAR
  NEAR pf.assets binding.

  Plan-level pins for the pf.assets NEAR lane:
    * `pf.assets.native.deposit(amount)` lowers to `.nativeDeposit` with exact
      `attached_deposit == amount` emission (u128 lo/hi check in WAT)
    * `pf.assets.native.transferAsync(dst, amount)` lowers to `.promiseTransfer`
      (fire-and-forget `promise_batch_action_transfer`; no response cursor)
    * `pf.assets.token.transferAsync(mint, dst, amount)` lowers to
      `.promiseTokenTransfer` (fire-and-forget NEP-141 `ft_transfer`
      `promise_batch_action_function_call`; 1 yoctoNEAR deposit; JSON args)
    * `pf.assets.native.balanceOfSelf()` lowers to `.accountBalance` (host
      `account_balance` + UInt64 range guard); view/entry-callable
    * `pf.assets.token.balanceOfSelf` permanently fail closed (async NEP-141 view)
    * catalog QN requires exact `extension.pf-assets` row (declaration gate)
    * sync `pf.assets.native.transfer` permanently fail closed (Promise async)
    * sync `pf.assets.token.transfer` permanently fail closed (NEP-141 async)
    * token.transferAsync declaration gate (no extension → fail closed)
    * non-catalog sync calls fail closed
    * host imports: function-call action present iff a schedule or
      tokenTransferAsync is lowered; transfer action present iff a
      transferAsync is lowered; promise batch create present for any promise;
      account_balance present iff native balanceOfSelf is lowered
-/
import ProofForgeV2
import ProofForgeV2.Targets.Near
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.NearPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.Near

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

private unsafe def planNearOf (compiled : CompiledSemanticV1) : IO Plan := do
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  liftResult <| planFromCapability capability

private def tipJarAsyncSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program TipAsync where\n" ++
  pfAssetsRequiresBlock ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.deposit(amount)\n" ++
  "    call pf.assets.native.transferAsync(dst, amount)\n" ++
  "    tips := tips + amount\n" ++
  "    return tips\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

private def tokenJarAsyncSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program TokenJarAsync where\n" ++
  pfAssetsRequiresBlock ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  "  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.token.transferAsync(mint, dst, amount)\n" ++
  "    tips := tips + amount\n" ++
  "    return tips\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

/-- Positive: deposit + transferAsync lower into the tip entry body in source
    order, and the Plan validates (canonical NEAR descriptor policies). -/
unsafe def testDepositTransferAsyncPlan : IO Unit := do
  let compiled ← compileSource "<near-pf-assets>" "Tests.NearPfAssetsTip" tipJarAsyncSource
  let plan ← planNearOf compiled
  let some tip := plan.entries[0]? |
    throw <| IO.userError "tip entry must exist"
  let deposits := tip.body.filter fun st => match st with
    | .nativeDeposit _ => true | _ => false
  let transfers := tip.body.filter fun st => match st with
    | .promiseTransfer .. => true | _ => false
  expect (deposits.size == 1) "tip must contain exactly one nativeDeposit"
  expect (transfers.size == 1) "tip must contain exactly one promiseTransfer"
  -- Source order: deposit before transfer before the store.
  let depositIdx := tip.body.findIdx? fun st => match st with
    | .nativeDeposit _ => true | _ => false
  let transferIdx := tip.body.findIdx? fun st => match st with
    | .promiseTransfer .. => true | _ => false
  let storeIdx := tip.body.findIdx? fun st => match st with
    | .store _ | .storeAtomic _ => true | _ => false
  match depositIdx, transferIdx, storeIdx with
  | some d, some t, some s =>
      expect (d < t && t < s) "source order: deposit < transferAsync < store"
  | _, _, _ => throw <| IO.userError "tip body missing deposit/transfer/store"
  -- Host imports: transfer action present (transferAsync), function-call absent
  -- (no schedule in program), promise batch create present (shared by both).
  let imports := plan.hostImports
  expect (imports.contains .promiseBatchActionTransfer)
    "plan must import promise_batch_action_transfer"
  expect (imports.contains .promiseBatchCreate)
    "plan must import promise_batch_create"
  expect (!imports.contains .promiseBatchActionFunctionCall)
    "plan must not import function-call action (no schedule in program)"

/-- Positive: token.transferAsync lowers to promiseTokenTransfer in the entry
    body in source order, and the Plan validates. Host imports include
    function-call action (used by NEP-141 ft_transfer) + promise batch create,
    but NOT transfer action (no native transferAsync in this program). -/
unsafe def testTokenTransferAsyncPlan : IO Unit := do
  let compiled ← compileSource "<near-pf-assets-token-async>"
    "Tests.NearPfAssetsTokenAsync" tokenJarAsyncSource
  let plan ← planNearOf compiled
  let some tip := plan.entries[0]? |
    throw <| IO.userError "tipToken entry must exist"
  let tokenTransfers := tip.body.filter fun st => match st with
    | .promiseTokenTransfer .. => true | _ => false
  expect (tokenTransfers.size == 1)
    "tipToken must contain exactly one promiseTokenTransfer"
  -- Source order: tokenTransfer before the store.
  let transferIdx := tip.body.findIdx? fun st => match st with
    | .promiseTokenTransfer .. => true | _ => false
  let storeIdx := tip.body.findIdx? fun st => match st with
    | .store _ | .storeAtomic _ => true | _ => false
  match transferIdx, storeIdx with
  | some t, some s =>
      expect (t < s) "source order: tokenTransferAsync < store"
  | _, _ => throw <| IO.userError "tipToken body missing transfer/store"
  -- Host imports: function-call action present (token transferAsync uses it),
  -- promise batch create present, transfer action absent (no native transfer).
  let imports := plan.hostImports
  expect (imports.contains .promiseBatchActionFunctionCall)
    "plan must import promise_batch_action_function_call (token transferAsync)"
  expect (imports.contains .promiseBatchCreate)
    "plan must import promise_batch_create"
  expect (!imports.contains .promiseBatchActionTransfer)
    "plan must not import transfer action (no native transferAsync)"

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
    "    call pf.assets.native.transferAsync(dst, amount)\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<near-pf-assets-noext>" "Tests.NearPfAssetsNoExt" source
  -- Resolve succeeds (NEAR advertises sync-call + pf-assets); Plan must gate.
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "extension.pf-assets" || msg.contains "pf.assets catalog")
        s!"no-declaration must cite extension gate, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "pf.assets without extension must fail closed"

/-- Token transferAsync declaration gate: no extension → fail closed. -/
unsafe def testTokenTransferAsyncRequiresDeclaration : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program NoExtToken where\n" ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.token.transferAsync(mint, dst, amount)\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<near-pf-assets-token-noext>"
    "Tests.NearPfAssetsTokenNoExt" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "extension.pf-assets" || msg.contains "pf.assets catalog")
        s!"token no-declaration must cite extension gate, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "token.transferAsync without extension must fail closed"

/-- Sync transfer is permanently fail closed on NEAR (Promise is async). -/
unsafe def testSyncTransferPermanentlyFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SyncTip where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.native.transfer(dst, amount)\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<near-pf-assets-sync>" "Tests.NearPfAssetsSync" source
  match ← (do
      let selection ← liftResult <|
        Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
      liftResult <| Targets.resolveEngineeringRequirementsV1 selection compiled) with
  | capability =>
      match planFromCapability capability with
      | .error (.planInvariant .near msg) =>
          expect (msg.contains "permanently fail closed")
            s!"sync transfer must cite permanent fail closed, got: {msg}"
      | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
      | .ok _ => throw <| IO.userError "sync transfer must fail closed on NEAR"

/-- Sync token transfer is permanently fail closed on NEAR (NEP-141 is async). -/
unsafe def testSyncTokenTransferPermanentlyFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program SyncTokenTip where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  entry tipToken(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call pf.assets.token.transfer(mint, dst, amount)\n" ++
    "    return amount\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<near-pf-assets-sync-token>"
    "Tests.NearPfAssetsSyncToken" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "permanently fail closed")
        s!"sync token transfer must cite permanent fail closed, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "sync token transfer must fail closed on NEAR"

/-- Non-catalog sync calls stay fail closed (NEAR has no sync x-call). -/
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
  let compiled ← compileSource "<near-pf-assets-oracle>" "Tests.NearPfAssetsOracle" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "synchronous external calls" || msg.contains "outside the NEAR envelope")
        s!"non-catalog sync must cite NEAR envelope, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "non-catalog sync call must fail closed on NEAR"

/-- IR emission: token.transferAsync produces valid IR (wat2wasm-ready WAT).
    Verifies that the build succeeds and the WAT output file contains the
    ft_transfer promise_batch_action_function_call with the correct host import. -/
unsafe def testTokenTransferAsyncIR : IO Unit := do
  let compiled ← compileSource "<near-pf-assets-token-ir>"
    "Tests.NearPfAssetsTokenIR" tokenJarAsyncSource
  let plan ← planNearOf compiled
  let capability ← (do
      let selection ← liftResult <|
        Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
      liftResult <| Targets.resolveEngineeringRequirementsV1 selection compiled)
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  -- Find the .wat file and check its content.
  let watFile := files.find? (fun f => f.path.endsWith ".wat")
  let some wat := watFile |
    throw <| IO.userError "build must produce a .wat output file"
  let watContent := wat.contents
  expect (watContent.contains "ft_transfer")
    "WAT must contain ft_transfer method string"
  expect (watContent.contains "promise_batch_action_function_call")
    "WAT must contain promise_batch_action_function_call import"
  expect (watContent.contains "promise_batch_create")
    "WAT must contain promise_batch_create import"
  -- Deposit policy: entry has no nativeDeposit → requireZero.
  let some tip := plan.entries[0]? |
    throw <| IO.userError "tipToken entry must exist"
  expect (tip.depositPolicy == .requireZero)
    "token transferAsync entry must be requireZero (1 yocto comes from contract balance)"

private def envReadJarSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EnvReadJar where\n" ++
  pfAssetsRequiresBlock ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  "  entry acceptNative(amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.deposit(amount)\n" ++
  "    tips := tips + amount\n" ++
  "    return tips\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

/-- ADR-0030 E2-NEAR: native balanceOfSelf lowers to accountBalance in a view;
    host import account_balance is present; pureFn/token stay fail closed. -/
unsafe def testNativeBalanceOfSelfPlan : IO Unit := do
  let compiled ← compileSource "<near-pf-assets-envread>"
    "Tests.NearPfAssetsEnvRead" envReadJarSource
  let plan ← planNearOf compiled
  let some balView := plan.entries.find? (·.name == "nativeBalance") |
    throw <| IO.userError "nativeBalance view must exist"
  expect (balView.mode == .view) "nativeBalance must be a view"
  -- Bare `return pf.assets.native.balanceOfSelf()` lowers to a single
  -- returnValue of the accountBalance leaf expr.
  let hasAccountBalance := balView.body.any fun st =>
    match st with
    | .returnValue .accountBalance => true
    | _ => false
  expect hasAccountBalance "nativeBalance view must return accountBalance"
  expect (plan.hostImports.contains .accountBalance)
    "plan must import account_balance when native balanceOfSelf is used"
  -- Deposit entry still present and ordered.
  let some accept := plan.entries.find? (·.name == "acceptNative") |
    throw <| IO.userError "acceptNative entry must exist"
  let deposits := accept.body.filter fun st => match st with
    | .nativeDeposit _ => true | _ => false
  expect (deposits.size == 1) "acceptNative must contain exactly one nativeDeposit"

/-- E2-NEAR: token balanceOfSelf permanently fail closed with precise diagnosis. -/
unsafe def testTokenBalanceOfSelfPermanentlyFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program TokenBal where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  view tokenBalance(mint : Principal) : UInt64 do\n" ++
    "    return pf.assets.token.balanceOfSelf(mint)\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<near-pf-assets-token-bal>"
    "Tests.NearPfAssetsTokenBal" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "permanently fail closed" &&
          (msg.contains "ft_balance_of" || msg.contains "async cross-contract"))
        s!"token balanceOfSelf must cite permanent FC + NEP-141 reason, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "token.balanceOfSelf must fail closed on NEAR"

/-- E2-NEAR: pureFn cannot use envRead (host read is not pure). -/
unsafe def testEnvReadPureFnFailClosed : IO Unit := do
  let source :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program PureEnv where\n" ++
    pfAssetsRequiresBlock ++
    "  state tips : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    tips := initial\n" ++
    "  fn peek() : UInt64 do\n" ++
    "    return pf.assets.native.balanceOfSelf()\n" ++
    "  entry run() : UInt64 do\n" ++
    "    return peek()\n" ++
    "  view get() : UInt64 do\n" ++
    "    return tips\n"
  let compiled ← compileSource "<near-pf-assets-pure-env>"
    "Tests.NearPfAssetsPureEnv" source
  let selection ← liftResult <|
    Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error (.planInvariant .near msg) =>
      expect (msg.contains "pureFn" && msg.contains "envRead")
        s!"pureFn envRead must cite pureFn/host-read, got: {msg}"
  | .error e => throw <| IO.userError s!"expected planInvariant, got {e.render}"
  | .ok _ => throw <| IO.userError "pureFn envRead must fail closed on NEAR"

/-- E2-NEAR IR/WAT: native balanceOfSelf emits account_balance import + hi-word guard. -/
unsafe def testNativeBalanceOfSelfIR : IO Unit := do
  let compiled ← compileSource "<near-pf-assets-envread-ir>"
    "Tests.NearPfAssetsEnvReadIR" envReadJarSource
  let capability ← (do
      let selection ← liftResult <|
        Targets.BuildSelectionV1.resolveBuildSelectionV1 TargetId.near none
      liftResult <| Targets.resolveEngineeringRequirementsV1 selection compiled)
  let files ← liftResult <| Targets.Near.buildFromCapability capability
  let watFile := files.find? (fun f => f.path.endsWith ".wat")
  let some wat := watFile |
    throw <| IO.userError "build must produce a .wat output file"
  let watContent := wat.contents
  expect (watContent.contains "account_balance")
    "WAT must contain account_balance host import"
  expect (watContent.contains "pf_account_balance")
    "WAT must bind $pf_account_balance"
  -- Range guard: high word load compared against zero then unreachable.
  expect (watContent.contains "unreachable")
    "WAT must contain unreachable (UInt64 range guard on hi word)"

unsafe def run : IO Unit := do
  testDepositTransferAsyncPlan
  testTokenTransferAsyncPlan
  testCatalogCallRequiresDeclaration
  testTokenTransferAsyncRequiresDeclaration
  testSyncTransferPermanentlyFailClosed
  testSyncTokenTransferPermanentlyFailClosed
  testNonCatalogSyncFailClosed
  testTokenTransferAsyncIR
  testNativeBalanceOfSelfPlan
  testTokenBalanceOfSelfPermanentlyFailClosed
  testEnvReadPureFnFailClosed
  testNativeBalanceOfSelfIR
  IO.println "Tests.Materialization.NearPfAssetsV1: ok"

end Tests.Materialization.NearPfAssetsV1
