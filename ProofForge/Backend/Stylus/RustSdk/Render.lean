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

private def localName (id : StylusValueId) : String := s!"v{id}"

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
  | .add result type mode lhs rhs => do
      pure (.letAdd (localName result) (← rustTypeName type) (localName lhs) (localName rhs) mode)

private def renderFunction (plan : StylusPlan) (function : StylusFunctionPlan) :
    Except RenderError RustFunction := do
  let some method := plan.abi.methods.find? (fun method => method.name == function.abiMethod)
    | fail s!"Rust SDK function `{function.id}` has no ABI method"
  unless method.params.isEmpty do
    fail s!"Rust SDK function `{function.id}` parameters are scheduled after Counter"
  let #[block] := function.blocks
    | fail s!"Rust SDK function `{function.id}` requires one block in the Counter slice"
  unless block.id == function.entryBlock do
    fail s!"Rust SDK function `{function.id}` entry block is inconsistent"
  let mut body <- block.operations.mapM (renderOperation plan)
  let hasCheckedArithmetic := block.operations.any fun operation =>
    match operation with
    | .add _ _ .checked _ _ => true
    | _ => false
  let returnType <- match method.returns with
    | #[] => pure <| if hasCheckedArithmetic then .resultUnit else .unit
    | #[type] => pure (.value (← rustTypeName type))
    | _ => fail s!"Rust SDK function `{function.id}` has multiple returns"
  match block.terminator with
  | .return #[] => if hasCheckedArithmetic then body := body.push .okUnit else pure ()
  | .return #[value] => body := body.push (.returnValue (localName value))
  | .return _ => fail s!"Rust SDK function `{function.id}` has unsupported return arity"
  | _ => fail s!"Rust SDK function `{function.id}` control flow is scheduled after Counter"
  pure {
    name := method.name
    receiver := if method.mutability == .view then .shared else .mutable
    returnType
    body
  }

private def indent (level : Nat) : String := String.ofList (List.replicate (level * 4) ' ')

private def storageRustAlias : StylusAbiType -> Option String
  | .uint 8 => some "U8" | .uint 32 => some "U32" | .uint 64 => some "U64"
  | .uint 128 => some "U128" | .uint 160 => some "U160" | .uint 256 => some "U256"
  | _ => none

private def storageRead (field : String) (type : StylusAbiType) : String :=
  match type with
  | .uint bits => s!"self.{field}.get().to::<u{bits}>()"
  | _ => s!"self.{field}.get()"

private def storageWrite (field value : String) (type : StylusAbiType) : String :=
  match storageRustAlias type with
  | some alias => s!"self.{field}.set({alias}::from({value}));"
  | none => s!"self.{field}.set({value});"

private def renderStmt (stmt : RustStmt) : Array String :=
  match stmt with
  | .letLiteral name typeName value => #[s!"let {name}: {typeName} = {value};"]
  | .letStorageGet name field type => #[s!"let {name} = {storageRead field type};"]
  | .storageSet field value type => #[storageWrite field value type]
  | .returnValue value => #[value]
  | .okUnit => #["Ok(())"]
  | .letAdd name typeName lhs rhs .wrapping =>
      #[s!"let {name}: {typeName} = {lhs}.wrapping_add({rhs});"]
  | .letAdd name typeName lhs rhs .checked => #[
      s!"let {name}: {typeName} = {lhs}.checked_add({rhs})",
      "    .ok_or_else(|| b\"checked arithmetic overflow\".to_vec())?;"
    ]

private def renderFunctionText (function : RustFunction) : String :=
  let receiver := match function.receiver with | .shared => "&self" | .mutable => "&mut self"
  let returnType := match function.returnType with
    | .unit => ""
    | .value name => s!" -> {name}"
    | .resultUnit => " -> Result<(), Vec<u8>>"
  let lines := function.body.foldl (fun lines stmt =>
    lines ++ (renderStmt stmt).map (fun line => indent 2 ++ line)) #[]
  let header := indent 1 ++ "pub fn " ++ function.name ++ "(" ++ receiver ++ ")" ++
    returnType ++ " {"
  String.intercalate "\n" <| (#[header] ++ lines ++ #[indent 1 ++ "}"]).toList

private def renderLib (contract : RustContract) : String :=
  let storage := contract.storage.map fun field =>
    s!"{indent 2}{field.typeName} {field.name};"
  let functions := contract.functions.map renderFunctionText
  String.intercalate "\n" <| (#[] ++ #[
    "#![cfg_attr(not(any(test, feature = \"export-abi\")), no_main)]",
    "#![cfg_attr(not(test), no_std)]", "", "extern crate alloc;", "",
    "use alloc::{vec, vec::Vec};", "use stylus_sdk::{alloy_primitives::*, prelude::*};", "",
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
    pure { name := word.id, typeName := ← storageTypeName word.type }
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
