import Lean.Elab.Frontend
import Lean.Parser.Module
import ProofForgeV2.Language.ProgramElaborationV1

/-!
# InlineProofElaborationV1

In-process Lean 4.31 elaboration for fixed-import proof modules.

* Consumes an already-held raw source `String` (never re-reads files).
* Pipeline: `parseHeader` → header gate → reuse the package-owned immutable
  Loader Environment → `Elab.IO.processCommands`.
* Captures `MessageLog`; does not print diagnostics, write `.olean`, mutate the
  search path, or execute import initializers during certification.
* Requires exact single plain `import ProofForgeV2`; the already-loaded locked
  frontend module is the only elaboration base.
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

    `baseEnvironment` must be the immutable environment minted by Loader's
    private `ProductParserSessionV1`; this function performs no import or search
    path resolution. It never opens/re-reads source, writes `.olean`, prints
    messages, loads plugins, or executes import initializers. Header must be
    exactly one plain `import ProofForgeV2`. Ordinary in-process elaboration
    only — not containment. -/
unsafe def elaborateInlineProofSourceV1
    (baseEnvironment : Environment)
    (source : String)
    (fileName : String := "<inline-proof>")
    (mainModule : Name := `InlineProof) :
    IO (Except InlineProofElabFaultV1 InlineProofElabEnvV1) := do
  let inputCtx := mkInputContext source fileName
  let (header, parserState, parseMessages) ← parseHeader inputCtx
  if parseMessages.hasErrors then
    return .error (mkFault .headerParse parseMessages)
  unless validateHeaderGate header.raw do
    return .error (mkFault .headerGate parseMessages)
  unless baseEnvironment.header.moduleNames.any
      (· == `ProofForgeV2.Language.ProgramElaborationV1) do
    return .error (mkFault .headerImport parseMessages)
  let env := baseEnvironment.setMainModule mainModule
  -- Elevated bounds for same-file L1 proofs over generated structured subjects
  -- and the contract-agnostic Reference/preservation theorem stack.
  let elabOpts : Options :=
    let o := ({} : Options)
    let o := maxHeartbeats.set o 80000000
    maxRecDepth.set o 400000
  let commandState := Command.mkState env parseMessages elabOpts
  let cmdResult ←
    try
      let processed ← IO.processCommands inputCtx parserState commandState
      pure (some processed)
    catch _ =>
      pure none
  match cmdResult with
  | none =>
      return .error (mkFault .commands parseMessages)
  | some processed =>
      let finalMessages := processed.commandState.messages
      if finalMessages.hasErrors then
        return .error (mkFault .commands finalMessages)
      else
        return .ok (mkEnv processed.commandState.env finalMessages)

end ProofForgeV2.Compiler.InlineProofElaborationV1
