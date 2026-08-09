/-
  Aleo Instructions fixtures for source shapes not supported by the shared
  examples: OptionState and MapMini computed views remain outside the target
  Plan, so these entry-only sources exercise their supported subsets.
-/
namespace Tests.Fixtures.AleoAdmitSurfacesV1

/-- Full Examples/OptionState.lean Plan-FC reason on Aleo:
    computed view `peek` over Option state is not bare place return. -/
def fullExamplePlanFcReasonOptionState : String :=
  "computed view `peek` (match over Option state); bare place views only"

/-- Full Examples/MapMini.lean Plan-FC reason on Aleo:
    computed view `get` over Map index is not bare place return. -/
def fullExamplePlanFcReasonMapMini : String :=
  "computed view `get` (match over Map index); bare place views only"


/-- Loader / product module selector for OptionState admit-surface. -/
def optionStateAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.OptionState"

/-- Loader / product module selector for MapMini admit-surface. -/
def mapMiniAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.MapMini"


/-- Artifact / program-id stem for OptionState admit (→ `optionstate.aleo`). -/
def optionStateAdmitProgramId : String := "optionstate"

/-- Artifact / program-id stem for MapMini admit (→ `mapmini.aleo`). -/
def mapMiniAdmitProgramId : String := "mapmini"


/-- OptionState admit-surface: entry-only (setSome/clear); no computed peek.
    Full Examples/OptionState computed view stays Plan-FC on Aleo.
    ALEO-INSTRUCTIONS full-byte pin: `optionstate-admit.aleo` (1019 B). -/
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
