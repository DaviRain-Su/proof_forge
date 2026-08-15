/-
  Aleo Instructions fixtures: entry-only OptionState / MapMini sources keep
  the committed Instructions goldens. Full Examples now admit computed views
  as off-chain query descriptors (not Final returns).
-/
namespace Tests.Fixtures.AleoAdmitSurfacesV1

/-- Full Examples/OptionState.lean computed `peek` is a query descriptor. -/
def fullExampleComputedViewOptionState : String :=
  "computed query view `peek` (match over Option state)"

/-- Full Examples/MapMini.lean computed `get` is a query descriptor. -/
def fullExampleComputedViewMapMini : String :=
  "computed query view `get` (match over Map index)"


/-- Loader / product module selector for OptionState admit-surface. -/
def optionStateAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.OptionState"

/-- Loader / product module selector for MapMini admit-surface. -/
def mapMiniAdmitModuleName : String := "Tests.Fixtures.AleoAdmit.MapMini"


/-- Artifact / program-id stem for OptionState admit (→ `optionstate.aleo`). -/
def optionStateAdmitProgramId : String := "optionstate"

/-- Artifact / program-id stem for MapMini admit (→ `mapmini.aleo`). -/
def mapMiniAdmitProgramId : String := "mapmini"


/-- OptionState admit-surface: entry-only (setSome/clear); no computed peek
    in the Instructions golden. Full Examples/OptionState `peek` is a query
    descriptor and must not appear in `{id}.aleo`.
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

/-- MapMini admit-surface: entry put only; no computed get in the
    Instructions golden. Full Examples/MapMini `get` is a query descriptor. -/
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
