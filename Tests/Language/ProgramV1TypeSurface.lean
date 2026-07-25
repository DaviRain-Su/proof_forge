import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1TypeSurface

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.ValidatedSourceV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def nameComponent (raw : String) : IO SourceNameComponentV1 :=
  IO.ofExcept (parseSourceNameComponentV1 raw)

private def sourceHeader : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n"

private def programPrefix (name : String) : String :=
  sourceHeader ++ "program " ++ name ++ " where\n"

private def programSuffix : String :=
  "  entry ok() : UInt64 do\n" ++
  "    return 0\n"

private def itemSource (body : String) : String :=
  programPrefix "T" ++ body ++ programSuffix

private unsafe def expectType
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body : String)
    (expected : ProofForgeV2.Source.AstV1.TypeV1) : IO Unit := do
  let source := itemSource body
  match ← session.selectProgramV1 source ("<type-surface-" ++ label ++ ">")
      "Tests.ProgramV1TypeSurface" none with
  | .error error => throw <| IO.userError s!"'{label}' failed: {error.render}"
  | .ok value =>
      let items := value.program.items
      unless items.size == 2 do
        throw <| IO.userError s!"'{label}' expected 2 items, got {items.size}"
      match items[0]? with
      | some (ProgramItemV1.state declaration) =>
          unless declaration.type_ == expected do
            throw <| IO.userError
              s!"'{label}' expected {repr expected}, got {repr declaration.type_}"
      | other =>
          throw <| IO.userError s!"'{label}' expected state, got {repr other}"

private unsafe def expectConstType
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body : String)
    (expected : ProofForgeV2.Source.AstV1.TypeV1) : IO Unit := do
  let source := itemSource body
  match ← session.selectProgramV1 source ("<type-surface-" ++ label ++ ">")
      "Tests.ProgramV1TypeSurface" none with
  | .error error => throw <| IO.userError s!"'{label}' failed: {error.render}"
  | .ok value =>
      let items := value.program.items
      unless items.size == 2 do
        throw <| IO.userError s!"'{label}' expected 2 items, got {items.size}"
      match items[0]? with
      | some (ProgramItemV1.const declaration) =>
          unless declaration.type_ == expected do
            throw <| IO.userError
              s!"'{label}' expected {repr expected}, got {repr declaration.type_}"
      | other =>
          throw <| IO.userError s!"'{label}' expected const, got {repr other}"

private unsafe def expectEntryResult
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body : String)
    (expected : ProofForgeV2.Source.AstV1.TypeV1) : IO Unit := do
  let source := itemSource body
  match ← session.selectProgramV1 source ("<type-surface-" ++ label ++ ">")
      "Tests.ProgramV1TypeSurface" none with
  | .error error => throw <| IO.userError s!"'{label}' failed: {error.render}"
  | .ok value =>
      let items := value.program.items
      unless items.size == 1 || items.size == 2 do
        throw <| IO.userError s!"'{label}' expected 1 or 2 items, got {items.size}"
      match items[0]? with
      | some (ProgramItemV1.entry declaration) =>
          unless declaration.result == expected do
            throw <| IO.userError
              s!"'{label}' expected {repr expected}, got {repr declaration.result}"
      | other =>
          throw <| IO.userError s!"'{label}' expected entry, got {repr other}"

private unsafe def expectViewResult
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body : String)
    (expected : ProofForgeV2.Source.AstV1.TypeV1) : IO Unit := do
  let source := itemSource body
  match ← session.selectProgramV1 source ("<type-surface-" ++ label ++ ">")
      "Tests.ProgramV1TypeSurface" none with
  | .error error => throw <| IO.userError s!"'{label}' failed: {error.render}"
  | .ok value =>
      let items := value.program.items
      unless items.size == 1 || items.size == 2 do
        throw <| IO.userError s!"'{label}' expected 1 or 2 items, got {items.size}"
      match items[0]? with
      | some (ProgramItemV1.view declaration) =>
          unless declaration.result == expected do
            throw <| IO.userError
              s!"'{label}' expected {repr expected}, got {repr declaration.result}"
      | other =>
          throw <| IO.userError s!"'{label}' expected view, got {repr other}"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  let source := itemSource body
  match ← session.selectProgramV1 source ("<type-surface-negative-" ++ label ++ ">")
      "Tests.ProgramV1TypeSurface" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      let rendered := error.render
      unless rendered.contains expected do
        throw <| IO.userError
          s!"negative '{label}' expected '{expected}', got '{rendered}'"

/-- TST-SRC-D1-03 type-surface slice: direct ProgramV1 pfType accepts the full
prefix-atom EBNF surface and preserves exact TypeV1/bytes/hash identity. -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let bn254_fr ← nameComponent "bn254_fr"
  let choice ← nameComponent "Choice"
  let token ← nameComponent "Token"

  -- Primitive leaves in state position.
  expectType session "bool" "  state s : Bool\n" .bool
  expectType session "unit" "  state s : Unit\n" .unit
  expectType session "principal" "  state s : Principal\n" .principal
  expectType session "uint8" "  state s : UInt8\n" (.uint 8)
  expectType session "uint16" "  state s : UInt16\n" (.uint 16)
  expectType session "uint32" "  state s : UInt32\n" (.uint 32)
  expectType session "uint64" "  state s : UInt64\n" (.uint 64)
  expectType session "uint128" "  state s : UInt128\n" (.uint 128)
  expectType session "uint256" "  state s : UInt256\n" (.uint 256)
  expectType session "int8" "  state s : Int8\n" (.int 8)
  expectType session "int16" "  state s : Int16\n" (.int 16)
  expectType session "int32" "  state s : Int32\n" (.int 32)
  expectType session "int64" "  state s : Int64\n" (.int 64)
  expectType session "int128" "  state s : Int128\n" (.int 128)
  expectType session "int256" "  state s : Int256\n" (.int 256)

  -- Named single-component type.
  expectType session "named" "  state s : Choice\n" (.named choice)

  -- Bytes with canonical length spelling.
  expectType session "bytes" "  state s : Bytes 32\n" (.bytes 32)

  -- Field with the only supported identifier.
  expectType session "field" "  state s : Field bn254_fr\n" (.field bn254_fr)

  -- Option and Array special forms.
  expectType session "option-primitive" "  state s : Option UInt64\n"
    (.option (.uint 64))
  expectType session "array-primitive" "  state s : Array UInt64 4\n"
    (.array (.uint 64) 4)
  expectType session "option-array" "  state s : Option Array UInt64 4\n"
    (.option (.array (.uint 64) 4))
  expectType session "array-option" "  state s : Array Option UInt64 4\n"
    (.array (.option (.uint 64)) 4)
  expectType session "array-field" "  state s : Array Field bn254_fr 4\n"
    (.array (.field bn254_fr) 4)
  expectType session "array-bytes" "  state s : Array Bytes 8 4\n"
    (.array (.bytes 8) 4)
  expectType session "nested-option" "  state s : Option Option UInt64\n"
    (.option (.option (.uint 64)))
  expectType session "array-array" "  state s : Array Array UInt64 2 3\n"
    (.array (.array (.uint 64) 2) 3)

  -- Map forms (new surface).
  expectType session "map-primitive" "  state s : Map UInt64 Bool\n"
    (.map (.uint 64) .bool)
  expectType session "map-nested-option" "  state s : Map UInt64 Option UInt64\n"
    (.map (.uint 64) (.option (.uint 64)))
  expectType session "map-nested-array" "  state s : Map UInt64 Array UInt64 4\n"
    (.map (.uint 64) (.array (.uint 64) 4))
  expectType session "map-nested-map" "  state s : Map UInt64 Map Bool UInt64\n"
    (.map (.uint 64) (.map .bool (.uint 64)))
  expectType session "map-escaped-key" "  state s : Map «Token» Bool\n"
    (.map (.named token) .bool)

  -- Zero-length Bytes/Array are valid surface spellings.
  expectType session "bytes-zero" "  state s : Bytes 0\n" (.bytes 0)
  expectType session "array-zero" "  state s : Array UInt64 0\n"
    (.array (.uint 64) 0)

  -- Const, param and result positions.
  expectConstType session "const-type"
    "  const c : Map UInt64 Bool := 0\n"
    (.map (.uint 64) .bool)
  expectEntryResult session "param-result-type"
    "  entry e(x : Map UInt64 Bool) : Map UInt64 Bool do\n    return 0\n"
    (.map (.uint 64) .bool)
  expectViewResult session "view-result-type"
    "  view v() : Map UInt64 Bool do\n    return 0\n"
    (.map (.uint 64) .bool)

  -- Canonical byte/hash binding for type changes.
  let baseSource := itemSource "  state s : UInt64\n"
  let modifiedSource := itemSource "  state s : UInt8\n"
  let base ← match ← session.selectProgramV1 baseSource "<type-hash-base>"
      "Tests.ProgramV1TypeSurface" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  let modified ← match ← session.selectProgramV1 modifiedSource "<type-hash-modified>"
      "Tests.ProgramV1TypeSurface" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  let baseBytes ← match canonicalValidatedSourceAstBytesV1 base with
  | .ok bytes => pure bytes
  | .error message => throw <| IO.userError message
  let modifiedBytes ← match canonicalValidatedSourceAstBytesV1 modified with
  | .ok bytes => pure bytes
  | .error message => throw <| IO.userError message
  unless baseBytes != modifiedBytes do
    throw <| IO.userError "different types produced identical canonical bytes"
  let baseHash ← match sourceHashV1 base with
  | .ok digest => pure digest
  | .error message => throw <| IO.userError message
  let modifiedHash ← match sourceHashV1 modified with
  | .ok digest => pure digest
  | .error message => throw <| IO.userError message
  unless baseHash != modifiedHash do
    throw <| IO.userError "different types produced identical source hash"

  -- Ordinary/escaped named-type canonical equality.
  let ordinary ← match ← session.selectProgramV1
      (itemSource "  state s : Token\n") "<type-name-ordinary>"
      "Tests.ProgramV1TypeSurface" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  let escaped ← match ← session.selectProgramV1
      (itemSource "  state s : «Token»\n") "<type-name-escaped>"
      "Tests.ProgramV1TypeSurface" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render
  let ordinaryBytes ← match canonicalValidatedSourceAstBytesV1 ordinary with
  | .ok bytes => pure bytes
  | .error message => throw <| IO.userError message
  let escapedBytes ← match canonicalValidatedSourceAstBytesV1 escaped with
  | .ok bytes => pure bytes
  | .error message => throw <| IO.userError message
  unless ordinaryBytes == escapedBytes do
    throw <| IO.userError "ordinary and escaped named type produced different canonical bytes"
  let ordinaryHash ← match sourceHashV1 ordinary with
  | .ok digest => pure digest
  | .error message => throw <| IO.userError message
  let escapedHash ← match sourceHashV1 escaped with
  | .ok digest => pure digest
  | .error message => throw <| IO.userError message
  unless ordinaryHash == escapedHash do
    throw <| IO.userError "ordinary and escaped named type produced different source hashes"

  -- Negative matrix with exact diagnostics.
  expectReject session "map-missing-key"
    "  state s : Map\n" "unsupported portable type"
  expectReject session "map-missing-value"
    "  state s : Map UInt64\n" "unsupported portable type"
  expectReject session "map-trailing"
    "  state s : Map UInt64 Bool Extra\n" "unsupported portable type"
  -- Escaped type-constructor spellings at the leading position are
  -- parser-boundary rejects because the prefix rule matches the literal
  -- constructor token.
  expectReject session "escaped-map-constructor"
    "  state s : «Map» UInt64 Bool\n" "Lean parser rejected source"
  expectReject session "qualified-named-type"
    "  state s : Foo.Bar\n" "unsupported portable type"
  expectReject session "map-qualified-key"
    "  state s : Map Foo.Bar Bool\n" "unsupported portable type"
  expectReject session "map-escaped-option-key"
    "  state s : Map «Option» UInt64 Bool\n" "unsupported portable type"
  expectReject session "option-missing-payload"
    "  state s : Option\n" "unsupported portable type"
  expectReject session "array-missing-length"
    "  state s : Array UInt64\n" "unsupported portable type"
  expectReject session "array-map-element"
    "  state s : Array Map UInt64 Bool 4\n" "Lean parser rejected source"
  expectReject session "option-map-element"
    "  state s : Option Map UInt64 Bool\n" "unsupported portable type"
  expectReject session "array-malformed-map-element"
    "  state s : Array Map 4\n" "unsupported portable type"
  expectReject session "bytes-missing-length"
    "  state s : Bytes\n" "unsupported portable type"
  expectReject session "bytes-leading-zero"
    "  state s : Bytes 032\n" "unsupported portable type"
  expectReject session "bytes-over-limit"
    "  state s : Bytes 4097\n" "unsupported portable type"
  expectReject session "array-length-leading-zero"
    "  state s : Array UInt64 032\n" "unsupported portable type"
  expectReject session "array-length-over-limit"
    "  state s : Array UInt64 4097\n" "unsupported portable type"
  expectReject session "field-wrong-id"
    "  state s : Field bls12_381\n" "unsupported portable type"
  expectReject session "field-escaped-id"
    "  state s : Field «bn254_fr»\n" "unsupported portable type"
  expectReject session "escaped-primitive"
    "  state s : «UInt64»\n" "unsupported portable type"
  expectReject session "escaped-option-constructor"
    "  state s : «Option» UInt64\n" "unsupported portable type"
  expectReject session "reserved-named-type"
    "  state s : «state»\n" "reserved portable identifier 'state'"
  expectReject session "line-broken-map"
    "  state s : Map\n    UInt64 Bool\n" "unsupported portable type"

end Tests.Language.ProgramV1TypeSurface
