/-
  Tests.Targets.SolanaProductFrameV1 — ADR-0032 U1 P3-b pure frame pins.
-/
import ProofForgeV2.Targets.Solana.ProductFrameV1

namespace Tests.Targets.SolanaProductFrameV1

open ProofForgeV2.Targets.Solana.ProductFrameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def expectOk (e : Except String α) (message : String) : IO α :=
  match e with
  | .ok v => pure v
  | .error err => throw <| IO.userError s!"{message}: {err}"

private def testEscrowPins : IO Unit := do
  expect (productRoleTableBytesV1 == 1024) "role table 1024"
  expect (productEscrowTempBaseV1 == 1096) "temp base 1096"
  expect (productFixedSlotBytesV1 == 72) "fixed slots 72"
  expect (productMaxFrameBytesV1 == 4096) "max frame 4096"
  expect (productEscrowTempRegionEndV1 == 1096 + 16 * 8) "temp region end"
  expect (productCpiBaseMinV1 == 1600) "cpi base min 1600"

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
  -- body 128 + cpi 256 → total 1024+72+128+256 = 1480
  let L ← expectOk (mintUnifiedCpiFrameV1 128 256) "unified 128/256"
  expect (L.mode == .unifiedCpi) "mode unified"
  expect (L.roleTableBytes == 1024) "role"
  expect (L.fixedSlotBytes == 72) "slots"
  expect (L.bodyTempStart == 1096) "body at escrow temp base"
  expect (L.totalBytes == 1024 + 72 + 128 + 256) "total"
  -- overflow: body huge
  match mintUnifiedCpiFrameV1 4000 256 with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "unified oversize must FC"
  -- wrong role if we hand-build
  let bad : ProductFrameLayoutV1 := {
    mode := .unifiedCpi
    roleTableBytes := 512
    fixedSlotBytes := 72
    bodyTempBytes := 64
    cpiScratchBytes := 64
  }
  match validateProductFrameV1 bad with
  | .error _ => pure ()
  | .ok () => throw <| IO.userError "wrong role table size must FC"

private def testNoOverlapByConstruction : IO Unit := do
  let L ← expectOk (mintUnifiedCpiFrameV1 64 128) "unified small"
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
