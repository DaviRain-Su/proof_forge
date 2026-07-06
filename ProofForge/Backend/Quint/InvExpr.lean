import ProofForge.Backend.Quint.Model

namespace ProofForge.Backend.Quint.InvExpr

open ProofForge.Backend.Quint

/-- Errors produced while parsing scenario invariant expressions. -/
structure ParseError where
  message : String

def ParseError.render (err : ParseError) : String := err.message

/-- Token kinds for the tiny invariant expression language. -/
inductive Token where
  | number (n : Nat)
  | str (s : String)
  | bool (b : Bool)
  | ident (name : String)
  | plus | minus | star | slash
  | eq | ne | lt | le | gt | ge
  | ampamp | pipepipe | bang
  | lparen | rparen
  | eof
  deriving BEq, Repr

namespace Token

def toString : Token → String
  | .number n => s!"{n}"
  | .str s => s!"\"{s}\""
  | .bool true => "true"
  | .bool false => "false"
  | .ident name => name
  | .plus => "+"
  | .minus => "-"
  | .star => "*"
  | .slash => "/"
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="
  | .ampamp => "&&"
  | .pipepipe => "||"
  | .bang => "!"
  | .lparen => "("
  | .rparen => ")"
  | .eof => "<eof>"

end Token

/-- A single token with its source position. -/
structure Located where
  tok : Token
  pos : Nat
  deriving Repr

/-- Lexical analysis for invariant expressions. -/
def isIdentStart (c : Char) : Bool :=
  c.isAlpha || c == '_'

def isIdentCont (c : Char) : Bool :=
  c.isAlphanum || c == '_'

partial def readDigits (n : Nat) : List Char → Nat × List Char
  | [] => (n, [])
  | d :: ds =>
      if d.isDigit then
        readDigits (n * 10 + (d.toNat - '0'.toNat)) ds
      else
        (n, d :: ds)

partial def readString (acc : List Char) : List Char → Except ParseError (String × List Char)
  | [] => .error { message := "unterminated string" }
  | '"' :: ds => .ok (String.ofList acc.reverse, ds)
  | d :: ds => readString (d :: acc) ds

partial def readIdent (acc : List Char) : List Char → String × List Char
  | [] => (String.ofList acc.reverse, [])
  | d :: ds =>
      if isIdentCont d then
        readIdent (d :: acc) ds
      else
        (String.ofList acc.reverse, d :: ds)

partial def lexLoop (acc : List Located) (pos : Nat) (cs : List Char) : Except ParseError (List Located) :=
  match cs with
  | [] => .ok (acc.reverse ++ [{ tok := .eof, pos }])
  | c :: rest =>
      if c == ' ' || c == '\t' || c == '\r' || c == '\n' then
        lexLoop acc (pos + 1) rest
      else if c.isDigit then
        let (n, rest') := readDigits (c.toNat - '0'.toNat) rest
        lexLoop ({ tok := .number n, pos } :: acc) (pos + 1) rest'
      else if c == '"' then
        match readString [] rest with
        | .error e => .error e
        | .ok (s, rest') =>
            lexLoop ({ tok := .str s, pos } :: acc) (pos + 2 + s.length) rest'
      else if isIdentStart c then
        let (name, rest') := readIdent [c] rest
        let tok := match name with
          | "true" => .bool true
          | "false" => .bool false
          | "and" => .ampamp
          | "or" => .pipepipe
          | "not" => .bang
          | _ => .ident name
        lexLoop ({ tok, pos } :: acc) (pos + name.length) rest'
      else
        let single? :=
          match cs with
          | '&' :: '&' :: r => some (.ampamp, 2, r)
          | '|' :: '|' :: r => some (.pipepipe, 2, r)
          | '=' :: '=' :: r => some (.eq, 2, r)
          | '!' :: '=' :: r => some (.ne, 2, r)
          | '<' :: '=' :: r => some (.le, 2, r)
          | '>' :: '=' :: r => some (.ge, 2, r)
          | '<' :: r => some (.lt, 1, r)
          | '>' :: r => some (.gt, 1, r)
          | '+' :: r => some (.plus, 1, r)
          | '-' :: r => some (.minus, 1, r)
          | '*' :: r => some (.star, 1, r)
          | '/' :: r => some (.slash, 1, r)
          | '!' :: r => some (.bang, 1, r)
          | '(' :: r => some (.lparen, 1, r)
          | ')' :: r => some (.rparen, 1, r)
          | _ => none
        match single? with
        | some (tok, consumed, rest') =>
            lexLoop ({ tok, pos } :: acc) (pos + consumed) rest'
        | none =>
            .error { message := s!"unexpected character '{c}' at position {pos}" }

def lex (input : String) : Except ParseError (List Located) :=
  lexLoop [] 0 input.toList

/-- Parser state: list of located tokens. -/
abbrev Parser := List Located

/-- The first token without consuming it. -/
def peek : Parser → Token
  | [] => .eof
  | t :: _ => t.tok

/-- Consume the first token. -/
def advance : Parser → Parser
  | [] => []
  | _ :: ts => ts

/-- Position of the first token. -/
def pos : Parser → Nat
  | [] => 0
  | t :: _ => t.pos

/-- Expect a specific token, otherwise fail. -/
def expect (p : Parser) (t : Token) : Except ParseError Parser :=
  if peek p == t then
    .ok (advance p)
  else
    .error { message := s!"expected {t.toString} at position {pos p}, got {peek p |>.toString}" }

mutual
  /-- Parse a full expression. -/
  partial def parseExpr (p : Parser) : Except ParseError (Expr × Parser) :=
    parseOr p

  partial def parseOr (p : Parser) : Except ParseError (Expr × Parser) := do
    let (lhs0, p0) ← parseAnd p
    let mut lhs := lhs0
    let mut p1 := p0
    while peek p1 == .pipepipe do
      let (rhs, p2) ← parseAnd (advance p1)
      lhs := .binOp .or lhs rhs
      p1 := p2
    .ok (lhs, p1)

  partial def parseAnd (p : Parser) : Except ParseError (Expr × Parser) := do
    let (lhs0, p0) ← parseNot p
    let mut lhs := lhs0
    let mut p1 := p0
    while peek p1 == .ampamp do
      let (rhs, p2) ← parseNot (advance p1)
      lhs := .binOp .and lhs rhs
      p1 := p2
    .ok (lhs, p1)

  partial def parseNot (p : Parser) : Except ParseError (Expr × Parser) := do
    if peek p == .bang then
      let (e, p1) ← parseNot (advance p)
      .ok (.unOp .not e, p1)
    else
      parseCompare p

  partial def parseCompare (p : Parser) : Except ParseError (Expr × Parser) := do
    let (lhs, p1) ← parseAdd p
    match peek p1 with
    | .eq => do
        let (rhs, p2) ← parseAdd (advance p1)
        .ok (.binOp .eq lhs rhs, p2)
    | .ne => do
        let (rhs, p2) ← parseAdd (advance p1)
        .ok (.binOp .ne lhs rhs, p2)
    | .lt => do
        let (rhs, p2) ← parseAdd (advance p1)
        .ok (.binOp .lt lhs rhs, p2)
    | .le => do
        let (rhs, p2) ← parseAdd (advance p1)
        .ok (.binOp .le lhs rhs, p2)
    | .gt => do
        let (rhs, p2) ← parseAdd (advance p1)
        .ok (.binOp .gt lhs rhs, p2)
    | .ge => do
        let (rhs, p2) ← parseAdd (advance p1)
        .ok (.binOp .ge lhs rhs, p2)
    | _ => .ok (lhs, p1)

  partial def parseAdd (p : Parser) : Except ParseError (Expr × Parser) := do
    let (lhs0, p0) ← parseMul p
    let mut lhs := lhs0
    let mut p1 := p0
    while
      match peek p1 with
      | .plus | .minus => true
      | _ => false
    do
      match peek p1 with
      | .plus =>
          let (rhs, p2) ← parseMul (advance p1)
          lhs := .binOp .add lhs rhs
          p1 := p2
      | .minus =>
          let (rhs, p2) ← parseMul (advance p1)
          lhs := .binOp .sub lhs rhs
          p1 := p2
      | _ => break -- unreachable
    .ok (lhs, p1)

  partial def parseMul (p : Parser) : Except ParseError (Expr × Parser) := do
    let (lhs0, p0) ← parseUnary p
    let mut lhs := lhs0
    let mut p1 := p0
    while
      match peek p1 with
      | .star | .slash => true
      | _ => false
    do
      match peek p1 with
      | .star =>
          let (rhs, p2) ← parseUnary (advance p1)
          lhs := .binOp .mul lhs rhs
          p1 := p2
      | .slash =>
          let (rhs, p2) ← parseUnary (advance p1)
          lhs := .binOp .div lhs rhs
          p1 := p2
      | _ => break -- unreachable
    .ok (lhs, p1)

  partial def parseUnary (p : Parser) : Except ParseError (Expr × Parser) := do
    match peek p with
    | .minus =>
        let (e, p1) ← parseUnary (advance p)
        .ok (.unOp .neg e, p1)
    | _ => parsePrimary p

  partial def parsePrimary (p : Parser) : Except ParseError (Expr × Parser) := do
    match peek p with
    | .number n => .ok (.literalInt (Int.ofNat n), advance p)
    | .str s => .ok (.literalStr s, advance p)
    | .bool b => .ok (.literalBool b, advance p)
    | .ident name => .ok (.local name, advance p)
    | .lparen =>
        let (e, p1) ← parseExpr (advance p)
        let p2 ← expect p1 .rparen
        .ok (e, p2)
    | t => .error { message := s!"unexpected token {t.toString} at position {pos p}" }
end

/-- Parse a scenario invariant expression string into a Quint `Expr`. -/
def parse (input : String) : Except ParseError Expr := do
  let toks ← lex input
  let (e, p) ← parseExpr toks
  if peek p != .eof then
    .error { message := s!"unexpected trailing token {peek p |>.toString} at position {pos p}" }
  else
    .ok e

end InvExpr
