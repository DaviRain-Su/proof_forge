import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- NEAR scalar const-table product pin (parity Phase 4 slice).
-- `const ANSWER` lowers via Op.Constant → plan literal on NEAR.
-- Sandbox: scripts/near_runtime_test.sh suite `constanswer`.
-- Engineering only — not formal. Not imported by Examples.lean.
program ConstAnswer where
  const ANSWER : UInt64 := 42

  state stored : UInt64

  init() do
    stored := 0

  entry answer() : UInt64 do
    stored := stored + ANSWER
    return stored

  view get() : UInt64 do
    return stored

end Examples
