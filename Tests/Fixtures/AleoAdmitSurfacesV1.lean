/-
  ALEO-ADMIT-FIXTURES: durable suite-owned admit-surface ProgramV1 sources.

  Authority: docs/targets/09-aleo-instructions-lowering.md §10 ALEO-ADMIT-FIXTURES.

  These strings are the sole product-path sources for Aleo Instructions
  structural / COMPILE-COMPARE pins that cannot use full shared Examples:

  * Accumulator credit  — entry renamed off Leo reserved `add`
  * OptionState entries — entry-only (no computed `peek` view)
  * MapMini put         — entry `put` only (no computed `get` view)

  Full `Examples/*` remain shared multi-target fixtures and may stay Plan-FC
  on Aleo (see fullExamplePlanFcReason*). Do **not** rename
  Examples/Accumulator.add / computed views for Aleo alone.

  Consumers: Tests.Materialization.AleoInstructionsV1 (MULTI-GOLDEN /
  COMPILE-COMPARE / ADMIT-FIXTURES). Not product Examples. deployable=false.
  Counter IR-1 golden remains independent authority.
-/
namespace Tests.Fixtures.AleoAdmitSurfacesV1

/-- Full Examples/Accumulator.lean Plan-FC reason on Aleo:
    entry name `add` collides with Leo reserved instruction op name. -/
def fullExamplePlanFcReasonAccumulator : String :=
  "reserved entry name `add` (Leo Instructions op); rename to non-reserved (e.g. credit)"

/-- Full Examples/OptionState.lean Plan-FC reason on Aleo:
    computed view `peek` over Option state is not bare place return. -/
def fullExamplePlanFcReasonOptionState : String :=
  "computed view `peek` (match over Option state); bare place views only"

/-- Full Examples/MapMini.lean Plan-FC reason on Aleo:
    computed view `get` over Map index is not bare place return. -/
def fullExamplePlanFcReasonMapMini : String :=
  "computed view `get` (match over Map index); bare place views only"

/-- Loader / product module selector for Accumulator admit-surface. -/
def accumulatorAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.Accumulator"

/-- Loader / product module selector for OptionState admit-surface. -/
def optionStateAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.OptionState"

/-- Loader / product module selector for MapMini admit-surface. -/
def mapMiniAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.MapMini"

/-- Artifact / program-id stem for Accumulator admit (→ `accumulator.aleo`). -/
def accumulatorAdmitProgramId : String := "accumulator"

/-- Artifact / program-id stem for OptionState admit (→ `optionstate.aleo`). -/
def optionStateAdmitProgramId : String := "optionstate"

/-- Artifact / program-id stem for MapMini admit (→ `mapmini.aleo`). -/
def mapMiniAdmitProgramId : String := "mapmini"

/-- Accumulator admit-surface: same state/view shape as Examples/Accumulator,
    entry `credit` (not reserved `add`). Used by MULTI-GOLDEN structural pin and
    COMPILE-COMPARE `accumulator-admit.compiled.aleo` full-byte pin. -/
def accumulatorAdmitSourceV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n" ++
  "  entry credit(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n"

/-- OptionState admit-surface: entry-only (setSome/clear); no computed peek.
    Full Examples/OptionState computed view stays Plan-FC on Aleo. -/
def optionStateAdmitSourceV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program OptionState where\n" ++
  "  state slot : Option UInt64\n" ++
  "  init() do\n" ++
  "    slot := Option.none()\n" ++
  "  entry setSome(v : UInt64) : UInt64 do\n" ++
  "    slot := Option.some(v)\n" ++
  "    return v\n" ++
  "  entry clear() : UInt64 do\n" ++
  "    slot := Option.none()\n" ++
  "    return 0\n"

/-- MapMini admit-surface: entry put only; no computed get view.
    Full Examples/MapMini computed view stays Plan-FC on Aleo. -/
def mapMiniAdmitSourceV1 : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program MapMini where\n" ++
  "  state m : Map UInt64 UInt64\n" ++
  "  init() do\n" ++
  "    m := Map.empty()\n" ++
  "  entry put(k : UInt64, v : UInt64) : UInt64 do\n" ++
  "    m[k] := v\n" ++
  "    return v\n"

end Tests.Fixtures.AleoAdmitSurfacesV1
