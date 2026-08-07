/-
  Tests.Targets.SolanaProductCpiRecipesV1 — ADR-0032 P3-e foundation pins.
-/
import ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
import ProofForgeV2.Targets.Solana.ProductFrameV1

namespace Tests.Targets.SolanaProductCpiRecipesV1

open ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
open ProofForgeV2.Targets.Solana.ProductFrameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  expect (systemProgramIdHexV1.length == 64) "system program id hex is 64 chars"
  expect (systemProgramIdHexV1.all (· == '0')) "system program id is 32 zero bytes"
  expect (systemTransferDataLenV1 == 12) "transfer data is 12 bytes"
  expect (systemTransferMetaCountV1 == 2) "transfer has 2 metas"
  expect (systemTransferInstructionTagV1 == 2) "Transfer discriminant is 2"
  expect (isSystemTransferQnV1 systemTransferQnV1) "qn recognition"
  expect (isSystemTransferCalleeV1 #["solana", "system", "transfer"])
    "callee array recognition"
  expect (!isSystemTransferCalleeV1 #["pf", "assets", "native", "transfer"])
    "pf.assets is not system.transfer"
  expect (isPfAssetsTokenTransferQnV1 pfAssetsTokenTransferQnV1) "token qn recognition"
  expect (isPfAssetsTokenTransferCalleeV1 #["pf", "assets", "token", "transfer"])
    "token callee array recognition"
  expect (!isPfAssetsTokenTransferCalleeV1 #["solana", "system", "transfer"])
    "system.transfer is not token.transfer"
  expect (tokenTransferCheckedDataLenV1 == 10) "transferChecked data is 10 bytes"
  expect (tokenTransferCheckedMetaCountV1 == 4) "transferChecked has 4 metas"
  expect (tokenTransferCheckedTagV1 == 0x0c) "TransferChecked discriminant is 0x0c"
  let scratch4 := systemTransferScratchBytesV1 4
  expect (scratch4 == 16 + 2 * 16 + 40 + 4 * 56)
    s!"scratch for 4 roles, got {scratch4}"
  match validateSystemTransferFrameBudgetV1 128 4 with
  | .error e => throw <| IO.userError s!"frame budget must accept 128+4roles: {e}"
  | .ok () => pure ()
  match validateSystemTransferFrameBudgetV1 productMaxFrameBytesV1 16 with
  | .ok () => throw <| IO.userError "oversize frame must fail"
  | .error _ => pure ()
  IO.println "Tests.Targets.SolanaProductCpiRecipesV1: ok"

end Tests.Targets.SolanaProductCpiRecipesV1
