/-
  Tests.Materialization.CallBindV1 — ADR-0053 Wave 1 parser + Wave 2 emit.

  Pure parse of `proof-forge.call-bind.v1`, `--bindings` preflight, and
  three-leaf emit consume (missing row fail closed; bound address appears
  in Yul / WAT). Not formal / C-3. Not Wave 2a empty-account CALL.
-/
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.CallBindV1
import ProofForgeV2.Targets.Registry
import Tests.Language.ParserSession

namespace Tests.Materialization.CallBindV1

open ProofForgeV2
open ProofForgeV2.CLI
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets
open ProofForgeV2.Targets.BuildSelectionV1
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

  -- Wave 2 lookup helpers (table row is Oracle.quote).
  let quoteQn ← expectOk "quote qn 2" (parseQualifiedName #["Oracle", "quote"])
  match requireEvmAddressV1 evmTable quoteQn.components.toArray with
  | .ok bytes => expect (bytes.size == 20) "requireEvm 20 bytes"
  | .error msg => throw <| IO.userError s!"requireEvm Oracle.quote: {msg}"
  expectErr "requireEvm missing"
    (requireEvmAddressV1 evmTable
      (← expectOk "missing2" (parseQualifiedName #["Oracle", "missing"])).components.toArray)
    "no evm row"
  -- Wave 2b: nonempty Solana accounts parse, but lookup fail-closes.
  expectErr "requireSol nonempty accounts"
    (requireSolanaProgramIdV1 solTable
      (← expectOk "vault qn" (parseQualifiedName #["Vault", "deposit"])).components.toArray)
    "accounts binding is not admitted"

  -- Wave 2 EVM emit: bound address appears; missing row fail closed;
  -- no table keeps hashed stub.
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
    "    count := count + delta\n" ++
    "    return count\n" ++
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
  let boundAddr := "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let evmBindText ← liftJcs "evm-bind-emit"
    (evmDoc #[evmBinding "Oracle.feed" boundAddr])
  let evmBindTable ← expectOk "evm-bind-emit"
    (parseCallBindTableV1 evmBindText)
  let boundIr ← match Targets.Evm.irFromCapability callCap (some evmBindTable) with
    | .ok ir => pure ir
    | .error e => throw <| IO.userError s!"ir bound: {e.render}"
  expect (boundIr.yul.contains
      "call(gas(), 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,")
    "bound Yul must CALL the table address"
  expect (!boundIr.yul.contains s!"call(gas(), 0x{hashedNeedle},")
    "bound Yul must not keep the hashed stub"
  let emptyEvm ← expectOk "evm-empty-table" (parseCallBindTableV1 (← liftJcs "empty" (evmDoc #[])))
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
  let emptyCw ← expectOk "cw-empty-table"
    (parseCallBindTableV1 (← liftJcs "cw-empty" (cosmwasmDoc #[])))
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
  let solBindText ← liftJcs "sol-bind"
    (solanaDoc #[solanaBinding "Oracle.feed" ones32 #[]])
  let solBindTable ← expectOk "sol-bind" (parseCallBindTableV1 solBindText)
  match Targets.Solana.buildFromCapability solCap (some solBindTable) with
  | .ok files =>
      let some asm := files.find? (·.path.endsWith ".s") |
        throw <| IO.userError "solana bound emit missing .s"
      expect (hasSubstr asm.contents ones32)
        "bound solana asm must contain the table programId"
  | .error e =>
      throw <| IO.userError
        s!"solana bound Oracle.feed must emit, got {e.render}"
  let nonemptyAccText ← liftJcs "sol-nonempty"
    (solanaDoc #[solanaBinding "Oracle.feed" ones32
      #[solanaAccount "authority" zero32 false false]])
  let nonemptyAccTable ← expectOk "sol-nonempty" (parseCallBindTableV1 nonemptyAccText)
  match Targets.Solana.buildFromCapability solCap (some nonemptyAccTable) with
  | .ok _ => throw <| IO.userError "nonempty solana accounts must fail closed in Wave 2"
  | .error e =>
      expect (hasSubstr e.render "accounts binding is not admitted")
        s!"nonempty accounts must mention Wave 2b, got {e.render}"

  IO.println "Tests.Materialization.CallBindV1: ok"

end Tests.Materialization.CallBindV1
