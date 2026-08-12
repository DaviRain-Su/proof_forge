import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- ADR-0031 S3: context.chainId Plan open fixture.
-- Returns `context.chainId` as a view and stamps it via entry:
--   EVM → CHAINID / Yul `chainid()` with UInt64 range guard
--   NEAR / CosmWasm / Solana → Plan fail closed (no exact UInt64 host counterpart)
-- Not imported by Examples.lean (target-runtime fixture, like BlockHeightCheck).
program ChainIdCheck where
  state pad : UInt64

  init(initial : UInt64) do
    pad := initial

  view chainId() : UInt64 do
    return context.chainId

  entry stamp() : UInt64 do
    pad := context.chainId
    return pad

  view get() : UInt64 do
    return pad

end Examples
