/-
  Tests.Materialization.CallBindV1 — ADR-0053 parser + bound emit.

  Pure parse of `proof-forge.call-bind.v1`, `--bindings` preflight, and
  three-leaf emit consume (missing row fail closed; bound address appears
  in Yul / WAT). EVM and Solana rows additionally require exact local-output
  identity verification. EVM pins the runtime `extcodehash` gate before CALL;
  Solana retains the verified local ELF identity in the caller Plan while the
  runtime gate remains programId + executable AccountInfo.
  Wave 2a pins empty-account void CALL `extcodesize` revert.
  Wave 2b pins Solana compile-time AccountMeta (nonempty accounts).
  Wave 2c pins program-level callScheduleResidual (build only; target
  inspect stays the closed kind table). Wave 3 pins Solana bound-account
  outer AccountInfo join. Not formal / C-3.
-/
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.CallBindV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.Solana.CpiIdlV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import Tests.Language.ParserSession

set_option maxRecDepth 4096

namespace Tests.Materialization.CallBindV1

open ProofForgeV2
open ProofForgeV2.CLI
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.CallBindV1
open ProofForgeV2.Targets.RequirementResolverV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def hasSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

private def expectOk (label : String) (r : Except String α) : IO α :=
  match r with
  | .ok v => pure v
  | .error msg => throw <| IO.userError s!"{label}: unexpected error: {msg}"

private def expectErr (label : String) (r : Except String α) (needle : String) : IO Unit :=
  match r with
  | .ok _ => throw <| IO.userError s!"{label}: expected error containing '{needle}'"
  | .error msg =>
      expect (hasSubstr msg needle)
        s!"{label}: error must mention '{needle}', got: {msg}"

private def liftJcs (label : String) (value : PfJson) : IO String :=
  match renderPfJcs value with
  | .ok s => pure s
  | .error msg => throw <| IO.userError s!"{label}: renderPfJcs failed: {msg}"

private def digestWire (label : String) (digest : Digest) : IO String :=
  match renderDigest digest with
  | .ok value => pure value
  | .error msg => throw <| IO.userError s!"{label}: renderDigest failed: {msg}"

private def evmBinding (callee address : String) : PfJson :=
  .object #[("address", .string address), ("callee", .string callee)]

private def evmBindingWithIdentity
    (callee address sourceHash semanticHash artifactSha256 : String) : PfJson :=
  .object #[
    ("address", .string address),
    ("callee", .string callee),
    ("identity", .object #[
      ("artifactSha256", .string artifactSha256),
      ("semanticHash", .string semanticHash),
      ("sourceHash", .string sourceHash)
    ])
  ]

private def evmDoc (bindings : Array PfJson) : PfJson :=
  .object #[
    ("bindings", .array bindings),
    ("schema", .string schemaIdV1),
    ("target", .string "evm")
  ]

private def solanaAccount (role pubkey : String) (signer writable : Bool) : PfJson :=
  .object #[
    ("pubkey", .string pubkey),
    ("role", .string role),
    ("signer", .bool signer),
    ("writable", .bool writable)
  ]

private def solanaBinding (callee programId : String) (accounts : Array PfJson) : PfJson :=
  .object #[
    ("accounts", .array accounts),
    ("callee", .string callee),
    ("programId", .string programId)
  ]

private def solanaBindingWithIdentity
    (callee programId sourceHash semanticHash artifactSha256 : String)
    (accounts : Array PfJson) : PfJson :=
  .object #[
    ("accounts", .array accounts),
    ("callee", .string callee),
    ("identity", .object #[
      ("artifactSha256", .string artifactSha256),
      ("semanticHash", .string semanticHash),
      ("sourceHash", .string sourceHash)
    ]),
    ("programId", .string programId)
  ]

private def solanaDoc (bindings : Array PfJson) : PfJson :=
  .object #[
    ("bindings", .array bindings),
    ("schema", .string schemaIdV1),
    ("target", .string "solana")
  ]

private def cosmwasmBinding (callee addr : String) : PfJson :=
  .object #[("callee", .string callee), ("contractAddr", .string addr)]

private def cosmwasmDoc (bindings : Array PfJson) : PfJson :=
  .object #[
    ("bindings", .array bindings),
    ("schema", .string schemaIdV1),
    ("target", .string "cosmwasm")
  ]

private def zero20 : String := "0x" ++ String.ofList (List.replicate 40 '0')
private def ones20 : String := "0x" ++ String.ofList (List.replicate 40 '1')
private def zero32 : String := String.ofList (List.replicate 64 '0')
private def ones32 : String := String.ofList (List.replicate 64 '1')
private def digest0 : String := "sha256:" ++ String.ofList (List.replicate 64 '0')
private def digest1 : String := "sha256:" ++ String.ofList (List.replicate 64 '1')

private def expectBuildOpts (label : String) (args : List String) : IO BuildOptions :=
  expectOk label (parseBuildArgsExcept args)

private def expectResidual
    (label : String)
    (kind : TargetKind)
    (semantic : SemanticProgramV1)
    (table : Option CallBindTableV1)
    (expected : Option String) : IO Unit := do
  match programCallScheduleResidualV1 kind semantic table with
  | .ok tag =>
      expect (tag == expected)
        s!"{label}: residual {repr tag} ≠ {repr expected}"
  | .error msg => throw <| IO.userError s!"{label}: {msg}"

unsafe def run : IO Unit := do
  -- Canonical empty table (all three targets).
  for (label, doc, expected) in
      #[("evm-empty", evmDoc #[], CallBindTargetV1.evm),
        ("solana-empty", solanaDoc #[], CallBindTargetV1.solana),
        ("cw-empty", cosmwasmDoc #[], CallBindTargetV1.cosmwasm)] do
    let text ← liftJcs label doc
    let table ← expectOk label (parseCallBindTableV1 text)
    expect (table.target == expected) s!"{label}: target"
    expect (table.rows.size == 0) s!"{label}: empty rows"

  -- Canonical EVM row + lookup.
  let evmText ← liftJcs "evm-row" (evmDoc #[evmBinding "Oracle.quote" zero20])
  let evmTable ← expectOk "evm-row" (parseCallBindTableV1 evmText)
  expect (evmTable.rows.size == 1) "evm row count"
  let oracle ← expectOk "oracle qn" (parseQualifiedName #["Oracle", "quote"])
  match findRow? evmTable oracle, evmTable.rows[0]? with
  | some row, some first =>
      expect (row.callee == first.callee) "evm findRow matches first"
      match row.site with
      | .evm addr => expect (addr.size == 20) "evm address is 20 bytes"
      | _ => throw <| IO.userError "evm row must be evm site"
      expect row.identity.isNone "evm identity omitted"
  | _, _ => throw <| IO.userError "evm findRow must hit Oracle.quote"
  let missing ← expectOk "missing qn" (parseQualifiedName #["Oracle", "missing"])
  expect (findRow? evmTable missing).isNone "missing callee is none"

  -- Canonical Solana row with optional flags.
  let solText ← liftJcs "sol-row"
    (solanaDoc #[solanaBinding "Vault.deposit" ones32
      #[solanaAccount "authority" zero32 true true]])
  let solTable ← expectOk "sol-row" (parseCallBindTableV1 solText)
  match solTable.rows[0]? with
  | none => throw <| IO.userError "solana row missing"
  | some row =>
      match row.site with
      | .solana pid accounts =>
          expect (pid.size == 32) "solana programId is 32 bytes"
          expect (accounts.size == 1) "one account"
          match accounts[0]? with
          | some acc =>
              expect (acc.role == "authority") "account role"
              expect (acc.signer && acc.writable) "account flags"
              expect (acc.pubkey.size == 32) "account pubkey is 32 bytes"
          | none => throw <| IO.userError "solana account missing"
      | _ => throw <| IO.userError "solana row must be solana site"

  -- Canonical CosmWasm row.
  let cwText ← liftJcs "cw-row"
    (cosmwasmDoc #[cosmwasmBinding "Bank.send" "cosmos1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqnrql8a"])
  let cwTable ← expectOk "cw-row" (parseCallBindTableV1 cwText)
  match cwTable.rows[0]? with
  | none => throw <| IO.userError "cosmwasm row missing"
  | some row =>
      match row.site with
      | .cosmwasm addr => expect (addr.startsWith "cosmos1") "cw bech32-shaped stub"
      | _ => throw <| IO.userError "cosmwasm row must be cosmwasm site"

  -- Optional identity (one digest is enough).
  let idDoc := evmDoc #[.object #[
    ("address", .string ones20),
    ("callee", .string "Feed.push"),
    ("identity", .object #[("sourceHash", .string digest0)])
  ]]
  let idText ← liftJcs "identity" idDoc
  let idTable ← expectOk "identity" (parseCallBindTableV1 idText)
  match idTable.rows[0]? with
  | none => throw <| IO.userError "identity row missing"
  | some row =>
      match row.identity with
      | some id =>
          expect id.sourceHash.isSome "sourceHash present"
          expect id.semanticHash.isNone "semanticHash omitted"
          expect id.artifactSha256.isNone "artifactSha256 omitted"
      | none => throw <| IO.userError "identity object must parse"

  -- Non-canonical JSON (trailing space) fail closed.
  expectErr "non-canonical"
    (parseCallBindTableV1 "{\"bindings\":[],\"schema\":\"proof-forge.call-bind.v1\",\"target\":\"evm\"} ")
    "trailing data"

  -- Wrong schema / unknown / unsupported target.
  let badSchema ← liftJcs "bad-schema"
    (.object #[("bindings", .array #[]), ("schema", .string "nope"), ("target", .string "evm")])
  expectErr "bad-schema" (parseCallBindTableV1 badSchema) "schema must be"
  let unknownTarget ← liftJcs "unknown-target"
    (.object #[("bindings", .array #[]), ("schema", .string schemaIdV1),
      ("target", .string "NOT-A-TARGET")])
  expectErr "unknown-target" (parseCallBindTableV1 unknownTarget) "unknown target"
  let noirTarget ← liftJcs "noir-target"
    (.object #[("bindings", .array #[]), ("schema", .string schemaIdV1),
      ("target", .string "noir")])
  expectErr "noir-target" (parseCallBindTableV1 noirTarget) "outside evm|solana|cosmwasm"

  -- Duplicate callee / malformed QN.
  let dup ← liftJcs "dup"
    (evmDoc #[evmBinding "Oracle.quote" zero20, evmBinding "Oracle.quote" ones20])
  expectErr "dup" (parseCallBindTableV1 dup) "duplicate callee"
  let shortQn ← liftJcs "short-qn" (evmDoc #[evmBinding "Oracle" zero20])
  expectErr "short-qn" (parseCallBindTableV1 shortQn) "at least two"
  let emptyComp ← liftJcs "empty-comp" (evmDoc #[evmBinding "Oracle." zero20])
  expectErr "empty-comp" (parseCallBindTableV1 emptyComp) "empty component"

  -- EVM address gates.
  let no0x ← liftJcs "no0x" (evmDoc #[evmBinding "Oracle.quote" (String.ofList (List.replicate 40 '0'))])
  expectErr "no0x" (parseCallBindTableV1 no0x) "must start with 0x"
  let upper ← liftJcs "upper" (evmDoc #[evmBinding "Oracle.quote" ("0x" ++ String.ofList (List.replicate 40 'A'))])
  expectErr "upper" (parseCallBindTableV1 upper) "lowercase hex"
  let shortAddr ← liftJcs "short-addr" (evmDoc #[evmBinding "Oracle.quote" "0x00"])
  expectErr "short-addr" (parseCallBindTableV1 shortAddr) "exactly 20 bytes"
  let evmWithPid ← liftJcs "evm-pid"
    (.object #[
      ("bindings", .array #[.object #[
        ("address", .string zero20),
        ("callee", .string "Oracle.quote"),
        ("programId", .string zero32)]]),
      ("schema", .string schemaIdV1),
      ("target", .string "evm")])
  expectErr "evm-pid" (parseCallBindTableV1 evmWithPid) "unknown field"

  -- Solana length / duplicate role.
  let shortPid ← liftJcs "short-pid"
    (solanaDoc #[solanaBinding "Vault.deposit" "00" #[solanaAccount "authority" zero32 false false]])
  expectErr "short-pid" (parseCallBindTableV1 shortPid) "exactly 32 bytes"
  let shortPk ← liftJcs "short-pk"
    (solanaDoc #[solanaBinding "Vault.deposit" ones32 #[solanaAccount "authority" "00" false false]])
  expectErr "short-pk" (parseCallBindTableV1 shortPk) "exactly 32 bytes"
  let dupRole ← liftJcs "dup-role"
    (solanaDoc #[solanaBinding "Vault.deposit" ones32
      #[solanaAccount "authority" zero32 false false,
        solanaAccount "authority" ones32 true true]])
  expectErr "dup-role" (parseCallBindTableV1 dupRole) "duplicate account role"

  -- CosmWasm empty / non-NFC.
  let emptyAddr ← liftJcs "empty-addr" (cosmwasmDoc #[cosmwasmBinding "Bank.send" ""])
  expectErr "empty-addr" (parseCallBindTableV1 emptyAddr) "1..128"
  let nfd := String.ofList ['e', Char.ofNat 0x0301]
  let nfdDoc ← liftJcs "nfd" (cosmwasmDoc #[cosmwasmBinding "Bank.send" nfd])
  expectErr "nfd" (parseCallBindTableV1 nfdDoc) "NFC"

  -- Identity digest format + empty identity.
  let badDigest ← liftJcs "bad-digest"
    (evmDoc #[.object #[
      ("address", .string zero20),
      ("callee", .string "Feed.push"),
      ("identity", .object #[("sourceHash", .string (String.ofList (List.replicate 64 '0')))])]])
  expectErr "bad-digest" (parseCallBindTableV1 badDigest) "sha256:"
  let emptyId ← liftJcs "empty-id"
    (evmDoc #[.object #[
      ("address", .string zero20),
      ("callee", .string "Feed.push"),
      ("identity", .object #[])]])
  expectErr "empty-id" (parseCallBindTableV1 emptyId) "at least one digest"

  -- Target join helper.
  let evmOk ← expectOk "join-ok" (decodeCallBindTableForTargetV1 evmText TargetId.evm)
  expect (evmOk.target == .evm) "join keeps evm"
  expectErr "join-mismatch"
    (decodeCallBindTableForTargetV1 evmText TargetId.solana)
    "does not match --target"

  -- CLI: parse path; no flag stays none.
  let noFlag ← expectBuildOpts "no-flag"
    ["Examples/StateCell.lean", "--module", "Examples.StateCell", "--target", "evm"]
  expect noFlag.bindings.isNone "omitted --bindings stays none"
  let withFlag ← expectBuildOpts "with-flag"
    ["Examples/StateCell.lean", "--module", "Examples.StateCell", "--target", "evm",
      "--bindings", "testdata/call-bind/evm.v1.json",
      "--callee-output", "build/callee-a", "--callee-output", "build/callee-b"]
  expect (withFlag.bindings == some "testdata/call-bind/evm.v1.json") "bindings path"
  expect (withFlag.calleeOutputs == #["build/callee-a", "build/callee-b"])
    "callee outputs preserve explicit argv order"
  expectErr "dup-flag"
    (parseBuildArgsExcept
      ["Examples/StateCell.lean", "--module", "Examples.StateCell", "--target", "evm",
        "--bindings", "a.json", "--bindings", "b.json"])
    "duplicate --bindings"
  expectErr "missing-value"
    (parseBuildArgsExcept
      ["Examples/StateCell.lean", "--module", "Examples.StateCell", "--target", "evm",
        "--bindings"])
    "missing --bindings value"
  expectErr "callee-without-bindings"
    (parseProductCliCommandV1
      ["build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
        "--target", "evm", "--callee-output", "build/callee"])
    "--callee-output requires --bindings"
  match ← expectOk "callee-on-solana"
      (parseProductCliCommandV1
      ["build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
        "--target", "solana", "--bindings", "a.json",
        "--callee-output", "build/callee"]) with
  | .build opts =>
      expect (opts.calleeOutputs == #["build/callee"])
        "Solana product build keeps explicit callee output"
  | other => throw <| IO.userError s!"expected Solana build command, got {repr other}"
  expectErr "callee-on-cosmwasm"
    (parseProductCliCommandV1
      ["build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
        "--target", "cosmwasm", "--bindings", "a.json",
        "--callee-output", "build/callee"])
    "only accepted with --target evm|solana"
  expectErr "duplicate-callee-output"
    (parseBuildArgsExcept
      ["Examples/StateCell.lean", "--module", "Examples.StateCell", "--target", "evm",
        "--bindings", "a.json", "--callee-output", "build/callee",
        "--callee-output", "build/callee"])
    "duplicate --callee-output"

  -- Product preflight: check rejects; unsupported target rejects; evm accepts path.
  expectErr "check-flag"
    (parseProductCliCommandV1
      ["check", "Examples/StateCell.lean", "--module", "Examples.StateCell",
        "--bindings", "a.json"])
    "--bindings is not accepted on check"
  expectErr "noir-flag"
    (parseProductCliCommandV1
      ["build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
        "--target", "noir", "--bindings", "a.json"])
    "only accepted with --target evm|solana|cosmwasm"
  match ← expectOk "build-ok"
      (parseProductCliCommandV1
        ["build", "Examples/StateCell.lean", "--module", "Examples.StateCell",
          "--target", "evm", "--bindings", "a.json",
          "--callee-output", "build/callee"]) with
  | .build opts =>
      expect (opts.bindings == some "a.json") "product build keeps path"
      expect (opts.calleeOutputs == #["build/callee"])
        "product build keeps explicit callee output"
  | other => throw <| IO.userError s!"expected build command, got {repr other}"

  -- Wave 2 lookup helpers (table row is Oracle.quote).
  let quoteQn ← expectOk "quote qn 2" (parseQualifiedName #["Oracle", "quote"])
  match requireEvmAddressV1 evmTable quoteQn.components.toArray with
  | .ok bytes => expect (bytes.size == 20) "requireEvm 20 bytes"
  | .error msg => throw <| IO.userError s!"requireEvm Oracle.quote: {msg}"
  expectErr "requireEvm missing"
    (requireEvmAddressV1 evmTable
      (← expectOk "missing2" (parseQualifiedName #["Oracle", "missing"])).components.toArray)
    "no evm row"
  -- Wave 2b: nonempty Solana accounts parse and lookup admits program id.
  match requireSolanaProgramIdV1 solTable
      (← expectOk "vault qn" (parseQualifiedName #["Vault", "deposit"])).components.toArray with
  | .ok bytes => expect (bytes.size == 32) "requireSol nonempty still returns programId"
  | .error msg => throw <| IO.userError s!"requireSol nonempty must admit Wave 2b, got {msg}"
  match requireSolanaAccountsV1 solTable
      (← expectOk "vault qn 2" (parseQualifiedName #["Vault", "deposit"])).components.toArray with
  | .ok accs =>
      expect (accs.size == 1) "Vault.deposit has one compile-time AccountMeta"
      match accs[0]? with
      | some acc =>
          expect (acc.role == "authority") "Vault.deposit role"
          expect (acc.signer && acc.writable) "Vault.deposit flags"
      | none => throw <| IO.userError "Vault.deposit AccountMeta missing"
  | .error msg => throw <| IO.userError s!"requireSol accounts: {msg}"

  -- EVM local-output identity join. artifactSha256 binds the exact lowercase
  -- hex+LF runtime artifact; EXTCODEHASH uses Keccak of decoded code bytes.
  let runtimeArtifact := "6001600055\n".toUTF8
  let sourceDigest ← expectOk "source digest" (parseDigest digest0)
  let semanticDigest ← expectOk "semantic digest" (parseDigest digest1)
  let artifactDigest := sha256Bytes runtimeArtifact
  let artifactWire ← digestWire "artifact digest" artifactDigest
  let boundAddr := "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let evmBindText ← liftJcs "evm-bind-emit"
    (evmDoc #[evmBindingWithIdentity "Oracle.feed" boundAddr
      digest0 digest1 artifactWire])
  let parsedEvmBindTable ← expectOk "evm-bind-emit"
    (parseCallBindTableV1 evmBindText)
  let authority : BindingOutputAuthorityV1 := {
    target := .evm
    deployable := true
    artifactProgramName := "Oracle"
    sourceHash := sourceDigest
    semanticHash := semanticDigest
    artifactSha256 := artifactDigest
    artifactBytes := runtimeArtifact
  }
  let evmBindTable ← expectOk "verify EVM output"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable #[authority])
  let expectedRuntimeBytes ← expectOk "decode runtime"
    (decodeEvmRuntimeBytecodeArtifactV1 runtimeArtifact)
  let expectedRuntimeKeccak := Targets.Evm.Keccak.keccak256 expectedRuntimeBytes
  match requireVerifiedEvmCallSiteV1 evmBindTable #["Oracle", "feed"] with
  | .ok site =>
      expect (site.address.size == 20) "verified EVM site keeps 20-byte address"
      expect (site.runtimeCodeKeccak256 == expectedRuntimeKeccak)
        "verified EVM site derives Keccak from decoded runtime code"
  | .error msg => throw <| IO.userError s!"verified EVM site: {msg}"
  expectErr "EVM output missing"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable #[])
    "no verified EVM output"
  expectErr "EVM output duplicate"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable #[authority, authority])
    "multiple verified EVM outputs"
  expectErr "EVM source mismatch"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable
      #[{ authority with sourceHash := semanticDigest }])
    "no verified EVM output"
  expectErr "EVM semantic mismatch"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable
      #[{ authority with semanticHash := sourceDigest }])
    "no verified EVM output"
  expectErr "EVM runtime artifact mismatch"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable
      #[{ authority with artifactBytes := "6002\n".toUTF8 }])
    "artifact SHA-256 mismatch"
  expectErr "EVM unused output"
    (verifyEvmBindingOutputsV1 parsedEvmBindTable
      #[authority, { authority with artifactProgramName := "Unused" }])
    "does not match any row"
  expectErr "EVM partial identity"
    (verifyEvmBindingOutputsV1 idTable #[authority])
    "requires identity.semanticHash"
  expectErr "runtime missing LF"
    (decodeEvmRuntimeBytecodeArtifactV1 "6001".toUTF8)
    "end with one LF"
  expectErr "runtime uppercase"
    (decodeEvmRuntimeBytecodeArtifactV1 "60AA\n".toUTF8)
    "lowercase hex"
  expectErr "runtime empty"
    (decodeEvmRuntimeBytecodeArtifactV1 "\n".toUTF8)
    "nonempty"

  -- Bound EVM emit: endpoint + exact runtime hash appear; missing/unverified
  -- rows fail closed. No table keeps the historical hashed-QN stub.
  let session ← Tests.Language.ParserSession.shared
  let callText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallBindEvm where\n" ++
    "  state count : UInt64\n" ++
    "  init(initial : UInt64) do\n" ++
    "    count := initial\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    schedule Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    let observed : UInt64 := call Oracle.feed(count)\n" ++
    "    return observed\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let callSource ← match ← session.selectProgramV1
      callText "<call-bind-evm>" "Tests.CallBindEvm" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindEvm: {e.render}"
  let callCompiled ← match Compiler.compileValidatedSourceV1 callSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindEvm: {e.render}"
  let callSel ← match resolveBuildSelectionV1 TargetId.evm none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"select evm: {e.render}"
  let callCap ← match Targets.resolveEngineeringRequirementsV1 callSel callCompiled with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"resolve CallBindEvm: {e.render}"
  let hashedNeedle :=
    (Targets.Evm.Keccak.keccak256Hex "Oracle".toUTF8).drop 24
  let stubIr ← match Targets.Evm.irFromCapability callCap none with
    | .ok ir => pure ir
    | .error e => throw <| IO.userError s!"ir stub: {e.render}"
  expect (stubIr.yul.contains s!"call(gas(), 0x{hashedNeedle},")
    s!"no-bindings Yul must keep hashed stub 0x{hashedNeedle}"
  expect (stubIr.yul.contains s!"if iszero(extcodesize(0x{hashedNeedle}))")
    "Wave 2a hashed stub void CALL must revert on empty code"
  expect (!stubIr.yul.contains "extcodehash")
    "no-bindings hashed stub must not claim verified runtime identity"
  match Targets.Evm.irFromCapability callCap (some parsedEvmBindTable) with
  | .ok _ => throw <| IO.userError "parse-only EVM table must fail before emit"
  | .error e =>
      expect (hasSubstr e.render "no verified runtime artifact")
        s!"parse-only EVM table must name unverified runtime, got {e.render}"
  let boundIr ← match Targets.Evm.irFromCapability callCap (some evmBindTable) with
    | .ok ir => pure ir
    | .error e => throw <| IO.userError s!"ir bound: {e.render}"
  expect (boundIr.yul.contains
      "call(gas(), 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,")
    "bound Yul must CALL the table address"
  expect (boundIr.yul.contains
      "if iszero(extcodesize(0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa))")
    "Wave 2a bound void CALL must revert on empty code"
  let expectedRuntimeKeccakHex := encodeLowerHexBytesV1 expectedRuntimeKeccak
  let codeHashGuard :=
    s!"if iszero(eq(extcodehash(0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa), 0x{expectedRuntimeKeccakHex})) \{ revert(0, 0) }"
  expect ((boundIr.yul.splitOn codeHashGuard).length == 4)
    "bound Yul must check exact runtime Keccak before void/result/schedule CALL"
  expect (!boundIr.yul.contains s!"call(gas(), 0x{hashedNeedle},")
    "bound Yul must not keep the hashed stub"
  -- Wave 2c: program-level residual. Target inspect stays hashed-qn.
  let evmSemantic := Compiler.CompiledSemanticV1.semanticV1Of callCompiled
  expectResidual "evm none-table" .evm evmSemantic none
    (some "hashed-qn-no-deploy-bind")
  expectResidual "evm bound" .evm evmSemantic (some evmBindTable) none
  let emptyEvm ← expectOk "evm-empty-table" (parseCallBindTableV1 (← liftJcs "empty" (evmDoc #[])))
  expectResidual "evm empty-table" .evm evmSemantic (some emptyEvm)
    (some "hashed-qn-no-deploy-bind")
  match Targets.Evm.irFromCapability callCap (some emptyEvm) with
  | .ok _ => throw <| IO.userError "empty table must fail closed on Oracle.feed"
  | .error e =>
      expect (hasSubstr e.render "no evm row")
        s!"empty table must mention no evm row, got {e.render}"

  -- Wave 2 CosmWasm emit: bound contract_addr; IR keeps QN stub.
  let schedText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallBindCw where\n" ++
    "  state count : UInt64\n" ++
    "  init(x : UInt64) do\n" ++
    "    count := x\n" ++
    "  entry later() : UInt64 do\n" ++
    "    schedule ledger.daily(count)\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return count\n"
  let schedSource ← match ← session.selectProgramV1
      schedText "<call-bind-cw>" "Tests.CallBindCw" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindCw: {e.render}"
  let schedCompiled ← match Compiler.compileValidatedSourceV1 schedSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindCw: {e.render}"
  let schedSel ← match resolveBuildSelectionV1 TargetId.cosmwasm none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"select cw: {e.render}"
  let schedCap ← match Targets.resolveEngineeringRequirementsV1 schedSel schedCompiled with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"resolve CallBindCw: {e.render}"
  let cwPlan ← match Targets.CosmWasm.planFromCapability schedCap with
    | .ok p => pure p
    | .error e => throw <| IO.userError s!"plan CallBindCw: {e.render}"
  let stubFiles ← match Targets.CosmWasm.engineeringFilesFromPlan cwPlan none with
    | .ok fs => pure fs
    | .error e => throw <| IO.userError s!"cw stub files: {e.render}"
  let some stubWat := stubFiles.find? (·.path.endsWith ".wat") |
    throw <| IO.userError "missing stub wat"
  expect (stubWat.contents.contains "\"contract_addr\":\"ledger.daily\"")
    "no-bindings WAT must keep QN stub"
  let cwBindText ← liftJcs "cw-bind-emit"
    (cosmwasmDoc #[cosmwasmBinding "ledger.daily" "bound-contract-addr"])
  let cwBindTable ← expectOk "cw-bind-emit" (parseCallBindTableV1 cwBindText)
  let boundFiles ← match Targets.CosmWasm.engineeringFilesFromPlan cwPlan (some cwBindTable) with
    | .ok fs => pure fs
    | .error e => throw <| IO.userError s!"cw bound files: {e.render}"
  let some boundWat := boundFiles.find? (·.path.endsWith ".wat") |
    throw <| IO.userError "missing bound wat"
  expect (boundWat.contents.contains "\"contract_addr\":\"bound-contract-addr\"")
    "bound WAT must use table contractAddr"
  expect (!boundWat.contents.contains "\"contract_addr\":\"ledger.daily\"")
    "bound WAT must not keep the QN stub as contract_addr"
  let cwSemantic := Compiler.CompiledSemanticV1.semanticV1Of schedCompiled
  expectResidual "cw none-table" .cosmwasm cwSemantic none
    (some "contract-addr-qn-stub")
  expectResidual "cw bound" .cosmwasm cwSemantic (some cwBindTable) none
  let emptyCw ← expectOk "cw-empty-table"
    (parseCallBindTableV1 (← liftJcs "cw-empty" (cosmwasmDoc #[])))
  expectResidual "cw empty-table" .cosmwasm cwSemantic (some emptyCw)
    (some "contract-addr-qn-stub")
  match Targets.CosmWasm.engineeringFilesFromPlan cwPlan (some emptyCw) with
  | .ok _ => throw <| IO.userError "empty CW table must fail closed on ledger.daily"
  | .error e =>
      expect (hasSubstr e.render "no cosmwasm row")
        s!"empty CW table must mention no cosmwasm row, got {e.render}"

  -- Wave 2 Solana: missing row fail closed at product derive; system.transfer
  -- stays catalog-exempt (does not consult the table). Naked sync without
  -- extension.solana-cpi-accounts stays the existing product capability FC.
  let solNakedText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallBindSolNaked where\n" ++
    "  state count : UInt64\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n"
  let solNakedSource ← match ← session.selectProgramV1
      solNakedText "<call-bind-sol-naked>" "Tests.CallBindSolNaked" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindSolNaked: {e.render}"
  let solNakedCompiled ← match Compiler.compileValidatedSourceV1 solNakedSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindSolNaked: {e.render}"
  let solSel ← match resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1) with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"select solana: {e.render}"
  let solNakedCap ← match Targets.resolveEngineeringRequirementsV1 solSel solNakedCompiled with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"resolve CallBindSolNaked: {e.render}"
  match Targets.Solana.buildFromCapability solNakedCap none with
  | .ok _ => throw <| IO.userError "solana naked Oracle.feed without table must stay FC"
  | .error e =>
      expect (e.code == "PF-REQ-UNSUPPORTED")
        s!"solana no-table naked Oracle.feed must PF-REQ-UNSUPPORTED, got {e.render}"
  let solText :=
    "import ProofForgeV2\n\n" ++
    "namespace ProofForgeV2.Examples\n\n" ++
    "open ProofForgeV2.Language\n\n" ++
    "program CallBindSol where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
    "  state count : UInt64\n\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n\n" ++
    "  entry bump(delta : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(count)\n" ++
    "    count := count + delta\n" ++
    "    return count\n\n" ++
    "  view get() : UInt64 do\n" ++
    "    return count\n\n" ++
    "end ProofForgeV2.Examples\n"
  let solSource ← match ← session.selectProgramV1
      solText "<call-bind-sol>" "Examples.CallBindSol" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindSol: {e.render}"
  let solCompiled ← match Compiler.compileValidatedSourceV1 solSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindSol: {e.render}"
  let solCap ← match Targets.resolveEngineeringRequirementsV1 solSel solCompiled with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"resolve CallBindSol: {e.render}"
  match Targets.Solana.buildFromCapability solCap none with
  | .ok _ => throw <| IO.userError "solana Oracle.feed without table must stay FC"
  | .error e =>
      expect (e.code == "PF-PLAN-INVARIANT")
        s!"solana no-table Oracle.feed with extension must PF-PLAN-INVARIANT, got {e.render}"
  let emptySol ← expectOk "sol-empty"
    (parseCallBindTableV1 (← liftJcs "sol-empty" (solanaDoc #[])))
  match Targets.Solana.buildFromCapability solCap (some emptySol) with
  | .ok _ => throw <| IO.userError "empty solana table must fail closed on Oracle.feed"
  | .error e =>
      expect (hasSubstr e.render "no solana row")
        s!"empty solana table must mention no solana row, got {e.render}"
  let solanaArtifact := ByteArray.mk #[0x7f, 0x45, 0x4c, 0x46]
  let solanaArtifactDigest := sha256Bytes solanaArtifact
  let solanaArtifactWire ← digestWire "Solana artifact digest" solanaArtifactDigest
  let solanaAuthority : BindingOutputAuthorityV1 := {
    target := .solana
    deployable := true
    artifactProgramName := "Oracle"
    sourceHash := sourceDigest
    semanticHash := semanticDigest
    artifactSha256 := solanaArtifactDigest
    artifactBytes := solanaArtifact
  }
  let solBindText ← liftJcs "sol-bind"
    (solanaDoc #[solanaBindingWithIdentity "Oracle.feed" ones32
      digest0 digest1 solanaArtifactWire #[]])
  let parsedSolBindTable ← expectOk "sol-bind" (parseCallBindTableV1 solBindText)
  let solBindWithoutIdentityText ← liftJcs "sol-bind-without-identity"
    (solanaDoc #[solanaBinding "Oracle.feed" ones32 #[]])
  let solBindWithoutIdentity ← expectOk "sol-bind-without-identity"
    (parseCallBindTableV1 solBindWithoutIdentityText)
  expectErr "Solana identity required"
    (verifySolanaBindingOutputsV1 solBindWithoutIdentity #[solanaAuthority])
    "requires identity"
  expectErr "Solana output required"
    (verifySolanaBindingOutputsV1 parsedSolBindTable #[])
    "no verified Solana output"
  expectErr "Solana duplicate output"
    (verifySolanaBindingOutputsV1 parsedSolBindTable #[solanaAuthority, solanaAuthority])
    "multiple verified Solana outputs"
  expectErr "Solana source mismatch"
    (verifySolanaBindingOutputsV1 parsedSolBindTable
      #[{ solanaAuthority with sourceHash := semanticDigest }])
    "no verified Solana output"
  expectErr "Solana semantic mismatch"
    (verifySolanaBindingOutputsV1 parsedSolBindTable
      #[{ solanaAuthority with semanticHash := sourceDigest }])
    "no verified Solana output"
  expectErr "Solana wrong-target output"
    (verifySolanaBindingOutputsV1 parsedSolBindTable
      #[{ solanaAuthority with target := .evm }])
    "no verified Solana output"
  expectErr "Solana artifact bytes mismatch"
    (verifySolanaBindingOutputsV1 parsedSolBindTable
      #[{ solanaAuthority with artifactBytes := ByteArray.mk #[0x00] }])
    "Solana artifact SHA-256 mismatch"
  expectErr "Solana unused output"
    (verifySolanaBindingOutputsV1 parsedSolBindTable
      #[solanaAuthority, { solanaAuthority with artifactProgramName := "Unused" }])
    "does not match any row"
  expectErr "parse-only Solana site"
    (requireVerifiedSolanaCallSiteV1 parsedSolBindTable #["Oracle", "feed"])
    "no verified output artifact"
  let solBindTable ← expectOk "verify Solana output"
    (verifySolanaBindingOutputsV1 parsedSolBindTable #[solanaAuthority])
  match requireVerifiedSolanaCallSiteV1 solBindTable #["Oracle", "feed"] with
  | .ok site =>
      expect (site.programId == ByteArray.mk (Array.replicate 32 0x11))
        "verified Solana site keeps exact programId"
      expect (site.outputIdentity.artifactSha256 == solanaArtifactDigest)
        "verified Solana site keeps exact local ELF digest"
  | .error msg => throw <| IO.userError s!"verified Solana site: {msg}"
  let solSemantic := Compiler.CompiledSemanticV1.semanticV1Of solCompiled
  expectResidual "sol none-table" .solana solSemantic none
    (some "callee-identity-outer-account-open")
  expectResidual "sol bound" .solana solSemantic (some solBindTable)
    (some "callee-identity-outer-account-open")
  expectResidual "sol empty-table" .solana solSemantic (some emptySol)
    (some "callee-identity-outer-account-open")
  match Targets.Solana.buildFromCapability solCap (some solBindTable) with
  | .ok files =>
      let some asm := files.find? (·.path.endsWith ".s") |
        throw <| IO.userError "solana bound emit missing .s"
      expect (hasSubstr asm.contents ones32)
        "bound solana asm must contain the table programId"
      expect (hasSubstr asm.contents "empty AccountMeta")
        "empty-accounts bind stays empty-meta"
  | .error e =>
      throw <| IO.userError
        s!"solana bound Oracle.feed must emit, got {e.render}"
  let nonemptyAccText ← liftJcs "sol-nonempty"
    (solanaDoc #[solanaBindingWithIdentity "Oracle.feed" ones32
      digest0 digest1 solanaArtifactWire
      #[solanaAccount "authority" zero32 true true]])
  let parsedNonemptyAccTable ← expectOk "sol-nonempty"
    (parseCallBindTableV1 nonemptyAccText)
  match Targets.Solana.CpiV1.productPlanFromCapabilityV1
      solCap (some parsedNonemptyAccTable) with
  | .ok _ => throw <| IO.userError "parse-only Solana table must fail before Plan derive"
  | .error e =>
      expect (hasSubstr e.render "no verified output artifact")
        s!"parse-only Solana Plan diagnostic, got {e.render}"
  let nonemptyAccTable ← expectOk "verify Solana nonempty output"
    (verifySolanaBindingOutputsV1 parsedNonemptyAccTable #[solanaAuthority])
  expectResidual "sol nonempty bound" .solana solSemantic (some nonemptyAccTable) none
  let callBindPlan ← match Targets.Solana.CpiV1.productPlanFromCapabilityV1
      solCap (some nonemptyAccTable) with
    | .ok plan => pure plan
    | .error e => throw <| IO.userError s!"derive call-bind Plan: {e.render}"
  let callBindCandidate :=
    Targets.Solana.CpiV1.SolanaCpiProductPlanV1.candidateOf callBindPlan
  expect (callBindCandidate.accountRoles.size == 3)
    "call-bind Plan must expose state + bound account + callee program"
  expect callBindCandidate.cpiSites.isEmpty
    "generic call-bind roles must not fabricate a frozen CpiSitePlan"
  match callBindCandidate.accountRoles[0]? with
  | some role =>
      expect (role.roleId == 0 && role.name == "state")
        "call-bind Plan role 0 must remain caller state"
      match role.keyPolicy with
      | .state 0 => pure ()
      | _ => throw <| IO.userError "call-bind Plan role 0 key policy must be state:0"
  | none => throw <| IO.userError "call-bind Plan state role missing"
  match callBindCandidate.accountRoles[1]? with
  | some role =>
      expect (role.roleId == 1 && role.name == "authority")
        "call-bind Plan role 1 must be the bound account"
      match role.keyPolicy with
      | .callBindAccount pubkey signer writable =>
          expect (Targets.Solana.CpiV1.SolanaPubkeyV1.toBytes pubkey ==
              ByteArray.mk (Array.replicate 32 0))
            "call-bind Plan must retain the exact bound account pubkey"
          expect (signer && writable)
            "call-bind Plan key policy must retain bind privileges"
      | _ =>
          throw <| IO.userError "call-bind Plan role 1 must use callBindAccount"
      expect (role.constraint ==
          Targets.Solana.CpiV1.callBindAccountRoleConstraintV1)
        "bound account must forbid executable and not read data"
  | none => throw <| IO.userError "call-bind Plan account role missing"
  match callBindCandidate.accountRoles[2]? with
  | some role =>
      expect (role.roleId == 2 && role.name == "call_bind_Oracle_feed_program")
        "call-bind Plan role 2 must be the callee program"
      match role.keyPolicy with
      | .callBindProgram programId =>
          let actual := Targets.Solana.CpiV1.SolanaPubkeyV1.toBytes programId
          expect (actual == ByteArray.mk (Array.replicate 32 0x11))
            s!"call-bind Plan must retain the exact callee program id, got {repr actual.data}"
      | _ =>
          throw <| IO.userError "call-bind Plan role 2 must use callBindProgram"
      match role.callBindOutputIdentity with
      | some identity =>
          expect (identity.sourceHash == sourceDigest &&
              identity.semanticHash == semanticDigest &&
              identity.artifactSha256 == solanaArtifactDigest)
            "call-bind Plan must retain the exact verified local callee output identity"
      | none =>
          throw <| IO.userError
            "call-bind Plan program role must retain verified output identity"
      expect (role.constraint ==
          Targets.Solana.CpiV1.callBindProgramRoleConstraintV1)
        "callee program role must require executable"
  | none => throw <| IO.userError "call-bind Plan program role missing"
  let callBindPlanText ← match String.fromUTF8?
      (Targets.Solana.CpiV1.SolanaCpiProductPlanV1.canonicalBytesOf callBindPlan) with
    | some value => pure value
    | none => throw <| IO.userError "call-bind Plan canonical bytes must be UTF-8"
  expect (hasSubstr callBindPlanText "callBindOutputIdentity")
    "caller Plan JSON must carry verified local callee output identity"
  expect (hasSubstr callBindPlanText solanaArtifactWire)
    "caller Plan JSON must carry exact local ELF SHA-256"
  for handler in callBindCandidate.handlers do
    expect (handler.accountUses.size == 3)
      s!"call-bind Plan handler '{handler.name}' must expose all three roles"
    expect (handler.accountUses.map (·.roleId) == #[0, 1, 2])
      s!"call-bind Plan handler '{handler.name}' role order"
    match handler.accountUses[1]?, handler.accountUses[2]? with
    | some boundUse, some programUse =>
        expect (boundUse.position == 1 && boundUse.outerSigner &&
            boundUse.outerWritable && boundUse.directSignerContribution &&
            boundUse.directWritableContribution)
          s!"call-bind Plan handler '{handler.name}' bound privilege projection"
        expect (programUse.position == 2 && !programUse.outerSigner &&
            !programUse.outerWritable && !programUse.directSignerContribution &&
            !programUse.directWritableContribution)
          s!"call-bind Plan handler '{handler.name}' program privilege projection"
    | _, _ => throw <| IO.userError "call-bind Plan handler role suffix missing"
  let callBindIdl ← match Targets.Solana.CpiV1.deriveSolanaCpiIdlV1
      (Targets.Solana.CpiV1.SolanaCpiProductPlanV1.planOf callBindPlan) with
    | .ok idl => pure idl
    | .error e => throw <| IO.userError s!"derive call-bind IDL: {e.render}"
  expect callBindIdl.candidate.cpiSites.isEmpty
    "call-bind IDL must not fabricate a frozen CPI site"
  expect (callBindIdl.candidate.instructions.size == callBindCandidate.handlers.size)
    "call-bind IDL instruction count must equal Plan handler count"
  for (instruction, handler) in
      callBindIdl.candidate.instructions.zip callBindCandidate.handlers do
    expect (instruction.accounts.size == 3)
      s!"call-bind IDL instruction '{instruction.name}' must expose three accounts"
    for i in [0:instruction.accounts.size] do
      match instruction.accounts[i]?, handler.accountUses[i]?,
          callBindCandidate.accountRoles[i]? with
      | some account, some use, some role =>
          expect (account.position == i && account.roleId == i &&
              account.name == role.name && account.keyPolicy == role.keyPolicy &&
              account.constraint == role.constraint &&
              account.outerSigner == use.outerSigner &&
              account.outerWritable == use.outerWritable &&
              account.directSignerContribution == use.directSignerContribution &&
              account.directWritableContribution == use.directWritableContribution)
            s!"call-bind IDL instruction '{instruction.name}' account {i} must equal Plan projection"
      | _, _, _ => throw <| IO.userError "call-bind IDL/Plan role projection missing"
  match Targets.Solana.buildFromCapability solCap (some nonemptyAccTable) with
  | .ok files =>
      let some asm := files.find? (·.path.endsWith ".s") |
        throw <| IO.userError "solana Wave 3 emit missing .s"
      expect (hasSubstr asm.contents ones32)
        "Wave 3 asm must still contain the table programId"
      expect (hasSubstr asm.contents "Wave 2b compile-time AccountMeta n=1")
        "Wave 3 must retain compile-time AccountMeta"
      expect (hasSubstr asm.contents "lddw r1, 0x101\n")
        "Wave 2b writable+signer flags pack as 0x101"
      expect (hasSubstr asm.contents "lddw r1, 0x1\n")
        "Wave 2b accounts_len=1 packs as 0x1"
      expect (hasSubstr asm.contents "call-bind outer AccountInfo join")
        "Wave 3 must name the outer AccountInfo join"
      expect (hasSubstr asm.contents
          "call-bind account role 'authority' local=1 exact pubkey signer=1 writable=1")
        "Wave 3 must preflight authority key and exact privileges"
      expect (hasSubstr asm.contents
          "call-bind callee program local=2 exact program id executable=1")
        "Wave 3 must preflight the executable callee program identity"
      expect (hasSubstr asm.contents
          "ROLE_FLAGS (signer|writable<<8|executable<<16)")
        "multi-role walker must preserve executable for AccountInfo packing"
      expect (hasSubstr asm.contents "ROLE_RENT")
        "multi-role walker must preserve rent epoch for AccountInfo packing"
      expect (hasSubstr asm.contents "call-bind AccountInfos startLocal=1 n=2")
        "Wave 3 must pack one meta account plus the callee program AccountInfo"
      expect (hasSubstr asm.contents "lddw r3, 2")
        "Wave 3 must pass AccountInfo len rows+program=2"
      expect (hasSubstr asm.contents "jne r0, 0, cpi_failed_mr")
        "Wave 3 must propagate CPI failure"
      expect (hasSubstr asm.contents "jne r1, r3, call_bind_check_failed_")
        "Wave 3 exact role mismatch must use the local check-failure exit"
      expect (hasSubstr asm.contents "call_bind_checks_ok_")
        "Wave 3 successful role checks must branch around Custom(1)"
      expect (!hasSubstr asm.contents "empty AccountMeta")
        "Wave 2b nonempty accounts must not keep empty-meta comment"
      let some marker := files.find? (·.path.endsWith ".cpi-ir.json") |
        throw <| IO.userError "solana Wave 3 emit missing cpi-ir"
      expect (hasSubstr marker.contents "call-bind-outer-account-join")
        s!"Wave 3 marker must name call-bind join, got {marker.contents}"
      expect (hasSubstr marker.contents "\"outerRoleCount\":3")
        s!"Wave 3 marker must expose state+account+program roles, got {marker.contents}"
  | .error e =>
      throw <| IO.userError
        s!"solana Wave 3 Oracle.feed must emit, got {e.render}"
  let aa32 := String.ofList (List.replicate 64 'a')
  let bb32 := String.ofList (List.replicate 64 'b')
  let twoAccText ← liftJcs "sol-two-acc"
    (solanaDoc #[solanaBindingWithIdentity "Oracle.feed" ones32
      digest0 digest1 solanaArtifactWire
      #[solanaAccount "authority" aa32 true true,
        solanaAccount "vault" bb32 false true]])
  let parsedTwoAccTable ← expectOk "sol-two-acc" (parseCallBindTableV1 twoAccText)
  let twoAccTable ← expectOk "verify Solana two-account output"
    (verifySolanaBindingOutputsV1 parsedTwoAccTable #[solanaAuthority])
  match Targets.Solana.buildFromCapability solCap (some twoAccTable) with
  | .ok files =>
      let some asm := files.find? (·.path.endsWith ".s") |
        throw <| IO.userError "solana Wave 2b two-account emit missing .s"
      expect (hasSubstr asm.contents "Wave 2b compile-time AccountMeta n=2")
        "Wave 2b two-account asm must name n=2"
      -- Reverse-pack emits acc0 then acc1; flags 0x101 then 0x1.
      expect (hasSubstr asm.contents "lddw r1, 0x101\n")
        "acc0 writable+signer packs as 0x101"
      expect (hasSubstr asm.contents "lddw r1, 0x1\n")
        "acc1 writable-only packs as 0x1"
      expect (hasSubstr asm.contents "lddw r1, 0x2\n")
        "Wave 2b accounts_len=2 packs as 0x2"
      expect (hasSubstr asm.contents "lddw r1, 0xaaaaaaaaaaaaaaaa")
        "acc0 pubkey limbs must appear"
      expect (hasSubstr asm.contents "lddw r1, 0xbbbbbbbbbbbbbbbb")
        "acc1 pubkey limbs must appear"
      expect (hasSubstr asm.contents
          "call-bind account role 'authority' local=1 exact pubkey signer=1 writable=1")
        "acc0 runtime role contract must be exact"
      expect (hasSubstr asm.contents
          "call-bind account role 'vault' local=2 exact pubkey signer=0 writable=1")
        "acc1 runtime role contract must distinguish writable from signer"
      expect (hasSubstr asm.contents
          "call-bind callee program local=3 exact program id executable=1")
        "callee program must follow bound account rows"
      expect (hasSubstr asm.contents "call-bind AccountInfos startLocal=1 n=3")
        "two account rows require rows+program AccountInfos"
      expect (hasSubstr asm.contents "lddw r3, 3")
        "two account rows must pass AccountInfo len 3"
      let some before101 := (asm.contents.splitOn "lddw r1, 0x101\n")[0]? |
        throw <| IO.userError "missing 0x101 split"
      expect (!hasSubstr before101 "lddw r1, 0x1\n")
        "acc0 flags (0x101) must appear before acc1 flags (0x1)"
      let some beforeAa := (asm.contents.splitOn "lddw r1, 0xaaaaaaaaaaaaaaaa")[0]? |
        throw <| IO.userError "missing aa pubkey split"
      expect (!hasSubstr beforeAa "lddw r1, 0xbbbbbbbbbbbbbbbb")
        "acc0 pubkey must appear before acc1 pubkey"
  | .error e =>
      throw <| IO.userError
        s!"solana Wave 2b two-account Oracle.feed must emit, got {e.render}"
  let duplicatePubkeyText ← liftJcs "sol-duplicate-pubkey"
    (solanaDoc #[solanaBindingWithIdentity "Oracle.feed" ones32
      digest0 digest1 solanaArtifactWire
      #[solanaAccount "authority" aa32 true false,
        solanaAccount "vault" aa32 false true]])
  let parsedDuplicatePubkeyTable ← expectOk "sol-duplicate-pubkey"
    (parseCallBindTableV1 duplicatePubkeyText)
  let duplicatePubkeyTable ← expectOk "verify Solana duplicate-pubkey output"
    (verifySolanaBindingOutputsV1 parsedDuplicatePubkeyTable #[solanaAuthority])
  match Targets.Solana.buildFromCapability solCap (some duplicatePubkeyTable) with
  | .ok _ => throw <| IO.userError "duplicate outer account pubkeys must fail closed"
  | .error e =>
      expect (hasSubstr e.render "distinct account pubkeys")
        s!"duplicate outer account pubkeys diagnostic, got {e.render}"
  let programAsAccountText ← liftJcs "sol-program-as-account"
    (solanaDoc #[solanaBindingWithIdentity "Oracle.feed" ones32
      digest0 digest1 solanaArtifactWire
      #[solanaAccount "callee" ones32 false false]])
  let parsedProgramAsAccountTable ← expectOk "sol-program-as-account"
    (parseCallBindTableV1 programAsAccountText)
  let programAsAccountTable ← expectOk "verify Solana program-as-account output"
    (verifySolanaBindingOutputsV1 parsedProgramAsAccountTable #[solanaAuthority])
  match Targets.Solana.buildFromCapability solCap (some programAsAccountTable) with
  | .ok _ => throw <| IO.userError "callee program/account identity alias must fail closed"
  | .error e =>
      expect (hasSubstr e.render "distinct from programId")
        s!"callee program/account alias diagnostic, got {e.render}"
  let tooMany : Array PfJson :=
    (Array.range 9).map (fun i =>
      solanaAccount s!"role{i}" zero32 false false)
  let tooManyText ← liftJcs "sol-too-many"
    (solanaDoc #[solanaBindingWithIdentity "Oracle.feed" ones32
      digest0 digest1 solanaArtifactWire tooMany])
  let parsedTooManyTable ← expectOk "sol-too-many" (parseCallBindTableV1 tooManyText)
  let tooManyTable ← expectOk "verify Solana too-many output"
    (verifySolanaBindingOutputsV1 parsedTooManyTable #[solanaAuthority])
  match Targets.Solana.buildFromCapability solCap (some tooManyTable) with
  | .ok _ => throw <| IO.userError "9 AccountMetas must fail closed"
  | .error e =>
      expect (hasSubstr e.render "at most 8 AccountMetas")
        s!"9 AccountMetas must mention cap, got {e.render}"

  -- Wave 3 residual honesty: schedule has no synchronous AccountInfo join;
  -- frozen system.transfer is not a generic call-bind callee.
  let solScheduleText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallBindSolSchedule where\n" ++
    "  state count : UInt64\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n" ++
    "  entry later() : UInt64 do\n" ++
    "    schedule Oracle.feed(count)\n" ++
    "    return count\n"
  let solScheduleSource ← match ← session.selectProgramV1
      solScheduleText "<call-bind-sol-schedule>" "Tests.CallBindSolSchedule" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindSolSchedule: {e.render}"
  let solScheduleCompiled ← match Compiler.compileValidatedSourceV1 solScheduleSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindSolSchedule: {e.render}"
  expectResidual "sol scheduled nonempty bound" .solana
    (Compiler.CompiledSemanticV1.semanticV1Of solScheduleCompiled)
    (some nonemptyAccTable) (some "callee-identity-outer-account-open")

  let solSystemText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallBindSolSystem where\n" ++
    "  requires extension solana.cpi.accounts version \"1.0.0\"\n" ++
    "    digest \"sha256:df7d513d3d8b6324755a91d359c4d543a4432f87c78a0795d44b8bc7361b4020\"\n" ++
    "  state count : UInt64\n" ++
    "  init(i : UInt64) do\n" ++
    "    count := i\n" ++
    "  entry pay(payer : Principal, recipient : Principal, amount : UInt64) : UInt64 do\n" ++
    "    call solana.system.transfer(payer, recipient, amount)\n" ++
    "    return count\n"
  let solSystemSource ← match ← session.selectProgramV1
      solSystemText "<call-bind-sol-system>" "Tests.CallBindSolSystem" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindSolSystem: {e.render}"
  let solSystemCompiled ← match Compiler.compileValidatedSourceV1 solSystemSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindSolSystem: {e.render}"
  let solSystemSemantic := Compiler.CompiledSemanticV1.semanticV1Of solSystemCompiled
  expectResidual "sol system no table" .solana solSystemSemantic none none
  expectResidual "sol system unrelated table" .solana solSystemSemantic
    (some nonemptyAccTable) none
  let solSystemCap ← match
      Targets.resolveEngineeringRequirementsV1 solSel solSystemCompiled with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"resolve CallBindSolSystem: {e.render}"
  match Targets.Solana.buildFromCapability solSystemCap (some nonemptyAccTable) with
  | .ok files =>
      let some asm := files.find? (·.path.endsWith ".s") |
        throw <| IO.userError "Solana system build with unrelated bind table missing .s"
      expect (hasSubstr asm.contents "system.transfer")
        "frozen system.transfer must remain on its specialized rail"
      expect (!hasSubstr asm.contents "product_external_call_bind_join")
        "frozen system.transfer must not activate generic call-bind join"
  | .error e =>
      throw <| IO.userError
        s!"frozen system.transfer must ignore unrelated bind rows, got {e.render}"

  -- Wave 2c: no generic call/schedule → program-level residual none.
  let plainText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program CallBindPlain where\n" ++
    "  state count : UInt64\n" ++
    "  init(x : UInt64) do\n" ++
    "    count := x\n" ++
    "  entry bump() : UInt64 do\n" ++
    "    count := count + 1\n" ++
    "    return count\n" ++
    "  view peek() : UInt64 do\n" ++
    "    return count\n"
  let plainSource ← match ← session.selectProgramV1
      plainText "<call-bind-plain>" "Tests.CallBindPlain" none with
    | .ok s => pure s
    | .error e => throw <| IO.userError s!"load CallBindPlain: {e.render}"
  let plainCompiled ← match Compiler.compileValidatedSourceV1 plainSource with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"compile CallBindPlain: {e.render}"
  let plainSemantic := Compiler.CompiledSemanticV1.semanticV1Of plainCompiled
  expectResidual "plain evm" .evm plainSemantic none none
  expectResidual "plain solana" .solana plainSemantic none none
  expectResidual "plain cosmwasm" .cosmwasm plainSemantic none none

  IO.println "Tests.Materialization.CallBindV1: ok"

end Tests.Materialization.CallBindV1
