import Lean
import ProofForgeV2.Core.Source

open Lean

namespace ProofForgeV2.Language.ProgramExport

structure ProgramExportV1 where
  schema : String
  declaration : Name
  deriving BEq, Repr, Inhabited

def programExportSchemaV1 : String := "proof-forge.program-export.v1"

private def exportNameLt (left right : ProgramExportV1) : Bool :=
  left.declaration.toString < right.declaration.toString

/-- Validate schemas, reject structural/string duplicates, then sort by FQN string. -/
def normalizeProgramExports (entries : Array ProgramExportV1) :
    Except String (Array ProgramExportV1) := do
  let mut seenNames : Array Name := #[]
  let mut seenStrings : Array String := #[]
  for entry in entries do
    unless entry.schema == programExportSchemaV1 do
      throw "PF-EXPORT-001: unknown program export schema"
    if seenNames.contains entry.declaration then
      throw "PF-EXPORT-001: duplicate program export declaration"
    let rendered := entry.declaration.toString
    if seenStrings.contains rendered then
      throw "PF-EXPORT-001: conflicting program export name"
    seenNames := seenNames.push entry.declaration
    seenStrings := seenStrings.push rendered
  pure (entries.qsort exportNameLt)

initialize programExportExt :
    SimplePersistentEnvExtension ProgramExportV1 (Array ProgramExportV1) ←
  registerSimplePersistentEnvExtension {
    name := `ProofForgeV2.Language.ProgramExport.programExportExt
    addEntryFn := fun state entry => state.push entry
    addImportedFn := fun modules => modules.flatten
    toArrayFn := fun entries => entries.toArray
  }

/-- Merge imported and local registry rows, then normalize. -/
def programExports (env : Environment) : Except String (Array ProgramExportV1) :=
  normalizeProgramExports (programExportExt.getState env)

private def ensureProgramType (decl : Name) : AttrM Unit := do
  let info ← getConstInfo decl
  let expected := mkConst ``ProofForgeV2.Source.Program
  unless info.type == expected do
    throwError
      "attribute [proof_forge_program] requires type ProofForgeV2.Source.Program"

private def ensureExportable (env : Environment) (decl : Name) : AttrM Unit := do
  let rendered := decl.toString
  for entry in programExportExt.getState env do
    if entry.declaration == decl then
      throwError "PF-EXPORT-001: duplicate program export declaration"
    if entry.declaration.toString == rendered then
      throwError "PF-EXPORT-001: conflicting program export name"

initialize registerBuiltinAttribute {
  name := `proof_forge_program
  descr := "marks a ProofForge Source.Program for environment export"
  applicationTime := .afterTypeChecking
  add := fun decl stx kind => do
    Attribute.Builtin.ensureNoArgs stx
    unless kind == AttributeKind.global do
      throwAttrMustBeGlobal `proof_forge_program kind
    let env ← getEnv
    unless (env.getModuleIdxFor? decl).isNone do
      throwAttrDeclInImportedModule `proof_forge_program decl
    ensureAttrDeclIsPublic `proof_forge_program decl kind
    ensureProgramType decl
    ensureExportable env decl
    let entry : ProgramExportV1 := {
      schema := programExportSchemaV1
      declaration := decl
    }
    modifyEnv fun env => programExportExt.addEntry env entry
}

end ProofForgeV2.Language.ProgramExport
