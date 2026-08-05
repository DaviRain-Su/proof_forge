import ProofForgeV2.Language.ProgramElaborationV1

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

/- ADR-0030 E2 example: declares `pf.assets@1.1.0` and uses both env-read
   catalog QNs in a view. This is the product vertical for E2-2a: real CLI
   `check` passes (proof gate + compile + requirements); `build` for any
   target fails closed at Plan until E2-3 opens the materializers. -/
program EnvReadBalance where
  requires extension pf.assets version "1.1.0" digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"

  state count : UInt64

  init(initial : UInt64) do
    count := initial

  view nativeBalance() : UInt64 do
    return pf.assets.native.balanceOfSelf()

  entry setCount(newCount : UInt64) : UInt64 do
    count := newCount
    return count

end ProofForgeV2.Examples

/- Canonical source text for non-CLI library tests and product verticals. The
   product CLI reads the tracked source file only through the in-process
   loader, which accepts exactly `import ProofForgeV2`. -/
def envReadBalanceSourceText : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program EnvReadBalance where\n" ++
  "  requires extension pf.assets version \"1.1.0\" digest \"sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9\"\n\n" ++
  "  state count : UInt64\n\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n\n" ++
  "  view nativeBalance() : UInt64 do\n" ++
  "    return pf.assets.native.balanceOfSelf()\n\n" ++
  "  entry setCount(newCount : UInt64) : UInt64 do\n" ++
  "    count := newCount\n" ++
  "    return count\n\n" ++
  "end ProofForgeV2.Examples\n"

def envReadBalanceModuleNameV1 : String := "Examples.EnvReadBalance"