-- External-project Hello (ProgramV1).
-- Product CLI reads this file as source text; the `import ProofForgeV2` line is a
-- required source gate (exact), not a Lake dependency for `proof-forge-next build`.
-- Copy this directory out of the monorepo and point --root at the copy.
import ProofForgeV2

program Hello where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count
