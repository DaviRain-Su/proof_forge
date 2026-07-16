import ProofForge.Backend.WasmHost.WasmInterpreter
import ProofForge.Backend.Refinement.Core

/-!
Counter-specific interpreter smoke tests.

These were previously inlined in `WasmInterpreter.lean`; keeping them separate
preserves the "generic layers contain 0 Counter references" discipline.
-/

namespace ProofForge.Backend.WasmHost.CounterWasmInterpreterSmoke

open ProofForge.Backend.WasmHost.WasmInterpreter
open ProofForge.Backend.Refinement

def counterRAfterInitialize : Bool :=
  match EmitWat.lowerModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok wasm =>
      match runIrEntrypointState ProofForge.IR.Semantics.State.empty
          ProofForge.IR.Examples.Counter.initializeEntrypoint with
      | .error _ => false
      | .ok irState =>
          let call : TraceCall := { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }
          match runExport wasm (initialState wasm) call with
          | .ok wasmState => R ProofForge.IR.Examples.Counter.module "count" irState wasmState
          | .error _ => false

def counterRAfterIncrement : Bool :=
  match EmitWat.lowerModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok wasm =>
      match runIrEntrypointState ProofForge.IR.Semantics.State.empty
          ProofForge.IR.Examples.Counter.initializeEntrypoint with
      | .error _ => false
      | .ok irAfterInit =>
          match runIrEntrypointState irAfterInit ProofForge.IR.Examples.Counter.increment with
          | .error _ => false
          | .ok irAfterIncrement =>
              let initCall : TraceCall := { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint }
              let incCall : TraceCall := { entrypoint := ProofForge.IR.Examples.Counter.increment }
              match runExport wasm (initialState wasm) initCall with
              | .error _ => false
              | .ok wasmState =>
                  match runExport wasm wasmState incCall with
                  | .ok wasmState =>
                      R ProofForge.IR.Examples.Counter.module "count" irAfterIncrement wasmState
                  | .error _ => false

def counterInterpreterSmoke : Bool :=
  match EmitWat.lowerModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok wasm =>
      let calls := traceCallsFromEntrypoints #[
        ProofForge.IR.Examples.Counter.initializeEntrypoint,
        ProofForge.IR.Examples.Counter.get,
        ProofForge.IR.Examples.Counter.increment,
        ProofForge.IR.Examples.Counter.get
      ]
      match runTraceList wasm calls.toList (initialState wasm) with
      | .ok _ => true
      | .error _ => false

/- These smoke predicates intentionally remain unevaluated: `evalFunc`/`evalBlock`
are mutual `partial def`s, so `native_decide` cannot reduce them. The new
`CounterWasmRefinement.lean` provides a total, inductively-proven core instead. -/

end ProofForge.Backend.WasmHost.CounterWasmInterpreterSmoke
