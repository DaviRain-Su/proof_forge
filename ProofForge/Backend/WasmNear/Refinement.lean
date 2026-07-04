import ProofForge.Backend.WasmNear.EmitWat
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

def counterTraceEntrypoints : Array Entrypoint := #[
  ProofForge.IR.Examples.Counter.initializeEntrypoint,
  ProofForge.IR.Examples.Counter.get,
  ProofForge.IR.Examples.Counter.increment,
  ProofForge.IR.Examples.Counter.get
]

def counterExpectedTrace : Array ObservableStep := #[
  { exportName := "initialize", returnValue := .none },
  { exportName := "get", returnValue := .u64 0 },
  { exportName := "increment", returnValue := .none },
  { exportName := "get", returnValue := .u64 1 }
]

def counterTraceObligation : TraceObligation := {
  name := "Counter.initialize-get-increment-get"
  module := ProofForge.IR.Examples.Counter.module
  entrypoints := counterTraceEntrypoints
  expected := counterExpectedTrace
}

def emitWatKeyBuf : Nat := ProofForge.Backend.WasmNear.EmitWat.KEY_BUF
def emitWatRetBuf : Nat := ProofForge.Backend.WasmNear.EmitWat.RET_BUF
def emitWatEventBuf : Nat := ProofForge.Backend.WasmNear.EmitWat.EVENT_BUF
def emitWatEvtKeyPtr : Nat := ProofForge.Backend.WasmNear.EmitWat.EVT_KEY_PTR
def emitWatInputBuf : Nat := ProofForge.Backend.WasmNear.EmitWat.INPUT_BUF
def emitWatEvtPtrGlobal : String := ProofForge.Backend.WasmNear.EmitWat.evtPtrGlobal

def nearHostBufferMemoryRegions : Array WasmMemoryRegionExpectation := #[
  { name := "KEY_BUF", offset := emitWatKeyBuf, byteLength := 32 },
  { name := "RET_BUF", offset := emitWatRetBuf, byteLength := 32 },
  { name := "EVENT_BUF", offset := emitWatEventBuf, byteLength := 256 },
  { name := "EVT_KEY_PTR", offset := emitWatEvtKeyPtr, byteLength := 5 },
  { name := "INPUT_BUF", offset := emitWatInputBuf, byteLength := 1024 }
]

def nearHostBufferMemoryLayoutOk : Bool :=
  wasmMemoryLayoutOk nearHostBufferMemoryRegions

def nearU64StorageReadFrame : Array WasmTraceOp := #[
  .localGet "kl",
  .plain "i64.extend_i32_u",
  .localGet "kp",
  .plain "i64.extend_i32_u",
  .i64Const 0,
  .call "storage_read",
  .localSet "found",
  .localGet "found",
  .i64Const 0,
  .plain "i64.ne",
  .i64Const 0,
  .i64Const emitWatKeyBuf,
  .call "read_register",
  .i32Const emitWatKeyBuf,
  .load "i64.load" 0,
  .localSet "r"
]

def nearU64StorageWriteFrame : Array WasmTraceOp := #[
  .i32Const emitWatKeyBuf,
  .localGet "v",
  .store "i64.store" 0,
  .localGet "kl",
  .plain "i64.extend_i32_u",
  .localGet "kp",
  .plain "i64.extend_i32_u",
  .i64Const 8,
  .i64Const emitWatKeyBuf,
  .i64Const 0,
  .call "storage_write",
  .drop
]

def nearU64ValueReturnFrame : Array WasmTraceOp := #[
  .i32Const emitWatRetBuf,
  .localGet "v",
  .store "i64.store" 0,
  .i64Const 8,
  .i64Const emitWatRetBuf,
  .call "value_return"
]

def nearEventLogUtf8Frame : Array WasmTraceOp := #[
  .globalGet emitWatEvtPtrGlobal,
  .i32Const emitWatEventBuf,
  .plain "i32.sub",
  .plain "i64.extend_i32_u",
  .i64Const emitWatEventBuf,
  .call "log_utf8"
]

def nearInputRegisterFrame : Array WasmTraceOp := #[
  .i64Const 0,
  .call "input",
  .i64Const 0,
  .i64Const emitWatInputBuf,
  .call "read_register"
]

def nearU64InputParamFrame (name : String) (offset : Nat) : Array WasmTraceOp :=
  nearInputRegisterFrame ++ #[
    .i32Const (emitWatInputBuf + offset),
    .load "i64.load" 0,
    .localSet name
  ]

def nearU64ParamLoadFrame (name : String) (offset : Nat) : Array WasmTraceOp := #[
  .i32Const (emitWatInputBuf + offset),
  .load "i64.load" 0,
  .localSet name
]

def nearU64StorageReadKeyFrame (keyPtr keyLen : Nat) : Array WasmTraceOp := #[
  .i32Const keyPtr,
  .i32Const keyLen,
  .call (ProofForge.Backend.WasmNear.EmitWat.readName .u64)
]

def nearU64StorageWriteExprFrame
    (keyPtr keyLen : Nat)
    (valueOps : Array WasmTraceOp) : Array WasmTraceOp :=
  #[.i32Const keyPtr, .i32Const keyLen] ++
    valueOps ++
    #[.call (ProofForge.Backend.WasmNear.EmitWat.writeName .u64)]

def nearU64StorageWriteLiteralFrame (keyPtr keyLen value : Nat) : Array WasmTraceOp :=
  nearU64StorageWriteExprFrame keyPtr keyLen #[.i64Const value]

def nearU64StorageWriteLocalFrame (keyPtr keyLen : Nat) (localName : String) :
    Array WasmTraceOp :=
  nearU64StorageWriteExprFrame keyPtr keyLen #[.localGet localName]

def nearU64StorageWriteLocalAddLiteralFrame
    (keyPtr keyLen : Nat)
    (localName : String)
    (value : Nat) : Array WasmTraceOp :=
  nearU64StorageWriteExprFrame keyPtr keyLen #[
    .localGet localName,
    .i64Const value,
    .plain "i64.add"
  ]

def nearCheckpointBlockIndexFrame (localName : String) : Array WasmTraceOp := #[
  .call "block_index",
  .localSet localName
]

def nearU64HostFrameExpectations : Array WasmHostFrameExpectation := #[
  {
    functionName := ProofForge.Backend.WasmNear.EmitWat.readName .u64
    expectedOps := nearU64StorageReadFrame
  },
  {
    functionName := ProofForge.Backend.WasmNear.EmitWat.writeName .u64
    expectedOps := nearU64StorageWriteFrame
  },
  {
    functionName := ProofForge.Backend.WasmNear.EmitWat.returnU64Name
    expectedOps := nearU64ValueReturnFrame
  }
]

def nearInputHostFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearInputRegisterFrame },
  { functionName := "increment", expectedOps := nearInputRegisterFrame },
  { functionName := "get", expectedOps := nearInputRegisterFrame }
]

def nearValueVaultInputHostFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearU64InputParamFrame "initial" 0 },
  { functionName := "get_balance", expectedOps := nearInputRegisterFrame },
  { functionName := "deposit", expectedOps := nearU64InputParamFrame "amount" 0 },
  { functionName := "charge_fee", expectedOps := nearU64InputParamFrame "gross" 0 },
  {
    functionName := "charge_fee"
    expectedOps := nearU64ParamLoadFrame "fee_bps" 8
  },
  { functionName := "get_net_value", expectedOps := nearInputRegisterFrame },
  { functionName := "release", expectedOps := nearU64InputParamFrame "amount" 0 },
  { functionName := "snapshot", expectedOps := nearInputRegisterFrame }
]

def nearValueVaultContextHostFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearCheckpointBlockIndexFrame "checkpoint" },
  { functionName := "snapshot", expectedOps := nearCheckpointBlockIndexFrame "checkpoint" }
]

def counterStorageReadKeyFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "increment", expectedOps := nearU64StorageReadKeyFrame 0 5 },
  { functionName := "get", expectedOps := nearU64StorageReadKeyFrame 0 5 }
]

def counterStorageWriteKeyValueFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 0 5 0 },
  {
    functionName := "increment"
    expectedOps := nearU64StorageWriteLocalAddLiteralFrame 0 5 "n" 1
  }
]

def valueVaultStorageReadKeyFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "deposit", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "charge_fee", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "charge_fee", expectedOps := nearU64StorageReadKeyFrame 17 4 },
  { functionName := "charge_fee", expectedOps := nearU64StorageReadKeyFrame 49 10 },
  { functionName := "release", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "release", expectedOps := nearU64StorageReadKeyFrame 8 8 },
  { functionName := "release", expectedOps := nearU64StorageReadKeyFrame 49 10 },
  { functionName := "snapshot", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "snapshot", expectedOps := nearU64StorageReadKeyFrame 8 8 },
  { functionName := "snapshot", expectedOps := nearU64StorageReadKeyFrame 17 4 },
  { functionName := "get_balance", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "get_net_value", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "get_net_value", expectedOps := nearU64StorageReadKeyFrame 17 4 }
]

def valueVaultStorageWriteKeyValueFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearU64StorageWriteLocalFrame 0 7 "initial" },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 8 8 0 },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 17 4 0 },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLocalFrame 22 10 "initial" },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLocalFrame 33 15 "checkpoint" },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 49 10 1 },
  { functionName := "deposit", expectedOps := nearU64StorageWriteLocalFrame 0 7 "next" },
  { functionName := "deposit", expectedOps := nearU64StorageWriteLocalFrame 22 10 "amount" },
  { functionName := "deposit", expectedOps := nearU64StorageWriteLocalFrame 49 10 "next_ops" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 0 7 "next" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 17 4 "next_fees" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 22 10 "net" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 49 10 "next_ops" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 0 7 "next" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 8 8 "released_next" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 22 10 "amount" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 49 10 "next_ops" },
  { functionName := "snapshot", expectedOps := nearU64StorageWriteLocalFrame 33 15 "checkpoint" }
]

def wasmHostFramesOk
    (module : Module)
    (frames : Array WasmHostFrameExpectation) : Bool :=
  match ProofForge.Backend.WasmNear.EmitWat.lowerModule module with
  | .ok wasm => frames.all (fun expectation => expectation.ok wasm)
  | .error _ => false

def counterInputHostFramesOk : Bool :=
  wasmHostFramesOk ProofForge.IR.Examples.Counter.module nearInputHostFrameExpectations

def counterStorageReadKeyFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.IR.Examples.Counter.module
    counterStorageReadKeyFrameExpectations

def counterStorageWriteKeyValueFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.IR.Examples.Counter.module
    counterStorageWriteKeyValueFrameExpectations

def valueVaultInputHostFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.Contract.Examples.ValueVault.module
    nearValueVaultInputHostFrameExpectations

def valueVaultContextHostFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.Contract.Examples.ValueVault.module
    nearValueVaultContextHostFrameExpectations

def valueVaultStorageReadKeyFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.Contract.Examples.ValueVault.module
    valueVaultStorageReadKeyFrameExpectations

def valueVaultStorageWriteKeyValueFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.Contract.Examples.ValueVault.module
    valueVaultStorageWriteKeyValueFrameExpectations

def counterArtifactSurfaceObligation : ArtifactSurfaceObligation := {
  name := "Counter.EmitWat.artifact-surface"
  module := ProofForge.IR.Examples.Counter.module
  requiredImports := #[
    "input",
    "read_register",
    "storage_read",
    "storage_write",
    "value_return"
  ]
  requiredImportSignatures := #[
    { functionName := "input", params := #[.i64] },
    { functionName := "read_register", params := #[.i64, .i64] },
    { functionName := "storage_read", params := #[.i64, .i64, .i64], results := #[.i64] },
    {
      functionName := "storage_write"
      params := #[.i64, .i64, .i64, .i64, .i64]
      results := #[.i64]
    },
    { functionName := "value_return", params := #[.i64, .i64] }
  ]
  requiredExports := #[
    { exportName := "initialize", expectedCalls := #["input", "read_register", "__pf_write_u64"] },
    { exportName := "increment", expectedCalls := #["input", "read_register", "__pf_read_u64", "__pf_write_u64"] },
    { exportName := "get", expectedCalls := #["input", "read_register", "__pf_read_u64", "__pf_return_u64"] }
  ]
  requiredFunctions := #[
    { functionName := "__pf_read_u64", expectedCalls := #["storage_read", "read_register"] },
    { functionName := "__pf_write_u64", expectedCalls := #["storage_write"] },
    { functionName := "__pf_return_u64", expectedCalls := #["value_return"] }
  ]
  requiredHostFrames :=
    nearU64HostFrameExpectations ++
      nearInputHostFrameExpectations ++
      counterStorageReadKeyFrameExpectations ++
      counterStorageWriteKeyValueFrameExpectations
  requiredDataSegments := #[(0, "count")]
  requiredMemoryRegions := nearHostBufferMemoryRegions
}

def counterStorageSnapshot (count : Nat) :
    Array (String × ProofForge.IR.Semantics.Value) :=
  #[("count", .u64 count)]

def counterStorageHexSnapshot (count : Nat) : Array (String × String) :=
  #[("count", littleEndianHex 8 count)]

def counterOfflineHostExecutionObligation : OfflineHostExecutionObligation := {
  name := "Counter.EmitWat.offline-host-execution-surface"
  artifactSurface := counterArtifactSurfaceObligation
  steps := #[
    { exportName := "initialize" },
    { exportName := "get" },
    { exportName := "increment" },
    { exportName := "get" }
  ]
  expectedIO := #[
    {
      exportName := "initialize"
      inputHex := ""
      returnLineFragment := "call 1:initialize: return=<none>"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 0
      storageHexSnapshot := counterStorageHexSnapshot 0
      logCount := 0
    },
    {
      exportName := "get"
      inputHex := ""
      returnLineFragment := "call 1:get: return_hex=0000000000000000 return_u64=0"
      returnPayloadHex := "0000000000000000"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 0
      storageHexSnapshot := counterStorageHexSnapshot 0
      logCount := 0
    },
    {
      exportName := "increment"
      inputHex := ""
      returnLineFragment := "call 1:increment: return=<none>"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 1
      storageHexSnapshot := counterStorageHexSnapshot 1
      logCount := 0
    },
    {
      exportName := "get"
      inputHex := ""
      returnLineFragment := "call 1:get: return_hex=0100000000000000 return_u64=1"
      returnPayloadHex := "0100000000000000"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 1
      storageHexSnapshot := counterStorageHexSnapshot 1
      logCount := 0
    }
  ]
}

def valueVaultArtifactSurfaceObligation : ArtifactSurfaceObligation := {
  name := "ValueVault.EmitWat.artifact-surface"
  module := ProofForge.Contract.Examples.ValueVault.module
  requiredImports := #[
    "input",
    "read_register",
    "storage_read",
    "storage_write",
    "value_return",
    "log_utf8",
    "block_index"
  ]
  requiredImportSignatures := #[
    { functionName := "input", params := #[.i64] },
    { functionName := "read_register", params := #[.i64, .i64] },
    { functionName := "storage_read", params := #[.i64, .i64, .i64], results := #[.i64] },
    {
      functionName := "storage_write"
      params := #[.i64, .i64, .i64, .i64, .i64]
      results := #[.i64]
    },
    { functionName := "value_return", params := #[.i64, .i64] },
    { functionName := "log_utf8", params := #[.i64, .i64] },
    { functionName := "block_index", results := #[.i64] }
  ]
  requiredExports := #[
    {
      exportName := "initialize"
      expectedCalls := #[
        "input", "read_register", "block_index", "__pf_write_u64",
        "__pf_write_u64", "__pf_write_u64", "__pf_write_u64",
        "__pf_write_u64", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "deposit"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_read_u64",
        "__pf_write_u64", "__pf_write_u64", "__pf_write_u64",
        "__pf_evt_log"
      ]
    },
    {
      exportName := "charge_fee"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_read_u64",
        "__pf_read_u64", "__pf_write_u64", "__pf_write_u64",
        "__pf_write_u64", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "release"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_read_u64",
        "__pf_read_u64", "__pf_write_u64", "__pf_write_u64",
        "__pf_write_u64", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "snapshot"
      expectedCalls := #[
        "input", "read_register", "block_index", "__pf_read_u64",
        "__pf_read_u64", "__pf_read_u64", "__pf_write_u64",
        "__pf_evt_log", "__pf_return_u64"
      ]
    },
    {
      exportName := "get_balance"
      expectedCalls := #["input", "read_register", "__pf_read_u64", "__pf_return_u64"]
    },
    {
      exportName := "get_net_value"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_read_u64",
        "__pf_return_u64"
      ]
    }
  ]
  requiredFunctions := #[
    { functionName := "__pf_read_u64", expectedCalls := #["storage_read", "read_register"] },
    { functionName := "__pf_write_u64", expectedCalls := #["storage_write"] },
    { functionName := "__pf_return_u64", expectedCalls := #["value_return"] },
    { functionName := "__pf_evt_log", expectedCalls := #["log_utf8"] }
  ]
  requiredHostFrames :=
    nearU64HostFrameExpectations ++
      nearValueVaultInputHostFrameExpectations ++
      nearValueVaultContextHostFrameExpectations ++
      valueVaultStorageReadKeyFrameExpectations ++
      valueVaultStorageWriteKeyValueFrameExpectations |>.push {
      functionName := ProofForge.Backend.WasmNear.EmitWat.evtLogName
      expectedOps := nearEventLogUtf8Frame
    }
  requiredDataSegments := #[
    (0, "balance"),
    (8, "released"),
    (17, "fees"),
    (22, "last_value"),
    (33, "last_checkpoint"),
    (49, "operations"),
    (43000, "VaultInitialized"),
    (43036, "ValueDeposited"),
    (43077, "ValueCharged"),
    (43104, "ValueReleased"),
    (43127, "ValueSnapshot")
  ]
  requiredMemoryRegions := nearHostBufferMemoryRegions
}

def valueVaultStorageSnapshot
    (balance released fees lastValue lastCheckpoint operations : Nat) :
    Array (String × ProofForge.IR.Semantics.Value) := #[
  ("balance", .u64 balance),
  ("released", .u64 released),
  ("fees", .u64 fees),
  ("last_value", .u64 lastValue),
  ("last_checkpoint", .u64 lastCheckpoint),
  ("operations", .u64 operations)
]

def valueVaultStorageHexSnapshot
    (balance released fees lastValue lastCheckpoint operations : Nat) :
    Array (String × String) := #[
  ("balance", littleEndianHex 8 balance),
  ("released", littleEndianHex 8 released),
  ("fees", littleEndianHex 8 fees),
  ("last_value", littleEndianHex 8 lastValue),
  ("last_checkpoint", littleEndianHex 8 lastCheckpoint),
  ("operations", littleEndianHex 8 operations)
]

def valueVaultOfflineHostExecutionObligation : OfflineHostExecutionObligation := {
  name := "ValueVault.EmitWat.offline-host-execution-surface"
  artifactSurface := valueVaultArtifactSurfaceObligation
  steps := #[
    { exportName := "initialize", args := #[.u64 100] },
    { exportName := "get_balance" },
    { exportName := "deposit", args := #[.u64 25] },
    { exportName := "get_balance" },
    { exportName := "charge_fee", args := #[.u64 100, .u64 250] },
    { exportName := "get_balance" },
    { exportName := "get_net_value" },
    { exportName := "release", args := #[.u64 23] },
    { exportName := "get_balance" },
    { exportName := "snapshot" },
    { exportName := "get_net_value" }
  ]
  expectedIO := #[
    {
      exportName := "initialize"
      inputHex := "6400000000000000"
      returnLineFragment := "call 1:initialize: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 100 0 0 100 0 1
      storageHexSnapshot := valueVaultStorageHexSnapshot 100 0 0 100 0 1
      logCount := 1
      logLineFragments := #[
        "log: {\"event\":\"VaultInitialized\",\"initial\":100,\"checkpoint\":0}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"VaultInitialized\",\"initial\":100,\"checkpoint\":0}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=6400000000000000 return_u64=100"
      returnPayloadHex := "6400000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 100 0 0 100 0 1
      storageHexSnapshot := valueVaultStorageHexSnapshot 100 0 0 100 0 1
      logCount := 1
    },
    {
      exportName := "deposit"
      inputHex := "1900000000000000"
      returnLineFragment := "call 1:deposit: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 125 0 0 25 0 2
      storageHexSnapshot := valueVaultStorageHexSnapshot 125 0 0 25 0 2
      logCount := 2
      logLineFragments := #[
        "log: {\"event\":\"ValueDeposited\",\"amount\":25,\"balance\":125,\"operations\":2}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueDeposited\",\"amount\":25,\"balance\":125,\"operations\":2}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=7d00000000000000 return_u64=125"
      returnPayloadHex := "7d00000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 125 0 0 25 0 2
      storageHexSnapshot := valueVaultStorageHexSnapshot 125 0 0 25 0 2
      logCount := 2
    },
    {
      exportName := "charge_fee"
      inputHex := "6400000000000000fa00000000000000"
      returnLineFragment := "call 1:charge_fee: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 223 0 2 98 0 3
      storageHexSnapshot := valueVaultStorageHexSnapshot 223 0 2 98 0 3
      logCount := 3
      logLineFragments := #[
        "log: {\"event\":\"ValueCharged\",\"gross\":100,\"fee\":2,\"net\":98,\"balance\":223}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueCharged\",\"gross\":100,\"fee\":2,\"net\":98,\"balance\":223}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=df00000000000000 return_u64=223"
      returnPayloadHex := "df00000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 223 0 2 98 0 3
      storageHexSnapshot := valueVaultStorageHexSnapshot 223 0 2 98 0 3
      logCount := 3
    },
    {
      exportName := "get_net_value"
      inputHex := ""
      returnLineFragment := "call 1:get_net_value: return_hex=dd00000000000000 return_u64=221"
      returnPayloadHex := "dd00000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 223 0 2 98 0 3
      storageHexSnapshot := valueVaultStorageHexSnapshot 223 0 2 98 0 3
      logCount := 3
    },
    {
      exportName := "release"
      inputHex := "1700000000000000"
      returnLineFragment := "call 1:release: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 4
      logLineFragments := #[
        "log: {\"event\":\"ValueReleased\",\"amount\":23,\"balance\":200,\"released\":23}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueReleased\",\"amount\":23,\"balance\":200,\"released\":23}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=c800000000000000 return_u64=200"
      returnPayloadHex := "c800000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 4
    },
    {
      exportName := "snapshot"
      inputHex := ""
      returnLineFragment := "call 1:snapshot: return_hex=c800000000000000 return_u64=200"
      returnPayloadHex := "c800000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 5
      logLineFragments := #[
        "log: {\"event\":\"ValueSnapshot\",\"balance\":200,\"released\":23,\"fees\":2,\"checkpoint\":0}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueSnapshot\",\"balance\":200,\"released\":23,\"fees\":2,\"checkpoint\":0}"
      ]
    },
    {
      exportName := "get_net_value"
      inputHex := ""
      returnLineFragment := "call 1:get_net_value: return_hex=c600000000000000 return_u64=198"
      returnPayloadHex := "c600000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 5
    }
  ]
}

def valueVaultOfflineHostStepsDeriveFromInvariantInputs : Bool :=
  valueVaultOfflineHostExecutionObligation.steps ==
    valueVaultOfflineHostSteps ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs

def valueVaultOfflineHostExpectedIODerivesFromInvariantReturns : Bool :=
  match valueVaultOfflineHostExpectedIO? ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs with
  | .ok expected =>
      offlineHostReturnSurfaceMatches expected valueVaultOfflineHostExecutionObligation.expectedIO
  | .error _ => false

def valueVaultOfflineHostReturnPayloadHexDerivesFromInvariantReturns : Bool :=
  match valueVaultOfflineHostExpectedIO? ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs with
  | .ok expected =>
      offlineHostReturnPayloadHexMatches expected valueVaultOfflineHostExecutionObligation.expectedIO
  | .error _ => false

def valueVaultEmitWatBackendInvariantBridgeOk : Bool :=
  ProofForge.Contract.Examples.ValueVaultInvariant.defaultScenarioTraceOk &&
    ProofForge.Contract.Examples.ValueVaultInvariant.defaultScenarioAccountingOk &&
    ProofForge.Contract.Examples.ValueVaultInvariant.defaultScenarioNetValueOk &&
    valueVaultOfflineHostStepsDeriveFromInvariantInputs &&
    valueVaultOfflineHostExpectedIODerivesFromInvariantReturns &&
    valueVaultOfflineHostReturnPayloadHexDerivesFromInvariantReturns &&
    valueVaultOfflineHostFinalStateDerivesFromInvariant
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs &&
    valueVaultArtifactSurfaceObligation.memorySurfaceOk &&
    valueVaultInputHostFramesOk &&
    valueVaultContextHostFramesOk &&
    valueVaultStorageReadKeyFramesOk &&
    valueVaultStorageWriteKeyValueFramesOk &&
    valueVaultOfflineHostExecutionObligation.returnPayloadHexOk &&
    valueVaultOfflineHostExecutionObligation.storageSnapshotsOk &&
    valueVaultOfflineHostExecutionObligation.storageHexSnapshotsOk &&
    valueVaultOfflineHostLogFragmentsDeriveFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs &&
    valueVaultOfflineHostExecutionObligation.logPayloadHexOk &&
    valueVaultOfflineHostLogPayloadHexDerivesFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs &&
    valueVaultOfflineHostExecutionObligation.ok

theorem value_vault_offline_host_final_state_derives_from_invariant :
    valueVaultOfflineHostFinalStateDerivesFromInvariant
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs = true := by
  native_decide

theorem value_vault_offline_host_logs_derive_from_invariant_state :
    valueVaultOfflineHostLogFragmentsDeriveFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs = true := by
  native_decide

theorem value_vault_offline_host_log_payload_hex_derives_from_invariant_state :
    valueVaultOfflineHostLogPayloadHexDerivesFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs = true := by
  native_decide

theorem value_vault_offline_host_return_payload_hex_derives_from_invariant_returns :
    valueVaultOfflineHostReturnPayloadHexDerivesFromInvariantReturns = true := by
  native_decide

theorem near_emitwat_host_buffer_memory_layout_ok :
    nearHostBufferMemoryLayoutOk = true := by
  native_decide

theorem counter_ir_observable_trace_ok :
    counterTraceObligation.irTraceOk = true := by
  native_decide

theorem counter_emitwat_exports_trace_entrypoints :
    counterTraceObligation.emitWatExportsOk = true := by
  native_decide

theorem counter_emitwat_artifact_surface_ok :
    counterArtifactSurfaceObligation.ok = true := by
  native_decide

theorem counter_emitwat_host_import_signatures_ok :
    counterArtifactSurfaceObligation.hostImportSignaturesOk = true := by
  native_decide

theorem counter_emitwat_host_frames_ok :
    counterArtifactSurfaceObligation.hostFramesOk = true := by
  native_decide

theorem counter_emitwat_input_host_frames_ok :
    counterInputHostFramesOk = true := by
  native_decide

theorem counter_emitwat_storage_read_key_frames_ok :
    counterStorageReadKeyFramesOk = true := by
  native_decide

theorem counter_emitwat_storage_write_key_value_frames_ok :
    counterStorageWriteKeyValueFramesOk = true := by
  native_decide

theorem counter_emitwat_memory_surface_ok :
    counterArtifactSurfaceObligation.memorySurfaceOk = true := by
  native_decide

theorem counter_emitwat_offline_host_execution_surface_ok :
    counterOfflineHostExecutionObligation.ok = true := by
  native_decide

theorem counter_emitwat_offline_host_return_payload_hex_ok :
    counterOfflineHostExecutionObligation.returnPayloadHexOk = true := by
  native_decide

theorem counter_emitwat_offline_host_storage_snapshots_ok :
    counterOfflineHostExecutionObligation.storageSnapshotsOk = true := by
  native_decide

theorem counter_emitwat_offline_host_storage_hex_snapshots_ok :
    counterOfflineHostExecutionObligation.storageHexSnapshotsOk = true := by
  native_decide

theorem value_vault_emitwat_artifact_surface_ok :
    valueVaultArtifactSurfaceObligation.ok = true := by
  native_decide

theorem value_vault_emitwat_host_import_signatures_ok :
    valueVaultArtifactSurfaceObligation.hostImportSignaturesOk = true := by
  native_decide

theorem value_vault_emitwat_host_frames_ok :
    valueVaultArtifactSurfaceObligation.hostFramesOk = true := by
  native_decide

theorem value_vault_emitwat_input_host_frames_ok :
    valueVaultInputHostFramesOk = true := by
  native_decide

theorem value_vault_emitwat_context_host_frames_ok :
    valueVaultContextHostFramesOk = true := by
  native_decide

theorem value_vault_emitwat_storage_read_key_frames_ok :
    valueVaultStorageReadKeyFramesOk = true := by
  native_decide

theorem value_vault_emitwat_storage_write_key_value_frames_ok :
    valueVaultStorageWriteKeyValueFramesOk = true := by
  native_decide

theorem value_vault_emitwat_memory_surface_ok :
    valueVaultArtifactSurfaceObligation.memorySurfaceOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_execution_surface_ok :
    valueVaultOfflineHostExecutionObligation.ok = true := by
  native_decide

theorem value_vault_emitwat_offline_host_return_payload_hex_ok :
    valueVaultOfflineHostExecutionObligation.returnPayloadHexOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_storage_snapshots_ok :
    valueVaultOfflineHostExecutionObligation.storageSnapshotsOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_storage_hex_snapshots_ok :
    valueVaultOfflineHostExecutionObligation.storageHexSnapshotsOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_log_payload_hex_ok :
    valueVaultOfflineHostExecutionObligation.logPayloadHexOk = true := by
  native_decide

theorem value_vault_emitwat_backend_invariant_bridge_ok :
    valueVaultEmitWatBackendInvariantBridgeOk = true := by
  native_decide

end ProofForge.Backend.WasmNear.Refinement
