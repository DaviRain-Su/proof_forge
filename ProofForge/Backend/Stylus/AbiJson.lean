import ProofForge.Backend.Stylus.Plan

namespace ProofForge.Backend.Stylus.AbiJson

private def escape (value : String) : String :=
  value.replace "\\" "\\\\" |>.replace "\"" "\\\"" |>.replace "\n" "\\n"

partial def typeName : StylusAbiType -> String
  | .bool => "bool"
  | .uint bits => s!"uint{bits}"
  | .address => "address"
  | .fixedBytes bytes => s!"bytes{bytes}"
  | .bytes => "bytes"
  | .string => "string"
  | .fixedArray element size => s!"{typeName element}[{size}]"
  | .dynamicArray element => s!"{typeName element}[]"
  | .tuple _ => "tuple"

partial def baseTupleFields? : StylusAbiType -> Option (Array StylusAbiType)
  | .tuple fields => some fields
  | .fixedArray element _ | .dynamicArray element => baseTupleFields? element
  | _ => none

mutual
  partial def typeFields (type : StylusAbiType) : String :=
    let typeField := s!"\"type\":\"{typeName type}\""
    match baseTupleFields? type with
    | none => typeField
    | some fields =>
        let components := String.intercalate "," (fields.map tupleField).toList
        typeField ++ s!",\"components\":[{components}]"

  partial def tupleField (type : StylusAbiType) : String :=
    s!"\{{typeFields type}}"
end

private def paramJson (param : StylusAbiParamPlan) : String :=
  s!"\{\"name\":\"{escape param.name}\",{typeFields param.type}}"

private def returnJson (type : StylusAbiType) : String :=
  s!"\{{typeFields type}}"

private def methodJson (method : StylusAbiMethodPlan) : String :=
  let inputs := String.intercalate "," (method.params.map paramJson).toList
  let outputs := String.intercalate "," (method.returns.map returnJson).toList
  let mutability := if method.mutability == .view then "view"
    else if method.payable then "payable" else "nonpayable"
  s!"\{\"name\":\"{escape method.name}\",\"type\":\"function\",\"inputs\":[{inputs}],\"outputs\":[{outputs}],\"stateMutability\":\"{mutability}\"}"

def render (plan : StylusPlan) : String :=
  "[" ++ String.intercalate "," (plan.abi.methods.map methodJson).toList ++ "]"

end ProofForge.Backend.Stylus.AbiJson
