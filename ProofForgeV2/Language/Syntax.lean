import Lean
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Language.ProgramExport
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.ValidatedSourceV1
import Std.Data.HashSet

open Lean Parser Command
open ProofForgeV2
open ProofForgeV2.Language.ProgramExport
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

namespace ProofForgeV2.Language

declare_syntax_cat pfType
/-- Parse a leading identifier plus an optional same-line second atom that is
either an identifier (Field payload / named second atom) or a numeral (Bytes
length). Line equality prevents the following program item from becoming part
of the type. Sole non-constructor `pfType` alternative after B1R fixed-depth
deletion. -/
@[pfType_parser] def portableType := leading_parser
  withPosition (ident >> optional (checkLineEq >> (ident <|> numLit)))
/-- Same-line prefix-atom form for recursive `Option` / `Array` / `Map`
constructors. Payloads may nest arbitrary portable or prefix types (including
`Array Map`, `Option Map`, shallow Array/Option/Field/Bytes, and deeper
Option/Array chains). Sole constructor `pfType` alternative; all fixed-depth
combo parsers have been deleted. The sole decoder path is
`collectTypeAtomSyntaxV1` → `decodeTypeV1At` (with canonical-preorder syntax
anchors). -/
@[pfType_parser default+1] def prefixType := leading_parser
  withPosition (
    (nonReservedSymbol "Option " (includeIdent := true) <|>
      nonReservedSymbol "Array " (includeIdent := true) <|>
      nonReservedSymbol "Map " (includeIdent := true)) >>
    many (checkLineEq >> (ident <|> numLit)))

declare_syntax_cat pfParam
syntax ident " : " pfType : pfParam
syntax "public " ident " : " pfType : pfParam
syntax "private " ident " : " pfType : pfParam
syntax "commitment " ident " : " pfType : pfParam

declare_syntax_cat pfExpr
declare_syntax_cat pfPlace
syntax ident : pfPlace
syntax:max pfPlace "." ident : pfPlace
syntax:max pfPlace "[" pfExpr "]" : pfPlace
syntax num : pfExpr
syntax str : pfExpr
syntax pfPlace : pfExpr
syntax:max ident "(" pfExpr,* ")" : pfExpr
syntax:75 "-" pfExpr:75 : pfExpr
syntax:75 "~" pfExpr:75 : pfExpr
syntax:75 "!" pfExpr:75 : pfExpr
syntax:60 pfExpr:60 " << " pfExpr:61 : pfExpr
syntax:60 pfExpr:60 " >> " pfExpr:61 : pfExpr
syntax:50 pfExpr:51 " == " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " != " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " < " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " <= " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " > " pfExpr:51 : pfExpr
syntax:50 pfExpr:51 " >= " pfExpr:51 : pfExpr
syntax:45 pfExpr:45 " & " pfExpr:46 : pfExpr
syntax:40 pfExpr:40 " ^ " pfExpr:41 : pfExpr
/-- Bitwise-or keeps its original precedence (35, lhs 35, rhs 36) but rejects
the operator when a line break precedes it: `|` is also the match arm
delimiter, and without this guard an arm body like `return 0` absorbs the
next arm's bar as a bit-or continuation. All other infix tokens cannot start
an arm. -/
@[pfExpr_parser] def bitOrExpr := trailing_parser:35:35
  notFollowedBy (checkLinebreakBefore) "no line break" >> " | " >> categoryParser `pfExpr 36
syntax:30 pfExpr:30 " && " pfExpr:31 : pfExpr
syntax:25 pfExpr:25 " || " pfExpr:26 : pfExpr
syntax:65 pfExpr:65 " + " pfExpr:66 : pfExpr
syntax:65 pfExpr:65 " - " pfExpr:66 : pfExpr
syntax:70 pfExpr:70 " * " pfExpr:71 : pfExpr
syntax:70 pfExpr:70 " / " pfExpr:71 : pfExpr
syntax:70 pfExpr:70 " % " pfExpr:71 : pfExpr
/-- Primary parenthesized grouping. High-precedence outer result; inner uses min
precedence 0 so full `+`/`-`/`*` expressions remain legal inside. Desugars only. -/
syntax:max "(" pfExpr:0 ")" : pfExpr
/-- Exact bare `true` bool literal (contextual, not a host Lean keyword).
Higher priority than generic identifier; no low fallback. -/
@[pfExpr_parser default+1] def boolTrueExpr := leading_parser
  nonReservedSymbol "true" (includeIdent := true)
/-- Exact bare `false` bool literal (contextual, not a host Lean keyword).
Higher priority than generic identifier; no low fallback. -/
@[pfExpr_parser default+1] def boolFalseExpr := leading_parser
  nonReservedSymbol "false" (includeIdent := true)
/-- Expression-level match: `match Expr with | Pattern => Expr ...`. Leading
precedence 0 prevents it from becoming a binary/unary operand without grouping;
arms must start on a new line aligned with `match`. -/
@[pfExpr_parser] def matchExpr := leading_parser:0 withPosition (
  "match " >> categoryParser `pfExpr 0 >> " with" >>
  checkLinebreakBefore >> checkColEq >> many1Indent (categoryParser `pfExprMatchArm 0))

declare_syntax_cat pfPattern
syntax "_" : pfPattern
syntax ident : pfPattern
syntax num : pfPattern
syntax str : pfPattern
/-- Constructor pattern: `QualifiedId(PatternList?)`. Max precedence leading form so
bare `ident` remains a bind pattern and call-like shapes route here only when followed
by `(`; empty argument lists decode to `#[]`. -/
syntax:max ident "(" pfPattern,* ")" : pfPattern
@[pfPattern_parser default+1] def boolTruePattern := leading_parser
  nonReservedSymbol "true" (includeIdent := true)
@[pfPattern_parser default+1] def boolFalsePattern := leading_parser
  nonReservedSymbol "false" (includeIdent := true)

declare_syntax_cat pfExprMatchArm
/-- One expression match arm: `| Pattern => Expr`. The value is a full
precedence-0 expression, so nested match expressions and grouped operands are
legal; `do` blocks are rejected here because this is the expression-level arm. -/
@[pfExprMatchArm_parser default+1] def exprMatchArm := leading_parser withPosition (
  "| " >> categoryParser `pfPattern 0 >> " => " >> categoryParser `pfExpr 0)

declare_syntax_cat pfStmtMatchArm
/-- One statement match arm: `| Pattern => do` plus an indented nonempty block. Mirrors
ifStmt/forStmt indentation discipline; the bar column is owned by the enclosing
match, the body must be strictly deeper. -/
@[pfStmtMatchArm_parser default+1] def stmtMatchArm := leading_parser withPosition (
  "| " >> categoryParser `pfPattern 0 >> " => " >> "do" >>
  checkLinebreakBefore >> checkColGt >> many1Indent (categoryParser `pfStmt 0))

declare_syntax_cat pfStmt
syntax pfPlace " := " pfExpr : pfStmt
@[pfStmt_parser default+1] def returnValueStmt := leading_parser
  withPosition ("return " >> (checkLineEq <|> checkColGt) >> categoryParser `pfExpr 0)
syntax "return" : pfStmt
syntax "call " ident "(" pfExpr,* ")" : pfStmt
syntax "schedule " ident "(" pfExpr,* ")" : pfStmt
syntax "assert " pfExpr " else " ident : pfStmt
syntax "assert " pfExpr : pfStmt
syntax "revert " ident "(" pfExpr,* ")" : pfStmt
syntax "revert " ident : pfStmt
syntax "emit " ident "(" pfExpr,* ")" : pfStmt
@[pfStmt_parser default+1] def ifStmt := leading_parser withPosition (
    "if " >> categoryParser `pfExpr 0 >> " then" >> checkLinebreakBefore >> checkColGt >>
    many1Indent (categoryParser `pfStmt 0) >>
    optional (checkColEq >> "else" >> checkLinebreakBefore >> checkColGt >>
      many1Indent (categoryParser `pfStmt 0)))
@[pfStmt_parser default+1] def matchStmt := leading_parser withPosition (
  "match " >> categoryParser `pfExpr 0 >> " with" >>
  checkLinebreakBefore >> checkColEq >> many1Indent (categoryParser `pfStmtMatchArm 0))
@[pfStmt_parser default+1] def forStmt := leading_parser withPosition (
    "for " >> ident >> checkLineEq >> " in " >> checkLineEq >> categoryParser `pfExpr 0 >>
    checkLineEq >> " ..< " >> checkLineEq >> categoryParser `pfExpr 0 >> checkLineEq >>
    " bounded " >> checkLineEq >> numLit >> checkLineEq >> " do" >> checkLinebreakBefore >>
    checkColGt >> many1Indent (categoryParser `pfStmt 0))
/-- Same-line annotated let (contextual, not a host Lean keyword). No low fallback. -/
@[pfStmt_parser default+1] def letStmtAnnotated := leading_parser
  withPosition (
    nonReservedSymbol "let " (includeIdent := true) >>
    checkLineEq >> ident >>
    checkLineEq >> " : " >> checkLineEq >> categoryParser `pfType 0 >>
    checkLineEq >> " := " >> checkLineEq >> categoryParser `pfExpr 0)
/-- Same-line omitted-type let (contextual, not a host Lean keyword). No low fallback. -/
@[pfStmt_parser default+1] def letStmtOmitted := leading_parser
  withPosition (
    nonReservedSymbol "let " (includeIdent := true) >>
    checkLineEq >> ident >>
    checkLineEq >> " := " >> checkLineEq >> categoryParser `pfExpr 0)

declare_syntax_cat pfAggregateMember
/-- Struct field: name, colon, then the sole `pfType` surface (`portableType` +
`prefixType`). Terminated by linebreak so the next field starts cleanly. Field
decode remains `collectTypeAtomSyntaxV1` → `decodeTypeV1At` with the field name
as the first flattened atom — no second type decoder. All specialized
fixed-depth aggregate-field alternatives have been deleted. -/
@[pfAggregateMember_parser] def aggregateField := leading_parser
  withPosition (ident >> " : " >> categoryParser `pfType 0 >> checkLinebreakBefore)
syntax "| " ident linebreak : pfAggregateMember
syntax "| " ident "(" sepBy(pfType, ", ") ")" linebreak : pfAggregateMember

declare_syntax_cat pfItem
@[pfItem_parser default+1] def bareErrorDecl := leading_parser
  withPosition (nonReservedSymbol "error " (includeIdent := true) >> checkLineEq >> ident >>
    checkLinebreakBefore)
syntax "state " ident " : " pfType : pfItem
syntax "state " "public " ident " : " pfType : pfItem
syntax "state " "private " ident " : " pfType : pfItem
syntax "state " "commitment " ident " : " pfType : pfItem
syntax ident ident "(" sepBy(pfParam, ", ") ")" : pfItem
syntax ident ident " where" ppLine manyIndent(pfAggregateMember) : pfItem
@[pfItem_parser default+1] def constDecl := leading_parser
  withPosition (nonReservedSymbol "const " (includeIdent := true) >> checkLineEq >> ident >>
    " : " >> categoryParser `pfType 0 >> " := " >> categoryParser `pfExpr 0)
@[pfItem_parser default+1] def invariantDecl := leading_parser
  withPosition (nonReservedSymbol "invariant " (includeIdent := true) >> checkLineEq >> ident >>
    " : " >> categoryParser `pfExpr 0)
@[pfItem_parser default+1] def extensionReq := leading_parser
  withPosition (nonReservedSymbol "requires " (includeIdent := true) >> checkLineEq >>
    nonReservedSymbol "extension " (includeIdent := true) >> checkLineEq >> ident >> checkLineEq >>
    nonReservedSymbol "version " (includeIdent := true) >> checkLineEq >> strLit >> ppLine >>
    withPosition (nonReservedSymbol "digest " (includeIdent := true) >> checkLineEq >> strLit))
@[pfItem_parser default+1] def proofDecl := leading_parser
  withPosition (nonReservedSymbol "proof " (includeIdent := true) >> checkLineEq >> ident >>
    checkLineEq >> nonReservedSymbol "using " (includeIdent := true) >> checkLineEq >> ident)
/-- Preserve invalid escaped/unknown contextual shapes long enough for the
shared decoder to emit the stable unsupported-item diagnostic. -/
@[pfItem_parser low] def unsupportedConstLikeDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> " : " >> categoryParser `pfType 0 >>
    " := " >> categoryParser `pfExpr 0)
@[pfItem_parser low] def unsupportedInvariantLikeDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> " : " >> categoryParser `pfExpr 0 >>
    checkLinebreakBefore)
@[pfItem_parser low] def unsupportedExtensionLikeReq := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLineEq >> ident >> checkLineEq >> ident >>
    checkLineEq >> strLit >> ppLine >> withPosition (ident >> checkLineEq >> strLit))
@[pfItem_parser low] def unsupportedProofIntroducer := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLineEq >>
    nonReservedSymbol "using " (includeIdent := true) >> checkLineEq >> ident)
@[pfItem_parser low] def unsupportedBareItemDecl := leading_parser
  withPosition (ident >> checkLineEq >> ident >> checkLinebreakBefore)
syntax ident ident "(" sepBy(pfParam, ", ") ")" (" : " pfType)? " do" ppLine manyIndent(pfStmt) : pfItem
syntax "init" "(" sepBy(pfParam, ", ") ")" " do" ppLine manyIndent(pfStmt) : pfItem
syntax "entry " ident "(" sepBy(pfParam, ", ") ")" (" : " pfType)? " do" ppLine manyIndent(pfStmt) : pfItem
syntax "view " ident "(" sepBy(pfParam, ", ") ")" (" : " pfType)? " do" ppLine manyIndent(pfStmt) : pfItem

syntax (name := programDecl) "program " ident " where" ppLine ppIndent(pfItem*) : command

/-- Maximum nodes in one portable decoder subtree, including its root. -/
def maxSyntaxNodes : Nat := 100000

/-- Maximum root-inclusive depth in one portable decoder subtree. -/
def maxSyntaxNesting : Nat := 256

/-- Count name components iteratively, returning `none` before exceeding `limit`. -/
def boundedNamePartCount (limit : Nat) (name : Name) : Option Nat := Id.run do
  let mut current := name
  let mut count := 0
  while current != .anonymous do
    if count >= limit then
      return none
    count := count + 1
    current := current.getPrefix
  return some count

/-- Iterative post-parser preflight over one portable Syntax subtree. This runs
before the recursive DSL decoder or macro expander; it does not protect Lean's
parser itself or impose an aggregate limit across multiple programs. -/
def preflightSyntax (root : Syntax) : CompileResult Unit := do
  let mut pending : Array (Syntax × Nat) := #[(root, 1)]
  let mut discovered := 1
  while !pending.isEmpty do
    let (current, nesting) := pending.back!
    pending := pending.pop
    if nesting > maxSyntaxNesting then
      throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
    match current with
    | .ident _ _ name _ =>
        if (boundedNamePartCount maxSyntaxNesting name).isNone then
          throw <| .resourceBound
            s!"portable identifier nesting exceeds limit {maxSyntaxNesting}"
    | _ => pure ()
    for child in current.getArgs do
      let childNesting := nesting + 1
      if childNesting > maxSyntaxNesting then
        throw <| .resourceBound s!"portable syntax exceeds nesting limit {maxSyntaxNesting}"
      if discovered >= maxSyntaxNodes then
        throw <| .resourceBound s!"portable syntax exceeds node limit {maxSyntaxNodes}"
      discovered := discovered + 1
      pending := pending.push (child, childNesting)

private def rawIdentifierText? : Syntax → Option String
  | .ident _ rawValue _ _ => some rawValue.toString
  | _ => none

private def decodePortableIdentifierName (name : String) : Except String String :=
  if name == "struct" || name == "enum" || name == "const" || name == "event" ||
      name == "error" || name == "fn" || name == "invariant" || name == "requires" ||
      name == "extension" || name == "version" || name == "digest" || name == "proof" ||
      name == "using" then
    .error s!"reserved portable identifier '{name}'"
  else
    .ok name

private def decodeExtensionId (stx : Syntax) : Except String String := do
  let id ← match rawIdentifierText? stx with
    | some value => pure value
    | none => throw "unsupported extension id"
  match ProofForgeV2.Core.Common.parseSchemaId id with
  | .ok _ => pure id
  | .error message => throw (message.replace "schema id" "extension id")

private def decodeExtensionVersion (stx : Syntax) : Except String String := do
  let value ← match stx.isStrLit? with
    | some value => pure value
    | none => throw "unsupported extension version literal"
  let parsed ← ProofForgeV2.Core.Common.parseSemVer value
  let canonical ← ProofForgeV2.Core.Common.renderSemVer parsed
  unless canonical == value do
    throw "extension version must use canonical exact SemVer"
  pure canonical

private def decodeExtensionDigest (stx : Syntax) : Except String String := do
  let value ← match stx.isStrLit? with
    | some value => pure value
    | none => throw "unsupported extension digest literal"
  let parsed ← ProofForgeV2.Core.Common.parseDigest value
  let canonical ← ProofForgeV2.Core.Common.renderDigest parsed
  unless canonical == value do
    throw "extension digest must use canonical sha256 spelling"
  pure canonical

private def decodeProofTheorem (stx : Syntax) : Except String (Array String) := do
  let mut components : Array String := #[]
  for component in stx.getId.components do
    match component with
    | .str .anonymous value =>
        components := components.push (← decodePortableIdentifierName value)
    | _ => throw "qualified-name component must use Lean identifier characters"
  let qualified ← ProofForgeV2.Core.Common.parseQualifiedName components
  let canonical ← ProofForgeV2.Core.Common.renderQualifiedNameComponents qualified
  unless canonical.size >= 2 do
    throw "proof theorem name must contain at least two components"
  pure canonical

private def decodeBytesLengthAtom (stx : Syntax) : Except String UInt32 := do
  unless stx.isOfKind numLitKind do
    throw "unsupported portable type"
  let spelling ← match stx.isLit? numLitKind with
    | some value => pure value
    | none => throw "unsupported portable type"
  if spelling.isEmpty || spelling.length > 4 then
    throw "unsupported portable type"
  if spelling.length > 1 && spelling.front == '0' then
    throw "unsupported portable type"
  let mut value : Nat := 0
  for c in spelling.toList do
    unless c.isDigit do
      throw "unsupported portable type"
    value := value * 10 + (c.toNat - '0'.toNat)
    if value > 4096 then
      throw "unsupported portable type"
  pure (UInt32.ofNat value)

private def decodeIntegerLiteralV1 (stx : Syntax) : Except String Nat := do
  unless stx.isOfKind numLitKind do
    throw "unsupported portable integer literal"
  let spelling ← match stx.isLit? numLitKind with
    | some value => pure value
    | none => throw "unsupported portable integer literal"
  let (base, digits) ← match spelling.toList with
    | '0' :: 'x' :: rest =>
        if rest.isEmpty then
          throw "integer literal must use unsigned decimal or lowercase 0x hexadecimal spelling"
        pure (16, rest)
    | rest => pure (10, rest)
  if digits.isEmpty then
    throw "integer literal must use unsigned decimal or lowercase 0x hexadecimal spelling"
  let limit : Nat := 2 ^ 256
  let mut value : Nat := 0
  for c in digits do
    let digit? : Option Nat :=
      if '0' ≤ c && c ≤ '9' then
        some (c.toNat - '0'.toNat)
      else if base == 16 && 'a' ≤ c && c ≤ 'f' then
        some (10 + c.toNat - 'a'.toNat)
      else if base == 16 && 'A' ≤ c && c ≤ 'F' then
        some (10 + c.toNat - 'A'.toNat)
      else
        none
    let digit ← match digit? with
      | some digit => pure digit
      | none =>
          throw "integer literal must use unsigned decimal or lowercase 0x hexadecimal spelling"
    value := value * base + digit
    if value ≥ limit then
      throw "integer literal exceeds UInt256"
  pure value

private def reservedPortableKeywords : Array String :=
  #["program", "where", "state", "struct", "enum", "const", "event", "error",
    "init", "entry", "view", "fn", "invariant", "requires", "extension",
    "version", "digest", "proof", "using", "do", "let", "if", "then", "else",
    "match", "with", "for", "in", "bounded", "assert", "revert", "emit",
    "return", "call", "schedule", "public", "private", "commitment", "true",
    "false"]

private def isReservedPortableTypeName (raw : String) : Bool :=
  reservedPortableKeywords.contains raw

private def primitiveTypeV1 (raw : String) : Option TypeV1 :=
  match raw with
  | "Bool" => some .bool
  | "UInt8" => some (.uint 8)
  | "UInt16" => some (.uint 16)
  | "UInt32" => some (.uint 32)
  | "UInt64" => some (.uint 64)
  | "UInt128" => some (.uint 128)
  | "UInt256" => some (.uint 256)
  | "Int8" => some (.int 8)
  | "Int16" => some (.int 16)
  | "Int32" => some (.int 32)
  | "Int64" => some (.int 64)
  | "Int128" => some (.int 128)
  | "Int256" => some (.int 256)
  | "Unit" => some .unit
  | "Principal" => some .principal
  | _ => none

private def isTypeConstructorNameV1 (raw : String) : Bool :=
  (primitiveTypeV1 raw).isSome || #["Option", "Array", "Map", "Bytes", "Field"].contains raw

private def typeConstructorAtomTextV1? : Syntax → Option String
  | .atom _ value =>
      if #["Option", "Array", "Map", "Bytes", "Field"].contains value then
        some value
      else
        none
  | _ => none

private def typeTokenTextV1? (stx : Syntax) : Option String :=
  rawIdentifierText? stx <|> typeConstructorAtomTextV1? stx

/-- V1-only type token collector. Legacy decoding intentionally omits contextual
constructor atoms from `collectTypeAtomSyntax`; ProgramV1 needs them to preserve
prefix constructors parsed as `Syntax.atom` nodes. -/
private partial def collectTypeAtomSyntaxV1 (stx : Syntax) : Array Syntax :=
  if stx.isIdent || stx.isOfKind numLitKind || (typeConstructorAtomTextV1? stx).isSome then
    #[stx]
  else
    stx.getArgs.flatMap collectTypeAtomSyntaxV1

/-- Decode the prefix atom form of the recursive ProgramV1 type grammar and emit
one original Syntax anchor per TypeV1 node in canonical preorder (Map key before
value). Array/Bytes length atoms and the Field id atom are consumed as non-node
tokens and do not produce anchors. The syntax parser has already bounded the
tree; `fuel` additionally guarantees that malformed constructor prefixes cannot
recurse without consuming an atom. -/
private def decodeTypeV1At :
    (fuel : Nat) → (atoms : Array Syntax) → (index : Nat) →
      Except String (TypeV1 × Array Syntax × Nat)
  | 0, _, _ => .error "unsupported portable type"
  | fuel + 1, atoms, index => do
      let atom ← match atoms[index]? with
        | some atom => pure atom
        | none => throw "unsupported portable type"
      let raw ← match typeTokenTextV1? atom with
        | some raw => pure raw
        | none => throw "unsupported portable type"
      match primitiveTypeV1 raw with
      | some type => pure (type, #[atom], index + 1)
      | none =>
          match raw with
          | "Option" => do
              let (element, elementAnchors, next) ← decodeTypeV1At fuel atoms (index + 1)
              pure (.option element, #[atom] ++ elementAnchors, next)
          | "Array" => do
              let (element, elementAnchors, next) ← decodeTypeV1At fuel atoms (index + 1)
              let lengthSyntax ← match atoms[next]? with
                | some length => pure length
                | none => throw "unsupported portable type"
              pure (.array element (← decodeBytesLengthAtom lengthSyntax),
                #[atom] ++ elementAnchors, next + 1)
          | "Map" => do
              let (key, keyAnchors, next) ← decodeTypeV1At fuel atoms (index + 1)
              let (value, valueAnchors, finish) ← decodeTypeV1At fuel atoms next
              pure (.map key value, #[atom] ++ keyAnchors ++ valueAnchors, finish)
          | "Bytes" => do
              let lengthSyntax ← match atoms[index + 1]? with
                | some length => pure length
                | none => throw "unsupported portable type"
              pure (.bytes (← decodeBytesLengthAtom lengthSyntax), #[atom], index + 2)
          | "Field" => do
              let fieldSyntax ← match atoms[index + 1]? with
                | some field => pure field
                | none => throw "unsupported portable type"
              unless rawIdentifierText? fieldSyntax == some "bn254_fr" do
                throw "unsupported portable type"
              let name ← ProofForgeV2.Source.NameComponentV1.sourceNameComponentV1FromLeanName fieldSyntax.getId
              pure (.field name, #[atom], index + 2)
          | _ => do
              unless atom.getId.components.length == 1 do
                throw "unsupported portable type"
              let name ← ProofForgeV2.Source.NameComponentV1.sourceNameComponentV1FromLeanName atom.getId
              if isReservedPortableTypeName name.raw then
                throw s!"reserved portable identifier '{name.raw}'"
              if isTypeConstructorNameV1 name.raw then
                throw "unsupported portable type"
              pure (.named name, #[atom], index + 1)

private def decodeTypeV1FromAtoms (atoms : Array Syntax) : Except String TypeV1 := do
  let (type, _anchors, next) ← decodeTypeV1At (atoms.size + 1) atoms 0
  unless next == atoms.size do
    throw "unsupported portable type"
  pure type

/-- Sole ProgramV1 type decoder surface for span join: decode `pfType` syntax and
emit one original Syntax anchor per TypeV1 node in canonical preorder. Does not
interpret type structure independently of this decoder. -/
def decodeTypeV1WithAnchors (stx : Syntax) : Except String (TypeV1 × Array Syntax) := do
  let atoms := collectTypeAtomSyntaxV1 stx
  let (type, anchors, next) ← decodeTypeV1At (atoms.size + 1) atoms 0
  unless next == atoms.size do
    throw "unsupported portable type"
  pure (type, anchors)

inductive ProgramNamespace where
  | bounded (name : Name)
  | overLimit
  deriving Inhabited

namespace ProgramV1Decoder

open ProofForgeV2.Core.Common
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstProgramV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.ValidatedSourceV1

private def isReservedPortableIdentifierV1 (raw : String) : Bool :=
  reservedPortableKeywords.contains raw

private def decodeNameV1 (stx : Syntax) : Except String SourceNameComponentV1 := do
  unless stx.getId.components.length == 1 do
    throw "source name component must contain exactly one Lean Name component"
  let component ← sourceNameComponentV1FromLeanName stx.getId
  if isReservedPortableIdentifierV1 component.raw then
    throw s!"reserved portable identifier '{component.raw}'"
  pure component

/-- Collect every raw component of a (possibly dotted) source identifier in
root-to-leaf order, validating each component and rejecting reserved portable
identifiers at the first offending component. -/
private def decodeIdentComponentsV1 (stx : Syntax) :
    Except String (Array SourceNameComponentV1) := do
  let rec collectPureStrChain (name : Name) (remaining : Nat) :
      Except String (Array String) :=
    match name with
    | .anonymous => pure #[]
    | .str pre value => do
        if remaining == 0 then
          throw "source qualified name must contain 1..256 components"
        let preRaws ← collectPureStrChain pre (remaining - 1)
        pure (preRaws.push value)
    | .num _ _ => throw "source qualified name requires a pure .str Lean name chain"
  let raws ← collectPureStrChain stx.getId 256
  let mut components : Array SourceNameComponentV1 := #[]
  for raw in raws do
    let component ← parseSourceNameComponentV1 raw
    if isReservedPortableIdentifierV1 component.raw then
      throw s!"reserved portable identifier '{component.raw}'"
    components := components.push component
  if components.size == 0 then
    throw "source qualified name must contain 1..256 components"
  pure components

private def decodeIdentPlaceV1 (stx : Syntax) : Except String PlaceV1 := do
  let components ← decodeIdentComponentsV1 stx
  match components[0]? with
  | none => throw "source qualified name must contain 1..256 components"
  | some root =>
      let mut place : PlaceV1 := .name root
      for component in components.extract 1 components.size do
        place := .field place component
      pure place

private partial def decodePlaceV1With
    (decodeExpr : Syntax → Except String ExprV1) : Syntax → Except String PlaceV1
  | `(pfPlace| $name:ident) => decodeIdentPlaceV1 name
  | `(pfPlace| $base:pfPlace . $field:ident) => do
      let placeBase ← decodePlaceV1With decodeExpr base
      let components ← decodeIdentComponentsV1 field
      pure (components.foldl (fun place component => .field place component) placeBase)
  | `(pfPlace| $base:pfPlace [$index:pfExpr]) => do
      pure (.index (← decodePlaceV1With decodeExpr base) (← decodeExpr index))
  | _ => throw "unsupported portable place"

private def decodeTypeV1Unchecked (stx : Syntax) : Except String TypeV1 :=
  decodeTypeV1FromAtoms (collectTypeAtomSyntaxV1 stx)

private def decodeParamV1Unchecked : Syntax → Except String ParamV1
  | `(pfParam| $name:ident : $type:pfType) => do
      pure {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | `(pfParam| public $name:ident : $type:pfType) => do
      pure {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | `(pfParam| private $name:ident : $type:pfType) => do
      pure {
        visibility := .private_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | `(pfParam| commitment $name:ident : $type:pfType) => do
      pure {
        visibility := .commitment
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      }
  | _ => throw "unsupported portable parameter"

private def qualifiedV1FromStrings (parts : Array String) : Except String SourceQualifiedNameV1 := do
  for part in parts do
    if isReservedPortableIdentifierV1 part then
      throw s!"reserved portable identifier '{part}'"
  parseSourceQualifiedNameV1 parts

private def decodeQualifiedIdV1 (stx : Syntax) : Except String SourceQualifiedNameV1 := do
  let qualified ← sourceQualifiedNameV1FromLeanName stx.getId
  validateSourceQualifiedIdV1 qualified
  pure qualified

private def decodePortableQualifiedIdV1
    (stx : Syntax) : Except String SourceQualifiedNameV1 := do
  let qualified ← decodeQualifiedIdV1 stx
  for component in NonEmptyArray.toArray qualified.components do
    if isReservedPortableIdentifierV1 component.raw then
      throw s!"reserved portable identifier '{component.raw}'"
  pure qualified

private partial def decodePatternV1Unchecked : Syntax → Except String PatternV1
  | `(pfPattern| _) => pure .wildcard
  | `(boolTruePattern| true) => pure (.literal (.bool true))
  | `(boolFalsePattern| false) => pure (.literal (.bool false))
  | `(pfPattern| $value:num) => do
      pure (.literal (.integer (← decodeIntegerLiteralV1 value)))
  | `(pfPattern| $value:str) => pure (.literal (.string value.getString))
  | `(pfPattern| $ctor:ident ($args:pfPattern,*)) => do
      let ctor ← decodePortableQualifiedIdV1 ctor
      pure (.constructor ctor (← args.getElems.mapM decodePatternV1Unchecked))
  | `(pfPattern| $name:ident) => do
      pure (.bind (← decodeNameV1 name))
  | _ => throw "unsupported portable pattern"

private partial def decodeExprV1Unchecked : Syntax → Except String ExprV1
  | `(boolTrueExpr| true) => pure (.literal (.bool true))
  | `(boolFalseExpr| false) => pure (.literal (.bool false))
  | `(pfExpr| $value:num) => do
      pure (.literal (.integer (← decodeIntegerLiteralV1 value)))
  | `(pfExpr| $value:str) => pure (.literal (.string value.getString))
  | `(pfExpr| $callee:ident ($args:pfExpr,*)) => do
      if callee.getId.components.length == 1 then
        let callee ← decodeNameV1 callee
        pure (.localCall callee (← args.getElems.mapM decodeExprV1Unchecked))
      else
        let ctor ← decodePortableQualifiedIdV1 callee
        pure (.constructor ctor (← args.getElems.mapM decodeExprV1Unchecked))
  | `(pfExpr| $place:pfPlace) => do
      pure (.place (← decodePlaceV1With decodeExprV1Unchecked place))
  | `(pfExpr| $lhs:pfExpr + $rhs:pfExpr) => do
      pure (.binary .add (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr - $rhs:pfExpr) => do
      pure (.binary .sub (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr * $rhs:pfExpr) => do
      pure (.binary .mul (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr / $rhs:pfExpr) => do
      pure (.binary .div (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr % $rhs:pfExpr) => do
      pure (.binary .mod (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr << $rhs:pfExpr) => do
      pure (.binary .shl (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr >> $rhs:pfExpr) => do
      pure (.binary .shr (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr == $rhs:pfExpr) => do
      pure (.binary .eq (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr != $rhs:pfExpr) => do
      pure (.binary .ne (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr < $rhs:pfExpr) => do
      pure (.binary .lt (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr <= $rhs:pfExpr) => do
      pure (.binary .le (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr > $rhs:pfExpr) => do
      pure (.binary .gt (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr >= $rhs:pfExpr) => do
      pure (.binary .ge (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr & $rhs:pfExpr) => do
      pure (.binary .bitAnd (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr ^ $rhs:pfExpr) => do
      pure (.binary .bitXor (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr && $rhs:pfExpr) => do
      pure (.binary .logicalAnd (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| $lhs:pfExpr || $rhs:pfExpr) => do
      pure (.binary .logicalOr (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
  | `(pfExpr| - $operand:pfExpr) => do
      pure (.unary .neg (← decodeExprV1Unchecked operand))
  | `(pfExpr| ~ $operand:pfExpr) => do
      pure (.unary .bitNot (← decodeExprV1Unchecked operand))
  | `(pfExpr| ! $operand:pfExpr) => do
      pure (.unary .not (← decodeExprV1Unchecked operand))
  | `(pfExpr| ($inner:pfExpr)) => decodeExprV1Unchecked inner
  | stx =>
      match stx.getKind, stx.getArgs with
      | `ProofForgeV2.Language.matchExpr, #[.atom _ "match", scrutinee, .atom _ "with",
          .node _ `null arms] => do
          unless !arms.isEmpty do throw "unsupported portable expression"
          let scrutinee ← decodeExprV1Unchecked scrutinee
          let decodedArms ← arms.mapM fun arm => do
            unless arm.getKind == `ProofForgeV2.Language.exprMatchArm do
              throw "unsupported portable expression"
            match arm.getArgs with
            | #[.atom _ "|", pattern, .atom _ "=>", value] => do
                pure ({
                  pattern := ← decodePatternV1Unchecked pattern
                  value := ← decodeExprV1Unchecked value
                } : ExprMatchArmV1)
            | _ => throw "unsupported portable expression"
          pure (.match_ scrutinee decodedArms)
      | `ProofForgeV2.Language.bitOrExpr, #[lhs, .atom _ "|", rhs] =>
          return (.binary .bitOr (← decodeExprV1Unchecked lhs) (← decodeExprV1Unchecked rhs))
      | _, _ => throw "unsupported portable expression"

private def decodePlaceV1 (stx : Syntax) : Except String PlaceV1 :=
  decodePlaceV1With decodeExprV1Unchecked stx

private def decodeExternalCallV1Unchecked
    (calleeSyntax : Syntax) (argsSyntax : TSyntaxArray `pfExpr) :
    Except String ExternalCallExprV1 := do
  let callee ← decodePortableQualifiedIdV1 calleeSyntax
  pure {
    callee := callee
    args := ← argsSyntax.mapM decodeExprV1Unchecked
  }

private partial def decodeStatementV1Unchecked : Syntax → Except String StmtV1
  | `(letStmtAnnotated| let $name:ident : $type:pfType := $value:pfExpr) => do
      pure (.let_ (← decodeNameV1 name) (some (← decodeTypeV1Unchecked type))
        (← decodeExprV1Unchecked value))
  | `(letStmtOmitted| let $name:ident := $value:pfExpr) => do
      pure (.let_ (← decodeNameV1 name) none (← decodeExprV1Unchecked value))
  | `(pfStmt| $target:pfPlace := $value:pfExpr) => do
      pure (.assign (← decodePlaceV1 target) (← decodeExprV1Unchecked value))
  | `(returnValueStmt| return $value:pfExpr) => do
      pure (.return_ (some (← decodeExprV1Unchecked value)))
  | `(pfStmt| return) => pure (.return_ none)
  | `(pfStmt| assert $condition:pfExpr else $errorName:ident) => do
      pure (.assert_ (← decodeExprV1Unchecked condition) (some (← decodeNameV1 errorName)))
  | `(pfStmt| assert $condition:pfExpr) => do
      pure (.assert_ (← decodeExprV1Unchecked condition) none)
  | `(pfStmt| revert $errorName:ident ($args:pfExpr,*)) => do
      pure (.revert (← decodeNameV1 errorName) (← args.getElems.mapM decodeExprV1Unchecked))
  | `(pfStmt| revert $errorName:ident) => do
      pure (.revert (← decodeNameV1 errorName) #[])
  | `(pfStmt| emit $eventName:ident ($args:pfExpr,*)) => do
      pure (.emit (← decodeNameV1 eventName) (← args.getElems.mapM decodeExprV1Unchecked))
  | `(pfStmt| call $callee:ident ($args:pfExpr,*)) => do
      pure (.call (← decodeExternalCallV1Unchecked callee args))
  | `(pfStmt| schedule $callee:ident ($args:pfExpr,*)) => do
      pure (.schedule (← decodeExternalCallV1Unchecked callee args))
  | stx => do
      match stx.getKind, stx.getArgs with
      | `ProofForgeV2.Language.ifStmt, #[.atom _ "if", condition, .atom _ "then",
          .node _ `null thenSyntax, .node _ `null elseSyntax] => do
          unless !thenSyntax.isEmpty do throw "unsupported portable statement"
          let condition ← decodeExprV1Unchecked condition
          let thenBlock := { statements := ← thenSyntax.mapM decodeStatementV1Unchecked }
          let elseBlock ←
            if elseSyntax.isEmpty then
              pure none
            else
              match elseSyntax with
              | #[.atom _ "else", .node _ `null body] => do
                  if body.isEmpty then throw "unsupported portable statement"
                  else pure (some { statements := ← body.mapM decodeStatementV1Unchecked })
              | _ => throw "unsupported portable statement"
          pure (.if_ condition thenBlock elseBlock)
      | `ProofForgeV2.Language.matchStmt, #[.atom _ "match", scrutinee, .atom _ "with",
          .node _ `null arms] => do
          unless !arms.isEmpty do throw "unsupported portable statement"
          let scrutinee ← decodeExprV1Unchecked scrutinee
          let decodedArms ← arms.mapM fun arm => do
            unless arm.getKind == `ProofForgeV2.Language.stmtMatchArm do
              throw "unsupported portable statement"
            match arm.getArgs with
            | #[.atom _ "|", pattern, .atom _ "=>", .atom _ "do", .node _ `null body] => do
                unless !body.isEmpty do throw "unsupported portable statement"
                let pattern ← decodePatternV1Unchecked pattern
                let statements ← body.mapM decodeStatementV1Unchecked
                pure ({ pattern, body := { statements } } : StmtMatchArmV1)
            | _ => throw "unsupported portable statement"
          pure (.match_ scrutinee decodedArms)
      | `ProofForgeV2.Language.forStmt, #[.atom _ "for", iterator, .atom _ "in", start,
          .atom _ "..<", stopExclusive, .atom _ "bounded", bound, .atom _ "do",
          .node _ `null body] => do
          unless !body.isEmpty do throw "unsupported portable statement"
          unless iterator.getId.components.length == 1 do
            throw "unsupported portable statement"
          let binder ← decodeNameV1 iterator
          let start ← decodeExprV1Unchecked start
          let stopExclusive ← decodeExprV1Unchecked stopExclusive
          let bound ← match decodeBytesLengthAtom bound with
            | .ok value => pure value
            | .error _ => throw "unsupported portable statement"
          pure (.for_ binder start stopExclusive bound
            { statements := ← body.mapM decodeStatementV1Unchecked })
      | _, _ => throw "unsupported portable statement"

private def decodeParamsV1 (params : Array Syntax) : Except String (Array ParamV1) :=
  params.mapM decodeParamV1Unchecked

private def decodeBlockV1 (statements : Array Syntax) : Except String BlockV1 := do
  pure { statements := ← statements.mapM decodeStatementV1Unchecked }

private def decodeStructFieldV1Unchecked (stx : Syntax) : Except String FieldDeclV1 := do
  let atoms := collectTypeAtomSyntaxV1 stx
  let nameSyntax ← match atoms[0]? with
    | some name => pure name
    | none => throw "unsupported portable struct field"
  let typeAtoms := atoms.extract 1 atoms.size
  unless !typeAtoms.isEmpty do
    throw "unsupported portable struct field"
  pure {
    name := ← decodeNameV1 nameSyntax
    type_ := ← decodeTypeV1FromAtoms typeAtoms
  }

private def decodeEnumVariantV1Unchecked : Syntax → Except String EnumVariantV1
  | `(pfAggregateMember| | $name:ident
      ) => do
      pure { name := ← decodeNameV1 name, payloadTypes := #[] }
  | `(pfAggregateMember| | $name:ident ($payloadTypes:pfType,*)
      ) => do
      let payloadTypes := payloadTypes.getElems
      if payloadTypes.isEmpty then
        throw s!"enum variant '{(← decodeNameV1 name).raw}' payload must contain at least one type"
      pure {
        name := ← decodeNameV1 name
        payloadTypes := ← payloadTypes.mapM decodeTypeV1Unchecked
      }
  | _ => .error "unsupported portable enum variant"

private def decodeItemV1Unchecked : Syntax → Except String ProgramItemV1
  | `(pfItem| state $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(pfItem| state public $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .public_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(pfItem| state private $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .private_
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(pfItem| state commitment $name:ident : $type:pfType) => do
      pure (.state {
        visibility := .commitment
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
      })
  | `(constDecl| const $name:ident : $type:pfType := $value:pfExpr) => do
      pure (.const {
        name := ← decodeNameV1 name
        type_ := ← decodeTypeV1Unchecked type
        value := ← decodeExprV1Unchecked value
      })
  | `(unsupportedConstLikeDecl| $_kind:ident $_name:ident : $_type:pfType :=
        $_value:pfExpr) =>
      throw "unsupported portable program item"
  | `(invariantDecl| invariant $name:ident : $predicate:pfExpr) => do
      pure (.invariant {
        name := ← decodeNameV1 name
        predicate := ← decodeExprV1Unchecked predicate
      })
  | `(unsupportedInvariantLikeDecl| $_kind:ident $_name:ident : $_predicate:pfExpr
      ) =>
      throw "unsupported portable program item"
  | `(extensionReq| requires extension $id:ident version $version:str
        digest $digest:str) => do
      let _ ← decodeExtensionId id
      pure (.extensionReq {
        id := ← decodeQualifiedIdV1 id
        version := ← decodeExtensionVersion version
        digest := ← decodeExtensionDigest digest
      })
  | `(unsupportedExtensionLikeReq| $_requires:ident $_extension:ident $_id:ident $_versionKeyword:ident $_version:str
        $_digestKeyword:ident $_digest:str) =>
      throw "unsupported portable program item"
  | `(proofDecl| proof $invariant:ident using $theoremName:ident) => do
      let theoremParts ← decodeProofTheorem theoremName
      pure (.proof {
        invariant := ← decodeNameV1 invariant
        theorem_ := ← qualifiedV1FromStrings theoremParts
      })
  | `(unsupportedProofIntroducer| $_proof:ident $_invariant:ident using $_theoremName:ident) =>
      throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) : $result:pfType do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          pure (.fn {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
            result := ← decodeTypeV1Unchecked result
            body := ← decodeBlockV1 body
          })
      | _ => throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*) do
        $body:pfStmt*) =>
      match rawIdentifierText? kind with
      | some "fn" => do
          pure (.fn {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
            result := .unit
            body := ← decodeBlockV1 body
          })
      | _ => throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident where $members:pfAggregateMember*) =>
      match rawIdentifierText? kind with
      | some "struct" => do
          pure (.struct {
            name := ← decodeNameV1 name
            fields := ← members.mapM decodeStructFieldV1Unchecked
          })
      | some "enum" => do
          pure (.enum {
            name := ← decodeNameV1 name
            variants := ← members.mapM decodeEnumVariantV1Unchecked
          })
      | _ => throw "unsupported portable program item"
  | `(pfItem| $kind:ident $name:ident ($params:pfParam,*)) =>
      match rawIdentifierText? kind with
      | some "event" => do
          pure (.event {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
          })
      | some "error" => do
          pure (.error {
            name := ← decodeNameV1 name
            params := ← decodeParamsV1 params
          })
      | _ => throw "unsupported portable program item"
  | `(bareErrorDecl| error $name:ident
      ) => do
      pure (.error { name := ← decodeNameV1 name, params := #[] })
  | `(unsupportedBareItemDecl| $_kind:ident $_name:ident
      ) =>
      throw "unsupported portable program item"
  | `(pfItem| init ($params:pfParam,*) do $statements:pfStmt*) => do
      pure (.init {
        params := ← decodeParamsV1 params
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| entry $name:ident ($params:pfParam,*) : $type:pfType do
        $statements:pfStmt*) => do
      pure (.entry {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := ← decodeTypeV1Unchecked type
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| entry $name:ident ($params:pfParam,*) do $statements:pfStmt*) => do
      pure (.entry {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := .unit
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| view $name:ident ($params:pfParam,*) : $type:pfType do
        $statements:pfStmt*) => do
      pure (.view {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := ← decodeTypeV1Unchecked type
        body := ← decodeBlockV1 statements
      })
  | `(pfItem| view $name:ident ($params:pfParam,*) do $statements:pfStmt*) => do
      pure (.view {
        name := ← decodeNameV1 name
        params := ← decodeParamsV1 params
        result := .unit
        body := ← decodeBlockV1 statements
      })
  | _ => throw "unsupported portable program item"

private def leanNameComponentsV1 (name : Name) : Except String (Array SourceNameComponentV1) := do
  if name == .anonymous then
    pure #[]
  else
    pure (NonEmptyArray.toArray (← sourceQualifiedNameV1FromLeanName name).components)

/-- Total module+namespace+declaration identity overflow message (PF-BOUND-001). -/
private def identityNestingLimitMessage : String :=
  s!"portable program identity exceeds nesting limit {maxSyntaxNesting}"

private def invalidProgramString (message : String) : CompileError :=
  .invalidProgram message

private def decodeProgramV1Unchecked
    (moduleName : SourceQualifiedNameV1) (currentNamespace : Name) : Syntax →
    CompileResult ValidatedSourceV1
  | `(program $name:ident where $items:pfItem*) => do
      unless boundedNamePartCount 2 name.getId == some 1 do
        throw <| invalidProgramString "program name must be unqualified"
      let shortName ← match decodeNameV1 name with
        | .ok n => pure n
        | .error message => throw <| invalidProgramString message
      let namespaceComponents ← match leanNameComponentsV1 currentNamespace with
        | .ok cs => pure cs
        | .error message => throw <| invalidProgramString message
      let moduleComponents := NonEmptyArray.toArray moduleName.components
      -- Structured identity-size resourceBound at the assembly site, before the
      -- shared QualifiedName grammar constructor (qnCountError remains invalidProgram
      -- for place/ident component helpers elsewhere).
      let identityComponents := (moduleComponents ++ namespaceComponents).push shortName
      if identityComponents.size < 1 || identityComponents.size > maxSyntaxNesting then
        throw <| .resourceBound identityNestingLimitMessage
      let identity ← match sourceQualifiedNameV1OfComponents identityComponents with
        | .ok id => pure id
        | .error message => throw <| invalidProgramString message
      let decodedItems ← match items.mapM decodeItemV1Unchecked with
        | .ok decoded => pure decoded
        | .error message => throw <| invalidProgramString message
      let sourceProgram : ProgramV1 := {
        name := shortName
        items := decodedItems
      }
      match validateSourceV1 moduleName identity sourceProgram with
      | .ok source => pure source
      | .error message => throw <| invalidProgramString message
  | _ => throw <| invalidProgramString "expected a program declaration"

/-- Direct recovery frontend for the supported ProgramV1 product slice. It
constructs and validates ProgramV1 from Syntax without creating legacy source. -/
def decodeProgramCommandV1Checked
    (moduleName : SourceQualifiedNameV1) (currentNamespace : ProgramNamespace)
    (stx : Syntax) : CompileResult ValidatedSourceV1 := do
  preflightSyntax stx
  let namespaceName ← match currentNamespace with
    | .bounded name => pure name
    | .overLimit => .error (.resourceBound identityNestingLimitMessage)
  decodeProgramV1Unchecked moduleName namespaceName stx

end ProgramV1Decoder

export ProgramV1Decoder (decodeProgramCommandV1Checked)


private def quoteByteArray (bytes : ByteArray) : MacroM (TSyntax `term) := do
  let hex := bytes.foldl (fun acc byte =>
    (acc.push (Nat.digitChar (byte.toNat / 16))).push (Nat.digitChar (byte.toNat % 16))) ""
  `(ProofForgeV2.Language.ProgramExport.programExportBytesFromHex $(quote hex))

elab_rules : command
  | `(program $name:ident where $items:pfItem*) => do
      let env ← getEnv
      let moduleName ← match sourceQualifiedNameV1FromLeanName env.mainModule with
        | .ok value => pure value
        | .error message => throwError message
      let currentNamespace ← getCurrNamespace
      let relativeNamespace := currentNamespace.replacePrefix env.mainModule .anonymous
      let commandStx ← `(program $name:ident where $items:pfItem*)
      let source ← match decodeProgramCommandV1Checked moduleName (.bounded relativeNamespace) commandStx with
        | .error error => throwError error.render
        | .ok source => pure source
      let bytes ← match canonicalValidatedSourceAstBytesV1 source with
        | .error message => throwError message
        | .ok bytes => pure bytes
      let bytesExpr ← Lean.Elab.liftMacroM <| quoteByteArray bytes
      let expanded ← `(@[proof_forge_program]
        def $name : ProgramExportPayloadV2 := {
          schema := $(Syntax.mkStrLit programExportSchemaV2),
          bytes := $bytesExpr
        })
      Lean.Elab.Command.elabCommand expanded

end ProofForgeV2.Language
