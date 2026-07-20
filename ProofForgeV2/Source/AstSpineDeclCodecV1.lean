import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstSpineCodecV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.AstSupportCodecV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.WireCodecV1

namespace ProofForgeV2.Source.AstSpineDeclCodecV1

open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstSpineCodecV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSupportCodecV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.WireCodecV1

def encodeConstDeclV1 (d : ConstDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let ty ← encodeTypeV1 d.type_
  let value ← encodeExprV1 d.value
  encodeTagged "ConstDecl" #[name, ty, value]

def encodeInvariantDeclV1 (d : InvariantDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let pred ← encodeExprV1 d.predicate
  encodeTagged "InvariantDecl" #[name, pred]

def encodeInitDeclV1 (d : InitDeclV1) : Except String ByteArray := do
  let params ← encodeArray encodeParamV1 d.params
  let body ← encodeBlockV1 d.body
  encodeTagged "InitDecl" #[params, body]

def encodeEntryDeclV1 (d : EntryDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let params ← encodeArray encodeParamV1 d.params
  let result ← encodeTypeV1 d.result
  let body ← encodeBlockV1 d.body
  encodeTagged "EntryDecl" #[name, params, result, body]

def encodeViewDeclV1 (d : ViewDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let params ← encodeArray encodeParamV1 d.params
  let result ← encodeTypeV1 d.result
  let body ← encodeBlockV1 d.body
  encodeTagged "ViewDecl" #[name, params, result, body]

def encodeFnDeclV1 (d : FnDeclV1) : Except String ByteArray := do
  let name ← encodeSourceNameComponentV1 d.name
  let params ← encodeArray encodeParamV1 d.params
  let result ← encodeTypeV1 d.result
  let body ← encodeBlockV1 d.body
  encodeTagged "FnDecl" #[name, params, result, body]

end ProofForgeV2.Source.AstSpineDeclCodecV1
