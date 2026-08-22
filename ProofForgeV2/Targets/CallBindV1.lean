/-
  ProofForgeV2.Targets.CallBindV1 — compile-time opt-in callee bind table
  (ADR-0053 Wave 1 parse + Wave 2 lookup).

  Parses `proof-forge.call-bind.v1` PF-JCS into a private-ctor table.
  Wave 2: when a table is present, generic `call`/`schedule` on
  evm/solana/cosmwasm must match a row or fail closed. Missing table keeps
  hashed QN / QN stubs. `pf.crypto.*` and `pf.assets` never consult this
  table. EVM identity-bearing rows additionally contribute a canonical
  table-level digest to the EVM Plan; product artifact verification remains
  an explicit CLI boundary and does not change emitted Yul. Solana identity
  fields are exact-joined against explicit local output authorities and
  retained in the caller Plan before its outer AccountInfo path can emit.

  Not SemanticProgramV1. Not NetworkProfile. Not formal / C-3.
  Wave 2a empty-account void CALL lives in Evm.EmitIRV1 (not this table).
  Wave 2b: Solana nonempty `accounts` → compile-time AccountMeta (≤8).
  Wave 3: a nonempty, identity-distinct Solana row also drives the product
  full-body outer AccountInfo join; empty rows retain the partial path.
-/
import ProofForgeV2.Core.Canonical
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Core.Unicode

namespace ProofForgeV2.Targets.CallBindV1

open ProofForgeV2
open ProofForgeV2.Core.Common

/-- Local Repr so bind-table structures can derive Repr. -/
private instance : Repr ByteArray where
  reprPrec bytes _ :=
    (Std.Format.text "ByteArray.size=").append (repr bytes.size)

def schemaIdV1 : String := "proof-forge.call-bind.v1"

/-- Domain for the canonical EVM identity-bearing bind-row digest. This binds
    expected identity fields to callee + pre-placed address in Plan identity;
    it is not evidence that code is present at that address. -/
def evmIdentityDomainV1 : String := "pf.call-bind.evm-identity.v1"

/-- Closed bind-table targets (ADR-0053). Other TargetId values fail closed. -/
inductive CallBindTargetV1 where
  | evm
  | solana
  | cosmwasm
  deriving BEq, Repr

namespace CallBindTargetV1

def toTargetId : CallBindTargetV1 → TargetId
  | .evm => TargetId.evm
  | .solana => TargetId.solana
  | .cosmwasm => TargetId.cosmwasm

def ofTargetId? : TargetId → Option CallBindTargetV1
  | id =>
    if id == TargetId.evm then some .evm
    else if id == TargetId.solana then some .solana
    else if id == TargetId.cosmwasm then some .cosmwasm
    else none

def toString : CallBindTargetV1 → String
  | .evm => "evm"
  | .solana => "solana"
  | .cosmwasm => "cosmwasm"

instance : ToString CallBindTargetV1 := ⟨toString⟩

end CallBindTargetV1

structure CallBindIdentityV1 where
  sourceHash : Option Digest := none
  semanticHash : Option Digest := none
  artifactSha256 : Option Digest := none
  deriving Repr

/-- Complete local output identity minted only after a Solana bind row and a
    fully inspected output authority join exactly on all three SHA-256 digests. -/
structure VerifiedBindingOutputIdentityV1 where
  sourceHash : Digest
  semanticHash : Digest
  artifactSha256 : Digest
  deriving BEq, Repr

structure CallBindAccountV1 where
  role : String
  pubkey : ByteArray
  signer : Bool := false
  writable : Bool := false
  deriving Repr

inductive CallBindSiteV1 where
  | evm (address : ByteArray)
  | solana (programId : ByteArray) (accounts : Array CallBindAccountV1)
  | cosmwasm (contractAddr : String)
  deriving Repr

structure CallBindRowV1 where
  private mk ::
  callee : QualifiedName
  site : CallBindSiteV1
  identity : Option CallBindIdentityV1 := none
  /-- Product-minted local output identity. Never parsed from the bind
      document; the supported Solana outer-account path requires it. -/
  verifiedOutputIdentity : Option VerifiedBindingOutputIdentityV1 := none
  deriving Repr

/-- Fully inspected local output authority. Product CLI mints this only after
    proof-forge.output.v1 sidecar, artifact-content, and exact disk-closure
    validation. The pure target join re-hashes the selected artifact bytes. -/
structure BindingOutputAuthorityV1 where
  target : TargetId
  deployable : Bool
  artifactProgramName : String
  sourceHash : Digest
  semanticHash : Digest
  artifactSha256 : Digest
  artifactBytes : ByteArray
  deriving Repr

/-- Solana endpoint and exact local callee-output identity after authority join.
    ProgramData, loader upgrade authority, network, and deployment identity are
    deliberately outside this carrier. -/
structure VerifiedSolanaCallSiteV1 where
  programId : ByteArray
  accounts : Array CallBindAccountV1
  outputIdentity : VerifiedBindingOutputIdentityV1
  deriving Repr

structure CallBindTableV1 where
  private mk ::
  target : CallBindTargetV1
  rows : Array CallBindRowV1
  deriving Repr

namespace CallBindTableV1

/-- Module-owned mint used by the parser and Solana output verifier. Rows also
    have a private constructor, so callers cannot forge verified identities. -/
def ofRows (target : CallBindTargetV1) (rows : Array CallBindRowV1) : CallBindTableV1 :=
  { target, rows }

def empty (target : CallBindTargetV1) : CallBindTableV1 :=
  ofRows target #[]

end CallBindTableV1

private def dottedQualifiedName (name : QualifiedName) : String :=
  String.intercalate "." name.components.toArray.toList

private def findField?
    (fields : Array (String × PfJson)) (key : String) : Option PfJson :=
  match fields.find? (fun field => field.1 == key) with
  | some (_, value) => some value
  | none => none

private def requireObject
    (value : PfJson) (context : String) :
    Except String (Array (String × PfJson)) :=
  match value with
  | .object fields => pure fields
  | _ => throw s!"{context} must be a PF-JCS object"

private def requireString
    (value : PfJson) (context : String) : Except String String :=
  match value with
  | .string s => pure s
  | _ => throw s!"{context} must be a string"

private def requireArray
    (value : PfJson) (context : String) : Except String (Array PfJson) :=
  match value with
  | .array values => pure values
  | _ => throw s!"{context} must be an array"

private def requireBool
    (value : PfJson) (context : String) : Except String Bool :=
  match value with
  | .bool b => pure b
  | _ => throw s!"{context} must be a boolean"

private def requireField
    (fields : Array (String × PfJson)) (key context : String) : Except String PfJson :=
  match findField? fields key with
  | some value => pure value
  | none => throw s!"{context} missing field '{key}'"

private def rejectUnknownKeys
    (fields : Array (String × PfJson)) (allowed : Array String) (context : String) :
    Except String Unit := do
  for (key, _) in fields do
    unless allowed.any (· == key) do
      throw s!"{context} has unknown field '{key}'"

private def isLowerHexChar (c : Char) : Bool :=
  ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

private def hexNibble? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (10 + c.toNat - 'a'.toNat)
  else none

/-- Lowercase hex → bytes. Optional `0x` prefix (EVM addresses only). -/
def decodeLowerHexBytesV1 (hex : String) (expectBytes : Nat) (allow0x : Bool)
    (context : String) : Except String ByteArray := do
  let body :=
    if allow0x && hex.startsWith "0x" then
      String.ofList (hex.toList.drop 2)
    else hex
  unless body.all isLowerHexChar do
    throw s!"{context} must be lowercase hex"
  unless body.utf8ByteSize == expectBytes * 2 do
    throw s!"{context} must be exactly {expectBytes} bytes"
  let chars := body.toList.toArray
  let mut out := ByteArray.empty
  let mut i := 0
  while i + 1 < chars.size do
    match hexNibble? chars[i]!, hexNibble? chars[i + 1]! with
    | some high, some low =>
        out := out.push (UInt8.ofNat (high * 16 + low))
        i := i + 2
    | _, _ => throw s!"{context} contains a non-hex character"
  unless out.size == expectBytes do
    throw s!"{context} must be exactly {expectBytes} bytes"
  pure out

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

/-- Lowercase hex of exact bytes (no `0x`). Public so emitters can pin
    Solana program-id / EVM address needles from the same table. -/
def encodeLowerHexBytesV1 (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

private def parseCalleeDotted (value : String) : Except String QualifiedName := do
  let parts := (value.splitOn ".").toArray
  if parts.size < 2 then
    throw "callee must have at least two QualifiedName components"
  if parts.any (· == "") then
    throw "callee must not contain an empty component"
  parseQualifiedName parts

private def parseOptionalIdentity
    (fields : Array (String × PfJson)) : Except String (Option CallBindIdentityV1) := do
  match findField? fields "identity" with
  | none => pure none
  | some value =>
      let idFields ← requireObject value "identity"
      rejectUnknownKeys idFields #["artifactSha256", "semanticHash", "sourceHash"] "identity"
      let parseOne (key : String) : Except String (Option Digest) := do
        match findField? idFields key with
        | none => pure none
        | some v =>
            let s ← requireString v s!"identity.{key}"
            let d ← parseDigest s
            pure (some d)
      let sourceHash ← parseOne "sourceHash"
      let semanticHash ← parseOne "semanticHash"
      let artifactSha256 ← parseOne "artifactSha256"
      if sourceHash.isNone && semanticHash.isNone && artifactSha256.isNone then
        throw "identity must contain at least one digest field"
      pure (some { sourceHash, semanticHash, artifactSha256 })

private def parseAccountRow (value : PfJson) : Except String CallBindAccountV1 := do
  let fields ← requireObject value "accounts[]"
  rejectUnknownKeys fields #["pubkey", "role", "signer", "writable"] "accounts[]"
  let role ← requireString (← requireField fields "role" "accounts[]") "accounts[].role"
  validateIdentifierComponent role
  let pubkeyHex ← requireString (← requireField fields "pubkey" "accounts[]") "accounts[].pubkey"
  let pubkey ← decodeLowerHexBytesV1 pubkeyHex 32 false "accounts[].pubkey"
  let signer ←
    match findField? fields "signer" with
    | none => pure false
    | some v => requireBool v "accounts[].signer"
  let writable ←
    match findField? fields "writable" with
    | none => pure false
    | some v => requireBool v "accounts[].writable"
  pure { role, pubkey, signer, writable }

private def parseAccounts (value : PfJson) : Except String (Array CallBindAccountV1) := do
  let items ← requireArray value "accounts"
  let mut out : Array CallBindAccountV1 := #[]
  let mut seen : Array String := #[]
  for item in items do
    let acc ← parseAccountRow item
    if seen.any (· == acc.role) then
      throw s!"duplicate account role '{acc.role}'"
    seen := seen.push acc.role
    out := out.push acc
  pure out

private def parseEvmSite (fields : Array (String × PfJson)) : Except String CallBindSiteV1 := do
  rejectUnknownKeys fields #["address", "callee", "identity"] "evm binding"
  let hex ← requireString (← requireField fields "address" "evm binding") "address"
  unless hex.startsWith "0x" do
    throw "evm address must start with 0x"
  let address ← decodeLowerHexBytesV1 hex 20 true "address"
  pure (.evm address)

private def parseSolanaSite (fields : Array (String × PfJson)) : Except String CallBindSiteV1 := do
  rejectUnknownKeys fields #["accounts", "callee", "identity", "programId"] "solana binding"
  let pidHex ← requireString (← requireField fields "programId" "solana binding") "programId"
  let programId ← decodeLowerHexBytesV1 pidHex 32 false "programId"
  let accounts ← parseAccounts (← requireField fields "accounts" "solana binding")
  pure (.solana programId accounts)

private def parseCosmWasmSite (fields : Array (String × PfJson)) : Except String CallBindSiteV1 := do
  rejectUnknownKeys fields #["callee", "contractAddr", "identity"] "cosmwasm binding"
  let addr ← requireString (← requireField fields "contractAddr" "cosmwasm binding") "contractAddr"
  unless 1 ≤ addr.utf8ByteSize && addr.utf8ByteSize ≤ 128 do
    throw "contractAddr must contain 1..128 UTF-8 bytes"
  ProofForgeV2.Core.Unicode.requireNfc addr
  pure (.cosmwasm addr)

private def parseRow
    (target : CallBindTargetV1) (value : PfJson) : Except String CallBindRowV1 := do
  let fields ← requireObject value "bindings[]"
  let calleeStr ← requireString (← requireField fields "callee" "bindings[]") "callee"
  let callee ← parseCalleeDotted calleeStr
  let site ←
    match target with
    | .evm => parseEvmSite fields
    | .solana => parseSolanaSite fields
    | .cosmwasm => parseCosmWasmSite fields
  let identity ← parseOptionalIdentity fields
  pure { callee, site, identity }

private def parseTargetField (value : String) : Except String CallBindTargetV1 :=
  match TargetId.parse? value with
  | none => throw s!"unknown target '{value}'"
  | some id =>
      match CallBindTargetV1.ofTargetId? id with
      | some t => pure t
      | none => throw s!"--bindings target '{value}' is outside evm|solana|cosmwasm"

/-- Decode a canonical `proof-forge.call-bind.v1` PF-JCS document. -/
def parseCallBindTableV1 (input : String) : Except String CallBindTableV1 := do
  let json ← parsePfJcs input
  let fields ← requireObject json "call-bind root"
  rejectUnknownKeys fields #["bindings", "schema", "target"] "call-bind root"
  let schema ← requireString (← requireField fields "schema" "call-bind root") "schema"
  unless schema == schemaIdV1 do
    throw s!"schema must be '{schemaIdV1}'"
  let targetStr ← requireString (← requireField fields "target" "call-bind root") "target"
  let target ← parseTargetField targetStr
  let bindingJson ← requireArray (← requireField fields "bindings" "call-bind root") "bindings"
  let mut rows : Array CallBindRowV1 := #[]
  let mut seen : Array String := #[]
  for item in bindingJson do
    let row ← parseRow target item
    let key := dottedQualifiedName row.callee
    if seen.any (· == key) then
      throw s!"duplicate callee '{key}'"
    seen := seen.push key
    rows := rows.push row
  pure (CallBindTableV1.ofRows target rows)

/-- Exact QN lookup. Missing → none (Wave 2 turns that into emit fail-closed). -/
def findRow? (table : CallBindTableV1) (callee : QualifiedName) : Option CallBindRowV1 :=
  let key := dottedQualifiedName callee
  table.rows.find? (fun row => dottedQualifiedName row.callee == key)

/-- Reject `--bindings` on a target this table does not serve. -/
def requireCompatibleTarget (table : CallBindTableV1) (buildTarget : TargetId) :
    Except String Unit := do
  unless table.target.toTargetId == buildTarget do
    throw s!"--bindings target '{table.target}' does not match --target '{buildTarget}'"

/-- Parse + target join. Product build keeps the table and threads it into
    emit (Wave 2). -/
def decodeCallBindTableForTargetV1 (input : String) (buildTarget : TargetId) :
    Except String CallBindTableV1 := do
  let table ← parseCallBindTableV1 input
  requireCompatibleTarget table buildTarget
  pure table

/-- Whether the table contains at least one optional identity object. -/
def hasIdentityRowsV1 (table : CallBindTableV1) : Bool :=
  table.rows.any (·.identity.isSome)

private def identityJsonV1 (identity : CallBindIdentityV1) : Except String PfJson := do
  let mut fields : Array (String × PfJson) := #[]
  -- UTF-16/PF-JCS key order: artifactSha256, semanticHash, sourceHash.
  match identity.artifactSha256 with
  | none => pure ()
  | some digest => fields := fields.push ("artifactSha256", .string (← renderDigest digest))
  match identity.semanticHash with
  | none => pure ()
  | some digest => fields := fields.push ("semanticHash", .string (← renderDigest digest))
  match identity.sourceHash with
  | none => pure ()
  | some digest => fields := fields.push ("sourceHash", .string (← renderDigest digest))
  if fields.isEmpty then
    throw "call-bind: identity must contain at least one digest field"
  pure (.object fields)

/-- Canonical digest of all EVM identity-bearing rows, sorted by exact callee
    QN. Each row binds `address + callee + expected identity`; identity-less
    tables return `none`, preserving historical EVM Plan bytes. This is an
    expectation digest only. Product CLI evidence validation independently
    stable-reads a deployable engineering output before build publication. -/
def evmIdentityDigestV1 (table : CallBindTableV1) : Except String (Option Digest) := do
  unless table.target == .evm do
    throw "call-bind: EVM identity digest requires an evm table"
  let rows := (table.rows.filter (·.identity.isSome)).qsort fun a b =>
    dottedQualifiedName a.callee < dottedQualifiedName b.callee
  if rows.isEmpty then
    pure none
  else
    let mut encodedRows : Array PfJson := #[]
    for row in rows do
      let identity ← match row.identity with
        | some value => pure value
        | none => throw "call-bind: internal identity-row selection mismatch"
      let address ← match row.site with
        | .evm value => pure value
        | _ => throw "call-bind: identity-bearing EVM row is not an evm site"
      unless address.size == 20 do
        throw "call-bind: evm address must be exactly 20 bytes"
      encodedRows := encodedRows.push <| .object #[
        ("address", .string ("0x" ++ encodeLowerHexBytesV1 address)),
        ("callee", .string (dottedQualifiedName row.callee)),
        ("identity", ← identityJsonV1 identity)
      ]
    let document := PfJson.object #[
      ("bindings", .array encodedRows),
      ("schema", .string "proof-forge.call-bind-identity.v1"),
      ("target", .string "evm")
    ]
    let canonical ← renderPfJcs document
    pure (some (← domainSeparatedSha256 evmIdentityDomainV1 canonical.toUTF8))

/-- Exact QN from Plan callee components. Empty / malformed → none. -/
def qualifiedNameOfComponents? (components : Array String) : Option QualifiedName :=
  match parseQualifiedName components with
  | .ok name => some name
  | .error _ => none

private def missingCalleeError (kind : String) (callee : Array String) : String :=
  let qn := String.intercalate "." callee.toList
  s!"call-bind: no {kind} row for callee '{qn}'"

private def wrongSiteError (kind : String) (callee : Array String) : String :=
  let qn := String.intercalate "." callee.toList
  s!"call-bind: row for '{qn}' is not a {kind} site"

/-- Wave 2 EVM lookup. Present table + missing/wrong-site row → error.
    Caller must not invoke this when the table is absent. -/
def requireEvmAddressV1 (table : CallBindTableV1) (callee : Array String) :
    Except String ByteArray := do
  let some name := qualifiedNameOfComponents? callee |
    throw (missingCalleeError "evm" callee)
  match findRow? table name with
  | none => throw (missingCalleeError "evm" callee)
  | some row =>
      match row.site with
      | .evm address =>
          unless address.size == 20 do
            throw "call-bind: evm address must be exactly 20 bytes"
          pure address
      | _ => throw (wrongSiteError "evm" callee)

/-- Wave 2b compile-time AccountMeta cap. Larger rows fail closed so the
    S1b stack packing stays bounded. Not an outer-instruction role count. -/
def maxSolanaBindAccountsV1 : Nat := 8

/-- Shared Solana row lookup. Missing / wrong-site / bad sizes fail closed. -/
def requireSolanaBindingV1 (table : CallBindTableV1) (callee : Array String) :
    Except String (ByteArray × Array CallBindAccountV1) := do
  let some name := qualifiedNameOfComponents? callee |
    throw (missingCalleeError "solana" callee)
  match findRow? table name with
  | none => throw (missingCalleeError "solana" callee)
  | some row =>
      match row.site with
      | .solana programId accounts =>
          unless programId.size == 32 do
            throw "call-bind: solana programId must be exactly 32 bytes"
          unless accounts.size ≤ maxSolanaBindAccountsV1 do
            throw
              s!"call-bind: solana accounts binding admits at most {maxSolanaBindAccountsV1} AccountMetas"
          for acc in accounts do
            unless acc.pubkey.size == 32 do
              throw "call-bind: solana account pubkey must be exactly 32 bytes"
          pure (programId, accounts)
      | _ => throw (wrongSiteError "solana" callee)

private def digestEqV1 (a b : Digest) : Bool :=
  a.algorithm == b.algorithm && a.bytes == b.bytes

private def expectedArtifactProgramNameV1 (callee : QualifiedName) : Except String String := do
  let components := callee.components.toArray
  if components.size < 2 then
    throw "call-bind: Solana callee must contain a program and method"
  pure components[components.size - 2]!

private structure VerifiedBindingOutputMatchV1 where
  index : Nat
  identity : VerifiedBindingOutputIdentityV1
  artifactBytes : ByteArray

private def verifyBindingOutputForSolanaRowV1
    (row : CallBindRowV1)
    (outputs : Array BindingOutputAuthorityV1) :
    Except String VerifiedBindingOutputMatchV1 := do
  let identity ← match row.identity with
    | some value => pure value
    | none =>
        throw s!"call-bind: Solana row '{dottedQualifiedName row.callee}' requires identity"
  let sourceHash ← match identity.sourceHash with
    | some value => pure value
    | none =>
        throw
          s!"call-bind: Solana row '{dottedQualifiedName row.callee}' requires identity.sourceHash"
  let semanticHash ← match identity.semanticHash with
    | some value => pure value
    | none =>
        throw
          s!"call-bind: Solana row '{dottedQualifiedName row.callee}' requires identity.semanticHash"
  let artifactSha256 ← match identity.artifactSha256 with
    | some value => pure value
    | none =>
        throw
          s!"call-bind: Solana row '{dottedQualifiedName row.callee}' requires identity.artifactSha256"
  let programName ← expectedArtifactProgramNameV1 row.callee
  let mut matchIndexes : Array Nat := #[]
  for index in [0:outputs.size] do
    let output ← match outputs[index]? with
      | some value => pure value
      | none => throw "call-bind: internal Solana output index is out of bounds"
    if output.target == .solana && output.deployable &&
        output.artifactProgramName == programName &&
        digestEqV1 output.sourceHash sourceHash &&
        digestEqV1 output.semanticHash semanticHash &&
        digestEqV1 output.artifactSha256 artifactSha256 then
      matchIndexes := matchIndexes.push index
  if matchIndexes.isEmpty then
    throw
      s!"call-bind: no verified Solana output matches '{dottedQualifiedName row.callee}'"
  unless matchIndexes.size == 1 do
    throw
      s!"call-bind: multiple verified Solana outputs match '{dottedQualifiedName row.callee}'"
  let outputIndex := matchIndexes[0]!
  let output ← match outputs[outputIndex]? with
    | some value => pure value
    | none => throw "call-bind: internal Solana output index is out of bounds"
  let recomputedArtifactSha256 := sha256Bytes output.artifactBytes
  unless digestEqV1 recomputedArtifactSha256 artifactSha256 do
    throw
      s!"call-bind: Solana artifact SHA-256 mismatch for '{dottedQualifiedName row.callee}'"
  pure {
    index := outputIndex
    identity := { sourceHash, semanticHash, artifactSha256 }
    artifactBytes := output.artifactBytes
  }

/-- Close every Solana row against exactly one fully inspected local output.

    Required join:
    row QN program name + sourceHash + semanticHash + artifactSha256
      == proof-forge.output.v1 manifest + `{program}.so` descriptor.
    Missing/partial identities, duplicate authorities, empty ELF bytes, and
    unused authorities fail closed. No RPC or deployment claim is introduced. -/
def verifySolanaBindingOutputsV1
    (table : CallBindTableV1)
    (outputs : Array BindingOutputAuthorityV1) :
    Except String CallBindTableV1 := do
  unless table.target == .solana do
    throw "call-bind: Solana binding outputs require a solana table"
  let mut verifiedRows : Array CallBindRowV1 := #[]
  let mut usedOutputs : Array Nat := #[]
  for row in table.rows do
    match row.site with
    | .solana _ _ => pure ()
    | _ => throw "call-bind: Solana table contains a non-Solana site"
    let output ← verifyBindingOutputForSolanaRowV1 row outputs
    if output.artifactBytes.isEmpty then
      throw s!"call-bind: Solana ELF artifact is empty for '{dottedQualifiedName row.callee}'"
    unless usedOutputs.contains output.index do
      usedOutputs := usedOutputs.push output.index
    verifiedRows := verifiedRows.push
      { row with verifiedOutputIdentity := some output.identity }
  for index in [0:outputs.size] do
    unless usedOutputs.contains index do
      throw s!"call-bind: Solana binding output {index} does not match any row"
  pure (CallBindTableV1.ofRows .solana verifiedRows)

/-- Product gate for the Solana outer-account path. The endpoint remains the
    Wave-3 runtime contract; this identity proves only the local callee output
    inspected while building the caller. -/
def requireVerifiedSolanaCallSiteV1
    (table : CallBindTableV1) (callee : Array String) :
    Except String VerifiedSolanaCallSiteV1 := do
  let (programId, accounts) ← requireSolanaBindingV1 table callee
  let some name := qualifiedNameOfComponents? callee |
    throw (missingCalleeError "solana" callee)
  let some row := findRow? table name |
    throw (missingCalleeError "solana" callee)
  let outputIdentity ← match row.verifiedOutputIdentity with
    | some value => pure value
    | none =>
        throw s!"call-bind: Solana row '{dottedQualifiedName name}' has no verified output artifact"
  pure { programId, accounts, outputIdentity }

/-- Wave 2/2b Solana program-id lookup. Nonempty `accounts` are admitted
    (Wave 2b compile-time AccountMeta); this helper still returns only the
    program id. Empty accounts → program id only (empty-meta packing). -/
def requireSolanaProgramIdV1 (table : CallBindTableV1) (callee : Array String) :
    Except String ByteArray := do
  let (programId, _) ← requireSolanaBindingV1 table callee
  pure programId

/-- Wave 2b: compile-time AccountMeta list (possibly empty). -/
def requireSolanaAccountsV1 (table : CallBindTableV1) (callee : Array String) :
    Except String (Array CallBindAccountV1) := do
  let (_, accounts) ← requireSolanaBindingV1 table callee
  pure accounts

/-- Wave 3 outer AccountInfo join gate. The Loader transaction account list
    cannot carry two distinct full-account rows for one pubkey, and the callee
    program occupies its own outer role. Keep the schema permissive for the
    Wave 2b compile-time-only path, but fail closed before activating the
    runtime join. Product callers must separately pass
    `requireVerifiedSolanaCallSiteV1` before deriving a Plan. -/
def requireSolanaOuterAccountJoinV1
    (table : CallBindTableV1) (callee : Array String) :
    Except String (ByteArray × Array CallBindAccountV1) := do
  let (programId, accounts) ← requireSolanaBindingV1 table callee
  unless !accounts.isEmpty do
    throw "call-bind: Solana outer AccountInfo join requires at least one account row"
  let mut seen : Array ByteArray := #[]
  for account in accounts do
    if account.pubkey == programId then
      throw
        "call-bind: Solana outer AccountInfo account pubkeys must be distinct from programId"
    if seen.any (· == account.pubkey) then
      throw
        "call-bind: Solana outer AccountInfo join requires distinct account pubkeys"
    seen := seen.push account.pubkey
  pure (programId, accounts)

/-- Wave 2 CosmWasm lookup. Present table + missing/wrong-site → error. -/
def requireCosmWasmAddressV1 (table : CallBindTableV1) (callee : Array String) :
    Except String String := do
  let some name := qualifiedNameOfComponents? callee |
    throw (missingCalleeError "cosmwasm" callee)
  match findRow? table name with
  | none => throw (missingCalleeError "cosmwasm" callee)
  | some row =>
      match row.site with
      | .cosmwasm contractAddr =>
          unless 1 ≤ contractAddr.utf8ByteSize && contractAddr.utf8ByteSize ≤ 128 do
            throw "call-bind: contractAddr must contain 1..128 UTF-8 bytes"
          pure contractAddr
      | _ => throw (wrongSiteError "cosmwasm" callee)

/-- True when `qn` is a `pf.crypto.*` catalog call (never consults the table). -/
def isPfCryptoBindExemptQnV1 (qn : String) : Bool :=
  qn.startsWith "pf.crypto."

/-- True when `qn` is a `pf.assets.*` catalog call (never consults the table). -/
def isPfAssetsBindExemptQnV1 (qn : String) : Bool :=
  qn.startsWith "pf.assets."

end ProofForgeV2.Targets.CallBindV1
