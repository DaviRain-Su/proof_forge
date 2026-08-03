import Lean
import Std.Data.HashMap
import ProofForgeV2.Source.AstCanonicalRootDecodeV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.ValidatedSourceV1

open Lean
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Language.ProgramExport

deriving instance Repr for ByteArray

private def hexDigitToNat (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

private def byteArrayFromHex (hex : String) : Except String ByteArray := do
  unless hex.length % 2 == 0 do
    throw "hex string must have even length"
  let chars := hex.toList
  let rec loop (acc : ByteArray) (cs : List Char) : Except String ByteArray :=
    match cs with
    | [] => pure acc
    | high :: low :: rest =>
        match hexDigitToNat high, hexDigitToNat low with
        | some h, some l => loop (acc.push (UInt8.ofNat (h * 16 + l))) rest
        | _, _ => throw "invalid hex character"
    | [_] => throw "hex string must have even length"
  loop ByteArray.empty chars

/-- Transparent hex → bytes used by ProgramExport payloads and inline proof
    subjects. Expression-level reconstruction still prefers `decodeByteArray`
    on the hex argument; runtime evaluation now recovers exact product bytes
    (required for inline `subjectProgramV1` validation and proof linkage).
    Invalid hex fails closed to empty rather than inventing non-canonical data. -/
def programExportBytesFromHex (hex : String) : ByteArray :=
  match byteArrayFromHex hex with
  | .ok bytes => bytes
  | .error _ => ByteArray.empty

structure ProgramExportPayloadV2 where
  schema : String
  bytes : ByteArray
  deriving BEq, Repr, Inhabited

structure ProgramExportV2 where
  schema : String
  declaration : Name
  deriving BEq, Repr, Inhabited

def programExportSchemaV2 : String := "proof-forge.program-export.v2"

private def exportError (detail : String) : String :=
  s!"PF-EXPORT-004: {detail}"

private def identityError (detail : String) : String :=
  s!"PF-EXPORT-001: {detail}"

private def unsupported {α : Type} : Except String α :=
  .error (exportError "unsupported ProgramExportPayloadV2 form")

private def unavailable {α : Type} : Except String α :=
  .error (exportError "declaration unavailable or unsafe")

private def maxRawNodes : Nat := 100000
private def maxLogicalDepth : Nat := 256

private def isPolymorphicWrapper (name : Name) : Bool :=
  name == ``List.toArray || name == ``List.nil || name == ``List.cons ||
    name == ``Option.none || name == ``Option.some || name == ``OfNat.ofNat

private def hasExactLevels (name : Name) (levels : List Level) : Bool :=
  if isPolymorphicWrapper name then levels == [Level.zero] else levels.isEmpty

private def appView (expr : Expr) : Option (Name × List Expr) :=
  match expr with
  | .mdata .. => none
  | _ =>
    match expr.getAppFn with
    | .const name levels =>
        if hasExactLevels name levels then some (name, expr.getAppArgs.toList) else none
    | _ => none

private def checkRawNodeBound (root : Expr) : Except String Unit := do
  let mut stack := #[root]
  let mut count := 0
  while !stack.isEmpty do
    let expr := stack.back!
    stack := stack.pop
    count := count + 1
    if count > maxRawNodes then
      return ← .error (exportError "program payload structural bound exceeded")
    match expr with
    | .app fn arg => stack := stack.push fn |>.push arg
    | .lam _ type body _ | .forallE _ type body _ =>
        stack := stack.push type |>.push body
    | .letE _ type value body _ =>
        stack := stack.push type |>.push value |>.push body
    | .mdata _ body => stack := stack.push body
    | .proj _ _ struct => stack := stack.push struct
    | _ => pure ()

private def decodeRawNat (expr : Expr) : Except String Nat :=
  match expr with
  | .lit (.natVal value) => pure value
  | _ => unsupported

private def decodeNat (expr : Expr) : Except String Nat := do
  match expr with
  | .lit (.natVal value) => pure value
  | _ =>
      match appView expr with
      | some (``OfNat.ofNat, [type, literal, instanceExpr]) =>
          unless type.consumeMData == mkConst ``Nat do
            return ← unsupported
          let value ← decodeRawNat literal
          match appView instanceExpr with
          | some (``instOfNatNat, [sameLiteral]) =>
              unless (← decodeRawNat sameLiteral) == value do
                return ← unsupported
              pure value
          | _ => unsupported
      | _ => unsupported

private def decodeUInt8 (expr : Expr) : Except String UInt8 := do
  match appView expr with
  | some (``UInt8.ofNat, [valueExpr]) =>
      let value ← decodeNat valueExpr
      if value < 2 ^ 8 then pure (UInt8.ofNat value) else unsupported
  | _ => unsupported

private def decodeString (expr : Expr) : Except String String :=
  match expr with
  | .lit (.strVal value) => pure value
  | _ => unsupported

private def decodeArray (decode : Expr → Except String α) (expr : Expr) :
    Except String (Array α) := do
  let rest0 ← match appView expr with
    | some (``List.toArray, [_type, list]) => pure list
    | _ => unsupported
  let mut rest := rest0
  let mut result := #[]
  let mut done := false
  while !done do
    match appView rest with
    | some (``List.nil, [_type]) => done := true
    | some (``List.cons, [_type, head, tail]) =>
        result := result.push (← decode head)
        rest := tail
    | _ => return ← unsupported
  pure result

private partial def decodeByteArray (expr : Expr) : Except String ByteArray := do
  match appView expr with
  | some (``programExportBytesFromHex, [hexExpr]) =>
      byteArrayFromHex (← decodeString hexExpr)
  | some (``ByteArray.empty, []) => pure ByteArray.empty
  | some (``ByteArray.push, [arrExpr, byteExpr]) => do
      let arr ← decodeByteArray arrExpr
      let byte ← decodeUInt8 byteExpr
      pure (arr.push byte)
  | some (``ByteArray.mk, [data]) =>
      ByteArray.mk <$> decodeArray decodeUInt8 data
  | _ => unsupported

private def decodePayloadV2 (expr : Expr) : Except String ProgramExportPayloadV2 := do
  match appView expr with
  | some (``ProgramExportPayloadV2.mk, [schemaExpr, bytesExpr]) =>
      let schema ← decodeString schemaExpr
      let bytes ← decodeByteArray bytesExpr
      pure { schema, bytes }
  | _ => unsupported

private def declarationRawComponents (decl : Name) : Except String (Array String) := do
  let qn ← sourceQualifiedNameV1FromLeanName decl
  let components := NonEmptyArray.toArray qn.components
  pure (components.map (·.raw))

private def declarationNameComponents (decl : Name) :
    Except String (Array SourceNameComponentV1) := do
  let qn ← sourceQualifiedNameV1FromLeanName decl
  pure (NonEmptyArray.toArray qn.components)

private def checkProgramIdentity
    (decl : Name) (source : ValidatedSourceV1) : Except String Unit := do
  let declComponents ← declarationNameComponents decl
  let expectedIdentity ← sourceQualifiedNameV1OfComponents declComponents
  unless expectedIdentity == source.programIdentity do
    throw (identityError "exported program identity does not match declaration")

/-- Reconstruct a single registered v2 payload.

Bounded-exhaustively decodes the attributed constant's scalar/ByteArray
expression, then calls ONLY `decodeCanonicalSourceAstBytesV1`. v1 rows,
non-`ProgramExportPayloadV2` types, and malformed expressions are rejected
with PF-EXPORT-001/004. -/
def programPayloadV2 (env : Environment) (name : Name) :
    Except String ValidatedSourceV1 := do
  match env.find? name with
  | some (.defnInfo info) =>
      unless info.type == mkConst ``ProgramExportPayloadV2 do
        return ← unavailable
      match info.safety with
      | .safe => pure ()
      | _ => return ← unavailable
      unless (Lean.Compiler.getImplementedBy? env name).isNone do
        return ← unavailable
      unless (Lean.getExternAttrData? env name).isNone do
        return ← unavailable
      checkRawNodeBound info.value
      if env.hasUnsafe info.value then
        return ← unavailable
      let payload ← decodePayloadV2 info.value
      unless payload.schema == programExportSchemaV2 do
        throw (identityError "unknown program export schema")
      let source ← decodeCanonicalSourceAstBytesV1 payload.bytes
      checkProgramIdentity name source
      pure source
  | _ => unavailable

private def checkProgramIdentities
    (rows : Array (ProgramExportV2 × ValidatedSourceV1)) : Except String Unit := do
  let mut seen := Std.HashMap.emptyWithCapacity rows.size
  for (_, source) in rows do
    let identityKey := (NonEmptyArray.toArray source.programIdentity.components).map (·.raw)
    let digest ← match sourceHashV1 source with
      | .ok digest => pure digest
      | .error message => throw (exportError message)
    let (previous, updated) := seen.getThenInsertIfNew? identityKey digest
    seen := updated
    match previous with
    | none => pure ()
    | some previousHash =>
        if previousHash == digest then
          throw (identityError "duplicate exported program identity")
        else
          throw (identityError "conflicting exported program identity")

private def arrayLt (left right : Array String) : Bool :=
  decide (left.toList < right.toList)

private def exportNameLt (left right : ProgramExportV2) : Bool :=
  match declarationRawComponents left.declaration,
        declarationRawComponents right.declaration with
  | .ok leftComponents, .ok rightComponents => arrayLt leftComponents rightComponents
  | _, _ => false

/-- Validate schemas, reject structural/string duplicates, then sort by raw
component order. -/
def normalizeProgramExports (entries : Array ProgramExportV2) :
    Except String (Array ProgramExportV2) := do
  let mut seenNames : Array Name := #[]
  let mut seenKeys : Array (Array String) := #[]
  for entry in entries do
    unless entry.schema == programExportSchemaV2 do
      throw (identityError "unknown program export schema")
    if seenNames.contains entry.declaration then
      throw (identityError "duplicate program export declaration")
    let key ← match declarationRawComponents entry.declaration with
      | .ok components => pure components
      | .error message => throw (identityError message)
    if seenKeys.contains key then
      throw (identityError "conflicting exported program identity")
    seenNames := seenNames.push entry.declaration
    seenKeys := seenKeys.push key
  pure (entries.qsort exportNameLt)

initialize programExportExt :
    SimplePersistentEnvExtension ProgramExportV2 (Array ProgramExportV2) ←
  registerSimplePersistentEnvExtension {
    name := `ProofForgeV2.Language.ProgramExport.programExportExt
    addEntryFn := fun state entry => state.push entry
    addImportedFn := fun modules => modules.flatten
    toArrayFn := fun entries => entries.toArray
  }

/-- Merge imported and local registry rows, then normalize. -/
def programExports (env : Environment) : Except String (Array ProgramExportV2) :=
  normalizeProgramExports (programExportExt.getState env)

/-- Reconstruct every registered v2 payload, detecting duplicate/conflicting
raw-component identities and malformed v2 rows. -/
def programPayloadsV2 (env : Environment) :
    Except String (Array (ProgramExportV2 × ValidatedSourceV1)) := do
  let exports ← programExports env
  let mut rows := #[]
  for row in exports do
    rows := rows.push (row, ← programPayloadV2 env row.declaration)
  checkProgramIdentities rows
  pure rows

private def ensureProgramType (decl : Name) : AttrM Unit := do
  let info ← getConstInfo decl
  let expected := mkConst ``ProofForgeV2.Language.ProgramExport.ProgramExportPayloadV2
  unless info.type == expected do
    throwError
      "attribute [proof_forge_program] requires type ProofForgeV2.Language.ProgramExport.ProgramExportPayloadV2"

private def ensureExportable (env : Environment) (decl : Name) : AttrM Unit := do
  let key ← match declarationRawComponents decl with
    | .ok components => pure components
    | .error message => throwError "PF-EXPORT-001: {message}"
  for entry in programExportExt.getState env do
    if entry.declaration == decl then
      throwError "PF-EXPORT-001: duplicate program export declaration"
    match declarationRawComponents entry.declaration with
    | .ok entryKey =>
        if entryKey == key then
          throwError "PF-EXPORT-001: conflicting exported program identity"
    | .error _ => pure ()

initialize registerBuiltinAttribute {
  name := `proof_forge_program
  descr := "marks a ProofForge ProgramExportPayloadV2 for environment export"
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
    let entry : ProgramExportV2 := {
      schema := programExportSchemaV2
      declaration := decl
    }
    modifyEnv fun env => programExportExt.addEntry env entry
}

end ProofForgeV2.Language.ProgramExport
