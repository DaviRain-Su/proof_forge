import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
-- Void sync external call probe for Psy DPN PARTIAL invoke surface.
-- Callee is a static qualified name; DPN hashes components (no deployment binding).
program CallProbe where
  state n : UInt64

  init(v : UInt64) do
    n := v

  entry notify(x : UInt64) : UInt64 do
    call Other.ping(x)
    n := n + x
    return n

  view get() : UInt64 do
    return n
end Examples
