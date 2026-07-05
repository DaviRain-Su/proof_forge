/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Shared JSON renderer for `ProofForge.Backend.Psy.Metadata` structures.
Used by the CLI `metadata` command and by `Tests/PsyMetadataExport`.
-/

import ProofForge.Backend.Psy.Metadata

namespace ProofForge.Backend.Psy.MetadataJson

open ProofForge.Backend.Psy.Metadata

def quoteString (s : String) : String :=
  "\"" ++ (s.toList.map (fun c => match c with
    | '\\' => "\\\\"
    | '"' => "\\\""
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | c => c.toString)).foldl (· ++ ·) "" ++ "\""

/-! ## Compact rendering (default) -/

def jsonArray (items : List String) : String :=
  "[" ++ ", ".intercalate items ++ "]"

def jsonObject (fields : List (String × String)) : String :=
  "{" ++ ", ".intercalate (fields.map (fun (k, v) => quoteString k ++ ": " ++ v)) ++ "}"

def renderAbiParam (p : AbiParamDescriptor) : String :=
  jsonObject [("name", quoteString p.name), ("type", quoteString p.type)]

def renderAbiEntrypoint (e : AbiEntrypointDescriptor) : String :=
  jsonObject [
    ("name", quoteString e.name),
    ("params", jsonArray (e.params.toList.map renderAbiParam)),
    ("returnType", quoteString e.returnType)
  ]

def renderAbiEventField (f : AbiEventFieldDescriptor) : String :=
  jsonObject [("name", quoteString f.name), ("type", quoteString f.type)]

def renderAbiEvent (e : AbiEventDescriptor) : String :=
  jsonObject [
    ("name", quoteString e.name),
    ("fields", jsonArray (e.fields.toList.map renderAbiEventField))
  ]

def renderContextOp (o : ContextOpDescriptor) : String :=
  jsonObject [("name", quoteString o.name)]

def renderCrosscall (c : CrosscallDescriptor) : String :=
  jsonObject [("targetContractId", quoteString c.targetContractId)]

def renderArtifactMetadata (m : ArtifactMetadata) : String :=
  jsonObject [
    ("targetId", quoteString m.targetId),
    ("moduleName", quoteString m.moduleName),
    ("entrypoints", jsonArray (m.entrypoints.toList.map renderAbiEntrypoint)),
    ("events", jsonArray (m.events.toList.map renderAbiEvent)),
    ("contextOps", jsonArray (m.contextOps.toList.map renderContextOp)),
    ("crosscalls", jsonArray (m.crosscalls.toList.map renderCrosscall)),
    ("capabilities", jsonArray (m.capabilities.toList.map quoteString))
  ]

/-! ## Pretty rendering (2-space indentation) -/

private inductive Doc
  | text (s : String)
  | line
  | nest (n : Nat) (d : Doc)
  | append (d1 d2 : Doc)

private def Doc.render (d : Doc) (indent : Nat) : String :=
  match d with
  | text s => s
  | line => "\n" ++ String.ofList (List.replicate indent ' ')
  | nest n d => Doc.render d (indent + n)
  | append d1 d2 => Doc.render d1 indent ++ Doc.render d2 indent

private def Doc.intercalate (sep : Doc) (items : List Doc) : Doc :=
  match items with
  | [] => Doc.text ""
  | [x] => x
  | x :: xs => Doc.append x (Doc.append sep (Doc.intercalate sep xs))

private def indentString (n : Nat) : String :=
  String.ofList (List.replicate n ' ')

private def jsonArrayDoc (items : List Doc) : Doc :=
  if items.isEmpty then
    Doc.text "[]"
  else
    Doc.append (Doc.text "[")
      (Doc.append
        (Doc.nest 2 (Doc.append Doc.line (Doc.intercalate (Doc.append (Doc.text ",") Doc.line) items)))
        (Doc.append Doc.line (Doc.text "]")))

private def jsonObjectDoc (fields : List (String × Doc)) : Doc :=
  if fields.isEmpty then
    Doc.text "{}"
  else
    Doc.append (Doc.text "{")
      (Doc.append
        (Doc.nest 2 (Doc.append Doc.line (Doc.intercalate (Doc.append (Doc.text ",") Doc.line) (fields.map (fun (k, v) => Doc.append (Doc.text (quoteString k ++ ": ")) v)))))
        (Doc.append Doc.line (Doc.text "}")))

private def renderAbiParamPretty (p : AbiParamDescriptor) : Doc :=
  jsonObjectDoc [("name", Doc.text (quoteString p.name)), ("type", Doc.text (quoteString p.type))]

private def renderAbiEntrypointPretty (e : AbiEntrypointDescriptor) : Doc :=
  jsonObjectDoc [
    ("name", Doc.text (quoteString e.name)),
    ("params", jsonArrayDoc (e.params.toList.map renderAbiParamPretty)),
    ("returnType", Doc.text (quoteString e.returnType))
  ]

private def renderAbiEventFieldPretty (f : AbiEventFieldDescriptor) : Doc :=
  jsonObjectDoc [("name", Doc.text (quoteString f.name)), ("type", Doc.text (quoteString f.type))]

private def renderAbiEventPretty (e : AbiEventDescriptor) : Doc :=
  jsonObjectDoc [
    ("name", Doc.text (quoteString e.name)),
    ("fields", jsonArrayDoc (e.fields.toList.map renderAbiEventFieldPretty))
  ]

private def renderContextOpPretty (o : ContextOpDescriptor) : Doc :=
  jsonObjectDoc [("name", Doc.text (quoteString o.name))]

private def renderCrosscallPretty (c : CrosscallDescriptor) : Doc :=
  jsonObjectDoc [("targetContractId", Doc.text (quoteString c.targetContractId))]

def renderArtifactMetadataPretty (m : ArtifactMetadata) : String :=
  let doc := jsonObjectDoc [
    ("targetId", Doc.text (quoteString m.targetId)),
    ("moduleName", Doc.text (quoteString m.moduleName)),
    ("entrypoints", jsonArrayDoc (m.entrypoints.toList.map renderAbiEntrypointPretty)),
    ("events", jsonArrayDoc (m.events.toList.map renderAbiEventPretty)),
    ("contextOps", jsonArrayDoc (m.contextOps.toList.map renderContextOpPretty)),
    ("crosscalls", jsonArrayDoc (m.crosscalls.toList.map renderCrosscallPretty)),
    ("capabilities", jsonArrayDoc (m.capabilities.toList.map (fun c => Doc.text (quoteString c))))
  ]
  Doc.render doc 0

end ProofForge.Backend.Psy.MetadataJson
