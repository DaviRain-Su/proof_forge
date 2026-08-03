import Lean.Elab.Frontend
import Lean.Parser.Module
import Lean.Util.Path

/-!
# InlineProofElaborationV1

In-process Lean 4.31 elaboration for fixed-import proof modules.

* Consumes an already-held raw source `String` (never re-reads files).
* Pipeline: `parseHeader` → header gate → `Elab.processHeader` →
  `Elab.IO.processCommands`.
* Captures `MessageLog`; does not print diagnostics or write `.olean`.
* Requires exact single plain `import ProofForgeV2`; `plugins := #[]`; no
  output path.
* Permanent in-process path (D3-E6 product decision: do not restore product
  supervisor/worker). **Not** a containment boundary and **not** a
  hostile-code sandbox.
-/

namespace ProofForgeV2.Compiler.InlineProofElaborationV1

open Lean
open Lean.Elab
open Lean.Parser

/-- Closed elaboration-failure phases. -/
inductive InlineProofElabPhaseV1 where
  | headerParse
  | headerGate
  | headerImport
  | commands
  deriving BEq, DecidableEq, Repr

/-- Closed phase fault with captured messages (no printing). -/
structure InlineProofElabFaultV1 where
  private mk ::
  phase_ : InlineProofElabPhaseV1
  messages_ : MessageLog

namespace InlineProofElabFaultV1

def phase (fault : InlineProofElabFaultV1) : InlineProofElabPhaseV1 :=
  fault.phase_

def messages (fault : InlineProofElabFaultV1) : MessageLog :=
  fault.messages_

end InlineProofElabFaultV1

/-- Private success carrier: elaborated environment plus captured messages. -/
structure InlineProofElabEnvV1 where
  private mk ::
  environment_ : Environment
  messages_ : MessageLog

namespace InlineProofElabEnvV1

def environment (value : InlineProofElabEnvV1) : Environment :=
  value.environment_

def messages (value : InlineProofElabEnvV1) : MessageLog :=
  value.messages_

end InlineProofElabEnvV1

private def mkFault (phase : InlineProofElabPhaseV1) (messages : MessageLog) :
    InlineProofElabFaultV1 :=
  ⟨phase, messages⟩

private def mkEnv (environment : Environment) (messages : MessageLog) :
    InlineProofElabEnvV1 :=
  ⟨environment, messages⟩

/-- Exact single plain `import ProofForgeV2` (reject public/meta/all and any
    extra or wrong import). Optional `module` / `prelude` tokens are tolerated
    at the syntax level; import identity remains the sole gate. -/
private def validateHeaderGate (header : Syntax) : Bool :=
  match header with
  | `(Module.header| $[module%$_]? $[prelude%$_]? $imports*) =>
      if h : imports.size = 1 then
        match imports[0] with
        | `(Module.import| import $name:ident) =>
            name.getId == `ProofForgeV2
        | _ => false
      else
        false
  | _ => false

/-- In-process elaborate a raw proof-module source already held in memory.

    Never opens or re-reads the source from disk. Does not write `.olean`, does
    not print messages, and does not load plugins. Header must be exactly one
    plain `import ProofForgeV2`. Ordinary in-process elaboration only — not
    containment. -/
unsafe def elaborateInlineProofSourceV1
    (source : String)
    (fileName : String := "<inline-proof>")
    (mainModule : Name := `InlineProof) :
    IO (Except InlineProofElabFaultV1 InlineProofElabEnvV1) := do
  enableInitializersExecution
  initSearchPath (← findSysroot "lean")
  let inputCtx := mkInputContext source fileName
  let (header, parserState, parseMessages) ← parseHeader inputCtx
  if parseMessages.hasErrors then
    return .error (mkFault .headerParse parseMessages)
  unless validateHeaderGate header.raw do
    return .error (mkFault .headerGate parseMessages)
  let (env, headerMessages) ← processHeader header {} parseMessages inputCtx
    (trustLevel := 0) (plugins := #[]) (leakEnv := false)
    (mainModule := mainModule)
  if headerMessages.hasErrors then
    return .error (mkFault .headerImport headerMessages)
  let commandState := Command.mkState env headerMessages {}
  let cmdResult ←
    try
      let state ← IO.processCommands inputCtx parserState commandState
      pure (some state)
    catch _ =>
      pure none
  match cmdResult with
  | none =>
      return .error (mkFault .commands headerMessages)
  | some state =>
      let finalMessages := state.commandState.messages
      if finalMessages.hasErrors then
        return .error (mkFault .commands finalMessages)
      else
        return .ok (mkEnv state.commandState.env finalMessages)

end ProofForgeV2.Compiler.InlineProofElaborationV1
