import ProofForge.IR.Contract
import ProofForge.IR.Semantics
import ProofForge.Backend.Quint.ITF
import ProofForge.Backend.Quint.Model
import ProofForge.Backend.Quint.Replay

namespace ProofForge.Backend.Quint.EvmReplay

open ProofForge.IR
open ProofForge.IR.Semantics
open ProofForge.Backend.Quint
open ProofForge.Backend.Quint.Replay

structure EvmReplayError where
  message : String

structure EvmReplayConfig where
  bytecodeHex : String
  contractAddress : String := "0x1CED"
  /-- Solidity signature used to read the primary scalar state, e.g. `get()`. -/
  readSignature : String
  /-- ITF / IR state variable name checked after mutating steps, e.g. `count`. -/
  primaryStateVar : String
  /-- Optional Solidity signature for the initialize entrypoint. Defaults to
  `initialize()` (the Counter fixture shape). Modules whose `initialize` takes
  args (e.g. ValueVault's `initialize(uint256)`) override this so the init step
  encodes the args from the ITF nondet picks. -/
  initSignature : String := "initialize()"

def indent (n : Nat) (lines : List String) : String :=
  let pad := String.ofList (List.replicate n ' ')
  String.intercalate "\n" (lines.map (fun line => pad ++ line))

def itfNatValue (state : ITF.State) (varName : String) : Except EvmReplayError Nat :=
  match state.vars.find? (fun (k, _) => k == varName) with
  | some (_, .int n) => .ok n
  | some (_, v) => .error { message := s!"expected int for `{varName}` in ITF state {state.index}, got {repr v}" }
  | none => .error { message := s!"missing ITF field `{varName}` in state {state.index}" }

def solidityAbiType (t : ValueType) : Except EvmReplayError String :=
  match t with
  | .bool => .ok "bool"
  | .u8 | .u32 | .u64 | .u128 => .ok "uint256"
  | .address => .ok "address"
  | .hash => .ok "bytes32"
  | .bytes => .ok "bytes"
  | .string => .ok "string"
  | other => .error { message := s!"unsupported Solidity ABI type for EVM replay: {other.name}" }

def solidityCallSignature (ep : Entrypoint) : Except EvmReplayError String := do
  if !ep.params.isEmpty then
    let types ← ep.params.toList.mapM (fun (_, t) => solidityAbiType t)
    let typeList := String.intercalate ", " types
    .ok s!"{ep.name}({typeList})"
  else
    .ok s!"{ep.name}()"

/-- Render an IR scalar value as a Solidity literal for `abi.encodeWithSignature`.
All integer widths widen to `uint256` (the EVM ABI word width); booleans render
as `true`/`false`; addresses render as a `uint160` literal. -/
def renderSolidityArg (v : ProofForge.IR.Semantics.Value) : Except EvmReplayError String :=
  match v with
  | .u8 n | .u32 n | .u64 n | .u128 n => .ok (toString n)
  | .bool b => .ok (if b then "true" else "false")
  | .address n => .ok (toString n)
  | other => .error { message := s!"EVM replay cannot render arg literal: {repr other}" }

/-- Render the comma-separated argument literal list for an
`abi.encodeWithSignature(sig, <args...>)` call. Returns the empty string for
nullary entrypoints so the Counter path is byte-identical to the v1 renderer. -/
def renderAbiArgList (args : Array ProofForge.IR.Semantics.Value) : Except EvmReplayError String := do
  let mut out := ""
  let mut first := true
  for arg in args do
    let s ← renderSolidityArg arg
    out := if first then s else out ++ ", " ++ s
    first := false
  pure out

def renderReadAssertion (_cfg : EvmReplayConfig) (expected : Nat) : String :=
  s!"assertEq(readState(target), {expected});"

/-- Resolve the `initialize` entrypoint (if present) so init steps with args
can encode them. Counter's `initialize` is nullary; ValueVault's takes `initial`. -/
def initializeEntrypoint? (irModule : ProofForge.IR.Module) : Option Entrypoint :=
  irModule.entrypoints.find? (fun ep => ep.name == "initialize")

def renderInitStep (cfg : EvmReplayConfig) (irModule : ProofForge.IR.Module)
    (stepIdx : Nat) (expected : Nat) (picks : List (String × ITF.Value)) :
    Except EvmReplayError String := do
  let okVar := s!"initOk{stepIdx}"
  let initEp? := initializeEntrypoint? irModule
  -- If the module's `initialize` takes args, encode them from the ITF nondet
  -- picks; otherwise fall back to the configured nullary `initSignature`.
  -- The read-back assertion is the real correctness check; v1's `expected != 0`
  -- guard is dropped so modules like ValueVault (whose `initialize(initial)`
  -- sets the primary scalar to a non-zero value) render correctly. Counter's
  -- init (nullary, expected=0) renders byte-identically to the v1 path.
  let callExpr ← match initEp? with
  | some ep =>
    let args ← buildArgs ep picks |>.mapError (fun err => { message := err.message })
    let argList ← renderAbiArgList args
    let sig ← solidityCallSignature ep
    if args.isEmpty then
      .ok s!"abi.encodeWithSignature(\"{sig}\")"
    else
      .ok s!"abi.encodeWithSignature(\"{sig}\", {argList})"
  | none =>
    .ok s!"abi.encodeWithSignature(\"{cfg.initSignature}\")"
  .ok <| String.intercalate "\n" [
    s!"// step {stepIdx}: init -> {cfg.primaryStateVar} = {expected}",
    s!"(bool {okVar},) = target.call({callExpr});",
    s!"assertTrue({okVar});",
    renderReadAssertion cfg expected
  ]

def renderMutatingStep (cfg : EvmReplayConfig) (stepIdx : Nat) (ep : Entrypoint)
    (args : Array ProofForge.IR.Semantics.Value) (expected : Nat) : Except EvmReplayError String := do
  let sig ← solidityCallSignature ep
  let argList ← renderAbiArgList args
  let payload := if args.isEmpty then
    s!"abi.encodeWithSignature(\"{sig}\")"
  else
    s!"abi.encodeWithSignature(\"{sig}\", {argList})"
  let okVar := s!"callOk{stepIdx}"
  .ok <| String.intercalate "\n" [
    s!"// step {stepIdx}: {ep.name} -> {cfg.primaryStateVar} = {expected}",
    s!"(bool {okVar},) = target.call({payload});",
    s!"assertTrue({okVar});",
    renderReadAssertion cfg expected
  ]

def renderReadStep (cfg : EvmReplayConfig) (stepIdx : Nat) (ep : Entrypoint)
    (args : Array ProofForge.IR.Semantics.Value) (expected : Nat) : Except EvmReplayError String := do
  let sig ← solidityCallSignature ep
  let argList ← renderAbiArgList args
  let payload := if args.isEmpty then
    s!"abi.encodeWithSignature(\"{sig}\")"
  else
    s!"abi.encodeWithSignature(\"{sig}\", {argList})"
  let okVar := s!"readOk{stepIdx}"
  let resultVar := s!"readResult{stepIdx}"
  .ok <| String.intercalate "\n" [
    s!"// step {stepIdx}: {ep.name} (read) -> {cfg.primaryStateVar} = {expected}",
    s!"(bool {okVar}, bytes memory {resultVar}) = target.call({payload});",
    s!"assertTrue({okVar});",
    s!"assertEq(abi.decode({resultVar}, (uint256)), {expected});",
    renderReadAssertion cfg expected
  ]

def renderTraceStep (irModule : ProofForge.IR.Module) (cfg : EvmReplayConfig) (epMap : Std.HashMap String Entrypoint)
    (stepIdx : Nat) (state : ITF.State) : Except EvmReplayError String := do
  let expected ← itfNatValue state cfg.primaryStateVar
  let actionName ← resolveActionName irModule state.actionTaken state.nondetPicks
      |>.mapError (fun err => { message := err.message })
  if actionName == "init" then
    renderInitStep cfg irModule stepIdx expected state.nondetPicks
  else
    let entrypoint ← match Std.HashMap.get? epMap actionName with
      | some ep => .ok ep
      | none => .error { message := s!"unknown entrypoint `{actionName}` for EVM replay" }
    let args ← buildArgs entrypoint state.nondetPicks
      |>.mapError (fun err => { message := err.message })
    if entrypoint.returns != .unit then
      renderReadStep cfg stepIdx entrypoint args expected
    else
      renderMutatingStep cfg stepIdx entrypoint args expected

def renderTraceSteps (irModule : ProofForge.IR.Module) (cfg : EvmReplayConfig) (trace : ITF.Trace) : Except EvmReplayError String := do
  if trace.states.isEmpty then
    .error { message := "empty ITF trace" }
  let epMap := entrypointMap irModule
  let stepLines ← trace.states.tail!.mapM (fun state =>
    renderTraceStep irModule cfg epMap state.index state)
  .ok (String.intercalate "\n\n" stepLines)

def renderFoundryTest (irModule : ProofForge.IR.Module) (trace : ITF.Trace) (cfg : EvmReplayConfig) : Except EvmReplayError String := do
  let initial ← itfNatValue trace.states.head! cfg.primaryStateVar
  let steps ← renderTraceSteps irModule cfg trace
  .ok <| String.intercalate "\n" [
    "// SPDX-License-Identifier: MIT",
    "pragma solidity ^0.8.20;",
    "",
    "interface Vm {",
    "    function etch(address target, bytes calldata newRuntimeBytecode) external;",
    "}",
    "",
    "contract ProofForgeQuintEvmReplayTest {",
    "    Vm constant vm = Vm(address(uint160(uint256(keccak256(\"hevm cheat code\")))));",
    "",
    "    function assertTrue(bool value) internal pure {",
    "        require(value, \"assertTrue failed\");",
    "    }",
    "",
    "    function assertEq(uint256 actual, uint256 expected) internal pure {",
    "        require(actual == expected, \"assertEq failed\");",
    "    }",
    "",
    "    function deployRuntime(bytes memory code, address target) internal {",
    "        vm.etch(target, code);",
    "    }",
    "",
    "    function readState(address target) internal returns (uint256) {",
    "        (bool ok, bytes memory result) = target.call(abi.encodeWithSignature(\"" ++ cfg.readSignature ++ "\"));",
    "        assertTrue(ok);",
    "        return abi.decode(result, (uint256));",
    "    }",
    "",
    "    function testQuintMbtReplay() public {",
    s!"        address target = address({cfg.contractAddress});",
    s!"        deployRuntime(hex\"{cfg.bytecodeHex}\", target);",
    s!"        assertEq(readState(target), {initial});",
    "",
    indent 8 (steps.splitOn "\n"),
    "    }",
    "}"
  ]

end ProofForge.Backend.Quint.EvmReplay