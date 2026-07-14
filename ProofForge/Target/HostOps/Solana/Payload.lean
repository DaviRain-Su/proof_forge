import ProofForge.Target.Plan

/-! # Typed Solana Materialization Payloads

The common operation carrier knows only typed fields. This module owns the
Solana-specific schemas and their fail-closed decoders.
-/

namespace ProofForge.Target.HostOps.Solana.Payload

open ProofForge.Target

inductive AccountAccess where
  | readOnly
  | writable
  deriving BEq, DecidableEq, Repr

def AccountAccess.id : AccountAccess -> String
  | .readOnly => "readonly"
  | .writable => "writable"

def AccountAccess.ofId? : String -> Option AccountAccess
  | "readonly" => some .readOnly
  | "writable" => some .writable
  | _ => none

inductive SignerPolicy where
  | none
  | signer
  | pdaSigner
  deriving BEq, DecidableEq, Repr

def SignerPolicy.id : SignerPolicy -> String
  | .none => "none"
  | .signer => "signer"
  | .pdaSigner => "pda-signer"

def SignerPolicy.ofId? : String -> Option SignerPolicy
  | "none" => some .none
  | "signer" => some .signer
  | "pda-signer" => some .pdaSigner
  | _ => none

inductive PdaSeedKind where
  | literal
  | account
  | bump
  | instructionParam
  deriving BEq, DecidableEq, Repr

def PdaSeedKind.id : PdaSeedKind -> String
  | .literal => "literal"
  | .account => "account"
  | .bump => "bump"
  | .instructionParam => "instruction-param"

def PdaSeedKind.ofId? : String -> Option PdaSeedKind
  | "literal" => some .literal
  | "account" => some .account
  | "bump" => some .bump
  | "instruction-param" => some .instructionParam
  | _ => none

structure PdaSeed where
  kind : PdaSeedKind
  value : String
  deriving BEq, Repr

structure AccountSpec where
  name : String
  access : AccountAccess := .readOnly
  signer : SignerPolicy := .none
  owner : String := "program"
  deriving BEq, Repr

structure PdaSpec where
  name : String
  seeds : Array PdaSeed := #[]
  bump? : Option String := none
  account? : Option String := none
  signer : Bool := false
  deriving BEq, Repr

structure CpiAccountSpec where
  name : String
  access : AccountAccess := .readOnly
  signer : SignerPolicy := .none
  deriving BEq, Repr

inductive CpiArgumentKind where
  | lamportsSource
  | spaceSource
  | owner
  | amountSource
  | decimals
  | authorityType
  | newAuthority
  | memoSource
  | tokenProgram
  deriving BEq, DecidableEq, Repr

def CpiArgumentKind.id : CpiArgumentKind -> String
  | .lamportsSource => "lamports_source"
  | .spaceSource => "space_source"
  | .owner => "owner"
  | .amountSource => "amount_source"
  | .decimals => "decimals"
  | .authorityType => "authority_type"
  | .newAuthority => "new_authority"
  | .memoSource => "memo_source"
  | .tokenProgram => "token_program"

def CpiArgumentKind.ofId? : String -> Option CpiArgumentKind
  | "lamports_source" => some .lamportsSource
  | "space_source" => some .spaceSource
  | "owner" => some .owner
  | "amount_source" => some .amountSource
  | "decimals" => some .decimals
  | "authority_type" => some .authorityType
  | "new_authority" => some .newAuthority
  | "memo_source" => some .memoSource
  | "token_program" => some .tokenProgram
  | _ => none

structure CpiArgument where
  kind : CpiArgumentKind
  value : String
  deriving BEq, Repr

structure CpiSpec where
  name : String
  program : String
  instruction : String
  accounts : Array CpiAccountSpec := #[]
  signerSeeds : Array PdaSeed := #[]
  protocol? : Option String := none
  dataLayout? : Option String := none
  arguments : Array CpiArgument := #[]
  signed : Bool := false
  deriving BEq, Repr

inductive AllocatorKind where
  | bump
  | none
  deriving BEq, DecidableEq, Repr

def AllocatorKind.id : AllocatorKind -> String
  | .bump => "bump"
  | .none => "none"

def AllocatorKind.ofId? : String -> Option AllocatorKind
  | "bump" => some .bump
  | "none" => some .none
  | _ => none

structure AllocatorSpec where
  name : String := "runtime"
  kind : AllocatorKind := .bump
  heapStart : String := "0x300000000"
  heapBytes : Nat := 32768
  deriving BEq, Repr

structure AccountReallocSpec where
  name : String
  account : String
  newSize : Nat
  deriving BEq, Repr

structure TransferHookExtraAccountMetaSpec where
  name : String
  account : String
  extraAccounts : Array String
  deriving BEq, Repr

def pdaSeed (kind : PdaSeedKind) (value : String) : PdaSeed := { kind, value }

def accountSpec (name : String) (access : AccountAccess)
    (signerPolicy : SignerPolicy) (owner : String) : AccountSpec :=
  { name, access, signer := signerPolicy, owner }

def pdaSpec (name : String) (seeds : Array PdaSeed) (bump? account? : Option String)
    (isSigner : Bool) : PdaSpec :=
  { name, seeds, bump?, account?, signer := isSigner }

def cpiAccountSpec (name : String) (access : AccountAccess)
    (signerPolicy : SignerPolicy) : CpiAccountSpec :=
  { name, access, signer := signerPolicy }

def cpiArgument (kind : CpiArgumentKind) (value : String) : CpiArgument :=
  { kind, value }

def cpiSpec (name program instruction : String) (accounts : Array CpiAccountSpec)
    (signerSeeds : Array PdaSeed) (protocol? dataLayout? : Option String)
    (arguments : Array CpiArgument) (signed : Bool) : CpiSpec :=
  { name, program, instruction, accounts, signerSeeds, protocol?, dataLayout?, arguments, signed }

def allocatorSpec (name : String) (kind : AllocatorKind) (heapStart : String)
    (heapBytes : Nat) : AllocatorSpec :=
  { name, kind, heapStart, heapBytes }

def accountReallocSpec (name account : String) (newSize : Nat) : AccountReallocSpec :=
  { name, account, newSize }

def transferHookExtraAccountMetaSpec (name account : String)
    (extraAccounts : Array String) : TransferHookExtraAccountMetaSpec :=
  { name, account, extraAccounts }

inductive DecodeError where
  | malformedShape
  | missingField (name : String)
  | wrongFieldType (name : String)
  | invalidEnum (name value : String)
  | lengthMismatch (left right : String)
  | emptyIdentity (name : String)
  deriving BEq, Repr

private def field (name : String) (value : OperationPayloadValue) : OperationPayloadField :=
  { name, value }

private def requireShape (payload : OperationPayload) (names : Array String) :
    Except DecodeError Unit := do
  unless payload.wellFormed && payload.size == names.size &&
      names.all (fun name => (payload.value? name).isSome) do
    throw .malformedShape

private def textField (payload : OperationPayload) (name : String) :
    Except DecodeError String :=
  match payload.value? name with
  | some (.text value) => .ok value
  | some _ => .error (.wrongFieldType name)
  | none => .error (.missingField name)

private def textsField (payload : OperationPayload) (name : String) :
    Except DecodeError (Array String) :=
  match payload.value? name with
  | some (.texts values) => .ok values
  | some _ => .error (.wrongFieldType name)
  | none => .error (.missingField name)

private def flagField (payload : OperationPayload) (name : String) :
    Except DecodeError Bool :=
  match payload.value? name with
  | some (.flag value) => .ok value
  | some _ => .error (.wrongFieldType name)
  | none => .error (.missingField name)

private def naturalField (payload : OperationPayload) (name : String) :
    Except DecodeError Nat :=
  match payload.value? name with
  | some (.natural value) => .ok value
  | some _ => .error (.wrongFieldType name)
  | none => .error (.missingField name)

private def optionalTextField (payload : OperationPayload) (name : String) :
    Except DecodeError (Option String) :=
  match payload.value? name with
  | some (.optionalText value) => .ok value
  | some _ => .error (.wrongFieldType name)
  | none => .error (.missingField name)

private def accountAccessField (payload : OperationPayload) (name : String) :
    Except DecodeError AccountAccess := do
  let value ← textField payload name
  match AccountAccess.ofId? value with
  | some access => pure access
  | none => throw (.invalidEnum name value)

private def signerPolicyField (payload : OperationPayload) (name : String) :
    Except DecodeError SignerPolicy := do
  let value ← textField payload name
  match SignerPolicy.ofId? value with
  | some policy => pure policy
  | none => throw (.invalidEnum name value)

private def seedKinds (values : Array String) : Except DecodeError (Array PdaSeedKind) :=
  values.mapM fun value =>
    match PdaSeedKind.ofId? value with
    | some kind => pure kind
    | none => throw (.invalidEnum "seedKinds" value)

private def decodeSeeds (kinds values : Array String) : Except DecodeError (Array PdaSeed) := do
  unless kinds.size == values.size do
    throw (.lengthMismatch "seedKinds" "seedValues")
  let kinds ← seedKinds kinds
  return kinds.zip values |>.map fun pair => { kind := pair.1, value := pair.2 }

private def decodeArguments (kinds values : Array String) :
    Except DecodeError (Array CpiArgument) := do
  unless kinds.size == values.size do
    throw (.lengthMismatch "argumentKinds" "argumentValues")
  let mut seen : Array CpiArgumentKind := #[]
  let mut arguments := #[]
  for index in [0:kinds.size] do
    let kind ← match CpiArgumentKind.ofId? kinds[index]! with
      | some kind => pure kind
      | none => throw (.invalidEnum "argumentKinds" kinds[index]!)
    if seen.contains kind then
      throw (.invalidEnum "argumentKinds" s!"duplicate:{kind.id}")
    if values[index]!.isEmpty then
      throw (.emptyIdentity "argumentValues")
    seen := seen.push kind
    arguments := arguments.push { kind, value := values[index]! }
  return arguments

def AccountSpec.encode (spec : AccountSpec) : OperationPayload := #[
  field "name" (.text spec.name),
  field "access" (.text spec.access.id),
  field "signer" (.text spec.signer.id),
  field "owner" (.text spec.owner)
]

def AccountSpec.decode (payload : OperationPayload) : Except DecodeError AccountSpec := do
  requireShape payload #["name", "access", "signer", "owner"]
  let name ← textField payload "name"
  let owner ← textField payload "owner"
  if name.isEmpty then throw (.emptyIdentity "name")
  if owner.isEmpty then throw (.emptyIdentity "owner")
  return {
    name
    access := ← accountAccessField payload "access"
    signer := ← signerPolicyField payload "signer"
    owner
  }

def PdaSpec.encode (spec : PdaSpec) : OperationPayload := #[
  field "name" (.text spec.name),
  field "seedKinds" (.texts (spec.seeds.map (·.kind.id))),
  field "seedValues" (.texts (spec.seeds.map (·.value))),
  field "bump" (.optionalText spec.bump?),
  field "account" (.optionalText spec.account?),
  field "signer" (.flag spec.signer)
]

def PdaSpec.decode (payload : OperationPayload) : Except DecodeError PdaSpec := do
  requireShape payload #["name", "seedKinds", "seedValues", "bump", "account", "signer"]
  let name ← textField payload "name"
  if name.isEmpty then throw (.emptyIdentity "name")
  return {
    name
    seeds := ← decodeSeeds (← textsField payload "seedKinds") (← textsField payload "seedValues")
    bump? := ← optionalTextField payload "bump"
    account? := ← optionalTextField payload "account"
    signer := ← flagField payload "signer"
  }

def CpiSpec.encode (spec : CpiSpec) : OperationPayload := #[
  field "name" (.text spec.name),
  field "program" (.text spec.program),
  field "instruction" (.text spec.instruction),
  field "accountNames" (.texts (spec.accounts.map (·.name))),
  field "accountAccesses" (.texts (spec.accounts.map (·.access.id))),
  field "accountSigners" (.texts (spec.accounts.map (·.signer.id))),
  field "signerSeedKinds" (.texts (spec.signerSeeds.map (·.kind.id))),
  field "signerSeedValues" (.texts (spec.signerSeeds.map (·.value))),
  field "protocol" (.optionalText spec.protocol?),
  field "dataLayout" (.optionalText spec.dataLayout?),
  field "argumentKinds" (.texts (spec.arguments.map (·.kind.id))),
  field "argumentValues" (.texts (spec.arguments.map (·.value))),
  field "signed" (.flag spec.signed)
]

def CpiSpec.decode (payload : OperationPayload) : Except DecodeError CpiSpec := do
  requireShape payload #["name", "program", "instruction", "accountNames",
    "accountAccesses", "accountSigners", "signerSeedKinds", "signerSeedValues",
    "protocol", "dataLayout", "argumentKinds", "argumentValues", "signed"]
  let name ← textField payload "name"
  let program ← textField payload "program"
  let instruction ← textField payload "instruction"
  if name.isEmpty then throw (.emptyIdentity "name")
  if program.isEmpty then throw (.emptyIdentity "program")
  if instruction.isEmpty then throw (.emptyIdentity "instruction")
  let accountNames ← textsField payload "accountNames"
  let accountAccesses ← textsField payload "accountAccesses"
  let accountSigners ← textsField payload "accountSigners"
  unless accountNames.size == accountAccesses.size do
    throw (.lengthMismatch "accountNames" "accountAccesses")
  unless accountNames.size == accountSigners.size do
    throw (.lengthMismatch "accountNames" "accountSigners")
  let mut accounts := #[]
  for index in [0:accountNames.size] do
    let access ← match AccountAccess.ofId? accountAccesses[index]! with
      | some access => pure access
      | none => throw (.invalidEnum "accountAccesses" accountAccesses[index]!)
    let signerPolicy ← match SignerPolicy.ofId? accountSigners[index]! with
      | some policy => pure policy
      | none => throw (.invalidEnum "accountSigners" accountSigners[index]!)
    if accountNames[index]!.isEmpty then throw (.emptyIdentity "accountNames")
    accounts := accounts.push { name := accountNames[index]!, access, signer := signerPolicy }
  return {
    name
    program
    instruction
    accounts
    signerSeeds := ← decodeSeeds
      (← textsField payload "signerSeedKinds") (← textsField payload "signerSeedValues")
    protocol? := ← optionalTextField payload "protocol"
    dataLayout? := ← optionalTextField payload "dataLayout"
    arguments := ← decodeArguments
      (← textsField payload "argumentKinds") (← textsField payload "argumentValues")
    signed := ← flagField payload "signed"
  }

def AllocatorSpec.encode (spec : AllocatorSpec) : OperationPayload := #[
  field "name" (.text spec.name),
  field "kind" (.text spec.kind.id),
  field "heapStart" (.text spec.heapStart),
  field "heapBytes" (.natural spec.heapBytes)
]

def AllocatorSpec.decode (payload : OperationPayload) : Except DecodeError AllocatorSpec := do
  requireShape payload #["name", "kind", "heapStart", "heapBytes"]
  let name ← textField payload "name"
  let heapStart ← textField payload "heapStart"
  let kindValue ← textField payload "kind"
  if name.isEmpty then throw (.emptyIdentity "name")
  if heapStart.isEmpty then throw (.emptyIdentity "heapStart")
  let kind ← match AllocatorKind.ofId? kindValue with
    | some kind => pure kind
    | none => throw (.invalidEnum "kind" kindValue)
  return { name, kind, heapStart, heapBytes := ← naturalField payload "heapBytes" }

def AccountReallocSpec.encode (spec : AccountReallocSpec) : OperationPayload := #[
  field "name" (.text spec.name),
  field "account" (.text spec.account),
  field "newSize" (.natural spec.newSize)
]

def AccountReallocSpec.decode (payload : OperationPayload) :
    Except DecodeError AccountReallocSpec := do
  requireShape payload #["name", "account", "newSize"]
  let name ← textField payload "name"
  let account ← textField payload "account"
  if name.isEmpty then throw (.emptyIdentity "name")
  if account.isEmpty then throw (.emptyIdentity "account")
  return { name, account, newSize := ← naturalField payload "newSize" }

def TransferHookExtraAccountMetaSpec.encode
    (spec : TransferHookExtraAccountMetaSpec) : OperationPayload := #[
  field "name" (.text spec.name),
  field "account" (.text spec.account),
  field "extraAccounts" (.texts spec.extraAccounts)
]

def TransferHookExtraAccountMetaSpec.decode (payload : OperationPayload) :
    Except DecodeError TransferHookExtraAccountMetaSpec := do
  requireShape payload #["name", "account", "extraAccounts"]
  let name ← textField payload "name"
  let account ← textField payload "account"
  let extraAccounts ← textsField payload "extraAccounts"
  if name.isEmpty then throw (.emptyIdentity "name")
  if account.isEmpty then throw (.emptyIdentity "account")
  if extraAccounts.any String.isEmpty then throw (.emptyIdentity "extraAccounts")
  return { name, account, extraAccounts }

end ProofForge.Target.HostOps.Solana.Payload
