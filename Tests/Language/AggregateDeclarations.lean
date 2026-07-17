import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Language.AggregateDeclarationsFixture

open ProofForgeV2.Language

program AggregateSurface where
  struct Transfer where
    sender : UInt64
    amount : UInt64
    digestValue : Field bn254_fr

  enum Status where
    | Pending
    | Complete(UInt64)
    | Flagged(Bool, Field bn254_fr)

  entry ping() : UInt64 do
    return 0

end Tests.Language.AggregateDeclarationsFixture

namespace Tests.Language.AggregateDeclarations

open ProofForgeV2

private def struct : Nat := 1
private def enum : Nat := 2

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def source : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "namespace Tests.Language.AggregateDeclarationsFixture\n\n" ++
  "program AggregateSurface where\n" ++
  "  struct Transfer where\n" ++
  "    sender : UInt64\n" ++
  "    amount : UInt64\n" ++
  "    digestValue : Field bn254_fr\n\n" ++
  "  enum Status where\n" ++
  "    | Pending\n" ++
  "    | Complete(UInt64)\n" ++
  "    | Flagged(Bool, Field bn254_fr)\n\n" ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n\n" ++
  "end Tests.Language.AggregateDeclarationsFixture\n"

private def programSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO Source.Program := do
  match ← session.selectProgram input path none with
  | .ok sourceProgram => pure sourceProgram
  | .error error => throw <| IO.userError error.render

private def expectInvalid (label expected : String)
    (result : CompileResult (Array Source.Program)) : IO Unit := do
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}'"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

unsafe def run : IO Unit := do
  expect (struct + enum == 3)
    "struct/enum must remain legal host Lean identifiers outside the ProofForge DSL"

  let elaborated := Tests.Language.AggregateDeclarationsFixture.AggregateSurface
  match elaborated.structs with
  | #[transfer] =>
      expect (transfer.name == "Transfer" &&
          transfer.fields.map (fun field => (field.name, field.type)) ==
            #[("sender", .u64), ("amount", .u64), ("digestValue", .field)])
        "struct name, field names, types, and order must survive Lean command elaboration"
  | _ => throw <| IO.userError "AggregateSurface must retain one struct declaration"
  match elaborated.enums with
  | #[status] =>
      expect (status.name == "Status") "enum name must survive Lean command elaboration"
      match status.variants with
      | #[pending, complete, flagged] =>
          expect (pending.name == "Pending" && pending.payloadTypes.isEmpty)
            "nullary enum variants must retain an empty payload"
          expect (complete.name == "Complete" && complete.payloadTypes == #[.u64])
            "unary enum payload type must survive Lean command elaboration"
          expect (flagged.name == "Flagged" && flagged.payloadTypes == #[.bool, .field])
            "enum payload type order must survive Lean command elaboration"
      | _ => throw <| IO.userError "Status must retain three variants"
  | _ => throw <| IO.userError "AggregateSurface must retain one enum declaration"

  let session ← Language.Loader.ParserSession.create
  let decoded ← select session source "<aggregate-declarations>"
  expect (decoded == elaborated)
    "Loader and Lean command must produce the same struct/enum Source.Program"
  expect (decoded.sourceHash == elaborated.sourceHash)
    "Loader and Lean command must produce the same struct/enum source hash"

  let base ← select session (programSource "CanonicalAggregate" "") "<aggregate-base>"
  let structOne ← select session
    (programSource "CanonicalAggregate" "  struct A where\n    value : UInt64\n")
    "<aggregate-struct-one>"
  let structName ← select session
    (programSource "CanonicalAggregate" "  struct B where\n    value : UInt64\n")
    "<aggregate-struct-name>"
  let structFieldName ← select session
    (programSource "CanonicalAggregate" "  struct A where\n    other : UInt64\n")
    "<aggregate-struct-field-name>"
  let structFieldType ← select session
    (programSource "CanonicalAggregate" "  struct A where\n    value : Bool\n")
    "<aggregate-struct-field-type>"
  let structFieldsAB ← select session
    (programSource "CanonicalAggregate"
      "  struct A where\n    first : UInt64\n    second : Bool\n")
    "<aggregate-struct-fields-ab>"
  let structFieldsBA ← select session
    (programSource "CanonicalAggregate"
      "  struct A where\n    second : Bool\n    first : UInt64\n")
    "<aggregate-struct-fields-ba>"
  let structFieldCount ← select session
    (programSource "CanonicalAggregate"
      "  struct A where\n    value : UInt64\n    extra : Bool\n")
    "<aggregate-struct-field-count>"
  let structsAB ← select session
    (programSource "CanonicalAggregate"
      "  struct A where\n    value : UInt64\n  struct B where\n    flag : Bool\n")
    "<aggregate-structs-ab>"
  let structsBA ← select session
    (programSource "CanonicalAggregate"
      "  struct B where\n    flag : Bool\n  struct A where\n    value : UInt64\n")
    "<aggregate-structs-ba>"
  let enumOne ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Value(UInt64)\n")
    "<aggregate-enum-one>"
  let enumName ← select session
    (programSource "CanonicalAggregate" "  enum B where\n    | Value(UInt64)\n")
    "<aggregate-enum-name>"
  let enumVariantName ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Other(UInt64)\n")
    "<aggregate-enum-variant-name>"
  let enumPayloadType ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Value(Bool)\n")
    "<aggregate-enum-payload-type>"
  let enumPayloadAB ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Value(UInt64, Bool)\n")
    "<aggregate-enum-payload-ab>"
  let enumPayloadBA ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Value(Bool, UInt64)\n")
    "<aggregate-enum-payload-ba>"
  let enumVariantsAB ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | First\n    | Second(UInt64)\n")
    "<aggregate-enum-variants-ab>"
  let enumVariantsBA ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Second(UInt64)\n    | First\n")
    "<aggregate-enum-variants-ba>"
  let enumVariantCount ← select session
    (programSource "CanonicalAggregate"
      "  enum A where\n    | Value(UInt64)\n    | Extra\n")
    "<aggregate-enum-variant-count>"
  let enumPayloadCount ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Value(UInt64, Bool)\n")
    "<aggregate-enum-payload-count>"
  let enumsAB ← select session
    (programSource "CanonicalAggregate"
      "  enum A where\n    | Value(UInt64)\n  enum B where\n    | Flag(Bool)\n")
    "<aggregate-enums-ab>"
  let enumsBA ← select session
    (programSource "CanonicalAggregate"
      "  enum B where\n    | Flag(Bool)\n  enum A where\n    | Value(UInt64)\n")
    "<aggregate-enums-ba>"
  let enumSameShape ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | value(UInt64)\n")
    "<aggregate-enum-same-shape>"
  let enumNoParens ← select session
    (programSource "CanonicalAggregate" "  enum A where\n    | Empty\n")
    "<aggregate-enum-no-parens>"

  expect (base.sourceHash != structOne.sourceHash && structOne.sourceHash != enumSameShape.sourceHash)
    "struct/enum presence and kind must bind the source hash"
  expect (structOne.sourceHash != structName.sourceHash &&
      structOne.sourceHash != structFieldName.sourceHash &&
      structOne.sourceHash != structFieldType.sourceHash &&
      structOne.sourceHash != structFieldCount.sourceHash &&
      structFieldsAB.sourceHash != structFieldsBA.sourceHash &&
      structsAB.sourceHash != structsBA.sourceHash)
    "struct declaration/field name, type, count, field order, and declaration order must bind the source hash"
  expect (enumOne.sourceHash != enumName.sourceHash &&
      enumOne.sourceHash != enumVariantName.sourceHash &&
      enumOne.sourceHash != enumPayloadType.sourceHash &&
      enumOne.sourceHash != enumVariantCount.sourceHash &&
      enumOne.sourceHash != enumPayloadCount.sourceHash &&
      enumPayloadAB.sourceHash != enumPayloadBA.sourceHash &&
      enumVariantsAB.sourceHash != enumVariantsBA.sourceHash &&
      enumsAB.sourceHash != enumsBA.sourceHash)
    "enum declaration/variant name/count/order, payload count/type/order, and declaration order must bind the source hash"
  expect (enumNoParens.enums[0]!.variants[0]!.payloadTypes.isEmpty)
    "a bare enum variant must retain a nullary payload"

  expectInvalid "duplicate struct declarations"
    "program 'DuplicateStruct' contains duplicate struct declarations"
    (← session.parsePrograms
      (programSource "DuplicateStruct"
        "  struct A where\n    value : UInt64\n  struct A where\n    other : Bool\n")
      "<duplicate-struct>")
  expectInvalid "duplicate enum declarations"
    "program 'DuplicateEnum' contains duplicate enum declarations"
    (← session.parsePrograms
      (programSource "DuplicateEnum" "  enum A where\n    | X\n  enum A where\n    | Y\n")
      "<duplicate-enum>")
  expectInvalid "struct field declaration order" "struct 'First' contains duplicate fields"
    (← session.parsePrograms
      (programSource "DuplicateStructField"
        "  struct First where\n    value : UInt64\n    value : Bool\n  struct Second where\n    other : UInt64\n    other : Bool\n")
      "<duplicate-struct-field>")
  expectInvalid "enum variant declaration order" "enum 'First' contains duplicate variants"
    (← session.parsePrograms
      (programSource "DuplicateEnumVariant"
        "  enum First where\n    | Value\n    | Value(UInt64)\n  enum Second where\n    | Other\n    | Other\n")
      "<duplicate-enum-variant>")
  expectInvalid "empty struct" "struct 'Empty' must declare at least one field"
    (← session.parsePrograms
      (programSource "EmptyStruct" "  struct Empty where\n") "<empty-struct>")
  expectInvalid "empty enum" "enum 'Empty' must declare at least one variant"
    (← session.parsePrograms
      (programSource "EmptyEnum" "  enum Empty where\n") "<empty-enum>")
  expectInvalid "empty enum payload"
    "enum variant 'Empty' payload must contain at least one type"
    (← session.parsePrograms
      (programSource "EmptyEnumPayload" "  enum A where\n    | Empty()\n")
      "<empty-enum-payload>")
  expectInvalid "escaped struct keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedStructKeyword" "  «struct» A where\n    value : UInt64\n")
      "<escaped-struct-keyword>")
  expectInvalid "escaped enum keyword" "unsupported portable program item"
    (← session.parsePrograms
      (programSource "EscapedEnumKeyword" "  «enum» A where\n    | Value\n")
      "<escaped-enum-keyword>")
  expectInvalid "ordinary reserved struct identifier" "reserved portable identifier 'struct'"
    (← session.parsePrograms
      (programSource "OrdinaryReservedStructIdentifier"
        "  struct struct where\n    value : UInt64\n")
      "<ordinary-reserved-struct-identifier>")
  expectInvalid "escaped reserved struct identifier" "reserved portable identifier 'struct'"
    (← session.parsePrograms
      (programSource "ReservedStructIdentifier" "  struct «struct» where\n    value : UInt64\n")
      "<reserved-struct-identifier>")
  expectInvalid "ordinary reserved enum identifier" "reserved portable identifier 'enum'"
    (← session.parsePrograms
      (programSource "OrdinaryReservedEnumIdentifier" "  enum enum where\n    | Value\n")
      "<ordinary-reserved-enum-identifier>")
  expectInvalid "escaped reserved enum identifier" "reserved portable identifier 'enum'"
    (← session.parsePrograms
      (programSource "ReservedEnumIdentifier" "  enum A where\n    | «enum»\n")
      "<reserved-enum-identifier>")

  match Typed.check elaborated with
  | .error (.invalidProgram "struct declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"struct declarations reached the wrong typed failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase struct declarations"
  match Compiler.compile elaborated with
  | .error (.invalidProgram "struct declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"struct declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not silently erase struct declarations"

  let enumOnly ← select session
    (programSource "EnumOnly" "  enum Status where\n    | Ready\n") "<enum-only>"
  match Typed.check enumOnly with
  | .error (.invalidProgram "enum declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"enum declarations reached the wrong typed failure: {other.render}"
  | .ok _ => throw <| IO.userError "Typed.check must not silently erase enum declarations"
  match Compiler.compile enumOnly with
  | .error (.invalidProgram "enum declarations are not yet supported by typed checking") => pure ()
  | .error other => throw <| IO.userError s!"enum declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compile must not silently erase enum declarations"

end Tests.Language.AggregateDeclarations
