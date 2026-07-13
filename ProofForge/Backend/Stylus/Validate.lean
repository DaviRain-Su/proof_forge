/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.Plan

namespace ProofForge.Backend.Stylus

structure PlanError where
  message : String
  deriving Repr, BEq

inductive RendererKind where
  | rustSdk
  | directWasm
  deriving Repr, BEq, DecidableEq

def RendererKind.id : RendererKind -> String
  | .rustSdk => "rust-sdk"
  | .directWasm => "direct-wasm"

private def fail (message : String) : Except PlanError α :=
  .error { message }

partial def validateAbiType : StylusAbiType -> Except PlanError Unit
  | .bool | .address | .bytes | .string => pure ()
  | .uint bits =>
      unless StylusAbiType.validUintBits.contains bits do
        fail s!"Stylus plan has unsupported ABI type uint{bits}"
  | .fixedBytes bytes =>
      unless bytes >= 1 && bytes <= 32 do
        fail s!"Stylus plan has unsupported ABI type bytes{bytes}"
  | .fixedArray elem size => do
      if size == 0 then fail "Stylus fixed array size must be positive"
      validateAbiType elem
  | .dynamicArray elem => validateAbiType elem
  | .tuple fields =>
      fields.forM validateAbiType

private def validateSupportEntry (renderer : RendererKind) (owner : String)
    (support : RendererSupportPlan) : Except PlanError Unit := do
  let state := match renderer with
    | .rustSdk => support.rustSdk
    | .directWasm => support.directWasm
  match state with
  | .implemented => pure ()
  | .planned => fail s!"Stylus {owner} has no implemented handler for renderer {renderer.id}"
  | .unsupported reason =>
      fail s!"Stylus {owner} is unsupported by renderer {renderer.id}: {reason}"

def validatePlan (plan : StylusPlan) : Except PlanError Unit := do
  unless plan.targetId == "wasm-arbitrum-stylus" do
    fail s!"Stylus plan has wrong target `{plan.targetId}`"
  if plan.moduleName.isEmpty then fail "Stylus plan module name is empty"
  if plan.resources.maxMemoryPages == 0 then
    fail "Stylus plan maxMemoryPages must be positive"
  for method in plan.abi.methods do
    unless method.selector.size == 4 do
      fail s!"Stylus ABI method `{method.name}` selector must be four bytes"
    for param in method.params do validateAbiType param.type
    for type in method.returns do validateAbiType type
  for error in plan.abi.errors do
    unless error.selector.size == 4 do
      fail s!"Stylus ABI error `{error.name}` selector must be four bytes"
    for param in error.params do validateAbiType param.type
  for word in plan.storage.words do
    validateAbiType word.type
    for keyType in word.keyTypes do
      validateAbiType keyType
      if keyType == .bytes || keyType == .string then
        fail s!"Stylus mapping `{word.id}` dynamic keys must be pre-hashed by the plan"
    if word.byteWidth == 0 || word.byteWidth > 32 then
      fail s!"Stylus storage word `{word.id}` has invalid byte width {word.byteWidth}"
    if word.byteOffset + word.byteWidth > 32 then
      fail s!"Stylus storage word `{word.id}` exceeds its 32-byte slot"
    match word.slot with
    | .literal bytes =>
        unless bytes.size == 32 do
          fail s!"Stylus storage word `{word.id}` literal slot must be 32 bytes"
    | _ => pure ()
  for event in plan.events do
    let indexed := event.fields.filter (fun field => field.indexed)
    if indexed.size > 3 then
      fail s!"Stylus event `{event.id}` exceeds the four-topic EVM limit"
    for field in event.fields do
      validateAbiType field.type
      if field.indexed && (field.type == .bytes || field.type == .string) then
        fail s!"Stylus event `{event.id}` dynamic indexed field `{field.name}` must be pre-hashed"
  for call in plan.calls do
    if call.canonicalSignature.isEmpty then fail s!"Stylus call `{call.id}` has an empty signature"
    if call.arguments.size != call.paramTypes.size then
      fail s!"Stylus call `{call.id}` argument/type arity mismatch"
    for type in call.paramTypes do validateAbiType type
    validateAbiType call.returnType
    if call.returnType.isDynamic then
      match call.returnMaxLength? with
      | some maximum =>
          if maximum == 0 || maximum > 4096 then
            fail s!"Stylus call `{call.id}` has invalid dynamic return maximum {maximum}"
      | none => fail s!"Stylus call `{call.id}` dynamic return has no maximum length"
    else if call.returnMaxLength?.isSome then
      fail s!"Stylus call `{call.id}` static return has a dynamic maximum length"
    if call.value?.isSome != call.valueType?.isSome then
      fail s!"Stylus call `{call.id}` value id/type mismatch"
    if let some type := call.valueType? then
      if call.mode != .call then
        fail s!"Stylus call `{call.id}` value is only valid for call mode"
      match type with
      | .uint 64 | .uint 128 | .uint 256 => pure ()
      | _ => fail s!"Stylus call `{call.id}` has unsupported value type {repr type}"
    match call.mode, call.cachePolicy with
    | .staticCall, .flush => pure ()
    | .call, .clear | .delegateCall, .clear => pure ()
    | .staticCall, _ => fail s!"Stylus static call `{call.id}` requires flush cache policy"
    | _, _ => fail s!"Stylus call `{call.id}` requires clear cache policy"
  for function in plan.functions do
    let some method := plan.abi.methods.find? (fun method => method.name == function.abiMethod)
      | fail s!"Stylus function `{function.id}` references missing ABI method `{function.abiMethod}`"
    unless function.params.map (fun param => (param.name, param.type)) ==
        method.params.map (fun param => (param.name, param.type)) do
      fail s!"Stylus function `{function.id}` parameters do not match its ABI method"
    for param in function.params do
      if param.type.isDynamic then
        match param.dynamicMaxLength? with
        | some maximum => if maximum == 0 then fail s!"Stylus dynamic parameter `{param.name}` has zero maximum length"
        | none => fail s!"Stylus dynamic parameter `{param.name}` has no maximum length"
      else if param.dynamicMaxLength?.isSome then
        fail s!"Stylus scalar parameter `{param.name}` has a dynamic length policy"
    let hasCall := function.blocks.any fun block => block.operations.any fun operation =>
      match operation with | .call .. => true | _ => false
    if hasCall && !plan.hostOps.any (fun op => op.functionId == function.id && op.operation == .storageFlush) then
      fail s!"Stylus calling function `{function.id}` has no pre-call storageFlush HostOp"
    unless function.params.map (fun param => param.valueId) |>.toList.Pairwise (· != ·) do
      fail s!"Stylus function `{function.id}` has duplicate parameter value ids"
  if plan.resources.requiresStorageFlush &&
      !plan.hostOps.any (fun op => op.operation == .storageFlush) then
    fail "Stylus mutating plan requires storage flush but has no storageFlush HostOp"

def validateForRenderer (renderer : RendererKind) (plan : StylusPlan) : Except PlanError Unit := do
  validatePlan plan
  for function in plan.functions do
    validateSupportEntry renderer s!"function `{function.id}`" function.support
  for event in plan.events do
    validateSupportEntry renderer s!"event `{event.id}`" event.support
  for call in plan.calls do
    validateSupportEntry renderer s!"call `{call.id}`" call.support
  for hostOp in plan.hostOps do
    validateSupportEntry renderer s!"HostOp `{hostOp.id}`" hostOp.support

end ProofForge.Backend.Stylus
