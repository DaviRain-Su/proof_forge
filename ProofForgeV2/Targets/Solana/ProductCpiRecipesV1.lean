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

/-- Minimum unified frame total for body temps + system.transfer scratch.
    Role table is sized to `outerRoleCount` (M4c dynamic outer roles). -/
def systemTransferUnifiedFrameMinV1 (bodyTempBytes : Nat)
    (outerRoleCount : Nat) : Nat :=
  productRoleTableBytesForV1 outerRoleCount + productFixedSlotBytesV1 +
    bodyTempBytes + systemTransferScratchBytesV1 outerRoleCount

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

/-! ### M4b: `pf.assets.token.transfer` full-body multi-role foundation

    Mirrors P3-e system.transfer multi-role stamping for the portable token
    tip path. Full composite (ATA ensure ×2 + transferCheckedPda) is emitted
    on the unified CPI frame; programs whose outer role table or Map body temp
    peak cannot fit the 4 KiB stack stay on empty-meta partial (MiniAmmAssets
    dual-mint Map residual).
-/

/-- Exact QN for portable token transfer. -/
def pfAssetsTokenTransferQnV1 : String := "pf.assets.token.transfer"

/-- True when a site QN string is the approved pf.assets token transfer. -/
def isPfAssetsTokenTransferQnV1 (qn : String) : Bool :=
  qn == pfAssetsTokenTransferQnV1

/-- True when callee QN components are exactly `pf.assets.token.transfer`. -/
def isPfAssetsTokenTransferCalleeV1 (callee : Array String) : Bool :=
  callee.size == 4 &&
    callee[0]! == "pf" &&
    callee[1]! == "assets" &&
    callee[2]! == "token" &&
    callee[3]! == "transfer"

/-- TokenInstruction::TransferChecked discriminant byte. -/
def tokenTransferCheckedTagV1 : Nat := 0x0c

/-- Instruction data length: tag + amount u64le + decimals u8. -/
def tokenTransferCheckedDataLenV1 : Nat := 10

/-- AccountMeta count for transferCheckedPda (source, mint, dest, authority). -/
def tokenTransferCheckedMetaCountV1 : Nat := 4

/-- Frozen decimals for standard SPL fixture mints (catalog per-mint deferred). -/
def pfAssetsTokenTransferDecimalsV1 : Nat := 9

/-- Comment line for token multi-role maturity honesty. -/
def tokenTransferMaturityNoteV1 (multiRole : Bool) : String :=
  if multiRole then
    "pf.assets.token.transfer multi-role AccountMeta + ATA ensure + transferCheckedPda (M4b)"
  else
    "pf.assets.token.transfer empty AccountMeta partial; multi-role deferred (M4b residual)"

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

/-- M4b multi-role site binding for full-body `pf.assets.token.transfer`.
    Locals are dense product-plan role indices (0 = state). -/
structure ProductTokenTransferSiteV1 where
  /-- vault ATA (source, writable). -/
  vaultAtaLocal : Nat
  /-- mint account (readonly). -/
  mintLocal : Nat
  /-- destination ATA (writable). -/
  dstAtaLocal : Nat
  /-- vault PDA (authority, invoke_signed). -/
  vaultPdaLocal : Nat
  /-- classic Token program role. -/
  tokenProgramLocal : Nat
  /-- pf_caller (ATA ensure payer, outer signer). -/
  callerLocal : Nat
  /-- dst wallet Principal param role (dst ATA owner). -/
  dstWalletLocal : Nat
  /-- native System program role (ATA ensure meta). -/
  systemLocal : Nat
  /-- classic ATA program role (outer; ensure program_id may use frozen key). -/
  ataProgramLocal : Nat
  /-- Outer account infos length for sol_invoke_signed_c. -/
  accountInfoCount : Nat
  deriving BEq, Repr, Inhabited

/-- Fixed-slot relative offsets within the 72B band after the role table.
    Absolute r10 offset = `productRoleTableBytesForV1 roleCount + rel`.
    (Historical absolute 8/16/24/32/40 only worked with a padded 16-role table.) -/
def multiRoleSlotNumRolesV1 : Nat := 8
def multiRoleSlotProgramIdV1 : Nat := 16
def multiRoleSlotIxDataV1 : Nat := 24
def multiRoleSlotHandlerIdV1 : Nat := 32
def multiRoleSlotCursorV1 : Nat := 40

/-- Absolute r10 offset of a multi-role fixed slot for `roleCount` outer roles. -/
def multiRoleFixedSlotAbsV1 (roleCount slotRel : Nat) : Nat :=
  productRoleTableBytesForV1 roleCount + slotRel

/-- Body temp region start for historical 16-role layout (bytes below r10). -/
def multiRoleTempBaseV1 : Nat := productEscrowTempBaseV1

/-- Body temp reservation for multi-role handlers (128 × 8 = 1024).
    Raised for Map leaf temps (MiniAmmAssets); N=21 still fits 4 KiB. -/
def multiRoleBodyTempBytesV1 : Nat := 128 * 8

/-- Max CPI scratch bytes for multi-role composite (token ensure×2 + xfer).
    Must fit under `productMaxFrameBytesV1` with role/fixed/body reserved. -/
def multiRoleCpiScratchBudgetV1 : Nat := 1600

/-- CPI scratch base (bytes below r10) for `roleCount` outer roles.
    Writes use `[r10 - base + off]` with `off < multiRoleCpiScratchBudgetV1`,
    so the high edge is `base - budget` — must sit **below** role table +
    fixed slots + body temps. -/
def multiRoleCpiBaseForV1 (roleCount : Nat) : Nat :=
  productMultiRoleTempBaseForV1 roleCount + multiRoleBodyTempBytesV1 +
    multiRoleCpiScratchBudgetV1

/-- Absolute IR temp-index base so relative temp `0` lands at
    `productMultiRoleTempBaseForV1 roleCount` (`tempStackOff t = 8*(t+1)`). -/
def multiRoleBodyTempIndexBaseForV1 (roleCount : Nat) : Nat :=
  productMultiRoleTempBaseForV1 roleCount / 8 - 1

/-- Historical 16-role CPI base (compat / docs). Prefer `multiRoleCpiBaseForV1`. -/
def multiRoleCpiBaseV1 : Nat := multiRoleCpiBaseForV1 16

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
