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

end ProofForge.Backend.Psy.MetadataJson
