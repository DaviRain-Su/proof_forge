/-
Layer B Protocols smoke: catalog + EVM IERC20/721 examples + NEAR FT peer
example + Solana facade inventory.
-/
import ProofForge.Protocols
import ProofForge.Target.ProtocolMaterialize
import ProofForge.Backend.Evm.IR
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.Solana.Extension.Cpi
import ProofForge.Contract.Builder
import ProofForge.Contract.Surface
import Examples.Backend.Evm.Contracts.Ierc20Client
import Examples.Backend.Evm.Contracts.Ierc20PermitClient
import Examples.Backend.Evm.Contracts.Ierc4626Client
import Examples.Backend.Evm.Contracts.Ierc721Client
import Examples.Backend.Evm.Contracts.MulticallClient
import Examples.Backend.Evm.Contracts.Permit2Client
import Examples.Backend.WasmNear.FtPeerClient

namespace ProofForge.Tests.ProtocolsLayer

open ProofForge.Contract.Builder

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def main : IO UInt32 := do
  require (ProofForge.Protocols.layerId == "protocols") "layer id"
  require (ProofForge.Protocols.primaryHosts.contains "evm") "hosts include evm"
  require (ProofForge.Protocols.Solana.catalogId == "protocols.solana") "solana catalog"
  require (ProofForge.Protocols.Solana.knownFamilies.contains "spl-token") "spl-token family"
  require (ProofForge.Protocols.Solana.knownFamilies.contains "token-2022") "token-2022 family"
  require (ProofForge.Protocols.Solana.supportedDataLayouts.contains "spl-token.initialize_account3")
    "inventory lists initialize_account3"
  require (ProofForge.Protocols.Solana.supportedDataLayouts.contains "token-2022.pause")
    "inventory lists token-2022.pause"
  require (ProofForge.Protocols.Solana.rejectedLayoutExamples.any (·.contains "confidential"))
    "inventory documents confidential reject"
  require (ProofForge.Protocols.Evm.IERC20.catalogId == "protocols.evm.ierc20") "ierc20 catalog"
  require (ProofForge.Protocols.Evm.IERC721.catalogId == "protocols.evm.ierc721") "ierc721 catalog"
  require (ProofForge.Protocols.Evm.IERC20.selectorTransfer == 0xa9059cbb) "transfer selector"
  require (ProofForge.Protocols.Evm.IERC721.selectorOwnerOf == 0x6352211e) "ownerOf selector"
  require (ProofForge.Protocols.Evm.IERC721.selectorSafeTransferFrom == 0x42842e0e)
    "safeTransferFrom selector"
  require (ProofForge.Protocols.Evm.Multicall.catalogId == "protocols.evm.multicall")
    "multicall catalog"
  require (ProofForge.Protocols.Evm.Multicall.selectorAggregate3 == 0x82ad56cb)
    "multicall aggregate3 selector"
  -- AbiEncode-backed aggregate layout (empty Call[]).
  let agg0 := ProofForge.Protocols.Evm.Multicall.encodeAggregate #[]
  require (ProofForge.Backend.Evm.AbiEncode.planWordAt? agg0 0 == some 0x20)
    "aggregate layout head 0x20"
  require (ProofForge.Backend.Evm.AbiEncode.planWordAt? agg0 0x20 == some 0)
    "aggregate empty length"
  require (ProofForge.Protocols.Evm.Permit2.catalogId == "protocols.evm.permit2")
    "permit2 catalog"
  require (ProofForge.Protocols.Evm.Permit2.selectorTransferFrom == 0x36c78516)
    "permit2 transferFrom selector"
  require (ProofForge.Protocols.Evm.IERC4626.catalogId == "protocols.evm.ierc4626")
    "ierc4626 catalog"
  require (ProofForge.Protocols.Evm.IERC4626.selectorDeposit == 0x6e553f65)
    "4626 deposit selector"
  require (ProofForge.Protocols.Evm.IERC4626.selectorConvertToShares == 0xc6e6f592)
    "4626 convertToShares"
  require (ProofForge.Protocols.Evm.IERC20Permit.catalogId == "protocols.evm.ierc20_permit")
    "ierc20 permit catalog"
  require (ProofForge.Protocols.Evm.IERC20Permit.selectorPermit == 0xd505accf)
    "eip-2612 permit selector"
  require (ProofForge.Target.ProtocolMaterialize.evmSelector? "deposit" == some 0x6e553f65)
    "ProtocolMaterialize deposit"
  require (ProofForge.Target.ProtocolMaterialize.evmSelector? "permit" == some 0xd505accf)
    "ProtocolMaterialize permit"
  require (ProofForge.Protocols.Near.FungibleToken.methodFtTransfer == "ft_transfer")
    "ft_transfer method name"
  require (ProofForge.Protocols.Near.FungibleToken.methodStorageDeposit == "storage_deposit")
    "storage_deposit method name"
  require (ProofForge.Protocols.Near.FungibleToken.argPackingBoundId == "nep141_json_object")
    "NEAR FT packing bound id"
  match ProofForge.Protocols.Near.FungibleToken.requireArgPackingHonest 2 with
  | .error e => throw (IO.userError s!"scalar args=2 should be honest: {e}")
  | .ok () => pure ()
  match ProofForge.Protocols.Near.FungibleToken.requireArgPackingHonest 99 with
  | .ok () => throw (IO.userError "99 args must fail NEAR packing honesty")
  | .error msg =>
      require (contains msg "honesty") "NEAR packing reject names honesty"
      require (contains msg "scalar" || contains msg "nep141")
        "NEAR packing reject names bound"
  -- Confidential layouts must stay unsupported on the shipped CPI lowerer.
  for layout in ProofForge.Protocols.Solana.rejectedLayoutExamples do
    require (ProofForge.Protocols.Solana.isConfidentialOrZkLayout layout)
      s!"rejected list item should classify confidential/zk: {layout}"
    require (!ProofForge.Backend.Solana.Extension.isSupportedCpiDataLayout layout)
      s!"confidential layout must not be supported by lowerer: {layout}"
  let _ := ProofForge.Protocols.Solana.splTokenInitializeAccount3Call
    "init" "acct" "mint" "owner"
  let _ := ProofForge.Protocols.Solana.splToken2022PauseCall "pause" "mint" "authority"

  -- EVM IERC20 example
  let ierc20 := Examples.Backend.Evm.Contracts.Ierc20Client.module
  require (ierc20.entrypoints.any (·.name == "pushTokens")) "Ierc20Client has pushTokens"
  require (ierc20.crosscallStrings.any (· == "token.peer")) "Ierc20Client registers token.peer"
  let ierc4626 := Examples.Backend.Evm.Contracts.Ierc4626Client.module
  require (ierc4626.crosscallStrings.any (· == "vault.peer")) "Ierc4626 vault.peer"
  let iercPermit := Examples.Backend.Evm.Contracts.Ierc20PermitClient.module
  require (iercPermit.crosscallStrings.any (· == "permit.token")) "permit.token peer"
  match ProofForge.Backend.Evm.IR.renderModule ierc20 with
  | .error e => throw (IO.userError s!"EVM Ierc20Client render failed: {e.message}")
  | .ok yul =>
      let transferSel := toString ProofForge.Protocols.Evm.IERC20.selectorTransfer
      require (
          contains yul transferSel || contains yul "2835717307" ||
          contains yul "a9059cbb" || contains yul "0xa9059cbb"
        ) "Yul missing IERC20.transfer selector"
      require (
          contains yul (toString ProofForge.Protocols.Evm.IERC20.selectorBalanceOf) ||
          contains yul "70a08231"
        ) "Yul missing IERC20.balanceOf selector"
      require (
          contains yul (toString ProofForge.Protocols.Evm.IERC20.selectorTotalSupply) ||
          contains yul "18160ddd"
        ) "Yul missing IERC20.totalSupply selector"
      require (contains yul "crosscall" || contains yul "__proof_forge_crosscall")
        "Yul missing crosscall helper for IERC20 client"

  -- EVM IERC721 example
  let ierc721 := Examples.Backend.Evm.Contracts.Ierc721Client.module
  require (ierc721.entrypoints.any (·.name == "moveToken")) "Ierc721Client has moveToken"
  require (ierc721.crosscallStrings.any (· == "nft.peer")) "Ierc721Client registers nft.peer"
  match ProofForge.Backend.Evm.IR.renderModule ierc721 with
  | .error e => throw (IO.userError s!"EVM Ierc721Client render failed: {e.message}")
  | .ok yul =>
      require (
          contains yul (toString ProofForge.Protocols.Evm.IERC721.selectorTransferFrom) ||
          contains yul "23b872dd"
        ) "Yul missing IERC721.transferFrom selector"
      require (
          contains yul (toString ProofForge.Protocols.Evm.IERC721.selectorSafeTransferFrom) ||
          contains yul "42842e0e"
        ) "Yul missing IERC721.safeTransferFrom selector"
      require (
          contains yul (toString ProofForge.Protocols.Evm.IERC721.selectorOwnerOf) ||
          contains yul "6352211e"
        ) "Yul missing IERC721.ownerOf selector"
      require (contains yul "crosscall" || contains yul "__proof_forge_crosscall")
        "Yul missing crosscall helper for IERC721 client"

  -- NEAR FT peer example
  let nearFt := Examples.Backend.WasmNear.FtPeerClient.module
  require (nearFt.entrypoints.any (·.name == "pay")) "FtPeerClient has pay"
  require (nearFt.entrypoints.any (·.name == "pay_with_callback")) "FtPeerClient has pay_with_callback"
  require (nearFt.crosscallStrings.any (· == "my_ft")) "FtPeerClient registers my_ft peer"
  require (nearFt.crosscallStrings.any (· == "ft_transfer")) "FtPeerClient registers ft_transfer"
  require (nearFt.crosscallStrings.any (· == "ft_transfer_call"))
    "FtPeerClient registers ft_transfer_call"
  require (nearFt.crosscallStrings.any (· == "ft_balance_of"))
    "FtPeerClient registers ft_balance_of"
  require (nearFt.crosscallStrings.any (· == "ft_total_supply"))
    "FtPeerClient registers ft_total_supply"
  match ProofForge.Backend.WasmHost.EmitWat.renderModule nearFt with
  | .error e => throw (IO.userError s!"NEAR FtPeerClient render failed: {e.message}")
  | .ok wat =>
      require (contains wat "promise_create") "FtPeerClient WAT missing promise_create"
      require (contains wat "ft_transfer" || contains wat "my_ft")
        "FtPeerClient WAT should embed FT peer/method pool data"
      -- NEP-141 JSON object packing: '{' and key fragments as putc immediates.
      require (contains wat "i32.const 123" || contains wat "i32.const 0x7b")
        "FtPeerClient should emit JSON object open brace for NEP-141"
      require (contains wat "alice.near" || contains wat "alice")
        "FtPeerClient pool should include alice.near receiver"
      require (contains wat "__pf_crosscall_args_putu64" || contains wat "crosscall_args_putu64")
        "FtPeerClient should pack amount via putu64"

  -- Multicall3 client → Yul with aggregate selector.
  let mc := Examples.Backend.Evm.Contracts.MulticallClient.module
  require (mc.crosscallStrings.any (· == "multicall.peer")) "MulticallClient peer"
  match ProofForge.Backend.Evm.IR.renderModule mc with
  | .error e => throw (IO.userError s!"MulticallClient render failed: {e.message}")
  | .ok yul =>
      let sel := toString ProofForge.Protocols.Evm.Multicall.selectorAggregate
      require (
          contains yul sel || contains yul "252dba42" || contains yul "0x252dba42"
        ) "Yul missing Multicall.aggregate selector"
      require (contains yul "crosscall" || contains yul "__proof_forge_crosscall")
        "Yul missing crosscall for Multicall"

  -- Permit2 client → Yul with transferFrom selector.
  let p2 := Examples.Backend.Evm.Contracts.Permit2Client.module
  require (p2.crosscallStrings.any (· == "permit2.peer")) "Permit2Client peer"
  match ProofForge.Backend.Evm.IR.renderModule p2 with
  | .error e => throw (IO.userError s!"Permit2Client render failed: {e.message}")
  | .ok yul =>
      let sel := toString ProofForge.Protocols.Evm.Permit2.selectorTransferFrom
      require (
          contains yul sel || contains yul "36c78516" || contains yul "0x36c78516"
        ) "Yul missing Permit2.transferFrom selector"
      require (contains yul "crosscall" || contains yul "__proof_forge_crosscall")
        "Yul missing crosscall for Permit2"

  IO.println "protocols-layer: ok (solana · evm ierc20/721/multicall/permit2 · near ft honesty)"
  pure 0

end ProofForge.Tests.ProtocolsLayer

def main : IO UInt32 :=
  ProofForge.Tests.ProtocolsLayer.main
