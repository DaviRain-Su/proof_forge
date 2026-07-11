/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Build canonical ERC-20 `ContractSpec` values from Lean `TokenSpec` metadata.

When `permit` is enabled, merges EIP-2612 entrypoints/state from
`Stdlib.ERC20Permit` (ecrecover + EIP-712 digest) onto the ERC-20 body.
-/
import ProofForge.Contract.Token
import ProofForge.Contract.Stdlib.ERC20
import ProofForge.Contract.Stdlib.ERC20Permit
import ProofForge.Contract.Compose
import ProofForge.IR.Contract

namespace ProofForge.Contract.Token.EvmSpec

open ProofForge.Contract.Token
open ProofForge.Contract.Stdlib.ERC20
open ProofForge.IR

def fungibleSpec : ProofForge.Contract.ContractSpec := spec

private def keepEntrypoint (token : TokenSpec) (entrypoint : Entrypoint) : Bool :=
  entrypoint.name != "init" &&
    (entrypoint.name != "mint" || token.hasFeature .mintable) &&
    (entrypoint.name != "burn" || token.hasFeature .burnable)

private def canonicalSelector? (name : String) : Option String :=
  match name with
  | "totalSupply" => some "18160ddd"
  | "decimals" => some "313ce567"
  | "balanceOf" => some "70a08231"
  | "allowance" => some "dd62ed3e"
  | "transfer" => some "a9059cbb"
  | "approve" => some "095ea7b3"
  | "transferFrom" => some "23b872dd"
  | "mint" => some "40c10f19"
  | "burn" => some "42966c68"
  | "permit" => some "d505accf"
  | "nonces" => some "7ecebe00"
  | "DOMAIN_SEPARATOR" => some "3644e515"
  | "initDomain" => some "3c0ad216"
  | _ => none

def withCanonicalSelectors (module : Module) : Module :=
  { module with
    entrypoints := module.entrypoints.map fun entrypoint =>
      { entrypoint with selector? := canonicalSelector? entrypoint.name } }

/-- Permit-only slice: state + entrypoints not already on base ERC-20. -/
def permitAddonModule : Module :=
  let m := ProofForge.Contract.Stdlib.ERC20Permit.module
  let permitStateIds : Array String :=
    #["nonces", "domainSeparator"]
  let permitEntryNames : Array String :=
    #["nonces", "DOMAIN_SEPARATOR", "initDomain", "permit"]
  {
    name := "ERC20PermitAddon"
    state := m.state.filter (fun s => permitStateIds.contains s.id)
    entrypoints := m.entrypoints.filter (fun e => permitEntryNames.contains e.name)
  }

def baseModuleFor (token : TokenSpec) : Module :=
  { fungibleSpec.module with
    name := token.symbol
    entrypoints := fungibleSpec.module.entrypoints.filter (keepEntrypoint token) }

def moduleFor (token : TokenSpec) : Module :=
  let base := baseModuleFor token
  let merged :=
    if token.hasFeature .permit then
      ProofForge.Contract.Compose.mergeModules token.symbol base permitAddonModule
    else
      base
  withCanonicalSelectors merged

def specFor (token : TokenSpec) : ProofForge.Contract.ContractSpec :=
  { fungibleSpec with
    name := token.symbol
    module := moduleFor token }

end ProofForge.Contract.Token.EvmSpec
