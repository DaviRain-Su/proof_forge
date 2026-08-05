import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0030 E2 product vertical: declares `pf.assets@1.1.0` and uses the
-- `native.balanceOfSelf()` env-read catalog QN in a view. This is the first
-- non-Unit catalog member (expression-position only, result UInt64,
-- effect-free, view-callable). Product `check` passes (proof gate + compile +
-- requirements); `build` for any target fails closed at Plan until E2-3 opens
-- the materializers. Not imported by Examples.lean (target-specific vertical).
program EnvReadBalance where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state count : UInt64

  init(initial : UInt64) do
    count := initial

  view nativeBalance() : UInt64 do
    return pf.assets.native.balanceOfSelf()

  entry setCount(newCount : UInt64) : UInt64 do
    count := newCount
    return count

end Examples