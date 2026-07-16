/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Dynamic constructor probe: exercises `cstring`, `cbytes`, and `u256array`
constructor params through the EVM target.
-/
import ProofForge.Contract.Source

namespace DynamicConstructorProbe

open ProofForge.Contract.Source

namespace Core
contract_source DynamicConstructorProbe do
  constructor_param name : "cstring";
  constructor_param payload : "cbytes";
  constructor_param amounts : "u256array";

  state nameLen : .u64
  state nameHash : .hash
  state payloadLen : .u64
  state payloadHash : .hash
  state amountCount : .u64
  state amountSum : .u64

  query getNameLen returns(.u64) do
    return nameLen;

  query getNameHash returns(.hash) do
    return nameHash;

  query getPayloadLen returns(.u64) do
    return payloadLen;

  query getPayloadHash returns(.hash) do
    return payloadHash;

  query getAmountCount returns(.u64) do
    return amountCount;

  query getAmountSum returns(.u64) do
    return amountSum;

end Core

def spec : ProofForge.Contract.ContractSpec :=
  { Core.spec with
    constructorInitBindings := #[
      { stateId := "nameLen", paramName := "name", kind := .stringLength },
      { stateId := "nameHash", paramName := "name", kind := .stringKeccak },
      { stateId := "payloadLen", paramName := "payload", kind := .bytesLength },
      { stateId := "payloadHash", paramName := "payload", kind := .bytesKeccak },
      { stateId := "amountCount", paramName := "amounts", kind := .arrayLength },
      { stateId := "amountSum", paramName := "amounts", kind := .arraySumU64 }
    ]
  }

def module : ProofForge.IR.Module :=
  spec.module

end DynamicConstructorProbe
