import ProofForge.IR.Legacy.Core
import ProofForge.IR.Core.Error
import Std

namespace ProofForge.IR.Core.Validate

open ProofForge.IR.Core ProofForge.IR.Core.Error

def validateModule (m : CoreModule) : Except ValidationError Unit := do
  -- Check duplicate state names
  let mut seen : Std.HashSet String := {}
  for s in m.state do
    if seen.contains s.name then
      .error (.duplicateName s.name)
    seen := seen.insert s.name
  -- Check duplicate entrypoint names
  for e in m.entrypoints do
    if seen.contains e.name then
      .error (.duplicateName e.name)
    seen := seen.insert e.name
  .ok ()

end ProofForge.IR.Core.Validate
