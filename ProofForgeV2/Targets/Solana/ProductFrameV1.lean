/-
  ProofForgeV2.Targets.Solana.ProductFrameV1 — ADR-0032 U1 / P3-b / M4c.

  Unified pure `r10` frame budget for the sole product rail
  (`solana-sbpf-cpi-elf-v1`):

    [ role table | fixed slots | body temps | CPI scratch ]
         ≤ productMaxFrameBytesV1 (4096)

  Role table is sized to the program's outer `roleCount` (stride 64, max 32).
  Fixed slots (72B) sit immediately after the role table; body temps follow.
  Historical 16-role escrow pins (`productRoleTableBytesV1` / `productEscrowTempBaseV1`)
  remain for escrow-compatible docs and the straight-line escrow composite path.

  Pure / fail-closed. Engineering only — not formal ToolchainIdentity.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Solana.ProductFrameV1

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Hard stack ceiling (bytes), same as EmitSbpfAsm / escrow product. -/
def productMaxFrameBytesV1 : Nat := 4096

/-- Role stride (bytes). Escrow-compatible. -/
def productRoleStrideV1 : Nat := 64

/-- Max outer roles that fit a dynamic table under the 4 KiB frame with
    multi-role body temp (1024) + CPI scratch (1600) + fixed (72).
    N=21 → 1344+72+1024+1600 = 4040 ≤ 4096; N=32 is the hard outer cap. -/
def productMaxOuterRolesV1 : Nat := 32

/-- Historical 16-role role-table size (escrow / docs pin). Dynamic paths use
    `productRoleTableBytesForV1`. -/
def productRoleTableBytesV1 : Nat := 16 * productRoleStrideV1

/-- Max role-table bytes (32 × 64). -/
def productRoleTableBytesMaxV1 : Nat :=
  productMaxOuterRolesV1 * productRoleStrideV1

/-- Fixed slots region size between role table end and body temp base. -/
def productFixedSlotBytesV1 : Nat := 72

/-- Role table bytes for an exact outer role count. -/
def productRoleTableBytesForV1 (roleCount : Nat) : Nat :=
  roleCount * productRoleStrideV1

/-- Absolute r10-relative base of the first body temp for multi-role unified
    frames: role table + fixed slots. -/
def productMultiRoleTempBaseForV1 (roleCount : Nat) : Nat :=
  productRoleTableBytesForV1 roleCount + productFixedSlotBytesV1

/-- Absolute r10-relative base of the first body temp in the historical 16-role
    escrow layout (`1024 + 72 = 1096`). -/
def productEscrowTempBaseV1 : Nat :=
  productRoleTableBytesV1 + productFixedSlotBytesV1

/-- Historical escrow max body temps (16 × 8). Full-body may use more; budget
    still caps total frame at 4096. -/
def productEscrowMaxTempsV1 : Nat := 16

/-- Escrow temp region end (absolute). -/
def productEscrowTempRegionEndV1 : Nat :=
  productEscrowTempBaseV1 + productEscrowMaxTempsV1 * 8

/-- Minimum CPI scratch base used by composite product emitters. -/
def productCpiBaseMinV1 : Nat := 1600

/-- Frame mode for P3 synthesis. -/
inductive ProductFrameModeV1 where
  /-- Zero CPI sites: body temps only (today full-body hybrid). -/
  | bodyOnly
  /-- Multi-role + body temps + CPI scratch (escrow-compatible region order). -/
  | unifiedCpi
  deriving BEq, Repr, Inhabited

/-- Absolute region layout (byte offsets from frame base / toward lower r10).
    Offsets are the **start** of each region measured as "bytes reserved
    below r10" for the high end of that region (stack grows down):

    totalFrame = roleTable + fixedSlots + bodyTemps + cpiScratch
    region [0, roleTable) = role table
    … contiguous, no gaps, no overlap by construction.
-/
structure ProductFrameLayoutV1 where
  mode : ProductFrameModeV1
  roleTableBytes : Nat
  fixedSlotBytes : Nat
  bodyTempBytes : Nat
  cpiScratchBytes : Nat
  deriving BEq, Repr, Inhabited

/-- Total frame bytes. -/
def ProductFrameLayoutV1.totalBytes (L : ProductFrameLayoutV1) : Nat :=
  L.roleTableBytes + L.fixedSlotBytes + L.bodyTempBytes + L.cpiScratchBytes

/-- Absolute start offset of role table (always 0). -/
def ProductFrameLayoutV1.roleTableStart (_ : ProductFrameLayoutV1) : Nat := 0

/-- Absolute start of fixed slots. -/
def ProductFrameLayoutV1.fixedSlotStart (L : ProductFrameLayoutV1) : Nat :=
  L.roleTableBytes

/-- Absolute start of body temp region. -/
def ProductFrameLayoutV1.bodyTempStart (L : ProductFrameLayoutV1) : Nat :=
  L.roleTableBytes + L.fixedSlotBytes

/-- Absolute start of CPI scratch. -/
def ProductFrameLayoutV1.cpiScratchStart (L : ProductFrameLayoutV1) : Nat :=
  L.roleTableBytes + L.fixedSlotBytes + L.bodyTempBytes

private def isEightAligned (n : Nat) : Bool := n % 8 == 0

/-- Fail-closed pure validation: alignment, non-overlap (by sum), ceiling. -/
def validateProductFrameV1 (L : ProductFrameLayoutV1) : Except String Unit := do
  unless isEightAligned L.roleTableBytes do
    throw s!"ProductFrame: roleTableBytes {L.roleTableBytes} not 8-aligned"
  unless isEightAligned L.fixedSlotBytes do
    throw s!"ProductFrame: fixedSlotBytes {L.fixedSlotBytes} not 8-aligned"
  unless isEightAligned L.bodyTempBytes do
    throw s!"ProductFrame: bodyTempBytes {L.bodyTempBytes} not 8-aligned"
  unless isEightAligned L.cpiScratchBytes do
    throw s!"ProductFrame: cpiScratchBytes {L.cpiScratchBytes} not 8-aligned"
  let total := L.totalBytes
  unless isEightAligned total do
    throw s!"ProductFrame: total {total} not 8-aligned"
  unless total ≤ productMaxFrameBytesV1 do
    throw s!"ProductFrame: total {total} exceeds max {productMaxFrameBytesV1}"
  match L.mode with
  | .bodyOnly =>
      unless L.roleTableBytes == 0 && L.fixedSlotBytes == 0 &&
          L.cpiScratchBytes == 0 do
        throw "ProductFrame: bodyOnly requires zero role/slot/cpi regions"
  | .unifiedCpi =>
      unless L.roleTableBytes % productRoleStrideV1 == 0 do
        throw s!"ProductFrame: unifiedCpi role table {L.roleTableBytes} not stride-aligned"
      let roleCount := L.roleTableBytes / productRoleStrideV1
      unless roleCount ≥ 1 && roleCount ≤ productMaxOuterRolesV1 do
        throw s!"ProductFrame: unifiedCpi roleCount {roleCount} out of 1..{productMaxOuterRolesV1}"
      unless L.fixedSlotBytes == productFixedSlotBytesV1 do
        throw s!"ProductFrame: unifiedCpi fixed slots must be {productFixedSlotBytesV1}"
      unless L.bodyTempStart == productMultiRoleTempBaseForV1 roleCount do
        throw s!"ProductFrame: unifiedCpi body start must be {productMultiRoleTempBaseForV1 roleCount}"
  pure ()

/-- Body-only frame: `bodyTempBytes` must already be 8-aligned (temp count × 8). -/
def mintBodyOnlyFrameV1 (bodyTempBytes : Nat) : Except String ProductFrameLayoutV1 := do
  let L : ProductFrameLayoutV1 := {
    mode := .bodyOnly
    roleTableBytes := 0
    fixedSlotBytes := 0
    bodyTempBytes
    cpiScratchBytes := 0
  }
  validateProductFrameV1 L
  pure L

/-- Unified multi-role frame sized to `roleCount` outer accounts.
    `bodyTempBytes` and `cpiScratchBytes` must be 8-aligned. -/
def mintUnifiedCpiFrameV1 (roleCount bodyTempBytes cpiScratchBytes : Nat) :
    Except String ProductFrameLayoutV1 := do
  unless roleCount ≥ 1 && roleCount ≤ productMaxOuterRolesV1 do
    throw s!"ProductFrame: roleCount {roleCount} out of 1..{productMaxOuterRolesV1}"
  let L : ProductFrameLayoutV1 := {
    mode := .unifiedCpi
    roleTableBytes := productRoleTableBytesForV1 roleCount
    fixedSlotBytes := productFixedSlotBytesV1
    bodyTempBytes
    cpiScratchBytes
  }
  validateProductFrameV1 L
  pure L

/-- Historical 16-role escrow-compatible unified mint (straight-line escrow path). -/
def mintEscrowCompatibleUnifiedCpiFrameV1 (bodyTempBytes cpiScratchBytes : Nat) :
    Except String ProductFrameLayoutV1 :=
  mintUnifiedCpiFrameV1 16 bodyTempBytes cpiScratchBytes

/-- CompileResult-friendly gate. -/
def requireProductFrameV1 (L : ProductFrameLayoutV1) : CompileResult Unit :=
  match validateProductFrameV1 L with
  | .ok () => pure ()
  | .error e =>
      throw <| .planInvariant .solana e

/-- Escrow-compatible numeric pins (unit-test / docs). -/
def escrowCompatibilityPinsV1 : Array (String × Nat) := #[
  ("roleTableBytes", productRoleTableBytesV1),
  ("roleStride", productRoleStrideV1),
  ("tempBase", productEscrowTempBaseV1),
  ("tempRegionEnd", productEscrowTempRegionEndV1),
  ("cpiBaseMin", productCpiBaseMinV1),
  ("maxFrame", productMaxFrameBytesV1),
  ("maxOuterRoles", productMaxOuterRolesV1)
]

end ProofForgeV2.Targets.Solana.ProductFrameV1
