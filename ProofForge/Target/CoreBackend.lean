import ProofForge.IR.Contract
import ProofForge.IR.Legacy.Core
import ProofForge.IR.Elaborate
import ProofForge.IR.Legacy.Validate
import ProofForge.Target.Backend

namespace ProofForge.Target.CoreBackend

open ProofForge.IR.Legacy.Core
open ProofForge.IR.Elaborate
open ProofForge.IR.Legacy.Validate
open ProofForge.Target

/-- Configuration for a `-core` experimental backend that lowers portable IR
through a typed target plan (`Plan`) to a code AST (`Code`) and renders it to
source text. The profile supplies capability resolve / registry metadata. -/
structure CoreBackendConfig (Plan Code : Type) where
  profile : TargetProfile
  buildPlan : CoreModule → Plan
  lowerToCode : Plan → Code
  printCode : Code → String

/-- Build a `TargetBackend` from a core plan/lowering pair. All hooks return
`Unit` because the `TargetBackend` surface intentionally keeps typed plans
private (PF-P1-01 / RFC 0014); this helper wires elaboration, validation,
plan construction, lowering, and printing so that `proof-forge check` can
exercise the full core IR → target plan → code path. -/
def mkCoreBackend (cfg : CoreBackendConfig Plan Code) : TargetBackend :=
  { TargetBackend.ofProfile cfg.profile with
    validateModule? := some fun m =>
      match elaborateModule m with
      | .error e => .error { message := reprStr e }
      | .ok core =>
        match validateModule core with
        | .error e => .error { message := reprStr e }
        | .ok () => .ok ()
  , ensurePlan? := some fun m =>
      match elaborateModule m with
      | .error e => .error { message := reprStr e }
      | .ok core =>
        let _ := cfg.buildPlan core
        .ok ()
  , ensurePackage? := some fun m _ =>
      match elaborateModule m with
      | .error e => .error { message := reprStr e }
      | .ok core =>
        let plan := cfg.buildPlan core
        let code := cfg.lowerToCode plan
        let _ := cfg.printCode code
        .ok ()
  }

end ProofForge.Target.CoreBackend
