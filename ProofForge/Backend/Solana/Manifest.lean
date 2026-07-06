/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana Instruction Manifest

Generate the `manifest.toml` sidecar that describes instruction dispatch tags
and account constraints for the `solana-sbpf-asm` target.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

import ProofForge.IR.Contract
import ProofForge.Target.Plan
import ProofForge.Backend.Solana.Extension

namespace ProofForge.Backend.Solana.Manifest

open ProofForge.IR
open ProofForge.Backend.Solana.Extension

/-- A single account entry in the instruction manifest. -/
structure AccountEntry where
  name : String
  index : Nat
  signer : Bool
  writable : Bool
  owner : String
  deriving Repr, Inhabited

/-- A scalar instruction parameter in the Solana instruction-data ABI.
Offset is relative to the start of `instruction_data`; byte 0 is reserved for
the ProofForge entrypoint tag. -/
structure InstructionParamEntry where
  name : String
  typeName : String
  offset : Nat
  byteSize : Nat
  encoding : String
  deriving Repr, Inhabited

def stripHexPrefix (value : String) : String :=
  if value.startsWith "0x" || value.startsWith "0X" then
    (value.drop 2).toString
  else
    value

def hexValue? : Char → Option Nat
  | '0' => some 0
  | '1' => some 1
  | '2' => some 2
  | '3' => some 3
  | '4' => some 4
  | '5' => some 5
  | '6' => some 6
  | '7' => some 7
  | '8' => some 8
  | '9' => some 9
  | 'a' | 'A' => some 10
  | 'b' | 'B' => some 11
  | 'c' | 'C' => some 12
  | 'd' | 'D' => some 13
  | 'e' | 'E' => some 14
  | 'f' | 'F' => some 15
  | _ => none

partial def parseHexBytePairs : List Char → Option (Array Nat)
  | [] => some #[]
  | hi :: lo :: rest => do
      let hi ← hexValue? hi
      let lo ← hexValue? lo
      let tail ← parseHexBytePairs rest
      some (#[hi * 16 + lo] ++ tail)
  | _ => none

def externalDiscriminatorBytes? (entrypoint : Entrypoint) : Option (Array Nat) := do
  let selector ← entrypoint.selector?
  let hex := stripHexPrefix selector
  if hex.length == 16 then
    parseHexBytePairs hex.toList
  else
    none

def entrypointDiscriminatorSize (entrypoint : Entrypoint) : Nat :=
  match externalDiscriminatorBytes? entrypoint with
  | some bytes => bytes.size
  | none => 1

/-- One instruction table entry. -/
structure InstructionEntry where
  name : String
  tag : Nat
  handler : String
  accounts : Array AccountEntry
  params : Array InstructionParamEntry := #[]
  minDataLen : Nat := 1
  deriving Repr, Inhabited

def AccountEntry.render (a : AccountEntry) : String :=
  "  { name = \"" ++ a.name ++ "\", index = " ++ toString a.index ++
  ", signer = " ++ toString a.signer ++ ", writable = " ++ toString a.writable ++
  ", owner = \"" ++ a.owner ++ "\" }"

def tomlString (value : String) : String :=
  let escapeChar : Char → String
    | '"' => "\\\""
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | ch => ch.toString
  "\"" ++ String.intercalate "" (value.toList.map escapeChar) ++ "\""

def instructionParamByteSize? : ValueType → Option Nat
  | .u64 => some 8
  | .u32 => some 4
  | .bool => some 1
  | _ => none

def instructionParamEncoding : ValueType → String
  | .u64 => "le-u64"
  | .u32 => "le-u32"
  | .bool => "u8-bool"
  | _ => "unsupported"

def buildInstructionParams (ep : Entrypoint) : Array InstructionParamEntry := Id.run do
  let mut params := #[]
  let mut payloadOff := entrypointDiscriminatorSize ep
  for param in ep.params do
    let (name, type) := param
    let byteSize := (instructionParamByteSize? type).getD 0
    params := params.push {
      name := name
      typeName := type.name
      offset := payloadOff
      byteSize := byteSize
      encoding := instructionParamEncoding type
    }
    payloadOff := payloadOff + byteSize
  return params

def instructionParamPayloadSize (ep : Entrypoint) : Nat :=
  (buildInstructionParams ep).foldl (fun acc param => acc + param.byteSize) 0

def instructionDataMinLen (ep : Entrypoint) : Nat :=
  entrypointDiscriminatorSize ep + instructionParamPayloadSize ep

def InstructionParamEntry.render (param : InstructionParamEntry) : String :=
  "  { name = " ++ tomlString param.name ++
  ", type = " ++ tomlString param.typeName ++
  ", offset = " ++ toString param.offset ++
  ", byte_size = " ++ toString param.byteSize ++
  ", encoding = " ++ tomlString param.encoding ++ " }"

def InstructionEntry.render (ie : InstructionEntry) : String :=
  let accountLines := ie.accounts.mapIdx fun idx account =>
    AccountEntry.render account ++
      (if idx + 1 == ie.accounts.size then "" else ",")
  let accountsBlock :=
    if accountLines.isEmpty then "accounts = []"
    else "accounts = [\n" ++ String.intercalate "\n" accountLines.toList ++ "\n]"
  let paramLines := ie.params.mapIdx fun idx param =>
    InstructionParamEntry.render param ++
      (if idx + 1 == ie.params.size then "" else ",")
  let paramsBlock :=
    if paramLines.isEmpty then "params = []"
    else "params = [\n" ++ String.intercalate "\n" paramLines.toList ++ "\n]"
  "[[instruction]]\n" ++
  "name = \"" ++ ie.name ++ "\"\n" ++
  "tag = " ++ toString ie.tag ++ "\n" ++
  "handler = \"" ++ ie.handler ++ "\"\n" ++
  "min_data_len = " ++ toString ie.minDataLen ++ "\n" ++
  accountsBlock ++ "\n" ++
  paramsBlock

def defaultStateAccountName (module : Module) : String :=
  match module.state[0]? with
  | some state => state.id
  | none => "data"

def defaultStateAccount (module : Module) : AccountEntry := {
  name := defaultStateAccountName module
  index := 0
  signer := false
  writable := true
  owner := "program"
}

/-- Default account schema for portable IR modules that actually carry state:
state lives in account 0. Stateless Solana SDK programs can use only their
declared target accounts, which is required for callbacks with fixed ABIs. -/
def buildDefaultAccounts (module : Module) : Array AccountEntry :=
  if module.state.isEmpty then
    #[]
  else
    #[defaultStateAccount module]

def mergeOwner (existing incoming : String) : String :=
  if existing == incoming then
    existing
  else if existing == "any" then
    incoming
  else if incoming == "any" then
    existing
  else
    existing

def AccountEntry.merge (existing incoming : AccountEntry) : AccountEntry := {
  existing with
  signer := existing.signer || incoming.signer
  writable := existing.writable || incoming.writable
  owner := mergeOwner existing.owner incoming.owner
}

def pushAccount (accounts : Array AccountEntry) (account : AccountEntry) : Array AccountEntry :=
  if accounts.any (fun existing => existing.name == account.name) then
    accounts.map fun existing =>
      if existing.name == account.name then
        existing.merge account
      else
        existing
  else
    accounts.push { account with index := accounts.size }

def accountByName? (accounts : Array AccountEntry) (name : String) : Option AccountEntry :=
  accounts.find? (fun account => account.name == name)

def reindexAccounts (accounts : Array AccountEntry) : Array AccountEntry :=
  accounts.mapIdx fun idx account => { account with index := idx }

def applyAccountOrder (order : Array String) (accounts : Array AccountEntry) :
    Array AccountEntry :=
  if order.isEmpty then
    accounts
  else
    let ordered :=
      order.foldl
        (fun acc name =>
          if acc.any (fun account => account.name == name) then
            acc
          else
            match accountByName? accounts name with
            | some account => acc.push account
            | none => acc)
        #[]
    let merged :=
      accounts.foldl
        (fun acc account =>
          if acc.any (fun existing => existing.name == account.name) then
            acc
          else
            acc.push account)
        ordered
    reindexAccounts merged

def pdaInstructionAccount (pda : PdaDerive) : AccountEntry := {
  name := pda.account?.getD pda.name
  index := 0
  signer := false
  writable := true
  owner := "program"
}

def pdaSeedAccount (name : String) : AccountEntry := {
  name
  index := 0
  signer := false
  writable := false
  owner := "any"
}

def cpiInstructionSigner (account : AccountMeta) : Bool :=
  account.signer == "signer"

def cpiInstructionAccount (account : AccountMeta) : AccountEntry := {
  name := account.name
  index := 0
  signer := cpiInstructionSigner account
  writable := account.access == "writable"
  owner := "any"
}

def cpiProgramAccount (cpi : CpiInvoke) : AccountEntry := {
  name := cpi.program
  index := 0
  signer := false
  writable := false
  owner := "executable"
}

def cpiProgramAccountRequired (cpi : CpiInvoke) : Bool :=
  metadataValue? cpi.metadata "solana.cpi.require_program_account" != some "false"

def declaredInstructionSigner (account : DeclaredAccount) : Bool :=
  account.signer == "signer"

def declaredInstructionAccount (account : DeclaredAccount) : AccountEntry := {
  name := account.name
  index := 0
  signer := declaredInstructionSigner account
  writable := account.access == "writable"
  owner := account.owner
}

def pubkeyLogAccount (action : PubkeyLogAction) : AccountEntry := {
  name := action.account
  index := 0
  signer := false
  writable := false
  owner := "any"
}

def accountReallocAccount (action : AccountReallocAction) : AccountEntry := {
  name := action.account
  index := 0
  signer := false
  writable := true
  owner := "program"
}

def pdaByName? (extensions : ProgramExtensions) (name : String) : Option PdaDerive :=
  extensions.pdas.find? (fun pda => pda.name == name)

def cpiByName? (extensions : ProgramExtensions) (name : String) : Option CpiInvoke :=
  extensions.cpis.find? (fun cpi => cpi.name == name)

def pushEntrypointPdaAccounts (extensions : ProgramExtensions) (entrypoint : String)
    (accounts : Array AccountEntry) : Array AccountEntry :=
  extensions.pdaActions.foldl
    (fun accounts action =>
      if action.entrypoint == entrypoint then
        match pdaByName? extensions action.name with
        | some pda => pushAccount accounts (pdaInstructionAccount pda)
        | none => accounts
      else
        accounts)
    accounts

def pushPdaSeedAccounts (accounts : Array AccountEntry) (pda : PdaDerive) : Array AccountEntry :=
  pda.explicitSeeds.foldl
    (fun accounts seed =>
      match seed.kind with
      | .account => pushAccount accounts (pdaSeedAccount seed.value)
      | _ => accounts)
    accounts

def pushEntrypointPdaSeedAccounts (extensions : ProgramExtensions) (entrypoint : String)
    (accounts : Array AccountEntry) : Array AccountEntry :=
  extensions.pdaActions.foldl
    (fun accounts action =>
      if action.entrypoint == entrypoint then
        match pdaByName? extensions action.name with
        | some pda => pushPdaSeedAccounts accounts pda
        | none => accounts
      else
        accounts)
    accounts

def pushEntrypointCpiAccounts (extensions : ProgramExtensions) (entrypoint : String)
    (accounts : Array AccountEntry) : Array AccountEntry :=
  extensions.cpiActions.foldl
    (fun accounts action =>
      if action.entrypoint == entrypoint then
        match cpiByName? extensions action.name with
        | some cpi =>
            let accounts :=
              cpi.accounts.foldl
                (fun accounts account => pushAccount accounts (cpiInstructionAccount account))
                accounts
            if cpiProgramAccountRequired cpi then
              pushAccount accounts (cpiProgramAccount cpi)
            else
              accounts
        | none => accounts
      else
        accounts)
    accounts

def pushEntrypointPubkeyLogAccounts (extensions : ProgramExtensions) (entrypoint : String)
    (accounts : Array AccountEntry) : Array AccountEntry :=
  extensions.pubkeyLogActions.foldl
    (fun accounts action =>
      if action.entrypoint == entrypoint && !action.account.isEmpty then
        pushAccount accounts (pubkeyLogAccount action)
      else
        accounts)
    accounts

def pushEntrypointAccountReallocAccounts (extensions : ProgramExtensions) (entrypoint : String)
    (accounts : Array AccountEntry) : Array AccountEntry :=
  extensions.accountReallocActions.foldl
    (fun accounts action =>
      if action.entrypoint == entrypoint && !action.account.isEmpty then
        pushAccount accounts (accountReallocAccount action)
      else
        accounts)
    accounts

def pushDeclaredAccounts (accounts : Array AccountEntry)
    (declaredAccounts : Array DeclaredAccount) : Array AccountEntry :=
  declaredAccounts.foldl
    (fun accounts account => pushAccount accounts (declaredInstructionAccount account))
    accounts

def pushCpiAccounts (accounts : Array AccountEntry) (cpi : CpiInvoke) : Array AccountEntry :=
  let accounts :=
    cpi.accounts.foldl
      (fun accounts account => pushAccount accounts (cpiInstructionAccount account))
      accounts
  if cpiProgramAccountRequired cpi then
    pushAccount accounts (cpiProgramAccount cpi)
  else
    accounts

def buildInstructionAccounts (module : Module) (extensions : ProgramExtensions)
    (entrypoint : String) : Array AccountEntry :=
  let accounts := buildDefaultAccounts module
  let accounts := pushEntrypointPdaAccounts extensions entrypoint accounts
  let accounts := pushEntrypointCpiAccounts extensions entrypoint accounts
  let accounts := pushEntrypointPubkeyLogAccounts extensions entrypoint accounts
  let accounts := pushEntrypointAccountReallocAccounts extensions entrypoint accounts
  let accounts := pushEntrypointPdaSeedAccounts extensions entrypoint accounts
  let accounts := pushDeclaredAccounts accounts extensions.accounts
  applyAccountOrder extensions.accountOrder accounts

def alignInstructionAccountsWithModuleOrder
    (moduleAccounts instructionAccounts : Array AccountEntry) : Array AccountEntry :=
  moduleAccounts.map fun moduleAccount =>
    match accountByName? instructionAccounts moduleAccount.name with
    | some instructionAccount => { instructionAccount with index := moduleAccount.index }
    | none => moduleAccount

def buildEntrypointAccounts (module : Module) (extensions : ProgramExtensions)
    (moduleAccounts : Array AccountEntry) (entrypoint : String) : Array AccountEntry :=
  alignInstructionAccountsWithModuleOrder moduleAccounts
    (buildInstructionAccounts module extensions entrypoint)

def buildModuleAccounts (module : Module) (extensions : ProgramExtensions) : Array AccountEntry :=
  let accounts := buildDefaultAccounts module
  let accounts :=
    extensions.pdas.foldl
      (fun accounts pda => pushAccount accounts (pdaInstructionAccount pda))
      accounts
  let accounts := extensions.cpis.foldl pushCpiAccounts accounts
  let accounts := extensions.pubkeyLogActions.foldl
    (fun accounts action =>
      if action.account.isEmpty then accounts else pushAccount accounts (pubkeyLogAccount action))
    accounts
  let accounts := extensions.accountReallocActions.foldl
    (fun accounts action =>
      if action.account.isEmpty then accounts else pushAccount accounts (accountReallocAccount action))
    accounts
  let accounts := extensions.pdas.foldl pushPdaSeedAccounts accounts
  let accounts := pushDeclaredAccounts accounts extensions.accounts
  applyAccountOrder extensions.accountOrder accounts

def tomlBool (value : Bool) : String :=
  if value then "true" else "false"

def tomlStringArray (values : Array String) : String :=
  "[" ++ String.intercalate ", " (values.toList.map tomlString) ++ "]"

def renderPdaSeed (seed : PdaSeed) : String :=
  "  { kind = " ++ tomlString seed.kind.id ++
  ", value = " ++ tomlString seed.value ++ " }"

def renderPdaSeeds (seeds : Array PdaSeed) : String :=
  if seeds.isEmpty then
    "[]"
  else
    "[\n" ++ String.intercalate ",\n" (seeds.toList.map renderPdaSeed) ++ "\n]"

def renderExtensionAccount (account : AccountMeta) : String :=
  "  { name = " ++ tomlString account.name ++
  ", access = " ++ tomlString account.access ++
  ", signer = " ++ tomlString account.signer ++ " }"

def renderCpiMetadataField (cpi : CpiInvoke) (metadataKey tomlKey : String) : String :=
  match metadataValue? cpi.metadata metadataKey with
  | some value => s!"{tomlKey} = {tomlString value}\n"
  | none => ""

def renderAllocator (allocator : RuntimeAllocator) : String :=
  "[[solana.allocator]]\n" ++
  "name = " ++ tomlString allocator.name ++ "\n" ++
  "kind = " ++ tomlString allocator.kind ++ "\n" ++
  "model = " ++ tomlString allocator.model ++ "\n" ++
  "heap_start = " ++ tomlString allocator.heapStart ++ "\n" ++
  "heap_bytes = " ++ allocator.heapBytes ++ "\n"

def renderAccountOrder (names : Array String) : String :=
  if names.isEmpty then
    ""
  else
    "[solana.account_order]\n" ++
    "names = " ++ tomlStringArray names ++ "\n"

def renderDeclaredAccount (account : DeclaredAccount) : String :=
  "[[solana.account]]\n" ++
  "name = " ++ tomlString account.name ++ "\n" ++
  "access = " ++ tomlString account.access ++ "\n" ++
  "signer = " ++ tomlString account.signer ++ "\n" ++
  "owner = " ++ tomlString account.owner ++ "\n"

def renderPda (pda : PdaDerive) : String :=
  let optionalFields :=
    (match pda.bump? with
    | some bump => s!"bump = {tomlString bump}\n"
    | none => "") ++
    (match pda.account? with
    | some account => s!"account = {tomlString account}\n"
    | none => "")
  "[[solana.pda]]\n" ++
  "name = " ++ tomlString pda.name ++ "\n" ++
  "seeds = " ++ tomlStringArray pda.seedValues ++ "\n" ++
  "typed_seeds = " ++ renderPdaSeeds pda.effectiveSeeds ++ "\n" ++
  optionalFields ++
  "signer = " ++ tomlBool pda.signer ++ "\n"

def renderCpi (cpi : CpiInvoke) : String :=
  let accountLines := cpi.accounts.mapIdx fun idx account =>
    renderExtensionAccount account ++
      (if idx + 1 == cpi.accounts.size then "" else ",")
  let accountsBlock :=
    if accountLines.isEmpty then
      "accounts = []"
    else
      "accounts = [\n" ++ String.intercalate "\n" accountLines.toList ++ "\n]"
  let optionalFields :=
    (match cpi.protocol? with
    | some protocol => s!"protocol = {tomlString protocol}\n"
    | none => "") ++
    (match cpi.dataLayout? with
    | some dataLayout => s!"data_layout = {tomlString dataLayout}\n"
    | none => "") ++
    renderCpiMetadataField cpi "solana.cpi.lamports_source" "lamports_source" ++
    renderCpiMetadataField cpi "solana.cpi.space_source" "space_source" ++
    renderCpiMetadataField cpi "solana.cpi.owner" "owner_source" ++
    renderCpiMetadataField cpi "solana.cpi.amount_source" "amount_source" ++
    renderCpiMetadataField cpi "solana.cpi.fee_source" "fee_source" ++
    renderCpiMetadataField cpi "solana.cpi.decimals" "decimals" ++
    renderCpiMetadataField cpi "solana.cpi.authority_type" "authority_type" ++
    renderCpiMetadataField cpi "solana.cpi.new_authority" "new_authority" ++
    renderCpiMetadataField cpi "solana.cpi.token_program" "token_program" ++
    renderCpiMetadataField cpi "solana.cpi.transfer_fee_config_authority" "transfer_fee_config_authority" ++
    renderCpiMetadataField cpi "solana.cpi.withdraw_withheld_authority" "withdraw_withheld_authority" ++
    renderCpiMetadataField cpi "solana.cpi.transfer_fee_basis_points" "transfer_fee_basis_points" ++
    renderCpiMetadataField cpi "solana.cpi.maximum_fee" "maximum_fee" ++
    renderCpiMetadataField cpi "solana.cpi.num_token_accounts" "num_token_accounts" ++
    renderCpiMetadataField cpi "solana.cpi.memo_source" "memo_source" ++
    renderCpiMetadataField cpi "solana.cpi.metadata_pointer_authority" "metadata_pointer_authority" ++
    renderCpiMetadataField cpi "solana.cpi.metadata_address" "metadata_address" ++
    renderCpiMetadataField cpi "solana.cpi.default_account_state" "default_account_state" ++
    renderCpiMetadataField cpi "solana.cpi.permanent_delegate" "permanent_delegate" ++
    renderCpiMetadataField cpi "solana.cpi.interest_rate_authority" "interest_rate_authority" ++
    renderCpiMetadataField cpi "solana.cpi.interest_rate" "interest_rate" ++
    renderCpiMetadataField cpi "solana.cpi.memo_transfer_required" "memo_transfer_required" ++
    renderCpiMetadataField cpi "solana.cpi.transfer_hook_authority" "transfer_hook_authority" ++
    renderCpiMetadataField cpi "solana.cpi.transfer_hook_program" "transfer_hook_program" ++
    renderCpiMetadataField cpi "solana.cpi.pausable_authority" "pausable_authority" ++
    renderCpiMetadataField cpi "solana.cpi.require_program_account" "require_program_account"
  "[[solana.cpi]]\n" ++
  "name = " ++ tomlString cpi.name ++ "\n" ++
  "program = " ++ tomlString cpi.program ++ "\n" ++
  "instruction = " ++ tomlString cpi.instruction ++ "\n" ++
  "signed = " ++ tomlBool cpi.signed ++ "\n" ++
  accountsBlock ++ "\n" ++
  "signer_seeds = " ++ tomlStringArray cpi.signerSeeds ++ "\n" ++
  optionalFields

def renderPdaAction (action : PdaAction) : String :=
  "[[solana.entrypoint_pda]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "pda = " ++ tomlString action.name ++ "\n"

def renderCpiAction (action : CpiAction) : String :=
  "[[solana.entrypoint_cpi]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "cpi = " ++ tomlString action.name ++ "\n"

def renderMemoryAction (action : MemoryAction) : String :=
  let optionalFields :=
    (match action.dstState? with
    | some state => s!"dst_state = {tomlString state}\n"
    | none => "") ++
    (match action.srcState? with
    | some state => s!"src_state = {tomlString state}\n"
    | none => "") ++
    (match action.lhsState? with
    | some state => s!"lhs_state = {tomlString state}\n"
    | none => "") ++
    (match action.rhsState? with
    | some state => s!"rhs_state = {tomlString state}\n"
    | none => "") ++
    (match action.resultState? with
    | some state => s!"result_state = {tomlString state}\n"
    | none => "") ++
    (match action.value? with
    | some value => s!"value = {value}\n"
    | none => "")
  "[[solana.entrypoint_memory]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "memory = " ++ tomlString action.name ++ "\n" ++
  "op = " ++ tomlString action.op.id ++ "\n" ++
  "bytes = " ++ toString action.bytes ++ "\n" ++
  optionalFields

def renderCryptoHashAction (action : CryptoHashAction) : String :=
  "[[solana.entrypoint_crypto]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "crypto = " ++ tomlString action.name ++ "\n" ++
  "op = " ++ tomlString action.op.id ++ "\n" ++
  "input_state = " ++ tomlString action.inputState ++ "\n" ++
  "bytes = " ++ toString action.bytes ++ "\n" ++
  "output_states = " ++ tomlStringArray action.outputStates ++ "\n" ++
  "feature_gated = " ++ tomlBool action.featureGated ++ "\n"

def renderSysvarAction (action : SysvarReadAction) : String :=
  "[[solana.entrypoint_sysvar]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "sysvar = " ++ tomlString action.name ++ "\n" ++
  "kind = " ++ tomlString action.kind.id ++ "\n" ++
  "field = " ++ tomlString action.field.id ++ "\n" ++
  "output_state = " ++ tomlString action.outputState ++ "\n" ++
  "feature_gated = " ++ tomlBool (SysvarKind.featureGated action.kind) ++ "\n"

def renderReturnDataAction (action : ReturnDataAction) : String :=
  "[[solana.entrypoint_return_data]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "return_data = " ++ tomlString action.name ++ "\n" ++
  "op = \"set\"\n" ++
  "source_state = " ++ tomlString action.sourceState ++ "\n" ++
  "bytes = " ++ toString action.bytes ++ "\n"

def renderReturnDataReadAction (action : ReturnDataReadAction) : String :=
  let optionalFields :=
    (match action.lengthState? with
    | some state => s!"length_state = {tomlString state}\n"
    | none => "")
  "[[solana.entrypoint_return_data]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "return_data = " ++ tomlString action.name ++ "\n" ++
  "op = \"get\"\n" ++
  "destination_state = " ++ tomlString action.destinationState ++ "\n" ++
  "max_bytes = " ++ toString action.maxBytes ++ "\n" ++
  optionalFields ++
  "program_id_states = " ++ tomlStringArray action.programIdStates ++ "\n"

def renderComputeUnitsAction (action : ComputeUnitsAction) : String :=
  "[[solana.entrypoint_compute_units]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "compute_units = " ++ tomlString action.name ++ "\n" ++
  "op = \"remaining\"\n" ++
  "output_state = " ++ tomlString action.outputState ++ "\n" ++
  "feature_gated = " ++ tomlBool action.featureGated ++ "\n"

def renderComputeUnitsLogAction (action : ComputeUnitsLogAction) : String :=
  "[[solana.entrypoint_compute_units]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "compute_units = " ++ tomlString action.name ++ "\n" ++
  "op = \"log_remaining\"\n"

def renderComputeBudgetAdvice (action : ComputeBudgetAdvice) : String :=
  let optionalFields :=
    (match action.unitLimit? with
    | some units => s!"unit_limit = {units}\n"
    | none => "") ++
    (match action.unitPriceMicroLamports? with
    | some price => s!"unit_price_micro_lamports = {price}\n"
    | none => "")
  "[[solana.entrypoint_compute_budget]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "compute_budget = " ++ tomlString action.name ++ "\n" ++
  optionalFields

def renderPubkeyLogAction (action : PubkeyLogAction) : String :=
  "[[solana.entrypoint_log]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "log = " ++ tomlString action.name ++ "\n" ++
  "op = \"pubkey\"\n" ++
  "account = " ++ tomlString action.account ++ "\n"

def renderDataLogAction (action : DataLogAction) : String :=
  "[[solana.entrypoint_log]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "log = " ++ tomlString action.name ++ "\n" ++
  "op = \"data\"\n" ++
  "source_state = " ++ tomlString action.sourceState ++ "\n" ++
  "bytes = " ++ toString action.bytes ++ "\n"

def renderAccountReallocAction (action : AccountReallocAction) : String :=
  "[[solana.entrypoint_realloc]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "realloc = " ++ tomlString action.name ++ "\n" ++
  "account = " ++ tomlString action.account ++ "\n" ++
  "new_size = " ++ toString action.newSize ++ "\n" ++
  "max_permitted_data_increase = " ++
    toString ProofForge.Backend.Solana.StateLayout.MAX_PERMITTED_DATA_INCREASE ++ "\n"

def renderTransferHookExtraAccountMetaListAction
    (action : TransferHookExtraAccountMetaListAction) : String :=
  "[[solana.entrypoint_transfer_hook_extra_meta]]\n" ++
  "entrypoint = " ++ tomlString action.entrypoint ++ "\n" ++
  "transfer_hook_extra_meta = " ++ tomlString action.name ++ "\n" ++
  "account = " ++ tomlString action.account ++ "\n" ++
  "extra_accounts = " ++ tomlStringArray action.extraAccounts ++ "\n" ++
  "execute_discriminator = \"692565c54bfb661a\"\n" ++
  "extra_account_count = " ++ toString action.extraAccounts.size ++ "\n"

def hasManifestActions (extensions : ProgramExtensions) : Bool :=
  hasEntrypointActions extensions ||
    extensions.computeBudgetActions.size > 0

def renderActions (extensions : ProgramExtensions) : String :=
  if !hasManifestActions extensions then
    ""
  else
    let actionBlocks :=
      extensions.pdaActions.map renderPdaAction ++
      extensions.cpiActions.map renderCpiAction ++
      extensions.memoryActions.map renderMemoryAction ++
      extensions.cryptoHashActions.map renderCryptoHashAction ++
      extensions.sysvarActions.map renderSysvarAction ++
      extensions.returnDataActions.map renderReturnDataAction ++
      extensions.returnDataReadActions.map renderReturnDataReadAction ++
      extensions.computeUnitsActions.map renderComputeUnitsAction ++
      extensions.computeUnitsLogActions.map renderComputeUnitsLogAction ++
      extensions.computeBudgetActions.map renderComputeBudgetAdvice ++
      extensions.pubkeyLogActions.map renderPubkeyLogAction ++
      extensions.dataLogActions.map renderDataLogAction ++
      extensions.accountReallocActions.map renderAccountReallocAction ++
      extensions.transferHookExtraAccountMetaListActions.map
        renderTransferHookExtraAccountMetaListAction
    "\n# Solana SDK entrypoint actions\n" ++
    String.intercalate "\n" actionBlocks.toList

def renderExtensions (extensions : ProgramExtensions) : String :=
  if !hasExtensions extensions then
    ""
  else
    "\n# Solana SDK target extension metadata\n" ++
    renderAccountOrder extensions.accountOrder ++
    (if extensions.accountOrder.size > 0 && (extensions.accounts.size > 0 || extensions.allocators.size > 0 || extensions.pdas.size > 0 || extensions.cpis.size > 0 || hasManifestActions extensions) then "\n" else "") ++
    String.intercalate "\n" (extensions.accounts.map renderDeclaredAccount).toList ++
    (if extensions.accounts.size > 0 && (extensions.allocators.size > 0 || extensions.pdas.size > 0 || extensions.cpis.size > 0 || hasManifestActions extensions) then "\n" else "") ++
    String.intercalate "\n" (extensions.allocators.map renderAllocator).toList ++
    (if extensions.allocators.size > 0 && (extensions.pdas.size > 0 || extensions.cpis.size > 0 || hasManifestActions extensions) then "\n" else "") ++
    String.intercalate "\n" (extensions.pdas.map renderPda).toList ++
    (if extensions.pdas.size > 0 && (extensions.cpis.size > 0 || hasManifestActions extensions) then "\n" else "") ++
    String.intercalate "\n" (extensions.cpis.map renderCpi).toList ++
    (if extensions.cpis.size > 0 && hasManifestActions extensions then "\n" else "") ++
    renderActions extensions

/-- Build instruction entries from the IR module. -/
def buildInstructions (module : Module) : Array InstructionEntry :=
  let accounts := buildDefaultAccounts module
  module.entrypoints.mapIdx fun idx ep =>
    {
      name := ep.name
      tag := idx
      handler := "sol_" ++ ep.name
      accounts := accounts
      params := buildInstructionParams ep
      minDataLen := instructionDataMinLen ep
    }

def buildInstructionsWithExtensions (module : Module) (extensions : ProgramExtensions) :
    Array InstructionEntry :=
  let accounts := buildModuleAccounts module extensions
  module.entrypoints.mapIdx fun idx ep =>
    {
      name := ep.name
      tag := idx
      handler := "sol_" ++ ep.name
      accounts := buildEntrypointAccounts module extensions accounts ep.name
      params := buildInstructionParams ep
      minDataLen := instructionDataMinLen ep
    }

def buildInstructionsWithPlan (module : Module) (plan : ProofForge.Target.CapabilityPlan) :
    Array InstructionEntry :=
  buildInstructionsWithExtensions module (ProgramExtensions.fromPlan plan)

def renderManifestWithInstructions (module : Module) (instructions : Array InstructionEntry) : String :=
  let programName := module.name.toLower
  let instructionBlocks := instructions.map InstructionEntry.render
  String.intercalate "\n" #[
    "# ProofForge generated Solana instruction manifest",
    "target = \"solana-sbpf-asm\"",
    "",
    "[program]",
    "id = \"REPLACE_WITH_PROGRAM_ID\"",
    "name = \"" ++ programName ++ "\"",
    ""
  ].toList ++ "\n" ++ String.intercalate "\n\n" instructionBlocks.toList

/-- Render the full manifest.toml contents. -/
def renderManifest (module : Module) : String :=
  renderManifestWithInstructions module (buildInstructions module)

def renderManifestWithPlan (module : Module) (plan : ProofForge.Target.CapabilityPlan) : String :=
  let extensions := ProgramExtensions.fromPlan plan
  renderManifestWithInstructions module (buildInstructionsWithExtensions module extensions) ++
    renderExtensions extensions

end ProofForge.Backend.Solana.Manifest
