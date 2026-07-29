import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1Declarations

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def rawParts (name : SourceQualifiedNameV1) : Array String :=
  (NonEmptyArray.toArray name.components).map (·.raw)

private def source : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Full where\n" ++
  "  state total : UInt64\n" ++
  "  struct Pair where\n" ++
  "    left : UInt64\n" ++
  "    right : Bool\n" ++
  "    tagged : Choice\n" ++
  "    dotted : «Foo.Bar»\n" ++
  "    maybeField : Option Field bn254_fr\n" ++
  "    nestedOption : Option Option UInt64\n" ++
  "    optionBytes : Option Bytes 8\n" ++
  "    arrayPlain : Array UInt64 4\n" ++
  "    arrayOption : Array Option UInt64 4\n" ++
  "    optionArray : Option Array UInt64 4\n" ++
  "    arrayArray : Array Array UInt64 2 3\n" ++
  "    arrayDeep : Array Option Option Field bn254_fr 4\n" ++
  "    mapPlain : Map UInt64 Bool\n" ++
  "    arrayMap : Array Map UInt64 Bool 4\n" ++
  "    optionMap : Option Map UInt64 Bool\n" ++
  "  enum Choice where\n" ++
  "    | None\n" ++
  "    | Some(UInt64)\n" ++
  "  const one : UInt64 := 1\n" ++
  "  event Changed(private value : UInt64)\n" ++
  "  error Failed\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n" ++
  "  entry add(amount : Map UInt64 Bool) : Map UInt64 Bool do\n" ++
  "    return amount\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n" ++
  "  fn identity(value : UInt64) : UInt64 do\n" ++
  "    return value\n" ++
  "  invariant initialized : true\n" ++
  "  requires extension proof.forge.feature version \"1.0.0\"\n" ++
  "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n" ++
  "  proof initialized using Tests.Theorems.initialized\n"

private def negativeSource (programName body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ programName ++ " where\n" ++ body ++
  "  entry ok() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label source expected : String) : IO Unit := do
  match ← session.selectProgramV1 source ("<program-v1-negative-" ++ label ++ ">")
      "Tests.ProgramV1Declarations" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

/-- TST-SRC-004 migration RED: all thirteen declaration alternatives must be
constructed directly by the ProgramV1 Loader, in source order. -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let parsed ← session.selectProgramV1 source "<program-v1-declarations>"
    "Tests.ProgramV1Declarations" none
  let validated ← match parsed with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render

  expect (rawParts validated.moduleName == #["Tests", "ProgramV1Declarations"])
    "explicit module identity was not preserved as raw components"
  expect (rawParts validated.programIdentity ==
      #["Tests", "ProgramV1Declarations", "Full"])
    "program identity did not append the raw declaration name"
  let items : Array ProgramItemV1 := validated.program.items
  expect (items.size == 13) "ProgramV1 declaration decoder did not retain all items"

  match items[0]? with
  | some (ProgramItemV1.state declaration) =>
      expect (declaration.name.raw == "total" && declaration.type_ == .uint 64)
        "state declaration did not decode directly to ProgramV1"
  | other => throw <| IO.userError s!"item 0 is not StateDeclV1: {repr other}"

  match items[1]? with
  | some (ProgramItemV1.struct declaration) =>
      match declaration.fields.toList with
      | [left, right, tagged, dotted, maybeField, nestedOption, optionBytes,
          arrayPlain, arrayOption, optionArray, arrayArray, arrayDeep,
          mapPlain, arrayMap, optionMap] =>
          let taggedOk :=
            match tagged.type_ with
            | .named name => name.raw == "Choice"
            | _ => false
          let dottedOk :=
            match dotted.type_ with
            | .named name => name.raw == "Foo.Bar"
            | _ => false
          let maybeFieldOk :=
            match maybeField.type_ with
            | .option (.field id) => id.raw == "bn254_fr"
            | _ => false
          let nestedOptionOk := nestedOption.type_ == .option (.option (.uint 64))
          let optionBytesOk := optionBytes.type_ == .option (.bytes 8)
          let arrayPlainOk := arrayPlain.type_ == .array (.uint 64) 4
          let arrayOptionOk := arrayOption.type_ == .array (.option (.uint 64)) 4
          let optionArrayOk := optionArray.type_ == .option (.array (.uint 64) 4)
          let arrayArrayOk := arrayArray.type_ == .array (.array (.uint 64) 2) 3
          let arrayDeepOk :=
            match arrayDeep.type_ with
            | .array (.option (.option (.field id))) length =>
                id.raw == "bn254_fr" && length == 4
            | _ => false
          let mapPlainOk := mapPlain.type_ == .map (.uint 64) .bool
          let arrayMapOk := arrayMap.type_ == .array (.map (.uint 64) .bool) 4
          let optionMapOk := optionMap.type_ == .option (.map (.uint 64) .bool)
          expect (declaration.name.raw == "Pair" && left.name.raw == "left" &&
              left.type_ == .uint 64 && right.name.raw == "right" &&
              right.type_ == .bool && tagged.name.raw == "tagged" && taggedOk &&
              dotted.name.raw == "dotted" && dottedOk &&
              maybeField.name.raw == "maybeField" && maybeFieldOk &&
              nestedOption.name.raw == "nestedOption" && nestedOptionOk &&
              optionBytes.name.raw == "optionBytes" && optionBytesOk &&
              arrayPlain.name.raw == "arrayPlain" && arrayPlainOk &&
              arrayOption.name.raw == "arrayOption" && arrayOptionOk &&
              optionArray.name.raw == "optionArray" && optionArrayOk &&
              arrayArray.name.raw == "arrayArray" && arrayArrayOk &&
              arrayDeep.name.raw == "arrayDeep" && arrayDeepOk &&
              mapPlain.name.raw == "mapPlain" && mapPlainOk &&
              arrayMap.name.raw == "arrayMap" && arrayMapOk &&
              optionMap.name.raw == "optionMap" && optionMapOk)
            "struct fields did not retain source order and V1 types"
      | fields => throw <| IO.userError s!"struct fields are incomplete: {repr fields}"
  | other => throw <| IO.userError s!"item 1 is not StructDeclV1: {repr other}"

  match items[2]? with
  | some (ProgramItemV1.enum declaration) =>
      match declaration.variants.toList with
      | [noneVariant, someVariant] =>
          expect (declaration.name.raw == "Choice" && noneVariant.name.raw == "None" &&
              noneVariant.payloadTypes.isEmpty && someVariant.name.raw == "Some" &&
              someVariant.payloadTypes == #[.uint 64])
            "enum variants did not retain source order and payload types"
      | variants => throw <| IO.userError s!"enum variants are incomplete: {repr variants}"
  | other => throw <| IO.userError s!"item 2 is not EnumDeclV1: {repr other}"

  match items[3]? with
  | some (ProgramItemV1.const declaration) =>
      expect (declaration.name.raw == "one" && declaration.type_ == .uint 64 &&
          declaration.value == .literal (.integer 1))
        "const declaration did not retain its typed literal"
  | other => throw <| IO.userError s!"item 3 is not ConstDeclV1: {repr other}"

  match items[4]? with
  | some (ProgramItemV1.event declaration) =>
      match declaration.params.toList with
      | [parameter] =>
          expect (declaration.name.raw == "Changed" && parameter.visibility == .private_ &&
              parameter.name.raw == "value")
            "event parameters did not retain visibility and name"
      | params => throw <| IO.userError s!"event parameters are incomplete: {repr params}"
  | other => throw <| IO.userError s!"item 4 is not EventDeclV1: {repr other}"

  match items[5]? with
  | some (ProgramItemV1.error declaration) =>
      expect (declaration.name.raw == "Failed" && declaration.params.isEmpty)
        "bare error declaration did not materialize an empty parameter array"
  | other => throw <| IO.userError s!"item 5 is not ErrorDeclV1: {repr other}"

  match items[6]? with
  | some (ProgramItemV1.init declaration) =>
      expect (declaration.params.size == 1 && declaration.body.statements.size == 1)
        "initializer declaration did not retain params/body"
  | other => throw <| IO.userError s!"item 6 is not InitDeclV1: {repr other}"

  match items[7]?, items[8]? with
  | some (ProgramItemV1.entry entryDecl), some (ProgramItemV1.view viewDecl) =>
      let paramOk := match entryDecl.params.toList with
        | [param] => param.type_ == .map (.uint 64) .bool
        | _ => false
      expect (entryDecl.name.raw == "add" && entryDecl.result == .map (.uint 64) .bool &&
          paramOk &&
          viewDecl.name.raw == "current" && viewDecl.result == .uint 64)
        "entry/view declarations did not retain result/param types"
  | entryItem, viewItem =>
      throw <| IO.userError s!"items 7/8 are not Entry/View: {repr entryItem}, {repr viewItem}"

  match items[9]? with
  | some (ProgramItemV1.fn declaration) =>
      expect (declaration.name.raw == "identity" && declaration.params.size == 1 &&
          declaration.result == .uint 64 && declaration.body.statements.size == 1)
        "fn declaration did not retain its complete spine"
  | other => throw <| IO.userError s!"item 9 is not FnDeclV1: {repr other}"

  match items[10]? with
  | some (ProgramItemV1.invariant declaration) =>
      expect (declaration.name.raw == "initialized" &&
          declaration.predicate == .literal (.bool true))
        "invariant declaration did not retain its predicate"
  | other => throw <| IO.userError s!"item 10 is not InvariantDeclV1: {repr other}"

  match items[11]? with
  | some (ProgramItemV1.extensionReq declaration) =>
      expect (rawParts declaration.id == #["proof", "forge", "feature"] &&
          declaration.version == "1.0.0" &&
          declaration.digest ==
            "sha256:0000000000000000000000000000000000000000000000000000000000000000")
        "extension requirement did not retain exact identity/version/digest"
  | other => throw <| IO.userError s!"item 11 is not ExtensionReqV1: {repr other}"

  match items[12]? with
  | some (ProgramItemV1.proof declaration) =>
      expect (declaration.invariant.raw == "initialized" &&
          rawParts declaration.theorem_ == #["Tests", "Theorems", "initialized"])
        "proof declaration did not retain exact invariant/theorem identity"
  | other => throw <| IO.userError s!"item 12 is not ProofDeclV1: {repr other}"

  expectReject session "legacy-call-string"
    (negativeSource "LegacyCall" "  init() do\n    call \"legacy.effect\"\n")
    "failed to parse file"
  expectReject session "option-missing-payload"
    (negativeSource "MissingOption" "  state bad : Option\n")
    "unsupported portable type"
  expectReject session "qualified-named-type"
    (negativeSource "QualifiedNamedType" "  state bad : Foo.Bar\n")
    "unsupported portable type"
  expectReject session "wrong-field-id"
    (negativeSource "WrongField" "  state bad : Field bls12_381\n")
    "unsupported portable type"
  expectReject session "escaped-field-id"
    (negativeSource "EscapedField" "  state bad : Field «bn254_fr»\n")
    "unsupported portable type"
  expectReject session "escaped-primitive-type"
    (negativeSource "EscapedPrimitive" "  state bad : «UInt64»\n")
    "unsupported portable type"
  expectReject session "escaped-type-constructor"
    (negativeSource "EscapedConstructor" "  state bad : «Option» UInt64\n")
    "unsupported portable type"
  expectReject session "escaped-reserved-named-type"
    (negativeSource "EscapedReservedNamed" "  state bad : «state»\n")
    "reserved portable identifier 'state'"
  expectReject session "escaped-fn-introducer"
    (negativeSource "EscapedFnIntroducer" "  «fn» f() : UInt64 do\n    return 0\n")
    "unsupported portable program item"
  expectReject session "noncanonical-extension-version"
    (negativeSource "WrongExtensionVersion"
      ("  requires extension proof.forge.feature version \"01.0.0\"\n" ++
        "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n"))
    "leading zero forbidden"
  expectReject session "wrong-extension-digest"
    (negativeSource "WrongExtensionDigest"
      ("  requires extension proof.forge.feature version \"1.0.0\"\n" ++
        "    digest \"sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"\n"))
    "digest hex must be lowercase [0-9a-f]"
  expectReject session "reserved-proof-theorem-component"
    (negativeSource "ReservedProofComponent"
      "  invariant valid : true\n  proof valid using Foo.«state»\n")
    "reserved portable identifier 'state'"
  expectReject session "reserved-constructor-component"
    (negativeSource "ReservedConstructorComponent"
      "  const value : UInt64 := Foo.«state»()\n")
    "reserved portable identifier 'state'"
  expectReject session "unqualified-proof-theorem"
    (negativeSource "UnqualifiedProof"
      "  invariant initialized : true\n  proof initialized using initialized\n")
    "proof theorem name must contain at least two components"

end Tests.Language.ProgramV1Declarations
