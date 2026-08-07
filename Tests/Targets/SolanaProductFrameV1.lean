/-
  Tests.Targets.SolanaProductFrameV1 — ADR-0032 U1 P3-b / M4c pure frame pins.
-/
import ProofForgeV2.Targets.Solana.ProductFrameV1
import ProofForgeV2.Targets.Solana.ProductCpiRecipesV1

namespace Tests.Targets.SolanaProductFrameV1

open ProofForgeV2.Targets.Solana.ProductFrameV1
open ProofForgeV2.Targets.Solana.ProductCpiRecipesV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk (e : Except String α) (message : String) : IO α :=
  match e with
  | .ok v => pure v
  | .error err => throw <| IO.userError s!"{message}: {err}"

private def testEscrowPins : IO Unit := do
  expect (productRoleTableBytesV1 == 1024) "historical 16-role table 1024"
  expect (productEscrowTempBaseV1 == 1096) "escrow temp base 1096"
  expect (productFixedSlotBytesV1 == 72) "fixed slots 72"
  expect (productMaxFrameBytesV1 == 4096) "max frame 4096"
  expect (productEscrowTempRegionEndV1 == 1096 + 16 * 8) "temp region end"
  expect (productCpiBaseMinV1 == 1600) "cpi base min 1600"
  expect (productMaxOuterRolesV1 == 32) "max outer roles 32"
  expect (productRoleTableBytesForV1 4 == 256) "N=4 role table 256"
  expect (productRoleTableBytesForV1 10 == 640) "N=10 role table 640"
  expect (productRoleTableBytesForV1 21 == 1344) "N=21 role table 1344"
  expect (productMultiRoleTempBaseForV1 4 == 328) "N=4 temp base 328"
  expect (productMultiRoleTempBaseForV1 21 == 1416) "N=21 temp base 1416"
  expect (multiRoleCpiBaseForV1 21 == 4040) "N=21 cpi base 4040 ≤ 4096"
  expect (multiRoleCpiBaseForV1 21 ≤ productMaxFrameBytesV1) "N=21 fits frame"
  expect (multiRoleBodyTempBytesV1 == 1024) "body temp budget 1024"

private def testBodyOnlyMint : IO Unit := do
  let L ← expectOk (mintBodyOnlyFrameV1 64) "bodyOnly 64"
  expect (L.mode == .bodyOnly) "mode bodyOnly"
  expect (L.totalBytes == 64) "total 64"
  expect (L.bodyTempStart == 0) "body at 0"
  expect (L.cpiScratchStart == 64) "cpi start after body"
  match mintBodyOnlyFrameV1 65 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "bodyOnly 65 must fail (not 8-aligned)"
  match mintBodyOnlyFrameV1 5000 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "bodyOnly 5000 must exceed max"

private def testUnifiedMint : IO Unit := do
  -- N=16 historical: body 128 + cpi 256 → total 1024+72+128+256 = 1480
  let L ← expectOk (mintUnifiedCpiFrameV1 16 128 256) "unified 16/128/256"
  expect (L.mode == .unifiedCpi) "mode unified"
  expect (L.roleTableBytes == 1024) "role"
  expect (L.fixedSlotBytes == 72) "slots"
  expect (L.bodyTempStart == 1096) "body at escrow temp base"
  expect (L.totalBytes == 1024 + 72 + 128 + 256) "total"
  -- N=4 multi-role body budget
  let L4 ← expectOk
    (mintUnifiedCpiFrameV1 4 multiRoleBodyTempBytesV1 multiRoleCpiScratchBudgetV1)
    "unified N=4 multi-role"
  expect (L4.roleTableBytes == 256) "N=4 role"
  expect (L4.bodyTempStart == 328) "N=4 body"
  expect (L4.totalBytes == multiRoleCpiBaseForV1 4) "N=4 total=cpiBase"
  -- N=21 fits
  let L21 ← expectOk
    (mintUnifiedCpiFrameV1 21 multiRoleBodyTempBytesV1 multiRoleCpiScratchBudgetV1)
    "unified N=21"
  expect (L21.totalBytes == 4040) "N=21 total 4040"
  -- overflow: body huge
  match mintUnifiedCpiFrameV1 16 4000 256 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "unified oversize must FC"
  -- wrong role if we hand-build (non-stride)
  let bad : ProductFrameLayoutV1 := {
    mode := .unifiedCpi
    roleTableBytes := 500
    fixedSlotBytes := 72
    bodyTempBytes := 64
    cpiScratchBytes := 64
  }
  match validateProductFrameV1 bad with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "non-stride role table size must FC"
  -- escrow-compatible helper
  let Le ← expectOk (mintEscrowCompatibleUnifiedCpiFrameV1 128 256)
    "escrow-compatible mint"
  expect (Le.roleTableBytes == 1024) "escrow role 1024"

private def testNoOverlapByConstruction : IO Unit := do
  let L ← expectOk (mintUnifiedCpiFrameV1 10 64 128) "unified N=10 small"
  expect (L.roleTableStart == 0) "role 0"
  expect (L.fixedSlotStart == L.roleTableBytes) "slots abut role"
  expect (L.bodyTempStart == L.fixedSlotStart + L.fixedSlotBytes) "body abuts slots"
  expect (L.cpiScratchStart == L.bodyTempStart + L.bodyTempBytes) "cpi abuts body"
  expect (L.totalBytes == L.cpiScratchStart + L.cpiScratchBytes) "total closes"

unsafe def run : IO Unit := do
  testEscrowPins
  testBodyOnlyMint
  testUnifiedMint
  testNoOverlapByConstruction
  IO.println "Tests.Targets.SolanaProductFrameV1: ok"

end Tests.Targets.SolanaProductFrameV1
