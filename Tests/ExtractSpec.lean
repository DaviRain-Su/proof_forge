import ProofForge
import Examples.Counter
import Examples.Pair
import Examples.Flag
import Examples.Maybe
import Examples.Window
import Examples.Phase
import Examples.Choice
import Examples.Clock
import Examples.Transfer
import Examples.EvmCtx
import Examples.TipJar
import Examples.Ping
import Examples.Call
import Examples.Info
import Examples.Peer
import Examples.Pda
import Examples.Signed
import Examples.Create
import Examples.TokenXfer
import Examples.Token2022
import Examples.Ata
import Examples.Rent
import Examples.TokenMint
import Examples.SysAlloc
import Examples.TokenAcc
import Examples.Memo
import Examples.CreatePda
import Examples.TokenApprove
import Examples.TokenFreeze
import Examples.TokenAuth
import Examples.Epoch
import Examples.TokenSize
import Examples.SysSeed
import Examples.SysXfer
import Examples.TokenMint2
import Examples.TokenNative
import Examples.Hash
import Examples.Keys
import Examples.Keccak
import Examples.Trio
import Examples.Gate
import Examples.Nonce
import Examples.TokenOwner
import Examples.TokenMs
import Tests.Fixtures

open Lean Elab Command

#pf_extract Examples.Counter.init Examples.Counter.increment Examples.Counter.get

#pf_extract Examples.Counter.init Examples.Counter.decrement Examples.Counter.get

#pf_extract Examples.Pair.init Examples.Pair.creditLeft Examples.Pair.getLeft

#pf_extract Examples.Pair.init Examples.Pair.creditLeft Examples.Pair.getLeft with "left", "right"

/--
error: profile/rejected: Nat in root type Tests.Fixtures.usesNat
-/
#guard_msgs (error) in
#pf_extract Tests.Fixtures.usesNat Examples.Counter.increment Examples.Counter.get

/--
error: extract/unsupported: mutating method missing checked arith
-/
#guard_msgs (error) in
#pf_extract Examples.Counter.init Tests.Fixtures.wrappingAdd Examples.Counter.get

/--
error: extract/unsupported: mutating method missing checked arith
-/
#guard_msgs (error) in
#pf_extract Examples.Counter.init Tests.Fixtures.wrappingSub Examples.Counter.get

elab "#pf_guard_unknown_cpi_return" : command => do
  let env ← getEnv
  match ProofForge.Extract.extractProgram env ``Examples.Counter.init
      ``Tests.Fixtures.unknownCpiResult ``Examples.Counter.get with
  | .error reason =>
      unless reason.contains "unknown CPI return semantics" do
        throwError s!"unexpected unknown-CPI error: {reason}"
  | .ok _ => throwError "unknown CPI return semantics were silently accepted"

#pf_guard_unknown_cpi_return

/--
error: extract/unsupported: field flag enum has payload
-/
#guard_msgs (error) in
#pf_extract Tests.Fixtures.initFlag Tests.Fixtures.creditFlag Tests.Fixtures.getFlagValue

/--
error: extract/unsupported: fields #[value] != inferred #[left, right]
-/
#guard_msgs (error) in
#pf_extract Examples.Pair.init Examples.Pair.creditLeft Examples.Pair.getLeft with "value"

#pf_extract Examples.Counter.init Examples.Counter.scale Examples.Counter.get

#pf_extract Examples.Counter.init Examples.Counter.divide Examples.Counter.get

#pf_extract Examples.Counter.init Examples.Counter.modulo Examples.Counter.get

#pf_extract Tests.Fixtures.initFold Tests.Fixtures.runFold Tests.Fixtures.foldProduct

elab "#pf_guard_state_fold_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initFold
        ``Tests.Fixtures.runFold ``Tests.Fixtures.foldProduct with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runFold")
    | throwError "missing state-fold method"
  let expected : Array ProofForge.Ops.Op := #[
    .forBody 2 #[
      .ite .eq .loopIx (.lit 0)
        #[.storeField "product" (.mulU64 (.arg 0) (.arg 1))]
        #[
          .storeField "quotient" (.divU64 (.arg 0) (.arg 1)),
          .storeField "remainder" (.modU64 (.arg 0) (.arg 1))
        ]
    ],
    .okState (.field (.arg 2) "product")
  ]
  unless run.ops == expected do
    throwError s!"state-fold IR mismatch: {repr run.ops}"
  let evmProgram ←
    match ProofForge.Evm.IR.fromProgram program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let yul ←
    match ProofForge.Evm.Emit.emitYul evmProgram with
    | .ok yul => pure yul
    | .error reason => throwError reason
  let productReturn := "mstore(0, sload(0))\n            return(0, 32)"
  unless (yul.splitOn productReturn).length ≥ 3 do
    throwError "EVM state-fold exit returns the last write instead of the requested state field"

#pf_guard_state_fold_ir

elab "#pf_guard_initialized_state_fold_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initFold
        ``Tests.Fixtures.runInitializedFold ``Tests.Fixtures.foldProduct with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runInitializedFold")
    | throwError "missing initialized state-fold method"
  let expected : Array ProofForge.Ops.Op := #[
    .storeField "product" (.arg 0),
    .forBody 1 #[.storeField "remainder" (.arg 0)],
    .okState (.field (.arg 1) "product")
  ]
  unless run.ops == expected do
    throwError s!"initialized state-fold IR mismatch: {repr run.ops}"

#pf_guard_initialized_state_fold_ir

elab "#pf_guard_invoke_state_fold_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initFold
        ``Tests.Fixtures.runInvokeFold ``Tests.Fixtures.foldProduct with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runInvokeFold")
    | throwError "missing CPI state-fold method"
  let expected : Array ProofForge.Ops.Op := #[
    .forBody 2 #[
      .ite .eq .loopIx (.lit 0)
        #[
          .invoke 1 #[] #[.u64le (.arg 0)],
          .storeField "product" (.arg 0)
        ] #[]
    ],
    .okState (.field (.arg 1) "product")
  ]
  unless run.ops == expected do
    throwError s!"CPI state-fold IR mismatch: {repr run.ops}"
  let snapshotProgram ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initFold
        ``Tests.Fixtures.runInvokeSnapshot ``Tests.Fixtures.foldProduct with
    | .ok p => pure p
    | .error reason => throwError reason
  let some snapshot := snapshotProgram.methods.find? (·.ixName == "runInvokeSnapshot")
    | throwError "missing CPI snapshot method"
  let snapshotExpected : Array ProofForge.Ops.Op := #[
    .letLocal 0 (.field (.arg 0) "product"),
    .invoke 1 #[] #[.u64le (.local 0)],
    .storeField "product" (.lit 0),
    .okState (.local 0)
  ]
  unless snapshot.ops == snapshotExpected do
    throwError s!"CPI snapshot IR mismatch: {repr snapshot.ops}"

#pf_guard_invoke_state_fold_ir

elab "#pf_guard_nested_state_loop_control" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initGuardedLoop
        ``Tests.Fixtures.runGuardedLoop ``Tests.Fixtures.guardedLoopSelected with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runGuardedLoop")
    | throwError "missing guarded state-loop method"
  let rec valIndices (fuel : Nat) (value : ProofForge.Ops.Val) : Array ProofForge.Ops.Val :=
    match fuel with
    | 0 => #[]
    | fuel' + 1 =>
      match value with
      | .indexGet base "cells" index _ _ =>
          #[index] ++ valIndices fuel' base ++ valIndices fuel' index
      | .field base _ | .bitNot base => valIndices fuel' base
      | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
      | .shiftL lhs rhs | .shiftR lhs rhs | .addU64 lhs rhs | .subU64 lhs rhs
      | .mulU64 lhs rhs | .divU64 lhs rhs | .modU64 lhs rhs =>
          valIndices fuel' lhs ++ valIndices fuel' rhs
      | .select _ lhs rhs thn els =>
          valIndices fuel' lhs ++ valIndices fuel' rhs ++
            valIndices fuel' thn ++ valIndices fuel' els
      | _ => #[]
  let rec opIndices (fuel : Nat) (ops : Array ProofForge.Ops.Op) : Array ProofForge.Ops.Val :=
    match fuel with
    | 0 => #[]
    | fuel' + 1 => ops.flatMap fun
      | .letLocal _ value | .setLocal _ value | .storeField _ value | .okState value
      | .returnU64 value => valIndices 64 value
      | .checkedAddU64 lhs rhs | .checkedSubU64 lhs rhs | .checkedMulU64 lhs rhs
      | .checkedDivU64 lhs rhs | .checkedModU64 lhs rhs =>
          valIndices 64 lhs ++ valIndices 64 rhs
      | .indexSet "cells" index value _ _ =>
          #[index] ++ valIndices 64 value
      | .ite _ lhs rhs thn els =>
          valIndices 64 lhs ++ valIndices 64 rhs ++
            opIndices fuel' thn ++ opIndices fuel' els
      | .forBody _ body => opIndices fuel' body
      | _ => #[]
  match run.ops with
  | #[.ite .eq (.arg 1) (.lit 0) thn els] =>
      unless thn == #[.storeField "selected" (.lit 0), .okState (.lit 0)] do
        throwError s!"zero-quantity branch was not preserved: {repr thn}"
      unless els.any fun | .forBody 4 _ => true | _ => false do
        throwError s!"guarded loop was not retained in the else branch: {repr els}"
  | _ => throwError s!"state loop escaped its source guard: {repr run.ops}"
  let indices := opIndices 32 run.ops
  let rec containsLoopIx : ProofForge.Ops.Val → Bool
    | .loopIx => true
    | .field base _ | .bitNot base => containsLoopIx base
    | .indexGet base _ index _ _ => containsLoopIx base || containsLoopIx index
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftL lhs rhs | .shiftR lhs rhs | .addU64 lhs rhs | .subU64 lhs rhs
    | .mulU64 lhs rhs | .divU64 lhs rhs | .modU64 lhs rhs =>
        containsLoopIx lhs || containsLoopIx rhs
    | .select _ lhs rhs thn els =>
        containsLoopIx lhs || containsLoopIx rhs || containsLoopIx thn || containsLoopIx els
    | _ => false
  let rec containsArg : ProofForge.Ops.Val → Bool
    | .arg _ => true
    | .field base _ | .bitNot base => containsArg base
    | .indexGet base _ index _ _ => containsArg base || containsArg index
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftL lhs rhs | .shiftR lhs rhs | .addU64 lhs rhs | .subU64 lhs rhs
    | .mulU64 lhs rhs | .divU64 lhs rhs | .modU64 lhs rhs =>
        containsArg lhs || containsArg rhs
    | .select _ lhs rhs thn els =>
        containsArg lhs || containsArg rhs || containsArg thn || containsArg els
    | _ => false
  unless !indices.isEmpty && indices.all fun index =>
      containsLoopIx index && !containsArg index do
    throwError s!"state-loop vector indices escaped callback scope: {repr indices}"
  let rec containsArgIndex (want : Nat) : ProofForge.Ops.Val → Bool
    | .arg index => index == want
    | .field base _ | .bitNot base => containsArgIndex want base
    | .indexGet base _ index _ _ =>
        containsArgIndex want base || containsArgIndex want index
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs
    | .shiftL lhs rhs | .shiftR lhs rhs | .addU64 lhs rhs | .subU64 lhs rhs
    | .mulU64 lhs rhs | .divU64 lhs rhs | .modU64 lhs rhs =>
        containsArgIndex want lhs || containsArgIndex want rhs
    | .select _ lhs rhs thn els =>
        containsArgIndex want lhs || containsArgIndex want rhs ||
          containsArgIndex want thn || containsArgIndex want els
    | _ => false
  let rec containsReplacement (fuel : Nat) (ops : Array ProofForge.Ops.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
      | .indexSet "cells" _ value _ _ => containsArgIndex 2 value
      | .ite _ _ _ thn els =>
          containsReplacement fuel' thn || containsReplacement fuel' els
      | .forBody _ body => containsReplacement fuel' body
      | _ => false
  unless containsReplacement 32 run.ops do
    throwError s!"captured replacement parameter was rewritten as a loop binder: {repr run.ops}"

#pf_guard_nested_state_loop_control

elab "#pf_guard_composed_state_fold_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initFold
        ``Tests.Fixtures.runComposedFold ``Tests.Fixtures.foldProduct with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runComposedFold")
    | throwError "missing composed state-fold method"
  let expected : Array ProofForge.Ops.Op := #[
    .forBody 1 #[
      .ite .lt (.arg 0) (.lit 10)
        #[.storeField "product" (.addU64 (.field (.arg 1) "product") (.arg 0))]
        #[.storeField "quotient" (.arg 0)],
      .storeField "remainder" (.arg 0)
    ],
    .okState (.field (.arg 1) "product")
  ]
  unless run.ops == expected do
    throwError s!"composed state-fold IR mismatch: {repr run.ops}"

#pf_guard_composed_state_fold_ir

elab "#pf_guard_nested_composed_state_fold_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initFold
        ``Tests.Fixtures.runNestedComposedFold ``Tests.Fixtures.foldProduct with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runNestedComposedFold")
    | throwError "missing nested composed state-fold method"
  let expected : Array ProofForge.Ops.Op := #[
    .forBody 1 #[
      .ite .lt (.arg 0) (.lit 10)
        #[.storeField "product" (.addU64 (.field (.arg 1) "product") (.arg 0))]
        #[.storeField "quotient" (.arg 0)],
      .storeField "remainder" (.arg 0),
      .ite .lt (.field (.arg 1) "remainder") (.lit 100)
        #[.storeField "quotient" (.addU64 (.field (.arg 1) "quotient") (.lit 1))]
        #[]
    ],
    .okState (.field (.arg 1) "product")
  ]
  unless run.ops == expected do
    throwError s!"nested composed state-fold IR mismatch: {repr run.ops}"

#pf_guard_nested_composed_state_fold_ir

elab "#pf_guard_post_loop_topology_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initPostLoopTopology
        ``Tests.Fixtures.runPostLoopTopology ``Tests.Fixtures.postLoopTopologyRoot with
    | .ok p => pure p
    | .error reason => throwError reason
  let some run := program.methods.find? (·.ixName == "runPostLoopTopology")
    | throwError "missing post-loop topology method"
  let rec summarize (fuel : Nat) (ops : Array ProofForge.Ops.Op) :
      Bool × Bool × Bool × Bool :=
    match fuel with
    | 0 => (false, false, false, false)
    | fuel' + 1 => ops.foldl (init := (false, false, false, false)) fun found op =>
      let current := match op with
        | .forBody 1 _ => (true, false, false, false)
        | .storeField "count" _ => (false, true, false, false)
        | .storeField "root" _ => (false, false, true, false)
        | .indexSet "nodes" _ _ _ _ => (false, false, false, true)
        | .ite _ _ _ thn els =>
          let left := summarize fuel' thn
          let right := summarize fuel' els
          (left.1 || right.1, left.2.1 || right.2.1,
            left.2.2.1 || right.2.2.1, left.2.2.2 || right.2.2.2)
        | _ => (false, false, false, false)
      (found.1 || current.1, found.2.1 || current.2.1,
        found.2.2.1 || current.2.2.1, found.2.2.2 || current.2.2.2)
  let summary := summarize 32 run.ops
  unless summary.1 && summary.2.1 && summary.2.2.1 && summary.2.2.2 do
    throwError s!"post-loop topology continuation lost writes: {repr run.ops}"

#pf_guard_post_loop_topology_ir

elab "#pf_guard_checked_state_snapshot_ir" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initSnapshot
        ``Tests.Fixtures.collectSnapshot ``Tests.Fixtures.snapshotTotal with
    | .ok p => pure p
    | .error reason => throwError reason
  let some collect := program.methods.find? (·.ixName == "collectSnapshot")
    | throwError "missing checked state snapshot method"
  let expected : Array ProofForge.Ops.Op := #[
    .checkedAddU64 (.field (.arg 0) "total") (.field (.arg 0) "pending"),
    .letLocal 0 (.field (.arg 0) "pending"),
    .storeField "total" (.addU64 (.field (.arg 0) "total") (.local 0)),
    .storeField "pending" (.lit 0),
    .storeField "last" (.local 0),
    .okState (.local 0)
  ]
  unless collect.ops == expected do
    throwError s!"checked state snapshot IR mismatch: {repr collect.ops}"

#pf_guard_checked_state_snapshot_ir

elab "#pf_guard_dynamic_write_return" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initMarketEventBatch
        ``Tests.Fixtures.setMarketEventReturningIndex
        ``Tests.Fixtures.firstMarketEventValue with
    | .ok p => pure p
    | .error reason => throwError reason
  let some setEvent := program.methods.find? (·.ixName == "setMarketEventReturningIndex")
    | throwError "missing dynamic-write return fixture"
  let rec terminalReturns (fuel : Nat) (ops : Array ProofForge.Ops.Op) :
      Array ProofForge.Ops.Val :=
    match fuel with
    | 0 => #[]
    | fuel' + 1 =>
      ops.flatMap fun
        | .okState value => #[value]
        | .ite _ _ _ thn els => terminalReturns fuel' thn ++ terminalReturns fuel' els
        | .forBody _ body => terminalReturns fuel' body
        | _ => #[]
  unless terminalReturns 8 setEvent.ops == #[.arg 0] do
    throwError s!"dynamic vector write lost its explicit return: {repr setEvent.ops}"

#pf_guard_dynamic_write_return

elab "#pf_guard_inline_state_dynamic_write" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initMarketEventBatch
        ``Tests.Fixtures.appendMarketEventInFold
        ``Tests.Fixtures.firstMarketEventValue with
    | .ok p => pure p
    | .error reason => throwError reason
  let some append := program.methods.find? (·.ixName == "appendMarketEventInFold")
    | throwError "missing inline State dynamic-write fixture"
  let rec collectWrites (fuel : Nat) (ops : Array ProofForge.Ops.Op) :
      Array (String × Nat) × Array String :=
    match fuel with
    | 0 => (#[], #[])
    | fuel' + 1 => Id.run do
      let mut dynamic := #[]
      let mut static := #[]
      for op in ops do
        match op with
        | .indexSet name _ _ _ offset => dynamic := dynamic.push (name, offset)
        | .storeField name _ => static := static.push name
        | .ite _ _ _ thn els =>
          let thenWrites := collectWrites fuel' thn
          let elseWrites := collectWrites fuel' els
          dynamic := dynamic ++ thenWrites.1 ++ elseWrites.1
          static := static ++ thenWrites.2 ++ elseWrites.2
        | .forBody _ body =>
          let bodyWrites := collectWrites fuel' body
          dynamic := dynamic ++ bodyWrites.1
          static := static ++ bodyWrites.2
        | _ => pure ()
      return (dynamic, static)
  let writes := collectWrites 16 append.ops
  unless [0, 8, 16, 24, 32, 40].all fun offset =>
      writes.1.contains ("events", offset) do
    throwError s!"inline State helper lost variant-vector leaves: {writes.1}"
  let rec hasSelect : Nat → ProofForge.Ops.Val → Bool
    | 0, _ => false
    | _ + 1, .select _ _ _ _ _ => true
    | fuel + 1, .field base _ => hasSelect fuel base
    | fuel + 1, .indexGet base _ index _ _ =>
      hasSelect fuel base || hasSelect fuel index
    | _ + 1, _ => false
  let rec containsInlineScalar (fuel : Nat) (ops : Array ProofForge.Ops.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
      | .indexSet "events" _ value _ 8 => hasSelect 16 value
      | .ite _ _ _ thn els =>
        containsInlineScalar fuel' thn || containsInlineScalar fuel' els
      | .forBody _ body => containsInlineScalar fuel' body
      | _ => false
  unless containsInlineScalar 16 append.ops do
    throwError "pf_inline scalar event payload was not normalized"
  let rec containsProjectedUpdate (fuel : Nat) (ops : Array ProofForge.Ops.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
      | .indexSet "events" _ (.addU64 _ (.lit 1)) _ 16 => true
      | .ite _ _ _ thn els =>
        containsProjectedUpdate fuel' thn || containsProjectedUpdate fuel' els
      | .forBody _ body => containsProjectedUpdate fuel' body
      | _ => false
  unless containsProjectedUpdate 16 append.ops do
    throwError "updated-record scalar projection was not normalized"
  unless writes.2.contains "eventCount" do
    throwError s!"inline State helper lost scalar update: {writes.2}"
  unless ["lastEvent_tag", "lastEvent_p0", "lastEvent_p1", "lastEvent_p2",
      "lastEvent_p3", "lastEvent_p4"].all writes.2.contains do
    throwError s!"inline State helper lost static variant leaves: {writes.2}"
  let svm ←
    match ProofForge.Svm.Emit.emitCounterAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  let evmProgram ←
    match ProofForge.Evm.IR.fromProgram program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.Emit.emitYul evmProgram with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless svm.contains "; indexSet events[4]+40" &&
      evm.contains "sstore(add(" do
    throwError "inline State dynamic variant writes did not reach both targets"

#pf_guard_inline_state_dynamic_write

elab "#pf_guard_schema_driven_vector_layout" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Tests.Fixtures.initLayout
        ``Tests.Fixtures.setLayout ``Tests.Fixtures.getLayout with
    | .ok p => pure p
    | .error reason =>
      let methodError (kind : ProofForge.Core.IR.MethodKind) (name : Name) : String :=
        match ProofForge.Extract.extractMethod env kind name with
        | .ok _ => "ok"
        | .error detail => detail
      throwError s!"{reason}; init={methodError .init ``Tests.Fixtures.initLayout}; " ++
        s!"set={methodError .increment ``Tests.Fixtures.setLayout}; " ++
        s!"get={methodError .get ``Tests.Fixtures.getLayout}"
  let some vector := program.schema.vector? "entries"
    | throwError "layout fixture has no entries vector"
  let names := program.schema.vectorElementLeaves vector |>.map (vector.relativeLeafName ·)
  unless vector.elementBytes == 24 && names == #["marker", "left", "color"] do
    throwError s!"unexpected logical vector layout: {repr program.schema}"
  let some setter := program.methods.find? (·.ixName == "setLayout")
    | throwError "missing layout setter"
  let some getter := program.methods.find? (·.ixName == "getLayout")
    | throwError "missing layout getter"
  let rec containsWrite (fuel offset : Nat)
      (ops : Array ProofForge.Extract.IR.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
        | .indexSet "entries" _ _ 2 actual => actual == offset
        | .ite _ _ _ thn els =>
            containsWrite fuel' offset thn || containsWrite fuel' offset els
        | .forBody _ body => containsWrite fuel' offset body
        | _ => false
  let rec containsRead (offset : Nat) : ProofForge.Extract.IR.Val → Bool
    | .indexGet _ "entries" _ _ actual => actual == offset
    | .field base _ | .bitNot base => containsRead offset base
    | .select _ lhs rhs thn els =>
        containsRead offset lhs || containsRead offset rhs ||
          containsRead offset thn || containsRead offset els
    | _ => false
  let rec opsContainRead (fuel offset : Nat)
      (ops : Array ProofForge.Extract.IR.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
        | .letLocal _ value | .setLocal _ value | .returnU64 value =>
            containsRead offset value
        | .ite _ lhs rhs thn els =>
            containsRead offset lhs || containsRead offset rhs ||
              opsContainRead fuel' offset thn || opsContainRead fuel' offset els
        | .forBody _ body => opsContainRead fuel' offset body
        | _ => false
  let getterReads := opsContainRead 8 8 getter.ops
  let svm ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  unless containsWrite 8 8 setter.ops && containsWrite 8 16 setter.ops && getterReads do
    let some svmGetter := svm.methods.find? (·.ixName == "getLayout")
      | throwError "lowered SVM program has no layout getter"
    throwError s!"schema offsets did not replace field-name guesses: " ++
      s!"write8={containsWrite 8 8 setter.ops}, write16={containsWrite 8 16 setter.ops}, " ++
      s!"read0={opsContainRead 8 0 getter.ops}, read8={getterReads}, " ++
      s!"read16={opsContainRead 8 16 getter.ops}; ops={repr svmGetter.ops}"
  let evm ←
    match ProofForge.Evm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let svmAsm ←
    match ProofForge.Svm.Emit.emitAsm svm with
    | .ok asm => pure asm
    | .error reason => throwError reason
  let evmYul ←
    match ProofForge.Evm.Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless !svmAsm.isEmpty && !evmYul.isEmpty do
    throwError "schema-driven vector layout did not reach both emitters"

#pf_guard_schema_driven_vector_layout

elab "#pf_guard_nested_vector_path" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Tests.Fixtures.initNestedVector
        ``Tests.Fixtures.setNestedVector ``Tests.Fixtures.getNestedVector with
    | .ok p => pure p
    | .error reason => throwError reason
  let some vector := program.schema.vector? "book_right"
    | throwError s!"nested vector lost its qualified schema path: {repr program.schema}"
  unless vector.length == 2 && vector.elementBytes == 8 do
    throwError s!"unexpected nested vector layout: {repr vector}"
  let some setter := program.methods.find? (·.ixName == "setNestedVector")
    | throwError "missing nested-vector setter"
  let some getter := program.methods.find? (·.ixName == "getNestedVector")
    | throwError "missing nested-vector getter"
  let setterWrites := setter.ops.any fun
    | .ite _ _ _ thn els => (thn ++ els).any fun
        | .indexSet "book_right" _ _ 2 0 => true
        | _ => false
    | .indexSet "book_right" _ _ 2 0 => true
    | _ => false
  let rec readsNested : ProofForge.Extract.IR.Val → Bool
    | .indexGet _ "book_right" _ _ 0 => true
    | .field base _ | .bitNot base => readsNested base
    | .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs |
        .shiftL lhs rhs | .shiftR lhs rhs | .addU64 lhs rhs |
        .subU64 lhs rhs | .mulU64 lhs rhs | .divU64 lhs rhs | .modU64 lhs rhs =>
        readsNested lhs || readsNested rhs
    | .select _ lhs rhs thn els =>
        readsNested lhs || readsNested rhs || readsNested thn || readsNested els
    | _ => false
  let rec opsRead (fuel : Nat) (ops : Array ProofForge.Extract.IR.Op) : Bool :=
    match fuel with
    | 0 => false
    | fuel' + 1 => ops.any fun
      | .letLocal _ value | .setLocal _ value | .returnU64 value => readsNested value
      | .ite _ lhs rhs thn els =>
          readsNested lhs || readsNested rhs || opsRead fuel' thn || opsRead fuel' els
      | .forBody _ body => opsRead fuel' body
      | _ => false
  let getterReads := opsRead 8 getter.ops
  unless setterWrites && getterReads do
    throwError s!"nested vector path did not reach dynamic IR: " ++
      s!"setter={setterWrites}, getter={getterReads}"
  let svm ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let svmAsm ←
    match ProofForge.Svm.Emit.emitAsm svm with
    | .ok asm => pure asm
    | .error reason => throwError reason
  let evmYul ←
    match ProofForge.Evm.Emit.emitYul evm with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless !svmAsm.isEmpty && !evmYul.isEmpty do
    throwError "nested vector path did not reach both target emitters"

#pf_guard_nested_vector_path

elab "#pf_guard_staged_nested_transition" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Tests.Fixtures.initNestedVector
        ``Tests.Fixtures.setStagedNestedVector ``Tests.Fixtures.getNestedVector with
    | .ok p => pure p
    | .error reason => throwError reason
  let svm ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.IR.fromExtracted program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let some svmSetter := svm.methods.find? (·.ixName == "setStagedNestedVector")
    | throwError "missing lowered staged nested-vector setter"
  let rec writtenNames (fuel : Nat) (ops : Array ProofForge.Svm.IR.Op) : Array String :=
    match fuel with
    | 0 => #[]
    | fuel' + 1 => ops.flatMap fun
      | .storeField name _ | .indexSet name _ _ _ _ => #[name]
      | .ite _ _ _ thn els => writtenNames fuel' thn ++ writtenNames fuel' els
      | .forBody _ body => writtenNames fuel' body
      | _ => #[]
  let names := writtenNames 32 svmSetter.ops
  let tag? := names.findIdx? (· == "tag")
  let root? := names.findIdx? (· == "book_root")
  let right? := names.findIdx? (· == "book_right")
  unless (names.filter (· == "tag")).size == 1 &&
      (names.filter (· == "book_root")).size == 1 &&
      (names.filter (· == "book_right")).size == 1 do
    throwError s!"staged nested writes were missing or duplicated: {names}; {repr svmSetter.ops}"
  match tag?, root?, right? with
  | some tag, some root, some right =>
      unless tag < root && tag < right do
        throwError s!"outer transition did not precede nested writes: {names}"
  | _, _, _ => throwError s!"staged nested transition lost a write: {names}"
  unless !names.contains "book" && !names.contains "root" && !names.contains "right" &&
      !names.contains "book_tag" do
    throwError s!"staged nested transition leaked an untyped field name: {names}"
  unless (ProofForge.Svm.Emit.emitAsm svm).isOk && (ProofForge.Evm.Emit.emitYul evm).isOk do
    throwError "staged nested transition did not reach both target emitters"

#pf_guard_staged_nested_transition

elab "#pf_guard_conditional_local" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initChoice
        ``Tests.Fixtures.choose ``Tests.Fixtures.getChosen with
    | .ok p => pure p
    | .error reason => throwError reason
  let some choose := program.methods.find? (·.ixName == "choose")
    | throwError "missing conditional-local method"
  let expected : Array ProofForge.Ops.Op := #[
    .letLocal 0 (.select .lt (.arg 0) (.arg 1) (.arg 0) (.arg 1)),
    .okState (.local 0)
  ]
  unless choose.ops == expected do
    throwError s!"conditional-local IR mismatch: {repr choose.ops}"
  let svm ←
    match ProofForge.Svm.Emit.emitCounterAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  let evmProgram ←
    match ProofForge.Evm.IR.fromProgram program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.Emit.emitYul evmProgram with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless svm.contains "then_select_" && svm.contains "load local 0" do
    throwError "SVM conditional-local lowering is missing"
  unless evm.contains "let v0 := 0" && evm.contains "v0 := arg0" &&
      evm.contains "v0 := arg1" && evm.contains "l0 := v0" do
    throwError "EVM conditional-local lowering is missing"

#pf_guard_conditional_local

elab "#pf_guard_except_bind_join" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initChoice
        ``Tests.Fixtures.bindChoice ``Tests.Fixtures.getChosen with
    | .ok p => pure p
    | .error reason => throwError reason
  let some bindChoice := program.methods.find? (·.ixName == "bindChoice")
    | throwError "missing bind-join method"
  let expected : Array ProofForge.Ops.Op := #[
    .joinLocal 0,
    .ite .lt (.arg 0) (.arg 2)
      #[.setLocal 0 (.arg 0)]
      #[.ite .lt (.arg 1) (.arg 2)
          #[.setLocal 0 (.arg 1)]
          #[.errorOverflow]],
    .checkedAddU64 (.local 0) (.arg 3),
    .okState (.addU64 (.local 0) (.arg 3)),
    .errorOverflow
  ]
  unless bindChoice.ops == expected do
    throwError s!"Except.bind join IR mismatch: {repr bindChoice.ops}"
  let svm ←
    match ProofForge.Svm.Emit.emitCounterAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  let evmProgram ←
    match ProofForge.Evm.IR.fromProgram program with
    | .ok lowered => pure lowered
    | .error reason => throwError reason
  let evm ←
    match ProofForge.Evm.Emit.emitYul evmProgram with
    | .ok yul => pure yul
    | .error reason => throwError reason
  unless svm.contains "; declare join local 0" &&
      svm.contains "; set join local 0" && svm.contains "; load local 0" do
    throwError "SVM Except.bind join lowering is missing"
  unless svm.contains "cfg_bindChoice_block_" &&
      svm.contains "ja cfg_bindChoice_block_" && !svm.contains "@@CFG_EDGE_" do
    throwError "SVM successful Except.bind branch falls through into its else branch"
  unless evm.contains "let l0 := 0" && evm.contains "l0 := arg0" &&
      evm.contains "l0 := arg1" &&
      evm.contains "gt(l0, sub(0xffffffffffffffff, arg3))" do
    throwError "EVM Except.bind join lowering is missing"

#pf_guard_except_bind_join

elab "#pf_guard_compound_error_guard" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgram env ``Tests.Fixtures.initChoice
        ``Tests.Fixtures.compoundChoice ``Tests.Fixtures.getChosen with
    | .ok p => pure p
    | .error reason => throwError reason
  let some compound := program.methods.find? (·.ixName == "compoundChoice")
    | throwError "missing compound-guard method"
  let rec comparisonLeaves (fuel : Nat) (value : ProofForge.Ops.Val) : Nat :=
    match fuel with
    | 0 => 0
    | fuel' + 1 =>
      match value with
      | .bitAnd lhs rhs => comparisonLeaves fuel' lhs + comparisonLeaves fuel' rhs
      | .select _ _ _ _ _ => 1
      | _ => 0
  match compound.ops with
  | #[.ite .ne condition (.lit 0)
        #[.storeField "chosen" (.arg 0), .okState (.arg 0)] #[.errorOverflow]] =>
      unless comparisonLeaves 8 condition == 4 do
        throwError s!"compound guard lost comparisons: {repr compound.ops}"
  | #[.ite .eq condition (.lit 1)
        #[.storeField "chosen" (.arg 0), .okState (.arg 0)] #[.errorOverflow]] =>
      unless comparisonLeaves 8 condition == 4 do
        throwError s!"compound guard lost comparisons: {repr compound.ops}"
  | _ => throwError s!"compound error-guard IR mismatch: {repr compound.ops}"

#pf_guard_compound_error_guard

elab "#pf_guard_multi_seed_invoke_sequence" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Examples.Counter.init
        ``Tests.Fixtures.multiSeedTransfer ``Examples.Counter.get with
    | .ok p => pure p
    | .error reason => throwError reason
  let lowered ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok p => pure p
    | .error reason => throwError reason
  let some transfer := lowered.methods.find? (·.ixName == "multiSeedTransfer")
    | throwError "missing multi-seed transfer method"
  let expectedSeeds : Array ProofForge.Svm.Ops.PdaSeed :=
    #[.ascii "vault", .stateKey, .accKey 3]
  match transfer.ops with
  | #[.invoke 8 firstMetas
          #[.u8le (.lit 12), .u64le (.arg 0), .u8le (.lit 6)] #[] none,
      .invoke 8 secondMetas
          #[.u8le (.lit 12), .u64le (.arg 0), .u8le (.lit 6)] seeds
          (some (.ext (.findPdaSeeds bumpSeeds) #[])),
      .storeField "value" (.arg 0), .okState (.arg 0)] =>
        let expectedFirst : Array ProofForge.Svm.Ops.CpiMeta :=
          #[{ acc := 1, signer := false, writable := true },
            { acc := 3, signer := false, writable := false },
            { acc := 5, signer := false, writable := true },
            { acc := 0, signer := true, writable := false }]
        let expectedSecond : Array ProofForge.Svm.Ops.CpiMeta :=
          #[{ acc := 5, signer := false, writable := true },
            { acc := 3, signer := false, writable := false },
            { acc := 1, signer := false, writable := true },
            { acc := 7, signer := true, writable := false }]
        unless firstMetas == expectedFirst && secondMetas == expectedSecond &&
            seeds == expectedSeeds && bumpSeeds == expectedSeeds do
          throwError s!"multi-seed list mismatch: {repr transfer.ops}"
  | _ => throwError s!"multi-invoke sequence IR mismatch: {repr transfer.ops}"
  unless ProofForge.Svm.IR.cpiAccountCount lowered == 10 do
    throwError s!"multi-seed account scan stopped at {ProofForge.Svm.IR.cpiAccountCount lowered}"
  let asm ←
    match ProofForge.Svm.Emit.emitProgramAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  unless asm.contains "; findPdaSeeds count=3" &&
      (asm.splitOn "; invoke programIx=9").length == 3 do
    throwError "multi-seed discovery or consecutive CPI emission is missing"

#pf_guard_multi_seed_invoke_sequence

elab "#pf_guard_single_invoke_continuation" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Examples.Counter.init
        ``Tests.Fixtures.singleInvokeTransfer ``Examples.Counter.get with
    | .ok p => pure p
    | .error reason => throwError reason
  let lowered ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok p => pure p
    | .error reason => throwError reason
  let some transfer := lowered.methods.find? (·.ixName == "singleInvokeTransfer")
    | throwError "missing single invoke transfer method"
  match transfer.ops with
  | #[.invoke 8 _ _ #[] none, .storeField "value" (.arg 0), .okState (.arg 0)] => pure ()
  | _ => throwError s!"single invoke continuation IR mismatch: {repr transfer.ops}"

#pf_guard_single_invoke_continuation

elab "#pf_guard_indexed_transfer_result" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Examples.Counter.init
        ``Tests.Fixtures.indexedTransferResult ``Examples.Counter.get with
    | .ok p => pure p
    | .error reason => throwError reason
  let lowered ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok p => pure p
    | .error reason => throwError reason
  let some transfer := lowered.methods.find? (·.ixName == "indexedTransferResult")
    | throwError "missing indexed transfer-result method"
  match transfer.ops with
  | #[.invoke 8 _
        #[.u8le (.lit 12), .u64le (.arg 0), .u8le (.lit 6)] #[] none,
      .returnU64 (.arg 0)] => pure ()
  | _ => throwError s!"indexed TransferChecked result mismatch: {repr transfer.ops}"

#pf_guard_indexed_transfer_result

elab "#pf_guard_single_multi_seed_invoke_continuation" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Examples.Counter.init
        ``Tests.Fixtures.singleMultiSeedTransfer ``Examples.Counter.get with
    | .ok p => pure p
    | .error reason => throwError reason
  let lowered ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok p => pure p
    | .error reason => throwError reason
  let some transfer := lowered.methods.find? (·.ixName == "singleMultiSeedTransfer")
    | throwError "missing single multi-seed transfer method"
  let expectedSeeds : Array ProofForge.Svm.Ops.PdaSeed :=
    #[.ascii "vault", .stateKey, .accKey 3]
  match transfer.ops with
  | #[.invoke 8 _ _ seeds (some (.ext (.findPdaSeeds bumpSeeds) #[])),
      .storeField "value" (.arg 0), .okState (.arg 0)] =>
        unless seeds == expectedSeeds && bumpSeeds == expectedSeeds do
          throwError s!"single multi-seed list mismatch: {repr transfer.ops}"
  | _ =>
      throwError s!"single multi-seed continuation IR mismatch: {repr transfer.ops}"

#pf_guard_single_multi_seed_invoke_continuation

elab "#pf_guard_dynamic_cpi_word_widths" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Examples.Counter.init
        ``Tests.Fixtures.dynamicCpiWords ``Examples.Counter.get with
    | .ok p => pure p
    | .error reason => throwError reason
  let lowered ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok p => pure p
    | .error reason => throwError reason
  let some method := lowered.methods.find? (·.ixName == "dynamicCpiWords")
    | throwError "missing dynamic CPI word method"
  match method.ops with
  | #[.invoke 1 #[]
        #[.u8le (.arg 0), .u16le (.arg 0), .u32le (.arg 0), .u64le (.arg 0)] #[] none,
      .storeField "value" (.arg 0), .okState (.arg 0)] => pure ()
  | _ => throwError s!"dynamic CPI word IR mismatch: {repr method.ops}"
  let asm ←
    match ProofForge.Svm.Emit.emitProgramAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  unless asm.contains "; invoke programIx=2 metas=0 dataLen=15" &&
      asm.contains "stxb [r9 + 40], r1" && asm.contains "stxh [r9 + 41], r1" &&
      asm.contains "stxw [r9 + 43], r1" && asm.contains "stxdw [r9 + 47], r1" do
    throwError "dynamic CPI words lost their packed little-endian widths"

#pf_guard_dynamic_cpi_word_widths

elab "#pf_guard_multi_seed_pda_account_check" : command => do
  let env ← getEnv
  let program ←
    match ProofForge.Extract.extractProgramIR env ``Examples.Counter.init
        ``Examples.Counter.increment ``Tests.Fixtures.checkMultiSeedPda with
    | .ok p => pure p
    | .error reason => throwError reason
  let lowered ←
    match ProofForge.Svm.IR.fromExtracted program with
    | .ok p => pure p
    | .error reason => throwError reason
  let some check := lowered.methods.find? (·.ixName == "checkMultiSeedPda")
    | throwError "missing multi-seed PDA check method"
  let seeds : Array ProofForge.Svm.Ops.PdaSeed :=
    #[.ascii "vault", .stateKey, .accKey 3]
  unless check.ops == #[.returnU64 (.ext (.checkPdaSeeds 5 seeds) #[])] do
    throwError s!"multi-seed PDA check IR mismatch: {repr check.ops}"
  unless ProofForge.Svm.IR.cpiAccountCount lowered == 7 do
    throwError s!"multi-seed PDA check account scan stopped at " ++
      s!"{ProofForge.Svm.IR.cpiAccountCount lowered}"
  let asm ←
    match ProofForge.Svm.Emit.emitProgramAsm program with
    | .ok asm => pure asm
    | .error reason => throwError reason
  unless asm.contains "; checkPdaSeeds account=5 count=3" do
    throwError "multi-seed full-key PDA check emission is missing"

#pf_guard_multi_seed_pda_account_check

#pf_extract Examples.Counter.init Examples.Counter.increment Examples.Counter.nonzero

#pf_extract Examples.Flag.init Examples.Flag.setFlag Examples.Flag.getFlag

#pf_extract Examples.Maybe.init Examples.Maybe.setSome Examples.Maybe.isSome

#pf_extract Examples.Maybe.init Examples.Maybe.setSome Examples.Maybe.getValue

#pf_extract Examples.Window.init Examples.Window.setTail Examples.Window.getHead

#pf_extract Examples.Phase.init Examples.Phase.setLive Examples.Phase.isLive

#pf_extract Examples.Choice.init Examples.Choice.setHold Examples.Choice.getHeld

#pf_extract Examples.Clock.init Examples.Clock.stamp Examples.Clock.height

#pf_extract Examples.Clock.init Examples.Clock.stamp Examples.Clock.era

#pf_extract Examples.Clock.init Examples.Clock.stamp Examples.Clock.key0

#pf_extract Examples.Transfer.init Examples.Transfer.transfer Examples.Transfer.get

#pf_extract Examples.Ping.init Examples.Ping.ping Examples.Ping.get

#pf_extract Examples.Call.init Examples.Call.call Examples.Call.get

#pf_extract Examples.Info.init Examples.Info.touch Examples.Info.lamports

#pf_extract Examples.Peer.init Examples.Peer.touch Examples.Peer.lamports1

#pf_extract Examples.Pda.init Examples.Pda.touch Examples.Pda.bump

#pf_extract Examples.Pda.init Examples.Pda.touch Examples.Pda.check

#pf_extract Examples.Pda.init Examples.Pda.touch Examples.Pda.checkBad

#pf_extract Examples.Signed.init Examples.Signed.signed Examples.Signed.get

#pf_extract Examples.Create.init Examples.Create.create Examples.Create.get

#pf_extract Examples.TokenXfer.init Examples.TokenXfer.send Examples.TokenXfer.get

#pf_extract Examples.Token2022.init Examples.Token2022.send Examples.Token2022.get

#pf_extract Examples.Ata.init Examples.Ata.openAta Examples.Ata.get

#pf_extract Examples.Rent.init Examples.Rent.stamp Examples.Rent.exempt

#pf_extract Examples.TokenMint.init Examples.TokenMint.mintTo Examples.TokenMint.get

#pf_extract Examples.SysAlloc.init Examples.SysAlloc.alloc Examples.SysAlloc.get

#pf_extract Examples.SysAlloc.init Examples.SysAlloc.assign Examples.SysAlloc.get

#pf_extract Examples.TokenAcc.init Examples.TokenAcc.openAcc Examples.TokenAcc.get

#pf_extract Examples.TokenAcc.init Examples.TokenAcc.closeAcc Examples.TokenAcc.get

#pf_extract Examples.Memo.init Examples.Memo.write Examples.Memo.get

#pf_extract Examples.CreatePda.init Examples.CreatePda.openPda Examples.CreatePda.get

#pf_extract Examples.CreatePda.init Examples.CreatePda.openBad Examples.CreatePda.get

#pf_extract Examples.TokenApprove.init Examples.TokenApprove.approve Examples.TokenApprove.get

#pf_extract Examples.TokenFreeze.init Examples.TokenFreeze.freeze Examples.TokenFreeze.get

#pf_extract Examples.TokenFreeze.init Examples.TokenFreeze.thaw Examples.TokenFreeze.get

#pf_extract Examples.TokenAuth.init Examples.TokenAuth.setAuth Examples.TokenAuth.get

#pf_extract Examples.TokenAuth.init Examples.TokenAuth.revoke Examples.TokenAuth.get

#pf_extract Examples.Epoch.init Examples.Epoch.stamp Examples.Epoch.span

#pf_extract Examples.TokenSize.init Examples.TokenSize.size Examples.TokenSize.get

#pf_extract Examples.SysSeed.init Examples.SysSeed.openSeed Examples.SysSeed.get

#pf_extract Examples.SysSeed.init Examples.SysSeed.createSeed Examples.SysSeed.get

#pf_extract Examples.SysSeed.init Examples.SysSeed.assignSeed Examples.SysSeed.get

#pf_extract Examples.SysXfer.init Examples.SysXfer.sendSeed Examples.SysXfer.get

#pf_extract Examples.TokenMint2.init Examples.TokenMint2.openMint Examples.TokenMint2.get

#pf_extract Examples.TokenNative.init Examples.TokenNative.syncNative Examples.TokenNative.get

#pf_extract Examples.Hash.init Examples.Hash.touch Examples.Hash.vault

#pf_extract Examples.Hash.init Examples.Hash.touch Examples.Hash.ok

#pf_extract Examples.Hash.init Examples.Hash.touch Examples.Hash.empty

#pf_extract Examples.Keys.init Examples.Keys.touch Examples.Keys.key00

#pf_extract Examples.Keys.init Examples.Keys.touch Examples.Keys.key10

#pf_extract Examples.Keccak.init Examples.Keccak.touch Examples.Keccak.vault

#pf_extract Examples.Keccak.init Examples.Keccak.touch Examples.Keccak.empty

#pf_extract Examples.Trio.init Examples.Trio.touch Examples.Trio.lamports2

#pf_extract Examples.Trio.init Examples.Trio.touch Examples.Trio.needSig1

#pf_extract Examples.Trio.init Examples.Trio.touch Examples.Trio.self2

#pf_extract Examples.Gate.init Examples.Gate.openGate Examples.Gate.now

#pf_extract Examples.Nonce.init Examples.Nonce.advance Examples.Nonce.get

#pf_extract Examples.TokenOwner.init Examples.TokenOwner.setOwner Examples.TokenOwner.get

#pf_extract Examples.TokenMs.init Examples.TokenMs.openMs Examples.TokenMs.get

/--
error: extract/unsupported: svm rejects evm leaf
-/
#guard_msgs (error) in
#pf_extract Examples.TipJar.init Examples.TipJar.deposit Examples.TipJar.get

#pf_extract Tests.Fixtures.initTagged Tests.Fixtures.setTagged Tests.Fixtures.getTagged

#pf_extract Tests.Fixtures.initEvent Tests.Fixtures.setEventCancel Tests.Fixtures.getEvent

#pf_extract Tests.Fixtures.initMarketEvent Tests.Fixtures.setMarketFee Tests.Fixtures.marketEventValue

#pf_extract Tests.Fixtures.initMarketEventBatch Tests.Fixtures.setMarketEventAt
  Tests.Fixtures.firstMarketEventValue

/--
error: extract/unsupported: field items Array is not fixed-length; use Vector
-/
#guard_msgs (error) in
#pf_extract Tests.Fixtures.initBag Tests.Fixtures.setBagHead Tests.Fixtures.getBagHead

/--
error: extract/unsupported: mutating method missing checked arith
-/
#guard_msgs (error) in
#pf_extract Examples.Counter.init Tests.Fixtures.wrappingMul Examples.Counter.get
