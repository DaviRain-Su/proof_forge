import ProofForge.IR.Contract
import ProofForge.Solana

namespace ProofForge.Contract.Learn

open ProofForge.IR

inductive Token where
  | ident (value : String)
  | number (value : Nat)
  | string (value : String)
  | symbol (value : String)
  deriving Repr

inductive BinaryOp where
  | add
  | sub
  | mul
  | div
  deriving Repr

inductive Expr where
  | number (value : Nat)
  | name (value : String)
  | call0 (name : String)
  | binary (op : BinaryOp) (lhs rhs : Expr)
  deriving Repr

structure FieldDecl where
  name : String
  type : ValueType
  deriving Repr

abbrev ParamDecl := FieldDecl

inductive SolanaSeed where
  | literal (value : String)
  | account (name : String)
  deriving Repr

inductive SolanaSignerSeed where
  | pda (name : String)
  | bump (name : String)
  deriving Repr

inductive SolanaItem where
  | allocatorBump
  | account (name : String) (access : ProofForge.Solana.AccountAccess)
      (signerPolicy : ProofForge.Solana.SignerPolicy) (owner : String)
  | pda (name : String) (seeds : Array SolanaSeed) (bump account : String) (isSigner : Bool)
  | systemTransfer (name fromAccount toAccount lamportsSource : String)
  | systemCreateAccount (name payer newAccount lamportsSource spaceSource owner : String)
  | splTokenTransferChecked (name source mint destination authority amountSource : String)
      (decimals : Nat) (signerSeeds : Array SolanaSignerSeed)
  | splTokenMintTo (name mint destination authority amountSource : String)
      (signerSeeds : Array SolanaSignerSeed)
  | splTokenBurn (name source mint authority amountSource : String)
      (signerSeeds : Array SolanaSignerSeed)
  | splTokenApprove (name source delegate owner amountSource : String)
      (signerSeeds : Array SolanaSignerSeed)
  | splTokenRevoke (name source owner : String)
      (signerSeeds : Array SolanaSignerSeed)
  | splTokenCloseAccount (name account destination authority : String)
      (signerSeeds : Array SolanaSignerSeed)
  deriving Repr

inductive Stmt where
  | letBind (name : String) (type : ValueType) (value : Expr)
  | assign (target : String) (value : Expr)
  | emit (eventName : String) (fields : Array (String × Expr))
  | solanaDerivePda (name : String) (seeds : Array SolanaSeed) (bump account : String)
      (isSigner : Bool)
  | solanaInvokeSystemTransfer (name fromAccount toAccount lamportsSource : String)
  | solanaInvokeSystemCreateAccount (name payer newAccount lamportsSource spaceSource owner : String)
  | solanaInvokeSplTokenTransferChecked (name source mint destination authority amountSource : String)
      (decimals : Nat) (signerSeeds : Array SolanaSignerSeed)
  | solanaInvokeSplTokenMintTo (name mint destination authority amountSource : String)
      (signerSeeds : Array SolanaSignerSeed)
  | solanaInvokeSplTokenBurn (name source mint authority amountSource : String)
      (signerSeeds : Array SolanaSignerSeed)
  | solanaInvokeSplTokenApprove (name source delegate owner amountSource : String)
      (signerSeeds : Array SolanaSignerSeed)
  | solanaInvokeSplTokenRevoke (name source owner : String)
      (signerSeeds : Array SolanaSignerSeed)
  | solanaInvokeSplTokenCloseAccount (name account destination authority : String)
      (signerSeeds : Array SolanaSignerSeed)
  | solanaSetReturnData (name sourceState : String) (bytes : Nat)
  | solanaGetReturnData (name destinationState : String) (maxBytes : Nat)
      (lengthState? : Option String) (programIdStates : Array String)
  | solanaRemainingComputeUnits (name outputState : String)
  | solanaLogRemainingComputeUnits (name : String)
  | solanaLogAccountPubkey (name account : String)
  | solanaLogStateData (name sourceState : String) (bytes : Nat)
  | solanaMemoryMemcpy (name dstState srcState : String) (bytes : Nat)
  | solanaMemoryMemmove (name dstState srcState : String) (bytes : Nat)
  | solanaMemoryMemcmp (name lhsState rhsState resultState : String) (bytes : Nat)
  | solanaMemoryMemset (name dstState : String) (value bytes : Nat)
  | solanaCryptoHash (op : ProofForge.Solana.CryptoHashOp) (name inputState : String)
      (bytes : Nat) (outputStates : Array String)
  | solanaSysvarRead (kind : ProofForge.Solana.SysvarKind)
      (field : ProofForge.Solana.SysvarField) (name outputState : String)
  | return (value : Expr)
  deriving Repr

inductive MethodKind where
  | entry
  | query
  deriving Repr

structure MethodDecl where
  kind : MethodKind
  name : String
  selector? : Option String := none
  params : Array ParamDecl
  returns : ValueType
  body : Array Stmt
  deriving Repr

structure EventDecl where
  name : String
  fields : Array FieldDecl
  deriving Repr

structure ContractDecl where
  name : String
  state : Array FieldDecl
  bindings : Array FieldDecl := #[]
  events : Array EventDecl
  solanaItems : Array SolanaItem := #[]
  methods : Array MethodDecl
  deriving Repr

private def isWhitespace (ch : Char) : Bool :=
  ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r'

private def isIdentStart (ch : Char) : Bool :=
  ch == '_' || (ch.isAlphanum && !ch.isDigit)

private def isIdentContinue (ch : Char) : Bool :=
  ch == '_' || ch.isAlphanum

private def isSymbol (ch : Char) : Bool :=
  "{}[]():,+-*/=;".contains ch

private partial def takeWhile (pred : Char → Bool) (chars : List Char)
    (acc : List Char) : String × List Char :=
  match chars with
  | [] => (String.ofList acc.reverse, [])
  | ch :: rest =>
      if pred ch then
        takeWhile pred rest (ch :: acc)
      else
        (String.ofList acc.reverse, chars)

private partial def takeStringLiteral (chars : List Char) (acc : List Char) :
    Except String (String × List Char) :=
  match chars with
  | [] => .error "unterminated string literal"
  | '"' :: rest => .ok (String.ofList acc.reverse, rest)
  | '\\' :: '"' :: rest => takeStringLiteral rest ('"' :: acc)
  | ch :: rest => takeStringLiteral rest (ch :: acc)

private partial def lexChars (chars : List Char) (tokens : Array Token) :
    Except String (Array Token) :=
  match chars with
  | [] => .ok tokens
  | ch :: rest =>
      if isWhitespace ch then
        lexChars rest tokens
      else if ch == '/' && rest.head? == some '/' then
        let (_, tail) := takeWhile (fun c => c != '\n') rest []
        lexChars tail tokens
      else if ch == '"' then
        match takeStringLiteral rest [] with
        | .ok (value, tail) => lexChars tail (tokens.push (.string value))
        | .error err => .error err
      else if isIdentStart ch then
        let (text, tail) := takeWhile isIdentContinue rest [ch]
        lexChars tail (tokens.push (.ident text))
      else if ch.isDigit then
        let (text, tail) := takeWhile (fun c => c.isDigit) rest [ch]
        match text.toNat? with
        | some value => lexChars tail (tokens.push (.number value))
        | none => .error s!"invalid numeric literal `{text}`"
      else if isSymbol ch then
        lexChars rest (tokens.push (.symbol (String.singleton ch)))
      else
        .error s!"unexpected character `{ch}`"

def lex (source : String) : Except String (Array Token) :=
  lexChars source.toList #[]

structure ParserState where
  tokens : Array Token
  pos : Nat := 0
  deriving Repr

abbrev ParserM := StateT ParserState (Except String)

private def failAt {α : Type} (message : String) : ParserM α := do
  let state ← get
  throw s!"{message} at token {state.pos}"

private def peek? : ParserM (Option Token) := do
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
  if (← consumeSymbol symbol) then
    pure ()
  else
    failAt s!"expected symbol `{symbol}`"

private def expectIdent : ParserM String := do
  match (← peek?) with
  | some (.ident value) =>
      advance
      pure value
  | _ => failAt "expected identifier"

private def expectText : ParserM String := do
  match (← peek?) with
  | some (.ident value) =>
      advance
      pure value
  | some (.string value) =>
      advance
      pure value
  | _ => failAt "expected identifier or string"

private def expectKeyword (keyword : String) : ParserM Unit := do
  let value ← expectIdent
  if value == keyword then
    pure ()
  else
    failAt s!"expected keyword `{keyword}`, got `{value}`"

private def consumeKeyword (keyword : String) : ParserM Bool := do
  match (← peek?) with
  | some (.ident value) =>
      if value == keyword then
        advance
        pure true
      else
        pure false
  | _ => pure false

private def expectNumber : ParserM Nat := do
  match (← peek?) with
  | some (.number value) =>
      advance
      pure value
  | _ => failAt "expected number"

private def parseType : ParserM ValueType := do
  let value ← expectIdent
  match value with
  | "u64" => pure .u64
  | "u32" => pure .u32
  | "bool" => pure .bool
  | "unit" => pure .unit
  | other => failAt s!"unsupported Learn type `{other}`"

private def parseFieldDecl : ParserM FieldDecl := do
  let name ← expectIdent
  expectSymbol ":"
  let type ← parseType
  pure { name, type }

private partial def parseFieldDecls : ParserM (Array FieldDecl) := do
  if (← consumeSymbol ")") then
    pure #[]
  else
    let mut fields := #[]
    fields := fields.push (← parseFieldDecl)
    while (← consumeSymbol ",") do
      fields := fields.push (← parseFieldDecl)
    expectSymbol ")"
    pure fields

private partial def parseParams : ParserM (Array ParamDecl) := do
  expectSymbol "("
  parseFieldDecls

private partial def parseOptionalSelector : ParserM (Option String) := do
  if (← consumeKeyword "selector") then
    pure (some (← expectText))
  else
    pure none

private partial def parseIdentArgs : ParserM (Array String) := do
  expectSymbol "("
  if (← consumeSymbol ")") then
    pure #[]
  else
    let mut args := #[]
    args := args.push (← expectIdent)
    while (← consumeSymbol ",") do
      args := args.push (← expectIdent)
    expectSymbol ")"
    pure args

private partial def parseIdentList : ParserM (Array String) := do
  expectSymbol "["
  if (← consumeSymbol "]") then
    pure #[]
  else
    let mut items := #[]
    items := items.push (← expectIdent)
    while (← consumeSymbol ",") do
      items := items.push (← expectIdent)
    expectSymbol "]"
    pure items

private def expectArgs (name : String) (args : Array String) (size : Nat) : ParserM Unit :=
  if args.size == size then
    pure ()
  else
    failAt s!"{name} expects {size} arguments, got {args.size}"

private def parseAccountAccess : ParserM ProofForge.Solana.AccountAccess := do
  let access ← expectIdent
  match access with
  | "readonly" => pure .readOnly
  | "writable" => pure .writable
  | other => failAt s!"unsupported Solana account access `{other}`"

private partial def parseSolanaSeeds : ParserM (Array SolanaSeed) := do
  expectSymbol "["
  if (← consumeSymbol "]") then
    pure #[]
  else
    let mut seeds := #[]
    let parseOne : ParserM SolanaSeed := do
      let kind ← expectIdent
      let value ← expectText
      match kind with
      | "literal" => pure (.literal value)
      | "account" => pure (.account value)
      | other => failAt s!"unsupported Solana PDA seed kind `{other}`"
    seeds := seeds.push (← parseOne)
    while (← consumeSymbol ",") do
      seeds := seeds.push (← parseOne)
    expectSymbol "]"
    pure seeds

private partial def parseSolanaSignerSeeds : ParserM (Array SolanaSignerSeed) := do
  expectSymbol "["
  if (← consumeSymbol "]") then
    pure #[]
  else
    let mut seeds := #[]
    let parseOne : ParserM SolanaSignerSeed := do
      let kind ← expectIdent
      let value ← expectIdent
      match kind with
      | "pda" => pure (.pda value)
      | "bump" => pure (.bump value)
      | other => failAt s!"unsupported Solana signer seed kind `{other}`"
    seeds := seeds.push (← parseOne)
    while (← consumeSymbol ",") do
      seeds := seeds.push (← parseOne)
    expectSymbol "]"
    pure seeds

private partial def parseDecimals : ParserM Nat := do
  expectKeyword "decimals"
  expectSymbol "("
  let value ← expectNumber
  expectSymbol ")"
  pure value

private partial def parseOptionalSignerSeeds : ParserM (Array SolanaSignerSeed) := do
  if (← consumeKeyword "signer_seeds") then
    parseSolanaSignerSeeds
  else
    pure #[]

private partial def parsePdaTail : ParserM (Array SolanaSeed × String × String × Bool) := do
  expectKeyword "seeds"
  let seeds ← parseSolanaSeeds
  expectKeyword "bump"
  let bump ← expectIdent
  expectKeyword "account"
  let account ← expectIdent
  let isSigner ← consumeKeyword "signer"
  pure (seeds, bump, account, isSigner)

private partial def parseAccountTail :
    ParserM (ProofForge.Solana.AccountAccess × ProofForge.Solana.SignerPolicy × String) := do
  let access ← parseAccountAccess
  let mut signerPolicy : ProofForge.Solana.SignerPolicy := .none
  let mut owner := "any"
  let mut done := false
  repeat
    if (← consumeKeyword "signer") then
      signerPolicy := .signer
    else if (← consumeKeyword "owner") then
      owner ← expectText
    else
      done := true
    if done then
      break
  pure (access, signerPolicy, owner)

private partial def parseReturnDataStmt : ParserM Stmt := do
  let op ← expectIdent
  match op with
  | "set" =>
      let name ← expectIdent
      let args ← parseIdentArgs
      expectArgs "return_data set" args 1
      expectKeyword "bytes"
      let bytes ← expectNumber
      pure (.solanaSetReturnData name args[0]! bytes)
  | "get" =>
      let name ← expectIdent
      let args ← parseIdentArgs
      expectArgs "return_data get" args 1
      expectKeyword "max_bytes"
      let maxBytes ← expectNumber
      let lengthState? ←
        if (← consumeKeyword "length") then
          pure (some (← expectIdent))
        else
          pure none
      let programIdStates ←
        if (← consumeKeyword "program_id_states") then
          parseIdentList
        else
          pure #[]
      pure (.solanaGetReturnData name args[0]! maxBytes lengthState? programIdStates)
  | other => failAt s!"unsupported Solana return_data op `{other}`"

private partial def parseComputeUnitsStmt : ParserM Stmt := do
  let op ← expectIdent
  match op with
  | "remaining" =>
      let name ← expectIdent
      let args ← parseIdentArgs
      expectArgs "compute_units remaining" args 1
      pure (.solanaRemainingComputeUnits name args[0]!)
  | "log_remaining" =>
      let name ← expectIdent
      let args ← parseIdentArgs
      expectArgs "compute_units log_remaining" args 0
      pure (.solanaLogRemainingComputeUnits name)
  | other => failAt s!"unsupported Solana compute_units op `{other}`"

private partial def parseLogStmt : ParserM Stmt := do
  let op ← expectIdent
  match op with
  | "pubkey" =>
      let name ← expectIdent
      let args ← parseIdentArgs
      expectArgs "log pubkey" args 1
      pure (.solanaLogAccountPubkey name args[0]!)
  | "data" =>
      let name ← expectIdent
      let args ← parseIdentArgs
      expectArgs "log data" args 1
      expectKeyword "bytes"
      let bytes ← expectNumber
      pure (.solanaLogStateData name args[0]! bytes)
  | other => failAt s!"unsupported Solana log op `{other}`"

private partial def parseMemoryStmt : ParserM Stmt := do
  let op ← expectIdent
  let name ← expectIdent
  let args ← parseIdentArgs
  match op with
  | "memcpy" =>
      expectArgs "memory memcpy" args 2
      expectKeyword "bytes"
      let bytes ← expectNumber
      pure (.solanaMemoryMemcpy name args[0]! args[1]! bytes)
  | "memmove" =>
      expectArgs "memory memmove" args 2
      expectKeyword "bytes"
      let bytes ← expectNumber
      pure (.solanaMemoryMemmove name args[0]! args[1]! bytes)
  | "memcmp" =>
      expectArgs "memory memcmp" args 3
      expectKeyword "bytes"
      let bytes ← expectNumber
      pure (.solanaMemoryMemcmp name args[0]! args[1]! args[2]! bytes)
  | "memset" =>
      expectArgs "memory memset" args 1
      expectKeyword "value"
      let value ← expectNumber
      expectKeyword "bytes"
      let bytes ← expectNumber
      pure (.solanaMemoryMemset name args[0]! value bytes)
  | other => failAt s!"unsupported Solana memory op `{other}`"

private def parseCryptoHashOp (op : String) : ParserM ProofForge.Solana.CryptoHashOp := do
  match op with
  | "sha256" => pure .sha256
  | "keccak256" => pure .keccak256
  | "blake3" => pure .blake3
  | other => failAt s!"unsupported Solana crypto hash op `{other}`"

private partial def parseCryptoStmt : ParserM Stmt := do
  let op ← parseCryptoHashOp (← expectIdent)
  let name ← expectIdent
  let args ← parseIdentArgs
  expectArgs "crypto hash" args 1
  expectKeyword "bytes"
  let bytes ← expectNumber
  expectKeyword "output"
  let outputStates ← parseIdentList
  pure (.solanaCryptoHash op name args[0]! bytes outputStates)

private def parseSysvarKind (value : String) : ParserM ProofForge.Solana.SysvarKind := do
  match value with
  | "rent" => pure .rent
  | "epoch_schedule" => pure .epochSchedule
  | "epoch_rewards" => pure .epochRewards
  | "last_restart_slot" => pure .lastRestartSlot
  | other => failAt s!"unsupported Solana sysvar kind `{other}`"

private def parseSysvarField (value : String) : ParserM ProofForge.Solana.SysvarField := do
  match value with
  | "lamports_per_byte_year" => pure .rentLamportsPerByteYear
  | "slots_per_epoch" => pure .epochScheduleSlotsPerEpoch
  | "leader_schedule_slot_offset" => pure .epochScheduleLeaderScheduleSlotOffset
  | "warmup" => pure .epochScheduleWarmup
  | "first_normal_epoch" => pure .epochScheduleFirstNormalEpoch
  | "first_normal_slot" => pure .epochScheduleFirstNormalSlot
  | "distribution_starting_block_height" => pure .epochRewardsDistributionStartingBlockHeight
  | "num_partitions" => pure .epochRewardsNumPartitions
  | "parent_blockhash_word0" => pure .epochRewardsParentBlockhashWord0
  | "parent_blockhash_word1" => pure .epochRewardsParentBlockhashWord1
  | "parent_blockhash_word2" => pure .epochRewardsParentBlockhashWord2
  | "parent_blockhash_word3" => pure .epochRewardsParentBlockhashWord3
  | "total_points_low" => pure .epochRewardsTotalPointsLow
  | "total_points_high" => pure .epochRewardsTotalPointsHigh
  | "total_rewards" => pure .epochRewardsTotalRewards
  | "distributed_rewards" => pure .epochRewardsDistributedRewards
  | "active" => pure .epochRewardsActive
  | "last_restart_slot" => pure .lastRestartSlot
  | other => failAt s!"unsupported Solana sysvar field `{other}`"

private partial def parseSysvarStmt : ParserM Stmt := do
  let kind ← parseSysvarKind (← expectIdent)
  let field ← parseSysvarField (← expectIdent)
  if field.kind == kind then
    let name ← expectIdent
    let args ← parseIdentArgs
    expectArgs "sysvar read" args 1
    pure (.solanaSysvarRead kind field name args[0]!)
  else
    failAt s!"Solana sysvar field `{field.id}` does not belong to `{kind.id}`"

mutual
private partial def parseExpr : ParserM Expr :=
  parseAddSub

private partial def parseAddSub : ParserM Expr := do
  let mut lhs ← parseMulDiv
  let mut done := false
  repeat
    if (← consumeSymbol "+") then
      lhs := .binary .add lhs (← parseMulDiv)
    else if (← consumeSymbol "-") then
      lhs := .binary .sub lhs (← parseMulDiv)
    else
      done := true
    if done then
      break
  pure lhs

private partial def parseMulDiv : ParserM Expr := do
  let mut lhs ← parseAtom
  let mut done := false
  repeat
    if (← consumeSymbol "*") then
      lhs := .binary .mul lhs (← parseAtom)
    else if (← consumeSymbol "/") then
      lhs := .binary .div lhs (← parseAtom)
    else
      done := true
    if done then
      break
  pure lhs

private partial def parseAtom : ParserM Expr := do
  match (← peek?) with
  | some (.number value) =>
      advance
      pure (.number value)
  | some (.ident value) =>
      advance
      if (← consumeSymbol "(") then
        expectSymbol ")"
        pure (.call0 value)
      else
        pure (.name value)
  | some (.symbol "(") =>
      advance
      let value ← parseExpr
      expectSymbol ")"
      pure value
  | _ => failAt "expected expression"
end

private partial def parseEmitFields : ParserM (Array (String × Expr)) := do
  if (← consumeSymbol ")") then
    pure #[]
  else
    let mut fields := #[]
    let name ← expectIdent
    expectSymbol ":"
    fields := fields.push (name, (← parseExpr))
    while (← consumeSymbol ",") do
      let name ← expectIdent
      expectSymbol ":"
      fields := fields.push (name, (← parseExpr))
    expectSymbol ")"
    pure fields

private def consumeOptionalSemicolon : ParserM Unit := do
  discard <| consumeSymbol ";"

private partial def parseSolanaCpiDecl (name instruction : String) : ParserM SolanaItem := do
  let args ← parseIdentArgs
  match instruction with
  | "system_transfer" =>
      expectArgs "system_transfer" args 3
      pure (.systemTransfer name args[0]! args[1]! args[2]!)
  | "system_create_account" =>
      expectArgs "system_create_account" args 4
      expectKeyword "owner"
      let owner ← expectText
      pure (.systemCreateAccount name args[0]! args[1]! args[2]! args[3]! owner)
  | "spl_token_transfer_checked" =>
      expectArgs "spl_token_transfer_checked" args 5
      let decimals ← parseDecimals
      let signerSeeds ← parseOptionalSignerSeeds
      pure (.splTokenTransferChecked name args[0]! args[1]! args[2]! args[3]! args[4]!
        decimals signerSeeds)
  | "spl_token_mint_to" =>
      expectArgs "spl_token_mint_to" args 4
      let signerSeeds ← parseOptionalSignerSeeds
      pure (.splTokenMintTo name args[0]! args[1]! args[2]! args[3]! signerSeeds)
  | "spl_token_burn" =>
      expectArgs "spl_token_burn" args 4
      let signerSeeds ← parseOptionalSignerSeeds
      pure (.splTokenBurn name args[0]! args[1]! args[2]! args[3]! signerSeeds)
  | "spl_token_approve" =>
      expectArgs "spl_token_approve" args 4
      let signerSeeds ← parseOptionalSignerSeeds
      pure (.splTokenApprove name args[0]! args[1]! args[2]! args[3]! signerSeeds)
  | "spl_token_revoke" =>
      expectArgs "spl_token_revoke" args 2
      let signerSeeds ← parseOptionalSignerSeeds
      pure (.splTokenRevoke name args[0]! args[1]! signerSeeds)
  | "spl_token_close_account" =>
      expectArgs "spl_token_close_account" args 3
      let signerSeeds ← parseOptionalSignerSeeds
      pure (.splTokenCloseAccount name args[0]! args[1]! args[2]! signerSeeds)
  | other => failAt s!"unsupported Solana CPI instruction `{other}`"

private partial def parseSolanaItem : ParserM SolanaItem := do
  expectKeyword "solana"
  let kind ← expectIdent
  match kind with
  | "allocator" =>
      expectKeyword "bump"
      pure .allocatorBump
  | "account" =>
      let name ← expectIdent
      let (access, signerPolicy, owner) ← parseAccountTail
      pure (.account name access signerPolicy owner)
  | "pda" =>
      let name ← expectIdent
      let (seeds, bump, account, isSigner) ← parsePdaTail
      pure (.pda name seeds bump account isSigner)
  | "cpi" =>
      let name ← expectIdent
      let instruction ← expectIdent
      parseSolanaCpiDecl name instruction
  | other => failAt s!"unsupported Solana item `{other}`"

private partial def parseSolanaStmt : ParserM Stmt := do
  expectKeyword "solana"
  let kind ← expectIdent
  match kind with
  | "derive" =>
      expectKeyword "pda"
      let name ← expectIdent
      let (seeds, bump, account, isSigner) ← parsePdaTail
      consumeOptionalSemicolon
      pure (.solanaDerivePda name seeds bump account isSigner)
  | "invoke" =>
      let name ← expectIdent
      let instruction ← expectIdent
      let args ← parseIdentArgs
      let stmt ←
        match instruction with
        | "system_transfer" =>
            expectArgs "system_transfer" args 3
            pure (.solanaInvokeSystemTransfer name args[0]! args[1]! args[2]!)
        | "system_create_account" =>
            expectArgs "system_create_account" args 4
            expectKeyword "owner"
            let owner ← expectText
            pure (.solanaInvokeSystemCreateAccount name args[0]! args[1]! args[2]! args[3]! owner)
        | "spl_token_transfer_checked" =>
            expectArgs "spl_token_transfer_checked" args 5
            let decimals ← parseDecimals
            let signerSeeds ← parseOptionalSignerSeeds
            pure (.solanaInvokeSplTokenTransferChecked name args[0]! args[1]! args[2]! args[3]!
              args[4]! decimals signerSeeds)
        | "spl_token_mint_to" =>
            expectArgs "spl_token_mint_to" args 4
            let signerSeeds ← parseOptionalSignerSeeds
            pure (.solanaInvokeSplTokenMintTo name args[0]! args[1]! args[2]! args[3]! signerSeeds)
        | "spl_token_burn" =>
            expectArgs "spl_token_burn" args 4
            let signerSeeds ← parseOptionalSignerSeeds
            pure (.solanaInvokeSplTokenBurn name args[0]! args[1]! args[2]! args[3]! signerSeeds)
        | "spl_token_approve" =>
            expectArgs "spl_token_approve" args 4
            let signerSeeds ← parseOptionalSignerSeeds
            pure (.solanaInvokeSplTokenApprove name args[0]! args[1]! args[2]! args[3]! signerSeeds)
        | "spl_token_revoke" =>
            expectArgs "spl_token_revoke" args 2
            let signerSeeds ← parseOptionalSignerSeeds
            pure (.solanaInvokeSplTokenRevoke name args[0]! args[1]! signerSeeds)
        | "spl_token_close_account" =>
            expectArgs "spl_token_close_account" args 3
            let signerSeeds ← parseOptionalSignerSeeds
            pure (.solanaInvokeSplTokenCloseAccount name args[0]! args[1]! args[2]! signerSeeds)
        | other => failAt s!"unsupported Solana invoke instruction `{other}`"
      consumeOptionalSemicolon
      pure stmt
  | "return_data" =>
      let stmt ← parseReturnDataStmt
      consumeOptionalSemicolon
      pure stmt
  | "compute_units" =>
      let stmt ← parseComputeUnitsStmt
      consumeOptionalSemicolon
      pure stmt
  | "log" =>
      let stmt ← parseLogStmt
      consumeOptionalSemicolon
      pure stmt
  | "memory" =>
      let stmt ← parseMemoryStmt
      consumeOptionalSemicolon
      pure stmt
  | "crypto" =>
      let stmt ← parseCryptoStmt
      consumeOptionalSemicolon
      pure stmt
  | "sysvar" =>
      let stmt ← parseSysvarStmt
      consumeOptionalSemicolon
      pure stmt
  | other => failAt s!"unsupported Solana statement `{other}`"

private partial def parseStmt : ParserM Stmt := do
  match (← peek?) with
  | some (.ident "solana") =>
      parseSolanaStmt
  | some (.ident "let") =>
      advance
      let name ← expectIdent
      expectSymbol ":"
      let type ← parseType
      expectSymbol "="
      let value ← parseExpr
      consumeOptionalSemicolon
      pure (.letBind name type value)
  | some (.ident "emit") =>
      advance
      let eventName ← expectIdent
      expectSymbol "("
      let fields ← parseEmitFields
      consumeOptionalSemicolon
      pure (.emit eventName fields)
  | some (.ident "return") =>
      advance
      let value ← parseExpr
      consumeOptionalSemicolon
      pure (.return value)
  | some (.ident target) =>
      advance
      expectSymbol "="
      let value ← parseExpr
      consumeOptionalSemicolon
      pure (.assign target value)
  | _ => failAt "expected statement"

private partial def parseStmtBlock : ParserM (Array Stmt) := do
  expectSymbol "{"
  let mut body := #[]
  while !(← consumeSymbol "}") do
    body := body.push (← parseStmt)
  pure body

private partial def parseEvent : ParserM EventDecl := do
  expectKeyword "event"
  let name ← expectIdent
  expectSymbol "("
  let fields ← parseFieldDecls
  pure { name, fields }

private partial def parseMethod (kind : MethodKind) : ParserM MethodDecl := do
  match kind with
  | .entry => expectKeyword "entry"
  | .query => expectKeyword "query"
  let name ← expectIdent
  let selector? ← parseOptionalSelector
  let params ← parseParams
  let returns ←
    match kind with
    | .entry =>
        if ← consumeSymbol ":" then
          parseType
        else
          pure .unit
    | .query =>
        expectSymbol ":"
        parseType
  let body ← parseStmtBlock
  pure { kind, name, selector? := selector?, params, returns, body }

private partial def parseItems (state bindings : Array FieldDecl) (events : Array EventDecl)
    (solanaItems : Array SolanaItem) (methods : Array MethodDecl) :
    ParserM (Array FieldDecl × Array FieldDecl × Array EventDecl × Array SolanaItem × Array MethodDecl) := do
  match (← peek?) with
  | some (.symbol "}") =>
      advance
      pure (state, bindings, events, solanaItems, methods)
  | some (.ident "state") =>
      advance
      let decl ← parseFieldDecl
      parseItems (state.push decl) bindings events solanaItems methods
  | some (.ident "binding") =>
      advance
      let decl ← parseFieldDecl
      parseItems state (bindings.push decl) events solanaItems methods
  | some (.ident "event") =>
      let event ← parseEvent
      parseItems state bindings (events.push event) solanaItems methods
  | some (.ident "solana") =>
      let item ← parseSolanaItem
      parseItems state bindings events (solanaItems.push item) methods
  | some (.ident "entry") =>
      let method ← parseMethod .entry
      parseItems state bindings events solanaItems (methods.push method)
  | some (.ident "query") =>
      let method ← parseMethod .query
      parseItems state bindings events solanaItems (methods.push method)
  | _ => failAt "expected contract item"

private partial def parseContractDecl : ParserM ContractDecl := do
  expectKeyword "contract"
  let name ← expectIdent
  expectSymbol "{"
  let (state, bindings, events, solanaItems, methods) ← parseItems #[] #[] #[] #[] #[]
  pure { name, state, bindings, events, solanaItems, methods }

def parseTokens (tokens : Array Token) : Except String ContractDecl := do
  let (decl, state) ← parseContractDecl.run { tokens }
  if state.pos == state.tokens.size then
    pure decl
  else
    .error s!"unexpected trailing token at {state.pos}"

def parseSource (source : String) : Except String ContractDecl := do
  parseTokens (← lex source)

def parseFile (path : System.FilePath) : IO (Except String ContractDecl) := do
  pure <| parseSource (← IO.FS.readFile path)

end ProofForge.Contract.Learn
