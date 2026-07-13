/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.RustSdk.AST
import ProofForge.Backend.Stylus.Validate

namespace ProofForge.Backend.Stylus.RustSdk

open ProofForge.Backend.Stylus

structure RenderError where
  message : String
  deriving Repr, BEq

private def fail (message : String) : Except RenderError α :=
  .error { message }

private def fromPlanError (result : Except PlanError α) : Except RenderError α :=
  result.mapError fun error => { message := error.message }

partial def rustTypeName : StylusAbiType -> Except RenderError String
  | .bool => pure "bool"
  | .uint 8 => pure "u8"
  | .uint 32 => pure "u32"
  | .uint 64 => pure "u64"
  | .uint 128 => pure "u128"
  | .uint 160 => pure "Address"
  | .uint 256 => pure "U256"
  | .address => pure "Address"
  | .fixedBytes 32 => pure "B256"
  | .fixedBytes bytes => pure s!"FixedBytes<{bytes}>"
  | .bytes => pure "Vec<u8>"
  | .string => pure "String"
  | .fixedArray elem size => do
      pure s!"[{← rustTypeName elem}; {size}]"
  | .dynamicArray elem => do
      pure s!"Vec<{← rustTypeName elem}>"
  | .tuple fields => do
      let names <- fields.mapM rustTypeName
      pure s!"({String.intercalate ", " names.toList})"
  | .uint bits => fail s!"Rust SDK renderer has no type for uint{bits}"

private def storageTypeName : StylusAbiType -> Except RenderError String
  | .bool => pure "bool"
  | .uint bits => pure s!"uint{bits}"
  | .address => pure "address"
  | .fixedBytes bytes => pure s!"bytes{bytes}"
  | type => fail s!"Rust SDK storage renderer does not support `{repr type}` yet"

private def literalText : StylusLiteralPlan -> Except RenderError String
  | .bool true => pure "true"
  | .bool false => pure "false"
  | .uint value => pure (toString value)
  | .address value => pure s!"Address::parse_checksummed(\"{value}\", None).unwrap()"
  | .fixedBytes _ => fail "Rust SDK fixed-bytes literals are not implemented"
  | .bytes value => pure s!"vec![{String.intercalate ", " (value.toList.map (fun byte => toString byte.toNat))}]"
  | .string value =>
      let escaped := (value.replace "\\" "\\\\").replace "\"" "\\\""
      pure s!"String::from(\"{escaped}\")"

private def localName (id : StylusValueId) : String := s!"v{id}"

private def contextExpression (type : StylusAbiType) : StylusHostOp -> Except RenderError String
  | .msgSender => pure "self.vm().msg_sender()"
  | .msgValue => match type with
      | .uint 128 => pure "self.vm().msg_value().to::<u128>()"
      | .uint 256 => pure "self.vm().msg_value()"
      | _ => fail s!"Rust SDK msg.value cannot produce `{repr type}`"
  | .contractAddress => pure "self.vm().contract_address()"
  | .blockNumber => pure "self.vm().block_number()"
  | .blockTimestamp => pure "self.vm().block_timestamp()"
  | operation => fail s!"Rust SDK renderer has no context expression for `{repr operation}`"

private def storageField (plan : StylusPlan) (id : String) : Except RenderError RustStorageField := do
  let some word := plan.storage.words.find? (fun word => word.id == id)
    | fail s!"Rust SDK operation references unknown storage word `{id}`"
  pure { name := word.id, typeName := ← storageTypeName word.type }

private def renderOperation (plan : StylusPlan) : StylusOpPlan -> Except RenderError RustStmt
  | .literal result type value => do
      pure (.letLiteral (localName result) (← rustTypeName type) (← literalText value))
  | .storageLoad result wordId => do
      let field <- storageField plan wordId
      let some word := plan.storage.words.find? (fun word => word.id == wordId)
        | fail s!"Rust SDK operation references unknown storage word `{wordId}`"
      pure (.letStorageGet (localName result) field.name word.type)
  | .storageCache wordId value => do
      let field <- storageField plan wordId
      let some word := plan.storage.words.find? (fun word => word.id == wordId)
        | fail s!"Rust SDK operation references unknown storage word `{wordId}`"
      pure (.storageSet field.name (localName value) word.type)
  | .storagePathLoad result wordId keys => do
      let field <- storageField plan wordId
      let some word := plan.storage.words.find? (fun word => word.id == wordId)
        | fail s!"Rust SDK operation references unknown storage word `{wordId}`"
      if keys.isEmpty then fail "Rust SDK mapping access requires at least one key"
      pure (.letMapGet (localName result) field.name (keys.map localName) word.type)
  | .storagePathCache wordId keys value => do
      let field <- storageField plan wordId
      let some word := plan.storage.words.find? (fun word => word.id == wordId)
        | fail s!"Rust SDK operation references unknown storage word `{wordId}`"
      if keys.isEmpty then fail "Rust SDK mapping access requires at least one key"
      pure (.mapSet field.name (keys.map localName) (localName value) word.type)
  | .add result type mode lhs rhs => do
      pure (.letAdd (localName result) (← rustTypeName type) (localName lhs) (localName rhs) mode)
  | .sub result type mode lhs rhs => do
      pure (.letArithmetic (localName result) (← rustTypeName type) (localName lhs) (localName rhs) "sub" mode)
  | .mul result type mode lhs rhs => do
      pure (.letArithmetic (localName result) (← rustTypeName type) (localName lhs) (localName rhs) "mul" mode)
  | .div result type mode lhs rhs => do
      pure (.letArithmetic (localName result) (← rustTypeName type) (localName lhs) (localName rhs) "div" mode)
  | .contextRead result type operation => do
      pure (.letContext (localName result) (← contextExpression type operation))
  | .compare result _ op lhs rhs =>
      pure (.letCompare (localName result) (localName lhs) (localName rhs) op)
  | .assert_ condition message => pure (.assert_ (localName condition) message)
  | .emitEvent eventId values => do
      let some event := plan.events.find? (fun item => item.id == eventId)
        | fail s!"Rust SDK operation references unknown event `{eventId}`"
      let topicCount := 1 + (event.fields.filter fun field => field.indexed).size
      if topicCount > 4 then fail s!"Rust SDK event `{eventId}` has more than four topics"
      let indexed := (event.fields.zip values).filterMap fun (field, value) =>
        if field.indexed then some (localName value, field.type) else none
      let data := (event.fields.zip values).filterMap fun (field, value) =>
        if field.indexed then none else some (localName value, field.type)
      pure (.emitEvent event.canonicalSignature indexed data)
  | .call _ _ callId => fail s!"Rust SDK call envelope `{callId}` lowering is not implemented"

private def renderFunction (plan : StylusPlan) (function : StylusFunctionPlan) :
    Except RenderError RustFunction := do
  let some method := plan.abi.methods.find? (fun method => method.name == function.abiMethod)
    | fail s!"Rust SDK function `{function.id}` has no ABI method"
  let #[block] := function.blocks
    | fail s!"Rust SDK function `{function.id}` requires one block in the Counter slice"
  unless block.id == function.entryBlock do
    fail s!"Rust SDK function `{function.id}` entry block is inconsistent"
  let mut body <- block.operations.mapM (renderOperation plan)
  let hasCheckedArithmetic := block.operations.any fun operation =>
    match operation with
    | .add _ _ .checked _ _ | .sub _ _ .checked _ _ | .mul _ _ .checked _ _
    | .div _ _ .checked _ _ => true
    | _ => false
  let hasAssertion := block.operations.any fun operation =>
    match operation with | .assert_ .. => true | _ => false
  let returnType <- match method.returns with
    | #[] => pure <| if hasCheckedArithmetic || hasAssertion then .resultUnit else .unit
    | #[type] =>
        let name <- rustTypeName type
        pure <| if hasCheckedArithmetic || hasAssertion then .resultValue name else .value name
    | _ => fail s!"Rust SDK function `{function.id}` has multiple returns"
  match block.terminator with
  | .return #[] => if hasCheckedArithmetic || hasAssertion then body := body.push .okUnit else pure ()
  | .return #[value] =>
      if hasCheckedArithmetic || hasAssertion then body := body.push (.okValue (localName value))
      else body := body.push (.returnValue (localName value))
  | .return _ => fail s!"Rust SDK function `{function.id}` has unsupported return arity"
  | _ => fail s!"Rust SDK function `{function.id}` control flow is scheduled after Counter"
  pure {
    name := method.name
    receiver := if method.mutability == .view then .shared else .mutable
    params := ← function.params.mapM fun param => do
      pure { name := param.name, typeName := (← rustTypeName param.type), localName := localName param.valueId }
    returnType
    payable := method.payable
    body
  }

private def indent (level : Nat) : String := String.ofList (List.replicate (level * 4) ' ')

private def storageRustAlias : StylusAbiType -> Option String
  | .uint 8 => some "U8" | .uint 32 => some "U32" | .uint 64 => some "U64"
  | .uint 128 => some "U128" | .uint 160 => some "U160" | .uint 256 => some "U256"
  | _ => none

private def nestedStorageMapType (keys : Array StylusAbiType) (value : StylusAbiType) :
    Except RenderError String := do
  let some alias := storageRustAlias value
    | fail s!"Rust SDK mapping has unsupported value type `{repr value}`"
  let mut result := s!"Storage{alias}"
  for key in keys.reverse do
    result := s!"StorageMap<{← rustTypeName key}, {result}>"
  pure result

private def storageRead (field : String) (type : StylusAbiType) : String :=
  match type with
  | .uint bits => s!"self.{field}.get().to::<u{bits}>()"
  | _ => s!"self.{field}.get()"

private def storageWrite (field value : String) (type : StylusAbiType) : String :=
  match storageRustAlias type with
  | some alias => s!"self.{field}.set({alias}::from({value}));"
  | none => s!"self.{field}.set({value});"

private def mapRead (field : String) (keys : Array String) : String :=
  keys.foldl (fun access key => s!"{access}.get({key})") s!"self.{field}"

private def mapWrite (field : String) (keys : Array String) (value : String)
    (type : StylusAbiType) : String :=
  let prefixKeys := keys.extract 0 (keys.size - 1)
  let access := prefixKeys.foldl (fun access key => s!"{access}.setter({key})") s!"self.{field}"
  let key := keys[keys.size - 1]!
  match storageRustAlias type with
  | some alias => s!"{access}.insert({key}, {alias}::from({value}));"
  | none => s!"{access}.insert({key}, {value});"

private def renderStmt (stmt : RustStmt) : Array String :=
  match stmt with
  | .letLiteral name typeName value => #[s!"let {name}: {typeName} = {value};"]
  | .letStorageGet name field type => #[s!"let {name} = {storageRead field type};"]
  | .letMapGet name field keys (.uint bits) =>
      #[s!"let {name} = {mapRead field keys}.to::<u{bits}>();"]
  | .letMapGet name field keys _ => #[s!"let {name} = {mapRead field keys};"]
  | .storageSet field value type => #[storageWrite field value type]
  | .mapSet field keys value type => #[mapWrite field keys value type]
  | .returnValue value => #[value]
  | .okValue value => #[s!"Ok({value})"]
  | .okUnit => #["Ok(())"]
  | .letAdd name typeName lhs rhs .wrapping =>
      #[s!"let {name}: {typeName} = {lhs}.wrapping_add({rhs});"]
  | .letAdd name typeName lhs rhs .checked => #[
      s!"let {name}: {typeName} = {lhs}.checked_add({rhs})",
      "    .ok_or_else(|| b\"checked arithmetic overflow\".to_vec())?;"
    ]
  | .letArithmetic name typeName lhs rhs method .wrapping =>
      #[s!"let {name}: {typeName} = {lhs}.wrapping_{method}({rhs});"]
  | .letArithmetic name typeName lhs rhs method .checked => #[
      s!"let {name}: {typeName} = {lhs}.checked_{method}({rhs})",
      "    .ok_or_else(|| b\"checked arithmetic overflow\".to_vec())?;"
    ]
  | .letContext name expression => #[s!"let {name} = {expression};"]
  | .letCompare name lhs rhs op =>
      let symbol := match op with
        | .eq => "==" | .ne => "!=" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="
      #[s!"let {name}: bool = {lhs} {symbol} {rhs};"]
  | .assert_ condition message => #[
      "if !" ++ condition ++ " {", "    return Err(b\"" ++ message ++ "\".to_vec());", "}"
    ]
  | .emitEvent signature indexed data =>
      let renderWord := fun (value, type) => match type with
        | .address => s!"__pf_event.extend_from_slice({value}.into_word().as_slice());"
        | _ => s!"__pf_event.extend_from_slice(&U256::from({value}).to_be_bytes::<32>());"
      #["let mut __pf_event = self.vm().native_keccak256(b\"" ++ signature ++ "\").to_vec();"] ++
      indexed.map renderWord ++ data.map renderWord ++
      #[s!"self.vm().emit_log(&__pf_event, {1 + indexed.size});"]

private def renderFunctionText (function : RustFunction) : String :=
  let receiver := match function.receiver with | .shared => "&self" | .mutable => "&mut self"
  let params := function.params.map fun param => s!"{param.name}: {param.typeName}"
  let arguments := String.intercalate ", " <| (#[receiver] ++ params).toList
  let returnType := match function.returnType with
    | .unit => ""
    | .value name => s!" -> {name}"
    | .resultUnit => " -> Result<(), Vec<u8>>"
    | .resultValue name => s!" -> Result<{name}, Vec<u8>>"
  let bindings := function.params.map fun param => indent 2 ++ s!"let {param.localName} = {param.name};"
  let lines := function.body.foldl (fun lines stmt =>
    lines ++ (renderStmt stmt).map (fun line => indent 2 ++ line)) #[]
  let payable := if function.payable then indent 1 ++ "#[payable]\n" else ""
  let header := payable ++ indent 1 ++ "pub fn " ++ function.name ++ "(" ++ arguments ++ ")" ++
    returnType ++ " {"
  String.intercalate "\n" <| (#[header] ++ bindings ++ lines ++ #[indent 1 ++ "}"]).toList

private def renderLib (contract : RustContract) : String :=
  let storage := contract.storage.map fun field =>
    s!"{indent 2}{field.typeName} {field.name};"
  let functions := contract.functions.map renderFunctionText
  String.intercalate "\n" <| (#[] ++ #[
    "#![cfg_attr(not(any(test, feature = \"export-abi\")), no_main)]",
    "#![cfg_attr(not(test), no_std)]", "", "extern crate alloc;", "",
    "use alloc::{string::String, vec, vec::Vec};", "use stylus_sdk::{alloy_primitives::*, prelude::*, storage::*};", "",
    "sol_storage! {", s!"{indent 1}#[entrypoint]", indent 1 ++ "pub struct " ++ contract.name ++ " {"
  ] ++ storage ++ #[indent 1 ++ "}", "}", "", "#[public]", "impl " ++ contract.name ++ " {"] ++
    (functions.toList.intersperse "").toArray ++ #["}", ""]).toList

private def cargoToml (crateName : String) : String :=
  s!"[package]\nname = \"{crateName}\"\nversion = \"0.1.0\"\nedition = \"2021\"\npublish = false\n\n[lib]\ncrate-type = [\"cdylib\", \"lib\"]\n\n[dependencies]\nstylus-sdk = \"=0.10.8\"\n\n[features]\ndefault = []\nexport-abi = [\"stylus-sdk/export-abi\"]\nstylus-test = [\"stylus-sdk/stylus-test\"]\ncontract-client-gen = []\n"

private def crateSlug (moduleName : String) : String :=
  "proof-forge-" ++ String.toLower moduleName ++ "-stylus"

def renderCrate (plan : StylusPlan) : Except RenderError RustCrate := do
  fromPlanError (validateForRenderer .rustSdk plan)
  let storage <- plan.storage.words.mapM fun word => do
    let valueType <- storageTypeName word.type
    let typeName <- match word.keyTypes with
      | #[] => pure valueType
      | keys => nestedStorageMapType keys word.type
    pure { name := word.id, typeName }
  let functions <- plan.functions.mapM (renderFunction plan)
  let contract : RustContract := { name := plan.moduleName, storage, functions }
  let name := crateSlug plan.moduleName
  pure {
    name
    files := #[
      { path := "Cargo.toml", content := cargoToml name },
      { path := "src/lib.rs", content := renderLib contract }
    ]
  }

end ProofForge.Backend.Stylus.RustSdk
