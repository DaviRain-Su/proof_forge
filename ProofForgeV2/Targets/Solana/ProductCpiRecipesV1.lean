/-
  ProofForgeV2.Targets.Solana.ProductCpiRecipesV1 — ADR-0032 U1 / P3-e.

  Pure, cycle-free recipe constants and recognition helpers for product-rail
  CPI sites on the full-body synthesize path.

  * `solana.system.transfer` layout (SystemInstruction::Transfer = 2, 12B data,
    2 AccountMetas, native System program id = 32 zero bytes)
  * frame scratch needs (escrow-compatible formula)
  * multi-role site binding carrier for synthesize → multi-role emit
  * QN recognition for maturity tagging

  Does **not** import EmitCpiEscrow / EmitSbpfAsm (avoids cycles).
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Solana.ProductFrameV1

namespace ProofForgeV2.Targets.Solana.ProductCpiRecipesV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.Solana.ProductFrameV1

/-- Native System program id (32 zero bytes) as 64 lowercase hex chars. -/
def systemProgramIdHexV1 : String :=
  String.ofList (List.replicate 64 '0')

/-- SystemInstruction::Transfer discriminant (u32 LE). -/
def systemTransferInstructionTagV1 : Nat := 2

/-- Instruction data length: 4B tag + 8B lamports. -/
def systemTransferDataLenV1 : Nat := 12

/-- AccountMeta count for transfer (payer, recipient). -/
def systemTransferMetaCountV1 : Nat := 2

/-- AccountMeta size (bytes), escrow-compatible. -/
def productAccountMetaSizeV1 : Nat := 16

/-- SolAccountInfo size (bytes), escrow-compatible. -/
def productAccountInfoSizeV1 : Nat := 56

/-- SolInstruction size (bytes), escrow-compatible. -/
def productSolInstructionSizeV1 : Nat := 40

/-- Exact QN for native System transfer. -/
def systemTransferQnV1 : String := "solana.system.transfer"

/-- True when callee QN components are exactly `solana.system.transfer`. -/
def isSystemTransferCalleeV1 (callee : Array String) : Bool :=
  callee.size == 3 &&
    callee[0]! == "solana" &&
    callee[1]! == "system" &&
    callee[2]! == "transfer"

/-- True when a site QN string is the approved System transfer. -/
def isSystemTransferQnV1 (qn : String) : Bool :=
  qn == systemTransferQnV1

/-- CPI scratch bytes for one system.transfer with `outerRoleCount` infos
    (escrow formula: 16 data-aligned + 32 metas + 40 instr + 56*N infos). -/
def systemTransferScratchBytesV1 (outerRoleCount : Nat) : Nat :=
  16 + systemTransferMetaCountV1 * productAccountMetaSizeV1 +
    productSolInstructionSizeV1 + outerRoleCount * productAccountInfoSizeV1

/-- Minimum unified frame total for body temps + system.transfer scratch. -/
def systemTransferUnifiedFrameMinV1 (bodyTempBytes : Nat)
    (outerRoleCount : Nat) : Nat :=
  productRoleTableBytesV1 + productFixedSlotBytesV1 + bodyTempBytes +
    systemTransferScratchBytesV1 outerRoleCount

/-- Fail-closed: scratch + body must fit under product max frame. -/
def validateSystemTransferFrameBudgetV1 (bodyTempBytes outerRoleCount : Nat) :
    Except String Unit := do
  let total := systemTransferUnifiedFrameMinV1 bodyTempBytes outerRoleCount
  unless total ≤ productMaxFrameBytesV1 do
    throw s!"ProductCpiRecipes: system.transfer frame {total} exceeds max {productMaxFrameBytesV1}"
  unless bodyTempBytes % 8 == 0 do
    throw "ProductCpiRecipes: bodyTempBytes must be 8-aligned"
  pure ()

/-- LE u32 SystemInstruction::Transfer tag as UInt64 word (low 32 bits). -/
def systemTransferTagWordLeV1 : UInt64 :=
  UInt64.ofNat systemTransferInstructionTagV1

/-- Comment line for empty-meta / multi-role maturity honesty. -/
def systemTransferMaturityNoteV1 (multiRole : Bool) : String :=
  if multiRole then
    "system.transfer multi-role AccountMeta (P3-e)"
  else
    "system.transfer data layout (empty AccountMeta partial; multi-role deferred)"

/-- P3-e multi-role site binding for full-body system.transfer emit.
    Locals are dense role indices from the product plan (0 = state). -/
structure ProductSystemTransferSiteV1 where
  payerLocal : Nat
  recipientLocal : Nat
  programLocal : Nat
  /-- Outer account infos length passed to sol_invoke_signed_c (typically
      accountRoles.size). -/
  accountInfoCount : Nat
  deriving BEq, Repr, Inhabited

/-- Stack slot layout (bytes below r10), escrow-compatible. -/
def multiRoleSlotNumRolesV1 : Nat := 8
def multiRoleSlotProgramIdV1 : Nat := 16
def multiRoleSlotIxDataV1 : Nat := 24
def multiRoleSlotHandlerIdV1 : Nat := 32
def multiRoleSlotCursorV1 : Nat := 40

/-- Body temp region start (absolute bytes below r10). -/
def multiRoleTempBaseV1 : Nat := productEscrowTempBaseV1

/-- CPI scratch base for multi-role system.transfer (after 32 body temps). -/
def multiRoleCpiBaseV1 : Nat :=
  multiRoleTempBaseV1 + 32 * 8

/-- Loader V3 ABIv1 marker and key offsets (frozen product values). -/
def multiRoleAbiMarkerV1 : Nat := 0xff
def multiRoleAbiKeyOffsetV1 : Nat := 8
def multiRoleAbiOwnerOffsetV1 : Nat := 40
def multiRoleAbiLamportsOffsetV1 : Nat := 72
def multiRoleAbiDataLenOffsetV1 : Nat := 80
def multiRoleAbiFullPrefixV1 : Nat := 88
def multiRoleAbiIsSignerOffsetV1 : Nat := 1
def multiRoleAbiIsWritableOffsetV1 : Nat := 2
def multiRoleAbiMaxPermittedV1 : Nat := 10240
def multiRoleAbiOrigDataLenOffV1 : Nat := 4
/-- Must match `frozenLoaderV3AbiLayoutV1.originalDataLenEntryValue` (0).
    Agave/Mollusk ABIv1 writes the account's original data length here for
    non-dup entries — **not** `0xffffffff`. A `jne r1, 0xffffffff` also mis-
    encodes under SBPF's signed 32-bit immediate (zero-extended ldxw ≠
    sign-extended imm). -/
def multiRoleAbiOrigDataLenEntryV1 : Nat := 0

end ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
