import TestFixtures.Legacy.Core
import ProofForge.IR.Core.Error
import Std

namespace TestFixtures.Legacy.Validate

open TestFixtures.Legacy.Core
open ProofForge.IR.Core.Error

def validateModule (m : CoreModule) : Except ValidationError Unit := do
  -- Check duplicate state names
  let mut seen : Std.HashSet String := {}
  for s in m.state do
    if seen.contains s.name then
      .error <| ValidationError.mkSimple .duplicateId "legacy-symbol-uniqueness"
        s!"duplicate state name: {s.name}"
    seen := seen.insert s.name
  -- Check duplicate entrypoint names
  for e in m.entrypoints do
    if seen.contains e.name then
      .error <| ValidationError.mkSimple .duplicateId "legacy-symbol-uniqueness"
        s!"duplicate entrypoint name: {e.name}"
    seen := seen.insert e.name
  .ok ()

end TestFixtures.Legacy.Validate
