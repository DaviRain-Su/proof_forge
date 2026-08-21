/-
  Tests.Materialization.CallBindV1 — ADR-0053 parser, CLI, and EVM Wave 2.

  Pure parse of `proof-forge.call-bind.v1`, `--bindings` preflight, and the EVM
  Plan/digest/Yul/product-materialization binding path. Solana/CosmWasm remain
  parse-only. Not formal / C-3.
-/
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.CallBindV1
import ProofForgeV2.Targets.Evm.PlanSchemaV1
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.CallBindV1

open ProofForgeV2
open ProofForgeV2.CLI
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.CallBindV1
open ProofForgeV2.Targets.BuildSelectionV1

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

private def evmBinding (callee address : String) : PfJson :=
  .object #[("address", .string address), ("callee", .string callee)]

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
private def twos20 : String := "0x" ++ String.ofList (List.replicate 40 '2')
private def zero32 : String := String.ofList (List.replicate 64 '0')
private def ones32 : String := String.ofList (List.replicate 64 '1')
private def digest0 : String := "sha256:" ++ String.ofList (List.replicate 64 '0')

private def expectBuildOpts (label : String) (args : List String) : IO BuildOptions :=
  expectOk label (parseBuildArgsExcept args)

private def liftCompile (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

/-- Wave 2 EVM leaf: exact table addresses live in Plan identity and emitted
    Yul; omission preserves the historical QN-derived address; a present table
    with a missing row fails closed. -/
private unsafe def testEvmWave2Materialization : IO Unit := do
  let sourceText :=
    "import ProofForgeV2\n" ++
    "open ProofForgeV2.Language\n" ++
    "program BoundCallEvm where\n" ++
    "  entry probe(k : UInt64) : UInt64 do\n" ++
    "    call Oracle.feed(k)\n" ++
    "    let x : UInt64 := call Oracle.quote(k)\n" ++
    "    return x\n" ++
    "  entry later(k : UInt64) : UInt64 do\n" ++
    "    schedule Ledger.daily(k)\n" ++
    "    return k\n"
  let session ← Tests.Language.ParserSession.shared
  let source ← liftCompile "call-bind EVM source" (← session.selectProgramV1
    sourceText "<call-bind-evm-wave2>" "Tests.CallBindEvmWave2" none)
  let compiled ← liftCompile "call-bind EVM compile" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftCompile "call-bind EVM selection" <|
    resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftCompile "call-bind EVM capability" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled

  let tableText ← liftJcs "call-bind EVM Wave 2 table" <| evmDoc #[
    evmBinding "Oracle.feed" zero20,
    evmBinding "Oracle.quote" ones20,
    evmBinding "Ledger.daily" twos20]
  let table ← expectOk "call-bind EVM Wave 2 table" <|
    parseCallBindTableV1 tableText
  let feedAddress ← expectOk "feed address" <|
    decodeLowerHexBytesV1 zero20 20 true "feed address"
  let quoteAddress ← expectOk "quote address" <|
    decodeLowerHexBytesV1 ones20 20 true "quote address"
  let ledgerAddress ← expectOk "ledger address" <|
    decodeLowerHexBytesV1 twos20 20 true "ledger address"

  let unboundPlan ← liftCompile "unbound EVM plan" <|
    Targets.Evm.planFromCapability capability
  let boundPlan ← liftCompile "bound EVM plan" <|
    Targets.Evm.planFromCapability capability (some table)
  let boundPlanAgain ← liftCompile "bound EVM plan repeat" <|
    Targets.Evm.planFromCapability capability (some table)
  expect (unboundPlan.entries.all fun e => e.body.all fun stmt =>
      match stmt with
      | .externalCall _ _ _ none | .externalCallResult _ _ _ none |
          .schedule _ _ _ none => true
      | .externalCall .. | .externalCallResult .. | .schedule .. => false
      | _ => true)
    "omitted EVM bindings must retain unbound Plan statements"
  expect (boundPlan.entries.any fun e => e.body.any fun stmt =>
      match stmt with
      | .externalCall #["Oracle", "feed"] _ _ (some address) =>
          address == feedAddress
      | _ => false)
    "EVM void call Plan must carry the exact bound address"
  expect (boundPlan.entries.any fun e => e.body.any fun stmt =>
      match stmt with
      | .externalCallResult #["Oracle", "quote"] _ _ (some address) =>
          address == quoteAddress
      | _ => false)
    "EVM result call Plan must carry the exact bound address"
  expect (boundPlan.entries.any fun e => e.body.any fun stmt =>
      match stmt with
      | .schedule #["Ledger", "daily"] _ _ (some address) =>
          address == ledgerAddress
      | _ => false)
    "EVM schedule Plan must carry the exact bound address"

  let unboundBytes ← expectOk "unbound EVM Plan bytes" <|
    Targets.Evm.encodeEngineeringEvmPlanBytesV1 unboundPlan
  let boundBytes ← expectOk "bound EVM Plan bytes" <|
    Targets.Evm.encodeEngineeringEvmPlanBytesV1 boundPlan
  let boundBytesAgain ← expectOk "bound EVM Plan bytes repeat" <|
    Targets.Evm.encodeEngineeringEvmPlanBytesV1 boundPlanAgain
  expect (!(unboundBytes == boundBytes))
    "bound and unbound EVM Plans must have distinct identity bytes"
  expect (boundBytes == boundBytesAgain)
    "the same EVM bind table must produce deterministic Plan bytes"
  let unboundDigest ← expectOk "unbound EVM Plan digest" <|
    Targets.Evm.engineeringEvmPlanDigestV1 unboundPlan
  let boundDigest ← expectOk "bound EVM Plan digest" <|
    Targets.Evm.engineeringEvmPlanDigestV1 boundPlan
  expect (!(unboundDigest.bytes == boundDigest.bytes))
    "bound and unbound EVM Plan digests must differ"

  let unboundIr ← liftCompile "unbound EVM IR" <|
    Targets.Evm.irFromCapability capability
  let boundIr ← liftCompile "bound EVM IR" <|
    Targets.Evm.irFromCapability capability (some table)
  let oracleHistorical :=
    ((Targets.Evm.Keccak.keccak256Hex "Oracle".toUTF8).drop 24).toString
  let ledgerHistorical :=
    ((Targets.Evm.Keccak.keccak256Hex "Ledger".toUTF8).drop 24).toString
  expect (unboundIr.yul.contains s!"call(gas(), 0x{oracleHistorical}," &&
      unboundIr.yul.contains s!"call(gas(), 0x{ledgerHistorical},")
    "omitted EVM bindings must preserve historical QN-derived CALL addresses"
  for exact in [zero20.drop 2, ones20.drop 2, twos20.drop 2] do
    expect (boundIr.yul.contains s!"call(gas(), 0x{exact},")
      s!"bound EVM Yul must use exact address 0x{exact}"

  -- Registry must use the same bound Plan for both emitted bytes and the
  -- EngineeringBuildIdentity plan-digest slot.
  let unboundArtifacts ← liftCompile "unbound EVM artifacts" <|
    Targets.materializeResult capability
  let boundArtifacts ← liftCompile "bound EVM artifacts" <|
    Targets.materializeResult capability (some table)
  let unboundIdentity := MaterializedArtifactsV1.buildIdentityOf unboundArtifacts
  let boundIdentity := MaterializedArtifactsV1.buildIdentityOf boundArtifacts
  expect (!(ProofForgeV2.Targets.EngineeringBuildIdentityV1.EngineeringBuildIdentityV1.planDigestOf
        unboundIdentity ==
      ProofForgeV2.Targets.EngineeringBuildIdentityV1.EngineeringBuildIdentityV1.planDigestOf
        boundIdentity))
    "EVM binding must change the materialized build identity plan digest"
  let some boundYul := (MaterializedArtifactsV1.filesOf boundArtifacts).find?
      (·.path == "BoundCallEvm.yul") |
    throw <| IO.userError "bound EVM Registry output is missing Yul"
  expect (boundYul.contents == boundIr.yul)
    "Registry EVM output and bound IR must use the same Plan binding"

  let emptyTable := CallBindTableV1.empty .evm
  match Targets.Evm.planFromCapability capability (some emptyTable) with
  | .error error =>
      expect (error.code == "PF-PLAN-INVARIANT" &&
          hasSubstr error.message "call-bind: no evm row for callee 'Oracle.feed'")
        s!"missing EVM binding row must fail closed, got {error.render}"
  | .ok _ => throw <| IO.userError "present EVM bind table accepted a missing callee row"

  -- Parser normally prevents this, but Plan validation independently rejects
  -- a malformed direct Plan constructor.
  let malformedPlan := {
    unboundPlan with
    entries := unboundPlan.entries.map fun e => {
      e with body := e.body.map fun stmt =>
        match stmt with
        | .externalCall callee args widths _ =>
            .externalCall callee args widths (some ByteArray.empty)
        | other => other }
  }
  match Targets.Evm.validatePlan malformedPlan with
  | .error error =>
      expect (hasSubstr error.message "bound EVM external call address must be exactly 20 bytes")
        s!"malformed bound EVM Plan address diagnostic, got {error.render}"
  | .ok _ => throw <| IO.userError "EVM Plan accepted a malformed bound address"

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
      "--bindings", "testdata/call-bind/evm.v1.json"]
  expect (withFlag.bindings == some "testdata/call-bind/evm.v1.json") "bindings path"
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
          "--target", "evm", "--bindings", "a.json"]) with
  | .build opts =>
      expect (opts.bindings == some "a.json") "product build keeps path"
  | other => throw <| IO.userError s!"expected build command, got {repr other}"

  testEvmWave2Materialization

  IO.println "Tests.Materialization.CallBindV1: ok"

end Tests.Materialization.CallBindV1
