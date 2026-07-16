/-
Solana BinaryLayout pack hygiene (Wave δ.2).
-/
import ProofForge.Backend.Solana.BinaryLayout

namespace ProofForge.Tests.BinaryLayout

open ProofForge.Backend.Solana.BinaryLayout

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def main : IO UInt32 := do
  require (catalogId == "solana.binary_layout") "catalog"
  require (packSizeMatches (splTransferChecked 1000 6)) "size matches"

  let tc := pack (splTransferChecked 0x0102 9)
  require (tc.size == 1 + 8 + 1) s!"transfer_checked len {tc.size}"
  require (tc[0]! == 12) "tag 12"
  require (tc[1]! == 0x02 && tc[2]! == 0x01) "amount LE low bytes"
  require (tc[9]! == 9) "decimals"

  let tr := pack (splTransfer 256)
  require (tr[0]! == 3) "transfer tag 3"
  require (tr[1]! == 0 && tr[2]! == 1) "amount 256 LE"

  let st := pack (systemTransfer 42)
  require (st.size == 4 + 8) "system transfer size"
  require (st[0]! == 2) "system tag LE u32"

  require (splTransferCheckedDataLen == 10) "transfer_checked data len"
  require (splTransferDataLen == 9) "amount-only data len"
  require (splRevokeDataLen == 1) "revoke data len"
  require (pack splRevoke == #[5]) "revoke tag byte"
  require (pack splCloseAccount == #[9]) "close_account tag byte"

  require (token2022PausableTagDataLen == 2) "pausable tag len"
  require (pack token2022Pause == #[44, 1]) "pause bytes"
  require (pack token2022Resume == #[44, 2]) "resume bytes"
  require (pack token2022InitializeNonTransferableMint == #[32]) "non-transferable tag"
  require (pack token2022InitializeImmutableOwner == #[22]) "immutable owner tag"
  require (pack (token2022TransferFeeTag 2) == #[26, 2]) "transfer fee tag"

  IO.println "binary-layout: ok"
  pure 0

end ProofForge.Tests.BinaryLayout

def main : IO UInt32 :=
  ProofForge.Tests.BinaryLayout.main
