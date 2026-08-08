import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- UInt64 bounded-for static-unroll probe for Psy local-VM execute.
-- run(n) adds 1 for each of four steps n ..< n+4 (bounded 8).
-- Use only -- line comments; module-doc openers before program break the parser.
program LoopSum where
  state total : UInt64

  init(initial : UInt64) do
    total := initial

  entry run(n : UInt64) : UInt64 do
    let limit : UInt64 := n + 4
    for i in n ..< limit bounded 8 do
      total := total + 1
    return total

  view get() : UInt64 do
    return total

end Examples
