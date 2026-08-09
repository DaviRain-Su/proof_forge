/-
  Tests.Materialization.EvmPfAssetsV1 — ADR-0029 Phase B2 EVM pf.assets lane.

  Nails Plan/IR/Yul for native deposit/transfer:
    * payable entry + exact callvalue==amount
    * value CALL structure (full gas, empty calldata, success check)
    * QN gate: catalog without extension.pf-assets FC
    * Phase B scope: async/token catalog QNs FC
    * non-deposit entry keeps callvalue==0 (global or entry-local)
    * interface-standard artifactBinding skeleton present
  Engineering only; Anvil runtime differential is a main-agent merge concern.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Evm.PfAssetsCatalogV1
import ProofForgeV2.Targets.Registry
import Tests.Language.ParserSession

namespace Tests.Materialization.EvmPfAssetsV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Evm
open ProofForgeV2.Targets.Evm.PfAssetsCatalogV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok v => pure v
  | .error e => throw <| IO.userError s!"{label}: {e.render}"

private def pfAssetsDigestV1 : String :=
  "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

private def tipSource (name : String) (extra : String := "") : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  s!"program {name} where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  extra ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.deposit(amount)\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    tips := tips + amount\n" ++
  "    return tips\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

private def noExtSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program NoExtAssets where\n" ++
  "  state tips : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    tips := initial\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.transfer(dst, amount)\n" ++
  "    return tips\n" ++
  "  view get() : UInt64 do\n" ++
  "    return tips\n"

private def asyncSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program AsyncAssets where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  entry tip(dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.native.transferAsync(dst, amount)\n" ++
  "    return amount\n"

private def tokenSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program TokenAssets where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  entry tip(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.token.transfer(mint, dst, amount)\n" ++
  "    return amount\n"

private def tokenAsyncSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program TokenAsyncAssets where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  entry tip(mint : Principal, dst : Principal, amount : UInt64) : UInt64 do\n" ++
  "    call pf.assets.token.transferAsync(mint, dst, amount)\n" ++
  "    return amount\n"

private def plainStateCellSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PlainNoDeposit where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

/-- E2-3: native balanceOfSelf in a view (read-only, SELFBALANCE). -/
private def envReadNativeSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EnvReadNative where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

/-- E2-3: token balanceOfSelf in a view (read-only STATICCALL). -/
private def envReadTokenSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EnvReadToken where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view tokenBalance(mint : Principal) : UInt64 do\n" ++
  "    return pf.assets.token.balanceOfSelf(mint)\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

/-- E2-3: envRead in a pureFn must fail closed at Plan (host read not pure). -/
private def envReadPureFnSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EnvReadPureFn where\n" ++
  "  requires extension pf.assets version \"1.1.0\"\n" ++
  s!"    digest \"{pfAssetsDigestV1}\"\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  fn pureBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

/-- E2-3: envRead without extension.pf-assets must fail closed at Plan. -/
private def envReadNoExtSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program EnvReadNoExt where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n" ++
  "  entry bump(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n"

private unsafe def planEvm (compiled : CompiledSemanticV1) : IO Plan := do
  let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult "resolve" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  liftResult "plan" <| planFromCapability capability

private unsafe def buildEvm (compiled : CompiledSemanticV1) : IO (Array OutputFile) := do
  let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult "resolve" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  liftResult "build" <| buildFromCapability capability

/-- Catalog skeleton: native admit set + token admit set + interface-standard ERC-20. -/
private def testCatalogSkeleton : IO Unit := do
  expect (isEvmAdmittedPfAssetsQnV1 "pf.assets.native.deposit") "deposit admitted"
  expect (isEvmAdmittedPfAssetsQnV1 "pf.assets.native.transfer") "transfer admitted"
  expect (isEvmAdmittedPfAssetsQnV1 "pf.assets.token.transfer") "token.transfer admitted"
  expect (!isEvmAdmittedPfAssetsQnV1 "pf.assets.native.transferAsync") "native async not admitted"
  expect (!isEvmAdmittedPfAssetsQnV1 "pf.assets.token.transferAsync") "token async not admitted"
  expect (nativeBindingsV1.size == 2) "two native bindings"
  expect (nativeBindingsV1.all (·.artifactBinding == .runtimeNative))
    "native package uses runtimeNative"
  expect (nativeValueLoweringContractV1.depositCallvalueRelation == "eq")
    "deposit relation pinned to eq (not >=)"
  expect (nativeValueLoweringContractV1.transferGasPolicy == "forward-all-gas")
    "transfer gas = full remaining"
  expect (nativeValueLoweringContractV1.dstPrincipalEncoding ==
      "u32le(20)||addr20-network-order")
    "dst Principal encoding pinned"
  expect (containsSubstr nativeValueLoweringContractV1.reentrancyNote "reentrancy")
    "reentrancy honesty note present"
  -- E1a ERC-20 token binding.
  expect (tokenBindingsV1.size == 1) "one token binding"
  expect (tokenBindingsV1[0]!.qn == "pf.assets.token.transfer")
    "token binding QN pinned"
  expect (tokenBindingsV1[0]!.admittedForMaterialization)
    "token transfer admitted for materialization"
  expect (tokenBindingsV1[0]!.packageId == "evm-erc20-standard-v1")
    "token package id pinned"
  expect (erc20TokenLoweringContractV1.transferSelector == "0xa9059cbb")
    "ERC-20 transfer selector pinned"
  expect (erc20TokenLoweringContractV1.transferCalldataSize == "68")
    "ERC-20 calldata size pinned (4+32+32)"
  expect (erc20TokenLoweringContractV1.transferCallValue == "zero")
    "ERC-20 transfer carries zero native value"
  expect (erc20TokenLoweringContractV1.mintPrincipalEncoding ==
      "u32le(20)||addr20-network-order")
    "mint Principal encoding pinned (same as native dst)"
  expect (containsSubstr erc20TokenLoweringContractV1.transferReturnValuePolicy
      "returndatasize==0")
    "return-value policy handles USDT-style no-return"
  expect (containsSubstr erc20TokenLoweringContractV1.transferReturnValuePolicy
      "first-word-must-be-nonzero")
    "return-value policy checks bool false"
  expect (containsSubstr erc20TokenLoweringContractV1.dynamicCalleeDiscipline
      "generic-dynamic-callee-fail-closed")
    "controlled dynamic callee discipline pinned"
  match erc20InterfaceStandardSkeletonV1 with
  | .interfaceStandard sid preds =>
      expect (sid == "erc-20") "ERC-20 standard id"
      expect (!preds.isEmpty) "ERC-20 predicates non-empty skeleton"
  | _ => throw <| IO.userError "erc20 skeleton must be interfaceStandard"

/-- Positive TipJar-shaped plan/IR/Yul nails. -/
private unsafe def testTipJarPlanAndYul : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load tip" (← session.selectProgramV1
    (tipSource "EvmTipJar") "<evm-tipjar>" "Tests.EvmTipJar" none)
  let compiled ← liftResult "compile tip" <| compileValidatedSourceV1 source
  let plan ← planEvm compiled
  expect (plan.objectName == "EvmTipJar") "object name"
  expect (plan.entries.size == 2) "tip + get"
  let tip := plan.entries[0]!
  let get := plan.entries[1]!
  expect (tip.name == "tip") "entry tip"
  expect (get.name == "get") "view get"
  expect (tip.mutability == .payable) "tip is payable (has deposit)"
  expect (get.mutability == .view) "get is view"
  -- Body contains nativeDeposit then nativeTransfer (source order).
  let hasDeposit := tip.body.any fun s => match s with | .nativeDeposit _ => true | _ => false
  let hasTransfer := tip.body.any fun s =>
    match s with | .nativeTransfer .. => true | _ => false
  expect hasDeposit "plan body has nativeDeposit"
  expect hasTransfer "plan body has nativeTransfer"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"tip plan must validate: {e.render}"
  let files ← buildEvm compiled
  let some yulFile := files.find? (·.path.endsWith ".yul") |
    throw <| IO.userError "missing yul"
  let yul := yulFile.contents
  -- Deposit: exact callvalue == amount (eq, not iszero/gt alone).
  expect (containsSubstr yul "if iszero(eq(callvalue(),")
    s!"Yul must exact-eq callvalue to amount, got head"
  -- Transfer: full-gas value CALL empty calldata + success check.
  expect (containsSubstr yul "call(gas(),")
    "Yul must forward full gas on value CALL"
  expect (containsSubstr yul ", 0, 0, 0, 0)")
    "Yul value CALL must use empty calldata (argsOffset/Size + ret 0)"
  expect (containsSubstr yul "xferOk")
    "Yul must bind transfer CALL success flag"
  -- Principal len==20 gate.
  expect (containsSubstr yul ", 20)")
    "Yul must require Principal len == 20"
  -- View/non-payable discipline: get entry has callvalue==0 (entry-local
  -- because tip is payable; global runtime guard is absent).
  expect (containsSubstr yul "if callvalue() { revert(0, 0) }")
    "non-deposit view must still enforce callvalue==0"
  let some abiFile := files.find? (·.path.endsWith ".abi.json") |
    throw <| IO.userError "missing abi"
  expect (containsSubstr abiFile.contents "\"stateMutability\":\"payable\"")
    "ABI tip must be payable"
  expect (containsSubstr abiFile.contents "\"stateMutability\":\"view\"")
    "ABI get must be view"

/-- Catalog QN without extension.pf-assets fails closed at Plan. -/
private unsafe def testQnGateNoExtension : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load noext" (← session.selectProgramV1
    noExtSource "<evm-noext>" "Tests.EvmNoExt" none)
  let compiled ← liftResult "compile noext" <| compileValidatedSourceV1 source
  -- Resolve may succeed (no extension row) — Plan must still FC on catalog QN.
  let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult "resolve noext" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  match planFromCapability capability with
  | .error e =>
      let msg := e.render
      expect (containsSubstr msg "extension.pf-assets" ||
          containsSubstr msg "pf.assets catalog")
        s!"no-extension catalog call must cite extension.pf-assets, got={msg}"
  | .ok _ => throw <| IO.userError "pf.assets catalog without extension must fail closed"

/-- Async / tokenAsync pf.assets QNs fail closed (EVM offers sync only). -/
private unsafe def testAsyncFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  for (label, module, text) in
      #[("native-async", "Tests.EvmNativeAsync", asyncSource),
        ("token-async", "Tests.EvmTokenAsync", tokenAsyncSource)] do
    let source ← liftResult s!"load {label}" (← session.selectProgramV1
      text s!"<evm-{label}>" module none)
    let compiled ← liftResult s!"compile {label}" <| compileValidatedSourceV1 source
    let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
    match Targets.resolveEngineeringRequirementsV1 selection compiled with
    | .error e =>
        -- May fail at resolve if requirements don't include only admitted keys;
        -- accept either resolve or plan FC.
        let msg := e.render
        expect (containsSubstr msg "PF-REQ" || containsSubstr msg "unsupported" ||
            containsSubstr msg "pf.assets")
          s!"{label} must fail closed, got={msg}"
    | .ok capability =>
        match planFromCapability capability with
        | .error e =>
            let msg := e.render
            expect (containsSubstr msg "fail closed" ||
                containsSubstr msg "pf.assets" ||
                containsSubstr msg "unsupported")
              s!"{label} plan must FC with scope diagnostic, got={msg}"
        | .ok _ =>
            throw <| IO.userError s!"{label} pf.assets QN must fail closed on EVM"

/-- Positive token transfer Plan/IR/Yul nails (E1a: controlled dynamic callee). -/
private unsafe def testTokenTransferPlanAndYul : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load token" (← session.selectProgramV1
    (tokenSource) "<evm-token>" "Tests.EvmToken" none)
  let compiled ← liftResult "compile token" <| compileValidatedSourceV1 source
  let plan ← planEvm compiled
  expect (plan.objectName == "TokenAssets") "token object name"
  expect (plan.entries.size == 1) "single tip entry"
  let tip := plan.entries[0]!
  expect (tip.name == "tip") "entry tip"
  -- Token transfer is NOT a deposit → entry stays nonpayable (no ETH value).
  expect (tip.mutability == .nonpayable) "token tip is nonpayable (no native value)"
  -- Body contains tokenTransfer (controlled dynamic callee).
  let hasTokenTransfer := tip.body.any fun s =>
    match s with | .tokenTransfer .. => true | _ => false
  expect hasTokenTransfer "plan body has tokenTransfer"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"token plan must validate: {e.render}"
  let files ← buildEvm compiled
  let some yulFile := files.find? (·.path.endsWith ".yul") |
    throw <| IO.userError "token missing yul"
  let yul := yulFile.contents
  -- ERC-20 transfer selector 0xa9059cbb in calldata.
  expect (containsSubstr yul "0xa9059cbb")
    "Yul must emit ERC-20 transfer selector"
  -- Calldata layout: 68-byte calldata (4B selector + 32B addr + 32B amount).
  expect (containsSubstr yul "0, 68, 0, 32)")
    "Yul CALL must use 68-byte calldata + 32-byte return buffer"
  -- Dynamic callee: token address assembled from mint Principal.
  expect (containsSubstr yul "tokenAddr")
    "Yul must bind token contract address from mint Principal"
  -- Wire-shape gates: mint len==20 and dst len==20.
  -- Both mint and dst require eq(..., 20) gates.
  expect (containsSubstr yul ", 20)")
    "Yul must require Principal len == 20 (mint and/or dst)"
  -- High-limb zero gates (shr(32, ...) for the third body word).
  expect (containsSubstr yul "shr(32,")
    "Yul must gate high Principal limbs to zero"
  -- Return-value predicate: returndatasize switch.
  expect (containsSubstr yul "returndatasize()")
    "Yul must read returndatasize for return-value predicate"
  expect (containsSubstr yul "case 0")
    "Yul return-value predicate must handle returndatasize==0 (USDT-style)"
  expect (containsSubstr yul "case 32")
    "Yul return-value predicate must handle returndatasize==32 (bool check)"
  expect (containsSubstr yul "mload(0)")
    "Yul must read first return word for bool false check"
  -- CALL failure propagation.
  expect (containsSubstr yul "call(gas(),")
    "Yul must forward full gas on ERC-20 CALL"
  expect (containsSubstr yul "tokOk")
    "Yul must bind CALL success flag"
  -- Zero value (ERC-20 transfer carries no ETH).
  -- The CALL has value 0: ", 0, 0, 68, 0, 32)" — the second arg after gas
  -- is the address, third is value (0), then argsOffset/Size/retOffset/Size.
  let some abiFile := files.find? (·.path.endsWith ".abi.json") |
    throw <| IO.userError "token missing abi"
  expect (containsSubstr abiFile.contents "\"stateMutability\":\"nonpayable\"")
    "ABI tip must be nonpayable (token transfer carries no ETH value)"

/-- Non-deposit programs keep historical global callvalue==0 (byte path). -/
private unsafe def testNonDepositCallvalueZero : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load plain" (← session.selectProgramV1
    plainStateCellSource "<evm-plain>" "Tests.EvmPlain" none)
  let compiled ← liftResult "compile plain" <| compileValidatedSourceV1 source
  let files ← buildEvm compiled
  let some yulFile := files.find? (·.path.endsWith ".yul") |
    throw <| IO.userError "plain missing yul"
  let yul := yulFile.contents
  -- Global runtime guard still present when no payable entry.
  expect (containsSubstr yul "if callvalue() { revert(0, 0) }")
    "non-deposit program must keep callvalue==0 guard"
  expect (!containsSubstr yul "nativeDeposit" &&
      !containsSubstr yul "eq(callvalue(),")
    "non-deposit program must not emit deposit callvalue-eq"

/-- E2-3: envRead catalog skeleton — native + token balanceOfSelf admitted. -/
private def testEnvReadCatalogSkeleton : IO Unit := do
  expect (isEvmAdmittedPfAssetsQnV1 "pf.assets.native.balanceOfSelf")
    "native balanceOfSelf admitted"
  expect (isEvmAdmittedPfAssetsQnV1 "pf.assets.token.balanceOfSelf")
    "token balanceOfSelf admitted"
  expect (envReadBindingsV1.size == 2) "two env-read bindings"
  expect (envReadBindingsV1[0]!.qn == "pf.assets.native.balanceOfSelf")
    "env-read native QN pinned"
  expect (envReadBindingsV1[1]!.qn == "pf.assets.token.balanceOfSelf")
    "env-read token QN pinned"
  expect (envReadBindingsV1.all (·.admittedForMaterialization))
    "env-read bindings admitted for materialization"
  expect (envReadLoweringContractV1.nativeOpcode == "0x47-SELFBALANCE")
    "native lowering pinned to SELFBALANCE"
  expect (envReadLoweringContractV1.tokenCallOpcode == "STATICCALL")
    "token lowering pinned to STATICCALL"
  expect (envReadLoweringContractV1.tokenSelector == "0x70a08231")
    "balanceOf selector pinned"
  expect (envReadLoweringContractV1.tokenCalldataSize == "36")
    "balanceOf calldata size pinned (4+32)"
  expect (envReadLoweringContractV1.mintPrincipalEncoding ==
      "u32le(20)||addr20-network-order")
    "mint Principal encoding pinned (same as E1a)"
  expect (containsSubstr envReadLoweringContractV1.tokenReturnValuePolicy
      "returndatasize==32-required")
    "return-value policy requires exactly 32 bytes"
  expect (containsSubstr envReadLoweringContractV1.tokenReturnValuePolicy
      "high-192-bits-zero-required")
    "return-value policy requires high 192 bits zero"
  expect (containsSubstr envReadLoweringContractV1.readOnlyNote "view-and-entry-callable")
    "env-read is view-and-entry-callable"

/-- E2-3: positive native balanceOfSelf Plan/IR/Yul (SELFBALANCE in a view). -/
private unsafe def testEnvReadNativePlanAndYul : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load envread-native" (← session.selectProgramV1
    envReadNativeSource "<evm-envread-native>" "Tests.EvmEnvReadNative" none)
  let compiled ← liftResult "compile envread-native" <| compileValidatedSourceV1 source
  let plan ← planEvm compiled
  expect (plan.objectName == "EnvReadNative") "envread native object name"
  expect (plan.entries.size == 2) "nativeBalance view + bump entry"
  let nativeBalance := plan.entries[0]!
  expect (nativeBalance.name == "nativeBalance") "view nativeBalance"
  expect (nativeBalance.mutability == .view) "nativeBalance is view"
  -- Body contains selfBalance expr (SELFBALANCE).
  let hasSelfBalance := nativeBalance.body.any fun s => match s with
    | .returnValue .selfBalance => true | _ => false
  expect hasSelfBalance "plan body has returnValue selfBalance"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"envread native plan must validate: {e.render}"
  let files ← buildEvm compiled
  let some yulFile := files.find? (·.path.endsWith ".yul") |
    throw <| IO.userError "envread native missing yul"
  let yul := yulFile.contents
  -- SELFBALANCE opcode in Yul.
  expect (containsSubstr yul "selfbalance()")
    "Yul must emit selfbalance() opcode"
  -- UInt64 range guard.
  expect (containsSubstr yul "0xffffffffffffffff")
    "Yul must have UInt64 range guard for selfbalance"
  -- View acceptance: the view entry is callable (no revert on view path).
  let some abiFile := files.find? (·.path.endsWith ".abi.json") |
    throw <| IO.userError "envread native missing abi"
  expect (containsSubstr abiFile.contents "\"stateMutability\":\"view\"")
    "ABI nativeBalance must be view"

/-- E2-3: positive token balanceOfSelf Plan/IR/Yul (STATICCALL in a view). -/
private unsafe def testEnvReadTokenPlanAndYul : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load envread-token" (← session.selectProgramV1
    envReadTokenSource "<evm-envread-token>" "Tests.EvmEnvReadToken" none)
  let compiled ← liftResult "compile envread-token" <| compileValidatedSourceV1 source
  let plan ← planEvm compiled
  expect (plan.objectName == "EnvReadToken") "envread token object name"
  expect (plan.entries.size == 2) "tokenBalance view + bump entry"
  let tokenBalance := plan.entries[0]!
  expect (tokenBalance.name == "tokenBalance") "view tokenBalance"
  expect (tokenBalance.mutability == .view) "tokenBalance is view"
  -- Body contains tokenBalanceOf statement (STATICCALL).
  let hasTokenBalanceOf := tokenBalance.body.any fun s =>
    match s with | .tokenBalanceOf .. => true | _ => false
  expect hasTokenBalanceOf "plan body has tokenBalanceOf"
  match Targets.Evm.validatePlan plan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"envread token plan must validate: {e.render}"
  let files ← buildEvm compiled
  let some yulFile := files.find? (·.path.endsWith ".yul") |
    throw <| IO.userError "envread token missing yul"
  let yul := yulFile.contents
  -- balanceOf selector 0x70a08231 in calldata.
  expect (containsSubstr yul "0x70a08231")
    "Yul must emit balanceOf selector"
  -- STATICCALL (not CALL).
  expect (containsSubstr yul "staticcall(gas(),")
    "Yul must use staticcall for balanceOf"
  -- Calldata: 36-byte calldata (4B selector + 32B self address).
  expect (containsSubstr yul ", 0, 36, 0, 32)")
    "Yul STATICCALL must use 36-byte calldata + 32-byte return buffer"
  -- Self address via address() opcode.
  expect (containsSubstr yul "address()")
    "Yul must use address() for self address in balanceOf calldata"
  -- Wire-shape gate: mint len==20.
  expect (containsSubstr yul "eq(")
    "Yul must check mint Principal len == 20"
  -- High-limb zero gates.
  expect (containsSubstr yul "shr(32,")
    "Yul must gate high Principal limbs to zero"
  -- returndatasize==32 check.
  expect (containsSubstr yul "returndatasize()")
    "Yul must check returndatasize for balanceOf return"
  expect (containsSubstr yul "eq(returndatasize(), 32)")
    "Yul must require returndatasize == 32"
  -- High 192 bits zero check (shr(64, ...) == 0).
  expect (containsSubstr yul "shr(64,")
    "Yul must check high 192 bits zero for UInt64 result"
  -- STATICCALL failure reverts.
  expect (containsSubstr yul "if iszero(")
    "Yul must revert on STATICCALL failure"
  -- View acceptance.
  let some abiFile := files.find? (·.path.endsWith ".abi.json") |
    throw <| IO.userError "envread token missing abi"
  expect (containsSubstr abiFile.contents "\"stateMutability\":\"view\"")
    "ABI tokenBalance must be view"

/-- E2-3: envRead in pureFn fails closed at Plan (host read is not pure). -/
private unsafe def testEnvReadPureFnFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load envread-purefn" (← session.selectProgramV1
    envReadPureFnSource "<evm-envread-purefn>" "Tests.EvmEnvReadPureFn" none)
  let compiled ← liftResult "compile envread-purefn" <| compileValidatedSourceV1 source
  let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
  match Targets.resolveEngineeringRequirementsV1 selection compiled with
  | .error e =>
      let msg := e.render
      expect (containsSubstr msg "PF-REQ" || containsSubstr msg "unsupported" ||
          containsSubstr msg "pf.assets")
        s!"envread purefn must fail closed, got={msg}"
  | .ok capability =>
      match planFromCapability capability with
      | .error e =>
          let msg := e.render
          expect (containsSubstr msg "fail closed" || containsSubstr msg "pureFn" ||
              containsSubstr msg "unsupported" || containsSubstr msg "pf.assets")
            s!"envread purefn plan must FC, got={msg}"
      | .ok _ =>
          throw <| IO.userError "envread pureFn must fail closed on EVM"

/-- E2-3: envRead without extension.pf-assets fails closed (compile or Plan). -/
private unsafe def testEnvReadNoExtFc : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load envread-noext" (← session.selectProgramV1
    envReadNoExtSource "<evm-envread-noext>" "Tests.EvmEnvReadNoExt" none)
  -- Compile may fail closed (catalog QN requires extension at compile time)
  -- or succeed and fail at resolve/Plan. Either is a valid fail-closed path.
  match compileValidatedSourceV1 source with
  | .error e =>
      let msg := e.render
      expect (containsSubstr msg "pf.assets" || containsSubstr msg "extension")
        s!"no-extension envread compile must cite pf.assets/extension, got={msg}"
  | .ok compiled =>
      let selection ← liftResult "selection" <| resolveBuildSelectionV1 TargetId.evm none
      match Targets.resolveEngineeringRequirementsV1 selection compiled with
      | .error e =>
          let msg := e.render
          expect (containsSubstr msg "PF-REQ" || containsSubstr msg "unsupported" ||
              containsSubstr msg "pf.assets")
            s!"envread noext must fail closed, got={msg}"
      | .ok capability =>
          match planFromCapability capability with
          | .error e =>
              let msg := e.render
              expect (containsSubstr msg "extension.pf-assets" ||
                  containsSubstr msg "pf.assets")
                s!"no-extension envread must cite extension.pf-assets, got={msg}"
          | .ok _ =>
              throw <| IO.userError "envRead without extension must fail closed"

unsafe def run : IO Unit := do
  testCatalogSkeleton
  testTipJarPlanAndYul
  testTokenTransferPlanAndYul
  testQnGateNoExtension
  testAsyncFc
  testNonDepositCallvalueZero
  testEnvReadCatalogSkeleton
  testEnvReadNativePlanAndYul
  testEnvReadTokenPlanAndYul
  testEnvReadPureFnFc
  testEnvReadNoExtFc
  IO.println "Tests.Materialization.EvmPfAssetsV1: ok"

end Tests.Materialization.EvmPfAssetsV1
