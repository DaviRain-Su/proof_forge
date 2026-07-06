namespace ProofForge.Backend.Evm.Names

def arrayLocalElementName (name : String) (index : Nat) : String :=
  s!"__proof_forge_array_{name}_{index}"

def arrayStructLocalFieldName (name : String) (index : Nat) (fieldName : String) : String :=
  s!"__proof_forge_array_struct_{name}_{index}_{fieldName}"

def natPathSuffix (path : Array Nat) : String :=
  Id.run do
    let mut suffix := ""
    for h : idx in [0:path.size] do
      let part := toString path[idx]
      suffix := if idx == 0 then part else s!"{suffix}_{part}"
    suffix

def arrayLocalPathName (name : String) (path : Array Nat) : String :=
  match path.toList with
  | [index] => arrayLocalElementName name index
  | _ => s!"__proof_forge_array_{name}_{natPathSuffix path}"

def arrayStructLocalPathFieldName (name : String) (path : Array Nat) (fieldName : String) : String :=
  match path.toList with
  | [index] => arrayStructLocalFieldName name index fieldName
  | _ => s!"__proof_forge_array_struct_{name}_{natPathSuffix path}_{fieldName}"

def structLocalFieldName (name fieldName : String) : String :=
  s!"__proof_forge_struct_{name}_{fieldName}"

def localArrayGetFunctionName (length : Nat) : String :=
  s!"__proof_forge_local_array_get_{length}"

def nestedLocalArrayGetFunctionName (lengths : Array Nat) : String :=
  s!"__proof_forge_local_array_get_nested_{natPathSuffix lengths}"

def localArrayGetValueParamName (index : Nat) : String :=
  s!"value_{index}"

def localArrayGetIndexParamName (index : Nat) : String :=
  s!"index_{index}"

def localArrayGetPathValueParamName (path : Array Nat) : String :=
  s!"value_{natPathSuffix path}"

partial def nestedLocalArrayLeafPaths (lengths : Array Nat) : Array (Array Nat) :=
  match lengths.toList with
  | [] => #[#[]]
  | length :: rest =>
      let nested := nestedLocalArrayLeafPaths rest.toArray
      Id.run do
        let mut paths : Array (Array Nat) := #[]
        for _h : idx in [0:length] do
          for tail in nested do
            paths := paths.push (#[idx] ++ tail)
        paths

end ProofForge.Backend.Evm.Names
