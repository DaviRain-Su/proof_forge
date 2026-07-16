import ProofForge.Contract.Learn
import ProofForge.Contract.Token

namespace ProofForge.Contract.Token.Learn

abbrev LexToken := ProofForge.Contract.Learn.Token

structure TokenDecl where
  id : String
  spec : TokenSpec
  deriving Repr

structure PartialTokenDecl where
  id : String
  name? : Option String := none
  symbol? : Option String := none
  decimals? : Option Nat := none
  initialSupply? : Option Nat := none
  features : Array TokenFeature := #[]
  deriving Repr

structure ParserState where
  tokens : Array LexToken
  pos : Nat := 0
  deriving Repr

abbrev ParserM := StateT ParserState (Except String)

private def failAt {α : Type} (message : String) : ParserM α := do
  let state ← get
  throw s!"{message} at token {state.pos}"

private def peek? : ParserM (Option LexToken) := do
  let state ← get
  pure state.tokens[state.pos]?

private def advance : ParserM Unit := do
  modify fun state => { state with pos := state.pos + 1 }

private def consumeSymbol (symbol : String) : ParserM Bool := do
  match (← peek?) with
  | some (.symbol value) =>
      if value == symbol then
        advance
        pure true
      else
        pure false
  | _ => pure false

private def expectSymbol (symbol : String) : ParserM Unit := do
  if ← consumeSymbol symbol then
    pure ()
  else
    failAt s!"expected `{symbol}`"

private def expectIdent (what : String) : ParserM String := do
  match (← peek?) with
  | some (.ident value) =>
      advance
      pure value
  | _ => failAt s!"expected {what}"

private def expectKeyword (keyword : String) : ParserM Unit := do
  let value ← expectIdent s!"`{keyword}`"
  if value == keyword then
    pure ()
  else
    failAt s!"expected `{keyword}`, got `{value}`"

private def expectString (what : String) : ParserM String := do
  match (← peek?) with
  | some (.string value) =>
      advance
      pure value
  | _ => failAt s!"expected {what}"

private def expectNumber (what : String) : ParserM Nat := do
  match (← peek?) with
  | some (.number value) =>
      advance
      pure value
  | _ => failAt s!"expected {what}"

private def ensureFieldUnset (label : String) (value? : Option α) : ParserM Unit := do
  if value?.isSome then
    failAt s!"duplicate token field `{label}`"

private def parseFeatureIdent : ParserM TokenFeature := do
  let featureId ← expectIdent "token feature id"
  match TokenFeature.parse featureId with
  | .ok feature => pure feature
  | .error err => failAt err

private partial def parseFeatureList (features : Array TokenFeature) : ParserM (Array TokenFeature) := do
  if ← consumeSymbol "]" then
    pure features
  else
    let feature ← parseFeatureIdent
    let features := features.push feature
    if ← consumeSymbol "," then
      parseFeatureList features
    else
      expectSymbol "]"
      pure features

private partial def parseFields (decl : PartialTokenDecl) : ParserM PartialTokenDecl := do
  if ← consumeSymbol "}" then
    pure decl
  else
    let keyword ← expectIdent "token field"
    let decl ←
      match keyword with
      | "name" => do
          ensureFieldUnset "name" decl.name?
          pure { decl with name? := some (← expectString "token display name string") }
      | "symbol" => do
          ensureFieldUnset "symbol" decl.symbol?
          pure { decl with symbol? := some (← expectString "token symbol string") }
      | "decimals" => do
          ensureFieldUnset "decimals" decl.decimals?
          pure { decl with decimals? := some (← expectNumber "token decimal count") }
      | "initial_supply" => do
          ensureFieldUnset "initial_supply" decl.initialSupply?
          pure { decl with initialSupply? := some (← expectNumber "initial supply") }
      | "initialSupply" => do
          ensureFieldUnset "initialSupply" decl.initialSupply?
          pure { decl with initialSupply? := some (← expectNumber "initial supply") }
      | "feature" => do
          let feature ← parseFeatureIdent
          pure { decl with features := decl.features.push feature }
      | "features" => do
          expectSymbol "["
          let features ← parseFeatureList decl.features
          pure { decl with features := features }
      | other =>
          failAt s!"unknown token field `{other}`"
    parseFields decl

private def requireField (label : String) : Option α → Except String α
  | some value => .ok value
  | none => .error s!"token source missing required `{label}` field"

private def PartialTokenDecl.finalize (decl : PartialTokenDecl) : Except String TokenDecl := do
  let name ← requireField "name" decl.name?
  let symbol ← requireField "symbol" decl.symbol?
  let decimals ← requireField "decimals" decl.decimals?
  pure {
    id := decl.id
    spec := {
      name := name
      symbol := symbol
      decimals := decimals
      initialSupply? := decl.initialSupply?
      features := decl.features
    }
  }

def parseTokens (tokens : Array LexToken) : Except String TokenDecl := do
  let decl ←
    match (do
      expectKeyword "token"
      let id ← expectIdent "token id"
      expectSymbol "{"
      let decl ← parseFields { id := id }
      match (← peek?) with
      | none => pure decl
      | some _ => failAt "unexpected tokens after token declaration"
    ).run { tokens := tokens } with
    | .ok (decl, _) => .ok decl
    | .error err => .error err
  decl.finalize

def parse (source : String) : Except String TokenDecl := do
  parseTokens (← ProofForge.Contract.Learn.lex source)

def parseFile (path : System.FilePath) : IO (Except String TokenDecl) := do
  pure <| parse (← IO.FS.readFile path)

end ProofForge.Contract.Token.Learn
