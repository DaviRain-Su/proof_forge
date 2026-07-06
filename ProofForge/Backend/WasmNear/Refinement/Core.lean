import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Types
import ProofForge.IR.Semantics
import ProofForge.IR.Examples.Counter
import ProofForge.Compiler.Wasm.AST
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Examples.ValueVaultInvariant

namespace ProofForge.Backend.WasmNear.Refinement

open ProofForge.IR

/-! Refinement scaffolding for the IR -> EmitWat/NEAR Wasm path.

This does not claim a full Wasm instruction semantics yet. It fixes the
observable boundary that later proofs should refine against: a sequence of
exported entrypoint calls and their returned values. The current theorems prove
that the scalar IR semantics produces the expected observable Counter trace and
that EmitWat exposes the entrypoint names used by that trace.
-/

inductive ObservableReturn where
  | none
  | bool (value : Bool)
  | u32 (value : Nat)
  | u64 (value : Nat)
  | hash (a b c d : Nat)
  deriving Repr, BEq, DecidableEq

structure ObservableStep where
  exportName : String
  returnValue : ObservableReturn
  deriving Repr, BEq, DecidableEq

structure TraceObligation where
  name : String
  module : Module
  entrypoints : Array Entrypoint
  expected : Array ObservableStep
  deriving Repr

def observableReturn (expectedType : ValueType) (value? : Option ProofForge.IR.Semantics.Value) :
    Except String ObservableReturn :=
  match expectedType, value? with
  | .unit, none => .ok .none
  | .unit, some .unit => .ok .none
  | .bool, some (.bool value) => .ok (.bool value)
  | .u32, some (.u32 value) => .ok (.u32 value)
  | .u64, some (.u64 value) => .ok (.u64 value)
  | .hash, some (.hash a b c d) => .ok (.hash a b c d)
  | _, none => .error s!"entrypoint expected `{expectedType.name}` but returned no value"
  | _, some _ => .error s!"entrypoint returned a value that does not match `{expectedType.name}`"

def runEntrypointObservable (state : ProofForge.IR.Semantics.State) (entrypoint : Entrypoint) :
    Except String (ProofForge.IR.Semantics.State × ObservableStep) := do
  let (nextState, result?) ← ProofForge.IR.Semantics.runEntrypoint state entrypoint
  let returnValue ← observableReturn entrypoint.returns result?
  .ok (nextState, { exportName := entrypoint.name, returnValue := returnValue })

def runTraceList : List Entrypoint → ProofForge.IR.Semantics.State →
    Except String (ProofForge.IR.Semantics.State × Array ObservableStep)
  | [], state => .ok (state, #[])
  | entrypoint :: rest, state => do
      let (nextState, step) ← runEntrypointObservable state entrypoint
      let (finalState, steps) ← runTraceList rest nextState
      .ok (finalState, #[step] ++ steps)

def runTrace (entrypoints : Array Entrypoint) : Except String (Array ObservableStep) := do
  let (_, steps) ← runTraceList entrypoints.toList ProofForge.IR.Semantics.State.empty
  .ok steps

def TraceObligation.irTraceOk (obligation : TraceObligation) : Bool :=
  match runTrace obligation.entrypoints with
  | .ok actual => actual == obligation.expected
  | .error _ => false

def hasWatExport (wat exportName : String) : Bool :=
  wat.contains s!"(export \"{exportName}\""

def TraceObligation.emitWatExportsOk (obligation : TraceObligation) : Bool :=
  match ProofForge.Backend.WasmNear.EmitWat.renderModule obligation.module with
  | .ok wat => obligation.entrypoints.all (fun entrypoint => hasWatExport wat entrypoint.name)
  | .error _ => false

/-! Artifact-surface obligations.

The first NEAR/Wasm refinement obligation only checked WAT export names.  The
next step toward artifact execution is to inspect the actual Wasm AST produced
by EmitWat and pin the host-boundary calls that the offline host will execute:
entrypoint prologues, storage helper calls, return helper calls, memory export,
and the storage-key data segment.  This is still not a full Wasm semantics, but
it is stronger than a text export check and gives later executable Wasm
obligations a stable AST boundary to refine.
-/

abbrev WasmModule := ProofForge.Compiler.Wasm.Module
abbrev WasmFunc := ProofForge.Compiler.Wasm.Func
abbrev WasmBlock := ProofForge.Compiler.Wasm.Block
abbrev WasmInsn := ProofForge.Compiler.Wasm.Insn

def stringArrayContains (values : Array String) (expected : String) : Bool :=
  values.any (fun value => value == expected)

def callsContainInOrderList : List String → List String → Bool
  | _, [] => true
  | [], _ :: _ => false
  | call :: restCalls, expected :: restExpected =>
      if call == expected then
        callsContainInOrderList restCalls restExpected
      else
        callsContainInOrderList restCalls (expected :: restExpected)

def callsContainInOrder (calls expected : Array String) : Bool :=
  callsContainInOrderList calls.toList expected.toList

mutual
partial def wasmInsnCalls : WasmInsn → Array String
  | .call name => #[name]
  | .block_ body => wasmBlockCalls body
  | .loop_ body => wasmBlockCalls body
  | .if_ thenBody elseBody => wasmBlockCalls thenBody ++ wasmBlockCalls elseBody
  | _ => #[]

partial def wasmBlockCalls (block : WasmBlock) : Array String :=
  block.insns.foldl (fun calls insn => calls ++ wasmInsnCalls insn) #[]
end

def WasmFunc.calls (func : WasmFunc) : Array String :=
  wasmBlockCalls func.body

def findFunc? (mod : WasmModule) (name : String) : Option WasmFunc :=
  mod.funcs.find? (fun func => func.name == name)

def findExportedFunc? (mod : WasmModule) (exportName : String) : Option WasmFunc :=
  mod.funcs.find? (fun func => func.exportName == some exportName)

def importedFunctionNames (mod : WasmModule) : Array String :=
  mod.imports.map (fun import_ => import_.name)

def funcTypeMatches (type : ProofForge.Compiler.Wasm.FuncType)
    (params results : Array ProofForge.Compiler.Wasm.ValType) : Bool :=
  type.params == params && type.results == results

def findImport? (mod : WasmModule) (moduleName functionName : String) :
    Option ProofForge.Compiler.Wasm.Import :=
  mod.imports.find? (fun import_ =>
    import_.module_ == moduleName && import_.name == functionName)

def hasDataSegment (mod : WasmModule) (offset : Nat) (bytes : String) : Bool :=
  mod.dataSegments.any (fun segment => segment.offset == offset && segment.bytes == bytes)

def memoryDeclarationMatches
    (mod : WasmModule)
    (exportName : String)
    (min : Nat)
    (max : Option Nat) : Bool :=
  match mod.memory with
  | some memory =>
      memory.exportName == some exportName &&
        memory.min == min &&
        memory.max == max
  | none => false

structure WasmCallExpectation where
  functionName : String
  expectedCalls : Array String

structure WasmMemoryRegionExpectation where
  name : String
  offset : Nat
  byteLength : Nat
  deriving Repr, BEq

def WasmMemoryRegionExpectation.endExclusive
    (region : WasmMemoryRegionExpectation) : Nat :=
  region.offset + region.byteLength

def WasmMemoryRegionExpectation.fitsIn
    (region : WasmMemoryRegionExpectation)
    (pageBytes : Nat) : Bool :=
  region.byteLength > 0 && region.endExclusive <= pageBytes

def wasmMemoryRegionsDoNotOverlap
    (lhs rhs : WasmMemoryRegionExpectation) : Bool :=
  lhs.endExclusive <= rhs.offset || rhs.endExclusive <= lhs.offset

def wasmMemoryRegionsDisjointFrom
    (region : WasmMemoryRegionExpectation) :
    List WasmMemoryRegionExpectation → Bool
  | [] => true
  | other :: rest =>
      wasmMemoryRegionsDoNotOverlap region other &&
        wasmMemoryRegionsDisjointFrom region rest

def wasmMemoryRegionsPairwiseDisjointList :
    List WasmMemoryRegionExpectation → Bool
  | [] => true
  | region :: rest =>
      wasmMemoryRegionsDisjointFrom region rest &&
        wasmMemoryRegionsPairwiseDisjointList rest

def wasmMemoryRegionsFitInPage
    (regions : Array WasmMemoryRegionExpectation)
    (pageBytes : Nat) : Bool :=
  regions.all (fun region => region.fitsIn pageBytes)

def wasmMemoryRegionsPairwiseDisjoint
    (regions : Array WasmMemoryRegionExpectation) : Bool :=
  wasmMemoryRegionsPairwiseDisjointList regions.toList

def wasmMemoryLayoutOk
    (regions : Array WasmMemoryRegionExpectation)
    (pageBytes : Nat := 65536) : Bool :=
  wasmMemoryRegionsFitInPage regions pageBytes &&
    wasmMemoryRegionsPairwiseDisjoint regions

inductive WasmTraceOp where
  | drop
  | const (type : ProofForge.Compiler.Wasm.ValType) (value : String)
  | localGet (name : String)
  | localSet (name : String)
  | globalGet (name : String)
  | globalSet (name : String)
  | plain (name : String)
  | load (name : String) (offset : Nat)
  | store (name : String) (offset : Nat)
  | call (name : String)
  deriving Repr, BEq, DecidableEq

def WasmTraceOp.i32Const (value : Nat) : WasmTraceOp :=
  .const .i32 (toString value)

def WasmTraceOp.i64Const (value : Nat) : WasmTraceOp :=
  .const .i64 (toString value)

mutual
partial def wasmInsnTraceOps : WasmInsn → Array WasmTraceOp
  | .drop => #[.drop]
  | .const type value => #[.const type value]
  | .localGet name => #[.localGet name]
  | .localSet name => #[.localSet name]
  | .globalGet name => #[.globalGet name]
  | .globalSet name => #[.globalSet name]
  | .plain name => #[.plain name]
  | .load name offset => #[.load name offset]
  | .store name offset => #[.store name offset]
  | .call name => #[.call name]
  | .block_ body => wasmBlockTraceOps body
  | .loop_ body => wasmBlockTraceOps body
  | .if_ thenBody elseBody => wasmBlockTraceOps thenBody ++ wasmBlockTraceOps elseBody
  | _ => #[]

partial def wasmBlockTraceOps (block : WasmBlock) : Array WasmTraceOp :=
  block.insns.foldl (fun ops insn => ops ++ wasmInsnTraceOps insn) #[]
end

def WasmFunc.traceOps (func : WasmFunc) : Array WasmTraceOp :=
  wasmBlockTraceOps func.body

def traceOpsStartsWithList : List WasmTraceOp → List WasmTraceOp → Bool
  | _, [] => true
  | [], _ :: _ => false
  | actual :: actualRest, expected :: expectedRest =>
      actual == expected && traceOpsStartsWithList actualRest expectedRest

def traceOpsContainContiguousList : List WasmTraceOp → List WasmTraceOp → Bool
  | _, [] => true
  | [], _ :: _ => false
  | actual@(_ :: rest), expected =>
      traceOpsStartsWithList actual expected ||
        traceOpsContainContiguousList rest expected

def traceOpsContainContiguous (actual expected : Array WasmTraceOp) : Bool :=
  traceOpsContainContiguousList actual.toList expected.toList

structure WasmHostFrameExpectation where
  functionName : String
  expectedOps : Array WasmTraceOp

structure WasmImportExpectation where
  moduleName : String := "env"
  functionName : String
  params : Array ProofForge.Compiler.Wasm.ValType := #[]
  results : Array ProofForge.Compiler.Wasm.ValType := #[]

structure WasmExportExpectation where
  exportName : String
  expectedCalls : Array String

structure ArtifactSurfaceObligation where
  name : String
  module : Module
  requiredImports : Array String := #[]
  requiredImportSignatures : Array WasmImportExpectation := #[]
  requiredExports : Array WasmExportExpectation := #[]
  requiredFunctions : Array WasmCallExpectation := #[]
  requiredHostFrames : Array WasmHostFrameExpectation := #[]
  requiredDataSegments : Array (Nat × String) := #[]
  requiredMemoryExport : String := "memory"
  requiredMemoryMin : Nat := 1
  requiredMemoryMax : Option Nat := none
  requiredMemoryRegions : Array WasmMemoryRegionExpectation := #[]

def WasmExportExpectation.ok (mod : WasmModule) (expectation : WasmExportExpectation) :
    Bool :=
  match findExportedFunc? mod expectation.exportName with
  | some func => callsContainInOrder func.calls expectation.expectedCalls
  | none => false

def WasmCallExpectation.ok (mod : WasmModule) (expectation : WasmCallExpectation) :
    Bool :=
  match findFunc? mod expectation.functionName with
  | some func => callsContainInOrder func.calls expectation.expectedCalls
  | none => false

def WasmImportExpectation.ok (mod : WasmModule) (expectation : WasmImportExpectation) :
    Bool :=
  match findImport? mod expectation.moduleName expectation.functionName with
  | some import_ => funcTypeMatches import_.type expectation.params expectation.results
  | none => false

def WasmHostFrameExpectation.ok (mod : WasmModule)
    (expectation : WasmHostFrameExpectation) : Bool :=
  match findFunc? mod expectation.functionName with
  | some func => traceOpsContainContiguous func.traceOps expectation.expectedOps
  | none => false

def ArtifactSurfaceObligation.hostImportSignaturesOk
    (obligation : ArtifactSurfaceObligation) : Bool :=
  match ProofForge.Backend.WasmNear.EmitWat.lowerModule obligation.module with
  | .ok wasm =>
      obligation.requiredImportSignatures.all
        (fun expectation => expectation.ok wasm)
  | .error _ => false

def ArtifactSurfaceObligation.hostFramesOk
    (obligation : ArtifactSurfaceObligation) : Bool :=
  match ProofForge.Backend.WasmNear.EmitWat.lowerModule obligation.module with
  | .ok wasm =>
      obligation.requiredHostFrames.all
        (fun expectation => expectation.ok wasm)
  | .error _ => false

def ArtifactSurfaceObligation.memorySurfaceOk
    (obligation : ArtifactSurfaceObligation) : Bool :=
  match ProofForge.Backend.WasmNear.EmitWat.lowerModule obligation.module with
  | .ok wasm =>
      memoryDeclarationMatches wasm
        obligation.requiredMemoryExport
        obligation.requiredMemoryMin
        obligation.requiredMemoryMax &&
      wasmMemoryLayoutOk obligation.requiredMemoryRegions
  | .error _ => false

def ArtifactSurfaceObligation.ok (obligation : ArtifactSurfaceObligation) : Bool :=
  match ProofForge.Backend.WasmNear.EmitWat.lowerModule obligation.module with
  | .ok wasm =>
      let imports := importedFunctionNames wasm
      obligation.requiredImports.all (stringArrayContains imports) &&
      obligation.requiredImportSignatures.all (fun expectation => expectation.ok wasm) &&
      obligation.requiredExports.all (fun expectation => expectation.ok wasm) &&
      obligation.requiredFunctions.all (fun expectation => expectation.ok wasm) &&
      obligation.requiredHostFrames.all (fun expectation => expectation.ok wasm) &&
      obligation.requiredDataSegments.all (fun segment => hasDataSegment wasm segment.fst segment.snd) &&
      memoryDeclarationMatches wasm
        obligation.requiredMemoryExport
        obligation.requiredMemoryMin
        obligation.requiredMemoryMax &&
      wasmMemoryLayoutOk obligation.requiredMemoryRegions
  | .error _ => false

/-! Offline-host execution-surface obligations.

The Rust offline host remains an external differential-testing boundary, not
part of the trusted Lean kernel.  This obligation pins the deterministic IO
surface that host execution must expose for a generated EmitWat artifact: the
Borsh/little-endian input bytes passed to each exported entrypoint and the
return fragment that the host prints after executing it.
-/

def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat ('0'.toNat + value) else Char.ofNat ('a'.toNat + (value - 10))

def byteHex (value : Nat) : String :=
  String.ofList [hexDigit (value / 16 % 16), hexDigit (value % 16)]

def stringHex (value : String) : String :=
  String.intercalate "" <| value.toList.map (fun char => byteHex char.toNat)

def littleEndianHex (byteCount value : Nat) : String :=
  String.intercalate "" <|
    (List.range byteCount).map fun idx => byteHex ((value / (256 ^ idx)) % 256)

partial def borshValueHex : ProofForge.IR.Semantics.Value → Except String String
  | .unit => .ok ""
  | .bool value => .ok (if value then "01" else "00")
  | .u32 value => .ok (littleEndianHex 4 value)
  | .u64 value => .ok (littleEndianHex 8 value)
  | .hash a b c d =>
      .ok (littleEndianHex 8 a ++ littleEndianHex 8 b ++ littleEndianHex 8 c ++ littleEndianHex 8 d)
  | .array values => do
      let parts ← values.mapM borshValueHex
      .ok (String.intercalate "" parts)
  | .struct _ fields => do
      let parts ← fields.mapM fun (_, v) => borshValueHex v
      .ok (String.intercalate "" parts)
  | .address value => .ok (littleEndianHex 8 value)
  | .u8 value => .ok (littleEndianHex 1 value)
  | .u128 _ => .error "offline-host execution obligation does not yet encode u128 Borsh input values"
  | .bytes _ => .error "offline-host execution obligation does not yet encode bytes Borsh input values"
  | .string _ => .error "offline-host execution obligation does not yet encode string Borsh input values"

def borshArgsHex (args : Array ProofForge.IR.Semantics.Value) : Except String String := do
  let parts ← args.mapM borshValueHex
  .ok (String.intercalate "" parts.toList)

def observableReturnHex : ObservableReturn → String
  | .none => ""
  | .bool value => if value then "01" else "00"
  | .u32 value => littleEndianHex 4 value
  | .u64 value => littleEndianHex 8 value
  | .hash a b c d =>
      littleEndianHex 8 a ++ littleEndianHex 8 b ++ littleEndianHex 8 c ++ littleEndianHex 8 d

def offlineHostReturnFragment : ObservableReturn → String
  | .none => "return=<none>"
  | .bool value => s!"return_hex={observableReturnHex (.bool value)} return_bool={value}"
  | .u32 value => s!"return_hex={observableReturnHex (.u32 value)} return_u32={value}"
  | .u64 value => s!"return_hex={observableReturnHex (.u64 value)} return_u64={value}"
  | .hash a b c d =>
      s!"return_hex={observableReturnHex (.hash a b c d)} return_len=32"

structure OfflineHostExecutionStep where
  exportName : String
  args : Array ProofForge.IR.Semantics.Value := #[]
  deriving Repr, BEq

structure OfflineHostIOExpectation where
  exportName : String
  inputHex : String
  returnLineFragment : String
  returnPayloadHex : String := ""
  storageKeys : Nat := 0
  storageSnapshot : Array (String × ProofForge.IR.Semantics.Value) := #[]
  storageHexSnapshot : Array (String × String) := #[]
  logCount : Nat := 0
  logLineFragments : Array String := #[]
  logPayloadHexFragments : Array String := #[]
  deriving Repr, BEq

structure OfflineHostExecutionTraceResult where
  finalState : ProofForge.IR.Semantics.State
  io : Array OfflineHostIOExpectation
  deriving Repr, BEq

structure OfflineHostExecutionObligation where
  name : String
  artifactSurface : ArtifactSurfaceObligation
  steps : Array OfflineHostExecutionStep
  expectedIO : Array OfflineHostIOExpectation

def findEntrypoint? (mod : Module) (name : String) : Option Entrypoint :=
  mod.entrypoints.find? (fun entrypoint => entrypoint.name == name)

def arrayDrop {α : Type} (values : Array α) (n : Nat) : Array α :=
  values.toList.drop n |>.toArray

def valueVaultEventLogPayload
    (log : ProofForge.IR.Semantics.EventLog) :
    Except String String := do
  if !log.indexed.isEmpty then
    .error s!"offline-host log obligation does not yet encode indexed event `{log.name}`"
  else
    match log.name, log.data.toList with
    | "VaultInitialized", [.u64 initial, .u64 checkpoint] =>
        .ok ("{\"event\":\"VaultInitialized\",\"initial\":" ++
          toString initial ++ ",\"checkpoint\":" ++ toString checkpoint ++ "}")
    | "ValueDeposited", [.u64 amount, .u64 balance, .u64 operations] =>
        .ok ("{\"event\":\"ValueDeposited\",\"amount\":" ++
          toString amount ++ ",\"balance\":" ++ toString balance ++
          ",\"operations\":" ++ toString operations ++ "}")
    | "ValueCharged", [.u64 gross, .u64 fee, .u64 net, .u64 balance] =>
        .ok ("{\"event\":\"ValueCharged\",\"gross\":" ++
          toString gross ++ ",\"fee\":" ++ toString fee ++
          ",\"net\":" ++ toString net ++ ",\"balance\":" ++
          toString balance ++ "}")
    | "ValueReleased", [.u64 amount, .u64 balance, .u64 released] =>
        .ok ("{\"event\":\"ValueReleased\",\"amount\":" ++
          toString amount ++ ",\"balance\":" ++ toString balance ++
          ",\"released\":" ++ toString released ++ "}")
    | "ValueSnapshot", [.u64 balance, .u64 released, .u64 fees, .u64 checkpoint] =>
        .ok ("{\"event\":\"ValueSnapshot\",\"balance\":" ++
          toString balance ++ ",\"released\":" ++ toString released ++
          ",\"fees\":" ++ toString fees ++ ",\"checkpoint\":" ++
          toString checkpoint ++ "}")
    | _, _ =>
        .error s!"offline-host log obligation has no formatter for event `{log.name}`"

def valueVaultEventLogLineFragment
    (log : ProofForge.IR.Semantics.EventLog) :
    Except String String := do
  .ok ("log: " ++ (← valueVaultEventLogPayload log))

def offlineHostLogLineFragments
    (logs : Array ProofForge.IR.Semantics.EventLog) :
    Except String (Array String) := do
  let mut fragments := #[]
  for log in logs do
    fragments := fragments.push (← valueVaultEventLogLineFragment log)
  .ok fragments

def offlineHostLogPayloadHexFragments
    (logs : Array ProofForge.IR.Semantics.EventLog) :
    Except String (Array String) := do
  let mut fragments := #[]
  for log in logs do
    fragments := fragments.push (stringHex (← valueVaultEventLogPayload log))
  .ok fragments

def storageHexSnapshot
    (storage : ProofForge.IR.Semantics.Bindings) :
    Except String (Array (String × String)) := do
  let mut snapshot := #[]
  for entry in storage do
    let valueHex ← borshValueHex entry.snd
    snapshot := snapshot.push (entry.fst, valueHex)
  .ok snapshot

def runOfflineHostExecutionStep
    (state : ProofForge.IR.Semantics.State)
    (mod : Module)
    (step : OfflineHostExecutionStep) :
    Except String (ProofForge.IR.Semantics.State × OfflineHostIOExpectation) := do
  let entrypoint ←
    match findEntrypoint? mod step.exportName with
    | some entrypoint => .ok entrypoint
    | none => .error s!"module `{mod.name}` has no exported entrypoint `{step.exportName}`"
  let inputHex ← borshArgsHex step.args
  let (nextState, result?) ← ProofForge.IR.Semantics.runEntrypointWithArgs state entrypoint step.args
  let returnValue ← observableReturn entrypoint.returns result?
  let newLogs := arrayDrop nextState.logs state.logs.size
  let logLineFragments ← offlineHostLogLineFragments newLogs
  let logPayloadHexFragments ← offlineHostLogPayloadHexFragments newLogs
  let storageHex ← storageHexSnapshot nextState.storage
  .ok (nextState, {
    exportName := step.exportName
    inputHex := inputHex
    returnLineFragment := s!"call 1:{step.exportName}: {offlineHostReturnFragment returnValue}"
    returnPayloadHex := observableReturnHex returnValue
    storageKeys := nextState.storage.length
    storageSnapshot := nextState.storage.toArray
    storageHexSnapshot := storageHex
    logCount := nextState.logs.size
    logLineFragments := logLineFragments
    logPayloadHexFragments := logPayloadHexFragments
  })

def runOfflineHostExecutionTraceList (mod : Module) :
    List OfflineHostExecutionStep → ProofForge.IR.Semantics.State →
    Except String (ProofForge.IR.Semantics.State × Array OfflineHostIOExpectation)
  | [], state => .ok (state, #[])
  | step :: rest, state => do
      let (nextState, ioStep) ← runOfflineHostExecutionStep state mod step
      let (finalState, ioSteps) ← runOfflineHostExecutionTraceList mod rest nextState
      .ok (finalState, #[ioStep] ++ ioSteps)

def runOfflineHostExecutionTraceResult
    (mod : Module)
    (steps : Array OfflineHostExecutionStep) :
    Except String OfflineHostExecutionTraceResult := do
  let (finalState, ioSteps) ←
    runOfflineHostExecutionTraceList mod steps.toList ProofForge.IR.Semantics.State.empty
  .ok { finalState := finalState, io := ioSteps }

def runOfflineHostExecutionTrace
    (mod : Module)
    (steps : Array OfflineHostExecutionStep) :
    Except String (Array OfflineHostIOExpectation) := do
  let result ← runOfflineHostExecutionTraceResult mod steps
  .ok result.io

def OfflineHostExecutionObligation.ioSurfaceOk
    (obligation : OfflineHostExecutionObligation) : Bool :=
  match runOfflineHostExecutionTrace obligation.artifactSurface.module obligation.steps with
  | .ok actual => actual == obligation.expectedIO
  | .error _ => false

def OfflineHostExecutionObligation.ok (obligation : OfflineHostExecutionObligation) : Bool :=
  obligation.artifactSurface.ok && obligation.ioSurfaceOk

abbrev SemValue := ProofForge.IR.Semantics.Value
abbrev ValueVaultInputs := ProofForge.Contract.Examples.ValueVaultInvariant.ScenarioInputs

def observableReturnFromSemValue? : Option SemValue → Except String ObservableReturn
  | none => .ok .none
  | some .unit => .ok .none
  | some (.bool value) => .ok (.bool value)
  | some (.u32 value) => .ok (.u32 value)
  | some (.u64 value) => .ok (.u64 value)
  | some (.hash a b c d) => .ok (.hash a b c d)
  | some (.address value) => .ok (.u64 value)
  | some (.u8 value) => .ok (.u32 value)
  | some (.u128 _) => .error "offline-host execution obligation does not yet encode u128 return values"
  | some (.bytes _) =>
      .error "offline-host execution obligation does not yet encode bytes return values"
  | some (.string _) =>
      .error "offline-host execution obligation does not yet encode string return values"
  | some (.array _) =>
      .error "offline-host execution obligation does not yet encode aggregate return values"
  | some (.struct _ _) =>
      .error "offline-host execution obligation does not yet encode struct return values"

def offlineHostIOExpectationFromReturn
    (step : OfflineHostExecutionStep)
    (returnValue? : Option SemValue) :
    Except String OfflineHostIOExpectation := do
  let inputHex ← borshArgsHex step.args
  let returnValue ← observableReturnFromSemValue? returnValue?
  .ok {
    exportName := step.exportName
    inputHex := inputHex
    returnLineFragment := s!"call 1:{step.exportName}: {offlineHostReturnFragment returnValue}"
    returnPayloadHex := observableReturnHex returnValue
  }

def OfflineHostIOExpectation.returnSurfaceEq
    (lhs rhs : OfflineHostIOExpectation) : Bool :=
  lhs.exportName == rhs.exportName &&
    lhs.inputHex == rhs.inputHex &&
    lhs.returnLineFragment == rhs.returnLineFragment &&
    lhs.returnPayloadHex == rhs.returnPayloadHex

def OfflineHostIOExpectation.returnPayloadHexEq
    (lhs rhs : OfflineHostIOExpectation) : Bool :=
  lhs.exportName == rhs.exportName &&
    lhs.returnPayloadHex == rhs.returnPayloadHex

def OfflineHostIOExpectation.storageSnapshotEq
    (lhs rhs : OfflineHostIOExpectation) : Bool :=
  lhs.exportName == rhs.exportName &&
    lhs.storageKeys == rhs.storageKeys &&
    lhs.storageSnapshot == rhs.storageSnapshot

def OfflineHostIOExpectation.storageHexSnapshotEq
    (lhs rhs : OfflineHostIOExpectation) : Bool :=
  lhs.exportName == rhs.exportName &&
    lhs.storageKeys == rhs.storageKeys &&
    lhs.storageHexSnapshot == rhs.storageHexSnapshot

def flattenOfflineHostLogLineFragments
    (io : Array OfflineHostIOExpectation) : Array String :=
  io.foldl (fun fragments step => fragments ++ step.logLineFragments) #[]

def flattenOfflineHostLogPayloadHexFragments
    (io : Array OfflineHostIOExpectation) : Array String :=
  io.foldl (fun fragments step => fragments ++ step.logPayloadHexFragments) #[]

def offlineHostReturnSurfaceMatchesList :
    List OfflineHostIOExpectation → List OfflineHostIOExpectation → Bool
  | [], [] => true
  | lhs :: lhsRest, rhs :: rhsRest =>
      lhs.returnSurfaceEq rhs && offlineHostReturnSurfaceMatchesList lhsRest rhsRest
  | _, _ => false

def offlineHostReturnSurfaceMatches
    (lhs rhs : Array OfflineHostIOExpectation) : Bool :=
  offlineHostReturnSurfaceMatchesList lhs.toList rhs.toList

def offlineHostReturnPayloadHexMatchesList :
    List OfflineHostIOExpectation → List OfflineHostIOExpectation → Bool
  | [], [] => true
  | lhs :: lhsRest, rhs :: rhsRest =>
      lhs.returnPayloadHexEq rhs && offlineHostReturnPayloadHexMatchesList lhsRest rhsRest
  | _, _ => false

def offlineHostReturnPayloadHexMatches
    (lhs rhs : Array OfflineHostIOExpectation) : Bool :=
  offlineHostReturnPayloadHexMatchesList lhs.toList rhs.toList

def OfflineHostExecutionObligation.returnPayloadHexOk
    (obligation : OfflineHostExecutionObligation) : Bool :=
  match runOfflineHostExecutionTrace obligation.artifactSurface.module obligation.steps with
  | .ok actual => offlineHostReturnPayloadHexMatches actual obligation.expectedIO
  | .error _ => false

def offlineHostStorageSnapshotsMatchList :
    List OfflineHostIOExpectation → List OfflineHostIOExpectation → Bool
  | [], [] => true
  | lhs :: lhsRest, rhs :: rhsRest =>
      lhs.storageSnapshotEq rhs && offlineHostStorageSnapshotsMatchList lhsRest rhsRest
  | _, _ => false

def offlineHostStorageSnapshotsMatch
    (lhs rhs : Array OfflineHostIOExpectation) : Bool :=
  offlineHostStorageSnapshotsMatchList lhs.toList rhs.toList

def OfflineHostExecutionObligation.storageSnapshotsOk
    (obligation : OfflineHostExecutionObligation) : Bool :=
  match runOfflineHostExecutionTrace obligation.artifactSurface.module obligation.steps with
  | .ok actual => offlineHostStorageSnapshotsMatch actual obligation.expectedIO
  | .error _ => false

def offlineHostStorageHexSnapshotsMatchList :
    List OfflineHostIOExpectation → List OfflineHostIOExpectation → Bool
  | [], [] => true
  | lhs :: lhsRest, rhs :: rhsRest =>
      lhs.storageHexSnapshotEq rhs && offlineHostStorageHexSnapshotsMatchList lhsRest rhsRest
  | _, _ => false

def offlineHostStorageHexSnapshotsMatch
    (lhs rhs : Array OfflineHostIOExpectation) : Bool :=
  offlineHostStorageHexSnapshotsMatchList lhs.toList rhs.toList

def OfflineHostExecutionObligation.storageHexSnapshotsOk
    (obligation : OfflineHostExecutionObligation) : Bool :=
  match runOfflineHostExecutionTrace obligation.artifactSurface.module obligation.steps with
  | .ok actual => offlineHostStorageHexSnapshotsMatch actual obligation.expectedIO
  | .error _ => false

def OfflineHostIOExpectation.logPayloadHexEq
    (lhs rhs : OfflineHostIOExpectation) : Bool :=
  lhs.exportName == rhs.exportName &&
    lhs.logCount == rhs.logCount &&
    lhs.logPayloadHexFragments == rhs.logPayloadHexFragments

def offlineHostLogPayloadHexMatchesList :
    List OfflineHostIOExpectation → List OfflineHostIOExpectation → Bool
  | [], [] => true
  | lhs :: lhsRest, rhs :: rhsRest =>
      lhs.logPayloadHexEq rhs && offlineHostLogPayloadHexMatchesList lhsRest rhsRest
  | _, _ => false

def offlineHostLogPayloadHexMatches
    (lhs rhs : Array OfflineHostIOExpectation) : Bool :=
  offlineHostLogPayloadHexMatchesList lhs.toList rhs.toList

def OfflineHostExecutionObligation.logPayloadHexOk
    (obligation : OfflineHostExecutionObligation) : Bool :=
  match runOfflineHostExecutionTrace obligation.artifactSurface.module obligation.steps with
  | .ok actual => offlineHostLogPayloadHexMatches actual obligation.expectedIO
  | .error _ => false

def offlineHostExpectedIOFromReturnsList :
    List OfflineHostExecutionStep → List (Option SemValue) →
    Except String (List OfflineHostIOExpectation)
  | [], [] => .ok []
  | step :: steps, returnValue? :: returnValues => do
      let current ← offlineHostIOExpectationFromReturn step returnValue?
      let rest ← offlineHostExpectedIOFromReturnsList steps returnValues
      .ok (current :: rest)
  | [], _ :: _ =>
      .error "offline-host execution obligation has more expected returns than steps"
  | _ :: _, [] =>
      .error "offline-host execution obligation has more steps than expected returns"

def offlineHostExpectedIOFromReturns
    (steps : Array OfflineHostExecutionStep)
    (returnValues : Array (Option SemValue)) :
    Except String (Array OfflineHostIOExpectation) := do
  let expected ← offlineHostExpectedIOFromReturnsList steps.toList returnValues.toList
  .ok expected.toArray

def valueVaultOfflineHostSteps (inputs : ValueVaultInputs) : Array OfflineHostExecutionStep := #[
  { exportName := "initialize", args := #[.u64 inputs.initial] },
  { exportName := "get_balance" },
  { exportName := "deposit", args := #[.u64 inputs.deposit] },
  { exportName := "get_balance" },
  { exportName := "charge_fee", args := #[.u64 inputs.grossCharge, .u64 inputs.feeBps] },
  { exportName := "get_balance" },
  { exportName := "get_net_value" },
  { exportName := "release", args := #[.u64 inputs.release] },
  { exportName := "get_balance" },
  { exportName := "snapshot" },
  { exportName := "get_net_value" }
]

def valueVaultOfflineHostExpectedIO?
    (inputs : ValueVaultInputs) :
    Except String (Array OfflineHostIOExpectation) :=
  offlineHostExpectedIOFromReturns
    (valueVaultOfflineHostSteps inputs)
    (ProofForge.Contract.Examples.ValueVaultInvariant.expectedReturns inputs)

def valueVaultOfflineHostInvariantTraceResult?
    (inputs : ValueVaultInputs) :
    Except String OfflineHostExecutionTraceResult :=
  runOfflineHostExecutionTraceResult
    ProofForge.Contract.Examples.ValueVaultInvariant.module
    (valueVaultOfflineHostSteps inputs)

def valueVaultOfflineHostFinalStateDerivesFromInvariant
    (inputs : ValueVaultInputs) : Bool :=
  match
      ProofForge.Contract.Examples.ValueVaultInvariant.runScenario inputs,
      valueVaultOfflineHostInvariantTraceResult? inputs with
  | .ok scenario, .ok trace =>
      trace.finalState == scenario.state &&
        ProofForge.Contract.Examples.ValueVaultInvariant.accountingInvariantHolds
          inputs trace.finalState &&
        ProofForge.Contract.Examples.ValueVaultInvariant.finalStorageMatches
          inputs trace.finalState
  | _, _ => false

def valueVaultOfflineHostLogFragmentsDeriveFromInvariantState
    (inputs : ValueVaultInputs) : Bool :=
  match
      ProofForge.Contract.Examples.ValueVaultInvariant.runScenario inputs,
      valueVaultOfflineHostInvariantTraceResult? inputs with
  | .ok scenario, .ok trace =>
      match offlineHostLogLineFragments scenario.state.logs with
      | .ok expected => flattenOfflineHostLogLineFragments trace.io == expected
      | .error _ => false
  | _, _ => false

def valueVaultOfflineHostLogPayloadHexDerivesFromInvariantState
    (inputs : ValueVaultInputs) : Bool :=
  match
      ProofForge.Contract.Examples.ValueVaultInvariant.runScenario inputs,
      valueVaultOfflineHostInvariantTraceResult? inputs with
  | .ok scenario, .ok trace =>
      match offlineHostLogPayloadHexFragments scenario.state.logs with
      | .ok expected => flattenOfflineHostLogPayloadHexFragments trace.io == expected
      | .error _ => false
  | _, _ => false

end ProofForge.Backend.WasmNear.Refinement
