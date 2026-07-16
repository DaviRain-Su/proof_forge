import Init.Data.Array.Basic
import Init.Data.String.Basic

namespace ProofForge.Target

/-- Product maturity advertised by the registry (PF-P1-02). Distinct from
lifecycle marketing prose: CLI and generated tables must read this field. -/
inductive TargetMaturity where
  /-- Primary product host with source builds and multi-gate validation. -/
  | experimental
  /-- Partial surface; Counter/fixture spike, not primary product. -/
  | spike
  /-- Intentionally narrow Counter MVP (e.g. Sui). -/
  | counterMvp
  /-- Research / off-chain sourcegen; fixture or CLI-only. -/
  | research
  deriving BEq, DecidableEq, Repr, Inhabited

def TargetMaturity.id : TargetMaturity → String
  | .experimental => "experimental"
  | .spike => "spike"
  | .counterMvp => "counter-mvp"
  | .research => "research"

/-- How authors may feed a target. -/
inductive InputMode where
  | contractSource
  | fixture
  | learn
  | tokenSpec
  deriving BEq, DecidableEq, Repr, Inhabited

def InputMode.id : InputMode → String
  | .contractSource => "contract-source"
  | .fixture => "fixture"
  | .learn => "learn"
  | .tokenSpec => "token-spec"

/-- Target-first CLI verbs supported for this profile. -/
inductive TargetCommand where
  | build
  | emit
  | check
  deriving BEq, DecidableEq, Repr, Inhabited

def TargetCommand.id : TargetCommand → String
  | .build => "build"
  | .emit => "emit"
  | .check => "check"

/-- Output stages the backend can produce (not a single ArtifactKind). -/
inductive OutputStage where
  | intermediate
  | finalDeployable
  | sourcegen
  deriving BEq, DecidableEq, Repr, Inhabited

def OutputStage.id : OutputStage → String
  | .intermediate => "intermediate"
  | .finalDeployable => "final-deployable"
  | .sourcegen => "sourcegen"

/-- Deepest validation the target-first `check` path runs for this profile. -/
inductive ValidationLevel where
  | none
  | capability
  | plan
  | package
  deriving BEq, DecidableEq, Repr, Inhabited

def ValidationLevel.id : ValidationLevel → String
  | .none => "none"
  | .capability => "capability"
  | .plan => "plan"
  | .package => "package"

/-- Tool required at a named pipeline stage (PF-P1-02). -/
structure ToolStageRequirement where
  tool : String
  stage : String
  deriving Repr, BEq, Inhabited

/-- Machine-readable support matrix entry for one target (PF-P1-02). -/
structure TargetSupport where
  maturity : TargetMaturity := .research
  inputModes : Array InputMode := #[.fixture]
  commands : Array TargetCommand := #[.emit]
  outputStages : Array OutputStage := #[.sourcegen]
  validationLevel : ValidationLevel := .none
  /-- Short lowerable-fragment summary; exact IR fragment remains backend-owned. -/
  supportedFragment : String := "fixture-only"
  toolStages : Array ToolStageRequirement := #[]
  deriving Repr, Inhabited, BEq

def TargetSupport.primaryTriad (fragment : String) (tools : Array ToolStageRequirement) :
    TargetSupport := {
  maturity := .experimental
  inputModes := #[.contractSource, .fixture, .learn, .tokenSpec]
  commands := #[.build, .emit, .check]
  outputStages := #[.intermediate, .finalDeployable]
  validationLevel := .package
  supportedFragment := fragment
  toolStages := tools
}

def TargetSupport.fixtureSpike (fragment : String) (tools : Array ToolStageRequirement := #[]) :
    TargetSupport := {
  maturity := .spike
  inputModes := #[.fixture]
  commands := #[.build, .emit, .check]
  outputStages := #[.intermediate, .sourcegen]
  validationLevel := .capability
  supportedFragment := fragment
  toolStages := tools
}

def TargetSupport.fixtureResearch (fragment : String) (tools : Array ToolStageRequirement := #[]) :
    TargetSupport := {
  maturity := .research
  inputModes := #[.fixture]
  commands := #[.emit]
  outputStages := #[.sourcegen]
  validationLevel := .none
  supportedFragment := fragment
  toolStages := tools
}

def TargetSupport.allowsInput (support : TargetSupport) (mode : InputMode) : Bool :=
  support.inputModes.contains mode

def TargetSupport.allowsCommand (support : TargetSupport) (cmd : TargetCommand) : Bool :=
  support.commands.contains cmd

def TargetSupport.isFixtureOnly (support : TargetSupport) : Bool :=
  support.inputModes == #[.fixture] ||
    (support.inputModes.size == 1 && support.inputModes[0]! == .fixture)

def TargetSupport.isPrimarySource (support : TargetSupport) : Bool :=
  support.maturity == .experimental && support.allowsInput .contractSource

end ProofForge.Target
