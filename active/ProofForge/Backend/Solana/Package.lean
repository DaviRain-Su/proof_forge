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

namespace ProofForge.Backend.Solana.Package

open ProofForge.IR

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

end ProofForge.Backend.Solana.Package
