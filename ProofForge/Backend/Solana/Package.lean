/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Package Printer

Turns a lowered Solana module into the file set expected by the `sbpf`
toolchain. The core assembly still flows through `IR -> AstNode -> .s`; this
module owns the deployment-package text files around that assembly.
-/

import ProofForge.IR.Contract
import ProofForge.Contract.Spec
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Solana.Client
import ProofForge.Backend.Solana.Idl
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.Plan
import ProofForge.Util.Json

namespace ProofForge.Backend.Solana.Package

open ProofForge.IR
open ProofForge.Util.Json

structure PackageFile where
  path : String
  contents : String
  deriving Repr, Inhabited

structure RenderedPackage where
  projectName : String
  asmPath : String
  manifestPath : String
  idlPath : String
  clientPath : String
  cargoTomlPath : String
  libRsPath : String
  files : Array PackageFile
  deriving Repr, Inhabited

def asmPath (projectName : String) : String :=
  s!"src/{projectName}/{projectName}.s"

def manifestPath : String := "manifest.toml"
def idlPath : String := Idl.idlPath
def clientPath : String := Client.clientPath
def cargoTomlPath : String := "Cargo.toml"
def libRsPath : String := "src/lib.rs"

def renderCargoToml (projectName : String) : String :=
  String.intercalate "\n" [
    "[package]",
    s!"name = \"{projectName}\"",
    "version = \"0.1.0\"",
    "edition = \"2021\"",
    ""
  ]

def renderPackageWithPlan (projectName : String) (module : Module) (plan : ProofForge.Target.CapabilityPlan) :
    Except SbpfAsm.LowerError RenderedPackage := do
  let nodes ← SbpfAsm.lowerModuleWithPlan module plan
  let asm := ProofForge.Backend.Solana.Asm.renderNodes nodes
  let manifest := Manifest.renderManifestWithPlan module plan ++ "\n"
  let idl := Idl.renderWithPlan module plan ++ "\n"
  let client := Client.renderWithPlan module plan ++ "\n"
  let asmFile := asmPath projectName
  let files := #[
    { path := asmFile, contents := asm },
    { path := manifestPath, contents := manifest },
    { path := idlPath, contents := idl },
    { path := clientPath, contents := client },
    { path := cargoTomlPath, contents := renderCargoToml projectName },
    { path := libRsPath, contents := "" }
  ]
  .ok {
    projectName,
    asmPath := asmFile,
    manifestPath,
    idlPath,
    clientPath,
    cargoTomlPath,
    libRsPath,
    files
  }

/-- Render package for a module: always resolve capability plan so PDA/CPI
extensions are not dropped (unlike an empty `capPlan?` Counter-only lower). -/
def renderPackage (projectName : String) (module : Module) : Except SbpfAsm.LowerError RenderedPackage := do
  let plan ←
    match ProofForge.Target.resolveModule ProofForge.Target.solanaSbpfAsm module with
    | .ok plan => pure plan
    | .error err => .error (SbpfAsm.diagnosticError err)
  renderPackageWithPlan projectName module plan

def renderPackageForSpec (projectName : String) (spec : ProofForge.Contract.ContractSpec) :
    Except SbpfAsm.LowerError RenderedPackage := do
  let plan ←
    match ProofForge.Target.resolveSpec ProofForge.Target.solanaSbpfAsm spec with
    | .ok plan => .ok plan
    | .error err => .error (SbpfAsm.diagnosticError err)
  renderPackageWithPlan projectName spec.module plan

private def planParamEncoding
    (param : ProofForge.Backend.Solana.Plan.SolanaInstructionParamPlan) : String :=
  if param.typeName == "u64" then
    "le-u64"
  else if param.typeName == "address" || param.typeName == "hash" then
    "le-u64-identity-handle"
  else if param.typeName == "u32" then
    "le-u32"
  else if param.typeName == "bool" then
    "u8-bool"
  else
    "raw-bytes"

private def planAccountEntry
    (account : ProofForge.Backend.Solana.Plan.SolanaAccountPlan) : Manifest.AccountEntry := {
  name := account.name
  index := account.index
  signer := account.signer
  writable := account.writable
  owner := account.owner
}

private def planParamEntry
    (param : ProofForge.Backend.Solana.Plan.SolanaInstructionParamPlan) : Manifest.InstructionParamEntry := {
  name := param.name
  typeName := param.typeName
  offset := param.offset
  byteSize := param.byteSize
  encoding := planParamEncoding param
}

private def planInstructionEntry (tag : Nat)
    (entrypoint : ProofForge.Backend.Solana.Plan.SolanaEntrypointPlan) : Manifest.InstructionEntry := {
  name := entrypoint.name
  tag
  handler := "sol_" ++ entrypoint.name
  accounts := entrypoint.accounts.map planAccountEntry
  params := entrypoint.params.map planParamEntry
  minDataLen := entrypoint.instructionDataMinLen
}

def renderManifestFromPlan (plan : ProofForge.Backend.Solana.Plan.SolanaModulePlan) : String :=
  let instructions := plan.entrypoints.mapIdx planInstructionEntry
  Manifest.renderManifestWithNameAndInstructions plan.moduleName instructions ++
    Manifest.renderExtensions plan.lowerCtxSeed.extensions

private def planAccountJson
    (account : ProofForge.Backend.Solana.Plan.SolanaAccountPlan) : String :=
  jsonObject #[
    ("name", jsonString account.name),
    ("index", toString account.index),
    ("signer", jsonBool account.signer),
    ("writable", jsonBool account.writable),
    ("owner", jsonString account.owner)
  ]

private def planParamJson
    (param : ProofForge.Backend.Solana.Plan.SolanaInstructionParamPlan) : String :=
  jsonObject #[
    ("name", jsonString param.name),
    ("type", jsonString param.typeName),
    ("offset", toString param.offset),
    ("byteSize", toString param.byteSize),
    ("encoding", jsonString (planParamEncoding param))
  ]

private def planComputeBudgetJson
    (action : ProofForge.Backend.Solana.Extension.ComputeBudgetAdvice) : String :=
  Idl.computeBudgetJson action

private def planInstructionJson
    (extensions : ProofForge.Backend.Solana.Extension.ProgramExtensions)
    (tag : Nat) (entrypoint : ProofForge.Backend.Solana.Plan.SolanaEntrypointPlan) : String :=
  jsonObject #[
    ("name", jsonString entrypoint.name),
    ("tag", toString tag),
    ("handler", jsonString ("sol_" ++ entrypoint.name)),
    ("minDataLen", toString entrypoint.instructionDataMinLen),
    ("accounts", jsonArray (entrypoint.accounts.map planAccountJson)),
    ("params", jsonArray (entrypoint.params.map planParamJson)),
    ("computeBudget", jsonArray ((Idl.computeBudgetForEntrypoint extensions entrypoint.name).map
      planComputeBudgetJson)),
    ("returns", jsonString entrypoint.returns)
  ]

private def planStateJson
    (field : ProofForge.Backend.Solana.Plan.SolanaStateFieldPlan) : String :=
  jsonObject #[
    ("name", jsonString field.id),
    ("type", jsonString field.typeName),
    ("kind", jsonString field.kind),
    ("byteSize", toString field.byteSize),
    ("offset", toString field.absOff),
    ("capacity", toString field.capacity)
  ]

def renderIdlFromPlan (plan : ProofForge.Backend.Solana.Plan.SolanaModulePlan) : String :=
  let extensions := plan.lowerCtxSeed.extensions
  jsonObject #[
    ("schema", jsonString Idl.schema),
    ("name", jsonString plan.moduleName),
    ("target", jsonString plan.targetId),
    ("irVersion", jsonString plan.irVersion),
    ("capabilities", jsonStringArray #[]),
    ("structs", jsonArray #[]),
    ("state", jsonArray (plan.stateFields.map planStateJson)),
    ("instructions", jsonArray (plan.entrypoints.mapIdx (planInstructionJson extensions))),
    ("accounts", jsonArray (plan.accounts.map planAccountJson)),
    ("declaredAccounts", jsonArray (extensions.accounts.map Idl.declaredAccountJson)),
    ("allocators", jsonArray (extensions.allocators.map Idl.allocatorJson)),
    ("pdas", jsonArray (extensions.pdas.map Idl.pdaJson)),
    ("cpis", jsonArray (extensions.cpis.map Idl.cpiJson)),
    ("errors", jsonArray #[]),
    ("entrypointActions", Idl.actionsJson extensions)
  ]

def renderClientFromPlan (plan : ProofForge.Backend.Solana.Plan.SolanaModulePlan) : String :=
  Client.renderWithIdl (renderIdlFromPlan plan)

def renderPackageFromPlan (projectName : String)
    (plan : ProofForge.Backend.Solana.Plan.SolanaModulePlan) :
    Except ProofForge.Backend.Solana.SbpfAsm.LowerError RenderedPackage := do
  let nodes ← ProofForge.Backend.Solana.Plan.lowerFromPlan plan
  let asm := ProofForge.Backend.Solana.Asm.renderNodes nodes
  let asmFile := asmPath projectName
  let files := #[
    { path := asmFile, contents := asm },
    { path := manifestPath, contents := renderManifestFromPlan plan ++ "\n" },
    { path := idlPath, contents := renderIdlFromPlan plan ++ "\n" },
    { path := clientPath, contents := renderClientFromPlan plan ++ "\n" },
    { path := cargoTomlPath, contents := renderCargoToml projectName },
    { path := libRsPath, contents := "" }
  ]
  return {
    projectName,
    asmPath := asmFile,
    manifestPath,
    idlPath,
    clientPath,
    cargoTomlPath,
    libRsPath,
    files
  }

end ProofForge.Backend.Solana.Package
