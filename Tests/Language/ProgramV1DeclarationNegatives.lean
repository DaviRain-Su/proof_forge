import Tests.Language.ParserSession
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.ValidatedSourceV1

namespace Tests.Language.ProgramV1DeclarationNegatives

open ProofForgeV2
open ProofForgeV2.Source.AstProgramItemV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def sourceHeader : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n"

/-- Build a ProgramV1 source with the given name and declaration body, plus an
entry so that validator rejections target the body rather than a missing entry/view. -/
private def programSource (body : String) : String :=
  sourceHeader ++
  "program P where\n" ++
  body ++ "\n" ++
  "  entry ok() : UInt64 do\n" ++
  "    return 0\n"

private unsafe def expectReject
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body expected : String) : IO Unit := do
  match ← session.selectProgramV1 (programSource body)
      ("<program-v1-decl-neg-" ++ label ++ ">")
      "Tests.ProgramV1DeclarationNegatives" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      unless error.code == "PF-SRC-INVALID" && error.message == expected do
        throw <| IO.userError
          s!"negative '{label}' expected PF-SRC-INVALID: '{expected}', got {error.code}: '{error.message}'"

private unsafe def expectRejectSource
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label source expected : String) : IO Unit := do
  match ← session.selectProgramV1 source
      ("<program-v1-decl-neg-" ++ label ++ ">")
      "Tests.ProgramV1DeclarationNegatives" none with
  | .ok value =>
      throw <| IO.userError s!"negative '{label}' unexpectedly decoded: {repr value.program.items}"
  | .error error =>
      unless error.code == "PF-SRC-INVALID" && error.message == expected do
        throw <| IO.userError
          s!"negative '{label}' expected PF-SRC-INVALID: '{expected}', got {error.code}: '{error.message}'"

private def multiProgramSource (programs : String) : String :=
  sourceHeader ++ programs

private unsafe def expectDecode
    (session : ProofForgeV2.Language.Loader.ParserSession)
    (label body : String) : IO Unit := do
  match ← session.selectProgramV1 (programSource body)
      ("<program-v1-decl-pos-" ++ label ++ ">")
      "Tests.ProgramV1DeclarationNegatives" none with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"positive '{label}' unexpectedly rejected: {error.render}"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared

  -- Positive sanity: whole-escaped dotted single-component names remain legal
  -- because the raw payload is one component.
  expectDecode session "whole-escaped-state-name" "  state «Foo.Bar» : UInt64"
  expectDecode session "whole-escaped-field-name" "  struct S where\n    «Foo.Bar» : UInt64"
  expectDecode session "whole-escaped-variant-name" "  enum E where\n    | «Foo.Bar»"
  expectDecode session "whole-escaped-param-name"
    "  fn f(«Foo.Bar» : UInt64) : UInt64 do\n    return 0"

  -- Reserved / qualified declaration names.
  expectReject session "reserved-state-name" "  state state : UInt64"
    "Lean parser rejected source: failed to parse file"
  expectReject session "escaped-reserved-state-name" "  state «state» : UInt64"
    "reserved portable identifier 'state'"
  expectReject session "qualified-state-name" "  state Foo.state : UInt64"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-struct-name" "  struct struct where\n    value : UInt64"
    "reserved portable identifier 'struct'"
  expectReject session "escaped-reserved-struct-name" "  struct «struct» where\n    value : UInt64"
    "reserved portable identifier 'struct'"
  expectReject session "qualified-struct-name" "  struct Foo.struct where\n    value : UInt64"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-enum-name" "  enum enum where\n    | Value"
    "reserved portable identifier 'enum'"
  expectReject session "escaped-reserved-enum-name" "  enum «enum» where\n    | Value"
    "reserved portable identifier 'enum'"
  expectReject session "qualified-enum-name" "  enum Foo.enum where\n    | Value"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-const-name" "  const const : UInt64 := 1"
    "reserved portable identifier 'const'"
  expectReject session "escaped-reserved-const-name" "  const «const» : UInt64 := 1"
    "reserved portable identifier 'const'"
  expectReject session "qualified-const-name" "  const Foo.const : UInt64 := 1"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-event-name" "  event event()"
    "reserved portable identifier 'event'"
  expectReject session "escaped-reserved-event-name" "  event «event»()"
    "reserved portable identifier 'event'"
  expectReject session "qualified-event-name" "  event Foo.event()"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-error-name" "  error error"
    "reserved portable identifier 'error'"
  expectReject session "escaped-reserved-error-name" "  error «error»"
    "reserved portable identifier 'error'"
  expectReject session "qualified-error-name" "  error Foo.error"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-entry-name" "  entry entry() : UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "escaped-reserved-entry-name" "  entry «entry»() : UInt64 do\n    return 0"
    "reserved portable identifier 'entry'"
  expectReject session "qualified-entry-name" "  entry Foo.entry() : UInt64 do\n    return 0"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-view-name" "  view view() : UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "escaped-reserved-view-name" "  view «view»() : UInt64 do\n    return 0"
    "reserved portable identifier 'view'"
  expectReject session "qualified-view-name" "  view Foo.view() : UInt64 do\n    return 0"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-fn-name" "  fn fn() : UInt64 do\n    return 0"
    "reserved portable identifier 'fn'"
  expectReject session "escaped-reserved-fn-name" "  fn «fn»() : UInt64 do\n    return 0"
    "reserved portable identifier 'fn'"
  expectReject session "qualified-fn-name" "  fn Foo.fn() : UInt64 do\n    return 0"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-invariant-name" "  invariant invariant : true"
    "reserved portable identifier 'invariant'"
  expectReject session "escaped-reserved-invariant-name" "  invariant «invariant» : true"
    "reserved portable identifier 'invariant'"
  expectReject session "qualified-invariant-name" "  invariant Foo.invariant : true"
    "source name component must contain exactly one Lean Name component"

  expectReject session "reserved-proof-name" "  proof proof using Foo.Bar"
    "reserved portable identifier 'proof'"
  expectReject session "escaped-reserved-proof-name" "  proof «proof» using Foo.Bar"
    "reserved portable identifier 'proof'"
  expectReject session "qualified-proof-name" "  proof Foo.proof using Foo.Bar"
    "source name component must contain exactly one Lean Name component"

  -- init has no user-declared name; exercise malformed syntax and reserved params.
  expectReject session "init-missing-parens" "  init do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "init-missing-do" "  init(x : UInt64)\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "escaped-reserved-init-param" "  init(«state» : UInt64) do\n    return 0"
    "reserved portable identifier 'state'"
  expectReject session "multi-init" "  init() do\n    return 0\n  init(x : UInt64) do\n    return 0"
    "program must declare at most one init"

  -- extension id is qualified by design; cover malformed syntax and reserved components.
  expectReject session "extension-missing-id" "  requires extension"
    "unsupported portable program item"
  expectReject session "extension-missing-version" "  requires extension proof.forge.feature"
    "Lean parser rejected source: failed to parse file"
  expectReject session "extension-bad-version" "  requires extension proof.forge.feature version \"01.0.0\"\n    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\""
    "leading zero forbidden"
  expectReject session "extension-bad-digest" "  requires extension proof.forge.feature version \"1.0.0\"\n    digest \"sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\""
    "digest hex must be lowercase [0-9a-f]"
  expectReject session "extension-string-id"
    "  requires extension \"not-an-id\" version \"1.0.0\"\n    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\""
    "Lean parser rejected source: failed to parse file"
  expectReject session "extension-numeric-id"
    "  requires extension 123 version \"1.0.0\"\n    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\""
    "Lean parser rejected source: failed to parse file"

  -- Malformed syntax per declaration kind.
  expectReject session "state-missing-colon" "  state x UInt64"
    "Lean parser rejected source: failed to parse file"
  expectReject session "state-missing-type" "  state x"
    "Lean parser rejected source: failed to parse file"
  expectReject session "state-extra-payload" "  state x : UInt64 := 1"
    "Lean parser rejected source: failed to parse file"

  expectReject session "struct-missing-where" "  struct S"
    "unsupported portable program item"
  expectReject session "struct-field-missing-type" "  struct S where\n    x"
    "Lean parser rejected source: failed to parse file"
  expectReject session "struct-missing-field-type-colon" "  struct S where\n    x UInt64"
    "Lean parser rejected source: failed to parse file"

  expectReject session "enum-missing-where" "  enum E"
    "unsupported portable program item"
  expectReject session "enum-missing-variant" "  enum E where\n    |"
    "Lean parser rejected source: failed to parse file"
  expectReject session "enum-empty-payload" "  enum E where\n    | Empty()"
    "enum variant 'Empty' payload must contain at least one type"

  expectReject session "const-missing-colon" "  const x UInt64 := 1"
    "Lean parser rejected source: failed to parse file"
  expectReject session "const-missing-type" "  const x := 1"
    "Lean parser rejected source: failed to parse file"
  expectReject session "const-missing-value" "  const x : UInt64 :="
    "Lean parser rejected source: failed to parse file"

  expectReject session "event-missing-parens" "  event E"
    "unsupported portable program item"
  expectReject session "event-malformed-parens" "  event E("
    "Lean parser rejected source: failed to parse file"

  expectReject session "error-malformed-parens" "  error E("
    "Lean parser rejected source: failed to parse file"

  expectReject session "fn-missing-parens" "  fn f : UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "fn-missing-arrow" "  fn f() UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "fn-missing-do" "  fn f() : UInt64 return 0"
    "Lean parser rejected source: failed to parse file"

  expectReject session "entry-missing-parens" "  entry f : UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "entry-missing-arrow" "  entry f() UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "entry-missing-do" "  entry f() : UInt64 return 0"
    "Lean parser rejected source: failed to parse file"

  expectReject session "view-missing-parens" "  view f : UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "view-missing-arrow" "  view f() UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "view-missing-do" "  view f() : UInt64 return 0"
    "Lean parser rejected source: failed to parse file"

  expectReject session "invariant-missing-colon" "  invariant x true"
    "Lean parser rejected source: failed to parse file"
  expectReject session "invariant-missing-name" "  invariant : true"
    "Lean parser rejected source: failed to parse file"

  expectReject session "proof-missing-using" "  proof x"
    "unsupported portable program item"
  expectReject session "proof-missing-invariant" "  proof using Foo.Bar"
    "Lean parser rejected source: failed to parse file"
  expectReject session "proof-unqualified-theorem" "  invariant x : true\n  proof x using y"
    "proof theorem name must contain at least two components"
  expectReject session "proof-unknown-invariant" "  proof missing using X.Y"
    "proof reference names unknown invariant 'missing'"

  -- Empty aggregates are rejected during canonical encoding.
  expectReject session "empty-struct" "  struct Empty where"
    "struct fields must be nonempty"
  expectReject session "empty-enum" "  enum Empty where"
    "enum variants must be nonempty"

  -- Duplicate declaration names.
  expectReject session "dup-state" "  state a : UInt64\n  state a : UInt64"
    "program contains duplicate state declarations"
  expectReject session "dup-entry" "  entry a() : UInt64 do\n    return 0\n  entry a() : UInt64 do\n    return 0"
    "program contains duplicate entry/view declarations"
  expectReject session "dup-view" "  view a() : UInt64 do\n    return 0\n  view a() : UInt64 do\n    return 0"
    "program contains duplicate entry/view declarations"
  expectReject session "dup-event" "  event A()\n  event A()"
    "program contains duplicate event declarations"
  expectReject session "dup-error" "  error A\n  error A"
    "program contains duplicate error declarations"
  expectReject session "dup-struct" "  struct S where\n    x : UInt64\n  struct S where\n    y : Bool"
    "program contains duplicate struct declarations"
  expectReject session "dup-enum" "  enum E where\n    | X\n  enum E where\n    | Y"
    "program contains duplicate enum declarations"
  expectReject session "dup-const" "  const a : UInt64 := 1\n  const a : UInt64 := 2"
    "program contains duplicate const declarations"
  expectReject session "dup-fn" "  fn a() : UInt64 do\n    return 0\n  fn a() : UInt64 do\n    return 0"
    "program contains duplicate fn declarations"
  expectReject session "dup-callable-entry-fn" "  entry a() : UInt64 do\n    return 0\n  fn a() : UInt64 do\n    return 0"
    "program contains duplicate callable declarations"
  expectReject session "dup-callable-view-fn" "  view a() : UInt64 do\n    return 0\n  fn a() : UInt64 do\n    return 0"
    "program contains duplicate callable declarations"
  expectReject session "dup-invariant" "  invariant a : true\n  invariant a : true"
    "program contains duplicate invariant declarations"
  expectReject session "dup-extension"
    ("  requires extension proof.forge.feature version \"1.0.0\"\n" ++
     "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"\n" ++
     "  requires extension proof.forge.feature version \"1.0.0\"\n" ++
     "    digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\"")
    "program contains duplicate extension requirements"
  expectReject session "dup-proof" "  invariant a : true\n  proof a using X.Y\n  proof a using X.Z"
    "program contains duplicate proof references"

  expectRejectSource session "dup-program"
    (multiProgramSource
      ("program P where\n" ++
       "  entry a() : UInt64 do\n" ++
       "    return 0\n\n" ++
       "program P where\n" ++
       "  entry a() : UInt64 do\n" ++
       "    return 0\n"))
    "duplicate program 'Tests.ProgramV1DeclarationNegatives.P'"

  -- Duplicate fields, variants, and parameters.
  expectReject session "dup-struct-field" "  struct S where\n    x : UInt64\n    x : Bool"
    "struct 'S' contains duplicate fields"
  expectReject session "dup-enum-variant" "  enum E where\n    | X\n    | X"
    "enum 'E' contains duplicate variants"
  expectReject session "dup-init-param" "  init(x : UInt64, x : UInt64) do\n    return 0"
    "initializer contains duplicate parameters"
  expectReject session "dup-event-param" "  event E(x : UInt64, x : UInt64)"
    "event 'E' contains duplicate parameters"
  expectReject session "dup-error-param" "  error E(x : UInt64, x : UInt64)"
    "error 'E' contains duplicate parameters"
  expectReject session "dup-entry-param" "  entry a(x : UInt64, x : UInt64) : UInt64 do\n    return 0"
    "entry 'a' contains duplicate parameters"
  expectReject session "dup-view-param" "  view a(x : UInt64, x : UInt64) : UInt64 do\n    return 0"
    "view 'a' contains duplicate parameters"
  expectReject session "dup-fn-param" "  fn a(x : UInt64, x : UInt64) : UInt64 do\n    return 0"
    "fn 'a' contains duplicate parameters"

  -- Source-order error priority: within a category the first offending name wins;
  -- across categories the validator's fixed category order dominates.
  expectReject session "priority-state-before-const" "  state a : UInt64\n  state a : UInt64\n  const a : UInt64 := 1"
    "program contains duplicate state declarations"
  expectReject session "priority-struct-checked-before-enum"
    "  enum E where\n    | X\n  enum E where\n    | Y\n  struct S where\n    x : UInt64\n  struct S where\n    y : Bool"
    "program contains duplicate struct declarations"
  expectReject session "priority-field-first" "  struct S where\n    x : UInt64\n    x : Bool\n    y : UInt64\n    y : Bool"
    "struct 'S' contains duplicate fields"
  expectReject session "priority-variant-first" "  enum E where\n    | X\n    | X\n    | Y\n    | Y"
    "enum 'E' contains duplicate variants"
  expectReject session "priority-param-first" "  fn a(x : UInt64, x : UInt64, y : UInt64, y : UInt64) : UInt64 do\n    return 0"
    "fn 'a' contains duplicate parameters"

  -- Reserved components: escaped forms reach decodeNameV1 and fail with the
  -- reserved identifier diagnostic; ordinary keyword spellings are rejected at
  -- the parser boundary (covered above by malformed-syntax failures).
  expectReject session "reserved-struct-field-escaped" "  struct S where\n    «state» : UInt64"
    "reserved portable identifier 'state'"
  expectReject session "reserved-enum-variant-escaped" "  enum E where\n    | «state»"
    "reserved portable identifier 'state'"
  expectReject session "reserved-init-param-escaped" "  init(«state» : UInt64) do\n    return 0"
    "reserved portable identifier 'state'"
  expectReject session "reserved-event-param-escaped" "  event E(«state» : UInt64)"
    "reserved portable identifier 'state'"
  expectReject session "reserved-error-param-escaped" "  error E(«state» : UInt64)"
    "reserved portable identifier 'state'"
  expectReject session "reserved-entry-param-escaped" "  entry a(«state» : UInt64) : UInt64 do\n    return 0"
    "reserved portable identifier 'state'"
  expectReject session "reserved-view-param-escaped" "  view a(«state» : UInt64) : UInt64 do\n    return 0"
    "reserved portable identifier 'state'"
  expectReject session "reserved-fn-param-escaped" "  fn a(«state» : UInt64) : UInt64 do\n    return 0"
    "reserved portable identifier 'state'"

  -- Qualified component names on fields/variants/params reach decodeNameV1.
  expectReject session "qualified-struct-field" "  struct S where\n    Foo.x : UInt64"
    "source name component must contain exactly one Lean Name component"
  expectReject session "qualified-enum-variant" "  enum E where\n    | Foo.x"
    "source name component must contain exactly one Lean Name component"
  expectReject session "qualified-fn-param" "  fn a(Foo.x : UInt64) : UInt64 do\n    return 0"
    "source name component must contain exactly one Lean Name component"

  -- Visibility misuse.
  expectReject session "state-unknown-visibility" "  state secret x : UInt64"
    "Lean parser rejected source: failed to parse file"
  expectReject session "struct-public-visibility" "  struct public S where\n    x : UInt64"
    "Lean parser rejected source: failed to parse file"
  expectReject session "fn-public-visibility" "  fn public f() : UInt64 do\n    return 0"
    "Lean parser rejected source: failed to parse file"
  expectReject session "enum-private-visibility" "  enum private E where\n    | X"
    "Lean parser rejected source: failed to parse file"
  expectReject session "invariant-private-visibility" "  invariant private x : true"
    "Lean parser rejected source: failed to parse file"
  expectReject session "const-public-visibility" "  const public x : UInt64 := 1"
    "Lean parser rejected source: failed to parse file"

end Tests.Language.ProgramV1DeclarationNegatives
