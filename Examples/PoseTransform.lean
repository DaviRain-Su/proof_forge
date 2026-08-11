import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- Low-integration NEAR product demo (parity Phase 1): 2D pose with
-- translate / rotate90 CW / uniform scale. Int64 state so rotate is honest
-- around the origin without a fake unsigned encoding.
--
-- No assets, no Promise, no invariants, no cross-contract.
-- Sandbox gate: scripts/near_runtime_test.sh suite `posetransform`.
-- Engineering only — not formal Reference↔sandbox, not testnet/mainnet.
-- Not imported by Examples.lean (target-runtime fixture, like BlockHeightCheck).
program PoseTransform where
  struct Pose where
    x : Int64
    y : Int64

  state p : Pose

  init(x0 : Int64, y0 : Int64) do
    p := Pose.new(x0, y0)

  entry translate(dx : Int64, dy : Int64) : Pose do
    -- Construct+store so both leaves share one pre-store snapshot (storeAtomic).
    p := Pose.new(p.x + dx, p.y + dy)
    return p

  -- 90° clockwise about the origin: (x, y) → (y, -x).
  entry rotate90() : Pose do
    p := Pose.new(p.y, 0 - p.x)
    return p

  entry scale(k : Int64) : Pose do
    p := Pose.new(p.x * k, p.y * k)
    return p

  entry setPose(x : Int64, y : Int64) : Pose do
    p := Pose.new(x, y)
    return p

  view getPose() : Pose do
    return p

end Examples
