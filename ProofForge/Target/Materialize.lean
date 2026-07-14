/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Target materialization report — all implemented registry targets

Product north star: authors write portable business logic; `--target` selects
a registered adapter and materializes native form. This module is the shared
product vocabulary for every **implemented** target in `Target.Registry.all`
(not only the three primary chains):

| Family | Targets | Layout |
|---|---|---|
| EVM | `evm` | contract-global slots |
| Solana | `solana-sbpf-asm` | account-data |
| Wasm host | `wasm-near`, `wasm-cosmwasm` | host KV (+ host bridge) |
| ZK sourcegen | `psy-dpn`, `aleo-leo` | circuit mapping |

Deprecated Solana routes stay importable but are not advertised.
-/
import ProofForge.IR.Contract
import ProofForge.Target.Registry
import ProofForge.Target.StorageBinding
import ProofForge.Target.HostBridge
import ProofForge.Backend.Solana.Extension.Types
import ProofForge.Backend.Solana.Materialize

namespace ProofForge.Target.Materialize

open ProofForge.IR
open ProofForge.Target

inductive Mode where
  | autoPortable
  | extensionDeclared
  deriving BEq, DecidableEq, Repr

def Mode.id : Mode → String
  | .autoPortable => "auto-portable"
  | .extensionDeclared => "extension-declared"

structure Report where
  targetId : String
  targetFamily : String
  storageBinding : String
  mode : Mode
  layoutKind : String
  hostBridge? : Option String := none
  stateUnits : Nat
  entrypointCount : Nat
  note : String
  deriving Repr

private def jsonStr (s : String) : String := "\"" ++ s ++ "\""

private def jsonOptStr : Option String → String
  | none => "null"
  | some s => jsonStr s

def Report.json (r : Report) : String :=
  "{" ++
  "\"targetId\":" ++ jsonStr r.targetId ++ "," ++
  "\"targetFamily\":" ++ jsonStr r.targetFamily ++ "," ++
  "\"storageBinding\":" ++ jsonStr r.storageBinding ++ "," ++
  "\"mode\":" ++ jsonStr r.mode.id ++ "," ++
  "\"layoutKind\":" ++ jsonStr r.layoutKind ++ "," ++
  "\"hostBridge\":" ++ jsonOptStr r.hostBridge? ++ "," ++
  "\"stateUnits\":" ++ toString r.stateUnits ++ "," ++
  "\"entrypointCount\":" ++ toString r.entrypointCount ++ "," ++
  "\"note\":" ++ jsonStr r.note ++
  "}"

/-- Base counts shared by every adapter report. -/
private def baseCounts (module : Module) : Nat × Nat :=
  (module.state.size, module.entrypoints.size)

/-- EVM: portable state → contract-global slots. Proxy pattern is extension. -/
def forEvm (module : Module) : Report :=
  let (stateUnits, entrypointCount) := baseCounts module
  let mode :=
    match module.proxyPattern? with
    | some _ => .extensionDeclared
    | none => .autoPortable
  { targetId := "evm"
    targetFamily := TargetFamily.evm.id
    storageBinding := StorageBinding.contractGlobal.id
    mode := mode
    layoutKind := "contract-global-slots"
    hostBridge? := none
    stateUnits := stateUnits
    entrypointCount := entrypointCount
    note :=
      match mode with
      | .autoPortable =>
          "EVM storage slots and ABI synthesized from portable IR (no chain DSL authoring)"
      | .extensionDeclared =>
          "EVM layout includes declared proxy/extension metadata" }

/-- Solana: portable state → default program-owned account; extensions merge PDA/CPI. -/
def forSolana (module : Module)
    (ext : ProofForge.Backend.Solana.Extension.ProgramExtensions := {})
    (targetId : String := "solana-sbpf-asm") : Report :=
  let sol := ProofForge.Backend.Solana.Materialize.report module ext
  let mode :=
    match sol.mode with
    | .autoPortable => Mode.autoPortable
    | .extensionDeclared => Mode.extensionDeclared
  { targetId := targetId
    targetFamily := TargetFamily.solana.id
    storageBinding := StorageBinding.accountData.id
    mode := mode
    layoutKind := "account-data"
    hostBridge? := none
    stateUnits := sol.stateAccountCount
    entrypointCount := module.entrypoints.size
    note := sol.note }

/-- Generic Wasm-host report driven by profile host bridge. -/
def forWasmHost (module : Module) (profile : TargetProfile) : Report :=
  let (stateUnits, entrypointCount) := baseCounts module
  let bridge? := profile.hostBridge?
  let hasNearExt :=
    !module.crosscallStrings.isEmpty ||
    module.capabilities.any (fun c => c == .nearPromise)
  let mode :=
    match bridge? with
    | some .near => if hasNearExt then Mode.extensionDeclared else Mode.autoPortable
    | _ => Mode.autoPortable
  let layoutKind :=
    match bridge? with
    | some .near => "host-key-value"
    | some .cosmWasm => "cosmwasm-storage"
    | some .soroban => "soroban-storage"
    | none =>
        "host-key-value"
  let note :=
    match bridge?, mode with
    | some .near, .autoPortable =>
        "NEAR host storage keys and imports synthesized from portable IR"
    | some .near, .extensionDeclared =>
        "NEAR layout includes Promise / host-string-pool extension surface"
    | some .cosmWasm, _ =>
        "CosmWasm host storage/msgs synthesized from portable IR (EmitWat host adapter)"
    | some .soroban, _ =>
        "Soroban host storage (_put/_get) + portable crosscall → invoke_contract (soroban-invoke)"
    | none, _ =>
        "Wasm-host layout synthesized from portable IR"
  { targetId := profile.id
    targetFamily := TargetFamily.wasmHost.id
    storageBinding := profile.storageBinding.id
    mode := mode
    layoutKind := layoutKind
    hostBridge? := bridge?.map (·.id)
    stateUnits := stateUnits
    entrypointCount := entrypointCount
    note := note }

def forWasmNear (module : Module) : Report :=
  forWasmHost module wasmNear

def forWasmCosmWasm (module : Module) : Report :=
  forWasmHost module wasmCosmWasm

/-- Soroban host adapter (profile constant; not yet in `Registry.all`). -/
def forWasmStellarSoroban (module : Module) : Report :=
  forWasmHost module wasmStellarSoroban

/-- ZK circuit / Leo sourcegen family. -/
def forZk (module : Module) (profile : TargetProfile) : Report :=
  let (stateUnits, entrypointCount) := baseCounts module
  let layoutKind :=
    match profile.id with
    | "psy-dpn" => "psy-circuit-storage"
    | "aleo-leo" => "leo-mapping-storage"
    | _ => "circuit-mapping"
  let note :=
    match profile.id with
    | "psy-dpn" =>
        "Psy/DPN circuit storage and .psy sourcegen from portable IR (restricted subset)"
    | "aleo-leo" =>
        "Aleo Leo mapping/program sourcegen from portable IR (Road 1 Counter/PureMath)"
    | _ =>
        "ZK circuit sourcegen from portable IR"
  { targetId := profile.id
    targetFamily := TargetFamily.zkCircuitSourcegen.id
    storageBinding := StorageBinding.circuitMapping.id
    mode := .autoPortable
    layoutKind := layoutKind
    hostBridge? := none
    stateUnits := stateUnits
    entrypointCount := entrypointCount
    note := note }

def forPsyDpn (module : Module) : Report := forZk module psyDpn
def forAleoLeo (module : Module) : Report := forZk module aleoLeo

/-- Dispatch for every **implemented** non-deprecated registry profile. -/
def forImplementedProfile (profile : TargetProfile) (module : Module)
    (solanaExt : ProofForge.Backend.Solana.Extension.ProgramExtensions := {}) :
    Option Report :=
  if profile.deprecated then none
  else
    match profile.id with
    | "evm" => some (forEvm module)
    | "solana-sbpf-asm" => some (forSolana module solanaExt)
    | "wasm-near" => some (forWasmNear module)
    | "wasm-cosmwasm" => some (forWasmCosmWasm module)
    | "wasm-stellar-soroban" => some (forWasmStellarSoroban module)
    | "psy-dpn" => some (forPsyDpn module)
    | "aleo-leo" => some (forAleoLeo module)
    | _ =>
        match profile.family with
        | .evm => some (forEvm module)
        | .solana => some (forSolana module solanaExt profile.id)
        | .wasmHost => some (forWasmHost module profile)
        | .zkCircuitSourcegen => some (forZk module profile)

/-- Compatibility alias for earlier primary-only callers. -/
def forPrimaryProfile (profile : TargetProfile) (module : Module)
    (solanaExt : ProofForge.Backend.Solana.Extension.ProgramExtensions := {}) :
    Option Report :=
  forImplementedProfile profile module solanaExt

/-- All active registry targets produce a materialization report for this module. -/
def reportsForAllImplemented (module : Module) : Array Report :=
  all.filterMap (fun profile => forImplementedProfile profile module)

end ProofForge.Target.Materialize
