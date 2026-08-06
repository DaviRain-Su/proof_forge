import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0032 U1 / P3-f product demo: Map Principal + pf.assets transfer on
-- sole rail `solana-sbpf-cpi-elf-v1` (hasSites ∧ needsFullBody).
--
-- Engineering path: ProductSynthesize full-body LowerSemantic + empty-meta
-- `sol_invoke_signed_c` for ExternalCall (P3-d partial). Multi-role
-- AccountMeta / vault PDA maturity remains deferred (not TipJar-class CPI).
--
-- Scratch discipline: pure binder values must not cross Map StateStore
-- effect sinks as IndexSet RHS expressions — store through `scratch` first
-- (same pattern as MiniAmm). Multi-block if warms the CFG before match.
--
-- Not imported by Examples.lean (target-specific product pin).
-- Non-formal, non-mainnet, not Mollusk.
program BodyCpiMapTip where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state tips : Map Principal UInt64
  state scratch : UInt64

  init() do
    tips := Map.empty()
    scratch := 0

  entry tip(dst : Principal, amount : UInt64) : UInt64 do
    assert amount > 0
    call pf.assets.native.transfer(dst, amount)
    if amount > 0 then
      scratch := amount
    else
      scratch := 0
    match tips[dst] with
    | Option.some(v) => do
      scratch := v + scratch
      tips[dst] := scratch
      return scratch
    | _ => do
      tips[dst] := scratch
      return scratch

  view get(dst : Principal) : UInt64 do
    match tips[dst] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0

end Examples
