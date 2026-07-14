import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.JsonReturn.Legacy
import ProofForge.Backend.WasmHost.NearAbiPlan.Legacy
import ProofForge.Backend.WasmHost.NearModulePlan.Legacy
import ProofForge.Backend.WasmHost.WasmInterpreter

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.WasmHost.WasmInterpreter

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def echoEntrypoint : Entrypoint := {
  name := "echo"
  mutability := .view
  params := #[("value", .u64)]
  returns := .u64
  body := #[.return (.local "value")]
}

def echoModule : Module := {
  name := "NearU64RoundTrip"
  state := #[]
  entrypoints := #[echoEntrypoint]
}

def ftBalanceEntrypoint : Entrypoint := {
  name := "ft_balance_of"
  mutability := .view
  params := #[("account_id", .string)]
  returns := .u128
  body := #[.return (.literal (.u128 100))]
}

def ftBalanceModule : Module := {
  name := "NearFtBalanceJson"
  state := #[]
  entrypoints := #[ftBalanceEntrypoint]
}

def ftSupplyEntrypoint : Entrypoint := {
  name := "ft_total_supply"
  mutability := .view
  params := #[]
  returns := .u128
  body := #[.return (.literal (.u128 100))]
}

def ftSupplyModule : Module := {
  name := "NearFtSupplyJson"
  state := #[]
  entrypoints := #[ftSupplyEntrypoint]
}

def metadataStruct : StructDecl := {
  name := "FungibleTokenMetadata"
  fields := #[
    { id := "spec", type := .string }, { id := "name", type := .string },
    { id := "symbol", type := .string }, { id := "icon", type := .string },
    { id := "reference", type := .string }, { id := "decimals", type := .u64 }
  ]
}

def ftMetadataEntrypoint : Entrypoint := {
  name := "ft_metadata"
  mutability := .view
  returns := .structType "FungibleTokenMetadata"
  body := #[.return (.structLit "FungibleTokenMetadata" #[
    ("spec", .literal (.string "ft-1.0.0")),
    ("name", .literal (.string "ProofForge Token")),
    ("symbol", .literal (.string "PFT")),
    ("icon", .literal (.string "")),
    ("reference", .literal (.string "")),
    ("decimals", .literal (.u64 18))
  ])]
}

def ftMetadataModule : Module := {
  name := "NearFtMetadataJson"
  structs := #[metadataStruct]
  state := #[]
  entrypoints := #[ftMetadataEntrypoint]
}

def jsonSchemaStructs : Array StructDecl := #[{
  name := "StorageBalance"
  fields := #[
    { id := "total", type := .u128 },
    { id := "available", type := .u128 },
    { id := "flags", type := .fixedArray .bool 2 }
  ]
}]

def aggregateCarrierModule : Module := {
  name := "NearJsonAggregateCarrier"
  structs := #[{
    name := "JsonAggregateCarrier"
    fields := #[
      { id := "amount", type := .u128 },
      { id := "memo", type := .string }
    ]
  }]
  state := #[]
  entrypoints := #[{
    name := "aggregate_amount"
    mutability := .view
    params := #[("memo", .string)]
    returns := .u128
    body := #[.return (.field
      (.structLit "JsonAggregateCarrier" #[
        ("amount", .literal (.u128 100)), ("memo", .local "memo")
      ]) "amount")]
  }]
}

def ftTransferEntrypoint : Entrypoint := {
  name := "ft_transfer"
  mutability := .call
  params := #[("receiver_id", .string), ("amount", .u128), ("memo", .string)]
  returns := .unit
  body := #[]
}

def ftTransferModule : Module := {
  name := "NearFtTransferJson"
  state := #[]
  entrypoints := #[ftTransferEntrypoint]
}

def ftTransferCallEntrypoint : Entrypoint := {
  name := "ft_transfer_call"
  mutability := .call
  params := #[("receiver_id", .string), ("amount", .u128), ("memo", .string),
    ("msg", .string)]
  returns := .u64
  body := #[.return (.literal (.u64 0))]
}

def ftResolveTransferEntrypoint : Entrypoint := {
  name := "ft_resolve_transfer"
  mutability := .call
  params := #[("transfer_id", .u64), ("sender", .string), ("receiver", .string)]
  returns := .u128
  body := #[.return (.literal (.u128 0))]
}

def nep145Structs : Array StructDecl := #[
  { name := "StorageBalance", fields := #[
      { id := "total", type := .u128 }, { id := "available", type := .u128 }] },
  { name := "StorageBalanceBounds", fields := #[
      { id := "min", type := .u128 }, { id := "max", type := .u128 }] }
]

def storageDepositEntrypoint : Entrypoint := {
  name := "storage_deposit"
  mutability := .call
  params := #[("account_id", .string), ("registration_only", .bool)]
  returns := .structType "StorageBalance"
  body := #[]
}

def storageWithdrawEntrypoint : Entrypoint := {
  name := "storage_withdraw"
  mutability := .call
  params := #[("amount", .u128)]
  returns := .structType "StorageBalance"
  body := #[]
}

def storageUnregisterEntrypoint : Entrypoint := {
  name := "storage_unregister"
  mutability := .call
  params := #[("force", .bool)]
  returns := .bool
  body := #[]
}

def dynamicBytesModule : Module := {
  name := "DynamicBytesNearAbi"
  state := #[]
  entrypoints := #[{
    name := "echo_bytes"
    mutability := .view
    params := #[("value", .bytes)]
    returns := .bytes
    body := #[.return (.local "value")]
  }]
}

def mixedDynamicModule : Module := {
  name := "MixedDynamicNearAbi"
  state := #[]
  entrypoints := #[{
    name := "echo_bytes_with_tag"
    mutability := .view
    params := #[("value", .bytes), ("tag", .u64)]
    returns := .bytes
    body := #[.return (.local "value")]
  }]
}

def main : IO Unit := do
  let abi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] echoEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (abi.inputCodec == .borsh && abi.outputCodec == .borsh)
    "NEAR entrypoint codecs must be Borsh"
  require (abi.inputByteWidth == 8 && abi.outputByteWidth == 8)
    "NEAR u64 round-trip must use exact 8-byte input/output widths"
  let ftAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] ftBalanceEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (ftAbi.inputCodec == .json && ftAbi.outputCodec == .json)
    "NEAR ft_balance_of must use the standard JSON codec"
  require (ftAbi.inputByteWidth == 0 && ftAbi.outputByteWidth == 0)
    "dynamic JSON codec widths must not claim a fixed Borsh payload"
  let some ftInputSchema := ftAbi.inputJson?
    | throw <| IO.userError "ft_balance_of input JSON schema is missing"
  let some ftInputRoot := ftInputSchema.root?
    | throw <| IO.userError "ft_balance_of input JSON schema root is missing"
  require (ftInputRoot.kind == .object && ftInputRoot.fields.map (·.wireName) == #["account_id"])
    "ft_balance_of input JSON schema must own its canonical object field"
  let some ftOutputSchema := ftAbi.outputJson?
    | throw <| IO.userError "ft_balance_of output JSON schema is missing"
  require (ftOutputSchema.root?.map (·.kind) == some .decimalString)
    "ft_balance_of output JSON schema must encode U128 as a decimal string"
  let ftPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan ftBalanceModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let ftWat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan ftBalanceModule ftPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (ftWat.contains "call $__pf_return_json_ft_balance_of")
    "NEAR ft_balance_of must route U128 through the JSON decimal-string return helper"
  require (ftWat.contains "i32.const 123" && ftWat.contains "i32.const 125")
    "NEAR ft_balance_of JSON input must validate object braces"
  let invalidFtBalance := { ftBalanceEntrypoint with returns := .u64 }
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] invalidFtBalance with
  | .error message =>
      require (message.contains "must have signature")
        "invalid standard ft_balance_of signature must be actionable"
  | .ok _ => throw <| IO.userError "invalid standard ft_balance_of signature did not fail closed"
  let supplyAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] ftSupplyEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (supplyAbi.inputCodec == .json && supplyAbi.outputCodec == .json)
    "NEAR ft_total_supply must use standard JSON input/output"
  require ((supplyAbi.inputJson?.bind (·.root?) |>.map (·.fields.isEmpty)) == some true)
    "NEAR ft_total_supply must plan an empty JSON input object"
  require ((supplyAbi.outputJson?.bind (·.root?) |>.map (·.kind)) == some .decimalString)
    "NEAR ft_total_supply must plan a JSON U128 decimal-string output"
  let supplyPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan ftSupplyModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let supplyWat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan ftSupplyModule supplyPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (supplyWat.contains "call $__pf_return_json_ft_total_supply")
    "NEAR ft_total_supply must use the JSON U128 return helper"
  require (supplyWat.contains "i64.const 2" && supplyWat.contains "i32.const 123")
    "NEAR ft_total_supply must validate the canonical empty JSON object"
  let metadataAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan
      #[metadataStruct] ftMetadataEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (metadataAbi.inputCodec == .json && metadataAbi.outputCodec == .json)
    "NEAR ft_metadata must use standard JSON input/output"
  require ((metadataAbi.outputJson?.bind (·.root?) |>.map (fun root =>
      root.fields.map (·.wireName))) ==
      some #["spec", "name", "symbol", "icon", "reference", "decimals"])
    "ft_metadata JSON schema must expose the NEP-148 metadata fields"
  let metadataPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan
      ftMetadataModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let metadataWat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan
      ftMetadataModule metadataPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (metadataWat.contains "call $__pf_return_json_ft_metadata")
    "NEAR ft_metadata must route its struct through the schema-driven JSON return helper"
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[metadataStruct]
      { ftMetadataEntrypoint with returns := .u64 } with
  | .ok _ => throw <| IO.userError "invalid ft_metadata signature did not fail closed"
  | .error message =>
      require (message.contains "must have signature")
        "invalid ft_metadata signature must be actionable"
  let transferAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] ftTransferEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (transferAbi.inputCodec == .json && transferAbi.outputCodec == .borsh)
    "NEAR ft_transfer must use JSON input without claiming a JSON return payload"
  require (transferAbi.inputByteWidth == 0 && transferAbi.outputByteWidth == 0)
    "NEAR ft_transfer JSON input and Unit output must have dynamic/zero codec widths"
  let some transferSchema := transferAbi.inputJson?
    | throw <| IO.userError "ft_transfer input JSON schema is missing"
  require (transferSchema.orderIndependent && transferSchema.rejectUnknownFields)
    "NEAR JSON object schemas must accept field reordering and reject unknown fields"
  require (transferSchema.root?.map (fun root => root.fields.map (·.wireName)) ==
      some #["receiver_id", "amount", "memo"])
    "ft_transfer JSON schema must own its standard wire fields"
  let some transferRoot := transferSchema.root?
    | throw <| IO.userError "ft_transfer JSON root is missing"
  require (transferRoot.fields[2]?.map (fun field => !field.required) == some true)
    "ft_transfer memo must be optional on the wire"
  let transferPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan ftTransferModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let transferWat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan ftTransferModule transferPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (transferWat.contains "call $__pf_parse_u128_decimal")
    "NEAR ft_transfer must parse its JSON decimal-string amount into U128"
  require (transferWat.contains "i32.const 114" && transferWat.contains "i32.const 97")
    "NEAR ft_transfer must validate receiver_id and amount field bytes"
  let invalidFtTransfer := { ftTransferEntrypoint with returns := .u64 }
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] invalidFtTransfer with
  | .error message =>
      require (message.contains "must have signature")
        "invalid standard ft_transfer signature must be actionable"
  | .ok _ => throw <| IO.userError "invalid standard ft_transfer signature did not fail closed"
  let transferCallAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan
      #[] ftTransferCallEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (transferCallAbi.inputCodec == .json && transferCallAbi.outputCodec == .borsh)
    "ft_transfer_call must accept standard JSON and return through its promise"
  require ((transferCallAbi.inputJson?.bind (·.root?) |>.map (fun root =>
      root.fields.map (·.wireName))) == some #["receiver_id", "amount", "memo", "msg"])
    "ft_transfer_call JSON schema must remove receiver_idx and expose memo/msg"
  require ((transferCallAbi.inputJson?.bind (·.root?) |>.bind (fun root => root.fields[2]?)
      |>.map (fun field => !field.required)) == some true)
    "ft_transfer_call memo must be optional"
  let resolverAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan
      #[] ftResolveTransferEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (resolverAbi.inputCodec == .json && resolverAbi.outputCodec == .json)
    "ft_resolve_transfer callback must use JSON object input and JSON U128 output"
  let storageDepositAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan
      nep145Structs storageDepositEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require (storageDepositAbi.inputCodec == .json && storageDepositAbi.outputCodec == .json)
    "storage_deposit must use the standard NEP-145 JSON boundary"
  require ((storageDepositAbi.inputJson?.bind (·.root?) |>.map (fun root =>
      root.fields.map (fun field => (field.wireName, field.required)))) ==
      some #[("account_id", false), ("registration_only", false)])
    "storage_deposit account_id and registration_only must both be optional"
  require ((storageDepositAbi.outputJson?.bind (·.root?) |>.map (·.kind)) == some .object)
    "storage_deposit must return a StorageBalance JSON object"
  let storageWithdrawAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan
      nep145Structs storageWithdrawEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require ((storageWithdrawAbi.inputJson?.bind (·.root?) |>.bind (fun root => root.fields[0]?)
      |>.map (·.required)) == some false)
    "storage_withdraw amount must be optional"
  let storageUnregisterAbi ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan
      nep145Structs storageUnregisterEntrypoint with
    | .ok plan => pure plan
    | .error message => throw <| IO.userError message
  require ((storageUnregisterAbi.inputJson?.bind (·.root?) |>.bind (fun root => root.fields[0]?)
      |>.map (·.required)) == some false && storageUnregisterAbi.outputCodec == .json)
    "storage_unregister force must be optional and its Bool result must use JSON"
  let aggregateSchema ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildJsonValueSchemaFromIR
      jsonSchemaStructs (.structType "StorageBalance") with
    | .ok schema => pure schema
    | .error message => throw <| IO.userError message
  require (aggregateSchema.root?.map (·.kind) == some .object)
    "JSON schema graph must represent struct outputs as objects"
  require (aggregateSchema.nodes.any fun node =>
      node.kind == .fixedArray && node.fixedLength? == some 2)
    "JSON schema graph must represent fixed-array fields"
  let aggregateReturnFunc ← match
      ProofForge.Backend.WasmHost.JsonReturn.buildReturnFuncFromIR "storage_balance_of"
        jsonSchemaStructs aggregateSchema (.structType "StorageBalance") with
    | .ok func => pure func
    | .error message => throw <| IO.userError message
  let aggregateReturnModule : ProofForge.Compiler.Wasm.Module := {
    imports := #[]
    globals := #[ProofForge.Backend.WasmHost.JsonReturn.ptrGlobalDecl]
    funcs := ProofForge.Backend.WasmHost.JsonReturn.runtimeFuncs ++ #[aggregateReturnFunc]
    memory := some { min := 1 }
    dataSegments := #[]
  }
  let aggregateReturnWat := ProofForge.Compiler.Wasm.Printer.render aggregateReturnModule
  require (aggregateReturnWat.contains "func $__pf_return_json_storage_balance_of" &&
      aggregateReturnWat.contains "call $__pf_json_return_put_u128" &&
      aggregateReturnWat.contains "call $__pf_json_return_put_bool")
    "structured JSON return lowering must encode U128 fields and fixed Bool arrays"
  let optionalSchema : ProofForge.Backend.WasmHost.AbiPlan.JsonSchemaPlan := {
    rootNode := 1
    nodes := #[
      { id := 0, kind := .string, valueType? := some .string },
      { id := 1, kind := .optional, elementNode? := some 0 }
    ]
  }
  match optionalSchema.validate with
  | .ok _ => pure ()
  | .error message => throw <| IO.userError s!"valid optional JSON schema rejected: {message}"
  let optionalInputBase ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildJsonObjectSchemaFromIR
      #[] #[("memo", .string)] with
    | .ok schema => pure schema
    | .error message => throw <| IO.userError message
  let optionalInput ← match optionalInputBase.withOptionalRootField "memo" with
    | .ok schema => pure schema
    | .error message => throw <| IO.userError message
  let some optionalRoot := optionalInput.root?
    | throw <| IO.userError "optional input schema root is missing"
  let some optionalField := optionalRoot.fields[0]?
    | throw <| IO.userError "optional input schema field is missing"
  require (!optionalField.required &&
      (optionalInput.nodes.find? (·.id == optionalField.nodeId) |>.map (·.kind)) == some .optional)
    "optional root-field planning must wrap the wire node and allow omission"
  let optionalPlan : ProofForge.Backend.WasmHost.AbiPlan.EntrypointPlan := {
    name := "optional_json_probe"
    inputCodec := .json
    outputCodec := .borsh
    params := #[{ name? := some "memo", type := .string, offset := 0, byteWidth := 0 }]
    inputByteWidth := 0
    returnType := .unit
    outputByteWidth := 0
    inputJson? := some optionalInput
  }
  let (optionalInsns, optionalLocals) ← match
      ProofForge.Backend.WasmHost.Params.loadParams #[] #[("memo", .string)] optionalPlan with
    | .ok result => pure result
    | .error error => throw <| IO.userError error.message
  let packedMemo := #[
    .localGet "memo", .load "i32.load8_u" 0,
    .localGet "memo", .i32Const 1, .plain "i32.add", .load "i32.load8_u" 0,
    .i32Const 8, .plain "i32.shl", .plain "i32.or",
    .localGet "memo", .i32Const 2, .plain "i32.add", .load "i32.load8_u" 0,
    .i32Const 16, .plain "i32.shl", .plain "i32.or"
  ]
  let optionalFunc : ProofForge.Compiler.Wasm.Func := {
    name := "optional_json_probe"
    results := #[.i32]
    locals := optionalLocals
    body := { insns := optionalInsns ++ packedMemo }
  }
  let optionalWasm : ProofForge.Compiler.Wasm.Module := {
    globals := #[ProofForge.Backend.WasmHost.ArrayHeap.arrPtrGlobalDecl 60000]
    funcs := #[
      ProofForge.Backend.WasmHost.ArrayHeap.arrAllocFunc ProofForge.IR.defaultAllocator,
      ProofForge.Backend.WasmHost.Params.parseJsonHex4Func,
      ProofForge.Backend.WasmHost.Params.writeJsonUtf8Func,
      optionalFunc
    ]
  }
  let optionalWat := ProofForge.Compiler.Wasm.Printer.render optionalWasm
  require (optionalWat.contains "call $__pf_arr_alloc" &&
      optionalWat.contains "i32.store8")
    "optional JSON string decoding must materialize owned UTF-8 bytes"
  require (optionalWat.contains "i32.const 110" &&
      optionalWat.contains "i32.const 117" && optionalWat.contains "i32.const 108")
    "optional JSON decoding must recognize the null literal"
  require (optionalWat.contains "i32.const 10" && optionalWat.contains "i32.const 92")
    "JSON string decoding must materialize newline and backslash escape cases"
  require (optionalWat.contains "func $__pf_json_parse_hex4" &&
      optionalWat.contains "func $__pf_json_write_utf8")
    "JSON string decoding must include Unicode hex and UTF-8 helpers"
  let invalidSchema := { optionalSchema with rootNode := 99 }
  match invalidSchema.validate with
  | .error message => do
      require (message.contains "root node")
        "invalid JSON schema must report its missing root"
  | .ok _ => throw <| IO.userError "JSON schema accepted a missing root"
  let aggregateCarrierPlan ← match
      ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan aggregateCarrierModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  let aggregateCarrierWat ← match
      ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan
        aggregateCarrierModule aggregateCarrierPlan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (aggregateCarrierWat.contains "func $__pf_struct_get_u128_pair" &&
      aggregateCarrierWat.contains "call $__pf_struct_get_u128_pair")
    "aggregate U128 fields must use the two-word struct carrier"
  require (aggregateCarrierWat.contains "local.get $memo_len" &&
      aggregateCarrierWat.contains "i32.store")
    "aggregate String fields must store the schema runtime (ptr,len) carrier"
  let plan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan echoModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  require (plan.entrypointAbis == #[abi]) "NearModulePlan must own the entrypoint ABI plan"
  let wat ← match ProofForge.Backend.WasmHost.NearModulePlan.renderModuleFromPlan echoModule plan with
    | .ok wat => pure wat
    | .error error => throw <| IO.userError error.message
  require (wat.contains "call $register_len") "NEAR input must inspect the host payload length"
  require (wat.contains "i64.const 8") "NEAR input must enforce the planned 8-byte payload"
  let mismatchedAbi := { abi with params := #[], inputByteWidth := 0 }
  match ProofForge.Backend.WasmHost.Params.loadParams #[] echoEntrypoint.params mismatchedAbi with
  | .error error =>
      require (error.message.contains "does not match")
        "NEAR parameter/codec plan mismatch must be actionable"
  | .ok _ => throw <| IO.userError "NEAR parameter/codec plan mismatch did not fail closed"
  let mismatchedOutput := { abi with returnType := .u32, outputByteWidth := 4 }
  let mismatchedPlan := { plan with entrypointAbis := #[mismatchedOutput] }
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan echoModule mismatchedPlan with
  | .error error =>
      require (error.message.contains "does not match its signature")
        "NEAR return codec plan mismatch must be actionable"
  | .ok _ => throw <| IO.userError "NEAR return codec plan mismatch did not fail closed"
  let wasm ← match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan echoModule plan with
    | .ok wasm => pure wasm
    | .error error => throw <| IO.userError error.message
  let call : TraceCall := { entrypoint := echoEntrypoint, args := #[.u64 42] }
  let (_, steps) ← match runTraceList wasm [call] (initialState wasm) with
    | .ok result => pure result
    | .error message => throw <| IO.userError message
  require (steps[0]?.map (fun step => step.returnValue) == some (.u64 42))
    "NEAR planned Borsh codec must round-trip a nonzero u64 result"
  let some echoFunc := findExportedFunc? wasm "echo"
    | throw <| IO.userError "missing echo export"
  let initial := initialState wasm
  let malformed := { initial with host := initial.host.beginCall #[1] }
  match evalFunc wasm echoFunc #[] defaultFuel malformed with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "NEAR ABI accepted a malformed one-byte u64 payload"
  let dynamicPlans ← match ProofForge.Backend.WasmHost.NearAbiPlan.buildModulePlans dynamicBytesModule with
    | .ok plans => pure plans
    | .error message => throw <| IO.userError message
  let some dynamicAbi := dynamicPlans[0]?
    | throw <| IO.userError "NEAR dynamic bytes plan is missing its entrypoint"
  require (dynamicPlans.size == 1 && dynamicAbi.inputByteWidth == 260 &&
      dynamicAbi.outputByteWidth == 260)
    "NEAR dynamic bytes plan must reserve a four-byte Borsh prefix plus bounded payload"
  let dynamicPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan dynamicBytesModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan dynamicBytesModule dynamicPlan with
  | .error error => throw <| IO.userError error.message
  | .ok _ => pure ()
  let mixedPlan ← match ProofForge.Backend.WasmHost.NearModulePlan.buildNearModulePlan mixedDynamicModule with
    | .ok plan => pure plan
    | .error error => throw <| IO.userError error.message
  match ProofForge.Backend.WasmHost.NearModulePlan.lowerModuleFromPlan mixedDynamicModule mixedPlan with
  | .error error =>
      require (error.message.contains "sole parameter")
        "mixed dynamic NEAR parameters must return an actionable lowering error"
  | .ok _ => throw <| IO.userError "mixed dynamic NEAR parameters did not fail closed"
  let bareCtx := { (ProofForge.Backend.WasmHost.ModuleAssembly.loweringCtxForModule echoModule .near) with
    entrypointAbis := #[] }
  match ProofForge.Backend.WasmHost.EmitWat.lowerEntrypoint bareCtx echoEntrypoint with
  | .error error =>
      require (error.message.contains "missing NEAR ABI plan")
        "a bare context with empty entrypointAbis must reject lowerEntrypoint"
  | .ok _ => throw <| IO.userError "lowerEntrypoint accepted a context with no NEAR ABI plan"
  IO.println "near-abi-plan: ok"
