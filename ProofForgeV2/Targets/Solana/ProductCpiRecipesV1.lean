/-
  ProofForgeV2.Targets.Solana.ProductCpiRecipesV1 — ADR-0032 U1 / P3-e foundation.

  Pure, cycle-free recipe constants and recognition helpers for product-rail
  CPI sites that full-body synthesize may eventually multi-role emit.

  Today (P3-e foundation):
  * `solana.system.transfer` layout (SystemInstruction::Transfer = 2, 12B data,
    2 AccountMetas, native System program id = 32 zero bytes)
  * frame scratch needs for multi-role emit (escrow-compatible formula)
  * QN recognition for maturity tagging

  Does **not** import EmitCpiEscrow / EmitSbpfAsm (avoids cycles). Engineering
  only — multi-role AccountMeta walker still deferred to full P3-e integration.
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
    (escrow formula: 16 data-aligned + 32 metas + 40 instr + 56*N infos).
    Data region uses 16B (12B payload + 4B pad) in the composite emitter. -/
def systemTransferScratchBytesV1 (outerRoleCount : Nat) : Nat :=
  16 + systemTransferMetaCountV1 * productAccountMetaSizeV1 +
    productSolInstructionSizeV1 + outerRoleCount * productAccountInfoSizeV1

/-- Minimum unified frame total for body temps + system.transfer scratch
    under the escrow-compatible region order (role table + fixed slots). -/
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

end ProofForgeV2.Targets.Solana.ProductCpiRecipesV1
