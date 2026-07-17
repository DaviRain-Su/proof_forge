/-
  ProofForgeV2.Core.Canonical — restricted canonical JSON for common wire types.

  PF-JCS intentionally supports only the JSON values needed by the V2 common
  schemas: null, booleans, signed I-JSON safe integers, Unicode strings,
  arrays, and objects.  Parsing is strict: the decoded value must render back
  to the exact input text, so whitespace, alternate escapes, alternate number
  spellings, and non-canonical member order fail closed.
-/
import Std

namespace ProofForgeV2.Core.Common

inductive PfJson where
  | null
  | bool (value : Bool)
  | int (value : Int)
  | string (value : String)
  | array (values : Array PfJson)
  | object (fields : Array (String × PfJson))
  deriving BEq, Repr

noncomputable instance : DecidableEq PfJson :=
  fun left right => Classical.propDecidable (left = right)

private def maxSafeInteger : Nat := 9007199254740991

private def lowerHexDigit (value : Nat) : Char :=
  if value < 10 then
    Char.ofNat ('0'.toNat + value)
  else
    Char.ofNat ('a'.toNat + value - 10)

private def escapedControl (value : Nat) : String :=
  String.ofList
    ['\\', 'u', lowerHexDigit ((value / 4096) % 16),
      lowerHexDigit ((value / 256) % 16),
      lowerHexDigit ((value / 16) % 16), lowerHexDigit (value % 16)]

private def escapeStringChar (c : Char) : String :=
  match c with
  | '\x22' => "\\\""
  | '\\' => "\\\\"
  | '\x08' => "\\b"
  | '\x09' => "\\t"
  | '\x0a' => "\\n"
  | '\x0c' => "\\f"
  | '\x0d' => "\\r"
  | c =>
    if c.toNat < 0x20 then escapedControl c.toNat
    else String.singleton c

private def renderString (value : String) : String :=
  let chunks := value.foldl (fun acc c => escapeStringChar c :: acc) []
  "\"" ++ String.join chunks.reverse ++ "\""

private def charUtf16CodeUnits (c : Char) : List Nat :=
  let value := c.toNat
  if value < 0x10000 then
    [value]
  else
    let offset := value - 0x10000
    [0xd800 + offset / 0x400, 0xdc00 + offset % 0x400]

private def stringUtf16CodeUnits (value : String) : List Nat :=
  value.toList.flatMap charUtf16CodeUnits

private def utf16LexLE : List Nat → List Nat → Bool
  | [], _ => true
  | _ :: _, [] => false
  | left :: leftRest, right :: rightRest =>
    if left < right then true
    else if right < left then false
    else utf16LexLE leftRest rightRest

private def fieldUtf16LE
    (left right : String × PfJson) : Bool :=
  utf16LexLE (stringUtf16CodeUnits left.1) (stringUtf16CodeUnits right.1)

private def ensureNoAdjacentDuplicateKeys : List (String × PfJson) → Except String Unit
  | [] | [_] => pure ()
  | left :: right :: rest => do
    if left.1 == right.1 then
      throw "PF-JCS object contains a duplicate key"
    ensureNoAdjacentDuplicateKeys (right :: rest)

private partial def renderPfJcsInner : PfJson → Except String String
  | .null => pure "null"
  | .bool true => pure "true"
  | .bool false => pure "false"
  | .int value => do
    unless -(Int.ofNat maxSafeInteger) ≤ value &&
        value ≤ Int.ofNat maxSafeInteger do
      throw "PF-JCS integer exceeds the signed I-JSON safe range"
    pure (toString value)
  | .string value => pure (renderString value)
  | .array values => do
    let rendered ← values.mapM renderPfJcsInner
    pure ("[" ++ String.intercalate "," rendered.toList ++ "]")
  | .object fields => do
    let sorted := fields.mergeSort fieldUtf16LE
    ensureNoAdjacentDuplicateKeys sorted.toList
    let rendered ← sorted.mapM fun field => do
      let value ← renderPfJcsInner field.2
      pure (renderString field.1 ++ ":" ++ value)
    pure ("{" ++ String.intercalate "," rendered.toList ++ "}")

/-- Render restricted PF-JCS UTF-8 text, sorting object keys by UTF-16 code units. -/
def renderPfJcs (value : PfJson) : Except String String :=
  renderPfJcsInner value

private def isAsciiDigit (c : Char) : Bool :=
  '0' ≤ c && c ≤ '9'

private def hexNibble? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then
    some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then
    some (10 + c.toNat - 'a'.toNat)
  else if 'A' ≤ c && c ≤ 'F' then
    some (10 + c.toNat - 'A'.toNat)
  else
    none

private def parseHex4 : List Char → Except String (Nat × List Char)
  | a :: b :: c :: d :: rest =>
    match hexNibble? a, hexNibble? b, hexNibble? c, hexNibble? d with
    | some an, some bn, some cn, some dn =>
      pure (an * 4096 + bn * 256 + cn * 16 + dn, rest)
    | _, _, _, _ => throw "PF-JCS string contains an invalid Unicode escape"
  | _ => throw "PF-JCS string contains a truncated Unicode escape"

private def decodeUnicodeEscape
    (input : List Char) : Except String (Char × List Char) := do
  let (first, rest) ← parseHex4 input
  if 0xd800 ≤ first && first ≤ 0xdbff then
    match rest with
    | '\\' :: 'u' :: lowInput =>
      let (second, tail) ← parseHex4 lowInput
      unless 0xdc00 ≤ second && second ≤ 0xdfff do
        throw "PF-JCS string contains an invalid surrogate pair"
      let scalar := 0x10000 + (first - 0xd800) * 0x400 + (second - 0xdc00)
      pure (Char.ofNat scalar, tail)
    | _ => throw "PF-JCS string contains a lone high surrogate"
  else if 0xdc00 ≤ first && first ≤ 0xdfff then
    throw "PF-JCS string contains a lone low surrogate"
  else
    pure (Char.ofNat first, rest)

private partial def parseStringBody
    (input : List Char) (reversed : List Char) : Except String (String × List Char) :=
  match input with
  | [] => throw "PF-JCS string is unterminated"
  | '\x22' :: rest => pure (String.ofList reversed.reverse, rest)
  | '\\' :: '\x22' :: rest => parseStringBody rest ('\x22' :: reversed)
  | '\\' :: '\\' :: rest => parseStringBody rest ('\\' :: reversed)
  | '\\' :: '/' :: rest => parseStringBody rest ('/' :: reversed)
  | '\\' :: 'b' :: rest => parseStringBody rest ('\x08' :: reversed)
  | '\\' :: 'f' :: rest => parseStringBody rest ('\x0c' :: reversed)
  | '\\' :: 'n' :: rest => parseStringBody rest ('\x0a' :: reversed)
  | '\\' :: 'r' :: rest => parseStringBody rest ('\x0d' :: reversed)
  | '\\' :: 't' :: rest => parseStringBody rest ('\x09' :: reversed)
  | '\\' :: 'u' :: rest => do
    let (decoded, tail) ← decodeUnicodeEscape rest
    parseStringBody tail (decoded :: reversed)
  | '\\' :: _ => throw "PF-JCS string contains an invalid escape"
  | c :: rest =>
    if c.toNat < 0x20 then
      throw "PF-JCS string contains an unescaped control character"
    else
      parseStringBody rest (c :: reversed)

private def parseStringValue : List Char → Except String (String × List Char)
  | '\x22' :: rest => parseStringBody rest []
  | _ => throw "PF-JCS expected a JSON string"

private def consumeLiteral : List Char → List Char → Option (List Char)
  | [], input => some input
  | wanted :: wantedRest, actual :: actualRest =>
    if wanted == actual then consumeLiteral wantedRest actualRest else none
  | _ :: _, [] => none

private def parseLiteral
    (spelling : String) (value : PfJson) (input : List Char) :
    Except String (PfJson × List Char) :=
  match consumeLiteral spelling.toList input with
  | some rest => pure (value, rest)
  | none => throw "PF-JCS contains an invalid literal"

private def parseSafeNat (digits : List Char) : Except String Nat := do
  let mut value := 0
  for digit in digits do
    value := value * 10 + (digit.toNat - '0'.toNat)
    if value > maxSafeInteger then
      throw "PF-JCS integer exceeds the signed I-JSON safe range"
  pure value

private def parseNumber (input : List Char) : Except String (PfJson × List Char) := do
  let (negative, unsignedInput) :=
    match input with
    | '-' :: rest => (true, rest)
    | _ => (false, input)
  let (digits, rest) := unsignedInput.span isAsciiDigit
  if digits.isEmpty then
    throw "PF-JCS integer requires at least one digit"
  if digits.length > 1 && digits.head? == some '0' then
    throw "PF-JCS integer contains a leading zero"
  let magnitude ← parseSafeNat digits
  if negative && magnitude = 0 then
    throw "PF-JCS forbids negative zero"
  let value := if negative then -(Int.ofNat magnitude) else Int.ofNat magnitude
  pure (.int value, rest)

private def hasObjectKey (fields : Array (String × PfJson)) (key : String) : Bool :=
  fields.any (fun field => field.1 == key)

mutual

private partial def parseValue (input : List Char) : Except String (PfJson × List Char) :=
  match input with
  | [] => throw "PF-JCS input ended before a value"
  | 'n' :: _ => parseLiteral "null" .null input
  | 't' :: _ => parseLiteral "true" (.bool true) input
  | 'f' :: _ => parseLiteral "false" (.bool false) input
  | '\x22' :: _ => do
    let (value, rest) ← parseStringValue input
    pure (.string value, rest)
  | '[' :: rest => parseArray rest
  | '{' :: rest => parseObject rest
  | '-' :: _ => parseNumber input
  | c :: _ =>
    if isAsciiDigit c then parseNumber input
    else throw "PF-JCS contains an invalid value"

private partial def parseArrayTail
    (input : List Char) (values : Array PfJson) : Except String (PfJson × List Char) :=
  match input with
  | ']' :: rest => pure (.array values, rest)
  | ',' :: rest => do
    let (value, tail) ← parseValue rest
    parseArrayTail tail (values.push value)
  | _ => throw "PF-JCS array requires ',' or ']'"

private partial def parseArray
    (input : List Char) : Except String (PfJson × List Char) :=
  match input with
  | ']' :: rest => pure (.array #[], rest)
  | _ => do
    let (value, rest) ← parseValue input
    parseArrayTail rest #[value]

private partial def parseObjectField
    (input : List Char) (fields : Array (String × PfJson)) :
    Except String ((Array (String × PfJson)) × List Char) := do
  let (key, afterKey) ← parseStringValue input
  if hasObjectKey fields key then
    throw "PF-JCS object contains a duplicate key"
  let afterColon ← match afterKey with
    | ':' :: rest => pure rest
    | _ => throw "PF-JCS object member requires ':'"
  let (value, rest) ← parseValue afterColon
  pure (fields.push (key, value), rest)

private partial def parseObjectTail
    (input : List Char) (fields : Array (String × PfJson)) :
    Except String (PfJson × List Char) :=
  match input with
  | '}' :: rest => pure (.object fields, rest)
  | ',' :: rest => do
    let (nextFields, tail) ← parseObjectField rest fields
    parseObjectTail tail nextFields
  | _ => throw "PF-JCS object requires ',' or '}'"

private partial def parseObject
    (input : List Char) : Except String (PfJson × List Char) :=
  match input with
  | '}' :: rest => pure (.object #[], rest)
  | _ => do
    let (fields, rest) ← parseObjectField input #[]
    parseObjectTail rest fields

end

/--
Decode restricted PF-JCS.  The exact render comparison makes the accepted wire
language canonical while the parser itself still detects decoded duplicate keys.
-/
def parsePfJcs (input : String) : Except String PfJson := do
  let (value, rest) ← parseValue input.toList
  unless rest.isEmpty do
    throw "PF-JCS input contains trailing data"
  let canonical ← renderPfJcs value
  unless canonical = input do
    throw "PF-JCS input is not in canonical form"
  pure value

/-- Decode PF-JCS bytes, rejecting malformed UTF-8 before JSON parsing. -/
def parsePfJcsBytes (input : ByteArray) : Except String PfJson := do
  let text ← match String.fromUTF8? input with
    | some value => pure value
    | none => throw "PF-JCS input is not valid UTF-8"
  parsePfJcs text

end ProofForgeV2.Core.Common
