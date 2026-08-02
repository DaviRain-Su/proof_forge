import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Targets.Psy.LowerSemanticV1
import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.EmitIRV1

/-!
# ProofForgeV2.Targets.Psy — public façade

Capability-gated Psy (Dargo/PsyProtocol) target leaf.

Port of the old `ProofForge.Backend.Psy` surface onto the current product
spine: consumes retained `SemanticProgramV1` via
`ResolvedEngineeringBuildV1` exactly like EVM/Solana/NEAR/Noir/Aleo.

Psy maps the V2 public-UInt64 envelope to reviewable `.psy` source:
  * UInt64/UInt32 → Felt, Bool → bool
  * checked u64 arith via explicit assert guards (Felt is a field element)
  * bitwise `&`/`|`/`^` and shifts as native Felt ops (golden BitwiseProbe);
    unary `~` (bitNot) lowers for **UInt32** to `x ^ 4294967295u32`
    (XOR mask; verified faithful on the real dargo VM) and stays fail-closed
    on UInt64/Int64 (no u64 type, no bitwise-not unary, 2^64−1 not
    representable as a Felt). UInt32 arithmetic/bitwise/shifts on u32
    operands stay fail-closed (VM u32 ops are not faithful to Reference:
    overflow/underflow are internal panics, shifts wrap); u32 comparisons
    are admitted (native unsigned == Reference unsigned)
  * emit → `__emit([...])`; call/schedule → `__invoke_sync#<Felt>(...)`
  * revert → `assert(false, ...)` (halt = atomic revert)

Descriptor/registry wiring is P-B: this façade exposes
`planFromCapability` + `Materializer .psy` and the pre-P-B
`planFromCompiledSemanticV1` / `buildFromCompiledSemanticV1` test entries.
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.psy

open ProofForgeV2
open ProofForgeV2.Compiler

/-- Capability-gated public Plan entry (Psy target leaf). Support is already
    decided by the capability; the Plan body consumes only retained
    SemanticProgramV1. Authority chain: semanticV1Of → makePlanFromSemanticV1
    → validatePlan. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  return plan

instance : Materializer .psy where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Psy
