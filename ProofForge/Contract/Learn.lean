import ProofForge.Contract.Builder
import ProofForge.Contract.Spec
import ProofForge.IR.Contract
import ProofForge.Solana
import ProofForge.Contract.Learn.Parser

namespace ProofForge.Contract.Learn

open ProofForge.IR

private def containsName (names : Array String) (name : String) : Bool :=
  names.any (fun candidate => candidate == name)

private structure LowerEnv where
  stateNames : Array String
  locals : Array String
  deriving Repr

private structure SolanaAccountRef where
  name : String
  access : ProofForge.Solana.AccountAccess := .readOnly
  signerPolicy : ProofForge.Solana.SignerPolicy := .none
  owner : String := "any"
  deriving Repr

private structure SolanaRefs where
  accounts : Array SolanaAccountRef := #[]
  pdaItems : Array SolanaItem := #[]
  cpiItems : Array SolanaItem := #[]
  deriving Repr

private def SolanaRefs.accountNames (refs : SolanaRefs) : Array String :=
  refs.accounts.map (fun account => account.name)

private def joined (values : Array String) : String :=
  String.intercalate "," values.toList

private def signerSeedSyntax : SolanaSignerSeed → String
  | .pda name => "pda:" ++ name
  | .bump name => "bump:" ++ name

private def signerSeedSignature (seeds : Array SolanaSignerSeed) : String :=
  joined (seeds.map signerSeedSyntax)

private def seedSyntax : SolanaSeed → String
  | .literal value => "literal:" ++ value
  | .account name => "account:" ++ name

private def seedSignature (seeds : Array SolanaSeed) : String :=
  joined (seeds.map seedSyntax)

private def pdaName? : SolanaItem → Option String
  | .pda name _ _ _ _ => some name
  | _ => none

private def cpiName? : SolanaItem → Option String
  | .systemTransfer name _ _ _ => some name
  | .systemCreateAccount name _ _ _ _ _ => some name
  | .splTokenTransferChecked name _ _ _ _ _ _ _ => some name
  | .splTokenMintTo name _ _ _ _ _ => some name
  | .splTokenBurn name _ _ _ _ _ => some name
  | .splTokenApprove name _ _ _ _ _ => some name
  | .splTokenRevoke name _ _ _ => some name
  | .splTokenCloseAccount name _ _ _ _ => some name
  | _ => none

private def pdaSignature? : SolanaItem → Option String
  | .pda _ seeds bump account isSigner =>
      some s!"seeds={seedSignature seeds};bump={bump};account={account};signer={isSigner}"
  | _ => none

private def cpiSignature? : SolanaItem → Option String
  | .systemTransfer _ fromAccount toAccount lamportsSource =>
      some s!"system_transfer({joined #[fromAccount, toAccount, lamportsSource]})"
  | .systemCreateAccount _ payer newAccount lamportsSource spaceSource owner =>
      some s!"system_create_account({joined #[payer, newAccount, lamportsSource, spaceSource]});owner={owner}"
  | .splTokenTransferChecked _ source mint destination authority amountSource decimals signerSeeds =>
      some s!"spl_token_transfer_checked({joined #[source, mint, destination, authority, amountSource]});decimals={decimals};signer_seeds={signerSeedSignature signerSeeds}"
  | .splTokenMintTo _ mint destination authority amountSource signerSeeds =>
      some s!"spl_token_mint_to({joined #[mint, destination, authority, amountSource]});signer_seeds={signerSeedSignature signerSeeds}"
  | .splTokenBurn _ source mint authority amountSource signerSeeds =>
      some s!"spl_token_burn({joined #[source, mint, authority, amountSource]});signer_seeds={signerSeedSignature signerSeeds}"
  | .splTokenApprove _ source delegate owner amountSource signerSeeds =>
      some s!"spl_token_approve({joined #[source, delegate, owner, amountSource]});signer_seeds={signerSeedSignature signerSeeds}"
  | .splTokenRevoke _ source owner signerSeeds =>
      some s!"spl_token_revoke({joined #[source, owner]});signer_seeds={signerSeedSignature signerSeeds}"
  | .splTokenCloseAccount _ account destination authority signerSeeds =>
      some s!"spl_token_close_account({joined #[account, destination, authority]});signer_seeds={signerSeedSignature signerSeeds}"
  | _ => none

private def cpiInvocationSignature? : Stmt → Option String
  | .solanaInvokeSystemTransfer _ fromAccount toAccount lamportsSource =>
      some s!"system_transfer({joined #[fromAccount, toAccount, lamportsSource]})"
  | .solanaInvokeSystemCreateAccount _ payer newAccount lamportsSource spaceSource owner =>
      some s!"system_create_account({joined #[payer, newAccount, lamportsSource, spaceSource]});owner={owner}"
  | .solanaInvokeSplTokenTransferChecked _ source mint destination authority amountSource decimals signerSeeds =>
      some s!"spl_token_transfer_checked({joined #[source, mint, destination, authority, amountSource]});decimals={decimals};signer_seeds={signerSeedSignature signerSeeds}"
  | .solanaInvokeSplTokenMintTo _ mint destination authority amountSource signerSeeds =>
      some s!"spl_token_mint_to({joined #[mint, destination, authority, amountSource]});signer_seeds={signerSeedSignature signerSeeds}"
  | .solanaInvokeSplTokenBurn _ source mint authority amountSource signerSeeds =>
      some s!"spl_token_burn({joined #[source, mint, authority, amountSource]});signer_seeds={signerSeedSignature signerSeeds}"
  | .solanaInvokeSplTokenApprove _ source delegate owner amountSource signerSeeds =>
      some s!"spl_token_approve({joined #[source, delegate, owner, amountSource]});signer_seeds={signerSeedSignature signerSeeds}"
  | .solanaInvokeSplTokenRevoke _ source owner signerSeeds =>
      some s!"spl_token_revoke({joined #[source, owner]});signer_seeds={signerSeedSignature signerSeeds}"
  | .solanaInvokeSplTokenCloseAccount _ account destination authority signerSeeds =>
      some s!"spl_token_close_account({joined #[account, destination, authority]});signer_seeds={signerSeedSignature signerSeeds}"
  | _ => none

private def cpiInvocationName? : Stmt → Option String
  | .solanaInvokeSystemTransfer name _ _ _ => some name
  | .solanaInvokeSystemCreateAccount name _ _ _ _ _ => some name
  | .solanaInvokeSplTokenTransferChecked name _ _ _ _ _ _ _ => some name
  | .solanaInvokeSplTokenMintTo name _ _ _ _ _ => some name
  | .solanaInvokeSplTokenBurn name _ _ _ _ _ => some name
  | .solanaInvokeSplTokenApprove name _ _ _ _ _ => some name
  | .solanaInvokeSplTokenRevoke name _ _ _ => some name
  | .solanaInvokeSplTokenCloseAccount name _ _ _ _ => some name
  | _ => none

private def buildSolanaRefs (items : Array SolanaItem) : SolanaRefs :=
  items.foldl
    (fun refs item =>
      match item with
      | .account name access signerPolicy owner =>
          { refs with accounts := refs.accounts.push { name, access, signerPolicy, owner } }
      | .pda .. => { refs with pdaItems := refs.pdaItems.push item }
      | .systemTransfer .. | .systemCreateAccount .. | .splTokenTransferChecked ..
      | .splTokenMintTo .. | .splTokenBurn .. | .splTokenApprove .. | .splTokenRevoke ..
      | .splTokenCloseAccount .. =>
          { refs with cpiItems := refs.cpiItems.push item }
      | .allocatorBump => refs)
    {}

private def findNamed? (name : String) (items : Array SolanaItem)
    (nameOf : SolanaItem → Option String) : Option SolanaItem :=
  items.find? fun item => nameOf item == some name

private def requireKnownName (kind : String) (names : Array String) (name : String) :
    Except String Unit :=
  if containsName names name then
    .ok ()
  else
    .error s!"unknown Learn {kind} `{name}`"

private def requireKnownState (stateNames : Array String) (name : String) :
    Except String Unit :=
  requireKnownName "state" stateNames name

private def requireKnownStateAll (stateNames names : Array String) : Except String Unit := do
  for name in names do
    requireKnownState stateNames name

private def requireStateOrAccount (refs : SolanaRefs) (stateNames : Array String)
    (name : String) : Except String Unit :=
  if containsName stateNames name || containsName refs.accountNames name then
    .ok ()
  else
    .error s!"unknown Learn state/account `{name}`"

private def requireKnownAccount (refs : SolanaRefs) (name : String) :
    Except String Unit :=
  requireKnownName "Solana account" refs.accountNames name

private def requireKnownAccounts (refs : SolanaRefs) (names : Array String) :
    Except String Unit := do
  for name in names do
    requireKnownAccount refs name

private def findAccount? (refs : SolanaRefs) (name : String) : Option SolanaAccountRef :=
  refs.accounts.find? fun account => account.name == name

private def requireWritableAccount (refs : SolanaRefs) (name : String) :
    Except String Unit := do
  requireKnownAccount refs name
  match findAccount? refs name with
  | some account =>
      if account.access == .writable then
        .ok ()
      else
        .error s!"Learn Solana account `{name}` must be writable"
  | none => .error s!"unknown Learn Solana account `{name}`"

private def requireSignerAccount (refs : SolanaRefs) (name : String) :
    Except String Unit := do
  requireKnownAccount refs name
  match findAccount? refs name with
  | some account =>
      if account.signerPolicy == .signer then
        .ok ()
      else
        .error s!"Learn Solana account `{name}` must be signer"
  | none => .error s!"unknown Learn Solana account `{name}`"

private def validateAccountMetas (refs : SolanaRefs)
    (writable signer : Array String) : Except String Unit := do
  requireKnownAccounts refs (writable ++ signer)
  for name in writable do
    requireWritableAccount refs name
  for name in signer do
    requireSignerAccount refs name

private def validateSignerSeeds (refs : SolanaRefs) (knownValueNames : Array String)
    (seeds : Array SolanaSignerSeed) : Except String Unit := do
  for seed in seeds do
    match seed with
    | .pda name =>
        match findNamed? name refs.pdaItems pdaName? with
        | some _ => pure ()
        | none => .error s!"unknown Learn Solana PDA signer seed `{name}`"
    | .bump name =>
        requireKnownName "PDA bump" knownValueNames name

private def validatePdaSeeds (refs : SolanaRefs) (seeds : Array SolanaSeed) :
    Except String Unit := do
  for seed in seeds do
    match seed with
    | .literal _ => pure ()
    | .account name => requireKnownName "Solana account seed" refs.accountNames name

private def validatePdaDecl (refs : SolanaRefs) (knownValueNames : Array String)
    (_name : String) (seeds : Array SolanaSeed) (bump account : String) : Except String Unit := do
  validatePdaSeeds refs seeds
  requireKnownName "PDA bump" knownValueNames bump
  requireKnownName "Solana PDA account" refs.accountNames account

private def validatePdaDerive (refs : SolanaRefs) (knownValueNames : Array String)
    (name : String) (seeds : Array SolanaSeed) (bump account : String) (isSigner : Bool) :
    Except String Unit := do
  validatePdaDecl refs knownValueNames name seeds bump account
  let actual := s!"seeds={seedSignature seeds};bump={bump};account={account};signer={isSigner}"
  match findNamed? name refs.pdaItems pdaName? with
  | none => .error s!"unknown Learn Solana PDA `{name}`"
  | some item =>
      match pdaSignature? item with
      | some expected =>
          if expected == actual then
            .ok ()
          else
            .error s!"Learn Solana PDA derive `{name}` does not match declaration: expected {expected}, got {actual}"
      | none => .error s!"unknown Learn Solana PDA `{name}`"

private def validateCpiInvocation (refs : SolanaRefs) (stmt : Stmt) : Except String Unit := do
  match cpiInvocationName? stmt, cpiInvocationSignature? stmt with
  | some name, some actual =>
      match findNamed? name refs.cpiItems cpiName? with
      | none => .error s!"unknown Learn Solana CPI `{name}`"
      | some item =>
          match cpiSignature? item with
          | some expected =>
              if expected == actual then
                .ok ()
              else
                .error s!"Learn Solana CPI invoke `{name}` does not match declaration: expected {expected}, got {actual}"
          | none => .error s!"unknown Learn Solana CPI `{name}`"
  | _, _ => .ok ()

private def validateSolanaItemRefs (refs : SolanaRefs) (knownValueNames : Array String)
    (item : SolanaItem) : Except String Unit := do
  match item with
  | .pda name seeds bump account _ =>
      validatePdaDecl refs knownValueNames name seeds bump account
  | .systemTransfer _ fromAccount toAccount _ =>
      validateAccountMetas refs #[fromAccount, toAccount] #[fromAccount]
  | .systemCreateAccount _ payer newAccount _ _ _ =>
      validateAccountMetas refs #[payer, newAccount] #[payer, newAccount]
  | .splTokenTransferChecked _ source mint destination authority _ _ signerSeeds =>
      validateAccountMetas refs #[source, destination] <|
        if signerSeeds.isEmpty then #[authority] else #[]
      requireKnownAccounts refs #[mint, authority]
      validateSignerSeeds refs knownValueNames signerSeeds
  | .splTokenMintTo _ mint destination authority _ signerSeeds =>
      validateAccountMetas refs #[mint, destination] <|
        if signerSeeds.isEmpty then #[authority] else #[]
      requireKnownAccount refs authority
      validateSignerSeeds refs knownValueNames signerSeeds
  | .splTokenBurn _ source mint authority _ signerSeeds =>
      validateAccountMetas refs #[source, mint] <|
        if signerSeeds.isEmpty then #[authority] else #[]
      requireKnownAccount refs authority
      validateSignerSeeds refs knownValueNames signerSeeds
  | .splTokenApprove _ source delegate owner _ signerSeeds =>
      validateAccountMetas refs #[source] <|
        if signerSeeds.isEmpty then #[owner] else #[]
      requireKnownAccounts refs #[delegate, owner]
      validateSignerSeeds refs knownValueNames signerSeeds
  | .splTokenRevoke _ source owner signerSeeds =>
      validateAccountMetas refs #[source] <|
        if signerSeeds.isEmpty then #[owner] else #[]
      requireKnownAccount refs owner
      validateSignerSeeds refs knownValueNames signerSeeds
  | .splTokenCloseAccount _ account destination authority signerSeeds =>
      validateAccountMetas refs #[account, destination] <|
        if signerSeeds.isEmpty then #[authority] else #[]
      requireKnownAccount refs authority
      validateSignerSeeds refs knownValueNames signerSeeds
  | _ => pure ()

private def validateStmtRefs (refs : SolanaRefs) (stateNames : Array String)
    (env : LowerEnv) (stmt : Stmt) : Except String Unit := do
  let knownValueNames := stateNames ++ env.locals
  match stmt with
  | .solanaDerivePda name seeds bump account isSigner =>
      validatePdaDerive refs knownValueNames name seeds bump account isSigner
  | .solanaInvokeSystemTransfer _ _ _ lamportsSource =>
      validateCpiInvocation refs stmt
      requireKnownName "value" knownValueNames lamportsSource
  | .solanaInvokeSystemCreateAccount _ _ _ lamportsSource spaceSource _ =>
      validateCpiInvocation refs stmt
      requireKnownName "value" knownValueNames lamportsSource
      requireKnownName "value" knownValueNames spaceSource
  | .solanaInvokeSplTokenTransferChecked _ _ _ _ _ amountSource _ signerSeeds =>
      validateCpiInvocation refs stmt
      requireKnownName "value" knownValueNames amountSource
      validateSignerSeeds refs knownValueNames signerSeeds
  | .solanaInvokeSplTokenMintTo _ _ _ _ amountSource signerSeeds =>
      validateCpiInvocation refs stmt
      requireKnownName "value" knownValueNames amountSource
      validateSignerSeeds refs knownValueNames signerSeeds
  | .solanaInvokeSplTokenBurn _ _ _ _ amountSource signerSeeds =>
      validateCpiInvocation refs stmt
      requireKnownName "value" knownValueNames amountSource
      validateSignerSeeds refs knownValueNames signerSeeds
  | .solanaInvokeSplTokenApprove _ _ _ _ amountSource signerSeeds =>
      validateCpiInvocation refs stmt
      requireKnownName "value" knownValueNames amountSource
      validateSignerSeeds refs knownValueNames signerSeeds
  | .solanaInvokeSplTokenRevoke _ _ _ signerSeeds =>
      validateCpiInvocation refs stmt
      validateSignerSeeds refs knownValueNames signerSeeds
  | .solanaInvokeSplTokenCloseAccount _ _ _ _ signerSeeds =>
      validateCpiInvocation refs stmt
      validateSignerSeeds refs knownValueNames signerSeeds
  | .solanaSetReturnData _ sourceState _ =>
      requireKnownState stateNames sourceState
  | .solanaGetReturnData _ destinationState _ lengthState? programIdStates =>
      requireKnownState stateNames destinationState
      match lengthState? with
      | some lengthState => requireKnownState stateNames lengthState
      | none => pure ()
      requireKnownStateAll stateNames programIdStates
  | .solanaRemainingComputeUnits _ outputState =>
      requireKnownState stateNames outputState
  | .solanaLogAccountPubkey _ account =>
      requireStateOrAccount refs stateNames account
  | .solanaLogStateData _ sourceState _ =>
      requireKnownState stateNames sourceState
  | .solanaMemoryMemcpy _ dstState srcState _ =>
      requireKnownState stateNames dstState
      requireKnownState stateNames srcState
  | .solanaMemoryMemmove _ dstState srcState _ =>
      requireKnownState stateNames dstState
      requireKnownState stateNames srcState
  | .solanaMemoryMemcmp _ lhsState rhsState resultState _ =>
      requireKnownState stateNames lhsState
      requireKnownState stateNames rhsState
      requireKnownState stateNames resultState
  | .solanaMemoryMemset _ dstState _ _ =>
      requireKnownState stateNames dstState
  | .solanaCryptoHash _ _ inputState _ outputStates =>
      requireKnownState stateNames inputState
      requireKnownStateAll stateNames outputStates
  | .solanaSysvarRead _ _ _ outputState =>
      requireKnownState stateNames outputState
  | _ => pure ()

private def lowerExpr (env : LowerEnv) : Expr → Except String ProofForge.IR.Expr
  | .number value => .ok (.literal (.u64 value))
  | .name value =>
      if containsName env.stateNames value then
        .ok (.effect (.storageScalarRead value))
      else if containsName env.locals value then
        .ok (.local value)
      else
        .error s!"unknown Learn name `{value}`"
  | .call0 "checkpoint_id" => .ok (.effect (.contextRead .checkpointId))
  | .call0 other => .error s!"unsupported Learn zero-argument call `{other}`"
  | .binary op lhs rhs => do
      let lhs ← lowerExpr env lhs
      let rhs ← lowerExpr env rhs
      match op with
      | .add => .ok (.add lhs rhs)
      | .sub => .ok (.sub lhs rhs)
      | .mul => .ok (.mul lhs rhs)
      | .div => .ok (.div lhs rhs)

private def lowerSolanaSeed : SolanaSeed → String
  | .literal value => ProofForge.Solana.literalSeed value
  | .account name => ProofForge.Solana.accountSeed name

private def lowerSolanaSeeds (seeds : Array SolanaSeed) : Array String :=
  seeds.map lowerSolanaSeed

private def lowerSolanaSignerSeed : SolanaSignerSeed → String
  | .pda name => name
  | .bump name => name

private def lowerSolanaSignerSeeds (seeds : Array SolanaSignerSeed) : Array String :=
  seeds.map lowerSolanaSignerSeed

private def lowerSolanaItem (item : SolanaItem) :
    Except String (ProofForge.Contract.Builder.ModuleM Unit) := do
  match item with
  | .allocatorBump =>
      pure ProofForge.Solana.bumpAllocator
  | .account name access signerPolicy owner =>
      pure (ProofForge.Solana.accountConstraint name access signerPolicy owner)
  | .pda name seeds bump account isSigner =>
      pure (ProofForge.Solana.pdaAccount name (lowerSolanaSeeds seeds)
        (bump? := some bump) (account? := some account) (isSigner := isSigner))
  | .systemTransfer name fromAccount toAccount lamportsSource =>
      pure (ProofForge.Solana.systemTransfer name fromAccount toAccount lamportsSource)
  | .systemCreateAccount name payer newAccount lamportsSource spaceSource owner =>
      pure (ProofForge.Solana.systemCreateAccount name payer newAccount lamportsSource spaceSource owner)
  | .splTokenTransferChecked name source mint destination authority amountSource decimals signerSeeds =>
      pure (ProofForge.Solana.splTokenTransferChecked name source mint destination authority amountSource
        decimals (signerSeeds := lowerSolanaSignerSeeds signerSeeds))
  | .splTokenMintTo name mint destination authority amountSource signerSeeds =>
      pure (ProofForge.Solana.splTokenMintTo name mint destination authority amountSource
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds))
  | .splTokenBurn name source mint authority amountSource signerSeeds =>
      pure (ProofForge.Solana.splTokenBurn name source mint authority amountSource
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds))
  | .splTokenApprove name source delegate owner amountSource signerSeeds =>
      pure (ProofForge.Solana.splTokenApprove name source delegate owner amountSource
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds))
  | .splTokenRevoke name source owner signerSeeds =>
      pure (ProofForge.Solana.splTokenRevoke name source owner
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds))
  | .splTokenCloseAccount name account destination authority signerSeeds =>
      pure (ProofForge.Solana.splTokenCloseAccount name account destination authority
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds))

private def lowerStmtAction (refs : SolanaRefs) (stateNames : Array String)
    (state : ProofForge.Contract.Builder.EntryM Unit × LowerEnv) (stmt : Stmt) :
    Except String (ProofForge.Contract.Builder.EntryM Unit × LowerEnv) := do
  let (action, env) := state
  validateStmtRefs refs stateNames env stmt
  match stmt with
  | .letBind name type value =>
      let value ← lowerExpr env value
      let env := { env with locals := env.locals.push name }
      let stmtAction := ProofForge.Contract.Builder.letBind name type value
      .ok (action *> stmtAction, env)
  | .assign target value =>
      let value ← lowerExpr env value
      if containsName stateNames target then
        let stmtAction := ProofForge.Contract.Builder.effect
          (ProofForge.Contract.Builder.storageScalarWrite target value)
        .ok (action *> stmtAction, env)
      else if containsName env.locals target then
        let stmtAction := ProofForge.Contract.Builder.assign (.local target) value
        .ok (action *> stmtAction, env)
      else
        .error s!"cannot assign unknown Learn target `{target}`"
  | .emit eventName fields =>
      let mut lowered := #[]
      for field in fields do
        lowered := lowered.push (field.fst, (← lowerExpr env field.snd))
      let stmtAction := ProofForge.Contract.Builder.effect
        (ProofForge.Contract.Builder.eventEmit eventName lowered)
      .ok (action *> stmtAction, env)
  | .solanaDerivePda name seeds bump account isSigner =>
      let stmtAction := ProofForge.Solana.derivePda name (lowerSolanaSeeds seeds)
        (bump? := some bump) (account? := some account) (isSigner := isSigner)
      .ok (action *> stmtAction, env)
  | .solanaInvokeSystemTransfer name fromAccount toAccount lamportsSource =>
      let stmtAction := ProofForge.Solana.invokeSystemTransfer name fromAccount toAccount lamportsSource
      .ok (action *> stmtAction, env)
  | .solanaInvokeSystemCreateAccount name payer newAccount lamportsSource spaceSource owner =>
      let stmtAction := ProofForge.Solana.invokeSystemCreateAccount name payer newAccount
        lamportsSource spaceSource owner
      .ok (action *> stmtAction, env)
  | .solanaInvokeSplTokenTransferChecked name source mint destination authority amountSource decimals signerSeeds =>
      let stmtAction := ProofForge.Solana.invokeSplTokenTransferChecked name source mint destination authority
        amountSource decimals (signerSeeds := lowerSolanaSignerSeeds signerSeeds)
      .ok (action *> stmtAction, env)
  | .solanaInvokeSplTokenMintTo name mint destination authority amountSource signerSeeds =>
      let stmtAction := ProofForge.Solana.invokeSplTokenMintTo name mint destination authority amountSource
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds)
      .ok (action *> stmtAction, env)
  | .solanaInvokeSplTokenBurn name source mint authority amountSource signerSeeds =>
      let stmtAction := ProofForge.Solana.invokeSplTokenBurn name source mint authority amountSource
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds)
      .ok (action *> stmtAction, env)
  | .solanaInvokeSplTokenApprove name source delegate owner amountSource signerSeeds =>
      let stmtAction := ProofForge.Solana.invokeSplTokenApprove name source delegate owner amountSource
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds)
      .ok (action *> stmtAction, env)
  | .solanaInvokeSplTokenRevoke name source owner signerSeeds =>
      let stmtAction := ProofForge.Solana.invokeSplTokenRevoke name source owner
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds)
      .ok (action *> stmtAction, env)
  | .solanaInvokeSplTokenCloseAccount name account destination authority signerSeeds =>
      let stmtAction := ProofForge.Solana.invokeSplTokenCloseAccount name account destination authority
        (signerSeeds := lowerSolanaSignerSeeds signerSeeds)
      .ok (action *> stmtAction, env)
  | .solanaSetReturnData name sourceState bytes =>
      let stmtAction := ProofForge.Solana.setReturnDataFromState name sourceState bytes
      .ok (action *> stmtAction, env)
  | .solanaGetReturnData name destinationState maxBytes lengthState? programIdStates =>
      let stmtAction := ProofForge.Solana.getReturnDataToState name destinationState maxBytes
        (lengthState? := lengthState?) (programIdStates := programIdStates)
      .ok (action *> stmtAction, env)
  | .solanaRemainingComputeUnits name outputState =>
      let stmtAction := ProofForge.Solana.remainingComputeUnitsToState name outputState
      .ok (action *> stmtAction, env)
  | .solanaLogRemainingComputeUnits name =>
      let stmtAction := ProofForge.Solana.logRemainingComputeUnits name
      .ok (action *> stmtAction, env)
  | .solanaLogAccountPubkey name account =>
      let stmtAction := ProofForge.Solana.logAccountPubkey name account
      .ok (action *> stmtAction, env)
  | .solanaLogStateData name sourceState bytes =>
      let stmtAction := ProofForge.Solana.logStateData name sourceState bytes
      .ok (action *> stmtAction, env)
  | .solanaMemoryMemcpy name dstState srcState bytes =>
      let stmtAction := ProofForge.Solana.memcpyState name dstState srcState bytes
      .ok (action *> stmtAction, env)
  | .solanaMemoryMemmove name dstState srcState bytes =>
      let stmtAction := ProofForge.Solana.memmoveState name dstState srcState bytes
      .ok (action *> stmtAction, env)
  | .solanaMemoryMemcmp name lhsState rhsState resultState bytes =>
      let stmtAction := ProofForge.Solana.memcmpState name lhsState rhsState resultState bytes
      .ok (action *> stmtAction, env)
  | .solanaMemoryMemset name dstState value bytes =>
      let stmtAction := ProofForge.Solana.memsetState name dstState value bytes
      .ok (action *> stmtAction, env)
  | .solanaCryptoHash .sha256 name inputState bytes outputStates =>
      let stmtAction := ProofForge.Solana.sha256StateToStates name inputState bytes outputStates
      .ok (action *> stmtAction, env)
  | .solanaCryptoHash .keccak256 name inputState bytes outputStates =>
      let stmtAction := ProofForge.Solana.keccak256StateToStates name inputState bytes outputStates
      .ok (action *> stmtAction, env)
  | .solanaCryptoHash .blake3 name inputState bytes outputStates =>
      let stmtAction := ProofForge.Solana.blake3StateToStates name inputState bytes outputStates
      .ok (action *> stmtAction, env)
  | .solanaSysvarRead kind field name outputState =>
      let stmtAction := ProofForge.Solana.sysvarEntry {
        name := name
        kind := kind
        field := field
        outputState := outputState
      }
      .ok (action *> stmtAction, env)
  | .return value =>
      let value ← lowerExpr env value
      let stmtAction := ProofForge.Contract.Builder.ret value
      .ok (action *> stmtAction, env)

private def lowerMethodAction (refs : SolanaRefs) (stateNames bindingNames : Array String)
    (method : MethodDecl) :
    Except String (ProofForge.Contract.Builder.ModuleM Unit) := do
  let params := method.params.map (fun param => (param.name, param.type))
  let paramNames := method.params.map (fun param => param.name)
  let env : LowerEnv := { stateNames, locals := bindingNames ++ paramNames }
  let (bodyAction, _) ← method.body.foldlM (lowerStmtAction refs stateNames) (pure (), env)
  .ok (ProofForge.Contract.Builder.entryFull method.name method.selector? method.returns params
    (ProofForge.Contract.Builder.defaultParamEvmAbiWords params) bodyAction
    (match method.kind with
    | .entry => .call
    | .query => .view))

def lowerContract (decl : ContractDecl) : Except String ContractSpec := do
  let stateNames := decl.state.map (fun item => item.name)
  let bindingNames := decl.bindings.map (fun item => item.name)
  let refs := buildSolanaRefs decl.solanaItems
  let knownTopLevelValues := stateNames ++ bindingNames
  let mut action : ProofForge.Contract.Builder.ModuleM Unit := pure ()
  for state in decl.state do
    action := action *> ProofForge.Contract.Builder.scalarState state.name state.type
  for item in decl.solanaItems do
    validateSolanaItemRefs refs knownTopLevelValues item
    action := action *> (← lowerSolanaItem item)
  for method in decl.methods do
    action := action *> (← lowerMethodAction refs stateNames bindingNames method)
  .ok (ProofForge.Contract.Builder.build decl.name action)

def parseAndLower (source : String) : Except String ContractSpec := do
  lowerContract (← parseSource source)

def parseAndLowerFile (path : System.FilePath) : IO (Except String ContractSpec) := do
  pure <| parseAndLower (← IO.FS.readFile path)

end ProofForge.Contract.Learn
