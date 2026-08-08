/-
  Thin native-exe entry for the Aleo Instructions suite.

  Suite body lives in `Tests.Materialization.AleoInstructionsV1` and only
  exports `run` so Shards.Targets / Tests.Fast can import it without clashing
  on a second root `main`. This module is the sole root of
  `aleo_instructions_v1_focus` / `aleo-instructions-v1-focus`.
-/
import Tests.Materialization.AleoInstructionsV1

unsafe def main : IO Unit :=
  Tests.Materialization.AleoInstructionsV1.run
