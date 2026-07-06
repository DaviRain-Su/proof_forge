import ProofForge.Backend.WasmNear.EmitWat
import ProofForge.Backend.WasmNear.Memory
import ProofForge.Backend.WasmNear.Types
import ProofForge.IR.Semantics
import ProofForge.IR.Examples.Counter
import ProofForge.Compiler.Wasm.AST
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Examples.ValueVaultInvariant
import ProofForge.Backend.WasmNear.Refinement.Core

namespace ProofForge.Backend.WasmNear.Refinement

open ProofForge.IR

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

def emitWatKeyBuf : Nat := ProofForge.Backend.WasmNear.Memory.KEY_BUF
def emitWatRetBuf : Nat := ProofForge.Backend.WasmNear.Memory.RET_BUF
def emitWatEventBuf : Nat := ProofForge.Backend.WasmNear.Memory.EVENT_BUF
def emitWatEvtKeyPtr : Nat := ProofForge.Backend.WasmNear.Memory.EVT_KEY_PTR
def emitWatInputBuf : Nat := ProofForge.Backend.WasmNear.Memory.INPUT_BUF
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
  .call (ProofForge.Backend.WasmNear.Types.readName .u64)
]

def nearU64StorageWriteExprFrame
    (keyPtr keyLen : Nat)
    (valueOps : Array WasmTraceOp) : Array WasmTraceOp :=
  #[.i32Const keyPtr, .i32Const keyLen] ++
    valueOps ++
    #[.call (ProofForge.Backend.WasmNear.Types.writeName .u64)]

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
    functionName := ProofForge.Backend.WasmNear.Types.readName .u64
    expectedOps := nearU64StorageReadFrame
  },
  {
    functionName := ProofForge.Backend.WasmNear.Types.writeName .u64
    expectedOps := nearU64StorageWriteFrame
  },
  {
    functionName := ProofForge.Backend.WasmNear.Types.returnU64Name
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
