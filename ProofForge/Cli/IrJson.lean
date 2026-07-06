import ProofForge.Cli.ArrayUtil
import ProofForge.Cli.JsonUtil
import ProofForge.IR

open ProofForge.Cli.JsonUtil

namespace ProofForge.Cli

def moduleCapabilityIds (module : ProofForge.IR.Module) : Array String :=
  dedupStrings (module.capabilities.map fun capability => capability.id)

def valueTypeJson (type : ProofForge.IR.ValueType) : String :=
  jsonString type.name


end ProofForge.Cli
