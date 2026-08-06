/-
  ProofForgeV2.Targets.Solana.ProductFrameV1 — ADR-0032 U1 / P3-b.

  Unified pure `r10` frame budget for the sole product rail
  (`solana-sbpf-cpi-elf-v1`):

    [ role table | fixed slots | body temps | CPI scratch ]
         ≤ productMaxFrameBytesV1 (4096)

  Numeric constants for the multi-role/CPI region match the existing
  escrow product layout (CpiEscrowIRV1) without importing that module
  (avoids IR↔emit cycles). Body-only zero-site hybrid uses a degenerate
  layout with role/slot/cpi = 0 and body temps from the stack top.

  Pure / fail-closed. Engineering only — not formal ToolchainIdentity.
-/
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Solana.ProductFrameV1

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Hard stack ceiling (bytes), same as EmitSbpfAsm / escrow product. -/
def productMaxFrameBytesV1 : Nat := 4096

/-- Multi-role outer account table (16 × 64). Escrow-compatible. -/
def productRoleTableBytesV1 : Nat := 1024

/-- Role stride (bytes). Escrow-compatible. -/
def productRoleStrideV1 : Nat := 64

/-- Max outer roles that fit the table. -/
def productMaxOuterRolesV1 : Nat := 16

/-- Absolute r10-relative base of the first body temp in unified mode.
    Escrow `escrowTempBaseV1 = 1096` = role table + fixed slots. -/
def productEscrowTempBaseV1 : Nat := 1096

/-- Fixed slots region size between role table end and temp base. -/
def productFixedSlotBytesV1 : Nat :=
  productEscrowTempBaseV1 - productRoleTableBytesV1

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
      unless L.roleTableBytes == productRoleTableBytesV1 do
        throw s!"ProductFrame: unifiedCpi role table must be {productRoleTableBytesV1}"
      unless L.fixedSlotBytes == productFixedSlotBytesV1 do
        throw s!"ProductFrame: unifiedCpi fixed slots must be {productFixedSlotBytesV1}"
      unless L.bodyTempStart == productEscrowTempBaseV1 do
        throw s!"ProductFrame: unifiedCpi body start must be {productEscrowTempBaseV1}"
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

/-- Unified frame with escrow-compatible role/slot prefix.
    `bodyTempBytes` and `cpiScratchBytes` must be 8-aligned. -/
def mintUnifiedCpiFrameV1 (bodyTempBytes cpiScratchBytes : Nat) :
    Except String ProductFrameLayoutV1 := do
  let L : ProductFrameLayoutV1 := {
    mode := .unifiedCpi
    roleTableBytes := productRoleTableBytesV1
    fixedSlotBytes := productFixedSlotBytesV1
    bodyTempBytes
    cpiScratchBytes
  }
  validateProductFrameV1 L
  pure L

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
  ("maxFrame", productMaxFrameBytesV1)
]

end ProofForgeV2.Targets.Solana.ProductFrameV1
