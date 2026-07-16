import ProofForge.Backend.WasmHost.WasmInterpreter

/-!
Chain-agnostic symbolic-execution helpers for the in-Lean Wasm interpreter.

This is the first WASM-1 proof surface: generic state-effect lemmas over the
Wasm stack machine and host-neutral tables. Contract-specific refinement work
should compose these helpers rather than inspect concrete contract programs.

`WasmInterpreter.evalInsn` is currently a mutual `partial def`, so per-instruction
lemmas over that evaluator need a later refactor that factors a total, reducible
core step out of the interpreter. Keep NEAR/CosmWasm host facts out of this file;
host-specific lemmas belong in thin host modules on top of this core.
-/

namespace ProofForge.Backend.WasmHost.WasmExec

open ProofForge.Backend.WasmHost.WasmInterpreter

set_option linter.unusedSimpArgs false

abbrev Bytes := WasmInterpreter.Bytes
abbrev LinearMemory := WasmInterpreter.LinearMemory
abbrev Locals := WasmInterpreter.Locals
abbrev Globals := WasmInterpreter.Globals
abbrev Registers := WasmInterpreter.Registers
abbrev Storage := WasmInterpreter.Storage
abbrev HostState := WasmInterpreter.HostState
abbrev State := WasmInterpreter.WasmState
abbrev StateStep := State → Except String State

def runStateSteps : List StateStep → State → Except String State
  | [], state => .ok state
  | step :: rest, state => do
      let state ← step state
      runStateSteps rest state

structure StateStepReduction (step : StateStep) (state nextState : State) : Prop where
  hstep : step state = .ok nextState

theorem StateStepReduction.of_step
    {step : StateStep} {state nextState : State}
    (hstep : step state = .ok nextState) :
    StateStepReduction step state nextState :=
  { hstep }

def pushStep (value : Nat) : StateStep :=
  fun state => .ok (stackPush state value)

def dropStep : StateStep :=
  fun state => execDrop state

def constStep (text : String) : StateStep :=
  fun state => execConst state text

def plainStep (name : String) : StateStep :=
  fun state => evalPlain state name

def localGetStep (name : String) : StateStep :=
  fun state => execLocalGet state name

def localSetStep (name : String) : StateStep :=
  fun state => execLocalSet state name

def localTeeStep (name : String) : StateStep :=
  fun state => execLocalTee state name

def globalGetStep (name : String) : StateStep :=
  fun state => execGlobalGet state name

def globalSetStep (name : String) : StateStep :=
  fun state => execGlobalSet state name

def loadStep (name : String) (offset : Nat) : StateStep :=
  fun state => execLoad state name offset

def storeStep (name : String) (offset : Nat) : StateStep :=
  fun state => execStore state name offset

def hostCallStep (name : String) : StateStep :=
  fun state => runHostCall name state

inductive StateStepReductionChain : List StateStep → State → State → Prop where
  | nil (state : State) : StateStepReductionChain [] state state
  | cons {step : StateStep} {rest : List StateStep} {state midState finalState : State}
      (head : StateStepReduction step state midState)
      (tail : StateStepReductionChain rest midState finalState) :
      StateStepReductionChain (step :: rest) state finalState

theorem runStateSteps_of_reductionChain
    {steps : List StateStep} {state finalState : State}
    (chain : StateStepReductionChain steps state finalState) :
    runStateSteps steps state = .ok finalState := by
  induction chain with
  | nil state =>
      rfl
  | cons head tail ih =>
      rw [runStateSteps, head.hstep]
      exact ih

theorem StateStepReductionChain.append
    {leftSteps rightSteps : List StateStep}
    {state midState finalState : State}
    (leftChain : StateStepReductionChain leftSteps state midState)
    (rightChain : StateStepReductionChain rightSteps midState finalState) :
    StateStepReductionChain (leftSteps ++ rightSteps) state finalState := by
  induction leftChain with
  | nil state =>
      simpa using rightChain
  | cons head tail ih =>
      simpa using StateStepReductionChain.cons head (ih rightChain)

structure ExecutionSegment (steps : List StateStep)
    (post : State → State → Prop) (state finalState : State) : Prop where
  chain : StateStepReductionChain steps state finalState
  postcondition : post state finalState

theorem runStateSteps_of_executionSegment
    {steps : List StateStep} {post : State → State → Prop}
    {state finalState : State}
    (segment : ExecutionSegment steps post state finalState) :
    runStateSteps steps state = .ok finalState :=
  runStateSteps_of_reductionChain segment.chain

theorem executionSegment_of_reductionChain
    {steps : List StateStep} {post : State → State → Prop}
    {state finalState : State}
    (chain : StateStepReductionChain steps state finalState)
    (hpost : post state finalState) :
    ExecutionSegment steps post state finalState :=
  { chain
    postcondition := hpost }

theorem executionSegment_append
    {leftSteps rightSteps : List StateStep}
    {leftPost rightPost combinedPost : State → State → Prop}
    {state midState finalState : State}
    (combine :
      leftPost state midState → rightPost midState finalState →
        combinedPost state finalState)
    (leftSegment : ExecutionSegment leftSteps leftPost state midState)
    (rightSegment : ExecutionSegment rightSteps rightPost midState finalState) :
    ExecutionSegment (leftSteps ++ rightSteps) combinedPost state finalState :=
  { chain :=
      StateStepReductionChain.append leftSegment.chain rightSegment.chain
    postcondition :=
      combine leftSegment.postcondition rightSegment.postcondition }

structure StateStepProvider (steps : List StateStep)
    (pre : State → Prop) (post : State → State → Prop) : Prop where
  chain :
    ∀ {state}, pre state →
      ∃ finalState,
        StateStepReductionChain steps state finalState ∧
          post state finalState

theorem stateStepProvider_single
    {step : StateStep} {pre : State → Prop} {post : State → State → Prop}
    (nextState : ∀ state, pre state → State)
    (reduction :
      ∀ {state} (hpre : pre state),
        StateStepReduction step state (nextState state hpre))
    (postcondition :
      ∀ {state} (hpre : pre state),
        post state (nextState state hpre)) :
    StateStepProvider [step] pre post where
  chain := by
    intro state hpre
    exact ⟨nextState state hpre,
      StateStepReductionChain.cons (reduction hpre)
        (StateStepReductionChain.nil (nextState state hpre)),
      postcondition hpre⟩

theorem stateStepProvider_append
    {leftSteps rightSteps : List StateStep}
    {leftPre rightPre : State → Prop}
    {leftPost rightPost combinedPost : State → State → Prop}
    (leftProvider :
      StateStepProvider leftSteps leftPre leftPost)
    (rightProvider :
      StateStepProvider rightSteps rightPre rightPost)
    (rightPre_of_leftPost :
      ∀ {state midState},
        leftPre state → leftPost state midState → rightPre midState)
    (combine :
      ∀ {state midState finalState},
        leftPre state →
        leftPost state midState →
        rightPost midState finalState →
        combinedPost state finalState) :
    StateStepProvider (leftSteps ++ rightSteps) leftPre combinedPost where
  chain := by
    intro state hleftPre
    obtain ⟨midState, leftChain, hleftPost⟩ :=
      leftProvider.chain hleftPre
    obtain ⟨finalState, rightChain, hrightPost⟩ :=
      rightProvider.chain
        (rightPre_of_leftPost hleftPre hleftPost)
    exact ⟨finalState,
      StateStepReductionChain.append leftChain rightChain,
      combine hleftPre hleftPost hrightPost⟩

theorem runStateSteps_post_of_provider
    {steps : List StateStep} {pre : State → Prop}
    {post : State → State → Prop} {state : State}
    (provider : StateStepProvider steps pre post) (hpre : pre state) :
    ∃ finalState,
      runStateSteps steps state = .ok finalState ∧
      post state finalState := by
  obtain ⟨finalState, chain, hpost⟩ := provider.chain hpre
  exact ⟨finalState, runStateSteps_of_reductionChain chain, hpost⟩

theorem valueStack_stackPush (state : State) (value : Nat) :
    (stackPush state value).valueStack = state.valueStack.push value := rfl

theorem locals_stackPush (state : State) (value : Nat) :
    (stackPush state value).locals = state.locals := rfl

theorem globals_stackPush (state : State) (value : Nat) :
    (stackPush state value).globals = state.globals := rfl

theorem memory_stackPush (state : State) (value : Nat) :
    (stackPush state value).memory = state.memory := rfl

theorem host_stackPush (state : State) (value : Nat) :
    (stackPush state value).host = state.host := rfl

theorem stackPeek_stackPush (state : State) (value : Nat) :
    stackPeek (stackPush state value) = .ok value := by
  simp [stackPeek, stackPush]

theorem stackPop_stackPush (state : State) (value : Nat) :
    stackPop (stackPush state value) = .ok (value, state) := by
  simp [stackPop, stackPush]

theorem pushStep_ok (state : State) (value : Nat) :
    StateStepReduction (pushStep value) state (stackPush state value) :=
  StateStepReduction.of_step rfl

theorem splitStackArgs_zero (state : State) :
    splitStackArgs state 0 = .ok (#[], state) := by
  simp [splitStackArgs]

theorem splitStackArgs_stackPush1 (state : State) (a : Nat) :
    splitStackArgs (stackPush state a) 1 = .ok (#[a], state) := by
  simp [splitStackArgs, stackPush, Array.extract_push]

theorem splitStackArgs_stackPush2 (state : State) (a b : Nat) :
    splitStackArgs (stackPush (stackPush state a) b) 2 = .ok (#[a, b], state) := by
  have hle1 : ¬ state.valueStack.size + 1 ≤ state.valueStack.size := by omega
  have hlt : ¬ state.valueStack.size + 1 + 1 < 2 := by omega
  simp [splitStackArgs, stackPush, Array.extract_push, hle1, hlt]

theorem splitStackArgs_stackPush3 (state : State) (a b c : Nat) :
    splitStackArgs (stackPush (stackPush (stackPush state a) b) c) 3 =
      .ok (#[a, b, c], state) := by
  have hle1 : ¬ state.valueStack.size + 1 ≤ state.valueStack.size := by omega
  have hlepos2 : state.valueStack.size ≤ state.valueStack.size + 1 + 1 := by omega
  have hlt : ¬ state.valueStack.size + 1 + 1 + 1 < 3 := by omega
  simp [splitStackArgs, stackPush, Array.extract_push, hle1, hlepos2, hlt]

theorem splitStackArgs_stackPush4 (state : State) (a b c d : Nat) :
    splitStackArgs
        (stackPush (stackPush (stackPush (stackPush state a) b) c) d) 4 =
      .ok (#[a, b, c, d], state) := by
  have hle1 : ¬ state.valueStack.size + 1 ≤ state.valueStack.size := by omega
  have hlepos2 : state.valueStack.size ≤ state.valueStack.size + 1 + 1 := by omega
  have hlepos3 : state.valueStack.size ≤ state.valueStack.size + 1 + 1 + 1 := by omega
  have hlt : ¬ state.valueStack.size + 1 + 1 + 1 + 1 < 4 := by omega
  simp [splitStackArgs, stackPush, Array.extract_push, hle1, hlepos2, hlepos3, hlt]

theorem splitStackArgs_stackPush5 (state : State) (a b c d e : Nat) :
    splitStackArgs
        (stackPush (stackPush (stackPush (stackPush (stackPush state a) b) c) d) e) 5 =
      .ok (#[a, b, c, d, e], state) := by
  have hle1 : ¬ state.valueStack.size + 1 ≤ state.valueStack.size := by omega
  have hlepos2 : state.valueStack.size ≤ state.valueStack.size + 1 + 1 := by omega
  have hlepos3 : state.valueStack.size ≤ state.valueStack.size + 1 + 1 + 1 := by omega
  have hlepos4 : state.valueStack.size ≤ state.valueStack.size + 1 + 1 + 1 + 1 := by omega
  have hlt : ¬ state.valueStack.size + 1 + 1 + 1 + 1 + 1 < 5 := by omega
  simp [splitStackArgs, stackPush, Array.extract_push, hle1, hlepos2, hlepos3, hlepos4, hlt]

theorem evalPlain_unary_stackPush
    (state : State) (name : String) (value result : Nat)
    (happly : applyUnaryPlain name value = some result) :
    evalPlain (stackPush state value) name = .ok (stackPush state result) := by
  unfold evalPlain
  simp [Bind.bind, Except.bind, stackPeek_stackPush, stackPop_stackPush, happly]

theorem plainStep_unary_stackPush
    (state : State) (name : String) (value result : Nat)
    (happly : applyUnaryPlain name value = some result) :
    StateStepReduction (plainStep name)
      (stackPush state value) (stackPush state result) :=
  StateStepReduction.of_step <| by
    simpa [plainStep] using evalPlain_unary_stackPush state name value result happly

theorem evalPlain_binary_stackPush
    (state : State) (name : String) (lhs rhs result : Nat)
    (hunary : applyUnaryPlain name rhs = none)
    (happly : applyBinaryPlain name lhs rhs = some result) :
    evalPlain (stackPush (stackPush state lhs) rhs) name =
      .ok (stackPush state result) := by
  unfold evalPlain
  simp [Bind.bind, Except.bind, stackPeek_stackPush, stackPop_stackPush, hunary, happly]

theorem plainStep_binary_stackPush
    (state : State) (name : String) (lhs rhs result : Nat)
    (hunary : applyUnaryPlain name rhs = none)
    (happly : applyBinaryPlain name lhs rhs = some result) :
    StateStepReduction (plainStep name)
      (stackPush (stackPush state lhs) rhs) (stackPush state result) :=
  StateStepReduction.of_step <| by
    simpa [plainStep] using
      evalPlain_binary_stackPush state name lhs rhs result hunary happly

theorem execDrop_stackPush (state : State) (value : Nat) :
    execDrop (stackPush state value) = .ok state := by
  simp [execDrop, stackPop_stackPush, Bind.bind, Except.bind]

theorem dropStep_stackPush (state : State) (value : Nat) :
    StateStepReduction dropStep (stackPush state value) state :=
  StateStepReduction.of_step <| by
    simpa [dropStep] using execDrop_stackPush state value

theorem execConst_ok (state : State) (text : String) (value : Nat)
    (hvalue : natValue? text = .ok value) :
    execConst state text = .ok (stackPush state value) := by
  simp [execConst, hvalue, Bind.bind, Except.bind]

theorem constStep_ok (state : State) (text : String) (value : Nat)
    (hvalue : natValue? text = .ok value) :
    StateStepReduction (constStep text) state (stackPush state value) :=
  StateStepReduction.of_step <| by
    simpa [constStep] using execConst_ok state text value hvalue

theorem execLocalGet_ok (state : State) (name : String) (value : Nat)
    (hlookup : lookupLocal? state.locals name = some value) :
    execLocalGet state name = .ok (stackPush state value) := by
  simp [execLocalGet, hlookup]

theorem localGetStep_ok (state : State) (name : String) (value : Nat)
    (hlookup : lookupLocal? state.locals name = some value) :
    StateStepReduction (localGetStep name) state (stackPush state value) :=
  StateStepReduction.of_step <| by
    simpa [localGetStep] using execLocalGet_ok state name value hlookup

theorem execLocalSet_stackPush (state : State) (name : String) (value : Nat) :
    execLocalSet (stackPush state value) name =
      .ok { state with locals := writeLocal state.locals name value } := by
  simp [execLocalSet, stackPop_stackPush, Bind.bind, Except.bind]

theorem localSetStep_stackPush (state : State) (name : String) (value : Nat) :
    StateStepReduction (localSetStep name) (stackPush state value)
      { state with locals := writeLocal state.locals name value } :=
  StateStepReduction.of_step <| by
    simpa [localSetStep] using execLocalSet_stackPush state name value

theorem execLocalTee_stackPush (state : State) (name : String) (value : Nat) :
    execLocalTee (stackPush state value) name =
      .ok { stackPush state value with
        locals := writeLocal state.locals name value } := by
  simp [execLocalTee, stackPeek_stackPush, locals_stackPush, Bind.bind, Except.bind]

theorem localTeeStep_stackPush (state : State) (name : String) (value : Nat) :
    StateStepReduction (localTeeStep name) (stackPush state value)
      { stackPush state value with locals := writeLocal state.locals name value } :=
  StateStepReduction.of_step <| by
    simpa [localTeeStep] using execLocalTee_stackPush state name value

theorem execGlobalGet_ok (state : State) (name : String) (value : Nat)
    (hlookup : lookupGlobal? state.globals name = some value) :
    execGlobalGet state name = .ok (stackPush state value) := by
  simp [execGlobalGet, hlookup]

theorem globalGetStep_ok (state : State) (name : String) (value : Nat)
    (hlookup : lookupGlobal? state.globals name = some value) :
    StateStepReduction (globalGetStep name) state (stackPush state value) :=
  StateStepReduction.of_step <| by
    simpa [globalGetStep] using execGlobalGet_ok state name value hlookup

theorem execGlobalSet_stackPush (state : State) (name : String) (value : Nat) :
    execGlobalSet (stackPush state value) name =
      .ok { state with globals := writeGlobal state.globals name value } := by
  simp [execGlobalSet, stackPop_stackPush, Bind.bind, Except.bind]

theorem globalSetStep_stackPush (state : State) (name : String) (value : Nat) :
    StateStepReduction (globalSetStep name) (stackPush state value)
      { state with globals := writeGlobal state.globals name value } :=
  StateStepReduction.of_step <| by
    simpa [globalSetStep] using execGlobalSet_stackPush state name value

theorem execLoad_stackPush
    (state : State) (name : String) (offset ptr byteCount : Nat)
    (hload : loadByteCount name = .ok byteCount) :
    execLoad (stackPush state ptr) name offset =
      .ok (stackPush state (readNatLE state.memory (ptr + offset) byteCount)) := by
  simp [execLoad, stackPop_stackPush, hload, Bind.bind, Except.bind]

theorem loadStep_stackPush
    (state : State) (name : String) (offset ptr byteCount : Nat)
    (hload : loadByteCount name = .ok byteCount) :
    StateStepReduction (loadStep name offset) (stackPush state ptr)
      (stackPush state (readNatLE state.memory (ptr + offset) byteCount)) :=
  StateStepReduction.of_step <| by
    simpa [loadStep] using execLoad_stackPush state name offset ptr byteCount hload

theorem execStore_stackPush
    (state : State) (name : String) (offset ptr value byteCount : Nat)
    (hstore : storeByteCount name = .ok byteCount) :
    execStore (stackPush (stackPush state ptr) value) name offset =
      .ok { state with memory := writeNatLE state.memory (ptr + offset) byteCount value } := by
  simp [execStore, stackPop_stackPush, hstore, Bind.bind, Except.bind]

theorem storeStep_stackPush
    (state : State) (name : String) (offset ptr value byteCount : Nat)
    (hstore : storeByteCount name = .ok byteCount) :
    StateStepReduction (storeStep name offset)
      (stackPush (stackPush state ptr) value)
      { state with memory := writeNatLE state.memory (ptr + offset) byteCount value } :=
  StateStepReduction.of_step <| by
    simpa [storeStep] using
      execStore_stackPush state name offset ptr value byteCount hstore

theorem runHostCallWith_ok
    (arity : String → Except String Nat)
    (run : String → Array Nat → State → Except String State)
    (name : String) (state argsState finalState : State)
    (argCount : Nat) (args : Array Nat)
    (harity : arity name = .ok argCount)
    (hsplit : splitStackArgs state argCount = .ok (args, argsState))
    (hrun : run name args argsState = .ok finalState) :
    runHostCallWith arity run name state = .ok finalState := by
  simp [runHostCallWith, harity, hsplit, hrun, Bind.bind, Except.bind]

theorem hostCallStep_ok (name : String) (state finalState : State)
    (hrun : runHostCall name state = .ok finalState) :
    StateStepReduction (hostCallStep name) state finalState :=
  StateStepReduction.of_step <| by
    simpa [hostCallStep] using hrun

theorem lookupLocal_writeLocal_same (locals : Locals) (name : String) (value : Nat) :
    lookupLocal? (writeLocal locals name value) name = some value := by
  simp [lookupLocal?, writeLocal]

theorem lookupGlobal_writeGlobal_same (globals : Globals) (name : String) (value : Nat) :
    lookupGlobal? (writeGlobal globals name value) name = some value := by
  simp [lookupGlobal?, writeGlobal]

theorem lookupRegister_writeRegister_same
    (registers : Registers) (id : Nat) (bytes : Bytes) :
    lookupRegister? (writeRegister registers id bytes) id = some bytes := by
  simp [lookupRegister?, writeRegister]

theorem lookupStorage_writeStorage_same (storage : Storage) (key value : Bytes) :
    lookupStorage? (writeStorage storage key value) key = some value := by
  simp [lookupStorage?, writeStorage]

theorem host_beginCall_input (host : HostState) (input : Bytes) :
    (host.beginCall input).input = input := rfl

theorem host_beginCall_registers (host : HostState) (input : Bytes) :
    (host.beginCall input).registers = #[] := rfl

theorem host_beginCall_returnValue (host : HostState) (input : Bytes) :
    (host.beginCall input).returnValue = #[] := rfl

end ProofForge.Backend.WasmHost.WasmExec
