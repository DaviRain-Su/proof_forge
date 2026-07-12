import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.U128FmtProbe

open ProofForge.IR

/-! Probe for the U128 decimal formatter (`__pf_fmt_u128`) via a JSON event.
    Emits two u128 amounts:
    - `simple` = u128 100 (lo-word only) -> "100"
    - `big`    = (u128 18446744073709551615) + (u128 18446744073709551615)
                = 36893488147419103230 (hi word = 1, exercises the full divmod10) -/

def u128 (v : Nat) : Expr := .literal (.u128 v)

def bigVal : Expr :=
  .add (u128 18446744073709551615) (u128 18446744073709551615)

def emitEp : Entrypoint := {
  name := "emitFmt", returns := .unit,
  body := #[
    .effect (.eventEmit "Fmt" #[("simple", u128 100), ("big", bigVal)])
  ]
}

def module : Module := {
  name := "U128FmtProbe"
  state := #[]
  entrypoints := #[emitEp]
}

end ProofForge.IR.Examples.U128FmtProbe
