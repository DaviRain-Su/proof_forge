import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program Counter where
  state count : UInt64

  init(initial : UInt64) do
    count := initial

  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count

  view get() : UInt64 do
    return count

def counter : ProofForgeV2.Source.Program := Counter

/-- Canonical source text used by the ProgramV1 CLI/product smoke path. -/
def counterSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Counter where\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

def counterModuleNameV1 : String := "Examples.Counter"

def counterWithSynchronousCall : ProofForgeV2.Source.Program :=
  ProofForgeV2.Source.Program.build "CounterWithCall" #[
    .stateDecl { name := "count", type := .u64 },
    .initializer { params := #[], body := #[] },
    .entry {
      name := "callPeer", params := #[], result := .u64, mode := .mutate,
      body := #[.synchronousCall "peer", .returnValue (.literal 0)]
    }
  ]

def counterWithDifferentBusinessLogic : ProofForgeV2.Source.Program :=
  ProofForgeV2.Source.Program.build "CounterDifferentLogic" #[
    .stateDecl { name := "count", type := .u64 },
    .initializer {
      params := #[{ name := "initial", type := .u64 }]
      body := #[.assign "count" (.variable "initial")]
    },
    .entry {
      name := "increment", params := #[{ name := "delta", type := .u64 }],
      result := .u64, mode := .mutate,
      body := #[.returnValue (.literal 99)]
    },
    .entry {
      name := "get", params := #[], result := .u64, mode := .view,
      body := #[.returnValue (.variable "count")]
    }
  ]

end ProofForgeV2.Examples
