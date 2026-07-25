import ProofForgeV2.Compiler.Pipeline
import Tests.Language.ParserSession

namespace Tests.Language.AggregateDeclarations

open ProofForgeV2
open ProofForgeV2.Source.AstCanonicalRootDecodeV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def typeName (type_ : TypeV1) : String :=
  match type_ with
  | .bool => "Bool"
  | .uint 64 => "UInt64"
  | .field c => s!"Field {c.raw}"
  | _ => "other"

private def mkProgramSource (name declarations : String) : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ declarations ++
  "  entry ping() : UInt64 do\n" ++
  "    return 0\n"

private def aggregateSource : String :=
  "import ProofForgeV2\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
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
  "    return 0\n"

private unsafe def select (session : Language.Loader.ParserSession)
    (input path : String) : IO ValidatedSourceV1 := do
  match ← session.selectProgramV1 input path "Root" none with
  | .ok source => pure source
  | .error error => throw <| IO.userError error.render

private def expectInvalid (label expected : String)
    (result : Except CompileError (Array ValidatedSourceV1)) : IO Unit := do
  match result with
  | .error (.invalidProgram actual) =>
      expect (actual == expected)
        s!"{label}: expected invalid-program '{expected}', got '{actual}'"
  | .error other =>
      throw <| IO.userError s!"{label}: expected invalid-program, got {other.render}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private def liftSourceHash (label : String) (result : Except String ProofForgeV2.Core.Common.Digest) : IO ProofForgeV2.Core.Common.Digest :=
  match result with
  | .ok digest => pure digest
  | .error message => throw <| IO.userError s!"{label}: {message}"

private def allDistinct (hashes : List ProofForgeV2.Core.Common.Digest) : Bool :=
  match hashes with
  | [] => true
  | x :: xs => !xs.contains x && allDistinct xs

private def firstEnumVariant (prog : ValidatedSourceV1) : Option ProofForgeV2.Source.AstSupportV1.EnumVariantV1 :=
  prog.program.items.findSome? fun item =>
    match item with
    | .enum e => e.variants[0]?
    | _ => none

private def liftValidated (label : String) (result : Except String ValidatedSourceV1) : IO ValidatedSourceV1 :=
  match result with
  | .ok value => pure value
  | .error message => throw <| IO.userError s!"{label}: {message}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let decoded ← select session aggregateSource "<aggregate-declarations>"

  match decoded.program.items.findSome? fun item =>
      match item with | .struct s => some s | _ => none with
  | none => throw <| IO.userError "AggregateSurface must retain one struct declaration"
  | some transfer =>
      expect (transfer.name.raw == "Transfer")
        "struct name must survive Loader parsing"
      expect (transfer.fields.map (fun field => (field.name.raw, typeName field.type_)) ==
          #[("sender", "UInt64"), ("amount", "UInt64"), ("digestValue", "Field bn254_fr")])
        "struct field names, types, and order must survive Loader parsing"

  match decoded.program.items.findSome? fun item =>
      match item with | .enum e => some e | _ => none with
  | none => throw <| IO.userError "AggregateSurface must retain one enum declaration"
  | some status =>
      expect (status.name.raw == "Status") "enum name must survive Loader parsing"
      match status.variants with
      | #[pending, complete, flagged] =>
          expect (pending.name.raw == "Pending" && pending.payloadTypes.isEmpty)
            "nullary enum variants must retain an empty payload"
          expect (complete.name.raw == "Complete" && complete.payloadTypes == #[.uint 64])
            "unary enum payload type must survive Loader parsing"
          expect (flagged.name.raw == "Flagged" && flagged.payloadTypes.map typeName == #["Bool", "Field bn254_fr"])
            "enum payload type order must survive Loader parsing"
      | _ => throw <| IO.userError "Status must retain three variants"

  let canonicalBytes ←
    match canonicalValidatedSourceAstBytesV1 decoded with
    | .ok bytes => pure bytes
    | .error message => throw <| IO.userError s!"canonical encode: {message}"
  let roundTrip ← liftValidated "canonical decode" (decodeCanonicalSourceAstBytesV1 canonicalBytes)
  expect (roundTrip.program == decoded.program)
    "canonical bytes round-trip must preserve the decoded ProgramV1 AST"
  expect (roundTrip.programIdentity == decoded.programIdentity)
    "canonical bytes round-trip must preserve program identity"
  let decodedHash ← liftSourceHash "decoded" (sourceHashV1 decoded)
  let roundTripHash ← liftSourceHash "round-trip" (sourceHashV1 roundTrip)
  expect (decodedHash == roundTripHash)
    "canonical bytes round-trip must preserve the source hash"

  let base ← select session (mkProgramSource "CanonicalAggregate" "") "<aggregate-base>"
  let structOne ← select session
    (mkProgramSource "CanonicalAggregate" "  struct A where\n    value : UInt64\n")
    "<aggregate-struct-one>"
  let structName ← select session
    (mkProgramSource "CanonicalAggregate" "  struct B where\n    value : UInt64\n")
    "<aggregate-struct-name>"
  let structFieldName ← select session
    (mkProgramSource "CanonicalAggregate" "  struct A where\n    other : UInt64\n")
    "<aggregate-struct-field-name>"
  let structFieldType ← select session
    (mkProgramSource "CanonicalAggregate" "  struct A where\n    value : Bool\n")
    "<aggregate-struct-field-type>"
  let structFieldsAB ← select session
    (mkProgramSource "CanonicalAggregate"
      "  struct A where\n    first : UInt64\n    second : Bool\n")
    "<aggregate-struct-fields-ab>"
  let structFieldsBA ← select session
    (mkProgramSource "CanonicalAggregate"
      "  struct A where\n    second : Bool\n    first : UInt64\n")
    "<aggregate-struct-fields-ba>"
  let structFieldCount ← select session
    (mkProgramSource "CanonicalAggregate"
      "  struct A where\n    value : UInt64\n    extra : Bool\n")
    "<aggregate-struct-field-count>"
  let structsAB ← select session
    (mkProgramSource "CanonicalAggregate"
      "  struct A where\n    value : UInt64\n  struct B where\n    flag : Bool\n")
    "<aggregate-structs-ab>"
  let structsBA ← select session
    (mkProgramSource "CanonicalAggregate"
      "  struct B where\n    flag : Bool\n  struct A where\n    value : UInt64\n")
    "<aggregate-structs-ba>"
  let enumOne ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Value(UInt64)\n")
    "<aggregate-enum-one>"
  let enumName ← select session
    (mkProgramSource "CanonicalAggregate" "  enum B where\n    | Value(UInt64)\n")
    "<aggregate-enum-name>"
  let enumVariantName ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Other(UInt64)\n")
    "<aggregate-enum-variant-name>"
  let enumPayloadType ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Value(Bool)\n")
    "<aggregate-enum-payload-type>"
  let enumPayloadAB ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Value(UInt64, Bool)\n")
    "<aggregate-enum-payload-ab>"
  let enumPayloadBA ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Value(Bool, UInt64)\n")
    "<aggregate-enum-payload-ba>"
  let enumVariantsAB ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | First\n    | Second(UInt64)\n")
    "<aggregate-enum-variants-ab>"
  let enumVariantsBA ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Second(UInt64)\n    | First\n")
    "<aggregate-enum-variants-ba>"
  let enumVariantCount ← select session
    (mkProgramSource "CanonicalAggregate"
      "  enum A where\n    | Value(UInt64)\n    | Extra\n")
    "<aggregate-enum-variant-count>"
  let enumPayloadCount ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Value(UInt64, Bool, Bool)\n")
    "<aggregate-enum-payload-count>"
  let enumsAB ← select session
    (mkProgramSource "CanonicalAggregate"
      "  enum A where\n    | Value(UInt64)\n  enum B where\n    | Flag(Bool)\n")
    "<aggregate-enums-ab>"
  let enumsBA ← select session
    (mkProgramSource "CanonicalAggregate"
      "  enum B where\n    | Flag(Bool)\n  enum A where\n    | Value(UInt64)\n")
    "<aggregate-enums-ba>"
  let enumSameShape ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | value(UInt64)\n")
    "<aggregate-enum-same-shape>"
  let enumNoParens ← select session
    (mkProgramSource "CanonicalAggregate" "  enum A where\n    | Empty\n")
    "<aggregate-enum-no-parens>"

  let baseHash ← liftSourceHash "base" (sourceHashV1 base)
  let structOneHash ← liftSourceHash "structOne" (sourceHashV1 structOne)
  let enumSameShapeHash ← liftSourceHash "enumSameShape" (sourceHashV1 enumSameShape)
  expect (baseHash != structOneHash && structOneHash != enumSameShapeHash)
    "struct/enum presence and kind must bind the source hash"

  let structHashes := [
    structOneHash,
    ← liftSourceHash "" (sourceHashV1 structName),
    ← liftSourceHash "" (sourceHashV1 structFieldName),
    ← liftSourceHash "" (sourceHashV1 structFieldType),
    ← liftSourceHash "" (sourceHashV1 structFieldCount),
    ← liftSourceHash "" (sourceHashV1 structFieldsAB),
    ← liftSourceHash "" (sourceHashV1 structFieldsBA),
    ← liftSourceHash "" (sourceHashV1 structsAB),
    ← liftSourceHash "" (sourceHashV1 structsBA)
  ]
  expect (allDistinct structHashes)
    "struct declaration/field name, type, count, field order, and declaration order must bind the source hash"

  let enumHashes := [
    ← liftSourceHash "" (sourceHashV1 enumOne),
    ← liftSourceHash "" (sourceHashV1 enumName),
    ← liftSourceHash "" (sourceHashV1 enumVariantName),
    ← liftSourceHash "" (sourceHashV1 enumPayloadType),
    ← liftSourceHash "" (sourceHashV1 enumVariantCount),
    ← liftSourceHash "" (sourceHashV1 enumPayloadAB),
    ← liftSourceHash "" (sourceHashV1 enumPayloadBA),
    ← liftSourceHash "" (sourceHashV1 enumPayloadCount),
    ← liftSourceHash "" (sourceHashV1 enumVariantsAB),
    ← liftSourceHash "" (sourceHashV1 enumVariantsBA),
    ← liftSourceHash "" (sourceHashV1 enumsAB),
    ← liftSourceHash "" (sourceHashV1 enumsBA)
  ]
  expect (allDistinct enumHashes)
    "enum declaration/variant name/count/order, payload count/type/order, and declaration order must bind the source hash"

  match firstEnumVariant enumNoParens with
  | none => throw <| IO.userError "enum-only program missing variant"
  | some firstVariant =>
      expect (firstVariant.payloadTypes.isEmpty)
        "a bare enum variant must retain a nullary payload"

  expectInvalid "duplicate struct declarations"
    "program contains duplicate struct declarations"
    (← session.parseProgramsV1
      (mkProgramSource "DuplicateStruct"
        "  struct A where\n    value : UInt64\n  struct A where\n    other : Bool\n")
      "<duplicate-struct>" "Root")
  expectInvalid "duplicate enum declarations"
    "program contains duplicate enum declarations"
    (← session.parseProgramsV1
      (mkProgramSource "DuplicateEnum" "  enum A where\n    | X\n  enum A where\n    | Y\n")
      "<duplicate-enum>" "Root")
  expectInvalid "struct field declaration order" "struct 'First' contains duplicate fields"
    (← session.parseProgramsV1
      (mkProgramSource "DuplicateStructField"
        "  struct First where\n    value : UInt64\n    value : Bool\n  struct Second where\n    other : UInt64\n    other : Bool\n")
      "<duplicate-struct-field>" "Root")
  expectInvalid "enum variant declaration order" "enum 'First' contains duplicate variants"
    (← session.parseProgramsV1
      (mkProgramSource "DuplicateEnumVariant"
        "  enum First where\n    | Value\n    | Value(UInt64)\n  enum Second where\n    | Other\n    | Other\n")
      "<duplicate-enum-variant>" "Root")
  expectInvalid "empty struct" "struct fields must be nonempty"
    (← session.parseProgramsV1
      (mkProgramSource "EmptyStruct" "  struct Empty where\n") "<empty-struct>" "Root")
  expectInvalid "empty enum" "enum variants must be nonempty"
    (← session.parseProgramsV1
      (mkProgramSource "EmptyEnum" "  enum Empty where\n") "<empty-enum>" "Root")
  expectInvalid "empty enum payload"
    "enum variant 'Empty' payload must contain at least one type"
    (← session.parseProgramsV1
      (mkProgramSource "EmptyEnumPayload" "  enum A where\n    | Empty()\n")
      "<empty-enum-payload>" "Root")
  expectInvalid "escaped struct keyword" "unsupported portable program item"
    (← session.parseProgramsV1
      (mkProgramSource "EscapedStructKeyword" "  «struct» A where\n    value : UInt64\n")
      "<escaped-struct-keyword>" "Root")
  expectInvalid "escaped enum keyword" "unsupported portable program item"
    (← session.parseProgramsV1
      (mkProgramSource "EscapedEnumKeyword" "  «enum» A where\n    | Value\n")
      "<escaped-enum-keyword>" "Root")
  expectInvalid "ordinary reserved struct identifier" "reserved portable identifier 'struct'"
    (← session.parseProgramsV1
      (mkProgramSource "OrdinaryReservedStructIdentifier"
        "  struct struct where\n    value : UInt64\n")
      "<ordinary-reserved-struct-identifier>" "Root")
  expectInvalid "escaped reserved struct identifier" "reserved portable identifier 'struct'"
    (← session.parseProgramsV1
      (mkProgramSource "ReservedStructIdentifier" "  struct «struct» where\n    value : UInt64\n")
      "<reserved-struct-identifier>" "Root")
  expectInvalid "ordinary reserved enum identifier" "reserved portable identifier 'enum'"
    (← session.parseProgramsV1
      (mkProgramSource "OrdinaryReservedEnumIdentifier" "  enum enum where\n    | Value\n")
      "<ordinary-reserved-enum-identifier>" "Root")
  expectInvalid "escaped reserved enum identifier" "reserved portable identifier 'enum'"
    (← session.parseProgramsV1
      (mkProgramSource "ReservedEnumIdentifier" "  enum A where\n    | «enum»\n")
      "<reserved-enum-identifier>" "Root")

  match Compiler.compileValidatedSourceV1 decoded with
  | .error (.invalidProgram "validated ProgramV1 lowering does not support StructDecl") => pure ()
  | .error other => throw <| IO.userError s!"struct declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compileValidatedSourceV1 must not silently erase struct declarations"

  let enumOnly ← select session
    (mkProgramSource "EnumOnly" "  enum Status where\n    | Ready\n") "<enum-only>"
  match Compiler.compileValidatedSourceV1 enumOnly with
  | .error (.invalidProgram "validated ProgramV1 lowering does not support EnumDecl") => pure ()
  | .error other => throw <| IO.userError s!"enum declarations reached the wrong failure: {other.render}"
  | .ok _ => throw <| IO.userError "Compiler.compileValidatedSourceV1 must not silently erase enum declarations"

end Tests.Language.AggregateDeclarations
