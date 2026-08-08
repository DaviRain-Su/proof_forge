/-
  Sole text encode/decode for Aleo Instructions Schema V1.

  Encode is authoritative for golden byte identity against locked Leo 4.0.2
  `compiled.aleo` output (Counter). Decode is fail-closed for the IR-1 subset
  and rejects unknown opcodes/shapes. Whitespace is exact (4-space indent,
  blank line between top-level items, trailing newline on last line).
-/
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1

namespace ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1

open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1

private def indent : String := "    "

private def dropPrefix (s : String) (n : Nat) : String :=
  (s.drop n).copy

private def dropSuffix (s : String) (n : Nat) : String :=
  (s.dropEnd n).copy

private def stripLeading? (s pre : String) : Option String :=
  if s.startsWith pre then some (dropPrefix s pre.length) else none

/-- Render a single instruction (body line without leading indent or `;`). -/
def renderInstruction (i : InstructionV1) : String :=
  match i with
  | .input reg ty => s!"input {reg.render} as {ty.render}"
  | .output reg ty => s!"output {reg.render} as {ty.render}"
  | .asyncCall name args dest =>
      let argStr :=
        if args.isEmpty then ""
        else " " ++ " ".intercalate (args.toList.map (·.render))
      s!"async {name}{argStr} into {dest.render}"
  | .unary op src dest => s!"{op} {src.render} into {dest.render}"
  | .binary op left right dest =>
      s!"{op} {left.render} {right.render} into {dest.render}"
  | .assertEq left right => s!"assert.eq {left.render} {right.render}"
  | .getOrUse mapping key default dest =>
      s!"get.or_use {mapping}[{key.render}] {default.render} into {dest.render}"
  | .set value mapping key =>
      s!"set {value.render} into {mapping}[{key.render}]"

private def renderBody (body : Array InstructionV1) : String :=
  body.foldl (init := "") fun acc i =>
    acc ++ indent ++ renderInstruction i ++ ";\n"

private def renderItem : ItemV1 → String
  | .mapping m =>
      s!"mapping {m.name}:\n" ++
      indent ++ s!"key as {m.keyType.render};\n" ++
      indent ++ s!"value as {m.valueType.render};\n"
  | .function f =>
      s!"function {f.name}:\n" ++ renderBody f.body
  | .finalize f =>
      s!"finalize {f.name}:\n" ++ renderBody f.body
  | .constructor c =>
      "constructor:\n" ++ renderBody c.body

/-- Encode program to Aleo Instructions text (Leo `build/main.aleo` style). -/
def encodeProgram (p : ProgramV1) : String :=
  let header := s!"program {p.name};\n"
  if p.items.isEmpty then
    header
  else
    let body := p.items.toList.map renderItem
    header ++ "\n" ++ "\n".intercalate body

-- ---------------------------------------------------------------------------
-- Decoder (fail closed)
-- ---------------------------------------------------------------------------

private structure Cursor where
  lines : Array String
  idx : Nat

private def Cursor.eof (c : Cursor) : Bool := c.idx >= c.lines.size

private def Cursor.peek (c : Cursor) : Option String :=
  if c.idx < c.lines.size then some c.lines[c.idx]! else none

private def Cursor.advance (c : Cursor) : Cursor := { c with idx := c.idx + 1 }

private def isBlank (s : String) : Bool :=
  s.all (fun c => c == ' ' || c == '\t' || c == '\r')

private partial def skipBlank (c : Cursor) : Cursor :=
  match c.peek with
  | none => c
  | some line =>
      if isBlank line then skipBlank c.advance else c

private def parseRegister? (s : String) : Option RegisterV1 :=
  match stripLeading? s "r" with
  | none => none
  | some rest =>
      if rest.isEmpty then none
      else if rest.all Char.isDigit then
        some ⟨rest.toNat!⟩
      else none

private def parseTypeAnn? (s : String) : Option TypeAnnV1 :=
  if s.endsWith ".future" then
    let core := dropSuffix s ".future".length
    match core.splitOn "/" with
    | [programId, functionName] =>
        if programId.isEmpty || functionName.isEmpty then none
        else some (.future programId functionName)
    | _ => none
  else
    match s.splitOn "." with
    | [base, vis] =>
        match BaseTypeV1.parse? base, VisibilityV1.parse? vis with
        | some ty, some v => some (.base ty v)
        | _, _ => none
    | _ => none

private def isIdentStart (c : Char) : Bool :=
  c.isAlpha || c == '_'

private def isIdentCont (c : Char) : Bool :=
  c.isAlphanum || c == '_'

/-- Classify a single token as operand. -/
private def parseOperandToken? (tok : String) : Option OperandV1 :=
  if tok.isEmpty then none
  else if let some r := parseRegister? tok then
    some (.register r)
  else if tok == "true" || tok == "false" then
    some (.literal tok)
  else if tok.front.isDigit then
    some (.literal tok)
  else if tok.front == '-' && tok.length > 1 &&
      ((tok.drop 1).copy).front.isDigit then
    some (.literal tok)
  else if isIdentStart tok.front && tok.all isIdentCont then
    some (.identifier tok)
  else
    none

private def splitTokens (s : String) : Array String :=
  Id.run do
    let mut out : Array String := #[]
    let mut cur : String := ""
    for c in s.toList do
      if c == ' ' || c == '\t' then
        if !cur.isEmpty then
          out := out.push cur
          cur := ""
      else
        cur := cur.push c
    if !cur.isEmpty then
      out := out.push cur
    pure out

private def expectEndsWithSemi (line : String) : Option String :=
  let t := line.trimAsciiEnd.copy
  if t.endsWith ";" then some (dropSuffix t 1 |>.trimAscii.copy) else none

private def stripIndent? (line : String) : Option String :=
  if line.startsWith indent then some (dropPrefix line indent.length) else none

private def parseMappingAccess? (tok : String) : Option (String × OperandV1) :=
  match tok.splitOn "[" with
  | [name, rest] =>
      if name.isEmpty then none
      else if rest.endsWith "]" then
        let keyTok := dropSuffix rest 1
        match parseOperandToken? keyTok with
        | some key => some (name, key)
        | none => none
      else none
  | _ => none

private def parseInstruction? (raw : String) : Option InstructionV1 := do
  let line ← expectEndsWithSemi raw
  let toks := splitTokens line
  if toks.isEmpty then none
  let head := toks[0]!
  match head with
  | "input" =>
      guard (toks.size == 4)
      guard (toks[2]! == "as")
      let reg ← parseRegister? toks[1]!
      let ty ← parseTypeAnn? toks[3]!
      pure (.input reg ty)
  | "output" =>
      guard (toks.size == 4)
      guard (toks[2]! == "as")
      let reg ← parseRegister? toks[1]!
      let ty ← parseTypeAnn? toks[3]!
      pure (.output reg ty)
  | "async" =>
      guard (toks.size >= 4)
      let name := toks[1]!
      let intoIdx ← toks.findIdx? (· == "into")
      guard (intoIdx >= 2)
      guard (intoIdx + 1 == toks.size - 1)
      let dest ← parseRegister? toks[intoIdx + 1]!
      let argToks := toks.extract 2 intoIdx
      let args ← argToks.mapM parseRegister?
      pure (.asyncCall name args dest)
  | "assert.eq" =>
      guard (toks.size == 3)
      let left ← parseOperandToken? toks[1]!
      let right ← parseOperandToken? toks[2]!
      pure (.assertEq left right)
  | "get.or_use" =>
      guard (toks.size == 5)
      guard (toks[3]! == "into")
      let (mapping, key) ← parseMappingAccess? toks[1]!
      let default ← parseOperandToken? toks[2]!
      let dest ← parseRegister? toks[4]!
      pure (.getOrUse mapping key default dest)
  | "set" =>
      guard (toks.size == 4)
      guard (toks[2]! == "into")
      let value ← parseOperandToken? toks[1]!
      let (mapping, key) ← parseMappingAccess? toks[3]!
      pure (.set value mapping key)
  | op =>
      match toks.findIdx? (· == "into") with
      | none => none
      | some intoIdx =>
          guard (intoIdx + 1 == toks.size - 1)
          let dest ← parseRegister? toks[intoIdx + 1]!
          if intoIdx == 2 then
            let src ← parseOperandToken? toks[1]!
            pure (.unary op src dest)
          else if intoIdx == 3 then
            let left ← parseOperandToken? toks[1]!
            let right ← parseOperandToken? toks[2]!
            pure (.binary op left right dest)
          else
            none

/-- Consume zero or more indented instruction lines. Stops at blank or
    non-indented line (left for the next item). -/
private partial def parseBodyLines
    (c : Cursor) (acc : Array InstructionV1) :
    Option (Array InstructionV1 × Cursor) :=
  match c.peek with
  | none => some (acc, c)
  | some line =>
      if isBlank line then
        some (acc, c)
      else if line.startsWith indent then
        match stripIndent? line with
        | none => none
        | some rest =>
            match parseInstruction? rest with
            | none => none
            | some instr => parseBodyLines c.advance (acc.push instr)
      else
        some (acc, c)

private def parseItem? (c0 : Cursor) : Option (ItemV1 × Cursor) := do
  let c := skipBlank c0
  let line ← c.peek
  let c := c.advance
  if let some rest := stripLeading? line "mapping " then
    guard (rest.endsWith ":")
    let name := dropSuffix rest 1
    guard (!name.isEmpty)
    let keyLine ← c.peek
    let c := c.advance
    let keyRest ← stripIndent? keyLine
    let keyBody ← expectEndsWithSemi keyRest
    let keyToks := splitTokens keyBody
    guard (keyToks.size == 3 && keyToks[0]! == "key" && keyToks[1]! == "as")
    let keyType ← parseTypeAnn? keyToks[2]!
    let valLine ← c.peek
    let c := c.advance
    let valRest ← stripIndent? valLine
    let valBody ← expectEndsWithSemi valRest
    let valToks := splitTokens valBody
    guard (valToks.size == 3 && valToks[0]! == "value" && valToks[1]! == "as")
    let valueType ← parseTypeAnn? valToks[2]!
    pure (.mapping { name, keyType, valueType }, c)
  else if let some rest := stripLeading? line "function " then
    guard (rest.endsWith ":")
    let name := dropSuffix rest 1
    guard (!name.isEmpty)
    let (body, c) ← parseBodyLines c #[]
    pure (.function { name, body }, c)
  else if let some rest := stripLeading? line "finalize " then
    guard (rest.endsWith ":")
    let name := dropSuffix rest 1
    guard (!name.isEmpty)
    let (body, c) ← parseBodyLines c #[]
    pure (.finalize { name, body }, c)
  else if line == "constructor:" then
    let (body, c) ← parseBodyLines c #[]
    pure (.constructor { body }, c)
  else
    none

private partial def parseItems
    (c : Cursor) (acc : Array ItemV1) : Option (Array ItemV1) :=
  let c := skipBlank c
  if c.eof then
    some acc
  else
    match parseItem? c with
    | none => none
    | some (item, c') => parseItems c' (acc.push item)

/-- Decode full program text. Fail closed on trailing garbage / unknown ops. -/
def decodeProgram? (text : String) : Option ProgramV1 :=
  let normalized := text.replace "\r\n" "\n"
  let rawLines := (normalized.splitOn "\n").toArray
  let lines :=
    if rawLines.size > 0 && rawLines.back! == "" then
      rawLines.pop
    else
      rawLines
  let c0 : Cursor := { lines, idx := 0 }
  let c := skipBlank c0
  match c.peek with
  | none => none
  | some header =>
      match stripLeading? header "program " with
      | none => none
      | some nameRest =>
          if !nameRest.endsWith ";" then none
          else
            let name := dropSuffix nameRest 1
            if name.isEmpty then none
            else
              match parseItems c.advance #[] with
              | none => none
              | some items => some { name, items }

end ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1
