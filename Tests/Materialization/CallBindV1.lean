/-
  Tests.Materialization.CallBindV1 — ADR-0053 Wave 1 parser + CLI flags.

  Pure parse of `proof-forge.call-bind.v1` and `--bindings` preflight.
  Does not change EVM / Solana / CosmWasm emit. Not formal / C-3.
-/
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.CallBindV1

namespace Tests.Materialization.CallBindV1

open ProofForgeV2
open ProofForgeV2.CLI
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.CallBindV1

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
private def zero32 : String := String.ofList (List.replicate 64 '0')
private def ones32 : String := String.ofList (List.replicate 64 '1')
private def digest0 : String := "sha256:" ++ String.ofList (List.replicate 64 '0')

private def expectBuildOpts (label : String) (args : List String) : IO BuildOptions :=
  expectOk label (parseBuildArgsExcept args)

def run : IO Unit := do
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

  IO.println "Tests.Materialization.CallBindV1: ok"

end Tests.Materialization.CallBindV1
