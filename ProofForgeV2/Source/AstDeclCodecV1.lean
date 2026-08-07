import ProofForgeV2.Core.Common
import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstSupportCodecV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstDeclCodecV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstSupportCodecV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireCodecV1

private def fail (detail : String) : Except String α :=
  .error detail

private def verErr := "extension version must use canonical exact SemVer"
private def digErr := "extension digest must use canonical sha256 spelling"
private def structEmptyErr := "struct fields must be nonempty"
private def enumEmptyErr := "enum variants must be nonempty"

private def requireCanonicalExtensionVersion (version : String) : Except String Unit :=
  match parseSemVer version with
  | .error _ => fail verErr
  | .ok parsed =>
    match renderSemVer parsed with
    | .error _ => fail verErr
    | .ok canon =>
        unless canon == version do
          return ← fail verErr

private def requireCanonicalExtensionDigest (digest : String) : Except String Unit :=
  match parseDigest digest with
  | .error _ => fail digErr
  | .ok parsed =>
    match renderDigest parsed with
    | .error _ => fail digErr
    | .ok canon =>
        unless canon == digest do
          return ← fail digErr

def encodeStateDeclV1 (d : StateDeclV1) : Except String ByteArray := do
  let vis ← encodeVisibilityV1 d.visibility
  let name ← encodeSourceNameComponentV1 d.name
  let ty ← encodeTypeV1 d.type_
  encodeTagged "StateDecl" #[vis, name, ty]

def encodeStructDeclV1 (d : StructDeclV1) : Except String ByteArray := do
  unless d.fields.size ≥ 1 do
    return ← fail structEmptyErr
  let name ← encodeSourceNameComponentV1 d.name
  let fields ← encodeArray encodeFieldDeclV1 d.fields
  encodeTagged "StructDecl" #[name, fields]

def encodeEnumDeclV1 (d : EnumDeclV1) : Except String ByteArray := do
  unless d.variants.size ≥ 1 do
    return ← fail enumEmptyErr
  let name ← encodeSourceNameComponentV1 d.name
  let variants ← encodeArray encodeEnumVariantV1 d.variants
  encodeTagged "EnumDecl" #[name, variants]

def encodeEventDeclV1 (d : EventDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let params ← encodeArray encodeParamV1 d.params
  encodeTagged "EventDecl" #[name, params]

def encodeErrorDeclV1 (d : ErrorDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let params ← encodeArray encodeParamV1 d.params
  encodeTagged "ErrorDecl" #[name, params]

def encodeExtensionReqV1 (d : ExtensionReqV1) : Except String ByteArray := do
  let idB ← encodeSourceQualifiedIdV1 d.id
  requireCanonicalExtensionVersion d.version
  requireCanonicalExtensionDigest d.digest
  let verB ← encodeString d.version
  let digB ← encodeString d.digest
  encodeTagged "ExtensionReq" #[idB, verB, digB]

def encodeProofDeclV1 (d : ProofDeclV1) : Except String ByteArray := do
  let inv ← encodeSourceNameComponentV1 d.invariant
  let kind ← encodeProofKindV1 d.kind
  let thm ← encodeSourceQualifiedIdV1 d.theorem_
  encodeTagged "ProofDecl" #[inv, kind, thm]

end ProofForgeV2.Source.AstDeclCodecV1
